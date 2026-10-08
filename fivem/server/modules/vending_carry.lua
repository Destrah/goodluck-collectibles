-- Server side of Config.VendingCarry: tells a carrying player whether their machine is stolen, and turns a machine item
-- into a networked prop roped to a vehicle (and back into the item when someone unties it). The item leaves the
-- inventory while the machine is being dragged, so it can never exist twice.
local vending = Config.VendingMachines or {}
local cfg = Config.VendingCarry or {}
if vending.Enabled == false or cfg.Enabled == false then return end
local tow = cfg.Tow or {}
local Registry = MetaComic.VendingRegistry
local Vending = MetaComic.Vending
local ITEM = vending.Item or 'vending_machine'
local MODEL = joaat(vending.Model or 'metacomics_vending_machine')
local BODY = joaat((vending.Door or {}).BodyModel or 'metacomics_vending_body')
local tows = {} -- object net id -> { entity, serial, products, cash, vehicle (net id), by (source), byName }
local resource = GetCurrentResourceName()
local recoveryFile = 'data/vending_tow_recovery.json'
local ok, saved = pcall(json.decode, LoadResourceFile(resource, recoveryFile) or '')
local recovery = ok and type(saved) == 'table' and saved or {}
local stopping = false
local finish

-- File writes are synchronous: shutdown must not start inventory/SQL callbacks.
local function saveRecovery()
    local list = {}
    for _, entry in ipairs(recovery) do list[#list + 1] = entry end
    for objectNet, entry in pairs(tows) do
        if DoesEntityExist(entry.entity) then
            local coords = GetEntityCoords(entry.entity)
            entry.coords = { x = coords.x, y = coords.y, z = coords.z }
            entry.heading = GetEntityHeading(entry.entity)
            if GetEntityRoutingBucket then entry.bucket = GetEntityRoutingBucket(entry.entity) end
        end
        list[#list + 1] = { objectNet = objectNet, towId = entry.towId, identifier = entry.identifier,
            serial = entry.serial, products = entry.products, cash = entry.cash, coords = entry.coords,
            heading = entry.heading, bucket = entry.bucket }

    end
    local written = SaveResourceFile(resource, recoveryFile, json.encode(list), -1)
    if not written then print('[meta-comic] Could not save vending tow recovery journal') end
    return written
end

local function notify(source, message, notifyType)
    if MetaComic.Framework.notify then MetaComic.Framework.notify(source, message, notifyType) end
end
local function playerName(source) return Registry.nameOf(source) end
-- a broken-into (stolen) machine's door hangs loose and swings while it moves (client/vending_door.lua)
local function looseDoor(serial) local record = serial and Registry.get(serial); return record ~= nil and record.status == 'stolen' end
local function machineModel(serial)
    return (vending.Door or {}).Enabled ~= false and looseDoor(serial) and BODY or MODEL
end

-- the player's machine items: { slot, metadata, stolen }
local function machineSlots(source)
    local result = {}
    local slots = MetaComic.Inventory.slotsOf and MetaComic.Inventory.slotsOf(source, ITEM) or {}
    for _, slot in pairs(slots) do
        local metadata = slot.metadata or slot.info or {}
        local record = metadata.serial and Registry.get(metadata.serial)
        result[#result + 1] = { slot = slot.slot, metadata = metadata, stolen = record ~= nil and record.status == 'stolen' }
    end
    return result
end

RegisterNetEvent('meta_comic:server:vendingCarryInfo', function()
    local source = source
    local stolen = false
    for _, entry in ipairs(machineSlots(source)) do if entry.stolen then stolen = true end end
    TriggerClientEvent('meta_comic:client:vendingCarryInfo', source, stolen)
end)

local function towList()
    local list = {}
    for objectNet, entry in pairs(tows) do list[objectNet] = { vehicle = entry.vehicle, snapped = entry.snapped == true } end
    return list
end
RegisterNetEvent('meta_comic:server:vendingTows', function() TriggerClientEvent('meta_comic:client:vendingTows', source, towList()) end)

RegisterNetEvent('meta_comic:server:vendingTow', function(vehicleNet)
    local source = source
    if stopping or tow.Enabled == false then return end
    local vehicle = NetworkGetEntityFromNetworkId(tonumber(vehicleNet) or 0)
    if not vehicle or vehicle == 0 or not DoesEntityExist(vehicle) or GetEntityType(vehicle) ~= 2 then return end
    local ped = GetPlayerPed(source)
    if GetVehiclePedIsIn(ped, false) ~= 0 then return end
    if #(GetEntityCoords(ped) - GetEntityCoords(vehicle)) > (tonumber(tow.Distance) or 3.0) + 6.0 then
        return notify(source, 'You are too far from that vehicle.', 'error')
    end
    for _, entry in pairs(tows) do
        if not entry.snapped and entry.vehicle == vehicleNet then return notify(source, 'Something is already tied to that vehicle.', 'error') end
    end
    local chosen
    for _, entry in ipairs(machineSlots(source)) do
        if entry.stolen or tow.StolenOnly == false then chosen = entry; break end
    end
    if not chosen then return notify(source, tow.StolenOnly == false and 'You have no vending machine.' or 'Only stolen machines get dragged around.', 'error') end
    local metadata = chosen.metadata
    local identity = metadata.serial and { serial = metadata.serial } or nil
    if not MetaComic.Inventory.remove(source, ITEM, 1, identity, chosen.slot) then return notify(source, 'Could not take the vending machine item.', 'error') end

    local back = GetEntityCoords(ped)
    local vehicleCoords, heading = GetEntityCoords(vehicle), GetEntityHeading(vehicle)
    local rad = math.rad(heading)
    local length = tonumber(tow.Length) or 6.0
    local spot = vehicleCoords + vector3(math.sin(rad), -math.cos(rad), 0.0) * (2.5 + length * 0.5) -- behind the vehicle
    -- Spawn above the surface and hold it until its owner has loaded collision
    -- and placed the model on the ground (its origin need not be at its base).
    local object = CreateObjectNoOffset(machineModel(metadata.serial), spot.x, spot.y, back.z + 1.0, true, true, false)
    local timeout = GetGameTimer() + 3000
    while not DoesEntityExist(object) and GetGameTimer() < timeout do Wait(0) end
    if not DoesEntityExist(object) then
        Vending.giveMachineItem(source, metadata.serial, metadata.products, metadata.cash)
        return notify(source, 'The machine could not be spawned.', 'error')
    end
    SetEntityHeading(object, heading)
    FreezeEntityPosition(object, true)
    Entity(object).state:set('metaComicTowNeedsGround', true, true)
    if SetEntityOrphanMode then SetEntityOrphanMode(object, 2) end -- keep it when nobody is near (the watchdog below handles deletion)
    local objectNet = NetworkGetNetworkIdFromEntity(object)
    local towId = ('%s:%s:%s'):format(source, objectNet, GetGameTimer())
    Entity(object).state:set('metaComicTowId', towId, true)
    Entity(object).state:set('metaComicDoorLoose', looseDoor(metadata.serial), true)
    tows[objectNet] = { entity = object, serial = metadata.serial, products = metadata.products, cash = metadata.cash, vehicle = vehicleNet,
        by = source, byName = playerName(source), identifier = Registry.identifierOf(source), towId = towId }
    saveRecovery()
    if MetaComic.VendingSecurity then MetaComic.VendingSecurity.track(metadata.serial, object) end
    if metadata.serial then
        Registry.update(metadata.serial, { holder = false, worldState = 'towed' }, ('Dragged behind a vehicle by %s'):format(playerName(source)), playerName(source))
    end
    TriggerClientEvent('meta_comic:client:vendingTow', -1, objectNet, vehicleNet)
    notify(source, 'Preparing the machine and towing rope...', 'info')
    local pending = tows[objectNet]
    SetTimeout(30000, function()
        if tows[objectNet] ~= pending or pending.ready or stopping then return end
        -- Roll back the same transfer, once, only to the original connected
        -- player. If their inventory is full, retain the world cabinet for pickup.
        if GetPlayerPing(source) > 0 and Registry.identifierOf(source) == pending.identifier then
            if finish(objectNet, source) then
                notify(source, 'Towing could not initialize. The machine was returned to you.', 'error')
            else
                notify(source, 'Towing could not initialize. Untie the machine to recover it.', 'error')
            end
        end
    end)
end)

finish = function(objectNet, receiver)
    local entry = tows[objectNet]
    if stopping or not entry or entry.finishing then return false end
    entry.finishing = true
    if receiver and not Vending.giveMachineItem(receiver, entry.serial, entry.products, entry.cash) then
        entry.finishing = nil
        notify(receiver, 'You cannot carry the vending machine.', 'error')
        return false
    end
    tows[objectNet] = nil
    saveRecovery()
    -- Detach client ropes before removing the networked endpoints.
    if DoesEntityExist(entry.entity) then FreezeEntityPosition(entry.entity, true) end
    TriggerClientEvent('meta_comic:client:vendingUntow', -1, objectNet)
    SetTimeout(500, function() if DoesEntityExist(entry.entity) then DeleteEntity(entry.entity) end end)
    if entry.serial then
        if receiver then
            Registry.update(entry.serial, { worldState = false, holder = { id = Registry.identifierOf(receiver), name = playerName(receiver) } },
                ('Untied by %s'):format(playerName(receiver)), playerName(receiver))
        else
            Registry.update(entry.serial, { status = 'removed', holder = false }, 'Lost while being dragged')
        end
    end
    return true
end

RegisterNetEvent('meta_comic:server:vendingTowReady', function(objectNet)
    local entry = tows[tonumber(objectNet) or 0]
    if not entry or entry.finishing or not DoesEntityExist(entry.entity) then return end
    if NetworkGetEntityOwner(entry.entity) ~= source then return end
    -- Release the server-authored freeze as well as the owner's local freeze.
    -- Client-only unfreezing can be overwritten by the replicated server state.
    FreezeEntityPosition(entry.entity, false)
    TriggerClientEvent('meta_comic:client:vendingTowActivate', source, tonumber(objectNet))
    if entry.ready then return end
    entry.ready = true
    if not entry.snapped and entry.by and GetPlayerPing(entry.by) > 0 and Registry.identifierOf(entry.by) == entry.identifier then
        notify(entry.by, 'Machine tied on. Get in and drive.', 'success')
    end
end)

RegisterNetEvent('meta_comic:server:vendingUntow', function(objectNet)
    local source = source
    objectNet = tonumber(objectNet)
    local entry = objectNet and tows[objectNet]
    if not entry then return end
    local coords = GetEntityCoords(GetPlayerPed(source))
    local distance = (tonumber(tow.Distance) or 3.0) + 4.0
    local vehicle = NetworkGetEntityFromNetworkId(entry.vehicle or 0)
    local nearMachine = DoesEntityExist(entry.entity) and #(coords - GetEntityCoords(entry.entity)) <= distance
    local nearVehicle = not entry.snapped and vehicle ~= 0 and DoesEntityExist(vehicle) and #(coords - GetEntityCoords(vehicle)) <= distance
    if not nearMachine and not nearVehicle then
        return notify(source, 'You are too far from the machine.', 'error')
    end
    if finish(objectNet, source) then notify(source, 'You untied the vending machine.', 'success') end
end)

local dropping = {}
RegisterNetEvent('meta_comic:server:vendingCarryDrop', function()
    local source = source
    if stopping or cfg.VehicleEntry ~= 'drop' or dropping[source] then return end
    local chosen = machineSlots(source)[1]
    local ped = GetPlayerPed(source)
    if not chosen or ped == 0 or not DoesEntityExist(ped) then return end
    dropping[source] = true
    local metadata = chosen.metadata
    local coords = GetEntityCoords(ped)
    local heading = math.rad(GetEntityHeading(ped))
    local object = CreateObjectNoOffset(machineModel(metadata.serial), coords.x - math.sin(heading) * 1.3, coords.y + math.cos(heading) * 1.3, coords.z + 1.0, true, true, false)
    local timeout = GetGameTimer() + 3000
    while not DoesEntityExist(object) and GetGameTimer() < timeout do Wait(0) end
    if stopping or not DoesEntityExist(object) then
        if DoesEntityExist(object) then DeleteEntity(object) end
        dropping[source] = nil
        return
    end
    FreezeEntityPosition(object, true)
    local identity = metadata.serial and { serial = metadata.serial } or nil
    if not MetaComic.Inventory.remove(source, ITEM, 1, identity, chosen.slot) then
        DeleteEntity(object)
        dropping[source] = nil
        return notify(source, 'Could not drop the vending machine.', 'error')
    end
    SetEntityHeading(object, GetEntityHeading(ped))
    if SetEntityOrphanMode then SetEntityOrphanMode(object, 2) end
    local objectNet = NetworkGetNetworkIdFromEntity(object)
    local towId = ('drop:%s:%s:%s'):format(source, objectNet, GetGameTimer())
    Entity(object).state:set('metaComicTowId', towId, true)
    Entity(object).state:set('metaComicDoorLoose', looseDoor(metadata.serial), true)
    Entity(object).state:set('metaComicTowNeedsGround', true, true)
    tows[objectNet] = { entity = object, serial = metadata.serial, products = metadata.products, cash = metadata.cash,
        snapped = true, by = source, byName = playerName(source), identifier = Registry.identifierOf(source), towId = towId }
    saveRecovery()
    if MetaComic.VendingSecurity then MetaComic.VendingSecurity.track(metadata.serial, object) end
    TriggerClientEvent('meta_comic:client:vendingRopeSnapped', -1, objectNet)
    if metadata.serial then Registry.update(metadata.serial, { holder = false, worldState = 'ground' }, 'Dropped before entering a vehicle', playerName(source)) end
    dropping[source] = nil
    notify(source, 'Machine dropped. You can pick it up with ox_target.', 'info')
end)

-- Snap decisions use server entity positions/speed, never a client-reported break.
-- The machine stays in the world and retains its serial, stock and cash until pickup.
CreateThread(function()
    local snap = tow.Snap or {}
    if snap.Enabled == false then return end
    local maximumDistance = math.max(0.5, tonumber(tow.Length) or 6.0) + math.max(0.0, tonumber(snap.ExtraDistance) or 3.0)
    local maximumSpeed = math.max(0.0, tonumber(snap.MaxSpeedKmh) or 100.0) / 3.6
    local duration = math.max(0, tonumber(snap.Duration) or 600)
    local grace = math.max(0, tonumber(snap.GracePeriod) or 3000)
    while not stopping do
        Wait(200)
        local now = GetGameTimer()
        for objectNet, entry in pairs(tows) do
            if not entry.snapped and not entry.finishing and DoesEntityExist(entry.entity)
                and Entity(entry.entity).state.metaComicTowNeedsGround == false then
                entry.readyAt = entry.readyAt or now
                local vehicle = NetworkGetEntityFromNetworkId(entry.vehicle)
                local missing = vehicle == 0 or not DoesEntityExist(vehicle)
                local overloaded = missing
                if not missing and now - entry.readyAt >= grace then
                    overloaded = #(GetEntityCoords(entry.entity) - GetEntityCoords(vehicle)) > maximumDistance
                        or (maximumSpeed > 0 and GetEntitySpeed(vehicle) > maximumSpeed)
                end
                if overloaded then
                    entry.overloadedAt = entry.overloadedAt or now
                    if now - entry.overloadedAt >= duration then
                        entry.snapped = true
                        if entry.serial then Registry.update(entry.serial, { worldState = 'ground' }, 'Tow rope snapped; cabinet remains in world') end
                        TriggerClientEvent('meta_comic:client:vendingRopeSnapped', -1, objectNet)
                        if GetPlayerPing(entry.by) > 0 and Registry.identifierOf(entry.by) == entry.identifier then
                            notify(entry.by, 'The towing rope snapped. Pick up the machine where it fell.', 'error')
                        end
                    end
                else
                    entry.overloadedAt = nil -- brief spikes cannot accumulate into a snap
                end
            end
        end
    end
end)

-- Missing props are recorded for later reconciliation; never teleport a cabinet back into inventory.
CreateThread(function()
    while true do
        Wait(5000)
        for objectNet, entry in pairs(tows) do
            if not DoesEntityExist(entry.entity) then
                recovery[#recovery + 1] = { serial = entry.serial, products = entry.products, cash = entry.cash,
                    coords = entry.coords, heading = entry.heading, bucket = entry.bucket, missing = true }
                tows[objectNet] = nil
                TriggerClientEvent('meta_comic:client:vendingUntow', -1, objectNet)
                if entry.serial then Registry.update(entry.serial, { holder = false, worldState = 'missing' }, 'Unplugged cabinet entity missing; no inventory return') end
            end
        end
        if not stopping then saveRecovery() end
    end
end)

AddEventHandler('onResourceStop', function(name)
    if name ~= resource then return end
    stopping = true
    saveRecovery()
    -- Keep endpoints alive while each client tears down its rope on stop.
    -- The next startup recovers these as untied world cabinets, never inventory items.
    for _, entry in pairs(tows) do
        if DoesEntityExist(entry.entity) then FreezeEntityPosition(entry.entity, true) end
    end
end)

CreateThread(function()
    Wait(2000) -- allow client stop handlers to finish before adopting old endpoints
    while not stopping and #recovery > 0 do
        for index = #recovery, 1, -1 do
            local entry = recovery[index]
            if not entry.missing then
                local object = entry.objectNet and NetworkGetEntityFromNetworkId(entry.objectNet) or 0
                -- Net IDs can be reused. Adopt only our exact cabinet; never delete unrelated entities.
                if object == 0 or not DoesEntityExist(object) or not entry.towId or Entity(object).state.metaComicTowId ~= entry.towId then
                    object = 0
                    local coords = entry.coords
                    if type(coords) == 'table' and tonumber(coords.x) and tonumber(coords.y) and tonumber(coords.z) then
                        object = CreateObjectNoOffset(machineModel(entry.serial), coords.x, coords.y, coords.z + 1.0, true, true, false)
                    end
                end
                if object ~= 0 and DoesEntityExist(object) then
                    FreezeEntityPosition(object, true)
                    SetEntityHeading(object, tonumber(entry.heading) or GetEntityHeading(object))
                    if SetEntityRoutingBucket and entry.bucket then SetEntityRoutingBucket(object, entry.bucket) end
                    if SetEntityOrphanMode then SetEntityOrphanMode(object, 2) end
                    local objectNet = NetworkGetNetworkIdFromEntity(object)
                    local towId = ('world:%s:%s'):format(objectNet, GetGameTimer())
                    Entity(object).state:set('metaComicTowId', towId, true)
                    Entity(object).state:set('metaComicDoorLoose', looseDoor(entry.serial), true)
                    Entity(object).state:set('metaComicTowNeedsGround', true, true)
                    tows[objectNet] = { entity = object, serial = entry.serial, products = entry.products, cash = entry.cash,
                        snapped = true, towId = towId, coords = entry.coords, heading = entry.heading, bucket = entry.bucket }
                    table.remove(recovery, index)
                    saveRecovery()
                    if MetaComic.VendingSecurity then MetaComic.VendingSecurity.track(entry.serial, object) end
                    if entry.serial then Registry.update(entry.serial, { holder = false, worldState = 'ground' }, 'Unplugged cabinet recovered in world after restart') end
                    TriggerClientEvent('meta_comic:client:vendingRopeSnapped', -1, objectNet)
                elseif not entry.coords then
                    -- Older journals may lack a reliable location. Keep contents for reconciliation.
                    entry.missing = true
                    if entry.serial then Registry.update(entry.serial, { holder = false, worldState = 'missing' }, 'Recovery location unknown; no inventory return') end
                    saveRecovery()
                end
            end
        end
        Wait(5000)
    end
end)
