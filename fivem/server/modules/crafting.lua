-- Crafting (Config.Crafting). Recipes start from config.lua; managers edit them in the admin UI ("Crafting" tab),
-- which saves them with MetaComic.Settings and from then on replaces the config list.
-- Players craft at stations (ox_target) or, for managers, anywhere with the crafting command.
-- Everything is checked here: station distance, who may craft, ingredients, money and the crafting time. Ingredients
-- and money are only taken when the timer has run out, right before the result is given.
local cfg = Config.Crafting or {}
if cfg.Enabled == false then return end

MetaComic.Crafting = {}
local service = MetaComic.Crafting
local SETTING_KEY = 'crafting_recipes'
local MAX_RECIPES, MAX_INGREDIENTS, MAX_AMOUNT = 200, 12, tonumber(cfg.MaxAmount) or 25
local recipes, pending = {}, {}

local function notify(source, message, notifyType)
    if MetaComic.Framework.notify then MetaComic.Framework.notify(source, message, notifyType) end
end
local function canManage(source) return MetaComic.CanManage and MetaComic.CanManage(source) == true end
local function finite(n) return type(n) == 'number' and n == n and n ~= math.huge and n ~= -math.huge end
local function whole(n, min, max)
    n = tonumber(n)
    if not finite(n) then return nil end
    n = math.floor(n)
    return n >= min and n <= max and n or nil
end
local function text(value, max)
    if type(value) ~= 'string' then return nil end
    value = value:gsub('^%s+', ''):gsub('%s+$', '')
    return value ~= '' and #value <= (max or 80) and value or nil
end
local function itemName(value) local name = text(value, 60); return name and name:match('^[%w_%-%.]+$') and name or nil end

-- Results ------------------------------------------------------------------------------------------------------------
-- what a recipe makes: MetaComic.Rewards (server/modules/rewards.lua) knows every kind, other modules add theirs
local resultTypes = MetaComic.Rewards.types
function service.registerResult(typeId, definition) MetaComic.Rewards.register(typeId, definition) end

