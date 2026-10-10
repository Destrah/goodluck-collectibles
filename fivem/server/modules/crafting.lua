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
local function gameAuthor(source)
    return source == 0 or IsPlayerAceAllowed(source, cfg.MinigameAce or (Config.Management or {}).Ace or 'metacomic.manage')
end
local function cleanGame(raw)
    if raw == nil or raw == false then return nil end
    if type(raw) ~= 'table' then return nil, 'minigame must be a table' end
    if raw.enabled ~= true then return nil end
    local game = { enabled = true, cols = whole(raw.cols or 5, 1, 10), rows = whole(raw.rows or 3, 1, 10),
        rewardPacks = whole(raw.rewardPacks or 3, 1, 100), maxErrors = whole(raw.maxErrors or 6, 1, 20),
        time = whole(raw.time or 900, 30, 1800), minSeconds = whole(raw.minSeconds or 20, 5, 300),
        bonusSeconds = whole(raw.bonusSeconds or 180, 0, 1800), bonusPacks = whole(raw.bonusPacks or 0, 0, 10),
        bulkBonusEvery = whole(raw.bulkBonusEvery or 5, 2, 100), bulkBonusPacks = whole(raw.bulkBonusPacks or 1, 0, 10),
        bulkBonusMax = whole(raw.bulkBonusMax or 5, 0, 100), scaleBonusTime = raw.scaleBonusTime ~= false,
        flawChance = tonumber(raw.flawChance) or 0.5, cutter = raw.cutter or 'bench' }
    for _, key in ipairs({'cols','rows','rewardPacks','maxErrors','time','minSeconds','bonusSeconds','bonusPacks','bulkBonusEvery','bulkBonusPacks','bulkBonusMax'}) do
        if game[key] == nil then return nil, 'invalid minigame ' .. key end
    end
    if game.cols * game.rows > 60 or game.cols * game.rows % 5 ~= 0 then return nil, 'sheet needs at most 60 cards and a total divisible by five' end
    if not finite(game.flawChance) or game.flawChance < 0 or game.flawChance > 1 then return nil, 'flaw chance must be 0 to 1' end
    if game.cutter ~= 'bench' and game.cutter ~= 'industrial' and game.cutter ~= 'random' then return nil, 'unknown cutter' end
    if game.minSeconds >= game.time then return nil, 'minimum duration must be below the time limit' end
    return game
end

local function bulkReward(game, completed)
    return math.min(game.bulkBonusMax, math.floor(completed / game.bulkBonusEvery) * game.bulkBonusPacks)
end
local function perfectWindow(game)
    -- Preserve the configured allowance for a normal 15-card sheet; larger sheets get proportional time.
    return math.min(game.time, game.bonusSeconds * (game.scaleBonusTime and math.max(1, game.cols * game.rows / 15) or 1))
