-- Crafting stations (Config.Crafting.Stations) with ox_target, recipe menus with ox_lib. The server decides what
-- this player may craft and checks everything again; this file only shows menus and the progress bar.
local cfg = Config.Crafting or {}
if cfg.Enabled == false then return end

local zones, props = {}, {}
local crafting = false

local function notify(message, notifyType) TriggerEvent('meta_comic:client:notify', message, notifyType) end
local function hasOxLib()
    if GetResourceState('ox_lib') == 'started' then return true end
    notify('Crafting menus need ox_lib.', 'error')
    return false
end
local function money(n) return ('$%d'):format(math.floor(tonumber(n) or 0)) end

local function loadModel(model)
    local hash = type(model) == 'number' and model or joaat(model)
    if not IsModelInCdimage(hash) then return nil end
    RequestModel(hash)
    local timeout = GetGameTimer() + 5000
    while not HasModelLoaded(hash) and GetGameTimer() < timeout do Wait(0) end
    return HasModelLoaded(hash) and hash or nil
end

RegisterNetEvent('meta_comic:client:craftingOpen', function(stationIndex, title, recipes, maxAmount)
    if not hasOxLib() then return end
    local byCategory, categories = {}, {}
    for _, recipe in ipairs(recipes or {}) do
        if not byCategory[recipe.category] then byCategory[recipe.category] = {}; categories[#categories + 1] = recipe.category end
        table.insert(byCategory[recipe.category], recipe)
    end
    local function recipeOption(recipe)
        local lines, ready = {}, true
        for _, entry in ipairs(recipe.ingredients) do
            local enough = (entry.have or 0) >= entry.count
            ready = ready and enough
            lines[#lines + 1] = ('%s %dx %s%s (have %d)'):format(enough and '✓' or '✗', entry.count, entry.item, entry.keep and ' [tool]' or '', entry.have or 0)
        end
        if recipe.interactive and (recipe.bulkBonusPacks or 0) > 0 and (recipe.bulkBonusMax or 0) > 0 then
            lines[#lines + 1] = ('Bulk order: +%d extra pack(s) every %d completed (maximum +%d). Mistakes do not remove this bonus.'):format(recipe.bulkBonusPacks, recipe.bulkBonusEvery, recipe.bulkBonusMax)
        end
        if (recipe.money or 0) > 0 then lines[#lines + 1] = ('%s (%s)'):format(money(recipe.money), recipe.account == 'bank' and 'bank' or 'cash') end
        return {
            title = recipe.label,
            description = recipe.interactive and ('Print, cut, fold and seal · %d packs per batch'):format(recipe.rewardPacks or 3) or ('Makes %s · %.1fs'):format(recipe.result, (recipe.time or 0) / 1000),
            icon = ready and 'hammer' or 'lock',
            iconColor = ready and '#4ade80' or '#f87171',
            metadata = lines,
            onSelect = function()
                local fields = { { type = 'number', label = recipe.interactive and 'Packs requested (bonuses are extra)' or 'How many', default = recipe.interactive and math.min(recipe.rewardPacks or 3, maxAmount or 1) or 1, min = 1, max = maxAmount or 1, required = true } }
                if recipe.sets then fields[#fields + 1] = { type = 'select', label = 'Card set', options = recipe.sets, default = recipe.defaultSet, required = true, searchable = true } end
                local result = exports.ox_lib:inputDialog(recipe.label, fields)
                if not result then return end
                TriggerServerEvent('meta_comic:server:craftingStart', stationIndex, recipe.id, math.floor(tonumber(result[1]) or 1), result[2])
            end,
        }
    end
    local options = {}
    if #categories == 1 then
        for _, recipe in ipairs(byCategory[categories[1]]) do options[#options + 1] = recipeOption(recipe) end
    else
        for _, category in ipairs(categories) do
            local subId = 'meta_comic_crafting_' .. category:gsub('%W', '_')
            options[#options + 1] = {
                title = category, icon = 'layer-group', arrow = true,
                description = ('%d recipe%s'):format(#byCategory[category], #byCategory[category] == 1 and '' or 's'),
                onSelect = function()
                    local sub = {}
                    for _, recipe in ipairs(byCategory[category]) do sub[#sub + 1] = recipeOption(recipe) end
                    exports.ox_lib:registerContext({ id = subId, title = category, menu = 'meta_comic_crafting', options = sub })
                    exports.ox_lib:showContext(subId)
                end,
            }
        end
    end
    if #options == 0 then options[1] = { title = 'Nothing you can craft here', disabled = true } end
    exports.ox_lib:registerContext({ id = 'meta_comic_crafting', title = title or 'Crafting', options = options })
    exports.ox_lib:showContext('meta_comic_crafting')
end)

RegisterNetEvent('meta_comic:client:craftingGame', function(config)
    if crafting then TriggerServerEvent('meta_comic:server:craftingCancel'); return end
    crafting = true
    local ok, success, details = pcall(function() return exports[GetCurrentResourceName()]:CraftingMinigame(config) end)
    crafting = false
    if ok and success then TriggerServerEvent('meta_comic:server:craftingFinish', details)
    else TriggerServerEvent('meta_comic:server:craftingCancel'); notify('Card production cancelled or failed.', 'info') end
end)

-- the server set the timer; finishing early is rejected there anyway
RegisterNetEvent('meta_comic:client:craftingProgress', function(duration, label, amount, animation)
    if crafting then return end
    crafting = true
    local anim = type(animation) == 'table' and animation or {}
    local finished = true
    if duration > 0 then
        if GetResourceState('ox_lib') == 'started' then
            finished = exports.ox_lib:progressBar({
                duration = duration,
                label = ('Crafting %s%s'):format(amount > 1 and (amount .. 'x ') or '', label),
                useWhileDead = false, canCancel = true,
                disable = { move = true, car = true, combat = true },
                anim = anim.dict and { dict = anim.dict, clip = anim.clip, flag = anim.flag or 49 } or (anim.scenario and { scenario = anim.scenario }) or nil,
                prop = anim.prop and { model = anim.prop, bone = anim.bone or 57005, pos = anim.pos or vec3(0.1, 0.0, -0.02), rot = anim.rot or vec3(0.0, 0.0, 0.0) } or nil,
            })
        else
            Wait(duration)
        end
    end
    crafting = false
    if finished then TriggerServerEvent('meta_comic:server:craftingFinish') else
        TriggerServerEvent('meta_comic:server:craftingCancel')
        notify('Crafting cancelled.', 'info')
    end
end)

CreateThread(function()
    if GetResourceState('ox_target') ~= 'started' then
        if #(cfg.Stations or {}) > 0 then print('[meta-comic] crafting stations need ox_target') end
        return
    end
    for index, station in ipairs(cfg.Stations or {}) do
        local coords = station.coords
        if coords then
            if station.model then
                local hash = loadModel(station.model)
                if hash then
                    local prop = CreateObjectNoOffset(hash, coords.x, coords.y, coords.z, false, false, false)
                    SetEntityHeading(prop, station.heading or 0.0)
                    FreezeEntityPosition(prop, true)
                    SetModelAsNoLongerNeeded(hash)
                    props[#props + 1] = prop
                end
            end
            zones[#zones + 1] = exports.ox_target:addSphereZone({
                coords = vec3(coords.x, coords.y, coords.z),
                radius = station.radius or 1.5,
                debug = Config.Debug == true,
                options = { {
                    name = 'meta_comic_crafting_' .. index,
                    icon = station.icon or 'fa-solid fa-hammer',
                    label = station.label or 'Craft',
                    distance = station.radius and station.radius + 1.0 or 2.5,
                    onSelect = function() TriggerServerEvent('meta_comic:server:craftingOpen', index) end,
                } },
            })
        end
    end
end)

-- other scripts: exports['<resource>']:OpenCrafting(stationIndex) (the player still has to stand at that station)
exports('OpenCrafting', function(stationIndex) TriggerServerEvent('meta_comic:server:craftingOpen', tonumber(stationIndex) or 1) end)

-- Starts the authoritative recipe workflow; amount is requested packs for production, item count otherwise.
exports('StartCrafting', function(stationIndex, recipeId, amount, setId)
    TriggerServerEvent('meta_comic:server:craftingStart', tonumber(stationIndex) or 1, recipeId, tonumber(amount) or 1, setId)
end)

AddEventHandler('onResourceStop', function(name)
    if name ~= GetCurrentResourceName() then return end
    for _, prop in ipairs(props) do if DoesEntityExist(prop) then DeleteEntity(prop) end end
    if GetResourceState('ox_target') == 'started' then
        for _, zone in ipairs(zones) do exports.ox_target:removeZone(zone) end
    end
end)
