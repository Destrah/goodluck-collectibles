MetaComic.Cards = MetaComic.Cards or {}

local resource = GetCurrentResourceName()
local catalog = {}

local function slug(value)
    local text = tostring(value or 'card'):lower()
    text = text:gsub('[^%w]+', '-')
    text = text:gsub('^-+', ''):gsub('-+$', '')
    return text
end

local function loadCatalog()
    local decoded
    if MetaComic.Persistence.name == 'mysql' then
        decoded = MetaComic.Persistence.loadCatalog(Config.Catalog.File)
    else
        local raw = LoadResourceFile(resource, Config.Catalog.File)
        if not raw or raw == '' then
            catalog = {}
            print(('[meta-comic] catalog file missing: %s'):format(Config.Catalog.File))
            return catalog
        end
        local ok
        ok, decoded = pcall(json.decode, raw)
        if not ok or type(decoded) ~= 'table' then
            catalog = {}
            print('[meta-comic] catalog.json could not be decoded')
            return catalog
        end
    end
    catalog = decoded
    -- Move legacy base framing into prints without rewriting the saved catalog on load.
    for _, card in ipairs(catalog) do
        for _, variant in ipairs(card.variants or {}) do
            local image = tostring(variant.image or ''):match('^%s*(.-)%s*$')
            local baseImage = tostring(card.image or ''):match('^%s*(.-)%s*$')
            local separateArt = image ~= '' and image ~= baseImage
            for key, default in pairs({ imagePositionX = 50, imagePositionY = 50, imageZoom = 100 }) do
                variant[key] = tonumber(variant[key]) or (not separateArt and tonumber(card[key])) or default
            end
        end
        card.imagePositionX, card.imagePositionY, card.imageZoom = nil, nil, nil
    end
    MetaComic.Cards.oddsCache, MetaComic.Cards.oddsBest, MetaComic.Cards.oddsBySet = nil, nil, nil
    return catalog
end

local function persistCatalog(cards)
    if MetaComic.Persistence.name == 'mysql' then
        local ok, err = MetaComic.Persistence.saveCatalog(cards)
        if ok and MetaComic.Sets and MetaComic.Sets.reload then MetaComic.Sets.reload() end
        return ok, err
    end
    if not SaveResourceFile(resource, Config.Catalog.File, json.encode(cards), -1) then
        return false, 'Could not save catalog JSON file'
    end
    return true
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
    local resolved = MetaComic.CopyTable(card)
    resolved.variants = nil
    for key, value in pairs(variant or {}) do
        if value ~= '' and value ~= nil then
            resolved[key] = type(value) == 'table' and MetaComic.CopyTable(value) or value
        end
    end
    resolved.baseCardId = card.id
    resolved.variantId = variant and variant.id or nil
    resolved.variantName = variant and variant.name or 'Standard'
    if not resolved.image or resolved.image == '' then resolved.image = card.image end
    resolved.cardKey = ('%s::%s'):format(card.id or slug(card.title), resolved.variantId or slug(resolved.variantName))
    return resolved
end

