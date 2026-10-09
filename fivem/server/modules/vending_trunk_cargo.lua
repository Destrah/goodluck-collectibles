-- Inventory remains the sole owner of cargo. Replicate placement data, never physical cargo entities.
local cfg = (Config.VendingCarry or {}).TrunkCargo or {}
local vending = Config.VendingMachines or {}
local crates = Config.ShippingCrates or {}
local crateCarry = crates.Carry or {}
if cfg.Enabled == false or (Config.VendingCarry or {}).Enabled == false then return end
local service = {}; MetaComic.VendingTrunkCargo = service
local item, resource = vending.Item or 'vending_machine', GetCurrentResourceName()
local crateItem = crates.Item or 'shipping_crate'
local function supported(name)
    return name == item and vending.Enabled ~= false or name == crateItem and crates.Enabled ~= false and crateCarry.TrunkEnabled ~= false
end
local tracked, pending, probes, stopping = {}, {}, {}, false
local profiles = {}
local function hash(value) return (tonumber(value) or joaat(value)) & 0xffffffff end
for model, value in pairs(cfg.Profiles or {}) do
    local visited = {}
    while type(value) == 'string' and not visited[value] do visited[value] = true;value = cfg.Profiles[value] end
    if type(value) == 'table' and (#(value.Slots or {}) > 0 or #(value.CrateSlots or {}) > 0) then profiles[hash(model)] = value end
end
function service.inventory(id)
    if cfg.Adapter and cfg.Adapter.GetInventory then return cfg.Adapter.GetInventory(id) end
    return exports[cfg.Inventory or 'ox_inventory']:GetInventory(id)
end
local function resolve(id)
    local inventory = service.inventory(id)
    if not inventory or inventory.type and inventory.type ~= 'trunk' then return end
    local vehicle = inventory.entityId
    if (not vehicle or not DoesEntityExist(vehicle)) and inventory.netid then vehicle = NetworkGetEntityFromNetworkId(inventory.netid) end
    if not vehicle or vehicle == 0 or not DoesEntityExist(vehicle) or GetEntityType(vehicle) ~= 2 then return end
    if inventory.netid and NetworkGetEntityFromNetworkId(inventory.netid) ~= vehicle then return end
    return inventory, vehicle, profiles[hash(GetEntityModel(vehicle))]
end
local function count(inventory, name)
    local amount = 0
    for _, slot in pairs(inventory.items or {}) do
        if slot.name == name then amount = amount + (tonumber(slot.count or slot.amount) or 1) end
    end
    return amount
end
local function clear(entry)
    if DoesEntityExist(entry.vehicle) then Entity(entry.vehicle).state:set('metaComicTrunkCargo', nil, true) end
end
function service.refresh(id)
    if stopping then return end
    local inventory, vehicle, profile = resolve(id)
    local old = tracked[id]
    if not profile then if old then clear(old);tracked[id] = nil end;return end
    if old and old.vehicle ~= vehicle then clear(old);old = nil end
    local machineCount = vending.Enabled ~= false and count(inventory,item) or 0
    local crateCount = supported(crateItem) and count(inventory,crateItem) or 0
    local kind = machineCount > 0 and 'machine' or 'crate'
    local placements = kind == 'machine' and profile.Slots or profile.CrateSlots or {}
    local amount = math.min(kind == 'machine' and machineCount or crateCount, #placements)
    if amount == 0 then if old then clear(old) end;tracked[id] = nil;return end
    local entry = old or { vehicle = vehicle }
    tracked[id] = entry
    local changed = not old or entry.amount ~= amount or entry.kind ~= kind
    entry.amount, entry.kind = amount, kind
    if changed then
        local slots = {}
        for index = 1, amount do
            local slot = placements[index]
            local offset, rotation = slot.offset or vec3(0,0,0), slot.rotation or vec3(0,0,0)
            slots[index] = { offset = {x=offset.x,y=offset.y,z=offset.z}, rotation = {x=rotation.x,y=rotation.y,z=rotation.z}, alignBottom = slot.alignBottom == true }
        end
        Entity(vehicle).state:set('metaComicTrunkCargo', { kind = kind, model = kind == 'machine' and (vending.Model or 'metacomics_vending_machine') or ((crates.Models or {}).Closed or 'prop_ld_crate_01'),
            lid = kind == 'crate' and (crates.Models or {}).SeparateLid and (crates.Models or {}).Lid or nil, slots = slots, doors = profile.Doors or {},
            collisionDoors = profile.CollisionDoors or profile.Doors or {}, doorMaxDegrees = tonumber(profile.DoorMaxDegrees) or 110,
            slidingDoors = profile.SlidingDoors, collisionClearance = tonumber(profile.CollisionClearance) or tonumber(cfg.CollisionClearance) or 0.005,
            doorStopAngle = math.max(0.01, math.min(1.0, tonumber(profile.DoorStopAngle) or tonumber(cfg.DoorStopAngle) or 0.25)) }, true)
    end
end
function service.check(payload)
    local additions = {}
    local same = payload.fromInventory == payload.toInventory
    if not same and payload.toType == 'trunk' and type(payload.fromSlot) == 'table' and supported(payload.fromSlot.name) then
        additions[payload.toInventory] = { amount = tonumber(payload.count) or 1, name = payload.fromSlot.name }
    end
    if not same and payload.action == 'swap' and payload.fromType == 'trunk' and type(payload.toSlot) == 'table' and supported(payload.toSlot.name) then
        additions[payload.fromInventory] = { amount = tonumber(payload.toSlot.count) or 1, name = payload.toSlot.name }
    end
    for id, addition in pairs(additions) do
        local amount, name = addition.amount, addition.name
        if amount <= 0 or amount % 1 ~= 0 then return false, 'Invalid vending machine quantity.' end
        local inventory, vehicle, profile = resolve(id)
        if not profile then return false, 'This vehicle needs a configured vending cargo profile before loading a machine.' end
        local placements = (name == item and profile.Slots or profile.CrateSlots) or {}
        local total = count(inventory,name) + amount
        local otherName = name == item and crateItem or item
        local otherCount = supported(otherName) and count(inventory,otherName) or 0
        -- A reverse swap removes its outgoing machine as well.
        if payload.action == 'swap' then
            local outgoing = id == payload.toInventory and payload.toSlot or payload.fromSlot
            if type(outgoing) == 'table' then
                if outgoing.name == name then total = total - (tonumber(outgoing.count) or 1) end
                if outgoing.name == otherName then otherCount = otherCount - (tonumber(outgoing.count) or 1) end
            end
        end
        -- Both layouts occupy the same cargo bay. Do not overlap independent machine/crate layouts.
        if otherCount > 0 then return false, 'Unload the other cargo type before loading machines or shipping crates.' end
        if total > #placements then return false, 'There is no configured space for another ' .. (name == item and 'vending machine' or 'shipping crate') .. ' in this vehicle.' end
        for _, door in ipairs(profile.Doors or {}) do
            if not GetVehicleDoorStatus or GetVehicleDoorStatus(vehicle, door) < (tonumber(cfg.DoorMinimum) or 3) then
                return false, 'Open both rear cargo doors fully before loading the vending machine.'
            end
        end
    end
    return true
end
function service.changed(payload)
    for _, side in ipairs({'from','to'}) do
        local id = payload[side .. 'Inventory']
        if payload[side .. 'Type'] == 'trunk' and not pending[id] then
            pending[id] = true
            SetTimeout(200, function()
                pending[id] = nil
                if not stopping then local ok, err = pcall(service.refresh, id);if not ok then print('[meta-comic] trunk cargo refresh: ' .. tostring(err)) end end
            end)
        end
    end
end
-- Restore loaded trunks after this resource restarts, including older ox versions without GetInventories.
RegisterNetEvent('meta_comic:server:vendingTrunkProbe', function(net)
    local src, now = source, GetGameTimer()
    if stopping or now - (probes[src] or -5000) < 1000 then return end
    probes[src] = now
    local vehicle = NetworkGetEntityFromNetworkId(tonumber(net) or 0)
    local ped = GetPlayerPed(src)
    if vehicle == 0 or not DoesEntityExist(vehicle) or GetEntityType(vehicle) ~= 2 or not profiles[hash(GetEntityModel(vehicle))]
        or ped == 0 or GetEntityRoutingBucket(vehicle) ~= GetPlayerRoutingBucket(src) or #(GetEntityCoords(ped) - GetEntityCoords(vehicle)) > 60 then return end
    if cfg.Adapter then return end -- custom resources restore through RefreshVendingTrunkCargo
    local plate = GetVehicleNumberPlateText(vehicle)
    if not plate or plate == '' then return end
    if GetConvarInt('inventory:trimplate', 1) == 1 then plate = plate:gsub('%s+', '') end
    local id = 'trunk' .. plate
    local ok, inventory, actual = pcall(resolve, id)
    if ok and inventory and actual == vehicle then pcall(service.refresh, id) end
end)
exports('RefreshVendingTrunkCargo', service.refresh)
exports('CanMoveVendingTrunkCargo', service.check)
AddEventHandler('playerDropped', function() probes[source] = nil end)
CreateThread(function()
    Wait(1500)
    local ok, inventories = pcall(function()
        if cfg.Adapter and cfg.Adapter.LoadedTrunks then return cfg.Adapter.LoadedTrunks() end
        return exports[cfg.Inventory or 'ox_inventory']:GetInventories('trunk', true)
    end)
    if ok then for _, inventory in pairs(inventories or {}) do service.refresh(type(inventory) == 'table' and inventory.id or inventory);Wait(0) end end
    while not stopping do
        Wait(math.max(500, tonumber(cfg.CheckInterval) or 1000))
        for id in pairs(tracked) do
            local ok, err = pcall(service.refresh, id)
            if not ok then print('[meta-comic] trunk cargo refresh: ' .. tostring(err)) end
            Wait(0)
        end
    end
end)
AddEventHandler('onResourceStop', function(name)
    if name ~= resource and name ~= (cfg.Inventory or 'ox_inventory') then return end
    if name == resource then stopping = true end
    for id, entry in pairs(tracked) do clear(entry);tracked[id] = nil end
end)
