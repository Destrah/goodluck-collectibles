-- Reject inventory UI moves on the server, including the reverse leg of swaps.
local vending = Config.VendingMachines or {}
local crates = Config.ShippingCrates or {}
local rules = (Config.VendingCarry or {}).TrunkRestrictions or {}
if vending.Enabled == false and crates.Enabled == false or rules.Enabled == false and not MetaComic.VendingTrunkCargo then return end
local cargoConfig = (Config.VendingCarry or {}).TrunkCargo or {}
local inventoryResource = cargoConfig.Enabled ~= false and (cargoConfig.Inventory or 'ox_inventory') or 'ox_inventory'
local item = vending.Item or 'vending_machine'
local crateItem = crates.Item or 'shipping_crate'
local function cargoItem(name)
    return name == item or name == crateItem and crates.Enabled ~= false and (crates.Carry or {}).TrunkEnabled ~= false
end
local classes = { compacts=0, sedans=1, sedan=1, suvs=2, coupes=3, muscle=4,
    sportsclassics=5, sports=6, sport=6, super=7, motorcycles=8, offroad=9,
    industrial=10, utility=11, vans=12, cycles=13, boats=14, helicopters=15,
    planes=16, service=17, emergency=18, military=19, commercial=20, trains=21, openwheel=22 }
local function classId(value)
    return tonumber(value) or classes[tostring(value):lower():gsub('[%s_-]', '')]
end
local function hash(value) return (tonumber(value) or joaat(value)) & 0xffffffff end
local models, blockedClasses, types, modelClasses, allowedModels = {}, {}, {}, {}, {}
for _, value in ipairs(rules.AllowedModels or {}) do allowedModels[hash(value)] = true end
local mode = rules.Mode or 'blacklist'
for _, value in ipairs(rules.BlockedModels or {}) do models[hash(value)] = true end
for _, value in ipairs(rules.BlockedClasses or {}) do
    local id = classId(value)
    if id then blockedClasses[id] = true else print('[meta-comic] Unknown blocked vehicle class: ' .. tostring(value)) end
end
for _, value in ipairs(rules.BlockedTypes or {}) do types[tostring(value):lower()] = true end
for model, value in pairs(rules.ModelClasses or {}) do modelClasses[hash(model)] = classId(value) end

local function allowed(inventoryId)
    if rules.Enabled == false then return true end
    local cargo = MetaComic.VendingTrunkCargo
    local inventory = cargo and cargo.inventory(inventoryId) or exports[inventoryResource]:GetInventory(inventoryId)
    local vehicle = inventory and inventory.entityId
    if (not vehicle or not DoesEntityExist(vehicle)) and inventory and inventory.netid then
        vehicle = NetworkGetEntityFromNetworkId(inventory.netid)
    end
    -- A stale inventory/entity pair cannot establish which vehicle is allowed.
    if not vehicle or vehicle == 0 or not DoesEntityExist(vehicle) or GetEntityType(vehicle) ~= 2 then return false end
    if inventory.netid and NetworkGetEntityFromNetworkId(inventory.netid) ~= vehicle then return false end
    local model = hash(GetEntityModel(vehicle))
    if (mode == 'allowlist' or mode == 'both') and not allowedModels[model] then return false end
    if (mode == 'blacklist' or mode == 'both') and models[model] then return false end
    if mode ~= 'allowlist' and next(types) and types[tostring(GetVehicleType(vehicle)):lower()] then return false end
    if mode ~= 'allowlist' and next(blockedClasses) then
        local class = modelClasses[model]
        if class == nil and rules.BlockUnknownClass ~= false then return false end
        if class ~= nil and blockedClasses[class] then return false end
    end
    return true
end

local function restrict(payload)
    local cargo = MetaComic.VendingTrunkCargo
    if cargo then
        local ok, message = cargo.check(payload)
        if not ok then
            if MetaComic.Framework.notify then MetaComic.Framework.notify(payload.source, message, 'error') end
            return false
        end
        cargo.changed(payload)
    end
    if mode == 'blacklist' and not next(models) and not next(blockedClasses) and not next(types) then return end
    local trunk
    if payload.toType == 'trunk' and type(payload.fromSlot) == 'table' and cargoItem(payload.fromSlot.name) then
        trunk = payload.toInventory
    elseif payload.action == 'swap' and payload.fromType == 'trunk' and type(payload.toSlot) == 'table' and cargoItem(payload.toSlot.name) then
        trunk = payload.fromInventory
    end
    if not trunk or allowed(trunk) then return end
    if MetaComic.Framework.notify then
        local incoming = trunk == payload.toInventory and payload.fromSlot or payload.toSlot
        local message = incoming and incoming.name == crateItem and (rules.CrateMessage or 'This vehicle cannot store a shipping crate.') or rules.Message or 'This trunk cannot store a vending machine.'
        MetaComic.Framework.notify(payload.source, message, 'error')
    end
    return false
end

local hook
local function register()
    if hook or GetResourceState(inventoryResource) ~= 'started' then return end
    local ok, result = pcall(function()
        if cargoConfig.Adapter and cargoConfig.Adapter.RegisterHook then return cargoConfig.Adapter.RegisterHook(restrict) end
        return exports[inventoryResource]:registerHook('swapItems', restrict, { itemFilter = { [item] = true } })
    end)
    if ok then hook = result else print('[meta-comic] Vending trunk hook could not register: ' .. tostring(result)) end
end
AddEventHandler('onResourceStart', function(name) if name == inventoryResource then register() end end)
AddEventHandler('onResourceStop', function(name)
    if name == inventoryResource then hook = nil
    elseif name == GetCurrentResourceName() and hook and GetResourceState(inventoryResource) == 'started' then
        if cargoConfig.Adapter and cargoConfig.Adapter.RemoveHook then cargoConfig.Adapter.RemoveHook(hook)
        else exports[inventoryResource]:removeHooks(hook) end
    end
end)
CreateThread(register)