-- Recipes -------------------------------------------------------------------------------------------------------------
-- a clean copy of one recipe, or nil and why it is invalid
local function cleanRecipe(raw, id)
    if type(raw) ~= 'table' then return nil, 'not a table' end
    id = text(raw.id or id, 60)
    if not id or not id:match('^[%w_%-]+$') then return nil, 'id must use letters, digits, - and _' end
    local result = type(raw.result) == 'table' and raw.result or {}
    local typeId = text(result.type, 30) or 'item'
    local resultType = resultTypes[typeId]
    if not resultType then return nil, ('%s: unknown result type %s'):format(id, typeId) end
    local cleanResult = {
        type = typeId, item = itemName(result.item), count = whole(result.count or 1, 1, 1000),
        kind = result.kind == 'box' and 'box' or (result.kind == 'pack' and 'pack' or nil),
        set = text(result.set, 80), collectible = text(result.collectible, 40), outer = result.outer == true,
        crate = text(result.crate, 40), model = text(result.model, 64),
    }
    if typeId == 'crate' and type(result.sets) == 'table' then -- card sets the crate's packs / boxes come from
        local sets = {}
        for _, id in ipairs(result.sets) do local value = text(id, 80); if value and #sets < 20 then sets[#sets + 1] = value end end
        cleanResult.sets = #sets > 0 and sets or nil
    end
    if not cleanResult.count then return nil, id .. ': result count must be 1 to 1000' end
    if resultType.validate and not resultType.validate(cleanResult) then return nil, id .. ': the result is not valid (check its item / set / type)' end
    local ingredients = {}
    for _, entry in ipairs(type(raw.ingredients) == 'table' and raw.ingredients or {}) do
        local name, count = itemName(entry.item), whole(entry.count or 1, 1, 10000)
        if not name or not count then return nil, id .. ': every ingredient needs an item name and a count' end
        ingredients[#ingredients + 1] = { item = name, count = count, keep = entry.keep == true } -- keep: a tool, needed but not used up
        if #ingredients > MAX_INGREDIENTS then return nil, id .. ': too many ingredients' end
    end
    local jobs = {}
    for name, grade in pairs(type(raw.jobs) == 'table' and raw.jobs or {}) do
        if type(name) == 'string' then jobs[name] = whole(grade, 0, 100) or 0 end
    end
    return {
        id = id,
        label = text(raw.label, 80) or id,
        category = text(raw.category, 40) or 'General',
        result = cleanResult,
        ingredients = ingredients,
        money = whole(raw.money or 0, 0, 100000000) or 0,
        account = (raw.account == 'bank') and 'bank' or 'cash',
        time = whole(raw.time or 5000, 0, 600000) or 5000,
        jobs = jobs,
        managersOnly = raw.managersOnly == true,
        stations = type(raw.stations) == 'table' and raw.stations or nil, -- station ids; nil = every station
        enabled = raw.enabled ~= false,
    }
end

-- lenient: skip invalid recipes with a console warning (loading) instead of refusing the list (saving from the UI)
local function cleanList(list, lenient)
    local result, seen = {}, {}
    for key, raw in pairs(type(list) == 'table' and list or {}) do
        local recipe, err = cleanRecipe(raw, type(key) == 'string' and key or nil)
        if not recipe and lenient then print('[meta-comic] skipped crafting recipe: ' .. tostring(err)) goto continue end
        if not recipe then return nil, err end
        if seen[recipe.id] then return nil, 'two recipes use the id ' .. recipe.id end
        seen[recipe.id] = true
        result[#result + 1] = recipe
        if #result > MAX_RECIPES then return nil, 'too many recipes' end
        ::continue::
    end
    table.sort(result, function(a, b) if a.category ~= b.category then return a.category < b.category end return a.label < b.label end)
    return result
end

local function loadRecipes()
    local saved = MetaComic.Settings and MetaComic.Settings.get(SETTING_KEY)
    local list, err = cleanList(saved or cfg.Recipes, true)
    if not list then print('[meta-comic] Config.Crafting.Recipes is invalid: ' .. tostring(err)); list = {} end
    recipes = list
end
-- results registered by later modules (crates, vending machines) must exist before recipes are checked
CreateThread(function() Wait(0); loadRecipes() end)

local function findRecipe(id) for _, recipe in ipairs(recipes) do if recipe.id == id then return recipe end end end
function service.all() return MetaComic.CopyTable(recipes) end

-- Stations ------------------------------------------------------------------------------------------------------------
local function stationOf(index)
    if index == 0 then return { id = 'anywhere', label = 'Crafting', anywhere = true } end
    local station = (cfg.Stations or {})[tonumber(index) or -1]
    if type(station) ~= 'table' then return nil end
    station.id = station.id or ('station_' .. index)
    return station
end
local function pedCoords(source)
    local ped = GetPlayerPed(source)
    if not ped or ped == 0 then return nil end
    local coords = GetEntityCoords(ped)
    if coords.x == 0.0 and coords.y == 0.0 and coords.z == 0.0 then return nil end
    return coords
end
local function atStation(source, station)
    if station.anywhere then return canManage(source) end
    local ped, coords = pedCoords(source), station.coords
    if not ped or not coords then return true end
    return #(ped - vector3(coords.x, coords.y, coords.z)) <= (tonumber(station.radius) or 2.0) + 3.0
end
local function jobAllowed(source, jobs)
    if not next(jobs or {}) then return true end
    local job = MetaComic.Framework.getJob and MetaComic.Framework.getJob(source)
    local minGrade = job and job.name and jobs[job.name]
    return minGrade ~= nil and (tonumber(job.grade) or 0) >= (tonumber(minGrade) or 0)
end
local function stationAllows(station, recipe)
    if station.anywhere then return true end
    if recipe.stations then
        local listed = false
        for _, id in ipairs(recipe.stations) do if id == station.id then listed = true end end
        if not listed then return false end
    end
    if type(station.recipes) == 'table' then
        for _, id in ipairs(station.recipes) do if id == recipe.id then return true end end
        return false
    end
    return true
end
local function mayCraft(source, station, recipe)
    if not recipe.enabled then return false, 'This recipe is turned off.' end
    if not stationAllows(station, recipe) then return false, 'This recipe is not made here.' end
    if canManage(source) then return true end
    if recipe.managersOnly then return false, 'Only managers can craft this.' end
    if not jobAllowed(source, station.jobs) or not jobAllowed(source, recipe.jobs) then return false, 'You do not have the job for this.' end
    return true
end

local function countOf(source, item)
    return MetaComic.Inventory.count and MetaComic.Inventory.count(source, item) or (MetaComic.Inventory.has(source, item, 1) and 1 or 0)
end
local function missing(source, recipe, amount)
    for _, entry in ipairs(recipe.ingredients) do
        local need = entry.keep and entry.count or entry.count * amount
        if countOf(source, entry.item) < need then return ('You need %dx %s.'):format(need, entry.item) end
    end
end
local function resultLabel(recipe)
    local resultType = resultTypes[recipe.result.type]
    return resultType and resultType.label and resultType.label(recipe.result) or recipe.label
end

-- what the menu shows: only the recipes this player may make here, with how many of each ingredient they hold
local function menuFor(source, station)
    local list = {}
    for _, recipe in ipairs(recipes) do
        if mayCraft(source, station, recipe) then
            local ingredients = {}
            for _, entry in ipairs(recipe.ingredients) do
                ingredients[#ingredients + 1] = { item = entry.item, count = entry.count, keep = entry.keep, have = countOf(source, entry.item) }
            end
            list[#list + 1] = { id = recipe.id, label = recipe.label, category = recipe.category, result = resultLabel(recipe),
                ingredients = ingredients, money = recipe.money, account = recipe.account, time = recipe.time }
        end
    end
    return list
end

-- Events --------------------------------------------------------------------------------------------------------------
RegisterNetEvent('meta_comic:server:craftingOpen', function(stationIndex)
    local source = source
    local station = stationOf(tonumber(stationIndex) or -1)
    if not station then return end
    if not atStation(source, station) then return notify(source, 'You need to stand at the crafting bench.', 'error') end
    TriggerLatentClientEvent('meta_comic:client:craftingOpen', source, 256 * 1024, tonumber(stationIndex), station.label or 'Crafting', menuFor(source, station), MAX_AMOUNT)
end)

RegisterNetEvent('meta_comic:server:craftingStart', function(stationIndex, recipeId, amount)
    local source = source
    if pending[source] then return notify(source, 'You are already crafting something.', 'error') end
    local station = stationOf(tonumber(stationIndex) or -1)
    local recipe = type(recipeId) == 'string' and findRecipe(recipeId)
    amount = whole(amount, 1, MAX_AMOUNT)
    if not station or not recipe or not amount then return end
    if not atStation(source, station) then return notify(source, 'You need to stand at the crafting bench.', 'error') end
    local allowed, why = mayCraft(source, station, recipe)
    if not allowed then return notify(source, why, 'error') end
    local short = missing(source, recipe, amount)
    if short then return notify(source, short, 'error') end
    local duration = recipe.time * amount
    pending[source] = { recipe = recipe, amount = amount, station = station, startedAt = GetGameTimer(), duration = duration }
    TriggerClientEvent('meta_comic:client:craftingProgress', source, duration, recipe.label, amount, cfg.Animation)
end)

RegisterNetEvent('meta_comic:server:craftingCancel', function() pending[source] = nil end)

RegisterNetEvent('meta_comic:server:craftingFinish', function()
    local source = source
    local job = pending[source]
    pending[source] = nil
    if not job then return end
    local recipe, amount = job.recipe, job.amount
    if GetGameTimer() - job.startedAt < job.duration - 750 then return notify(source, 'Crafting was interrupted.', 'error') end
    if not atStation(source, job.station) then return notify(source, 'You walked away from the crafting bench.', 'error') end
    local short = missing(source, recipe, amount)
    if short then return notify(source, short, 'error') end
    local resultType = resultTypes[recipe.result.type]
    if resultType.canGive and not resultType.canGive(source, recipe.result, amount) then return notify(source, 'You cannot carry that.', 'error') end

    local taken = {}
    local function giveBack()
        for _, entry in ipairs(taken) do MetaComic.Inventory.add(source, entry.item, entry.count) end
    end
    for _, entry in ipairs(recipe.ingredients) do
        if not entry.keep then
            local count = entry.count * amount
            if not MetaComic.Inventory.remove(source, entry.item, count) then
                giveBack()
                return notify(source, ('Could not take %dx %s.'):format(count, entry.item), 'error')
            end
            taken[#taken + 1] = { item = entry.item, count = count }
        end
    end
    local price = recipe.money * amount
    if price > 0 and not MetaComic.Money.remove(source, recipe.account, price, 'collectibles-crafting') then
        giveBack()
        return notify(source, ('Crafting this costs $%d.'):format(price), 'error')
    end
    local ok, err = resultType.give(source, recipe.result, amount)
    if not ok then
        giveBack()
        if price > 0 then MetaComic.Money.add(source, recipe.account, price, 'collectibles-crafting-refund') end
        return notify(source, err or 'Could not give the crafted items.', 'error')
    end
    notify(source, ('Crafted %s%s.'):format(amount > 1 and (amount .. 'x ') or '', recipe.label), 'success')
end)

AddEventHandler('playerDropped', function() pending[source] = nil end)

-- managers: craft anywhere (every recipe) with the command
if cfg.Command and cfg.Command ~= '' then
    RegisterCommand(cfg.Command, function(source)
        if source == 0 then return end
        if not canManage(source) then return notify(source, 'You do not have permission to use this.', 'error') end
        TriggerLatentClientEvent('meta_comic:client:craftingOpen', source, 256 * 1024, 0, 'Crafting', menuFor(source, stationOf(0)), MAX_AMOUNT)
    end, false)
end

-- Admin UI ------------------------------------------------------------------------------------------------------------
local handlers = MetaComic.RpcHandlers
if handlers then
    handlers.getCrafting = function(source)
        if not canManage(source) then return { ok = false, error = 'You do not have permission to manage crafting.' } end
        local types = {}
        for id in pairs(resultTypes) do types[#types + 1] = id end
        table.sort(types)
        local stations = {}
        for index, station in ipairs(cfg.Stations or {}) do stations[#stations + 1] = { id = station.id or ('station_' .. index), label = station.label or ('Station ' .. index) } end
        local collectibles = {}
        for id in pairs(MetaComic.Objects and MetaComic.Objects.types or {}) do collectibles[#collectibles + 1] = id end
        table.sort(collectibles)
        return { ok = true, recipes = recipes, resultTypes = types, stations = stations, collectibles = collectibles,
            crates = service.crateChoices and service.crateChoices() or {}, custom = MetaComic.Settings.get(SETTING_KEY) ~= nil }
    end
    handlers.saveCrafting = function(source, payload)
        if not canManage(source) then return { ok = false, error = 'You do not have permission to manage crafting.' } end
        if payload and payload.reset == true then
            local ok, err = MetaComic.Settings.set(SETTING_KEY, nil)
            if not ok then return { ok = false, error = err } end
            loadRecipes()
            return handlers.getCrafting(source)
        end
        local list, err = cleanList(payload and payload.recipes)
        if not list then return { ok = false, error = err } end
        local ok, saveError = MetaComic.Settings.set(SETTING_KEY, list)
        if not ok then return { ok = false, error = saveError } end
        recipes = list
        return handlers.getCrafting(source)
    end
end

-- other scripts: exports['<resource>']:GetCraftingRecipes()
exports('GetCraftingRecipes', function() return service.all() end)
