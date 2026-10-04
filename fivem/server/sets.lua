RushCards.Sets = RushCards.Sets or {}

local resource = GetCurrentResourceName()
local sets = {}

local function slug(value)
    local text = tostring(value or 'set'):lower()
    text = text:gsub('[^%w]+', '-')
    text = text:gsub('^-+', ''):gsub('-+$', '')
    return text ~= '' and text or 'set'
end

local function normalizeSet(input, index)
    input = type(input) == 'table' and input or {}
    local id = slug(input.id or input.code or input.name or ('set-' .. tostring(index or 1)))
    local name = tostring(input.name or id)
    local code = tostring(input.code or id):upper():gsub('[^%w%-_]', '')
    if code == '' then code = id:upper() end

    local seen, cardIds = {}, {}
    for _, cardId in ipairs(type(input.cardIds) == 'table' and input.cardIds or {}) do
        cardId = tostring(cardId or '')
        if cardId ~= '' and not seen[cardId] then
            seen[cardId] = true
            cardIds[#cardIds + 1] = cardId
        end
    end

    return {
        id = id,
        name = name,
        code = code,
        description = tostring(input.description or ''),
        cardIds = cardIds,
    }
end

local function loadSets()
    local fileName = (Config.Sets and Config.Sets.File) or 'data/sets.json'
    local raw = LoadResourceFile(resource, fileName)
    if not raw or raw == '' then
        sets = {}
        print(('[rush-tradingcards] sets file missing: %s'):format(fileName))
        return sets
    end

    local ok, decoded = pcall(json.decode, raw)
    if not ok or type(decoded) ~= 'table' then
        sets = {}
        print('[rush-tradingcards] sets.json could not be decoded')
        return sets
    end

    local normalized, used = {}, {}
    for index, item in ipairs(decoded) do
        local set = normalizeSet(item, index)
        if not used[set.id] then
            used[set.id] = true
            normalized[#normalized + 1] = set
        end
    end
    sets = normalized
    return sets
end

local function saveSets(list)
    local fileName = (Config.Sets and Config.Sets.File) or 'data/sets.json'
    SaveResourceFile(resource, fileName, json.encode(list), -1)
end

function RushCards.Sets.reload()
    return loadSets()
end

function RushCards.Sets.getAll()
    return RushCards.CopyTable(sets)
end

function RushCards.Sets.get(id)
    id = tostring(id or '')
    for _, set in ipairs(sets) do
        if set.id == id then return RushCards.CopyTable(set) end
    end
    return nil
end

function RushCards.Sets.defaultId()
    return tostring((Config.Sets and Config.Sets.Default) or 'base')
end

function RushCards.Sets.resolveId(id)
    local requested = tostring(id or '')
    if requested ~= '' and RushCards.Sets.get(requested) then return requested end
    local fallback = RushCards.Sets.defaultId()
    if RushCards.Sets.get(fallback) then return fallback end
    return sets[1] and sets[1].id or nil
end

function RushCards.Sets.cardAllowed(setId, cardId)
    local set = RushCards.Sets.get(setId)
    if not set then return false end
    for _, allowed in ipairs(set.cardIds or {}) do
        if allowed == cardId then return true end
    end
    return false
end

function RushCards.Sets.save(list)
    if type(list) ~= 'table' then return false, 'sets must be an array' end
    local knownCards = {}
    if RushCards.Cards and RushCards.Cards.getCatalog then
        for _, card in ipairs(RushCards.Cards.getCatalog() or {}) do
            if card.id then knownCards[card.id] = true end
        end
    end

    local normalized, used = {}, {}
    for index, item in ipairs(list) do
        local set = normalizeSet(item, index)
        if used[set.id] then return false, ('Duplicate set id: %s'):format(set.id) end
        for _, cardId in ipairs(set.cardIds or {}) do
            if next(knownCards) and not knownCards[cardId] then
                return false, ('Set "%s" references unknown card id: %s'):format(set.name, cardId)
            end
        end
        used[set.id] = true
        normalized[#normalized + 1] = set
    end
    if #normalized == 0 then return false, 'At least one card set is required.' end
    saveSets(normalized)
    sets = normalized
    return true
end

loadSets()
