-- Card skimmer items and card data buyers (Config.VendingMachines.Skimmer). The server does all the checks
-- (server/modules/vending_security.lua). Buyer peds spawn when a player comes close, like the vending machines.
local cfg = Config.VendingMachines or {}
local skimmer = cfg.Skimmer or {}
if cfg.Enabled == false or skimmer.Enabled == false then return end
local buyers = skimmer.Buyers or {}
local DATA_ITEM = skimmer.DataItem or 'skimmer_card_data'
local function notify(text, kind) TriggerEvent('meta_comic:client:notify', text, kind or 'info') end
local function slotOf(...)
    for i = 1, select('#', ...) do
        local value = select(i, ...)
        if type(value) == 'table' and tonumber(value.slot) then return tonumber(value.slot) end
        if tonumber(value) then return tonumber(value) end
    end
end
-- ox_inventory item client exports (examples/ox_inventory-items.lua)
exports('UseCardSkimmer', function(...) local slot = slotOf(...); if slot then TriggerServerEvent('meta_comic:server:useSkimmerItem', 'skimmer', slot) end end)
exports('UseSkimmerData', function(...) local slot = slotOf(...); if slot then TriggerServerEvent('meta_comic:server:useSkimmerItem', 'data', slot) end end)

RegisterNetEvent('meta_comic:client:skimmerData', function(data)
    local text = ('Card numbers, names and expiry dates from %d card purchases at vending machine %s, copied between %s and %s. The purchases add up to $%d, and $%d of it was skimmed. A buyer can recover the skimmed money and split it with you.')
        :format(data.cards or 0, data.serial or '?', data.from or '?', data.to or '?', data.total or 0, data.skimmed or 0)
    if GetResourceState('ox_lib') == 'started' then
        exports.ox_lib:alertDialog({ header = data.label or 'Card data', content = text, centered = true })
    else
        notify(text, 'inform')
    end
end)

local list = buyers.Peds or (buyers.Ped and { buyers.Ped }) or {}
if buyers.Enabled == false or #list == 0 then return end
local SPAWN = tonumber(buyers.SpawnDistance) or 60.0
local DESPAWN = SPAWN + 10.0
local spawned, selling = {}, false

local function sell(index)
    if selling then return end
    selling = true
    local done = true
    if GetResourceState('ox_lib') == 'started' then
        done = exports.ox_lib:progressBar({ duration = tonumber(buyers.Duration) or 4000, label = buyers.ProgressLabel or 'Handing over the card data',
            canCancel = true, disable = { move = true, car = true, combat = true },
            anim = { dict = 'mp_common', clip = 'givetake1_a', flag = 49 } }) == true
    end
    if done then TriggerServerEvent('meta_comic:server:sellCardData', index) end
    selling = false
end

local function despawn(index)
    local ped = spawned[index]
    spawned[index] = nil
    if not ped then return end
    if GetResourceState('ox_target') == 'started' then pcall(function() exports.ox_target:removeLocalEntity(ped) end) end
    if DoesEntityExist(ped) then DeleteEntity(ped) end
end

local function spawn(index, buyer)
    local model = type(buyer.model) == 'number' and buyer.model or joaat(buyer.model or 'g_m_y_mexgoon_02')
    if not IsModelInCdimage(model) then return end
    RequestModel(model)
    local timeout = GetGameTimer() + 5000
    while not HasModelLoaded(model) do
        if GetGameTimer() > timeout then return end
        Wait(50)
    end
    local c = buyer.coords
    local ped = CreatePed(4, model, c.x, c.y, c.z - 1.0, (c.w or buyer.heading or 0.0) + 0.0, false, true)
    SetModelAsNoLongerNeeded(model)
    SetEntityInvincible(ped, true)
    FreezeEntityPosition(ped, true)
    SetBlockingOfNonTemporaryEvents(ped, true)
    SetPedCanRagdoll(ped, false)
    if buyer.scenario ~= false then TaskStartScenarioInPlace(ped, buyer.scenario or 'WORLD_HUMAN_SMOKING', 0, true) end
    spawned[index] = ped
    if GetResourceState('ox_target') == 'started' then
        exports.ox_target:addLocalEntity(ped, { {
            name = 'meta_comic_card_data_buyer', label = buyer.label or buyers.Label or 'Sell card data', icon = buyers.Icon or 'fas fa-user-secret',
            distance = tonumber(buyers.Distance) or 2.0, items = DATA_ITEM,
            canInteract = function() return not selling end,
            onSelect = function() sell(index) end,
        } })
    end
end

CreateThread(function()
    while true do
        local position = GetEntityCoords(PlayerPedId())
        for index, buyer in ipairs(list) do
            local c = buyer.coords
            if c then
                local distance = #(position - vector3(c.x, c.y, c.z))
                if spawned[index] and (distance > DESPAWN or not DoesEntityExist(spawned[index])) then despawn(index) end
                if not spawned[index] and distance <= SPAWN then spawn(index, buyer) end
            end
        end
        Wait(1000)
    end
end)

AddEventHandler('onResourceStop', function(name)
    if name ~= GetCurrentResourceName() then return end
    for index in pairs(spawned) do despawn(index) end
end)