end

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
    -- Sealed recipes are shared across sets; callers choose the set at craft start.
    if typeId == 'sealed' then cleanResult.set = nil end
    if not cleanResult.count then return nil, id .. ': result count must be 1 to 1000' end
    if resultType.validate and not resultType.validate(cleanResult) then return nil, id .. ': the result is not valid (check its item / set / type)' end
    local minigame, gameError = cleanGame(raw.minigame)
    if gameError then return nil, id .. ': ' .. gameError end
    if minigame and (typeId ~= 'sealed' or cleanResult.kind == 'box') then return nil, id .. ': card production requires a sealed pack result' end
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
        minigame = minigame,
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
function service.prints(setId, sheetSize)
    if setId ~= nil and setId ~= '' and not text(setId, 80) then return nil end
    local set = MetaComic.Sets.get(text(setId, 80) or MetaComic.Sets.defaultId())
    if not set then return nil end
    local allowed, pool, cards = {}, {}, {}
    for _, id in ipairs(set.cardIds or {}) do allowed[id] = true end
    for _, card in ipairs(MetaComic.Cards.getCatalog()) do
        if allowed[card.id] and #(card.variants or {}) > 0 then pool[#pool + 1] = card end
    end
    -- Sample the whole set: distinct cards before any repetition, rather than first catalogue entries.
    for i = #pool, 2, -1 do local j = math.random(i); pool[i], pool[j] = pool[j], pool[i] end
    if sheetSize then
        -- Pick the sheet before resolving/transferring full artwork records. Only the requested stock
        -- needs a full sheet; other stocks are lightweight decoy previews for the selection task.
        local grouped, groups = {}, {}
        for _, card in ipairs(pool) do
            for _, variant in ipairs(card.variants) do
                local layout = text(variant.layout) or card.layout or 'classic'
                local accent = text(variant.accent) or card.accent or '#22d3ee'
                local key = layout == 'dark-borderless' and layout or (layout .. '|' .. accent)
                local group = grouped[key]
                if not group then group = { identities = {}, count = 0 }; grouped[key] = group; groups[#groups + 1] = group end
                if not group.identities[card.id] then group.identities[card.id] = {}; group.count = group.count + 1 end
                local prints = group.identities[card.id]
                prints[#prints + 1] = { card = card, variant = variant }
            end
        end
        table.sort(groups, function(a, b) return a.count > b.count end)
        if #groups > 0 then
            local eligible = 1
            while groups[eligible + 1] and groups[eligible + 1].count >= math.min(sheetSize, groups[1].count) do eligible = eligible + 1 end
            local chosen = math.random(eligible); groups[1], groups[chosen] = groups[chosen], groups[1]
        end
        for index = 1, math.min(6, #groups) do
            local group, identities = groups[index], {}
            for _, prints in pairs(group.identities) do identities[#identities + 1] = prints end
            for i = #identities, 2, -1 do local j = math.random(i); identities[i], identities[j] = identities[j], identities[i] end
            for i = 1, math.min(#identities, index == 1 and sheetSize or 1) do
                local prints = identities[i]
                local chosen = prints[math.random(#prints)]
                local print = MetaComic.Cards.resolve(chosen.card.id, chosen.variant.id)
                if print then cards[#cards + 1] = print end
            end
        end
        return cards, set
    end
    local variants = {}
    for i, card in ipairs(pool) do
        variants[i] = MetaComic.CopyTable(card.variants)
        for n = #variants[i], 2, -1 do local j = math.random(n); variants[i][n], variants[i][j] = variants[i][j], variants[i][n] end
    end
    -- Interleave prints across card identities; the bounded latent payload never favors the first cards.
    local round, more = 1, true
    while more and #cards < 600 do
        more = false
        for i, card in ipairs(pool) do
            local variant = variants[i][round]
            if variant and #cards < 600 then
                more = true
                local print = MetaComic.Cards.resolve(card.id, variant.id)
                if print then cards[#cards + 1] = print end
            end
        end
        round = round + 1
    end
    return cards, set
end
local function setChoices()
    local choices = {}
    for _, set in ipairs(MetaComic.Sets.getAll()) do choices[#choices + 1] = { value = set.id, label = set.name or set.id } end
    return choices
end

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
                ingredients = ingredients, money = recipe.money, account = recipe.account, time = recipe.time,
                interactive = recipe.minigame ~= nil, rewardPacks = recipe.minigame and recipe.minigame.rewardPacks,
                bulkBonusEvery = recipe.minigame and recipe.minigame.bulkBonusEvery, bulkBonusPacks = recipe.minigame and recipe.minigame.bulkBonusPacks, bulkBonusMax = recipe.minigame and recipe.minigame.bulkBonusMax,
                sets = recipe.result.type == 'sealed' and setChoices() or nil, defaultSet = recipe.result.type == 'sealed' and MetaComic.Sets.defaultId() or nil }
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

local function startCraft(source, stationIndex, recipeId, amount, setId, order)
    if pending[source] then return notify(source, 'You are already crafting something.', 'error') end
    local station = stationOf(tonumber(stationIndex) or -1)
    local recipe = order and order.recipe or (type(recipeId) == 'string' and findRecipe(recipeId))
    amount = whole(amount, 1, MAX_AMOUNT)
    if not station or not recipe or not amount then return end
    recipe = MetaComic.CopyTable(recipe)
    if recipe.result.type == 'sealed' then
        if setId ~= nil and setId ~= '' and not text(setId, 80) then return notify(source, 'Invalid card set.', 'error') end
        local selected = MetaComic.Sets.get(text(setId, 80) or MetaComic.Sets.defaultId())
        if not selected then return notify(source, 'Unknown card set.', 'error') end
        recipe.result.set = selected.id
    end
    local requested = recipe.minigame and amount or nil
    if requested then amount = 1; order = order or { requested = requested, completed = 0, bonusPaid = 0, recipe = recipe } end
    if not atStation(source, station) then return notify(source, 'You need to stand at the crafting bench.', 'error') end
    local allowed, why = mayCraft(source, station, recipe)
    if not allowed then return notify(source, why, 'error') end
    local short = missing(source, recipe, amount)
    if short then return notify(source, short, 'error') end
    local preview = MetaComic.CopyTable(recipe.result)
    if recipe.minigame then preview.count = requested + math.ceil(requested / recipe.minigame.rewardPacks) * recipe.minigame.bonusPacks + bulkReward(recipe.minigame, order.requested) - order.bonusPaid end
    local resultType = resultTypes[preview.type]
    if resultType.canGive and not resultType.canGive(source, preview, amount) then
        return notify(source, 'You cannot carry the crafted items. Make inventory room before starting.', 'error')
    end
    local duration = recipe.minigame and recipe.minigame.minSeconds * 1000 or recipe.time * amount
    pending[source] = { recipe = recipe, amount = amount, station = station, startedAt = GetGameTimer(), duration = duration, remaining = requested, stationIndex = stationIndex, order = order }
    if recipe.minigame then
        local game = MetaComic.CopyTable(recipe.minigame)
        game.game, game.type = 'crafting', 'builtin'
        if game.cutter == 'random' then game.cutter = math.random(2) == 1 and 'bench' or 'industrial' end
        local cards, selected = service.prints(recipe.result.set, game.cols * game.rows)
        if not cards or #cards == 0 then pending[source] = nil; return notify(source, 'This set has no printable cards.', 'error') end
        game.cards, game.setId, game.setName = cards, selected.id, selected.name or selected.id
        game.requestedPacks = requested
        game.orderCompleted = order.completed
        game.bulkBonusRemaining = bulkReward(recipe.minigame, order.requested) - order.bonusPaid
        game.bonusSeconds = perfectWindow(recipe.minigame)
        TriggerLatentClientEvent('meta_comic:client:craftingGame', source, 256 * 1024, game)
    else TriggerClientEvent('meta_comic:client:craftingProgress', source, duration, recipe.label, amount, cfg.Animation) end
end
RegisterNetEvent('meta_comic:server:craftingStart', function(stationIndex, recipeId, amount, setId)
    startCraft(source, stationIndex, recipeId, amount, setId)
end)

RegisterNetEvent('meta_comic:server:craftingCancel', function() pending[source] = nil end)

RegisterNetEvent('meta_comic:server:craftingFinish', function(details)
    local source = source
    local job = pending[source]
    pending[source] = nil
    if not job then return end
    local recipe, amount = job.recipe, job.amount
    local reward = MetaComic.CopyTable(recipe.result)
    local bulkBonus, completedPacks = 0, 0
    if recipe.minigame then
        local game, elapsed = recipe.minigame, GetGameTimer() - job.startedAt
        local expected = game.cols * game.rows / 5
        local errors = type(details) == 'table' and whole(details.errors, 0, game.maxErrors - 1)
        if not errors or details.printed ~= true or details.inspected ~= true or details.packs ~= expected
            or details.folds ~= expected or details.seals ~= expected or details.cuts ~= game.cols * game.rows - 1
            or elapsed > (game.time + 20) * 1000 then return notify(source, 'Card production was incomplete or expired.', 'error') end
        reward.count = math.min(game.rewardPacks, job.remaining or game.rewardPacks)
        completedPacks = reward.count
        bulkBonus = bulkReward(game, job.order.completed + completedPacks) - job.order.bonusPaid
        reward.count = reward.count + bulkBonus
        -- Payout and timing come from the pending server recipe, never client supplied reward quantities/time.
        if errors == 0 and elapsed <= perfectWindow(game) * 1000 then reward.count = reward.count + game.bonusPacks end
    end
    if GetGameTimer() - job.startedAt < job.duration - 750 then return notify(source, 'Crafting was interrupted.', 'error') end
    if not atStation(source, job.station) then return notify(source, 'You walked away from the crafting bench.', 'error') end
    local short = missing(source, recipe, amount)
    if short then return notify(source, short, 'error') end
    local resultType = resultTypes[recipe.result.type]
    local allowed, why = mayCraft(source, job.station, recipe)
    if not allowed then return notify(source, why, 'error') end
    if resultType.canGive and not resultType.canGive(source, reward, amount) then return notify(source, 'You cannot carry that.', 'error') end

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
    local ok, err = resultType.give(source, reward, amount)
    if not ok then
        giveBack()
        if price > 0 then MetaComic.Money.add(source, recipe.account, price, 'collectibles-crafting-refund') end
        return notify(source, err or 'Could not give the crafted items.', 'error')
    end
    if recipe.minigame then
        job.order.completed = job.order.completed + completedPacks
        job.order.bonusPaid = job.order.bonusPaid + bulkBonus
    end
    if recipe.minigame and job.remaining > recipe.minigame.rewardPacks then
        startCraft(source, job.stationIndex, recipe.id, job.remaining - recipe.minigame.rewardPacks, recipe.result.set, job.order)
    end
    notify(source, recipe.minigame and ('Crafted %d booster packs%s.'):format(reward.count, bulkBonus > 0 and (' (includes %d bulk bonus)'):format(bulkBonus) or '') or ('Crafted %s%s.'):format(amount > 1 and (amount .. 'x ') or '', recipe.label), 'success')
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
    handlers.getCraftingPrints = function(_, payload)
        local setId = type(payload) == 'table' and payload.setId or nil
        local cols = type(payload) == 'table' and whole(payload.cols or 5, 1, 10) or 5
        local rows = type(payload) == 'table' and whole(payload.rows or 3, 1, 10) or 3
        if not cols or not rows or cols * rows > 60 or cols * rows % 5 ~= 0 then return { ok = false, error = 'Invalid production sheet dimensions.' } end
        local cards, selected = service.prints(setId, cols * rows)
        return cards and { ok = true, cards = cards, setId = selected.id, setName = selected.name or selected.id } or { ok = false, error = 'Unknown card set.' }
    end
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
            crates = service.crateChoices and service.crateChoices() or {}, custom = MetaComic.Settings.get(SETTING_KEY) ~= nil,
            canEditMinigame = gameAuthor(source) }
    end
    handlers.saveCrafting = function(source, payload)
        if not canManage(source) then return { ok = false, error = 'You do not have permission to manage crafting.' } end
        if payload and payload.reset == true then
            if not gameAuthor(source) then return { ok = false, error = 'The crafting minigame settings require the management ACE.' } end
            local ok, err = MetaComic.Settings.set(SETTING_KEY, nil)
            if not ok then return { ok = false, error = err } end
            loadRecipes()
            return handlers.getCrafting(source)
        end
        local list, err = cleanList(payload and payload.recipes)
        if not list then return { ok = false, error = err } end
        if not gameAuthor(source) then
            local function same(a, b)
                a, b = a or {}, b or {}
                for _, key in ipairs({'enabled','cols','rows','rewardPacks','maxErrors','time','minSeconds','bonusSeconds','bonusPacks','bulkBonusEvery','bulkBonusPacks','bulkBonusMax','scaleBonusTime','flawChance','cutter'}) do if a[key] ~= b[key] then return false end end
                return true
            end
            local incoming = {}
            for _, recipe in ipairs(list) do incoming[recipe.id] = recipe; if not same(recipe.minigame, (findRecipe(recipe.id) or {}).minigame) then return { ok = false, error = 'The crafting minigame settings require the management ACE.' } end end
            for _, recipe in ipairs(recipes) do if recipe.minigame and not incoming[recipe.id] then return { ok = false, error = 'Removing a card production recipe requires the management ACE.' } end end
        end
        local ok, saveError = MetaComic.Settings.set(SETTING_KEY, list)
        if not ok then return { ok = false, error = saveError } end
        recipes = list
        return handlers.getCrafting(source)
    end
end

-- other scripts: exports['<resource>']:GetCraftingRecipes()
exports('GetCraftingRecipes', function() return service.all() end)
