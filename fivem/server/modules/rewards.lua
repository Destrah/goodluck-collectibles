-- Things the server can hand a player: crafting results and shipping crate contents use the same list.
-- Each kind: label(result), validate(result), canGive(source, result, amount)?, give(source, result, amount) -> ok, err
-- result.count is per unit; amount multiplies it. Modules register more kinds (crates, vending machines).
MetaComic.Rewards = { types = {} }
local service = MetaComic.Rewards
local resultTypes = service.types

local function text(value, max)
    if type(value) ~= 'string' then return nil end
    value = value:gsub('^%s+', ''):gsub('%s+$', '')
    return value ~= '' and #value <= (max or 80) and value or nil
end
local function itemName(value) local name = text(value, 60); return name and name:match('^[%w_%-%.]+$') and name or nil end
service.itemName = itemName

function service.register(typeId, definition) resultTypes[typeId] = definition end

resultTypes.item = {
    label = function(result) return ('%dx %s'):format(result.count or 1, result.item) end,
    validate = function(result) return itemName(result.item) ~= nil end,
    canGive = function(source, result, amount)
        return not MetaComic.Inventory.canCarry or MetaComic.Inventory.canCarry(source, result.item, (result.count or 1) * amount)
    end,
    give = function(source, result, amount) return MetaComic.Inventory.add(source, result.item, (result.count or 1) * amount) end,
}
resultTypes.sealed = { -- booster packs / boxes of a card set (no set: the default set)
    label = function(result)
        local set = result.set and MetaComic.Sets and MetaComic.Sets.get(result.set)
        return ('%dx %s %s'):format(result.count or 1, set and set.name or 'default set', result.kind == 'box' and 'booster box' or 'booster pack')
    end,
    validate = function(result) return result.set == nil or (MetaComic.Sets and MetaComic.Sets.get(result.set) ~= nil) end,
    canGive = function(source, result, amount)
        local item = result.kind == 'box' and Config.Items.BoosterBox or Config.Items.BoosterPack
        return not MetaComic.Inventory.canCarry or MetaComic.Inventory.canCarry(source, item, (result.count or 1) * amount)
    end,
    give = function(source, result, amount)
        return MetaComic.GiveSealed(source, result.kind == 'box' and 'box' or 'pack', result.set, (result.count or 1) * amount)
    end,
}
resultTypes.container = { -- plushie boxes / cases, coin bags / bag boxes (the container saved in the admin UI)
    label = function(result)
        local names = { plushie = { 'Plushie Box', 'Plushie Case' }, challenge_coin = { 'Coin Bag', 'Coin Bag Box' } }
        local pair = names[result.collectible] or { result.collectible .. ' container', result.collectible .. ' case' }
        return ('%dx %s'):format(result.count or 1, pair[result.outer and 2 or 1])
    end,
    validate = function(result) return MetaComic.Objects and MetaComic.Objects.types and MetaComic.Objects.types[result.collectible] ~= nil end,
    give = function(source, result, amount)
        local ok, err = pcall(MetaComic.Objects.create, source, { typeId = result.collectible, outer = result.outer == true, amount = (result.count or 1) * amount })
        return ok, not ok and tostring(err) or nil
    end,
}

function service.label(result)
    local kind = type(result) == 'table' and resultTypes[result.type]
    return kind and kind.label and kind.label(result) or tostring(type(result) == 'table' and result.type)
end
function service.valid(result)
    local kind = type(result) == 'table' and resultTypes[result.type]
    return kind ~= nil and (not kind.validate or kind.validate(result) == true)
end
function service.canGive(source, result, amount)
    local kind = resultTypes[result.type]
    return kind ~= nil and (not kind.canGive or kind.canGive(source, result, amount or 1) == true)
end
function service.give(source, result, amount)
    local kind = resultTypes[result.type]
    if not kind then return false, 'Unknown reward ' .. tostring(result.type) end
    local ok, a, b = pcall(kind.give, source, result, amount or 1)
    if not ok then return false, tostring(a) end
    return a, b
end