local PACK_CHAINS = {
    common = { 'common', 'uncommon', 'rare', 'ultra_rare', 'legendary' },
    uncommon = { 'uncommon', 'rare', 'ultra_rare', 'legendary', 'common' },
    rare = { 'rare', 'ultra_rare', 'legendary', 'uncommon', 'common' },
    ultra_rare = { 'ultra_rare', 'rare', 'legendary', 'uncommon', 'common' },
    legendary = { 'legendary', 'ultra_rare', 'rare', 'uncommon', 'common' },
}
local function pullFromTier(tier, fallbacks, sourceCatalog)
    local tiers = PACK_CHAINS[tier] or { tier }
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
    local set = MetaComic.Sets and MetaComic.Sets.get(setId)
    if not set then return nil, nil end
    local allowed = {}
    for _, cardId in ipairs(set.cardIds or {}) do allowed[cardId] = true end
    local filtered = {}
    for _, card in ipairs(catalog) do
        if allowed[card.id] then filtered[#filtered + 1] = card end
    end
    return filtered, set
end

function MetaComic.Cards.countForSet(setId)
    local filtered, set = catalogForSet(setId)
    return filtered and #filtered or 0, set
end

-- Rebuild a printed card from its base card id + variant id (used when a card item is viewed).
function MetaComic.Cards.resolve(baseCardId, variantId)
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
function MetaComic.Cards.forRarity(baseCardId, rarityKey)
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
function MetaComic.Cards.rarityPrints()
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

-- every print of every card, for the inventory icon pipeline (prints that look the same share one icon there)
function MetaComic.Cards.iconPrints()
    local list = {}
    for _, card in ipairs(catalog) do
        if card.id then
            for _, variant in ipairs(card.variants or {}) do list[#list + 1] = mergeCard(card, variant) end
        end
    end
    -- Stars use set-specific odds. A pulled print can have a different icon signature
    -- from its global-catalog look even when its artwork was never edited. Include
    -- those looks so rendering accepts them and pruning does not delete their icons.
    for _, set in ipairs(MetaComic.Sets and MetaComic.Sets.getAll() or {}) do
        local members = catalogForSet(set.id)
        for _, card in ipairs(members or {}) do
            for _, variant in ipairs(card.variants or {}) do
                local print = mergeCard(card, variant)
                print.setId = set.id
                list[#list + 1] = print
            end
        end
    end
    return list
end

-- How rare each print really is: expected copies per booster pack over the whole catalogue (mirrors
-- src/utils/printOdds.js computePrintOdds). Used for the colour of the rarity stars on inventory icons.
local PACK_SLOTS = {
    { 3, PACK_CHAINS.common }, { 1, PACK_CHAINS.uncommon },
    { 0.75, PACK_CHAINS.rare }, { 0.2, PACK_CHAINS.ultra_rare }, { 0.05, PACK_CHAINS.legendary },
}
local function oddsWeight(value) return math.max(1, tonumber(value) or 1) end
function MetaComic.Cards.printOdds(setId)
    local sourceCatalog, signature, setKey = catalog, nil, nil
    local set = setId and MetaComic.Sets and MetaComic.Sets.get(setId)
    if set then
        setKey=tostring(setId);signature=table.concat(set.cardIds or {},'\0')
        MetaComic.Cards.oddsBySet=MetaComic.Cards.oddsBySet or {}
        local cached=MetaComic.Cards.oddsBySet[setKey]
        if cached and cached.signature==signature then return cached.odds end
        sourceCatalog=catalogForSet(setId)
    elseif MetaComic.Cards.oddsCache then return MetaComic.Cards.oddsCache end
    local pools, order = {}, {} -- tier -> { [cardId] = { card = card, variants = { ... } } }
    for _, card in ipairs(sourceCatalog or {}) do
        for _, variant in ipairs(card.variants or {}) do
            local tier = variant.rarityKey or 'common'
            pools[tier] = pools[tier] or {}
            if not pools[tier][card.id] then pools[tier][card.id] = { card = card, variants = {} }; order[tier] = (order[tier] or 0) + 1 end
            table.insert(pools[tier][card.id].variants, variant)
        end
    end
    local share = {}
    for _, slot in ipairs(PACK_SLOTS) do
        for _, tier in ipairs(slot[2]) do
            if order[tier] then share[tier] = (share[tier] or 0) + slot[1] break end
        end
    end
    local odds = {}
    for tier, bases in pairs(pools) do
        local draws = share[tier] or 0
        if draws > 0 then
            local baseTotal = 0
            for _, entry in pairs(bases) do baseTotal = baseTotal + oddsWeight(entry.card.chanceWeight) end
            for id, entry in pairs(bases) do
                local variantTotal = 0
                for _, variant in ipairs(entry.variants) do variantTotal = variantTotal + oddsWeight(variant.chanceWeight) end
                for _, variant in ipairs(entry.variants) do
                    odds[('%s::%s'):format(id, variant.id)] = draws * oddsWeight(entry.card.chanceWeight) / baseTotal * oddsWeight(variant.chanceWeight) / variantTotal
                end
            end
        end
    end
    if setKey then MetaComic.Cards.oddsBySet[setKey]={signature=signature,odds=odds}
    else MetaComic.Cards.oddsCache = odds end
    return odds
end
-- Slot distributions use the same tier fallbacks and weighted base/variant picks as openPack.
function MetaComic.Cards.packDistribution(setId)
    local sourceCatalog,set=catalogForSet(setId)
    if not set or not sourceCatalog or #sourceCatalog==0 then return nil end
    local function tierDistribution(chain)
        for _,tier in ipairs(chain) do
            local bases,total={},0
            for _,card in ipairs(sourceCatalog) do
                local variants=variantsForTier(card,tier)
                if #variants>0 then bases[#bases+1]={card=card,variants=variants};total=total+weightOf(card) end
            end
            if #bases>0 then
                local result={}
                for _,base in ipairs(bases) do
                    local variantTotal=0;for _,v in ipairs(base.variants) do variantTotal=variantTotal+weightOf(v) end
                    for _,v in ipairs(base.variants) do
                        local card=mergeCard(base.card,v);card.setId=set.id
                        result[#result+1]={card=card,chance=weightOf(base.card)/total*weightOf(v)/variantTotal}
                    end
                end
                return result,tier
            end
        end
        return {},nil
    end
    local common,commonTier=tierDistribution(PACK_CHAINS.common)
    local uncommon,uncommonTier=tierDistribution(PACK_CHAINS.uncommon)
    local rare,seen={},{}
    for _,entry in ipairs({{.75,'rare'},{.2,'ultra_rare'},{.05,'legendary'}}) do
        local pool=tierDistribution(PACK_CHAINS[entry[2]])
        for _,outcome in ipairs(pool) do
            local key=outcome.card.cardKey
            if not seen[key] then seen[key]={card=outcome.card,chance=0};rare[#rare+1]=seen[key] end
            seen[key].chance=seen[key].chance+entry[1]*outcome.chance
        end
    end
    return {{count=3,label='Common slots',tier=commonTier,outcomes=common},{count=1,label='Uncommon-or-higher slot',tier=uncommonTier,outcomes=uncommon},
        {count=1,label='Rare-or-higher slot',outcomes=rare}}
end
-- star colour by how many times rarer than the catalogue's commonest print this one is (same bands as
-- printOdds.js ODDS_COLOURS: relative, since a big catalogue makes every print rare in absolute terms)
local ODDS_COLOURS = { { 2, '#d6dde8' }, { 6, '#4ade80' }, { 20, '#38bdf8' }, { 80, '#a78bfa' }, { 300, '#fbbf24' }, { math.huge, '#ff4d6d' } }
local bestByOdds = setmetatable({}, { __mode = 'k' })
function MetaComic.Cards.starColour(baseCardId, variantId, setId)
    local all = MetaComic.Cards.printOdds(setId)
    local odds = all[('%s::%s'):format(tostring(baseCardId), tostring(variantId))]
    if not odds or odds <= 0 then return nil end
    local best = bestByOdds[all]
    if not best then
        best = 0
        for _, value in pairs(all) do if value > best then best = value end end
        bestByOdds[all] = best
    end
    for _, band in ipairs(ODDS_COLOURS) do if best / odds <= band[1] then return band[2] end end
end

function MetaComic.Cards.reloadCatalog()
    return loadCatalog()
end

function MetaComic.Cards.getCatalog()
    return MetaComic.CopyTable(catalog)
end

function MetaComic.Cards.saveCatalog(cards)
    if type(cards) ~= 'table' then return false, 'catalog must be an array' end
    local ok, err = persistCatalog(cards)
    if not ok then return false, err end
    loadCatalog()
    return true
end

function MetaComic.Cards.saveCard(card)
    if type(card) ~= 'table' then return false, 'card must be an object' end
    local id = tostring(card.id or '')
    if id == '' then return false, 'card id is required' end
    if type(card.variants) ~= 'table' or #card.variants == 0 then return false, 'card must contain at least one print variant' end

    if MetaComic.Persistence.name == 'mysql' and MetaComic.Persistence.saveCard then
        local ok, err = MetaComic.Persistence.saveCard(card)
        if ok then
            loadCatalog()
            MetaComic.Sets.reload()
        end
        return ok, err
    end

    local nextCatalog = MetaComic.CopyTable(catalog)
    local replaced = false
    for index, existing in ipairs(nextCatalog) do
        if tostring(existing.id or '') == id then
            nextCatalog[index] = MetaComic.CopyTable(card)
            replaced = true
            break
        end
    end
    if not replaced then nextCatalog[#nextCatalog + 1] = MetaComic.CopyTable(card) end

    local ok, err = persistCatalog(nextCatalog)
    if not ok then return false, err end
    loadCatalog()
    return true
end

function MetaComic.Cards.deleteCard(cardId)
    local id = tostring(cardId or '')
    if id == '' then return false, 'card id is required' end
    if MetaComic.Persistence.name == 'mysql' and MetaComic.Persistence.deleteCard then
        local ok, err = MetaComic.Persistence.deleteCard(id)
        if ok then
            loadCatalog()
            MetaComic.Sets.reload()
        end
        return ok, err
    end
    if #catalog <= 1 then return false, 'at least one card must remain in the catalog' end

    local nextCatalog, removed = {}, false
    for _, existing in ipairs(catalog) do
        if tostring(existing.id or '') == id then
            removed = true
        else
            nextCatalog[#nextCatalog + 1] = MetaComic.CopyTable(existing)
        end
    end
    if not removed then return false, 'card was not found' end

    local ok, err = persistCatalog(nextCatalog)
    if not ok then return false, err end
    loadCatalog()
    return true
end

function MetaComic.Cards.openPack(owner, setId)
    if setId == nil or tostring(setId) == '' then setId = MetaComic.Sets and MetaComic.Sets.defaultId() or 'base' end
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
            -- this copy's print imperfections (server/modules/grading.lua): what grading looks for
            if MetaComic.Grading then card.condition = MetaComic.Grading.generate() end
            result[#result + 1] = card
        end
    end
    return result, nil, set
end

loadCatalog()
