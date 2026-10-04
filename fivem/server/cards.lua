RushCards.Cards = RushCards.Cards or {}

local resource = GetCurrentResourceName()
local catalog = {}

local function slug(value)
    local text = tostring(value or 'card'):lower()
    text = text:gsub('[^%w]+', '-')
    text = text:gsub('^-+', ''):gsub('-+$', '')
    return text
end

local function loadCatalog()
    local raw = LoadResourceFile(resource, Config.Catalog.File)
    if not raw or raw == '' then
        catalog = {}
        print(('[rush-tradingcards] catalog file missing: %s'):format(Config.Catalog.File))
        return catalog
    end
    local ok, decoded = pcall(json.decode, raw)
    if not ok or type(decoded) ~= 'table' then
        catalog = {}
        print('[rush-tradingcards] catalog.json could not be decoded')
        return catalog
    end
    catalog = decoded
    return catalog
end

local function weightOf(item)
    return math.max(1, tonumber(item.chanceWeight) or 1)
end

local function weightedPick(pool)
    if not pool or #pool == 0 then return nil end
    local total = 0
    for _, item in ipairs(pool) do total = total + weightOf(item) end
    local roll = math.random() * total
    for _, item in ipairs(pool) do
        roll = roll - weightOf(item)
        if roll <= 0 then return item end
    end
    return pool[#pool]
end

local function variantsForTier(card, tier)
    local list = {}
    for _, variant in ipairs(card.variants or {}) do
        if variant.rarityKey == tier then list[#list + 1] = variant end
    end
    return list
end

local function mergeCard(card, variant)
    local resolved = RushCards.CopyTable(card)
    resolved.variants = nil
    for key, value in pairs(variant or {}) do
        if value ~= '' and value ~= nil then
            resolved[key] = type(value) == 'table' and RushCards.CopyTable(value) or value
        end
    end
    resolved.baseCardId = card.id
    resolved.variantId = variant and variant.id or nil
    resolved.variantName = variant and variant.name or 'Standard'
    if not resolved.image or resolved.image == '' then resolved.image = card.image end
    resolved.cardKey = ('%s::%s'):format(card.id or slug(card.title), resolved.variantId or slug(resolved.variantName))
    return resolved
end

local function pullFromTier(tier, fallbacks, sourceCatalog)
    local tiers = { tier }
    for _, value in ipairs(fallbacks or {}) do tiers[#tiers + 1] = value end
    sourceCatalog = sourceCatalog or catalog

    for _, candidate in ipairs(tiers) do
        local basePool = {}
        for _, card in ipairs(sourceCatalog) do
            if #variantsForTier(card, candidate) > 0 then basePool[#basePool + 1] = card end
        end
        if #basePool > 0 then
            local base = weightedPick(basePool)
            local variant = weightedPick(variantsForTier(base, candidate))
            return mergeCard(base, variant)
        end
    end

    local base = weightedPick(sourceCatalog)
    if not base then return nil end
    local variant = weightedPick(base.variants or {})
    return mergeCard(base, variant)
end

local function catalogForSet(setId)
    local set = RushCards.Sets and RushCards.Sets.get(setId)
    if not set then return nil, nil end
    local allowed = {}
    for _, cardId in ipairs(set.cardIds or {}) do allowed[cardId] = true end
    local filtered = {}
    for _, card in ipairs(catalog) do
        if allowed[card.id] then filtered[#filtered + 1] = card end
    end
    return filtered, set
end

function RushCards.Cards.countForSet(setId)
    local filtered, set = catalogForSet(setId)
    return filtered and #filtered or 0, set
end

-- Rebuild a printed card from its base card id + variant id (used when a card item is viewed).
function RushCards.Cards.resolve(baseCardId, variantId)
    for _, card in ipairs(catalog) do
        if card.id == baseCardId then
            for _, variant in ipairs(card.variants or {}) do
                if variant.id == variantId then return mergeCard(card, variant) end
            end
            return mergeCard(card, (card.variants or {})[1])
        end
    end
    return nil
end

-- The card that stands for one base card at one rarity (its first variant of that rarity). Inventory icons are made
-- per base card + rarity, so every variant of the same rarity shares this one's icon.
function RushCards.Cards.forRarity(baseCardId, rarityKey)
    for _, card in ipairs(catalog) do
        if card.id == baseCardId then
            for _, variant in ipairs(card.variants or {}) do
                if variant.rarityKey == rarityKey then return mergeCard(card, variant) end
            end
            return nil
        end
    end
    return nil
end

-- every base card + rarity that exists in the catalog
function RushCards.Cards.rarityPrints()
    local list = {}
    for _, card in ipairs(catalog) do
        local seen = {}
        for _, variant in ipairs(card.variants or {}) do
            local tier = variant.rarityKey or 'common'
            if card.id and not seen[tier] then
                seen[tier] = true
                list[#list + 1] = mergeCard(card, variant)
            end
        end
    end
    return list
end

function RushCards.Cards.reloadCatalog()
    return loadCatalog()
end

function RushCards.Cards.getCatalog()
    return RushCards.CopyTable(catalog)
end

function RushCards.Cards.saveCatalog(cards)
    if type(cards) ~= 'table' then return false, 'catalog must be an array' end
    SaveResourceFile(resource, Config.Catalog.File, json.encode(cards), -1)
    loadCatalog()
    return true
end

function RushCards.Cards.saveCard(card)
    if type(card) ~= 'table' then return false, 'card must be an object' end
    local id = tostring(card.id or '')
    if id == '' then return false, 'card id is required' end
    if type(card.variants) ~= 'table' or #card.variants == 0 then return false, 'card must contain at least one print variant' end

    local nextCatalog = RushCards.CopyTable(catalog)
    local replaced = false
    for index, existing in ipairs(nextCatalog) do
        if tostring(existing.id or '') == id then
            nextCatalog[index] = RushCards.CopyTable(card)
            replaced = true
            break
        end
    end
    if not replaced then nextCatalog[#nextCatalog + 1] = RushCards.CopyTable(card) end

    SaveResourceFile(resource, Config.Catalog.File, json.encode(nextCatalog), -1)
    loadCatalog()
    return true
end

function RushCards.Cards.deleteCard(cardId)
    local id = tostring(cardId or '')
    if id == '' then return false, 'card id is required' end
    if #catalog <= 1 then return false, 'at least one card must remain in the catalog' end

    local nextCatalog, removed = {}, false
    for _, existing in ipairs(catalog) do
        if tostring(existing.id or '') == id then
            removed = true
        else
            nextCatalog[#nextCatalog + 1] = RushCards.CopyTable(existing)
        end
    end
    if not removed then return false, 'card was not found' end

    SaveResourceFile(resource, Config.Catalog.File, json.encode(nextCatalog), -1)
    loadCatalog()
    return true
end

function RushCards.Cards.openPack(owner, setId)
    if setId == nil or tostring(setId) == '' then setId = RushCards.Sets and RushCards.Sets.defaultId() or 'base' end
    local sourceCatalog, set = catalogForSet(setId)
    if not set then return nil, ('Unknown card set: %s'):format(tostring(setId)) end
    if not sourceCatalog or #sourceCatalog == 0 then return nil, ('Card set "%s" has no assigned cards.'):format(set.name or set.id) end

    local rareRoll = math.random() * 100
    local rareTier = rareRoll > 95 and 'legendary' or (rareRoll > 75 and 'ultra_rare' or 'rare')
    local cards = {
        pullFromTier('common', nil, sourceCatalog),
        pullFromTier('common', nil, sourceCatalog),
        pullFromTier('common', nil, sourceCatalog),
        pullFromTier('uncommon', { 'common' }, sourceCatalog),
        pullFromTier(rareTier, { 'rare', 'uncommon', 'common' }, sourceCatalog),
    }

    local result = {}
    for _, card in ipairs(cards) do
        if card then
            card.instanceId = ('%s-%06d-%06d'):format(os.time(), math.random(0, 999999), math.random(0, 999999))
            card.ownerIdentifier = owner
            card.acquiredAt = os.date('!%Y-%m-%dT%H:%M:%SZ')
            card.pullId = card.instanceId
            card.setId = set.id
            card.seriesId = set.id -- alias for servers that call these series rather than sets
            card.setName = set.name
            card.acquisitionSource = 'booster_pack'
            result[#result + 1] = card
        end
    end
    return result, nil, set
end

loadCatalog()
