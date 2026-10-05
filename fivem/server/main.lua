math.randomseed(os.time())

-- These are loaded by fxmanifest.lua before this file. An fxmanifest.lua kept from an older version doesn't list
-- them, which crashed here with "attempt to index a nil value (field 'Legacy' / 'Objects')". Say so clearly and
-- keep the trading cards working; coins and plushies stay off until the manifest is updated.
do
    local missing = {}
    if not MetaComic.Legacy then missing[#missing + 1] = 'shared/legacy.lua' end
    if not MetaComic.Collectables then missing[#missing + 1] = 'shared/collectables.lua' end
    if not MetaComic.Objects then missing[#missing + 1] = 'server/modules/objects.lua' end
    if #missing > 0 then
        print(('^1[meta-comic] fxmanifest.lua is out of date: %s %s not loaded. Replace fxmanifest.lua with the one from this version (keep your config.lua) and restart the resource.^7')
            :format(table.concat(missing, ', '), #missing == 1 and 'is' or 'are'))
    end
    MetaComic.Legacy = MetaComic.Legacy or {
        prefsKey = 'rush_cards:pack_prefs', uploadConvar = 'rushcards_fivemanage_key',
        manageAce = 'rushcards.manage', catalogAce = 'rushcards.catalog.write',
        fallbackIcon = function(value) return value end,
    }
    MetaComic.Collectables = MetaComic.Collectables or { snapshot = function(typeId, item) local copy = MetaComic.CopyTable(item); copy.collectableType = typeId; return copy end }
end
local function objectTypes() return MetaComic.Objects and MetaComic.Objects.types or {} end
-- (declared up here: printKey / iconCard further down use them) coins and plushies share the card icon pipeline: one icon per definition + print
local OBJECT_ICON_PREFIX = { challenge_coin = 'metacoin', plushie = 'metaplush' }
local function objectType(card) return type(card) == 'table' and OBJECT_ICON_PREFIX[card.collectableType] and card.collectableType or nil end
local function keyType(key) return type(key) == 'string' and key:match('^obj::([%w_]+)::') or 'trading_card' end

local function fail(message)
    return { ok = false, error = message }
end

-- Remote artwork/mask resolver -------------------------------------------------
-- Browser CSS masks and canvas pixel reads require CORS approval. Normal <img>
-- tags do not, which is why a CDN image can display while the same URL silently
-- fails as a subject mask. Fetching on the FiveM server removes browser CORS from
-- the equation; the NUI receives a data URL that is safe for CSS masks/canvas.
local REMOTE_ASSET_MAX_BYTES = 12 * 1024 * 1024
local REMOTE_ASSET_CACHE_BYTES = 48 * 1024 * 1024
local remoteAssetCache, remoteAssetCacheBytes, remoteAssetTick = {}, 0, 0
local base64Alphabet = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/'

local function base64Encode(data)
    local out = {}
    local len = #data
    local j = 1
    for i = 1, len, 3 do
        local a = data:byte(i) or 0
        local b = data:byte(i + 1) or 0
        local c = data:byte(i + 2) or 0
        local n = (a << 16) | (b << 8) | c
        out[j] = base64Alphabet:sub(((n >> 18) & 63) + 1, ((n >> 18) & 63) + 1); j = j + 1
        out[j] = base64Alphabet:sub(((n >> 12) & 63) + 1, ((n >> 12) & 63) + 1); j = j + 1
        out[j] = i + 1 <= len and base64Alphabet:sub(((n >> 6) & 63) + 1, ((n >> 6) & 63) + 1) or '='; j = j + 1
        out[j] = i + 2 <= len and base64Alphabet:sub((n & 63) + 1, (n & 63) + 1) or '='; j = j + 1
    end
    return table.concat(out)
end

local function remoteAssetHostAllowed(url)
    if type(url) ~= 'string' or #url < 8 or #url > 4096 then return false, 'INVALID_URL' end
    if not url:match('^https?://') then return false, 'INVALID_URL' end
    local authority = url:match('^https?://([^/%?#]+)')
    if not authority then return false, 'INVALID_URL' end
    local host = authority:gsub('^.-@', ''):gsub(':%d+$', ''):lower()
    if host == 'localhost' or host == '0.0.0.0' or host == '::1' or host:match('%.local$') then return false, 'BLOCKED_HOST' end
    if host:match('^127%.') or host:match('^10%.') or host:match('^192%.168%.') or host:match('^169%.254%.') then return false, 'BLOCKED_HOST' end
    local a, b = host:match('^(172)%.(%d+)%.')
    if a and tonumber(b) and tonumber(b) >= 16 and tonumber(b) <= 31 then return false, 'BLOCKED_HOST' end
    return true
end

local function sniffRemoteImageType(body)
    if type(body) ~= 'string' or #body < 4 then return nil end
    local b1, b2, b3, b4 = body:byte(1, 4)
    if b1 == 0x89 and b2 == 0x50 and b3 == 0x4E and b4 == 0x47 then return 'image/png' end
    if b1 == 0xFF and b2 == 0xD8 and b3 == 0xFF then return 'image/jpeg' end
    if body:sub(1, 6) == 'GIF87a' or body:sub(1, 6) == 'GIF89a' then return 'image/gif' end
    if body:sub(1, 4) == 'RIFF' and body:sub(9, 12) == 'WEBP' then return 'image/webp' end
    if #body >= 12 and body:sub(5, 8) == 'ftyp' and (body:sub(9, 12) == 'avif' or body:sub(9, 12) == 'avis') then return 'image/avif' end
    return nil
end

local function remoteAssetContentType(headers, url, body)
    local headerType
    if type(headers) == 'table' then
        for key, value in pairs(headers) do
            if tostring(key):lower() == 'content-type' then
                headerType = tostring(value):match('^%s*([^;]+)')
                if headerType then headerType = headerType:lower() end
                break
            end
        end
    end
    if headerType and headerType:match('^image/') then return headerType end

    -- Some CDNs return application/octet-stream (or omit Content-Type entirely).
    -- Prefer byte signatures so data: URLs handed to Chromium still have a real
    -- image MIME type and remain usable by CSS masks and canvas reads.
    local sniffed = sniffRemoteImageType(body)
    if sniffed then return sniffed end

    local clean = tostring(url or ''):lower():match('^[^?#]+') or ''
    if clean:match('%.png$') then return 'image/png' end
    if clean:match('%.jpe?g$') then return 'image/jpeg' end
    if clean:match('%.webp$') then return 'image/webp' end
    if clean:match('%.gif$') then return 'image/gif' end
    if clean:match('%.avif$') then return 'image/avif' end
    return headerType or 'application/octet-stream'
end

local function cacheRemoteAsset(url, dataUrl, contentType, bytes)
    remoteAssetTick = remoteAssetTick + 1
    local old = remoteAssetCache[url]
    if old then remoteAssetCacheBytes = remoteAssetCacheBytes - (old.bytes or 0) end
    remoteAssetCache[url] = { dataUrl = dataUrl, contentType = contentType, bytes = bytes, tick = remoteAssetTick }
    remoteAssetCacheBytes = remoteAssetCacheBytes + bytes

    while remoteAssetCacheBytes > REMOTE_ASSET_CACHE_BYTES do
        local oldestUrl, oldestTick
        for cachedUrl, entry in pairs(remoteAssetCache) do
            if not oldestTick or (entry.tick or 0) < oldestTick then oldestUrl, oldestTick = cachedUrl, entry.tick or 0 end
        end
        if not oldestUrl then break end
        local entry = remoteAssetCache[oldestUrl]
        remoteAssetCacheBytes = remoteAssetCacheBytes - (entry.bytes or 0)
        remoteAssetCache[oldestUrl] = nil
    end
end

local function fetchRemoteAsset(url)
    local allowed, code = remoteAssetHostAllowed(url)
    if not allowed then return nil, code, code == 'BLOCKED_HOST' and 'That remote asset host is not allowed.' or 'Only valid HTTP(S) asset URLs are supported.' end

    local cached = remoteAssetCache[url]
    if cached then
        remoteAssetTick = remoteAssetTick + 1
        cached.tick = remoteAssetTick
        return { ok = true, dataUrl = cached.dataUrl, contentType = cached.contentType, bytes = cached.bytes, cached = true }
    end

    local deferred = promise.new()
    local settled = false
    SetTimeout(15000, function()
        if settled then return end
        settled = true
        deferred:resolve({ ok = false, code = 'TIMEOUT', error = 'Remote asset request timed out.' })
    end)

    PerformHttpRequest(url, function(status, body, headers, errorData)
        if settled then return end
        settled = true
        status = tonumber(status) or 0
        if status < 200 or status >= 300 then
            deferred:resolve({ ok = false, code = ('HTTP_%s'):format(status), error = ('Remote server returned HTTP %s.'):format(status), httpStatus = status })
            return
        end
        if type(body) ~= 'string' or #body == 0 then
            deferred:resolve({ ok = false, code = 'EMPTY_RESPONSE', error = 'Remote asset returned an empty response.' })
            return
        end
        if #body > REMOTE_ASSET_MAX_BYTES then
            deferred:resolve({ ok = false, code = 'ASSET_TOO_LARGE', error = ('Remote image is larger than %d MB.'):format(math.floor(REMOTE_ASSET_MAX_BYTES / 1024 / 1024)) })
            return
        end
        local contentType = remoteAssetContentType(headers, url, body)
        if contentType ~= 'application/octet-stream' and not contentType:match('^image/') then
            deferred:resolve({ ok = false, code = 'UNSUPPORTED_CONTENT_TYPE', error = ('Remote URL returned %s, not an image.'):format(contentType) })
            return
        end
        local dataUrl = ('data:%s;base64,%s'):format(contentType, base64Encode(body))
        cacheRemoteAsset(url, dataUrl, contentType, #body)
        deferred:resolve({ ok = true, dataUrl = dataUrl, contentType = contentType, bytes = #body, cached = false })
    end, 'GET', '', {
        ['Accept'] = 'image/avif,image/webp,image/png,image/jpeg,image/*,*/*;q=0.8',
        ['User-Agent'] = 'MetaComic/5 remote-asset-resolver'
    }, { followLocation = true })

    return Citizen.Await(deferred)
end

local function configuredIdentifierAllowed(source)
    local management = Config.Management or {}
    local allowed = management.Identifiers or {}
    if type(allowed) ~= 'table' then return false end
    local ids = {}
    local frameworkId = MetaComic.Framework.getIdentifier and MetaComic.Framework.getIdentifier(source)
    if frameworkId then ids[tostring(frameworkId)] = true end
    local license = MetaComic.GetLicense(source)
    if license then ids[tostring(license)] = true end
    for _, identifier in ipairs(GetPlayerIdentifiers(source) or {}) do ids[tostring(identifier)] = true end
    for _, configured in ipairs(allowed) do
        if ids[tostring(configured)] then return true end
    end
    return false
end

local function canManage(source)
    if source == 0 then return true end
    local management = Config.Management or {}
    if management.Enabled == false then return true end

    if management.Ace and management.Ace ~= '' and IsPlayerAceAllowed(source, management.Ace) then return true end
    if management.Ace == 'metacomic.manage' and IsPlayerAceAllowed(source, MetaComic.Legacy.manageAce) then return true end
    -- Backwards compatibility: anyone who already had the older catalog-write ACE keeps management access.
    local legacyAce = Config.Catalog and Config.Catalog.WriteAce
    if legacyAce and legacyAce ~= '' and IsPlayerAceAllowed(source, legacyAce) then return true end
    if legacyAce == 'metacomic.catalog.write' and IsPlayerAceAllowed(source, MetaComic.Legacy.catalogAce) then return true end
    if configuredIdentifierAllowed(source) then return true end

    if MetaComic.Framework.name == 'qbcore' and MetaComic.Framework.hasPermission then
        -- Older preserved configs predate Config.Management. Keep the intended
        -- admin/god restriction in that case; an explicit Management table always wins.
        local permissions = management.QBCorePermissions
        if permissions == nil and Config.Management == nil then permissions = { 'admin', 'god' } end
        for _, permission in ipairs(permissions or {}) do
            if MetaComic.Framework.hasPermission(source, permission) then return true end
        end
    end

    if MetaComic.Framework.name == 'qbox' and MetaComic.Framework.hasGroup then
        local groups = management.QboxGroups
        if groups == nil and Config.Management == nil then groups = { admin = 0 } end
        groups = groups or {}
        if next(groups) and MetaComic.Framework.hasGroup(source, groups) then return true end
    end

    local job = MetaComic.Framework.getJob and MetaComic.Framework.getJob(source)
    local jobs = management.Jobs or {}
    if job and job.name and jobs[job.name] ~= nil then
        local configured = jobs[job.name]
        local minGrade = type(configured) == 'table' and tonumber(configured.minGrade or configured.grade) or tonumber(configured)
        minGrade = minGrade or 0
        local dutyRequired = type(configured) == 'table' and configured.onDuty == true
        if (tonumber(job.grade) or 0) >= minGrade and (not dutyRequired or job.onDuty == true) then return true end
    end

    return false
end

local function requireManage(source)
    if canManage(source) then return true end
    return false, 'You do not have permission to manage trading cards, sets, packs, or boxes.'
end

local function setById(setId)
    if not MetaComic.Sets then return nil end
    local requested = tostring(setId or '')
    if requested == '' then requested = MetaComic.Sets.defaultId() end
    return MetaComic.Sets.get(requested)
end

local function sealedMetadata(kind, set)
    local noun = kind == 'box' and 'Booster Box' or 'Booster Pack'
    return {
        setId = set.id,
        seriesId = set.id,
        set = set.id, -- backwards compatibility with older builds
        setName = set.name,
        setCode = set.code,
        label = ('%s %s'):format(set.name or 'Trading Card', noun),
        description = ('Sealed %s for the %s set.'):format(noun:lower(), set.name or set.id),
    }
end

local function metadataSetId(metadata)
    metadata = type(metadata) == 'table' and metadata or {}
    return tostring(metadata.setId or metadata.seriesId or metadata.set or MetaComic.Sets.defaultId())
end

local function maybeRemoveOpenItem(source, itemName)
    if not Config.Items.RequireForOpen then return true, nil end
    if MetaComic.Inventory.name == 'none' then return false, 'Pack item validation is enabled but no inventory adapter is active.' end
    if not MetaComic.Inventory.has(source, itemName, 1) then return false, ('You do not have %s.'):format(itemName) end

    local chosen
    if MetaComic.Inventory.slotsOf then
        local slots = MetaComic.Inventory.slotsOf(source, itemName) or {}
        local _, first = next(slots)
        chosen = first
    end
    local metadata = chosen and (chosen.metadata or chosen.info) or nil
    local slot = chosen and chosen.slot or nil
    if not MetaComic.Inventory.remove(source, itemName, 1, metadata, slot) then return false, ('Could not remove %s.'):format(itemName) end
    return true, { metadata = metadata, slot = slot }
end

-- Pack opens granted by using a booster pack item. Each credit carries the set from that exact inventory item.
local packCredits = {}
local lastUse = {}

local function pushPackCredit(source, setId)
    packCredits[source] = packCredits[source] or {}
    packCredits[source][#packCredits[source] + 1] = { setId = setId }
end

local function popPackCredit(source)
    local queue = packCredits[source]
    if not queue or #queue == 0 then return nil end
    local credit = table.remove(queue, 1)
    if #queue == 0 then packCredits[source] = nil end
    return credit
end

local function notify(source, message, notifyType)
    if MetaComic.Framework.notify then MetaComic.Framework.notify(source, message, notifyType) end
end

local function giveBoxPacks(source, count, setId)
    if not Config.Items.BoxGivesPackItems then return false, 'Box opening is disabled (Config.Items.BoxGivesPackItems = false).' end
    if MetaComic.Inventory.name == 'none' then return false, 'Box opening needs an inventory adapter to hand out pack items.' end
    local set = setById(setId)
    if not set then return false, ('Unknown card set: %s'):format(tostring(setId)) end
    local setCardCount = MetaComic.Cards.countForSet and MetaComic.Cards.countForSet(set.id) or #(set.cardIds or {})
    if setCardCount < 1 then return false, ('Card set "%s" has no valid assigned cards.'):format(set.name or set.id) end
    if MetaComic.Inventory.add(source, Config.Items.BoosterPack, count, sealedMetadata('pack', set)) ~= true then
        return false, 'Could not add booster packs to your inventory (is it full?).'
    end
    return true
end

-- Remove one item and confirm the inventory really changed (guards against adapters that report success but don't remove).
-- metadata + slot ensure a set-specific pack/box removes the exact item that was used.
local function takeOne(source, item, metadata, slot)
    local inv = MetaComic.Inventory
    local before = inv.count and inv.count(source, item) or nil
    if before ~= nil and before < 1 then return false end
    if not inv.remove(source, item, 1, metadata, slot) then return false end
    if before ~= nil then
        local after = inv.count(source, item)
        if after >= before then
            print(('[meta-comic] %s reported %s removed for player %s but the count did not change (%s -> %s).'):format(inv.name, item, source, before, after))
            return false
        end
    end
    MetaComic.Debug('took', item, 'from', source, before, '->', before and before - 1, 'set', metadataSetId(metadata))
    return true
end

local resourceName = GetCurrentResourceName()
local function cardImageUrl(image)
    if type(image) ~= 'string' or image == '' or image:sub(1, 5) == 'data:' then return nil end
    if image:sub(1, 4) == 'http' or image:sub(1, 6) == 'nui://' then return image end
    return ('nui://%s/%s'):format(resourceName, (image:gsub('^/', '')))
end

-- ---------- what ox_inventory will accept as an item picture ----------
-- When the convar inventory:webhook is set, ox_inventory checks metadata.imageurl on every AddItem / SetMetadata
-- and DELETES urls it doesn't like (it still shows them until the slot refreshes, which is why a fixed icon
-- "reverted" after moving the card):
--   ox_inventory 2.45.1+ : nui://<started resource>/...png|webp  and  https:// hosts in inventory:validhosts
--                          (default r2.fivemanage.com + i.fmfile.com)
--   older ox_inventory   : https://i.imgur.com only
-- metadata.image (a file name in ox_inventory/web/images) is never checked, so it's the fallback.
local VALID_EXT = { png = true, apng = true, webp = true }
local oxRules

local function versionAtLeast(version, target)
    local a, b = {}, {}
    for n in tostring(version or ''):gmatch('%d+') do a[#a + 1] = tonumber(n) end
    for n in target:gmatch('%d+') do b[#b + 1] = tonumber(n) end
    for i = 1, math.max(#a, #b) do
        local x, y = a[i] or 0, b[i] or 0
        if x ~= y then return x > y end
    end
    return true
end

local function getOxRules()
    if oxRules then return oxRules end
    if MetaComic.Inventory.name ~= 'ox_inventory' then oxRules = { checks = false } return oxRules end
    local version = GetResourceMetadata('ox_inventory', 'version', 0) or '?'
    if GetConvar('inventory:webhook', '') == '' then oxRules = { checks = false, version = version } return oxRules end
    local modern = versionAtLeast(version, '2.45.1')
    local hosts = { ['i.imgur.com'] = true }
    if modern then
        local ok, decoded = pcall(json.decode, GetConvar('inventory:validhosts', '{"r2.fivemanage.com":true,"i.fmfile.com":true}'))
        hosts = ok and type(decoded) == 'table' and decoded or {}
    end
    oxRules = { checks = true, modern = modern, hosts = hosts, version = version }
    return oxRules
end

local function imageUrlAccepted(url)
    if type(url) ~= 'string' or url == '' then return false end
    local rules = getOxRules()
    if not rules.checks then return true end
    if url:match('^nui://') then
        if not rules.modern then return false end
        local res, ext = url:match('^nui://([^/]+)/.-%.(%l+)$')
        return res ~= nil and VALID_EXT[ext] == true
    end
    local host, ext = url:match('^https?://([^/]+).+%.([%l]+)')
    return host ~= nil and rules.hosts[host] == true and VALID_EXT[ext] == true
end

-- Inventory icons. 'rarity': one picture per rarity (img/cards/metacard_<rarity>.png, 100x100).
-- 'upload': every card gets one 100x100 icon per rarity it comes in, drawn in a player's NUI and uploaded to Fivemanage
-- (data/card_icons.json remembers them). Missing / outdated icons are made when the resource starts, when a
-- player joins, when the catalog is saved in-game and when a print is pulled; until then the rarity icon is used.
local RARITY_ICONS = { common = true, uncommon = true, rare = true, ultra_rare = true, legendary = true }
local ICON_FILE = 'data/card_icons.json'
local ICON_STYLE = 1 -- bump when cardIcon.js draws differently, so every icon is redrawn
-- One icon per base card + rarity ('<baseCardId>::<rarityKey>'), so a card has at most one icon per rarity no matter how
-- many variants or copies of it exist.
local ICON_FORMAT = 2
local iconUrls = {} -- icon key -> { v = 2, url = <uploaded url>, file = <ox picture file>, sig = <appearance signature>, hash }
do
    local raw = LoadResourceFile(resourceName, ICON_FILE)
    local ok, decoded = pcall(function() return raw and json.decode(raw) or nil end)
    local dropped = 0
    if ok and type(decoded) == 'table' then
        for key, value in pairs(decoded) do
            if type(value) == 'table' and value.v == ICON_FORMAT then iconUrls[key] = value
            else dropped = dropped + 1 end -- older per-variant icons: replaced by per-rarity ones
        end
    end
    if dropped > 0 then
        print(('[meta-comic] card icons: %d older per-variant icon entries dropped; one icon per card + rarity is made instead.'):format(dropped))
    end
end
local function saveIconFile() SaveResourceFile(resourceName, ICON_FILE, json.encode(iconUrls), -1) end

local function printKey(card)
    if type(card) == 'table' and OBJECT_ICON_PREFIX[card.collectableType] then
        return ('obj::%s::%s::%s'):format(card.collectableType, tostring(card.definitionId or card.id), tostring(card.printId or 'base'))
    end
    return card and card.baseCardId and ('%s::%s'):format(card.baseCardId, card.rarityKey or 'common') or nil
end

-- the card an icon is drawn from: the catalog's first variant of this card at this rarity (falls back to the card itself)
local function iconCard(card)
    if type(card) == 'table' and OBJECT_ICON_PREFIX[card.collectableType] then return card end
    return (card and card.baseCardId and MetaComic.Cards.forRarity(card.baseCardId, card.rarityKey or 'common')) or card
end
local function uploadMode() return Config.CardIcons and Config.CardIcons.Mode == 'upload' end

-- Each collectible type uploads its icons into its own Fivemanage folder and may use its own API key
-- (Config.FivemanageFolders; a type without its own key uses metacomic_fivemanage_key).
local FOLDER_DEFAULTS = {
    trading_card = { Path = 'meta-comics/trading-cards', KeyConvar = 'metacomic_fivemanage_key_cards' },
    challenge_coin = { Path = 'meta-comics/challenge-coins', KeyConvar = 'metacomic_fivemanage_key_coins' },
    plushie = { Path = 'meta-comics/plushies', KeyConvar = 'metacomic_fivemanage_key_plushies' },
}
local function folderFor(typeId)
    local defaults = FOLDER_DEFAULTS[typeId] or FOLDER_DEFAULTS.trading_card
    local configured = type(Config.FivemanageFolders) == 'table' and Config.FivemanageFolders[typeId] or {}
    return { path = configured.Path or defaults.Path, convar = configured.KeyConvar or defaults.KeyConvar }
end
local function fivemanageKey(typeId)
    local own = GetConvar(folderFor(typeId or 'trading_card').convar, '')
    if own ~= '' then return own end
    local key = GetConvar('metacomic_fivemanage_key', '')
    return key ~= '' and key or GetConvar(MetaComic.Legacy.uploadConvar, '')
end
local function anyFivemanageKey()
    for typeId in pairs(FOLDER_DEFAULTS) do if fivemanageKey(typeId) ~= '' then return true end end
    return false
end


-- everything the icon shows; when any of it changes in the catalog the icon is redrawn
local function iconSig(card)
    local parts = { tostring(ICON_STYLE), tostring(card.title), tostring(card.hp), tostring(card.accent),
        tostring(card.rarityKey), tostring(card.image), tostring(card.imagePositionX or 50), tostring(card.imagePositionY or 50), tostring(card.imageZoom or 100) }
    if OBJECT_ICON_PREFIX[card.collectableType] then -- everything a coin / plushie icon shows
        for _, field in ipairs({ 'collectableType', 'printId', 'finish', 'finishStrength', 'rimImage', 'edgeImage', 'edgeStyle', 'tint', 'tintStrength', 'stitchColor', 'stitchPattern', 'stitchWidth', 'backImage' }) do
            parts[#parts + 1] = tostring(card[field])
        end
    end
    local text = table.concat(parts, '\31')
    local h = 5381
    for i = 1, #text, 4096 do
        local bytes = { text:byte(i, math.min(i + 4095, #text)) }
        for j = 1, #bytes do h = (h * 33 + bytes[j]) % 4294967296 end
    end
    return ('%08x%d'):format(h, #text)
end

-- File mode: ox_inventory would delete the uploaded urls (see above), so each print's icon is ALSO saved as a
-- picture in ox_inventory/web/images and used through metadata.image, which ox never checks. FiveM only serves
-- files that existed when ox_inventory started, so a picture written now shows after the next server restart
-- (the item keeps the rarity icon until then).
-- where ox_inventory loads metadata.image pictures from (convar inventory:imagepath, default nui://ox_inventory/web/images)
local OX_IMG_RES, OX_IMAGES = 'ox_inventory', 'web/images/'
do
    local res, path = GetConvar('inventory:imagepath', 'nui://ox_inventory/web/images'):match('^nui://([^/]+)/(.-)/*$')
    if res and path and path ~= '' then OX_IMG_RES, OX_IMAGES = res, path .. '/' end
end
local writtenThisSession = {} -- ox picture file -> true (not downloadable by players until ox_inventory restarts)

local function fileMode()
    if not uploadMode() then return false end
    local rules = getOxRules()
    if not rules.checks then return false end
    return not rules.modern or not (rules.hosts['r2.fivemanage.com'] or rules.hosts['i.fmfile.com'])
end

local function oxFileName(key, sig)
    return ('%s_%s_%s'):format(OBJECT_ICON_PREFIX[keyType(key)] or 'metacard', (key:gsub('[^%w_-]+', '_')), sig:sub(1, 8))
end

local function needsIcon(card)
    local key = printKey(card)
    if not key then return false end
    card = iconCard(card)
    local entry = iconUrls[key]
    if not entry then return true end
    if not entry.sig then entry.sig = iconSig(card) end -- older file: assume it's current
    if entry.sig ~= iconSig(card) then return true end
    if fileMode() and not entry.file and not entry.fileFailed then return true end -- has a url ox would delete, but no picture file yet
    if not entry.url and uploadMode() and fivemanageKey(objectType(card) or 'trading_card') ~= '' then return true end -- its upload was deleted from Fivemanage
    return false
end

local function rarityName(card)
    if objectType(card) then return OBJECT_ICON_PREFIX[card.collectableType] .. '_' .. (RARITY_ICONS[card.rarityKey] and card.rarityKey or 'common') end
    return 'metacard_' .. (RARITY_ICONS[card.rarityKey] and card.rarityKey or 'common')
end

-- returns imageurl, image (metadata.image = file name in ox_inventory/web/images, used when there's no imageurl)
local function cardIcon(card)
    local icons = Config.CardIcons or {}
    local name = rarityName(card)
    local fileName = icons.OxImageFiles and name or nil
    if icons.Enabled == false then
        local art = cardImageUrl(card.image)
        if imageUrlAccepted(art) then return art, nil end
        return nil, name
    end
    local key = printKey(card)
    local entry = uploadMode() and key and iconUrls[key]
    if entry and entry.url and imageUrlAccepted(entry.url) then return entry.url, nil end
    if entry and entry.file and not writtenThisSession[entry.file] then return nil, entry.file end -- picture in ox_inventory/web/images
    local rarityUrl = ('nui://%s/img/%s/%s.png'):format(resourceName, objectType(card) and 'collectibles' or 'cards', name)
    if imageUrlAccepted(rarityUrl) then return rarityUrl, fileName end
    return nil, name -- ox_inventory would delete the url: use the picture copied into ox_inventory/web/images
end

-- Metadata stored on each tradingcard item (shown by ox_inventory / qb-inventory, used to show the card when used).
local function cardMetadata(card)
    local imageurl, image = cardIcon(card)
    local manual = card.manualPrint == true or card.acquisitionSource == 'manual_print'
    local setPart = card.setName and card.setName ~= '' and (' · ' .. card.setName) or ''
    local prefix = manual and 'MANUAL PRINT · ' or ''
    return {
        instanceId = card.instanceId,
        collectableType = 'trading_card',
        cardSnapshotVersion = 1,
        cardSnapshot = MetaComic.Collectables.snapshot('trading_card', card),
        cardIconSnapshotSignature = iconSig(iconCard(card)),
        cardKey = card.cardKey,
        baseCardId = card.baseCardId,
        variantId = card.variantId,
        setId = card.setId,
        seriesId = card.seriesId or card.setId,
        setName = card.setName,
        acquisitionSource = card.acquisitionSource,
        manualPrint = manual,
        printType = manual and 'MANUAL PRINT' or nil,
        printedBy = card.printedBy,
        printedByIdentifier = card.printedByIdentifier,
        printedAt = card.printedAt,
        label = ('%s (%s)%s'):format(card.title or 'Trading Card', card.variantName or 'Standard', manual and ' [Manual Print]' or ''),
        description = ('%s%s · %s%s'):format(prefix, card.rarity or 'Common', card.variantName or 'Standard', setPart),
        rarity = card.rarity,
        imageurl = imageurl,
        image = image,
    }
end

-- The physical item's server-created snapshot remains authoritative after transfers/deletion.
local function findCard(source, metadata)
    if type(metadata) ~= 'table' then return nil end
    if type(metadata.cardSnapshot) == 'table' then
        return MetaComic.CopyTable(metadata.cardSnapshot)
    end
    local owner = MetaComic.Framework.getIdentifier(source)
    if metadata.instanceId then
        for _, owned in ipairs(MetaComic.Persistence.getCollection(owner) or {}) do
            if owned.instanceId == metadata.instanceId then return owned end
        end
    end
    if metadata.baseCardId then
        local card = MetaComic.Cards.resolve(metadata.baseCardId, metadata.variantId)
        if card then
            -- Acquisition/print information belongs to the physical item and must survive inventory transfers.
            for _, key in ipairs({ 'setId', 'seriesId', 'setName', 'acquisitionSource', 'manualPrint', 'printedBy', 'printedByIdentifier', 'printedAt', 'instanceId' }) do
                if metadata[key] ~= nil then card[key] = metadata[key] end
            end
        end
        return card
    end
    return nil
end

-- Freeze legacy data and allow pending icons only for the appearance captured at creation.
-- inv is the player inventory or binder container. All writes remain server-side.
local function refreshCardItem(source, slot, metadata, inv)
    if not MetaComic.Inventory.setMetadata or type(metadata) ~= 'table' or not slot then return false end
    local migrated = false
    local image = MetaComic.Legacy.fallbackIcon(metadata.image)
    local imageurl = MetaComic.Legacy.fallbackIcon(metadata.imageurl)
    if image ~= metadata.image or imageurl ~= metadata.imageurl then
        metadata = MetaComic.CopyTable(metadata)
        metadata.image, metadata.imageurl = image, imageurl
        MetaComic.Inventory.setMetadata(inv or source, tonumber(slot), metadata)
        migrated = true
    end
    if type(metadata.cardSnapshot) == 'table' then
        local entry = iconUrls[printKey(metadata.cardSnapshot)]
        if not entry or not metadata.cardIconSnapshotSignature or entry.sig ~= metadata.cardIconSnapshotSignature then return migrated end
        local imageurl, image = cardIcon(metadata.cardSnapshot)
        if metadata.imageurl == imageurl and metadata.image == image then return migrated end
        local updated = MetaComic.CopyTable(metadata)
        updated.imageurl, updated.image = imageurl, image
        MetaComic.Inventory.setMetadata(inv or source, tonumber(slot), updated)
        return true
    end
    local card = findCard(source, metadata)
    if not card then return migrated end
    local fresh = cardMetadata(card)
    local updated = MetaComic.CopyTable(metadata)
    for key, value in pairs(fresh) do updated[key] = value end
    -- Legacy icons have no historical signature. Keep the existing picture rather than
    -- claiming a current catalog icon belongs to the original print.
    updated.cardIconSnapshotSignature = nil
    updated.imageurl, updated.image = metadata.imageurl, metadata.image
    MetaComic.Inventory.setMetadata(inv or source, tonumber(slot), updated)
    return true
end

local refreshObjectItemsLater -- defined with the icon pipeline below
local function refreshPlayerItems(source)
    if not MetaComic.Inventory.slotsOf then return 0 end
    local updated = refreshObjectItemsLater and refreshObjectItemsLater(source) or 0
    for _, item in pairs(MetaComic.Inventory.slotsOf(source, Config.Items.TradingCard)) do
        if refreshCardItem(source, item.slot, item.metadata) then updated = updated + 1 end
    end
    if MetaComic.Inventory.getContainer then
        local binders = type(Config.Items.Binder) == 'table' and Config.Items.Binder or { Config.Items.Binder }
        for _, name in ipairs(binders) do
            for _, binder in pairs(MetaComic.Inventory.slotsOf(source, name)) do
                if binder.metadata and binder.metadata.container then
                    local container = MetaComic.Inventory.getContainer(source, binder.slot)
                    if container and container.id then
                        for index, item in pairs(container.items or {}) do
                            if item.name == Config.Items.TradingCard and refreshCardItem(source, item.slot or tonumber(index), item.metadata, container.id) then
                                updated = updated + 1
                            end
                        end
                    end
                end
            end
        end
    end
    return updated
end

local function freezeOnlineItems()
    -- Capture online players' legacy items before an administrator edits/deletes definitions.
    for _, id in ipairs(GetPlayers()) do refreshPlayerItems(tonumber(id)) end
end

-- ---------- uploaded card icons ----------
local pendingIcons, uploading, iconAttempts = {}, {}, {}
local MAX_ATTEMPTS = 3

local function uploadIcon(key, sig, dataUrl, cb)
    local typeId = keyType(key)
    local apiKey = fivemanageKey(typeId)
    if apiKey == '' then return cb(nil) end
    local ext = dataUrl:match('^data:image/(%a+);') or 'png'
    local filename = ('%s.%s'):format(oxFileName(key, sig), ext) -- same print + same look = same name
    PerformHttpRequest('https://api.fivemanage.com/api/v3/file/base64', function(status, body)
        local ok, res = pcall(json.decode, body or '')
        local data = ok and type(res) == 'table' and type(res.data) == 'table' and res.data or nil
        local url = data and data.url or nil
        -- custom CDN domain: 'url' uses it, 'originalUrl' is the r2.fivemanage.com one ox_inventory trusts by default
        if url and data.originalUrl and not imageUrlAccepted(url) and imageUrlAccepted(data.originalUrl) then url = data.originalUrl end
        if not url then
            print(('[meta-comic] card icon upload failed for %s (HTTP %s): %s'):format(key, tostring(status), tostring(body):sub(1, 200)))
        end
        cb(url)
    end, 'POST', json.encode({ base64 = dataUrl, filename = filename, path = folderFor(typeId).path, metadata = json.encode({ card = key, collectableType = typeId }) }), {
        ['Content-Type'] = 'application/json',
        ['Authorization'] = apiKey,
    })
end

-- ask this player's NUI to draw icons for prints that have no (current) uploaded icon; returns the keys asked for
local function iconsPossible() return uploadMode() and (anyFivemanageKey() or fileMode()) end

local function requestIcons(source, cards)
    if not iconsPossible() then return {} end
    local list, keys = {}, {}
    pendingIcons[source] = pendingIcons[source] or {}
    for _, card in ipairs(cards or {}) do
        local key = printKey(card)
        if key and needsIcon(card) and not uploading[key] and not pendingIcons[source][key] and (iconAttempts[key] or 0) < MAX_ATTEMPTS then
            local drawn = iconCard(card)
            pendingIcons[source][key] = iconSig(drawn)
            list[#list + 1] = { key = key, card = drawn }
            keys[#keys + 1] = key
        end
    end
    if #list > 0 then
        TriggerLatentClientEvent('meta_comic:client:renderIcons', source, 512 * 1024, list, (Config.CardIcons and Config.CardIcons.Size) or 100, fileMode() and 'png' or 'webp')
    end
    return keys
end

-- coin / plushie items: picture from their own print's icon (rarity picture until it is uploaded)
-- an item shows its print's uploaded icon only while that icon still matches the item's own snapshot;
-- after the print is edited, older items keep the rarity picture instead of borrowing the new look
local function objectIcon(snapshot)
    local entry = iconUrls[printKey(snapshot)]
    if entry and entry.sig and entry.sig ~= iconSig(snapshot) then
        local rarityOnly = MetaComic.CopyTable(snapshot)
        rarityOnly.printId = '__rarity__' -- no icon entry under this key -> rarity picture
        return cardIcon(rarityOnly)
    end
    return cardIcon(snapshot)
end
local function refreshObjectItem(source, item)
    local meta = item and (item.metadata or item.info)
    if type(meta) ~= 'table' or type(meta.collectibleSnapshot) ~= 'table' or not MetaComic.Inventory.setMetadata then return false end
    local imageurl, image = objectIcon(meta.collectibleSnapshot)
    if meta.imageurl == imageurl and meta.image == image then return false end
    local updated = MetaComic.CopyTable(meta)
    updated.imageurl, updated.image = imageurl, image
    MetaComic.Inventory.setMetadata(source, tonumber(item.slot), updated)
    return true
end
local function refreshObjectItems(source, typeId, key)
    if not MetaComic.Inventory.slotsOf then return 0 end
    local count = 0
    for id, names in pairs(objectTypes()) do
        if not typeId or typeId == id then
            for _, item in pairs(MetaComic.Inventory.slotsOf(source, names.item)) do
                local meta = item.metadata or item.info
                if (not key or (type(meta) == 'table' and printKey(meta.collectibleSnapshot) == key)) and refreshObjectItem(source, item) then count = count + 1 end
            end
        end
    end
    return count
end

-- after a print's icon changed: update that print's card items for everyone online
local function refreshItemsForPrint(key)
    if not MetaComic.Inventory.slotsOf then return end
    if key:sub(1, 5) == 'obj::' then
        for _, id in ipairs(GetPlayers()) do refreshObjectItems(tonumber(id), keyType(key), key) end
        return
    end
    for _, id in ipairs(GetPlayers()) do
        local src = tonumber(id)
        for _, item in pairs(MetaComic.Inventory.slotsOf(src, Config.Items.TradingCard)) do
            local meta = item.metadata
            if type(meta) == 'table' and meta.baseCardId and key:sub(1, #tostring(meta.baseCardId) + 2) == meta.baseCardId .. '::' then
                if printKey(findCard(src, meta)) == key then refreshCardItem(src, item.slot, meta) end
            end
        end
    end
end

refreshObjectItemsLater = function(source) return refreshObjectItems(source) end

-- hooks used by server/modules/objects.lua: item pictures, icons for new pulls, icons after catalogue saves
if MetaComic.Objects then
    MetaComic.Objects.icon = function(snapshot) return objectIcon(snapshot) end
    MetaComic.Objects.onPulled = function(source, snapshots) requestIcons(source, snapshots) end
end

local B64 = {}
do
    local chars = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/'
    for i = 1, #chars do B64[chars:byte(i)] = i - 1 end
end
local function base64Decode(text)
    local out, n, bits, count = {}, 0, 0, 0
    for i = 1, #text do
        local v = B64[text:byte(i)]
        if v then
            bits = bits * 64 + v
            count = count + 1
            if count == 4 then
                n = n + 1
                out[n] = string.char(bits // 65536 % 256, bits // 256 % 256, bits % 256)
                bits, count = 0, 0
            end
        end
    end
    if count == 3 then n = n + 1 out[n] = string.char(bits // 1024 % 256, bits // 4 % 256)
    elseif count == 2 then n = n + 1 out[n] = string.char(bits // 16 % 256) end
    return table.concat(out)
end

-- write the icon into ox_inventory/web/images (file mode); returns the metadata.image name
local function saveOxPicture(key, sig, dataUrl)
    local bytes = base64Decode(dataUrl:match(',(.*)$') or '')
    if #bytes < 64 then return nil end
    local name = oxFileName(key, sig)
    local path = OX_IMAGES .. name .. '.png'
    SaveResourceFile(OX_IMG_RES, path, bytes, #bytes)
    local back = LoadResourceFile(OX_IMG_RES, path) -- check it really landed
    if not back or #back ~= #bytes then return nil end
    writtenThisSession[name] = true
    return name
end

-- Same icon picture (byte for byte) -> reuse its upload instead of uploading it again
local function iconHash(dataUrl)
    local h = 5381
    for i = 1, #dataUrl, 4096 do
        local bytes = { dataUrl:byte(i, math.min(i + 4095, #dataUrl)) }
        for j = 1, #bytes do h = (h * 33 + bytes[j]) % 4294967296 end
    end
    return ('%08x%d'):format(h, #dataUrl)
end
local function urlForHash(hash)
    for _, entry in pairs(iconUrls) do
        if entry.hash == hash and entry.url then return entry.url end
    end
end

local uploadedThisSession = {} -- key..sig -> true: never upload the same print + look twice
local fileWriteFailed = false
local warnedRejected = false

RegisterNetEvent('meta_comic:server:cardIcon', function(key, dataUrl)
    local source = source
    local sig = type(key) == 'string' and pendingIcons[source] and pendingIcons[source][key]
    if not sig then return end -- only icons we asked this player for
    pendingIcons[source][key] = nil
    if type(dataUrl) ~= 'string' or dataUrl == '' or #dataUrl > 250000 or not dataUrl:match('^data:image/[%a]+;base64,') then
        iconAttempts[key] = (iconAttempts[key] or 0) + 1 -- the NUI couldn't draw it (e.g. artwork from a site without CORS)
        return
    end
    if uploading[key] then return end

    local entry = iconUrls[key]
    if not (entry and entry.sig == sig) then entry = { v = ICON_FORMAT, sig = sig } end -- new icon, or its look changed
    iconUrls[key] = entry

    if fileMode() and not entry.file then
        local file = saveOxPicture(key, sig, dataUrl)
        if file then
            entry.file = file
            MetaComic.Debug('card icon saved as picture file', key, file)
        else
            entry.fileFailed = true -- don't ask for it again this session
            if not fileWriteFailed then
                fileWriteFailed = true
                print(('[meta-comic] could not write card pictures into %s/%s (folder missing or not writable?).'):format(OX_IMG_RES, OX_IMAGES))
            end
        end
    end

    local hash = iconHash(dataUrl)
    entry.hash = entry.hash or hash
    if not entry.url then entry.url = urlForHash(hash) end -- identical picture already uploaded
    saveIconFile()

    local uploadKey = key .. '|' .. sig
    if entry.url or fivemanageKey(keyType(key)) == '' or uploadedThisSession[uploadKey] then
        refreshItemsForPrint(key)
        return
    end

    uploading[key] = true
    uploadedThisSession[uploadKey] = true
    uploadIcon(key, sig, dataUrl, function(url)
        uploading[key] = nil
        if not url then
            uploadedThisSession[uploadKey] = nil
            iconAttempts[key] = (iconAttempts[key] or 0) + 1
            return
        end
        local current = iconUrls[key]
        if not (current and current.sig == sig) then return end -- the card was edited meanwhile; its new look gets its own upload
        current.url = url
        saveIconFile()
        MetaComic.Debug('card icon uploaded', key, url)
        if not imageUrlAccepted(url) and not warnedRejected and not fileMode() then
            warnedRejected = true
            print(('[meta-comic] ox_inventory will delete the uploaded icon url (%s): add its host to the convar inventory:validhosts.'):format(url))
        end
        refreshItemsForPrint(key)
    end)
end)

-- ---------- keep every card + rarity icon uploaded ----------
local readyWorkers = {} -- players whose NUI has loaded (it draws the icons)
local syncRunning, syncAgain, syncPreferred = false, false, nil

local function catalogPrints() -- one per base card + rarity, plus one per coin / plushie print
    local list = MetaComic.Cards.rarityPrints()
    if MetaComic.Objects and MetaComic.Objects.iconPrints then
        for _, print in ipairs(MetaComic.Objects.iconPrints()) do list[#list + 1] = print end
    end
    return list
end

local function missingPrints(includeFailed)
    local list = {}
    for _, card in ipairs(catalogPrints()) do
        local key = printKey(card)
        if needsIcon(card) and (includeFailed or (not uploading[key] and (iconAttempts[key] or 0) < MAX_ATTEMPTS)) then list[#list + 1] = card end
    end
    return list
end

local function pickWorker()
    if syncPreferred and readyWorkers[syncPreferred] and GetPlayerName(syncPreferred) then return syncPreferred end
    for src in pairs(readyWorkers) do
        if GetPlayerName(src) then return src end
        readyWorkers[src] = nil
    end
    return nil
end

local function waitForIcons(worker, keys)
    local deadline = GetGameTimer() + 45000
    while GetGameTimer() < deadline do
        if not GetPlayerName(worker) then break end
        local open = false
        for _, key in ipairs(keys) do
            if (pendingIcons[worker] and pendingIcons[worker][key]) or uploading[key] then open = true break end
        end
        if not open then return end
        Wait(300)
    end
    for _, key in ipairs(keys) do -- timed out / left: count it as a failed try and move on
        if pendingIcons[worker] and pendingIcons[worker][key] then
            pendingIcons[worker][key] = nil
            iconAttempts[key] = (iconAttempts[key] or 0) + 1
        end
    end
end

-- Check that the saved Fivemanage urls still exist (files deleted on the dashboard -> upload them again).
-- One HEAD request per url, one at a time. Network errors keep the url; only "not found" removes it.
local checkingUrls = false
local function checkIconUrls(done)
    if checkingUrls or not anyFivemanageKey() then return done and done(0) end
    checkingUrls = true
    local urls, seen = {}, {}
    for _, entry in pairs(iconUrls) do
        if entry.url and not seen[entry.url] then seen[entry.url] = true urls[#urls + 1] = entry.url end
    end
    local index, removed = 0, 0
    local function nextUrl()
        index = index + 1
        local url = urls[index]
        if not url then
            checkingUrls = false
            if removed > 0 then
                uploadedThisSession = {} -- those prints may be uploaded again
                saveIconFile()
                print(('[meta-comic] card icons: %d saved Fivemanage url%s no longer exist%s; uploading %s again.'):format(
                    removed, removed == 1 and '' or 's', removed == 1 and 's' or '', removed == 1 and 'it' or 'them'))
            end
            if done then done(removed) end
            return
        end
        PerformHttpRequest(url, function(status)
            if status == 404 or status == 410 or status == 403 then
                for _, entry in pairs(iconUrls) do
                    if entry.url == url then entry.url = nil entry.hash = nil removed = removed + 1 end
                end
            end
            nextUrl()
        end, 'HEAD', '', {})
    end
    nextUrl()
end

local function syncIcons(preferred)
    if not iconsPossible() then return end
    if preferred then syncPreferred = preferred end
    syncAgain = true
    if syncRunning then return end
    syncRunning = true
    CreateThread(function()
        local done = 0
        while syncAgain do
            syncAgain = false
            local missing = missingPrints()
            while #missing > 0 do
                local worker = pickWorker()
                if not worker then break end -- carries on when the next player's UI is ready
                local batch = {}
                for i = 1, math.min(8, #missing) do batch[i] = missing[i] end
                local keys = requestIcons(worker, batch)
                if #keys == 0 then break end
                waitForIcons(worker, keys)
                done = done + #keys
                missing = missingPrints()
            end
        end
        syncRunning = false
        syncPreferred = nil
        if done > 0 then
            local left = #missingPrints(true)
            print(('[meta-comic] card icons: %d requested, %d card + rarity icon%s still missing%s.'):format(done, left, left == 1 and '' or 's',
                left > 0 and ' (they keep the rarity icon; /' .. tostring(Config.CardIcons.RefreshCommand or 'cardicons') .. ' in the server console retries)' or ''))
        end
    end)
end

-- a coin / plushie catalogue save: new or edited prints get their icon drawn (by the saving admin) and uploaded
if MetaComic.Objects then MetaComic.Objects.afterSave = function(source) syncIcons(source) end end

-- the client says its NUI is loaded (on join, and on every resource restart for players already online)
RegisterNetEvent('meta_comic:server:uiReady', function()
    local source = source
    readyWorkers[source] = true
    if MetaComic.Objects then
        local ok,err=pcall(MetaComic.Objects.claim,source)
        if not ok then MetaComic.Debug('Pending collectible delivery: '..tostring(err)) end
    end
    refreshPlayerItems(source) -- card items get the current icon (also fixes items made before an icon existed)
    syncIcons()
end)

-- On start: drop saved urls whose file was deleted from Fivemanage, then redraw + re-upload those prints.
CreateThread(function()
    Wait(2000)
    if not uploadMode() then return end
    checkIconUrls(function(removed)
        if removed == 0 then return end
        for _, id in ipairs(GetPlayers()) do refreshPlayerItems(tonumber(id)) end
        syncIcons()
    end)
end)

AddEventHandler('playerDropped', function()
    readyWorkers[source] = nil
    if syncPreferred == source then syncPreferred = nil end
end)

-- Startup: say what ox_inventory will do with card pictures, check the saved picture files still exist, and when
-- ox_inventory can't use urls copy the 5 rarity pictures into ox_inventory/web/images.
CreateThread(function()
    Wait(1000)
    local rules = getOxRules()
    if MetaComic.Inventory.name ~= 'ox_inventory' then return end
    local sample
    for _, entry in pairs(iconUrls) do if entry.url then sample = entry.url break end end
    print(('[meta-comic] card pictures: ox_inventory %s, inventory:webhook %s%s%s'):format(tostring(rules.version),
        rules.checks and 'SET (ox deletes picture urls it does not trust)' or 'not set (all picture urls kept)',
        sample and (', Fivemanage urls ' .. (imageUrlAccepted(sample) and 'accepted' or 'NOT accepted')) or '',
        fileMode() and (' -> per-card icons are saved as picture files in %s/%s (new ones show after a full server restart)'):format(OX_IMG_RES, OX_IMAGES) or ''))
    if fileMode() then
        local waiting = 0
        for _, entry in pairs(iconUrls) do if entry.file and writtenThisSession[entry.file] then waiting = waiting + 1 end end
        local ready = 0
        for _, entry in pairs(iconUrls) do if entry.file then ready = ready + 1 end end
        print(('[meta-comic] card pictures: %d per-card picture files ready to show this session.'):format(ready - waiting))
    end
    if fileMode() then
        print('[meta-comic] for per-card icons that show straight away: remove "inventory:webhook" from server.cfg (ox_inventory only uses it to log picture urls to Discord) or update ox_inventory to 2.45.1+.')
    end

    local missingFiles = false
    for _, entry in pairs(iconUrls) do
        if entry.fileFailed then entry.fileFailed = nil missingFiles = true end -- retry writes that failed last session
        if entry.file and not LoadResourceFile(OX_IMG_RES, OX_IMAGES .. entry.file .. '.png') then
            entry.file = nil -- ox_inventory was reinstalled / cleaned: draw them again
            missingFiles = true
        end
    end
    if missingFiles then saveIconFile() end

    if not rules.checks or imageUrlAccepted(('nui://%s/img/cards/metacard_common.png'):format(resourceName)) then return end
    local copied = 0
    for tier in pairs(RARITY_ICONS) do
        local target = OX_IMAGES .. ('metacard_%s.png'):format(tier)
        if not LoadResourceFile(OX_IMG_RES, target) then
            local data = LoadResourceFile(resourceName, ('img/cards/metacard_%s.png'):format(tier))
            if data and SaveResourceFile(OX_IMG_RES, target, data, #data) then copied = copied + 1 end
        end
    end
    for _, prefix in pairs(OBJECT_ICON_PREFIX) do
        for tier in pairs(RARITY_ICONS) do
            local target = OX_IMAGES .. ('%s_%s.png'):format(prefix, tier)
            if not LoadResourceFile(OX_IMG_RES, target) then
                local data = LoadResourceFile(resourceName, ('img/collectibles/%s_%s.png'):format(prefix, tier))
                if data and SaveResourceFile(OX_IMG_RES, target, data, #data) then copied = copied + 1 end
            end
        end
    end
    if copied > 0 then
        print(('[meta-comic] copied %d rarity card pictures into ox_inventory/web/images. Restart the server once so players download them.'):format(copied))
    end
end)

-- ox_inventory restarted: the picture files written since are downloadable now
AddEventHandler('onResourceStart', function(name)
    if name ~= OX_IMG_RES or next(writtenThisSession) == nil then return end
    writtenThisSession = {}
    SetTimeout(5000, function()
        for _, id in ipairs(GetPlayers()) do refreshPlayerItems(tonumber(id)) end
    end)
end)

local function viewCard(source, metadata)
    if type(metadata) ~= 'table' then return notify(source, 'This card has no card data.', 'error') end
    local card = findCard(source, metadata)
    if not card then return notify(source, 'That card is no longer in the catalog.', 'error') end
    TriggerLatentClientEvent('meta_comic:client:viewCard', source, 512 * 1024, card)
end

-- "Show Card" button: show a card from your inventory to the players standing near you.
local lastShow = {}
local lastBinder = {} -- throttle opening
local activeBinder = {} -- source -> { slot = player inventory slot, container = ox container id }
local lastBinderSwap = {}
local function showCardToOthers(source, metadata)
    local now = GetGameTimer()
    if lastShow[source] and now - lastShow[source] < 2000 then return end
    lastShow[source] = now
    local card = findCard(source, metadata)
    if not card then return notify(source, 'That card has no card data.', 'error') end

    local maxDistance = (Config.ShowCard and Config.ShowCard.Distance) or 3.0
    local myPed = GetPlayerPed(source)
    if not myPed or myPed == 0 then return end
    local myCoords = GetEntityCoords(myPed)
    local name = MetaComic.Framework.getName and MetaComic.Framework.getName(source) or GetPlayerName(source)
    local shown = 0
    for _, id in ipairs(GetPlayers()) do
        local target = tonumber(id)
        if target ~= source then
            local ped = GetPlayerPed(target)
            if ped and ped ~= 0 and #(GetEntityCoords(ped) - myCoords) <= maxDistance then
                TriggerLatentClientEvent('meta_comic:client:viewCard', target, 512 * 1024, card, name)
                shown = shown + 1
            end
        end
    end
    if shown == 0 then
        notify(source, 'Nobody is close enough to see your card.', 'error')
    else
        notify(source, ('Showing %s to %d player%s.'):format(card.title or 'your card', shown, shown == 1 and '' or 's'), 'success')
    end
end

-- Called when a player uses a booster pack / booster box item (framework usable item or ox_inventory client export).
local function useItem(source, kind, slot, passedItem)
    local now = GetGameTimer()
    MetaComic.Debug('useItem', kind, 'player', source, 'inventory', MetaComic.Inventory.name, 'slot', slot)
    if lastUse[source] and now - lastUse[source] < 1200 then MetaComic.Debug('useItem ignored: repeat within 1.2 s') return end
    lastUse[source] = now

    if MetaComic.Inventory.name == 'none' then
        notify(source, 'Trading card items need an inventory adapter (Config.Inventory).', 'error')
        return
    end

    local expected = kind == 'box' and Config.Items.BoosterBox or Config.Items.BoosterPack
    local item = nil
    slot = tonumber(slot or (type(passedItem) == 'table' and passedItem.slot))
    if slot and MetaComic.Inventory.getSlot then item = MetaComic.Inventory.getSlot(source, slot) end
    if not item and type(passedItem) == 'table' then item = passedItem end
    if item and item.name and item.name ~= expected then return end

    local metadata = type(item) == 'table' and (item.metadata or item.info) or nil
    local setId = metadataSetId(metadata)
    local set = setById(setId)
    if not set then return notify(source, ('This sealed item references an unknown card set: %s.'):format(setId), 'error') end
    local setCardCount = MetaComic.Cards.countForSet and MetaComic.Cards.countForSet(set.id) or #(set.cardIds or {})
    if setCardCount < 1 then return notify(source, ('The %s set has no valid assigned cards.'):format(set.name or set.id), 'error') end

    if kind == 'pack' then
        if not MetaComic.Inventory.has(source, expected, 1) then return notify(source, 'You do not have a booster pack.', 'error') end
        if not takeOne(source, expected, metadata, slot) then return notify(source, 'Could not use the booster pack.', 'error') end
        pushPackCredit(source, set.id)
        TriggerClientEvent('meta_comic:client:openPackOverlay', source, set.id, set.name)
    elseif kind == 'box' then
        local count = MetaComic.Collectables.containerCount('booster_box')
        if not MetaComic.Inventory.has(source, expected, 1) then return notify(source, 'You do not have a booster box.', 'error') end
        if not takeOne(source, expected, metadata, slot) then return notify(source, 'Could not open the booster box.', 'error') end
        local ok, err = giveBoxPacks(source, count, set.id)
        if not ok then
            MetaComic.Inventory.add(source, expected, 1, sealedMetadata('box', set)) -- refund the exact set box
            return notify(source, err, 'error')
        end
        notify(source, ('You opened a %s booster box: +%d %s packs.'):format(set.name, count, set.name), 'success')
        TriggerClientEvent('meta_comic:client:boxOpened', source, count, set.id, set.name)
    end
end

-- Card items are handed over once the player has flipped them all or closed the opening
-- (adding them at roll time would pop inventory notifications that spoil the reveal). Fallback: after 2 minutes.
local pendingCardItems = {}

local function giveCardItems(source)
    local list = pendingCardItems[source]
    pendingCardItems[source] = nil
    if not list then return 0 end
    for _, card in ipairs(list) do
        if MetaComic.Inventory.add(source, Config.Items.TradingCard, 1, cardMetadata(card)) ~= true then
            print(('[meta-comic] could not add card item %s to player %s (inventory full?)'):format(card.cardKey or '?', source))
        end
    end
    return #list
end

local function queueCardItems(source, cards)
    if not Config.Items.GiveCardItems or MetaComic.Inventory.name == 'none' then return end
    if pendingCardItems[source] then giveCardItems(source) end -- an earlier pack nobody claimed
    local list = MetaComic.CopyTable(cards)
    pendingCardItems[source] = list
    SetTimeout(120000, function()
        if pendingCardItems[source] == list then giveCardItems(source) end
    end)
end

AddEventHandler('playerDropped', function()
    packCredits[source] = nil
    lastUse[source] = nil
    pendingCardItems[source] = nil -- the cards are still saved in the player's collection
    lastShow[source] = nil
    lastBinder[source] = nil
    activeBinder[source] = nil
    lastBinderSwap[source] = nil
    pendingIcons[source] = nil
end)

local handlers = {}

handlers.getCollectibles = function(source)
    if not MetaComic.Objects then return fail('Coins and plushies are off: update fxmanifest.lua (see the server console).') end
    return {ok=true,data=MetaComic.Objects.get(source)}
end
handlers.saveCollectible = function(source,payload)
    local allowed,err=requireManage(source);if not allowed then return fail(err) end
    if not MetaComic.Objects then return fail('Coins and plushies are off: update fxmanifest.lua (see the server console).') end
    MetaComic.Objects.save(payload)
    if MetaComic.Objects.afterSave then MetaComic.Objects.afterSave(source) end
    return {ok=true,data=MetaComic.Objects.get(source)}
end
handlers.openCollectibleContainer = function(source,payload)
    if not MetaComic.Objects then return fail('Coins and plushies are off: update fxmanifest.lua (see the server console).') end
    local result=MetaComic.Objects.open(source,payload,canManage(source))
    result.ok=true;return result
end
handlers.claimCollectibles = function(source)
    if not MetaComic.Objects then return fail('Collectibles are unavailable') end
    return {ok=true,given=MetaComic.Objects.claim(source)}
end
handlers.createCollectibleContainer = function(source,payload)
    local allowed,err=requireManage(source);if not allowed then return fail(err) end
    if MetaComic.Inventory.name=='none' then return fail('A physical inventory is required') end
    if not MetaComic.Objects then return fail('Coins and plushies are off: update fxmanifest.lua (see the server console).') end
    return {ok=true,data=MetaComic.Objects.create(source,payload)}
end

handlers.getRuntimeInfo = function(source)
    local management = canManage(source)
    local capabilities = MetaComic.CopyTable(MetaComic.RuntimeInfo.capabilities or {})
    capabilities.management = management
    capabilities.editor = management and Config.Nui.AllowEditor == true
    capabilities.catalogWrite = management and Config.Catalog.AllowWrite == true
    capabilities.setManagement = management
    capabilities.manualPrint = management and MetaComic.Inventory.name ~= 'none'
    capabilities.createSealed = management and MetaComic.Inventory.name ~= 'none'
    capabilities.collectibles = MetaComic.Objects ~= nil
    return {
        ok = true,
        runtime = MetaComic.RuntimeInfo.runtime,
        framework = MetaComic.RuntimeInfo.framework,
        inventory = MetaComic.RuntimeInfo.inventory,
        persistence = MetaComic.RuntimeInfo.persistence,
        capabilities = capabilities,
        packAnimation = {
            maxSpeed = (Config.PackAnimation and Config.PackAnimation.MaxSpeed) or 3.0,
            flipAllKey = (Config.PackAnimation and Config.PackAnimation.FlipAllKey) or 'F'
        }
    }
end

handlers.resolveRemoteAsset = function(_, payload)
    local url = type(payload) == 'table' and tostring(payload.url or '') or ''
    local result, code, message = fetchRemoteAsset(url)
    if result then return result end
    return { ok = false, code = code or 'LOAD_FAILED', error = message or 'Could not load remote asset.' }
end

handlers.getCatalog = function()
    -- Administrative reads refresh persisted definitions; normal pulls still use the cache.
    if MetaComic.Persistence.reloadDefinitions then
        local ok,err=MetaComic.Persistence.reloadDefinitions()
        if not ok then return fail(tostring(err)) end
        MetaComic.Cards.reloadCatalog()
        MetaComic.Sets.reload()
    end
    return { ok = true, cards = MetaComic.Cards.getCatalog(), sets = MetaComic.Sets.getAll() }
end

-- Explicit recovery only; never automatically resurrect intentionally deleted definitions.
local function restoreSeed(source)
    if source ~= 0 then return notify(source, 'Run collectablesrestoreseed from the server console.', 'error') end
    if MetaComic.Persistence.name ~= 'mysql' or not MetaComic.Persistence.restoreMissingDefinitions then
        return print('[meta-comic] cardrestoreseed requires MySQL persistence.')
    end
    local ok, result = MetaComic.Persistence.restoreMissingDefinitions()
    if not ok then return print('[meta-comic] recovery failed: ' .. tostring(result)) end
    MetaComic.Cards.reloadCatalog()
    MetaComic.Sets.reload()
    print(('[meta-comic] recovered %d cards, %d prints, %d sets, %d memberships; existing records were kept. Reopen /cardadmin.'):format(result.cards, result.prints, result.sets, result.memberships))
    syncIcons()
end
RegisterCommand('collectablesrestoreseed',restoreSeed,true)
RegisterCommand('cardrestoreseed',restoreSeed,true)

handlers.saveCatalog = function(source, payload)
    local allowed, permissionError = requireManage(source)
    if not allowed then return fail(permissionError) end
    if not Config.Catalog.AllowWrite then return fail('FiveM catalog write is disabled in config.lua') end
    freezeOnlineItems()
    local ok, err = MetaComic.Cards.saveCatalog(payload.cards)
    if not ok then return fail(err or 'Could not save catalog') end
    syncIcons(source) -- new / changed prints get their inventory icon drawn (by this player) and uploaded
    return { ok = true }
end

handlers.saveCard = function(source, payload)
    local allowed, permissionError = requireManage(source)
    if not allowed then return fail(permissionError) end
    if not Config.Catalog.AllowWrite then return fail('FiveM catalog write is disabled in config.lua') end
    freezeOnlineItems()
    local ok, err = MetaComic.Cards.saveCard(payload.card)
    if not ok then return fail(err or 'Could not save card') end
    syncIcons(source)
    return { ok = true, cardId = payload.card and payload.card.id or nil }
end

handlers.deleteCard = function(source, payload)
    local allowed, permissionError = requireManage(source)
    if not allowed then return fail(permissionError) end
    if not Config.Catalog.AllowWrite then return fail('FiveM catalog write is disabled in config.lua') end
    freezeOnlineItems()
    local ok, err = MetaComic.Cards.deleteCard(payload.cardId)
    if not ok then return fail(err or 'Could not delete card') end
    return { ok = true, cardId = payload.cardId }
end

handlers.getSets = function()
    return { ok = true, sets = MetaComic.Sets.getAll(), defaultSet = MetaComic.Sets.defaultId() }
end

handlers.saveSets = function(source, payload)
    local allowed, permissionError = requireManage(source)
    if not allowed then return fail(permissionError) end
    local ok, err = MetaComic.Sets.save(payload.sets)
    if not ok then return fail(err or 'Could not save card sets') end
    return { ok = true, sets = MetaComic.Sets.getAll() }
end

handlers.printCard = function(source, payload)
    local allowed, permissionError = requireManage(source)
    if not allowed then return fail(permissionError) end
    if MetaComic.Inventory.name == 'none' then return fail('Manual printing needs an inventory adapter.') end

    local card = MetaComic.Cards.resolve(payload.baseCardId, payload.variantId)
    if not card then return fail('That card print no longer exists in the server catalog.') end

    local set = payload.setId and setById(payload.setId) or nil
    local owner = MetaComic.Framework.getIdentifier(source)
    local printedBy = MetaComic.Framework.getName and MetaComic.Framework.getName(source) or GetPlayerName(source)
    local now = os.date('!%Y-%m-%dT%H:%M:%SZ')
    card.instanceId = ('manual-%s-%06d-%06d'):format(os.time(), math.random(0, 999999), math.random(0, 999999))
    card.ownerIdentifier = owner
    card.acquiredAt = now
    card.pullId = card.instanceId
    card.acquisitionSource = 'manual_print'
    card.manualPrint = true
    card.printedBy = printedBy
    card.printedByIdentifier = owner
    card.printedAt = now
    if set then card.setId, card.seriesId, card.setName = set.id, set.id, set.name end

    if MetaComic.Inventory.add(source, Config.Items.TradingCard, 1, cardMetadata(card)) ~= true then
        return fail('Could not add the printed card to your inventory (is it full?).')
    end
    MetaComic.Persistence.addCards(owner, { card })
    local catalogPrint = MetaComic.Cards.resolve(card.baseCardId, card.variantId)
    if catalogPrint then requestIcons(source, { catalogPrint }) end -- shared icon must not include the MANUAL PRINT stamp
    return { ok = true, card = card }
end

handlers.createSealed = function(source, payload)
    local allowed, permissionError = requireManage(source)
    if not allowed then return fail(permissionError) end
    if MetaComic.Inventory.name == 'none' then return fail('Creating packs/boxes needs an inventory adapter.') end

    local kind = payload.kind == 'box' and 'box' or 'pack'
    local itemName = kind == 'box' and Config.Items.BoosterBox or Config.Items.BoosterPack
    local set = setById(payload.setId)
    if not set then return fail('Choose a valid card set first.') end
    local setCardCount = MetaComic.Cards.countForSet and MetaComic.Cards.countForSet(set.id) or #(set.cardIds or {})
    if setCardCount < 1 then return fail(('Assign at least one valid card to %s before creating sealed items.'):format(set.name or set.id)) end

    local maxAmount = math.max(1, math.floor(tonumber((Config.Management or {}).MaxCreateAmount) or 100))
    local amount = math.floor(tonumber(payload.amount) or 1)
    if amount < 1 then amount = 1 end
    if amount > maxAmount then amount = maxAmount end

    if MetaComic.Inventory.add(source, itemName, amount, sealedMetadata(kind, set)) ~= true then
        return fail(('Could not add %d %s%s to your inventory.'):format(amount, kind, amount == 1 and '' or 's'))
    end
    return { ok = true, kind = kind, amount = amount, set = set }
end

handlers.openPack = function(source, payload)
    local paid = false
    local setId
    local consumedContext
    local credit = popPackCredit(source)
    if credit then
        setId = credit.setId
        paid = true
    else
        local ok, itemContext = maybeRemoveOpenItem(source, Config.Items.BoosterPack)
        if not ok then return fail(itemContext) end
        consumedContext = itemContext
        paid = Config.Items.RequireForOpen == true
        if Config.Items.RequireForOpen and itemContext and itemContext.metadata then
            setId = metadataSetId(itemContext.metadata)
        elseif not Config.Items.RequireForOpen and canManage(source) and payload and payload.set then
            setId = MetaComic.Sets.resolveId(payload.set)
        else
            setId = MetaComic.Sets.defaultId()
        end
    end

    local owner = MetaComic.Framework.getIdentifier(source)
    local cards, packError, set = MetaComic.Collectables.open('booster_pack', { owner = owner, setId = setId })
    if not cards then
        if consumedContext then MetaComic.Inventory.add(source, Config.Items.BoosterPack, 1, consumedContext.metadata) end
        return fail(packError or 'Could not roll this card set.')
    end
    MetaComic.Persistence.addCards(owner, cards)

    -- card items only for packs that were paid for (free /cardpack test opens don't hand out items)
    if paid then
        queueCardItems(source, cards)
        requestIcons(source, cards) -- drawn + uploaded during the reveal, so the items usually get them straight away
    end

    return { ok = true, cards = cards, set = set }
end

-- Lab / command box opening. Real pack items are only handed out when a real box item was consumed
-- (RequireForOpen = true); otherwise the lab just shows a virtual box with PacksPerBox packs.
handlers.openBox = function(source, payload)
    local packs = MetaComic.Collectables.containerCount('booster_box')
    local setId = MetaComic.Sets.defaultId()
    if not Config.Items.RequireForOpen and canManage(source) and payload and payload.set then
        setId = MetaComic.Sets.resolveId(payload.set) or setId
    end
    local set = setById(setId)
    if not set then return fail('No valid default card set exists.') end

    if not Config.Items.RequireForOpen then
        return { ok = true, packs = packs, addedToInventory = false, set = set }
    end

    local ok, itemContext = maybeRemoveOpenItem(source, Config.Items.BoosterBox)
    if not ok then return fail(itemContext) end
    if itemContext and itemContext.metadata then
        local itemSetId = metadataSetId(itemContext.metadata)
        local itemSet = setById(itemSetId)
        if not itemSet then
            MetaComic.Inventory.add(source, Config.Items.BoosterBox, 1, itemContext.metadata)
            return fail(('This booster box references an unknown card set: %s.'):format(itemSetId))
        end
        set = itemSet
    end
    local given, giveErr = giveBoxPacks(source, packs, set.id)
    if not given then
        MetaComic.Inventory.add(source, Config.Items.BoosterBox, 1, sealedMetadata('box', set)) -- refund the box
        return fail(giveErr)
    end
    return { ok = true, packs = packs, addedToInventory = true, set = set }
end

-- NUI: all cards flipped, or the opening was closed -> hand over the card items
handlers.claimCards = function(source)
    return { ok = true, given = giveCardItems(source) }
end

handlers.getCollection = function(source)
    local owner = MetaComic.Framework.getIdentifier(source)
    return { ok = true, cards = MetaComic.Persistence.getCollection(owner) }
end

local RPC_LATENT_THRESHOLD = 16 * 1024
local RPC_LATENT_BPS = 512 * 1024

local function estimatedRpcResponseBytes(requestId, response)
    local ok, encoded = pcall(json.encode, { requestId = requestId, response = response })
    return ok and type(encoded) == 'string' and #encoded or 0
end

local function sendRpcResult(target, requestId, response)
    -- getCatalog and resolveRemoteAsset can become large too (for example after an
    -- embedded editor image is saved, or when the remote resolver returns image data).
    -- Mirror the client-side large-RPC handling so reopening /cardadmin cannot later
    -- overflow in the opposite direction.
    if estimatedRpcResponseBytes(requestId, response) >= RPC_LATENT_THRESHOLD then
        TriggerLatentClientEvent('meta_comic:client:rpcResult', target, RPC_LATENT_BPS, requestId, response)
    else
        TriggerClientEvent('meta_comic:client:rpcResult', target, requestId, response)
    end
end

RegisterNetEvent('meta_comic:server:rpc', function(requestId, action, payload)
    local source = source
    local handler = handlers[action]
    if not handler then
        sendRpcResult(source, requestId, fail(('Unknown action: %s'):format(tostring(action))))
        return
    end

    local ok, response = pcall(handler, source, payload or {})
    if not ok then
        print(('[meta-comic] RPC %s failed: %s'):format(action, response))
        response = fail('Server error while processing card request.')
    end
    sendRpcResult(source, requestId, response)
end)

-- How item use reaches us (Config.Items.UseMethod):
--   'auto'      (default) both routes below; whichever your item definitions use will work
--   'framework' QBCore / Qbox / custom usable-item callbacks. With ox_inventory on QBCore / Qbox, ox passes item use
--               to these callbacks for items WITHOUT a client export, so it doesn't depend on the resource folder name.
--   'ox_export' ox_inventory item definitions with client = { export = '<resource>.useBoosterPack' } (standalone + ox)
-- Using an item through both routes at once can't double-open: useItem() ignores repeats within 1.2 s.
local method = Config.Items.UseMethod or 'auto'
local frameworkRoute = Config.Items.RegisterUsableItems ~= false and (method == 'auto' or method == 'framework')
local exportRoute = (method == 'auto' and MetaComic.Inventory.name == 'ox_inventory') or method == 'ox_export'

local frameworkRegistered = false
if frameworkRoute then
    local a = MetaComic.Framework.registerUsableItem(Config.Items.BoosterPack, function(source, item) useItem(source, 'pack', item and item.slot, item) end)
    local b = MetaComic.Framework.registerUsableItem(Config.Items.BoosterBox, function(source, item) useItem(source, 'box', item and item.slot, item) end)
    local c = MetaComic.Framework.registerUsableItem(Config.Items.TradingCard, function(source, item)
        -- QBCore passes item.info, ox_inventory / Qbox pass item.metadata
        if item and item.metadata then refreshCardItem(source, item.slot, item.metadata) end
        viewCard(source, item and (item.metadata or item.info))
    end)
    frameworkRegistered = a == true and b == true and c == true
end

local routes = {}
local function useObjectItem(source,slot)
    local item=MetaComic.Inventory.getSlot and MetaComic.Inventory.getSlot(source,tonumber(slot))
    if not item then return end
    local metadata=item.metadata or item.info or {}
    for typeId,names in pairs(objectTypes()) do
        if item.name==names.item and type(metadata.collectibleSnapshot)=='table' then
            return TriggerLatentClientEvent('meta_comic:client:viewCard',source,512*1024,metadata.collectibleSnapshot)
        elseif item.name==names.inner or item.name==names.outer then
            return TriggerClientEvent('meta_comic:client:openCollectible',source,typeId,item.slot,item.name==names.outer)
        end
    end
end
if frameworkRoute then
    for _,names in pairs(objectTypes()) do
        for _,name in pairs(names) do MetaComic.Framework.registerUsableItem(name,function(source,item) useObjectItem(source,item and item.slot) end) end
    end
end
RegisterNetEvent('meta_comic:server:useCollectible',function(slot) useObjectItem(source,slot) end)
if frameworkRegistered then routes[#routes + 1] = 'framework' end
if exportRoute then routes[#routes + 1] = 'ox_export' end
print(('[meta-comic] framework=%s inventory=%s persistence=%s itemUse=%s cardItems=%s cardIcons=%s binder=%s'):format(
    MetaComic.Framework.name, MetaComic.Inventory.name, MetaComic.Persistence.name,
    #routes > 0 and table.concat(routes, '+') or 'NONE', tostring(Config.Items.GiveCardItems),
    (Config.CardIcons and Config.CardIcons.Enabled == false) and 'artwork' or (uploadMode() and (anyFivemanageKey() and 'upload' or 'upload(NO KEY: set metacomic_fivemanage_key)') or 'rarity'),
    type(Config.Items.Binder) == 'table' and table.concat(Config.Items.Binder, ',') or tostring(Config.Items.Binder)))
if MetaComic.Inventory.name == 'none' then
    print('[meta-comic] no inventory adapter: booster pack / box / card items cannot be used. Set Config.Inventory or start your inventory before this resource.')
elseif #routes == 0 then
    print('[meta-comic] no item-use route is active: booster packs / boxes / cards cannot be used from the inventory. Check Config.Items.UseMethod.')
end

-- ox_inventory client export -> here. The server re-checks and removes the item itself, so this can't be abused.
RegisterNetEvent('meta_comic:server:useItem', function(kind, slot)
    local source = source
    if not exportRoute then
        MetaComic.Debug('useItem event ignored: ox_export route is off (Config.Items.UseMethod)')
        return
    end
    if kind == 'card' then
        -- read the card from the player's own slot, so a client can't ask for an arbitrary card
        local item = MetaComic.Inventory.getSlot and MetaComic.Inventory.getSlot(source, tonumber(slot))
        if not item or item.name ~= Config.Items.TradingCard then return end
        refreshCardItem(source, item.slot or tonumber(slot), item.metadata)
        return viewCard(source, item.metadata)
    end
    if kind ~= 'pack' and kind ~= 'box' then return end
    useItem(source, kind, slot)
end)

-- /cardicons: update the card items in your inventory to the current icons, and make any missing catalog icons
local refreshCommand = Config.CardIcons and Config.CardIcons.RefreshCommand
if refreshCommand and refreshCommand ~= '' then
    local function refreshIcons(source)
        if source == 0 then
            iconAttempts = {} -- console: retry prints that failed before, and re-check the saved urls
            print('[meta-comic] checking the saved card icon urls on Fivemanage...')
            return checkIconUrls(function()
                local missing = #missingPrints(true)
                print(('[meta-comic] %d card + rarity icon%s missing; drawing them on the next player with the UI loaded.'):format(missing, missing == 1 and '' or 's'))
                for _, id in ipairs(GetPlayers()) do refreshPlayerItems(tonumber(id)) end
                syncIcons()
            end)
        end
        local updated = refreshPlayerItems(source)
        readyWorkers[source] = true
        syncIcons(source)
        notify(source, ('Updated %d trading card%s.'):format(updated, updated == 1 and '' or 's'), 'success')
    end
    RegisterCommand(refreshCommand,refreshIcons,false)
    if refreshCommand~='collectablesicons' then RegisterCommand('collectablesicons',refreshIcons,false) end
    if refreshCommand~='cardicons' then RegisterCommand('cardicons',refreshIcons,false) end
end

-- Binder item "View Binder" button: send the cards in the binder's pockets, in the binder's own slot order.
local function isBinder(name)
    local binder = Config.Items.Binder
    if type(binder) == 'table' then
        for _, value in ipairs(binder) do if value == name then return true end end
        return false
    end
    return binder ~= nil and binder == name
end

local function binderPayload(source, binderSlot)
    binderSlot = tonumber(binderSlot)
    local item = binderSlot and MetaComic.Inventory.getSlot and MetaComic.Inventory.getSlot(source, binderSlot)
    if not item then return nil, nil, nil, 'That binder is no longer in your inventory.' end
    if not isBinder(item.name) then return nil, nil, nil, 'That item is not a configured trading card binder.' end
    if not MetaComic.Inventory.getContainer then return nil, nil, nil, 'Binders need ox_inventory.' end
    if not (item.metadata and item.metadata.container) then
        return nil, nil, nil, 'This binder has no ox_inventory container.'
    end

    local container = MetaComic.Inventory.getContainer(source, binderSlot)
    if not container then return nil, item, nil, 'Could not open this binder container.' end

    local slots = tonumber(container.slots) or (item.metadata.size and tonumber(item.metadata.size[1])) or (Config.Binder and Config.Binder.DefaultPockets) or 36
    local pockets = {}
    for index, stored in pairs(container.items or {}) do
        if type(stored) == 'table' and stored.name == Config.Items.TradingCard then
            local card = findCard(source, stored.metadata)
            local pocketSlot = tonumber(stored.slot) or tonumber(index)
            if card then pockets[#pockets + 1] = { slot = pocketSlot, card = card } end
            if container.id then refreshCardItem(source, pocketSlot, stored.metadata, container.id) end
        end
    end
    table.sort(pockets, function(a, b) return a.slot < b.slot end)

    local label = (item.metadata and item.metadata.label) or item.label or 'Trading Card Binder'
    return { label = label, slots = slots, pockets = pockets }, item, container
end

-- NUI binder reorder. The client only supplies source/destination pocket numbers; the server uses the binder
-- the player actually opened, revalidates the source card, and either moves it into an empty pocket or swaps
-- it with another trading card in that exact ox_inventory container.
handlers.swapBinderCards = function(source, payload)
    if MetaComic.Inventory.name ~= 'ox_inventory' or not MetaComic.Inventory.swapSlots then
        return fail('Binder card swapping requires ox_inventory.')
    end

    local now = GetGameTimer()
    if lastBinderSwap[source] and now - lastBinderSwap[source] < 250 then return fail('Please wait for the current binder swap.') end
    lastBinderSwap[source] = now

    local active = activeBinder[source]
    if not active then return fail('Open the binder again before rearranging cards.') end

    local fromSlot = math.floor(tonumber(payload and payload.fromSlot) or 0)
    local toSlot = math.floor(tonumber(payload and payload.toSlot) or 0)
    if fromSlot < 1 or toSlot < 1 or fromSlot == toSlot then return fail('Choose a different binder pocket.') end

    local binder, item, container, err = binderPayload(source, active.slot)
    if not binder then
        activeBinder[source] = nil
        return fail(err or 'Could not read this binder.')
    end
    if tostring(item.metadata.container) ~= tostring(active.container) then
        activeBinder[source] = nil
        return fail('That binder changed. Open it again before rearranging cards.')
    end
    if fromSlot > binder.slots or toSlot > binder.slots then return fail('That binder pocket does not exist.') end

    local a = container.items and container.items[fromSlot]
    local b = container.items and container.items[toSlot]
    if type(a) ~= 'table' or a.name ~= Config.Items.TradingCard then
        return fail('The source binder pocket no longer contains that trading card.')
    end
    if b ~= nil and (type(b) ~= 'table' or b.name ~= Config.Items.TradingCard) then
        return fail('Trading cards can only be dropped onto an empty binder pocket or another trading card.')
    end

    local swapped = MetaComic.Inventory.swapSlots(active.container, fromSlot, toSlot)
    if not swapped then return fail(b and 'ox_inventory could not swap those binder slots.' or 'ox_inventory could not move that card to the empty binder slot.') end

    local updated, updatedItem, updatedContainer, refreshErr = binderPayload(source, active.slot)
    if not updated then return fail(refreshErr or 'Cards were swapped, but the binder could not be refreshed.') end
    activeBinder[source] = { slot = active.slot, container = updatedItem.metadata.container }
    return { ok = true, binder = updated }
end

RegisterNetEvent('meta_comic:server:viewBinder', function(slot)
    local source = source
    local now = GetGameTimer()
    if lastBinder[source] and now - lastBinder[source] < 800 then return end
    lastBinder[source] = now

    slot = tonumber(slot)
    local binder, item, container, err = binderPayload(source, slot)
    if not binder then
        if item and not isBinder(item.name) then
            print(('[meta-comic] View Binder used on "%s", which is not in Config.Items.Binder.'):format(tostring(item.name)))
        end
        return notify(source, err or 'Could not open that binder.', 'error')
    end

    activeBinder[source] = { slot = slot, container = item.metadata.container }
    TriggerLatentClientEvent('meta_comic:client:viewBinder', source, 512 * 1024, binder)
end)

-- ox_inventory "Show Card" button -> here, with the slot number. The card is read from the player's own slot.
RegisterNetEvent('meta_comic:server:showCardToOthers', function(slot)
    local source = source
    local item = MetaComic.Inventory.getSlot and MetaComic.Inventory.getSlot(source, tonumber(slot))
    if not item or item.name ~= Config.Items.TradingCard then return end
    showCardToOthers(source, item.metadata)
end)

exports('GetCollection', function(source)
    local owner = MetaComic.Framework.getIdentifier(source)
    return MetaComic.Persistence.getCollection(owner)
end)

exports('OpenPackForPlayer', function(source)
    return handlers.openPack(source, {})
end)

-- Let another resource open a pack on a player's screen (no item needed, e.g. rewards / shops).
exports('GivePackOpening', function(source, setId)
    local set = setById(setId or MetaComic.Sets.defaultId())
    if not set then return false end
    pushPackCredit(source, set.id)
    TriggerClientEvent('meta_comic:client:openPackOverlay', source, set.id, set.name)
    return true
end)
