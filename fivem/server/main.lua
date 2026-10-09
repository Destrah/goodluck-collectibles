math.randomseed(os.time())

-- These are loaded by fxmanifest.lua before this file. An fxmanifest.lua kept from an older version doesn't list
-- them, which crashed here with "attempt to index a nil value (field 'Legacy' / 'Objects')". Say so clearly and
-- keep the trading cards working; coins and plushies stay off until the manifest is updated.
do
    local missing = {}
    if not MetaComic.Legacy then missing[#missing + 1] = 'shared/legacy.lua' end
    if not MetaComic.Collectibles then missing[#missing + 1] = 'shared/collectibles.lua' end
    if not MetaComic.Objects then missing[#missing + 1] = 'server/modules/objects.lua' end
    if not MetaComic.Grading then missing[#missing + 1] = 'server/modules/grading.lua' end
    if #missing > 0 then
        print(('^1[meta-comic] fxmanifest.lua is out of date: %s %s not loaded. Replace fxmanifest.lua with the one from this version (keep your config.lua) and restart the resource.^7')
            :format(table.concat(missing, ', '), #missing == 1 and 'is' or 'are'))
    end
    MetaComic.Legacy = MetaComic.Legacy or {
        prefsKey = 'rush_cards:pack_prefs', uploadConvar = 'rushcards_fivemanage_key',
        manageAce = 'metacomic.manage', catalogAce = 'rushcards.catalog.write',
        fallbackIcon = function(value) return value end,
    }
    MetaComic.Collectibles = MetaComic.Collectibles or { snapshot = function(typeId, item) local copy = MetaComic.CopyTable(item); copy.collectibleType = typeId; return copy end }
end
local function objectTypes() return MetaComic.Objects and MetaComic.Objects.types or {} end
-- (declared up here: printKey / iconCard further down use them) coins and plushies share the card icon pipeline: one icon per definition + print
local OBJECT_ICON_PREFIX = { challenge_coin = 'metacoin', plushie = 'metaplush' }
local function typeOf(card) return MetaComic.Collectibles.typeOf and MetaComic.Collectibles.typeOf(card) or (type(card) == 'table' and card.collectibleType or nil) end
local function objectType(card) local typeId = typeOf(card); return OBJECT_ICON_PREFIX[typeId] and typeId or nil end
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

    if MetaComic.Framework.name == 'ox_core' and MetaComic.Framework.hasGroup then
        local groups = management.OxGroups
        if groups == nil and Config.Management == nil then groups = { admin = 0 } end
        if next(groups or {}) and MetaComic.Framework.hasGroup(source, groups) then return true end
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

MetaComic.CanManageReal = canManage
-- used by server/modules/vending_machines.lua and the other modules; a vending test role (/vendingtestrole) stands in for it
MetaComic.CanManage = function(source)
    local test = MetaComic.VendingTestRole and MetaComic.VendingTestRole(source)
    if test then return test.manage == true end
    return canManage(source)
end

local function requireManage(source)
    if canManage(source) then return true end
    return false, 'You do not have permission to manage trading cards, sets, packs, or boxes.'
end

-- Portal (Config.Portal): which admin UI tabs someone may open, e.g. embedded in a business tablet (GetEmbedUrl) or
-- with /cardportal. Managers get every tab; registered vending machine owners get OwnerTabs, scoped to their own
-- machines by the vending modules; people listed under Editor also get the card editor. Every RPC still checks.
local PORTAL_TABS = { 'editor', 'management', 'vending', 'records', 'crafting', 'minigames', 'pricing' }
local function portalJob(source, jobs)
    local job = MetaComic.Framework.getJob and MetaComic.Framework.getJob(source)
    local configured = job and job.name and type(jobs) == 'table' and jobs[job.name]
    if configured == nil or configured == false then return false end
    local minGrade = type(configured) == 'table' and tonumber(configured.minGrade or configured.grade) or tonumber(configured) or 0
    if type(configured) == 'table' and configured.onDuty == true and job.onDuty ~= true then return false end
    return (tonumber(job.grade) or 0) >= minGrade
end
local function portalEditor(source)
    local portal = Config.Portal or {}
    if portal.Enabled == false or source == 0 then return source == 0 end
    local editor = portal.Editor or {}
    if editor.Ace and editor.Ace ~= '' and IsPlayerAceAllowed(source, editor.Ace) then return true end
    if type(editor.Identifiers) == 'table' and next(editor.Identifiers) then
        local ids = {}
        local frameworkId = MetaComic.Framework.getIdentifier and MetaComic.Framework.getIdentifier(source)
        if frameworkId then ids[tostring(frameworkId)] = true end
        for _, identifier in ipairs(GetPlayerIdentifiers(source) or {}) do ids[tostring(identifier)] = true end
        for _, configured in ipairs(editor.Identifiers) do if ids[tostring(configured)] then return true end end
    end
    return portalJob(source, editor.Jobs)
end
-- the registered owner id when this player owns (leases) vending machines, else nil
local function portalOwnerId(source)
    local Registry = MetaComic.VendingRegistry
    local id = Registry and Registry.identifierOf and Registry.identifierOf(source)
    if not id then return nil end
    if Registry.person and Registry.person(id) then return id end
    for _, record in ipairs(Registry.all and Registry.all() or {}) do
        if (record.owner == id or Registry.osMember and Registry.osMember(record, id)) and record.status ~= 'removed' then return id end
    end
end
MetaComic.Portal = {
    editor = portalEditor,
    -- { manage, owner, editor, tabs = { ... } }; manage follows /vendingtestrole so owners can be tested
    access = function(source)
        local portal = Config.Portal or {}
        local result = { tabs = {} }
        if portal.Enabled == false then return result end
        local allowed = {}
        local function add(tab)
            if tab == 'editor' and Config.Nui.AllowEditor ~= true then return end
            if not allowed[tab] then allowed[tab] = true; result.tabs[#result.tabs + 1] = tab end
        end
        result.manage = MetaComic.CanManage(source) == true
        result.editor = canManage(source) or portalEditor(source)
        if result.manage then
            for _, tab in ipairs(PORTAL_TABS) do add(tab) end
            return result
        end
        result.owner = portalOwnerId(source) ~= nil
        if MetaComic.CardBuyers and #MetaComic.CardBuyers.analysisBuyers(source)>0 then add('pricing') end
        if portalEditor(source) then add('editor') end
        if result.owner then for _, tab in ipairs(portal.OwnerTabs or { 'vending', 'records' }) do add(tostring(tab)) end end
        return result
    end,
}
-- the owner id a non-manager sees `tab` scoped to (nil = not allowed); managers get false (= everything)
function MetaComic.Portal.ownerScope(source, tab)
    local access = MetaComic.Portal.access(source)
    if access.manage then return false end
    for _, allowed in ipairs(access.tabs) do
        if allowed == tab then return portalOwnerId(source) end
    end
    return nil
end
local function requireEdit(source)
    if canManage(source) or portalEditor(source) then return true end
    return false, 'You do not have permission to edit the card catalog.'
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

-- Gives sealed pack / box items of a set (default set when setId is empty). Used by server/modules/vending_machines.lua.
function MetaComic.GiveSealed(source, kind, setId, count)
    count = math.max(1, math.floor(tonumber(count) or 1))
    if MetaComic.Inventory.name == 'none' then return false, 'Buying packs needs an inventory adapter.' end
    local set = setById(setId)
    if not set then return false, ('Unknown card set: %s'):format(tostring(setId)) end
    local item = kind == 'box' and Config.Items.BoosterBox or Config.Items.BoosterPack
    if MetaComic.Inventory.canCarry and not MetaComic.Inventory.canCarry(source, item, count) then
        return false, 'You cannot carry that.'
    end
    if MetaComic.Inventory.add(source, item, count, sealedMetadata(kind, set)) ~= true then
        return false, 'Could not add it to your inventory (is it full?).'
    end
    return true, set
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
-- 'upload': one 100x100 icon per distinct LOOK of a collectible, drawn in a player's NUI and uploaded to Fivemanage
-- (data/card_icons.json remembers them). Prints / variants that look the same share one icon; a different look (full
-- art, another plushie colour, ...) gets its own. Icons of looks that no longer exist in the catalog (deleted, or
-- edited into a new look) are deleted from Fivemanage. Missing icons are made when the resource starts, when a
-- player joins, when the catalog is saved in-game and when a print is pulled; until then the rarity icon is used.
local RARITY_ICONS = { common = true, uncommon = true, rare = true, ultra_rare = true, legendary = true }
local ICON_FILE = 'data/card_icons.json'
local ICON_STYLE = 1 -- bump when cardIcon.js draws differently, so every icon is redrawn
-- Icon key = owner + appearance signature: 'card::<baseCardId>::<sig>' / 'obj::<type>::<definitionId>::<sig>'.
local ICON_FORMAT = 3
local iconUrls = {} -- icon key -> { v = 3, url = <uploaded url>, id = <Fivemanage file id>, file = <ox picture file>, sig, hash }
local legacyIcons = {} -- entries saved by older versions (one per card + rarity / per print): adopted or deleted at start
do
    local raw = LoadResourceFile(resourceName, ICON_FILE)
    local ok, decoded = pcall(function() return raw and json.decode(raw) or nil end)
    if ok and type(decoded) == 'table' then
        for key, value in pairs(decoded) do
            if type(value) == 'table' and value.v == ICON_FORMAT then iconUrls[key] = value
            elseif type(value) == 'table' then legacyIcons[key] = value end
        end
    end
end
local function saveIconFile()
    local out = iconUrls
    if next(legacyIcons) ~= nil then -- not adopted / deleted yet (catalog still loading): keep them in the file
        out = {}
        for key, value in pairs(legacyIcons) do out[key] = value end
        for key, value in pairs(iconUrls) do out[key] = value end
    end
    SaveResourceFile(resourceName, ICON_FILE, json.encode(out), -1)
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


-- Exactly the fields each icon renderer draws (src/utils/cardIcon.js, renderCollectibleIcon in Container3D.js).
-- Only these decide whether two prints share an icon, and only these are sent to the NUI that draws it.
-- starColour: the rarity stars' colour from the print's real pull odds (MetaComic.Cards.starColour), worked out here
local CARD_ICON_FIELDS = { 'title', 'hp', 'accent', 'rarityKey', 'image', 'imagePositionX', 'imagePositionY', 'imageZoom', 'starColour' }
local function iconField(card, field)
    if field == 'collectibleType' then return typeOf(card) end -- older items use the misspelled key
    if field == 'starColour' then
        return card.baseCardId and MetaComic.Cards.starColour and MetaComic.Cards.starColour(card.baseCardId, card.variantId, card.setId) or nil
    end
    return card[field]
end
local OBJECT_ICON_FIELDS = { 'collectibleType', 'title', 'accent', 'image', 'imagePositionX', 'imagePositionY', 'imageZoom',
    'finish', 'finishStrength', 'rimImage', 'edgeImage', 'edgeStyle', 'tint', 'tintStrength', 'stitchColor', 'stitchPattern', 'stitchWidth', 'backImage', 'backColor', 'backColorBlend', 'backStyle', 'plushThickness', 'plushFullness' }

local FIELD_DEFAULTS = { imagePositionX = 50, imagePositionY = 50, imageZoom = 100 }
-- 50, 50.0 and "50" are the same look: item snapshots pass through the inventory's JSON, which may change number types
local function sigValue(value)
    local n = type(value) == 'number' and value or (type(value) == 'string' and value:match('^%-?[%d.]+$') and tonumber(value))
    if n and n == n and n ~= math.huge and n ~= -math.huge then
        return n == math.floor(n) and ('%d'):format(n) or (('%.4f'):format(n):gsub('0+$', ''))
    end
    return tostring(value)
end
local function hashText(text, yielding)
    local h = 5381
    for i = 1, #text, 4096 do
        local bytes = { text:byte(i, math.min(i + 4095, #text)) }
        for j = 1, #bytes do h = (h * 33 + bytes[j]) % 4294967296 end
        if yielding and i % 32768 == 1 then Wait(0) end
    end
    return ('%08x%d'):format(h, #text)
end

-- Artwork saved in the editor can be a multi-MB data: URL. Hashing it in Lua on every lookup made each icon check
-- slow, so long values are hashed once and remembered.
local longValueHashes, longValueCount = {}, 0
local function sigPart(value, yielding)
    if type(value) ~= 'string' or #value <= 512 then return sigValue(value) end
    local cached = longValueHashes[value]
    if cached then return cached end
    if longValueCount >= 512 then longValueHashes, longValueCount = {}, 0 end
    cached = '#' .. hashText(value, yielding)
    longValueHashes[value], longValueCount = cached, longValueCount + 1
    return cached
end

-- everything the icon shows; prints with the same signature share one icon
local function iconSig(card, yielding)
    local parts = { tostring(ICON_STYLE) }
    for _, field in ipairs(objectType(card) and OBJECT_ICON_FIELDS or CARD_ICON_FIELDS) do
        local value = iconField(card, field)
        if value == nil or value == '' then value = FIELD_DEFAULTS[field] end
        parts[#parts + 1] = sigPart(value, yielding)
    end
    return hashText(table.concat(parts, '\31'))
end

-- the signature older versions stored for a card + rarity icon (only used to adopt those uploads once)
local function legacyCardSig(card, yielding)
    return hashText(table.concat({ tostring(ICON_STYLE), tostring(card.title), tostring(card.hp), tostring(card.accent),
        tostring(card.rarityKey), tostring(card.image), tostring(card.imagePositionX or 50), tostring(card.imagePositionY or 50), tostring(card.imageZoom or 100) }, '\31'), yielding)
end

local function printKey(card, yielding)
    if type(card) ~= 'table' then return nil end
    if objectType(card) then
        return ('obj::%s::%s::%s'):format(objectType(card), tostring(card.definitionId or card.id), iconSig(card, yielding))
    end
    return card.baseCardId and ('card::%s::%s'):format(card.baseCardId, iconSig(card, yielding)) or nil
end

-- what the NUI needs to draw an icon (not the whole snapshot: keeps the latent event small)
local function iconCard(card)
    local drawn = {}
    for _, field in ipairs(objectType(card) and OBJECT_ICON_FIELDS or CARD_ICON_FIELDS) do drawn[field] = iconField(card, field) end
    return drawn
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
    local entry = iconUrls[key]
    if not entry then return true end
    if fileMode() and not entry.file and not entry.fileFailed then return true end -- has a url ox would delete, but no picture file yet
    if not entry.url and uploadMode() and fivemanageKey(objectType(card) or 'trading_card') ~= '' then return true end -- its upload was deleted from Fivemanage
    return false
end

local function rarityName(card)
    if objectType(card) then return OBJECT_ICON_PREFIX[objectType(card)] .. '_' .. (RARITY_ICONS[card.rarityKey] and card.rarityKey or 'common') end
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
    -- grading / protection (server/modules/grading.lua): shown in the item's name and description
    local graded = type(card.graded) == 'table' and card.graded or nil
    local protectionNames = { sleeve = 'In a sleeve', toploader = 'In a toploader' }
    if graded then
        prefix = ('GRADED %s %s · '):format(tostring(graded.grade), tostring(graded.name or '')) .. prefix
    elseif protectionNames[card.protection] then
        setPart = setPart .. ' · ' .. protectionNames[card.protection]
    end
    return {
        instanceId = card.instanceId,
        collectibleType = 'trading_card',
        cardSnapshotVersion = 1,
        cardSnapshot = MetaComic.Collectibles.snapshot('trading_card', card),
        cardIconSnapshotSignature = iconSig(card),
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
        protection = graded and 'slab' or card.protection,
        grade = graded and graded.grade or nil,
        label = ('%s (%s)%s%s'):format(card.title or 'Trading Card', card.variantName or 'Standard', manual and ' [Manual Print]' or '', graded and (' [Graded %s]'):format(tostring(graded.grade)) or ''),
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
        -- the icon key comes from the snapshot's own look, so an item only ever shows the icon of how it looks;
        -- when that look's icon was deleted (the card was edited / removed) it falls back to the rarity icon
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
        -- binders and card cases
        local binders = {}
        for _, configured in ipairs({ Config.Items.Binder, Config.Items.CardCase }) do
            for _, name in ipairs(type(configured) == 'table' and configured or { configured }) do binders[#binders + 1] = name end
        end
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
        cb(url, data and data.id and tostring(data.id) or nil)
    end, 'POST', json.encode({ base64 = dataUrl, filename = filename, path = folderFor(typeId).path, retentionExempt = true,
        metadata = json.encode({ card = key, collectibleType = typeId }) }), {
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
            pendingIcons[source][key] = iconSig(card)
            list[#list + 1] = { key = key, card = iconCard(card) }
            keys[#keys + 1] = key
        end
    end
    if #list > 0 then
        TriggerLatentClientEvent('meta_comic:client:renderIcons', source, 512 * 1024, list, (Config.CardIcons and Config.CardIcons.Size) or 100, fileMode() and 'png' or 'webp')
    end
    return keys
end

-- coin / plushie items: the icon of their own snapshot's look (rarity picture until it is uploaded, or once that
-- look no longer exists in the catalog), so older items never borrow an edited print's new look
local function objectIcon(snapshot) return cardIcon(snapshot) end
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

-- after icons were uploaded or deleted: update the items of everyone online. Batched, so a sync of many icons
-- walks the inventories once instead of once per icon.
local refreshQueued = false
local function queueRefreshAll()
    if refreshQueued or not MetaComic.Inventory.slotsOf then return end
    refreshQueued = true
    SetTimeout(1500, function()
        refreshQueued = false
        for _, id in ipairs(GetPlayers()) do refreshPlayerItems(tonumber(id)) end
    end)
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

-- ---------- uploaded artwork on Fivemanage ----------
-- Editor uploads arrive as inline data:image URLs (hundreds of KB each). When a Fivemanage key is set they are
-- stored in Config.FivemanageFolders.artwork and only the short URL is saved, so the database, inventory
-- metadata, pending openings and every NUI reply stay small. Without a key the inline image is kept as before.
local ARTWORK_URLS_FILE = 'data/artwork_urls.json'
local artworkUrls -- content hash -> Fivemanage url: the same picture is never uploaded twice
local function artworkFolder()
    local configured = type(Config.FivemanageFolders) == 'table' and Config.FivemanageFolders.artwork or {}
    return configured.Path or 'Collectibles/Artwork', configured.KeyConvar or 'metacomic_fivemanage_key_artwork'
end
local function artworkKey()
    local _, convar = artworkFolder()
    local own = GetConvar(convar, '')
    return own ~= '' and own or fivemanageKey('trading_card')
end
local function loadArtworkUrls()
    if not artworkUrls then
        local ok, decoded = pcall(json.decode, LoadResourceFile(resourceName, ARTWORK_URLS_FILE) or '')
        artworkUrls = ok and type(decoded) == 'table' and decoded or {}
    end
    return artworkUrls
end
local function uploadArtwork(dataUrl)
    local apiKey = artworkKey()
    if apiKey == '' then return nil end
    loadArtworkUrls()
    local hash = iconHash(dataUrl)
    if artworkUrls[hash] then return artworkUrls[hash] end
    local ext = dataUrl:match('^data:image/(%a+);') or 'png'
    local path = artworkFolder()
    local done = promise.new()
    PerformHttpRequest('https://api.fivemanage.com/api/v3/file/base64', function(status, body)
        local ok, res = pcall(json.decode, body or '')
        local data = ok and type(res) == 'table' and type(res.data) == 'table' and res.data or nil
        if not (data and data.url) then
            print(('[meta-comic] artwork upload failed (HTTP %s): %s'):format(tostring(status), tostring(body):sub(1, 200)))
        end
        done:resolve(data and data.url or nil)
    end, 'POST', json.encode({ base64 = dataUrl, filename = ('art_%s.%s'):format(hash, ext), path = path, retentionExempt = true,
        metadata = json.encode({ kind = 'artwork' }) }), {
        ['Content-Type'] = 'application/json',
        ['Authorization'] = apiKey,
    })
    local url = Citizen.Await(done)
    if url then
        artworkUrls[hash] = url
        SaveResourceFile(resourceName, ARTWORK_URLS_FILE, json.encode(artworkUrls), -1)
    end
    return url
end
MetaComic.UploadArtwork = uploadArtwork -- set logos (server/modules/set_logos.lua) use the same artwork folder

-- Replaces every inline image inside a card / collectible (prints, variants, subject layers...) with its
-- Fivemanage URL. An image that can't be uploaded stays inline, so a save never fails because of Fivemanage.
local function externalizeArtwork(value, depth)
    depth = depth or 0
    if type(value) ~= 'table' or depth > 6 then return value, 0 end
    local count = 0
    for key, entry in pairs(value) do
        if type(entry) == 'string' and #entry > 2048 and entry:sub(1, 11) == 'data:image/' then
            local url = uploadArtwork(entry)
            if url then value[key] = url count = count + 1 end
        elseif type(entry) == 'table' then
            local _, nested = externalizeArtwork(entry, depth + 1)
            count = count + nested
        end
    end
    return value, count
end

local uploadedThisSession = {} -- icon key -> true: never upload the same look twice
local fileWriteFailed = false
local warnedRejected = false

-- ---------- one icon per look: which looks exist, and deleting the uploads of looks that are gone ----------
local readyWorkers = {} -- players whose NUI has loaded (it draws the icons)
local syncRunning, syncAgain, syncPreferred = false, false, nil

local function catalogPrints() -- every card print and every coin / plushie print (looks repeat; keys dedupe them)
    local list = MetaComic.Cards.iconPrints()
    if MetaComic.Objects and MetaComic.Objects.iconPrints then
        for _, print in ipairs(MetaComic.Objects.iconPrints()) do list[#list + 1] = print end
    end
    return list
end

-- icon key -> true for every look in the catalog, plus how many card / object looks there are
local function liveIconKeys()
    local live, cards, objects = {}, 0, 0
    for index, card in ipairs(catalogPrints()) do
        local key = printKey(card, true)
        if key and not live[key] then
            live[key] = true
            if key:sub(1, 5) == 'obj::' then objects = objects + 1 else cards = cards + 1 end
        end
        if index % 10 == 0 then Wait(0) end
    end
    return live, cards, objects
end

-- Fivemanage uploads waiting to be deleted (kept in a file, so a failed delete is retried after a restart)
local ICON_TRASH_FILE = 'data/card_icons_trash.json'
local iconTrash = {}
do
    local raw = LoadResourceFile(resourceName, ICON_TRASH_FILE)
    local ok, decoded = pcall(function() return raw and json.decode(raw) or nil end)
    if ok and type(decoded) == 'table' then iconTrash = decoded end
end
local function saveTrash() SaveResourceFile(resourceName, ICON_TRASH_FILE, json.encode(iconTrash), -1) end

local function urlEncode(text)
    return (text:gsub('[^%w%-%._~]', function(c) return ('%%%02X'):format(c:byte()) end))
end

local function trashUpload(entry, typeId)
    if type(entry) ~= 'table' or not entry.url then return end
    iconTrash[#iconTrash + 1] = { url = entry.url, id = entry.id, typeId = typeId, tries = 0 }
end

-- DELETE /api/v3/file/{file id or storage key}. Uploads made before ids were saved are deleted by their storage key
-- (the url path); 404 means it is already gone.
local trashRunning, warnedDelete = false, false
local function emptyTrash()
    if trashRunning or #iconTrash == 0 then return end
    trashRunning = true
    local inUse = {}
    for _, entry in pairs(iconUrls) do if entry.url then inUse[entry.url] = true end end
    local index = 0
    local function nextItem()
        index = index + 1
        local item = iconTrash[index]
        if not item then
            local kept = {}
            for _, entry in ipairs(iconTrash) do if not entry.done and (entry.tries or 0) < 5 then kept[#kept + 1] = entry end end
            iconTrash = kept
            saveTrash()
            trashRunning = false
            return
        end
        local apiKey = fivemanageKey(item.typeId or 'trading_card')
        if inUse[item.url] then item.done = true return nextItem() end -- a current look uses this upload again: keep it
        if apiKey == '' then item.tries = 5 return nextItem() end -- no API key: nothing can delete it
        local refs = {}
        if item.id then refs[#refs + 1] = urlEncode(item.id) end
        local storageKey = item.url:match('^https?://[^/]+/([^?#]+)')
        if storageKey then refs[#refs + 1] = urlEncode(storageKey) refs[#refs + 1] = storageKey end
        local function attempt(i)
            local ref = refs[i]
            if not ref then
                item.tries = (item.tries or 0) + 1
                if not warnedDelete then
                    warnedDelete = true
                    print(('[meta-comic] could not delete the unused inventory icon %s from Fivemanage (retried on the next restart); delete it on the dashboard if it stays.'):format(item.url))
                end
                return nextItem()
            end
            PerformHttpRequest('https://api.fivemanage.com/api/v3/file/' .. ref, function(status)
                if status == 200 or status == 204 or status == 404 then
                    item.done = true
                    MetaComic.Debug('unused card icon deleted from Fivemanage', item.url)
                    return nextItem()
                end
                attempt(i + 1)
            end, 'DELETE', '', { ['Authorization'] = apiKey })
        end
        attempt(1)
    end
    nextItem()
end

-- Older versions saved one icon per card + rarity ('<baseCardId>::<rarity>') / per coin or plushie print. Icons
-- whose look is exactly a current look are adopted (no new upload); the rest are deleted from Fivemanage.
local function adoptLegacyIcons()
    if next(legacyIcons) == nil then return end
    local prints = catalogPrints()
    if #prints == 0 then return end -- catalog not loaded: try again later rather than deleting everything
    local adopted = 0
    for index, card in ipairs(prints) do
        local key = printKey(card, true)
        local old = card.baseCardId and legacyIcons[('%s::%s'):format(card.baseCardId, card.rarityKey or 'common')]
        if key and not iconUrls[key] and old and old.sig == legacyCardSig(card, true) and (old.url or old.file) then
            iconUrls[key] = { v = ICON_FORMAT, sig = iconSig(card), url = old.url, file = old.file, hash = old.hash }
            adopted = adopted + 1
        end
        if index % 10 == 0 then Wait(0) end
    end
    local inUse, trashed = {}, 0
    for _, entry in pairs(iconUrls) do if entry.url then inUse[entry.url] = true end end
    for key, old in pairs(legacyIcons) do
        if old.url and not inUse[old.url] then inUse[old.url] = true trashUpload(old, keyType(key)) trashed = trashed + 1 end
    end
    legacyIcons = {}
    saveIconFile()
    saveTrash()
    print(('[meta-comic] inventory icons are now made once per look: %d existing icon%s kept, %d older upload%s will be deleted from Fivemanage.')
        :format(adopted, adopted == 1 and '' or 's', trashed, trashed == 1 and '' or 's'))
end

-- Forget (and delete from Fivemanage) the icons of looks that no longer exist: the collectible / variant was deleted,
-- or saved with a different look. Items still showing one fall back to their rarity icon.
local function pruneIcons()
    if not uploadMode() then return 0 end
    local live, cards, objects = liveIconKeys()
    local removed = {}
    for key, entry in pairs(iconUrls) do
        local object = key:sub(1, 5) == 'obj::'
        -- an empty catalog half is far more likely a failed load than everything deleted: keep its icons
        local guarded = (object and (objects == 0 or not MetaComic.Objects)) or (not object and cards == 0)
        if not live[key] and not guarded and not uploading[key] then
            iconUrls[key] = nil
            removed[#removed + 1] = { key = key, entry = entry }
        end
    end
    if #removed == 0 then return 0 end
    local inUse = {}
    for _, entry in pairs(iconUrls) do if entry.url then inUse[entry.url] = true end end
    for _, item in ipairs(removed) do
        local url = item.entry.url
        if url and not inUse[url] then inUse[url] = true trashUpload(item.entry, keyType(item.key)) end
    end
    saveIconFile()
    saveTrash()
    queueRefreshAll()
    emptyTrash()
    MetaComic.Debug(('%d unused inventory icon%s removed'):format(#removed, #removed == 1 and '' or 's'))
    return #removed
end

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
    if not liveIconKeys()[key] then return end -- that look was edited away / deleted while it was being drawn

    local entry = iconUrls[key] or { v = ICON_FORMAT, sig = sig }
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

    if entry.url or fivemanageKey(keyType(key)) == '' or uploadedThisSession[key] then
        queueRefreshAll()
        return
    end

    uploading[key] = true
    uploadedThisSession[key] = true
    uploadIcon(key, sig, dataUrl, function(url, id)
        uploading[key] = nil
        if not url then
            uploadedThisSession[key] = nil
            iconAttempts[key] = (iconAttempts[key] or 0) + 1
            return
        end
        local current = iconUrls[key]
        if not current then -- the look was removed while uploading: don't keep an unused file
            trashUpload({ url = url, id = id }, keyType(key))
            saveTrash()
            return emptyTrash()
        end
        current.url, current.id = url, id
        saveIconFile()
        MetaComic.Debug('card icon uploaded', key, url)
        if not imageUrlAccepted(url) and not warnedRejected and not fileMode() then
            warnedRejected = true
            print(('[meta-comic] ox_inventory will delete the uploaded icon url (%s): add its host to the convar inventory:validhosts.'):format(url))
        end
        queueRefreshAll()
    end)
end)

-- ---------- keep every look's icon uploaded ----------
local function missingPrints(includeFailed)
    local list, seen = {}, {}
    for index, card in ipairs(catalogPrints()) do
        local key = printKey(card, true)
        if key and not seen[key] then
            seen[key] = true
            if needsIcon(card) and (includeFailed or (not uploading[key] and (iconAttempts[key] or 0) < MAX_ATTEMPTS)) then list[#list + 1] = card end
        end
        if index % 10 == 0 then Wait(0) end
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
-- One HEAD request per url, one at a time. Network errors and refusals (403: rate limit / firewall) keep the url;
-- only "not found" removes it, so a hiccup can't make every icon upload again.
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
                uploadedThisSession = {} -- those looks may be uploaded again
                saveIconFile()
                print(('[meta-comic] card icons: %d saved Fivemanage url%s no longer exist%s; uploading %s again.'):format(
                    removed, removed == 1 and '' or 's', removed == 1 and 's' or '', removed == 1 and 'it' or 'them'))
            end
            if done then done(removed) end
            return
        end
        PerformHttpRequest(url, function(status)
            if status == 404 or status == 410 then
                for _, entry in pairs(iconUrls) do
                    if entry.url == url then entry.url, entry.id, entry.hash = nil, nil, nil removed = removed + 1 end
                end
            end
            nextUrl()
        end, 'HEAD', '', {})
    end
    nextUrl()
end

local function syncIcons(preferred)
    if not uploadMode() then return end
    if preferred then syncPreferred = preferred end
    syncAgain = true
    if syncRunning then return end
    syncRunning = true
    CreateThread(function()
        local done = 0
        while syncAgain do
            syncAgain = false
            adoptLegacyIcons() -- only does something once, after an update
            pruneIcons() -- deleted collectibles / looks saved away from: their icons go first
            local missing = iconsPossible() and missingPrints() or {}
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
            print(('[meta-comic] card icons: %d requested, %d icon%s still missing%s.'):format(done, left, left == 1 and '' or 's',
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

-- On start: adopt / delete icons saved by older versions, delete icons of looks that are gone, drop saved urls
-- whose file was deleted from Fivemanage, then redraw + re-upload those looks.
CreateThread(function()
    Wait(2000)
    if not uploadMode() then return end
    adoptLegacyIcons()
    pruneIcons()
    emptyTrash()
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

-- ---------- card condition, wear and protection (server/modules/grading.lua) ----------
local Grading = MetaComic.Grading
local gradingConfig = Config.Grading or {}
local lastViewed = {} -- source -> { slot, instanceId }: the card item the player is looking at (rough handling)

-- Writes a changed copy (condition / protection / grade) back onto its card item in the player's inventory.
local function saveCardItem(source, slot, metadata, card)
    if not MetaComic.Inventory.setMetadata or not slot then return false end
    local updated = MetaComic.CopyTable(metadata or {})
    for key, value in pairs(cardMetadata(card)) do
        if key ~= 'imageurl' and key ~= 'image' and key ~= 'cardIconSnapshotSignature' then updated[key] = value end
    end
    MetaComic.Inventory.setMetadata(source, tonumber(slot), updated)
    return true
end

-- The card on an item, with a condition (items made before conditions existed get one now) and, when handled,
-- a roll for wear. Returns the card and whether it changed (and was saved).
local function handleCardItem(source, slot, metadata, handling)
    local card = findCard(source, metadata)
    if not card then return nil end
    if not Grading then return card, false end
    local changed = false
    if type(card.condition) ~= 'table' then card.condition = Grading.generate() changed = true end
    if handling and gradingConfig.Wear ~= false then
        local worn = Grading.applyWear(card.condition, card.graded and 'slab' or card.protection, handling == 'rough')
        if worn ~= card.condition then card.condition = worn changed = true end
    end
    if changed then saveCardItem(source, slot, metadata, card) end
    return card, changed
end

local function viewCard(source, metadata, slot)
    if type(metadata) ~= 'table' then return notify(source, 'This card has no card data.', 'error') end
    local card = slot and handleCardItem(source, slot, metadata, 'view') or findCard(source, metadata)
    if not card then return notify(source, 'That card is no longer in the catalog.', 'error') end
    lastViewed[source] = slot and { slot = tonumber(slot), instanceId = card.instanceId } or nil
    TriggerLatentClientEvent('meta_comic:client:viewCard', source, 512 * 1024, card)
end

-- "Show Card" button: show a card from your inventory to the players standing near you.
local lastShow = {}
local lastBinder = {} -- throttle opening
local activeBinder = {} -- source -> { slot = player inventory slot, container = ox container id }
local lastBinderSwap = {}
-- shown: a card or a coin / plushie snapshot (the viewer renders either); kind: what the shower holds up
local function showToNearby(source, card, kind)
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
    local noun = kind == 'coin' and 'coin' or kind == 'plush' and 'plushie' or 'card'
    if shown == 0 then
        notify(source, ('Nobody is close enough to see your %s.'):format(noun), 'error')
    else
        notify(source, ('Showing %s to %d player%s.'):format(card.title or ('your ' .. noun), shown, shown == 1 and '' or 's'), 'success')
        TriggerClientEvent('meta_comic:client:showingCollectible', source, kind, (Config.ShowCard and Config.ShowCard.Seconds) or 8)
    end
end
local function throttledShow(source)
    local now = GetGameTimer()
    if lastShow[source] and now - lastShow[source] < 2000 then return false end
    lastShow[source] = now
    return true
end
local function showCardToOthers(source, metadata, slot)
    if not throttledShow(source) then return end
    local card = slot and handleCardItem(source, slot, metadata, 'view') or findCard(source, metadata) -- handling it can wear it
    if not card then return notify(source, 'That card has no card data.', 'error') end
    showToNearby(source, card, 'card')
end

-- Called when a player uses a booster pack / booster box item (framework usable item or ox_inventory client export).
local pendingBoxes, claimBox = {}, nil -- booster box items waiting for their 3D opening to finish
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
        local count = MetaComic.Collectibles.containerCount('booster_box')
        if not MetaComic.Inventory.has(source, expected, 1) then return notify(source, 'You do not have a booster box.', 'error') end
        if pendingBoxes[source] then claimBox(source) end -- an earlier box whose opening never reported back
        -- the 3D opening plays first; the box is swapped for its packs when it ends (or after a minute regardless)
        local job = { slot = slot, metadata = metadata, set = set, count = count }
        pendingBoxes[source] = job
        SetTimeout(60000, function() if pendingBoxes[source] == job then claimBox(source) end end)
        TriggerClientEvent('meta_comic:client:boxOpened', source, count, set.id, set.name)
    end
end

-- booster box item: take the box and give its packs once the 3D opening has played
claimBox = function(source)
    local job = pendingBoxes[source]
    pendingBoxes[source] = nil
    if not job then return end
    local expected, set = Config.Items.BoosterBox, job.set
    if not MetaComic.Inventory.has(source, expected, 1) then return notify(source, 'You do not have a booster box.', 'error') end
    if not takeOne(source, expected, job.metadata, job.slot) then return notify(source, 'Could not open the booster box.', 'error') end
    local ok, err = giveBoxPacks(source, job.count, set.id)
    if not ok then
        MetaComic.Inventory.add(source, expected, 1, sealedMetadata('box', set)) -- refund the exact set box
        return notify(source, err, 'error')
    end
    notify(source, ('You opened a %s booster box: +%d %s packs.'):format(set.name, job.count, set.name), 'success')
end
RegisterNetEvent('meta_comic:server:boxClaim', function() claimBox(source) end)
AddEventHandler('playerDropped', function() pendingBoxes[source] = nil end) -- the box stays in the inventory

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
MetaComic.RpcHandlers = handlers -- server/modules add their own NUI actions here (vending machine map)

handlers.getCollectibles = function(source)
    if not MetaComic.Objects then return fail('Coins and plushies are off: update fxmanifest.lua (see the server console).') end
    return {ok=true,data=MetaComic.Objects.get(source)}
end
handlers.saveCollectible = function(source,payload)
    local allowed,err=requireManage(source);if not allowed then return fail(err) end
    if not MetaComic.Objects then return fail('Coins and plushies are off: update fxmanifest.lua (see the server console).') end
    if payload.kind == 'definition' then externalizeArtwork(payload.value) end
    MetaComic.Objects.save(payload)
    if MetaComic.Objects.afterSave then MetaComic.Objects.afterSave(source) end
    -- No catalogue echo: every definition's artwork plus every pulled copy in the inventory made the reply
    -- several MB of latent traffic per save. The editor already holds the saved state.
    return {ok=true}
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
handlers.printCollectible = function(source,payload)
    local allowed,err=requireManage(source);if not allowed then return fail(err) end
    if MetaComic.Inventory.name=='none' then return fail('Manual printing needs an inventory adapter.') end
    if not MetaComic.Objects then return fail('Coins and plushies are off: update fxmanifest.lua (see the server console).') end
    local printer={identifier=MetaComic.Framework.getIdentifier(source),name=MetaComic.Framework.getName and MetaComic.Framework.getName(source) or GetPlayerName(source)}
    local snapshot=MetaComic.Objects.printManual(source,payload,printer)
    return {ok=true,instanceId=snapshot.instanceId}
end

-- ---------- card grading: a player inspects one of their raw cards and marks its flaws ----------
-- Every mark is checked here against the card's real condition (nothing that isn't there can be marked); the
-- grade on the slab is made of what the grader found, so a careless grader can over-grade by missing flaws.
local gradingSessions, lastRough = {}, {}
local function cardItemAt(source, slot)
    local item = slot and MetaComic.Inventory.getSlot and MetaComic.Inventory.getSlot(source, tonumber(slot))
    if item and item.name == Config.Items.TradingCard then return item end
end
local function gradingAllowed(source)
    if not Grading or gradingConfig.Enabled == false then return false, 'Card grading is turned off.' end
    if type(gradingConfig.Ace) == 'string' and gradingConfig.Ace ~= '' and not IsPlayerAceAllowed(source, gradingConfig.Ace) then return false, 'You are not a certified card grader.' end
    return true
end
local function maxWrongMarks() return math.max(1, math.floor(tonumber(gradingConfig.MaxWrongMarks) or 6)) end
-- how far (in grades) a grader may put the slab's grade from what their confirmed calls suggest
local function gradeAdjust() return math.max(0, tonumber(gradingConfig.GradeAdjust) or 1) end

handlers.startGrading = function(source, payload)
    local allowed, err = gradingAllowed(source)
    if not allowed then return fail(err) end
    local slot = tonumber(payload and payload.slot)
    local item = cardItemAt(source, slot)
    if not item then return fail('Choose a trading card from your inventory.') end
    local card = handleCardItem(source, slot, item.metadata or item.info)
    if not card then return fail('That card has no card data.') end
    if card.graded then return fail('That card is already graded and slabbed.') end
    local slabItem = gradingConfig.SlabItem or 'grading_slab'
    if gradingConfig.RequireSlabItem ~= false and not MetaComic.Inventory.has(source, slabItem, 1) then return fail('You need an empty grading slab to grade a card.') end
    local id = ('grade-%d-%d'):format(os.time(), math.random(100000, 999999))
    gradingSessions[source] = { id = id, slot = slot, instanceId = card.instanceId, flaws = Grading.listFlaws(card.condition, Grading.flawOptions(card)), found = {}, foundCount = 0, wrong = 0, calls = {} }
    local reference = MetaComic.CopyTable(card) -- compare with this acquired print, including historical edits
    if reference then reference.condition, reference.protection, reference.graded = nil, nil, nil end
    return { ok = true, sessionId = id, card = card, reference = reference, maxWrong = maxWrongMarks(), gradeAdjust = gradeAdjust(),
        debug = gradingConfig.Debug == true, debugFlaws = gradingConfig.Debug == true and gradingSessions[source].flaws or nil }
end

handlers.gradingMark = function(source, payload)
    local session = gradingSessions[source]
    if not session or session.id ~= (payload and payload.sessionId) then return fail('This grading session has ended.') end
    if session.wrong >= maxWrongMarks() then return fail('Too many wrong calls: submit your grade or cancel.') end
    local mark = type(payload.mark) == 'table' and payload.mark or {}
    local flaw = Grading.matchMark(session.flaws, { type = tostring(mark.type or ''), side = mark.side, textPart = mark.textPart, x = tonumber(mark.x), y = tonumber(mark.y) }, session.found)
    if flaw then
        session.found[flaw.id] = true
        session.foundCount = session.foundCount + 1
        -- kept for the grading record: what the grader called and where they clicked
        session.calls[#session.calls + 1] = { type = flaw.type, side = flaw.side, label = flaw.label, deduction = flaw.deduction, x = tonumber(mark.x), y = tonumber(mark.y) }
        return { ok = true, confirmed = true, flaw = { id = flaw.id, type = flaw.type, side = flaw.side, label = flaw.label, deduction = flaw.deduction }, found = session.foundCount }
    end
    session.wrong = session.wrong + 1
    return { ok = true, confirmed = false, wrong = session.wrong, maxWrong = maxWrongMarks() }
end

handlers.gradingSubmit = function(source, payload)
    local session = gradingSessions[source]
    if not session or session.id ~= (payload and payload.sessionId) then return fail('This grading session has ended.') end
    local item = cardItemAt(source, session.slot)
    local metadata = item and (item.metadata or item.info)
    local card = metadata and findCard(source, metadata)
    if not card or card.graded or (session.instanceId and card.instanceId ~= session.instanceId) then
        gradingSessions[source] = nil
        return fail('The card was moved or changed: grading cancelled.')
    end
    if gradingConfig.RequireSlabItem ~= false and not MetaComic.Inventory.remove(source, gradingConfig.SlabItem or 'grading_slab', 1) then
        return fail('You need an empty grading slab to grade a card.')
    end
    -- the grader's final pick, within GradeAdjust of what their confirmed calls suggest
    local suggested = Grading.gradeFromFound(session.flaws, session.found)
    local grade = Grading.allowedGrade(payload.grade, suggested, gradeAdjust())
    card.graded = {
        grade = grade, name = Grading.GRADE_NAMES[grade] or '', cert = Grading.newCert(), gradedAt = os.date('!%Y-%m-%dT%H:%M:%SZ'), found = session.foundCount,
        grader = MetaComic.Framework.getName and MetaComic.Framework.getName(source) or GetPlayerName(source), graderId = MetaComic.Framework.getIdentifier(source),
    }
    card.protection = 'slab'
    saveCardItem(source, session.slot, metadata, card)
    -- the public record: anyone can look the cert up (/gradecheck) and see the grade and the grader's calls
    Grading.saveRecord({
        cert = card.graded.cert, grade = grade, name = card.graded.name, suggested = suggested, grader = card.graded.grader, gradedAt = card.graded.gradedAt,
        title = card.title, variantName = card.variantName, setName = card.setName, baseCardId = card.baseCardId, variantId = card.variantId,
        condition = card.condition, marks = session.calls,
    })
    gradingSessions[source] = nil
    return { ok = true, card = card, grade = grade }
end

handlers.gradingCancel = function(source)
    gradingSessions[source] = nil
    return { ok = true }
end

-- cert lookup: the record plus the print to draw it on (the catalogue print, with the copy's condition laid over)
handlers.gradingRecord = function(source, payload)
    if not Grading then return fail('Card grading is turned off.') end
    local record = Grading.getRecord(payload and payload.cert)
    if not record then return { ok = true, record = nil } end
    local card = MetaComic.Cards.resolve(record.baseCardId, record.variantId)
    if card then card.condition = record.condition end
    return { ok = true, record = record, card = card }
end

-- expected copies per pack of every print ("baseCardId::variantId"), for the card stars' tooltip and colour
handlers.getPrintOdds = function()
    local bySet={}
    for _,set in ipairs(MetaComic.Sets.getAll()) do bySet[set.id]=MetaComic.Cards.printOdds(set.id) end
    return { ok = true, odds = MetaComic.Cards.printOdds(), bySet = bySet }
end

-- other resources (e.g. a grading business) can read a record too
exports('GetGradingRecord', function(cert) return Grading and Grading.getRecord(cert) or nil end)

-- item buttons: put a card in a penny sleeve / toploader, or take it out (the outer layer comes back as an item)
handlers.protectCard = function(source, payload)
    if not Grading then return fail('Card protection is unavailable.') end
    local slot = tonumber(payload and payload.slot)
    local item = cardItemAt(source, slot)
    if not item then return fail('Choose a trading card from your inventory.') end
    local metadata = item.metadata or item.info
    local card = handleCardItem(source, slot, metadata)
    if not card then return fail('That card has no card data.') end
    if card.graded then return fail('Graded cards stay sealed in their slab.') end
    local items = { sleeve = gradingConfig.SleeveItem or 'card_sleeve', toploader = gradingConfig.ToploaderItem or 'card_toploader' }
    local nouns = { sleeve = 'card sleeve', toploader = 'toploader' }
    local current, want = card.protection or 'none', payload.kind
    if want == 'sleeve' or want == 'toploader' then
        if current == want or (want == 'sleeve' and current == 'toploader') then return fail('That card is already protected.') end
        if not MetaComic.Inventory.remove(source, items[want], 1) then return fail(('You need a %s.'):format(nouns[want])) end
        card.sleeved = (want == 'toploader' and current == 'sleeve') or nil
        card.protection = want
    elseif want == 'none' then
        if not items[current] then return fail('That card is not in a sleeve or toploader.') end
        MetaComic.Inventory.add(source, items[current], 1)
        card.protection = (current == 'toploader' and card.sleeved) and 'sleeve' or 'none'
        card.sleeved = nil
    else
        return fail('Unknown protection.')
    end
    local fresh = cardItemAt(source, slot)
    saveCardItem(source, slot, fresh and (fresh.metadata or fresh.info) or metadata, card)
    return { ok = true, protection = card.protection }
end

-- the NUI saw the player spin / flip their own card hard in the viewer: unprotected cards can crease, bend or tear
handlers.roughHandling = function(source)
    local viewed = lastViewed[source]
    if not viewed or not Grading or gradingConfig.Wear == false then return { ok = true } end
    local now = GetGameTimer()
    if lastRough[source] and now - lastRough[source] < 4000 then return { ok = true } end
    lastRough[source] = now
    local item = cardItemAt(source, viewed.slot)
    local metadata = item and (item.metadata or item.info)
    local current = metadata and findCard(source, metadata)
    if not current or (viewed.instanceId and current.instanceId ~= viewed.instanceId) then return { ok = true } end
    local card, changed = handleCardItem(source, viewed.slot, metadata, 'rough')
    return { ok = true, card = changed and card or nil }
end

AddEventHandler('playerDropped', function()
    gradingSessions[source], lastRough[source], lastViewed[source] = nil, nil, nil
end)

handlers.getRuntimeInfo = function(source)
    local management = canManage(source)
    local capabilities = MetaComic.CopyTable(MetaComic.RuntimeInfo.capabilities or {})
    capabilities.management = management
    local editor = management or portalEditor(source)
    capabilities.editor = editor and Config.Nui.AllowEditor == true
    capabilities.catalogWrite = editor and Config.Catalog.AllowWrite == true
    capabilities.portal = MetaComic.Portal.access(source)
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

-- Served from memory: every catalog/set write goes through this resource, so the cache is always current.
-- (Re-reading the four definition tables on each UI open cost a 300+ ms server hitch.) After editing the
-- tables by hand, run 'collectiblesreload' in the server console.
-- The persistence adapter's load while the resource script is starting can come back empty (e.g. the database
-- resource still connecting); this used to be hidden by re-reading on every UI open. Load once more from a real
-- thread after startup, and again on the first catalog request if that still hasn't worked.
local definitionsLoaded = MetaComic.Persistence.reloadDefinitions == nil
local function loadDefinitions()
    if definitionsLoaded then return true end
    local ok, err = MetaComic.Persistence.reloadDefinitions()
    if not ok then
        print('[meta-comic] could not load the card catalog from the database: ' .. tostring(err))
        return false, err
    end
    MetaComic.Cards.reloadCatalog()
    MetaComic.Sets.reload()
    definitionsLoaded = true
    print(('[meta-comic] card catalog loaded: %d cards, %d sets.'):format(#MetaComic.Cards.getCatalog(), #MetaComic.Sets.getAll()))
    return true
end
CreateThread(function() Wait(0) loadDefinitions() end)

handlers.getCatalog = function()
    local ok, err = loadDefinitions()
    if not ok then return fail(tostring(err)) end
    return { ok = true, cards = MetaComic.Cards.getCatalog(), sets = MetaComic.Sets.getAll() }
end

-- Moves artwork that was saved inline (before uploads went to Fivemanage) to Fivemanage, then saves the URLs.
RegisterCommand('collectiblesartwork', function(source)
    if source ~= 0 then return notify(source, 'Run collectiblesartwork from the server console.', 'error') end
    if artworkKey() == '' then return print('[meta-comic] set metacomic_fivemanage_key_artwork (or metacomic_fivemanage_key) in server.cfg first.') end
    CreateThread(function()
        local cards, cardCount = externalizeArtwork(MetaComic.Cards.getCatalog())
        if cardCount > 0 then
            local ok, err = MetaComic.Cards.saveCatalog(cards)
            if not ok then return print('[meta-comic] could not save the card catalog: ' .. tostring(err)) end
        end
        local objectCount = 0
        for _, item in ipairs(MetaComic.Objects and MetaComic.CopyTable(MetaComic.Objects.data.definitions) or {}) do
            local _, moved = externalizeArtwork(item)
            if moved > 0 then MetaComic.Objects.save({ kind = 'definition', value = item }) objectCount = objectCount + moved end
        end
        print(('[meta-comic] artwork moved to Fivemanage: %d card image%s, %d coin / plushie image%s. Copies already pulled keep their own picture.'):format(
            cardCount, cardCount == 1 and '' or 's', objectCount, objectCount == 1 and '' or 's'))
        if cardCount + objectCount > 0 then syncIcons() end
    end)
end, true)

-- ---------- legacy artwork: downscale every saved image and store it on Fivemanage ----------
-- Old cards / collectibles keep full-size artwork inline (data: URLs in the catalog) or on other hosts (fetched
-- through this server and sent to the NUI as base64), which is what makes /cardadmin slow to load them. The server
-- can't resize images, so a player's NUI does it (like the inventory icons); the server uploads the result.
local optimizeJobs, optimizeRunning, optimizeSerial = {}, false, 0
local FIVEMANAGE_HOSTS = { ['r2.fivemanage.com'] = true, ['i.fmfile.com'] = true }
local function onFivemanage(url)
    local host = (url:match('^https?://([^/%?#:]+)') or ''):lower()
    if FIVEMANAGE_HOSTS[host] then return true end
    for _, saved in pairs(loadArtworkUrls()) do if saved == url then return true end end -- custom CDN domain
    return false
end
-- every image string in a card / collectible (prints, variants, subject layers...), deduped by value
local function collectArtwork(value, found, order, depth)
    if type(value) ~= 'table' or depth > 6 then return end
    for key, entry in pairs(value) do
        if type(entry) == 'string' and not found[entry] then
            local name = tostring(key):lower()
            local inline = entry:sub(1, 11) == 'data:image/' and #entry > 2048
            local remote = entry:match('^https?://') and (name:find('image') or name:find('mask') or name:find('art'))
            if inline or remote then
                found[entry] = true
                -- already on Fivemanage: only replaced when downscaling makes it smaller
                order[#order + 1] = { src = entry, lossless = name:find('mask') ~= nil, onlyIfSmaller = not inline and onFivemanage(entry) }
            end
        elseif type(entry) == 'table' then
            collectArtwork(entry, found, order, depth + 1)
        end
    end
end
local function replaceArtwork(value, urls, depth)
    if type(value) ~= 'table' or depth > 6 then return 0 end
    local count = 0
    for key, entry in pairs(value) do
        if type(entry) == 'string' and urls[entry] then value[key] = urls[entry] count = count + 1
        elseif type(entry) == 'table' then count = count + replaceArtwork(entry, urls, depth + 1) end
    end
    return count
end

RegisterNetEvent('meta_comic:server:optimizedArtwork', function(id, dataUrl)
    local job = type(id) == 'string' and optimizeJobs[id]
    if not job or job.worker ~= source then return end -- only images we asked this player for
    optimizeJobs[id] = nil
    if type(dataUrl) ~= 'string' or #dataUrl > 8 * 1024 * 1024 or not dataUrl:match('^data:image/[%w%+%.%-]+;base64,') then dataUrl = '' end
    job.promise:resolve(dataUrl)
end)

local function optimizeArtwork(requestedBy)
    local function report(message, notifyType)
        print('[meta-comic] ' .. message)
        if requestedBy then notify(requestedBy, message, notifyType or 'inform') end
    end
    if optimizeRunning then return report('Artwork optimization is already running.', 'error') end
    if artworkKey() == '' then return report('Set metacomic_fivemanage_key_artwork (or metacomic_fivemanage_key) in server.cfg first.', 'error') end
    optimizeRunning = true
    CreateThread(function()
        local ok, err = pcall(function()
            assert(loadDefinitions())
            loadArtworkUrls() -- lets onFivemanage recognise uploads on a custom CDN domain
            local found, order = {}, {}
            collectArtwork(MetaComic.Cards.getCatalog(), found, order, 0)
            if MetaComic.Objects then collectArtwork(MetaComic.Objects.data.definitions, found, order, 0) end
            if #order == 0 then return report('No artwork to optimize.') end
            report(('Optimizing %d image%s: downscaling in a player\'s game UI, then uploading to Fivemanage...'):format(#order, #order == 1 and '' or 's'))
            local urls, moved, kept, failed = {}, 0, 0, 0
            for index, entry in ipairs(order) do
                local worker = requestedBy and readyWorkers[requestedBy] and GetPlayerName(requestedBy) and requestedBy or pickWorker()
                if not worker then failed = failed + #order - index + 1 report('No player with the game UI loaded is online to downscale the images; the rest are left as they are.', 'error') break end
                optimizeSerial = optimizeSerial + 1
                local id = ('art-%d-%d'):format(os.time(), optimizeSerial)
                local job = { worker = worker, promise = promise.new() }
                optimizeJobs[id] = job
                TriggerLatentClientEvent('meta_comic:client:optimizeArtwork', worker, 1024 * 1024, id, entry.src,
                    { maxEdge = 1024, quality = 0.85, lossless = entry.lossless, onlyIfSmaller = entry.onlyIfSmaller })
                SetTimeout(120000, function() if optimizeJobs[id] then optimizeJobs[id] = nil job.promise:resolve(nil) end end)
                local dataUrl = Citizen.Await(job.promise)
                if dataUrl == '' and entry.onlyIfSmaller then kept = kept + 1
                elseif not dataUrl or dataUrl == '' then failed = failed + 1
                else
                    local url = uploadArtwork(dataUrl)
                    if url then urls[entry.src] = url moved = moved + 1 else failed = failed + 1 end
                end
                if index % 10 == 0 then print(('[meta-comic] artwork: %d / %d done'):format(index, #order)) end
            end
            if moved == 0 then return report(('Artwork: nothing changed (%d already small, %d could not be loaded).'):format(kept, failed)) end
            -- applied to the current catalog (not the one read at the start), so edits made meanwhile are kept
            local cards = MetaComic.CopyTable(MetaComic.Cards.getCatalog())
            local cardChanges = replaceArtwork(cards, urls, 0)
            if cardChanges > 0 then
                freezeOnlineItems()
                local saved, saveErr = MetaComic.Cards.saveCatalog(cards)
                if not saved then error('could not save the card catalog: ' .. tostring(saveErr)) end
            end
            local objectChanges = 0
            for _, item in ipairs(MetaComic.Objects and MetaComic.CopyTable(MetaComic.Objects.data.definitions) or {}) do
                local changed = replaceArtwork(item, urls, 0)
                if changed > 0 then MetaComic.Objects.save({ kind = 'definition', value = item }) objectChanges = objectChanges + changed end
            end
            report(('Artwork optimized: %d image%s downscaled and moved to Fivemanage (%d card, %d coin / plushie field%s), %d already small, %d could not be loaded. Copies already pulled keep their own picture.'):format(
                moved, moved == 1 and '' or 's', cardChanges, objectChanges, objectChanges == 1 and '' or 's', kept, failed), 'success')
            syncIcons(requestedBy) -- the artwork url is part of each print's look, so its inventory icon is drawn again
        end)
        optimizeRunning = false
        if not ok then report('Artwork optimization failed: ' .. tostring(err), 'error') end
    end)
end
-- Console, or in game by a card manager (whose game UI then does the downscaling).
RegisterCommand('collectiblesoptimizeart', function(source)
    if source ~= 0 and not canManage(source) then return notify(source, 'You are not allowed to use this command.', 'error') end
    optimizeArtwork(source ~= 0 and source or nil)
end, false)

RegisterCommand('collectiblesreload', function(source)
    if source ~= 0 then return notify(source, 'Run collectiblesreload from the server console.', 'error') end
    if not MetaComic.Persistence.reloadDefinitions then return print('[meta-comic] nothing to reload: definitions are not stored in a database.') end
    local ok, err = MetaComic.Persistence.reloadDefinitions()
    if not ok then return print('[meta-comic] reload failed: ' .. tostring(err)) end
    MetaComic.Cards.reloadCatalog()
    MetaComic.Sets.reload()
    print('[meta-comic] card catalog and sets reloaded from the database.')
end, true)

-- Explicit recovery only; never automatically resurrect intentionally deleted definitions.
local function restoreSeed(source)
    if source ~= 0 then return notify(source, 'Run collectiblesrestoreseed from the server console.', 'error') end
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
RegisterCommand('collectiblesrestoreseed',restoreSeed,true)
RegisterCommand('cardrestoreseed',restoreSeed,true)

RegisterCommand('collectiblessample',function(source,args)
    local allowed,err=requireManage(source)
    if not allowed then return notify(source,err,'error') end
    if not Config.Catalog.AllowWrite then return notify(source,'Catalog writes are disabled in config.lua','error') end
    CreateThread(function()
        local function report(message)
            print('[meta-comic] '..message)
            if source~=0 and GetPlayerName(source) then notify(source,message,'inform') end
        end
        local ok,result=pcall(MetaComic.SampleCards.generate,{
            refreshArt=args[1]=='refreshart',
            hasKey=function() return artworkKey()~='' end,upload=uploadArtwork,report=report,
            freeze=freezeOnlineItems,sync=function() syncIcons(source~=0 and source or nil) end,
        })
        if not ok then report('Sample generation stopped: '..tostring(result)) end
    end)
end,false)

handlers.saveCatalog = function(source, payload)
    local allowed, permissionError = requireEdit(source)
    if not allowed then return fail(permissionError) end
    if not Config.Catalog.AllowWrite then return fail('FiveM catalog write is disabled in config.lua') end
    freezeOnlineItems()
    externalizeArtwork(payload.cards)
    local ok, err = MetaComic.Cards.saveCatalog(payload.cards)
    if not ok then return fail(err or 'Could not save catalog') end
    syncIcons(source) -- new / changed prints get their inventory icon drawn (by this player) and uploaded
    return { ok = true }
end

handlers.saveCard = function(source, payload)
    local allowed, permissionError = requireEdit(source)
    if not allowed then return fail(permissionError) end
    if not Config.Catalog.AllowWrite then return fail('FiveM catalog write is disabled in config.lua') end
    freezeOnlineItems()
    externalizeArtwork(payload.card)
    local ok, err = MetaComic.Cards.saveCard(payload.card)
    if not ok then return fail(err or 'Could not save card') end
    syncIcons(source)
    return { ok = true, cardId = payload.card and payload.card.id or nil }
end

handlers.deleteCard = function(source, payload)
    local allowed, permissionError = requireEdit(source)
    if not allowed then return fail(permissionError) end
    if not Config.Catalog.AllowWrite then return fail('FiveM catalog write is disabled in config.lua') end
    freezeOnlineItems()
    local ok, err = MetaComic.Cards.deleteCard(payload.cardId)
    if not ok then return fail(err or 'Could not delete card') end
    syncIcons(source) -- the deleted card's icons are removed from Fivemanage
    return { ok = true, cardId = payload.cardId }
end

-- card sets for the NUI, each with its logo (server/modules/set_logos.lua)
local function setsWithLogos()
    local list = MetaComic.Sets.getAll()
    local logos = MetaComic.SetLogos and MetaComic.SetLogos.all('trading_card') or {}
    for _, set in ipairs(list) do set.logo = logos[set.id] end
    return list
end

handlers.getSets = function()
    -- NUI requests sets alongside the catalog at boot. Do not return an empty
    -- startup cache before persisted definitions/memberships have been loaded.
    local ok, err = loadDefinitions()
    if not ok then return fail(tostring(err)) end
    return { ok = true, sets = setsWithLogos(), defaultSet = MetaComic.Sets.defaultId() }
end

handlers.saveSets = function(source, payload)
    local allowed, permissionError = requireManage(source)
    if not allowed then return fail(permissionError) end
    local logos = {}
    for _, set in ipairs(type(payload.sets) == 'table' and payload.sets or {}) do
        if type(set) == 'table' and set.id ~= nil then logos[tostring(set.id)] = set.logo; set.logo = nil end
    end
    local ok, err = MetaComic.Sets.save(payload.sets)
    if not ok then return fail(err or 'Could not save card sets') end
    if MetaComic.SetLogos then
        local saved, logoError = pcall(MetaComic.SetLogos.replaceKind, 'trading_card', logos, uploadArtwork)
        if not saved then return fail('Sets saved, but not their logos: ' .. tostring(logoError)) end
    end
    return { ok = true, sets = setsWithLogos() }
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
    if MetaComic.Grading then card.condition = MetaComic.Grading.generate() end
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
    local cards, packError, set = MetaComic.Collectibles.open('booster_pack', { owner = owner, setId = setId })
    if not cards then
        if consumedContext then MetaComic.Inventory.add(source, Config.Items.BoosterPack, 1, consumedContext.metadata) end
        return fail(packError or 'Could not roll this card set.')
    end
    -- the collection record is written on its own thread so the pack opens without waiting for the database
    local record = MetaComic.CopyTable(cards)
    CreateThread(function()
        local ok, err = pcall(MetaComic.Persistence.addCards, owner, record)
        if not ok then print(('[meta-comic] could not record the opened cards for %s: %s'):format(tostring(owner), tostring(err))) end
    end)

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
    local packs = MetaComic.Collectibles.containerCount('booster_box')
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
        local fresh = item and item.slot and MetaComic.Inventory.getSlot and MetaComic.Inventory.getSlot(source, item.slot)
        viewCard(source, fresh and fresh.metadata or (item and (item.metadata or item.info)), item and item.slot)
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
            -- the sealed container's look travels with the event so the UI can show it before the server's roll returns
            local container=type(metadata.containerSnapshot)=='table' and metadata.containerSnapshot or (MetaComic.Objects.data.containers or {})[typeId]
            return TriggerClientEvent('meta_comic:client:openCollectible',source,typeId,item.slot,item.name==names.outer,container)
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
        local fresh = MetaComic.Inventory.getSlot(source, item.slot or tonumber(slot)) or item
        return viewCard(source, fresh.metadata, item.slot or tonumber(slot))
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
                print(('[meta-comic] %d inventory icon%s missing; drawing them on the next player with the UI loaded.'):format(missing, missing == 1 and '' or 's'))
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
    if refreshCommand~='collectiblesicons' then RegisterCommand('collectiblesicons',refreshIcons,false) end
    if refreshCommand~='cardicons' then RegisterCommand('cardicons',refreshIcons,false) end
end

-- Binder item "View Binder" button: send the cards in the binder's pockets, in the binder's own slot order.
local function isItem(configured, name)
    if type(configured) == 'table' then
        for _, value in ipairs(configured) do if value == name then return true end end
        return false
    end
    return configured ~= nil and configured == name
end
local function isBinder(name) return isItem(Config.Items.Binder, name) end
-- card holders: binders (sleeve pages) and card cases (upright rows, any card incl. slabs); both are ox containers
local function holderKind(name)
    if isBinder(name) then return 'binder' end
    if isItem(Config.Items.CardCase, name) then return 'case' end
    return nil
end

-- The trading cards in the player's own inventory, for the binder's card hand (slot order).
local function binderHand(source)
    local hand = {}
    if not MetaComic.Inventory.slotsOf then return hand end
    for _, stored in pairs(MetaComic.Inventory.slotsOf(source, Config.Items.TradingCard) or {}) do
        local card = type(stored) == 'table' and stored.slot and findCard(source, stored.metadata)
        if card then hand[#hand + 1] = { slot = tonumber(stored.slot), card = card } end
    end
    table.sort(hand, function(a, b) return a.slot < b.slot end)
    return hand
end

local function binderPayload(source, binderSlot)
    binderSlot = tonumber(binderSlot)
    local item = binderSlot and MetaComic.Inventory.getSlot and MetaComic.Inventory.getSlot(source, binderSlot)
    if not item then return nil, nil, nil, 'That binder is no longer in your inventory.' end
    local kind = holderKind(item.name)
    if not kind then return nil, nil, nil, 'That item is not a configured trading card binder or card case.' end
    if not MetaComic.Inventory.getContainer then return nil, nil, nil, 'Binders need ox_inventory.' end
    if not (item.metadata and item.metadata.container) then
        return nil, nil, nil, 'This binder has no ox_inventory container.'
    end

    local container = MetaComic.Inventory.getContainer(source, binderSlot)
    if not container then return nil, item, nil, 'Could not open this binder container.' end

    local fallback = kind == 'case' and (Config.CardCase and Config.CardCase.DefaultSlots or 48) or (Config.Binder and Config.Binder.DefaultPockets) or 36
    local slots = tonumber(container.slots) or (item.metadata.size and tonumber(item.metadata.size[1])) or fallback
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

    local label = (item.metadata and item.metadata.label) or item.label or (kind == 'case' and 'Card Case' or 'Trading Card Binder')
    return { kind = kind, style = kind == 'case' and Config.CardCase and Config.CardCase.Style or nil, label = label, slots = slots, pockets = pockets, hand = binderHand(source) }, item, container
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

-- The binder the player has open, checked again for every move (it may have been moved or dropped since).
local function openBinder(source)
    if MetaComic.Inventory.name ~= 'ox_inventory' or not MetaComic.Inventory.moveSlot then
        return nil, 'Moving cards in and out of binders requires ox_inventory.'
    end
    local now = GetGameTimer()
    if lastBinderSwap[source] and now - lastBinderSwap[source] < 250 then return nil, 'Please wait for the current binder move.' end
    lastBinderSwap[source] = now
    local active = activeBinder[source]
    if not active then return nil, 'Open the binder again before moving cards.' end
    local binder, item, container, err = binderPayload(source, active.slot)
    if not binder or tostring(item.metadata.container) ~= tostring(active.container) then
        activeBinder[source] = nil
        return nil, err or 'That binder changed. Open it again before moving cards.'
    end
    return binder, item, container, active
end

-- Card hand -> binder pocket. The client names the inventory slot and the (empty) pocket; the server checks the
-- slot really holds a trading card and the pocket is empty, then moves that exact item into the binder container.
handlers.binderStoreCard = function(source, payload)
    local binder, item, container, active = openBinder(source)
    if not binder then return fail(item) end
    local fromSlot = math.floor(tonumber(payload and payload.invSlot) or 0)
    local toSlot = math.floor(tonumber(payload and payload.toSlot) or 0)
    if toSlot < 1 or toSlot > binder.slots then return fail('That binder pocket does not exist.') end
    if fromSlot == tonumber(active.slot) then return fail('A binder cannot go inside itself.') end
    local card = MetaComic.Inventory.getSlot(source, fromSlot)
    if type(card) ~= 'table' or card.name ~= Config.Items.TradingCard then return fail('That card is no longer in your inventory.') end
    -- sleeved and toploaded cards fit a binder pocket; a graded slab does not (a card case holds anything)
    local meta = type(card.metadata) == 'table' and card.metadata or {}
    if binder.kind == 'binder' and (meta.protection == 'slab' or (type(meta.cardSnapshot) == 'table' and meta.cardSnapshot.graded)) then
        return fail('A graded slab is too big for a binder pocket.')
    end
    if container.items and container.items[toSlot] ~= nil then return fail('That pocket already holds a card. Drop it on an empty pocket.') end

    local moved, why = MetaComic.Inventory.moveSlot(source, fromSlot, active.container, toSlot)
    if not moved then return fail(why == 'full' and 'The binder has no room for that card.' or 'Could not put that card in the binder.') end
    local updated = binderPayload(source, active.slot)
    return { ok = true, binder = updated }
end

-- Binder pocket -> card hand: only when the player's inventory has room for it.
handlers.binderTakeCard = function(source, payload)
    local binder, item, container, active = openBinder(source)
    if not binder then return fail(item) end
    local fromSlot = math.floor(tonumber(payload and payload.fromSlot) or 0)
    local stored = container.items and container.items[fromSlot]
    if type(stored) ~= 'table' or stored.name ~= Config.Items.TradingCard then return fail('That pocket no longer holds a trading card.') end

    local moved, why = MetaComic.Inventory.moveSlot(active.container, fromSlot, source, nil)
    if not moved then return fail(why == 'full' and 'Your inventory has no room for that card.' or 'Could not take that card out of the binder.') end
    local updated = binderPayload(source, active.slot)
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
        if item and not holderKind(item.name) then
            print(('[meta-comic] View Binder / View Case used on "%s", which is not in Config.Items.Binder or Config.Items.CardCase.'):format(tostring(item.name)))
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
    showCardToOthers(source, item.metadata, item.slot or tonumber(slot))
end)

-- ox_inventory "Show" button on a challenge coin / plushie: its own snapshot, read from the player's own slot.
RegisterNetEvent('meta_comic:server:showCollectibleToOthers', function(slot)
    local source = source
    local item = MetaComic.Inventory.getSlot and MetaComic.Inventory.getSlot(source, tonumber(slot))
    if not item then return end
    local metadata = item.metadata or item.info or {}
    for typeId, names in pairs(objectTypes()) do
        if item.name == names.item then
            if type(metadata.collectibleSnapshot) ~= 'table' then return notify(source, 'That item has no collectible data.', 'error') end
            if not throttledShow(source) then return end
            return showToNearby(source, metadata.collectibleSnapshot, typeId == 'challenge_coin' and 'coin' or 'plush')
        end
    end
end)

exports('GetCollection', function(source)
    local owner = MetaComic.Framework.getIdentifier(source)
    return MetaComic.Persistence.getCollection(owner)
end)

exports('OpenPackForPlayer', function(source)
    return handlers.openPack(source, {})
end)

-- Admin UI for other scripts: exports['<resource>']:OpenAdmin(source, tab). The client asks the server again before
-- showing it, so a player without management permission only gets the usual "no permission" message.
exports('CanManage', function(source) return canManage(tonumber(source)) == true end)
exports('OpenAdmin', function(source, tab)
    source = tonumber(source)
    if not source or not canManage(source) then return false end
    TriggerClientEvent('meta_comic:client:openAdmin', source, type(tab) == 'string' and tab or nil)
    return true
end)
-- Sealed booster packs / boxes of a set: exports['<resource>']:GiveSealed(source, 'pack' | 'box', setId, count)
exports('GiveSealed', function(source, kind, setId, count) return MetaComic.GiveSealed(tonumber(source), kind == 'box' and 'box' or 'pack', setId, count) end)

-- Let another resource open a pack on a player's screen (no item needed, e.g. rewards / shops).
exports('GivePackOpening', function(source, setId)
    local set = setById(setId or MetaComic.Sets.defaultId())
    if not set then return false end
    pushPackCredit(source, set.id)
    TriggerClientEvent('meta_comic:client:openPackOverlay', source, set.id, set.name)
    return true
end)
