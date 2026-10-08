-- Carrying a vending machine item (Config.VendingCarry): while it is in the inventory the player pushes it on a dolly,
-- walking only (no sprint, jump, weapons), until they get into a vehicle. Stolen machines can be tied to the back of a
-- vehicle with a rope (ox_target on the vehicle) and dragged; untie it (ox_target on the machine) to load it back up.
local vending = Config.VendingMachines or {}
local cfg = Config.VendingCarry or {}
if vending.Enabled == false or cfg.Enabled == false then return end

local ITEM = vending.Item or 'vending_machine'
local MODEL = vending.Model or 'metacomics_vending_machine'
local BODY = (vending.Door or {}).BodyModel or 'metacomics_vending_body'
local dollyCfg, machineCfg, anim = cfg.Dolly or {}, cfg.Machine or {}, cfg.Animation or {}
local tow = cfg.Tow or {}
local BLOCKED = { 21, 22, 24, 25, 37, 44, 45, 47, 58, 140, 141, 142, 143, 257, 263, 264 } -- sprint, jump, attack, aim, cover, weapons

local carrying, stolen, busy = false, false, false -- busy: tying the rope (its own animation plays)
local props = {} -- dolly / machine entities attached to the player
local ropes = {} -- object net id -> { rope, vehicle net id }
local looseMachines = {} -- snapped machines remain available for pickup
local stopping = false

local function notify(message, notifyType) TriggerEvent('meta_comic:client:notify', message, notifyType) end
local function vec(value, default) return value and vector3(value.x + 0.0, value.y + 0.0, value.z + 0.0) or default end
local function loadModel(name)
    local hash = type(name) == 'number' and name or joaat(name)
    if not IsModelInCdimage(hash) then return nil end
    RequestModel(hash)
    local timeout = GetGameTimer() + 5000
    while not HasModelLoaded(hash) and GetGameTimer() < timeout do Wait(0) end
    return HasModelLoaded(hash) and hash or nil
end
local function loadDict(dict)
    RequestAnimDict(dict)
    local timeout = GetGameTimer() + 3000
    while not HasAnimDictLoaded(dict) and GetGameTimer() < timeout do Wait(0) end
    return HasAnimDictLoaded(dict)
end

-- how many machine items the player holds
local function heldCount()
    if GetResourceState('ox_inventory') == 'started' then
        local ok, count = pcall(function() return exports.ox_inventory:GetItemCount(ITEM) end)
        return ok and tonumber(count) or 0
    end
    local core = GetResourceState('qb-core') == 'started' and exports['qb-core']:GetCoreObject() or nil
    local data = core and core.Functions.GetPlayerData() or {}
    local total = 0
    for _, item in pairs(data.items or {}) do
        if item and item.name == ITEM then total = total + (tonumber(item.amount or item.count) or 1) end
    end
    return total
end

local function removeProps()
    local ped = PlayerPedId()
    for _, entity in pairs(props) do if DoesEntityExist(entity) then DetachEntity(entity, true, false); DeleteEntity(entity) end end
    props = {}
    if anim.dict then StopAnimTask(ped, anim.dict, anim.clip, 1.0) end
end

-- Offsets locate the machine's base on the dolly, rather than its model origin.
-- Custom vending models can have their origin halfway up the cabinet.
local function machineBaseOffset(hash, offset, rotation)
    local minimum, maximum = GetModelDimensions(hash)
    local rx, ry = math.rad(rotation.x), math.rad(rotation.y)
    local sx, cx, sy, cy = math.sin(rx), math.cos(rx), math.sin(ry), math.cos(ry)
    local bottom = math.huge
    -- Rotation order 2 is ZXY; Z rotation does not change the local height.
    for _, x in ipairs({ minimum.x, maximum.x }) do
        for _, y in ipairs({ minimum.y, maximum.y }) do
            for _, z in ipairs({ minimum.z, maximum.z }) do
                bottom = math.min(bottom, -cx * sy * x + sx * y + cx * cy * z)
            end
        end
    end
    return vector3(offset.x, offset.y, offset.z - bottom)
end

local function attachProps()
    local ped = PlayerPedId()
    local coords = GetEntityCoords(ped)
    local dollyHash = dollyCfg.model and loadModel(dollyCfg.model)
    local machineHash = loadModel(MODEL)
    if stopping or not carrying then return end
    local base = ped
    if dollyHash then
        local dolly = CreateObject(dollyHash, coords.x, coords.y, coords.z - 5.0, true, true, false)
        SetEntityCollision(dolly, false, false)
        -- Bone 0 is the animated skeleton root; use the entity origin to avoid walking sway.
        local bone = dollyCfg.bone and dollyCfg.bone ~= 0 and GetPedBoneIndex(ped, dollyCfg.bone) or -1
        AttachEntityToEntity(dolly, ped, bone, vec(dollyCfg.offset, vector3(0.0, 0.9, -0.93)),
            vec(dollyCfg.rotation, vector3(-20.0, 0.0, 180.0)), true, false, false, false, 2, true)
        SetModelAsNoLongerNeeded(dollyHash)
        props.dolly = dolly
        base = dolly
    end
    if machineHash then
        local machine = CreateObject(machineHash, coords.x, coords.y, coords.z - 5.0, true, true, false)
        SetEntityCollision(machine, false, false)
        if base == ped then
            local rotation = vector3(0.0, 0.0, 180.0)
            AttachEntityToEntity(machine, ped, -1, machineBaseOffset(machineHash, vector3(0.0, 1.0, -0.98), rotation), rotation, true, false, false, false, 2, true)
        else
            local rotation = vec(machineCfg.rotation, vector3(0.0, 0.0, 0.0))
            local offset = machineBaseOffset(machineHash, vec(machineCfg.offset, vector3(0.0, -0.1, 0.05)), rotation)
            AttachEntityToEntity(machine, base, -1, offset, rotation,
                true, false, false, false, 2, true)
        end
        SetModelAsNoLongerNeeded(machineHash)
        props.machine = machine
        Entity(machine).state:set('metaComicDoorLoose', stolen, true) -- broken-into: its door swings (client/vending_door.lua)
    end
    if anim.dict and loadDict(anim.dict) then TaskPlayAnim(ped, anim.dict, anim.clip, 3.0, 3.0, -1, anim.flag or 49, 0, false, false, false) end
    SetCurrentPedWeapon(ped, joaat("WEAPON_UNARMED"), true)
end

local function canShow(ped)
    return not IsPedInAnyVehicle(ped, true) and not IsPedSwimming(ped) and not IsPedRagdoll(ped) and not IsEntityDead(ped)
        and not IsPedClimbing(ped) and not IsPedFalling(ped)
end

-- the walking loop while a machine is held
local function carryLoop()
    local rate = tonumber(cfg.MoveRate) or 0.85
    local nextEntryAttempt = 0
    while carrying do
        local ped = PlayerPedId()
        -- Hold entry until the server has removed the item, including scripted entry tasks.
        DisableControlAction(0, 23, true)
        local entering = GetVehiclePedIsTryingToEnter(ped)
        local inside = GetVehiclePedIsIn(ped, false)
        if (IsDisabledControlJustPressed(0, 23) or entering ~= 0 or inside ~= 0) and GetGameTimer() >= nextEntryAttempt then
            nextEntryAttempt = GetGameTimer() + 1500
            if inside ~= 0 then TaskLeaveVehicle(ped, inside, 16)
            elseif entering ~= 0 then ClearPedTasks(ped) end
            if cfg.VehicleEntry == 'drop' then
                TriggerServerEvent('meta_comic:server:vendingCarryDrop')
            else
                notify('Put down or store the vending machine before entering a vehicle.', 'error')
            end
        end
        if canShow(ped) then
            if not props.machine and not props.dolly then attachProps() end
            for _, control in ipairs(BLOCKED) do DisableControlAction(0, control, true) end
            DisablePlayerFiring(PlayerId(), true)
            SetPedMaxMoveBlendRatio(ped, 1.0) -- walk, never jog / run
            SetPedMoveRateOverride(ped, rate)
            if not busy and anim.dict and not IsEntityPlayingAnim(ped, anim.dict, anim.clip, 3) and HasAnimDictLoaded(anim.dict) then
                TaskPlayAnim(ped, anim.dict, anim.clip, 3.0, 3.0, -1, anim.flag or 49, 0, false, false, false)
            end
            Wait(0)
        else
            if props.machine or props.dolly then removeProps() end
            Wait(250)
        end
    end
    removeProps()
end

CreateThread(function()
    while true do
        local held = heldCount() > 0
        if held and not carrying then
            carrying = true
            TriggerServerEvent('meta_comic:server:vendingCarryInfo')
            CreateThread(carryLoop)
        elseif not held and carrying then
            carrying, stolen = false, false
        end
        Wait(carrying and 1000 or 1500)
    end
end)
RegisterNetEvent('meta_comic:client:vendingCarryInfo', function(isStolen)
    stolen = isStolen == true
    if props.machine and DoesEntityExist(props.machine) then Entity(props.machine).state:set('metaComicDoorLoose', stolen, true) end
end)

-- Ropes ----------------------------------------------------------------------------------------------------------------
local function entityOf(netId)
    if not netId or not NetworkDoesNetworkIdExist(netId) then return nil end
    local entity = NetworkGetEntityFromNetworkId(netId)
    return entity ~= 0 and DoesEntityExist(entity) and entity or nil
end
local function dropRope(objectNet)
    local entry = ropes[objectNet]
    if entry and entry.rope and DoesRopeExist(entry.rope) then
        local object, vehicle = entityOf(objectNet), entityOf(entry.vehicle)
        if object then DetachRopeFromEntity(entry.rope, object) end
        if vehicle then DetachRopeFromEntity(entry.rope, vehicle) end
        DeleteRope(entry.rope)
    end
    ropes[objectNet] = nil
end
local function rearOf(vehicle)
    local minimum = GetModelDimensions(GetEntityModel(vehicle))
    return GetOffsetFromEntityInWorldCoords(vehicle, 0.0, minimum.y - 0.05, 0.1)
end
local function applyTowPhysics(object)
    local physics = tow.Physics or {}
    if physics.Enabled ~= false then
        local mass = math.max(1.0, math.min(10000.0, tonumber(physics.Mass) or 250.0))
        local linear = math.max(0.0, math.min(10.0, tonumber(physics.LinearDamping) or 0.1))
        local angular = math.max(0.0, math.min(10.0, tonumber(physics.AngularDamping) or 0.5))
        SetObjectPhysicsParams(object, mass, math.max(0.0, math.min(10.0, tonumber(physics.Gravity) or 1.0)),
            0.0, linear, 0.0, 0.0, angular, 0.0, 0.05, 10.0, 1.0)
    end
    SetEntityDynamic(object, true)
    SetActivateObjectPhysicsAsSoonAsItIsUnfrozen(object, true)
    SetEntityHasGravity(object, true)
    FreezeEntityPosition(object, false)
    ActivatePhysics(object)
end
RegisterNetEvent('meta_comic:client:vendingTowActivate', function(objectNet)
    local object = entityOf(objectNet)
    if object and NetworkHasControlOfEntity(object) and (ropes[objectNet] or looseMachines[objectNet]) then
        applyTowPhysics(object)
    end
end)
-- Only the network owner may move the shared cabinet. Ground discovery and
-- collision streaming can finish on different frames; keep gravity off until both do.
local function groundMachine(object)
    FreezeEntityPosition(object, true)
    SetEntityHasGravity(object, false)
    SetEntityCollision(object, true, true)
    SetEntityLoadCollisionFlag(object, true)
    local model = GetEntityModel(object)
    RequestModel(model)
    RequestCollisionForModel(model)
    local coords = GetEntityCoords(object)
    RequestCollisionAtCoord(coords.x, coords.y, coords.z)
    if not HasModelLoaded(model) or not HasCollisionLoadedAroundEntity(object) then return false end
    local found, ground = GetGroundZFor_3dCoord(coords.x, coords.y, coords.z + 50.0, false)
    if not found then return false end
    -- The cabinet origin is midway up its mesh, not at its feet. In particular,
    -- the vehicle/player height is not the ground height behind an elevated rear.
    local minimum = GetModelDimensions(model)
    SetEntityRotation(object, 0.0, 0.0, GetEntityHeading(object), 2, true)
    SetEntityCoordsNoOffset(object, coords.x, coords.y, ground - minimum.z + 0.15, false, false, false)
    -- This native can report false for frozen props even after their feet were
    -- placed correctly. Ground discovery and model bounds are the authority.
    PlaceObjectOnGroundProperly(object)
    local placed = GetEntityCoords(object)
    if placed.z + minimum.z < ground - 0.1 then
        SetEntityCoordsNoOffset(object, coords.x, coords.y, ground - minimum.z + 0.15, false, false, false)
    end
    SetEntityVelocity(object, 0.0, 0.0, 0.0)
    Entity(object).state:set('metaComicTowNeedsGround', false, true)
    SetModelAsNoLongerNeeded(model)
    return true
end
local function makeRope(objectNet, vehicleNet)
    if stopping then return false end
    local pending = ropes[objectNet]
    if not pending then return false end
    local object, vehicle = entityOf(objectNet), entityOf(vehicleNet)
    if not object or not vehicle then return false end
    if NetworkHasControlOfEntity(vehicle) and not NetworkHasControlOfEntity(object) then
        NetworkRequestControlOfEntity(object)
    end
    SetEntityCollision(object, true, true)
    SetEntityLoadCollisionFlag(object, true)
    local state = Entity(object).state
    if state.metaComicTowNeedsGround == nil then return false end -- wait for server initialization
    if state.metaComicTowNeedsGround then
        -- Only the network owner positions the shared object. Other clients retry
        -- once that position is replicated, including on later stream-in.
        if not NetworkHasControlOfEntity(object) then return false end
        if not groundMachine(object) then return false end
    end
    RopeLoadTextures()
    local timeout = GetGameTimer() + 3000
    while not RopeAreTexturesLoaded() and GetGameTimer() < timeout do Wait(0) end
    if stopping or ropes[objectNet] ~= pending or not RopeAreTexturesLoaded() or not DoesEntityExist(object) or not DoesEntityExist(vehicle) then return false end
    local length = tonumber(tow.Length) or 6.0
    local from, to = rearOf(vehicle), GetOffsetFromEntityInWorldCoords(object, 0.0, 0.0, 0.6)
    local rope = AddRope(from.x, from.y, from.z, 0.0, 0.0, 0.0, length, 4, length, 0.5, 0.5, false, false, false, 1.0, false, 0)
    if not DoesRopeExist(rope) then return false end
    local owner = NetworkHasControlOfEntity(object) and NetworkHasControlOfEntity(vehicle)
    if owner then
        -- One client simulates the shared cabinet. Spectators draw a pinned
        -- rope, avoiding duplicate physics constraints on the same car.
        AttachEntitiesToRope(rope, vehicle, object, from.x, from.y, from.z, to.x, to.y, to.z, length, false, false, nil, nil)
        applyTowPhysics(object)
        TriggerServerEvent('meta_comic:server:vendingTowReady', objectNet)
    else
        PinRopeVertex(rope, 0, from.x, from.y, from.z)
        PinRopeVertex(rope, GetRopeVertexCount(rope) - 1, to.x, to.y, to.z)
    end
    ropes[objectNet] = { rope = rope, vehicle = vehicleNet, physicsOwner = owner }
    return true
end
RegisterNetEvent('meta_comic:client:vendingTow', function(objectNet, vehicleNet)
    if stopping then return end
    looseMachines[objectNet] = nil
    dropRope(objectNet)
    local entry = { vehicle = vehicleNet, pending = true, creating = true }
    ropes[objectNet] = entry
    CreateThread(function()
        local timeout = GetGameTimer() + 10000
        while not stopping and ropes[objectNet] == entry do
            if makeRope(objectNet, vehicleNet) then return end
            if GetGameTimer() > timeout then entry.creating = nil; return end
            Wait(250)
        end
    end)
end)
RegisterNetEvent('meta_comic:client:vendingUntow', function(objectNet) dropRope(objectNet); looseMachines[objectNet] = nil end)
RegisterNetEvent('meta_comic:client:vendingRopeSnapped', function(objectNet)
    dropRope(objectNet)
    looseMachines[objectNet] = {}
end)
RegisterNetEvent('meta_comic:client:vendingTows', function(list)
    for key, entry in pairs(list or {}) do
        local objectNet = tonumber(key)
        if type(entry) == 'table' and entry.snapped then
            dropRope(objectNet)
            looseMachines[objectNet] = {}
        elseif not ropes[objectNet] then
            ropes[objectNet] = { vehicle = type(entry) == 'table' and entry.vehicle or entry, pending = true }
        end
    end
end)
-- ropes come and go with the entities (out of range, deleted vehicle)
CreateThread(function()
    while true do
        for objectNet, entry in pairs(ropes) do
            local object, vehicle = entityOf(objectNet), entityOf(entry.vehicle)
            if entry.rope and (not object or not vehicle) then
                dropRope(objectNet)
                ropes[objectNet] = { vehicle = entry.vehicle, pending = true }
            elseif entry.pending and not entry.creating and object and vehicle then makeRope(objectNet, entry.vehicle)
            elseif entry.rope and object then
                if vehicle and NetworkHasControlOfEntity(vehicle) and not NetworkHasControlOfEntity(object) then
                    NetworkRequestControlOfEntity(object)
                end
                local owner = vehicle and NetworkHasControlOfEntity(object) and NetworkHasControlOfEntity(vehicle) or false
                if owner ~= entry.physicsOwner then
                    local vehicleNet = entry.vehicle
                    dropRope(objectNet)
                    ropes[objectNet] = { vehicle = vehicleNet, pending = true }
                elseif not owner and vehicle then
                    local from, to = rearOf(vehicle), GetOffsetFromEntityInWorldCoords(object, 0.0, 0.0, 0.6)
                    PinRopeVertex(entry.rope, 0, from.x, from.y, from.z)
                    PinRopeVertex(entry.rope, GetRopeVertexCount(entry.rope) - 1, to.x, to.y, to.z)
                end
            end
        end
        for objectNet, entry in pairs(looseMachines) do
            local object = entityOf(objectNet)
            local owner = object and NetworkHasControlOfEntity(object) or false
            if owner and not entry.physicsOwner then
                local state = Entity(object).state
                if state.metaComicTowNeedsGround then
                    if not groundMachine(object) then
                        owner = false -- retry ground placement before enabling gravity
                    end
                elseif state.metaComicTowNeedsGround == nil then
                    owner = false
                end
                if owner then
                    applyTowPhysics(object)
                    TriggerServerEvent('meta_comic:server:vendingTowReady', objectNet)
                end
            end
            entry.physicsOwner = owner
        end
        Wait(100)
    end
end)
CreateThread(function() Wait(2000); TriggerServerEvent('meta_comic:server:vendingTows') end)

-- ox_target --------------------------------------------------------------------------------------------------------------
local function runProgress(label, ms)
    if GetResourceState('ox_lib') == 'started' then
        return exports.ox_lib:progressBar({ duration = ms, label = label, useWhileDead = false, canCancel = true, disable = { move = true, car = true, combat = true },
            anim = { dict = 'mini@repair', clip = 'fixing_a_ped', flag = 49 } })
    end
    local ped = PlayerPedId()
    if loadDict('mini@repair') then TaskPlayAnim(ped, 'mini@repair', 'fixing_a_ped', 3.0, 3.0, ms, 49, 0, false, false, false) end
    Wait(ms)
    StopAnimTask(ped, 'mini@repair', 'fixing_a_ped', 1.0)
    return true
end
local function behind(vehicle)
    local ped = PlayerPedId()
    local offset = GetOffsetFromEntityGivenWorldCoords(vehicle, GetEntityCoords(ped))
    local minimum = GetModelDimensions(GetEntityModel(vehicle))
    return offset.y < minimum.y + 1.2
end
local function progress(label, ms)
    busy = true
    local done = runProgress(label, ms)
    busy = false
    return done
end
local function towedBy(vehicle)
    if not NetworkGetEntityIsNetworked(vehicle) then return nil end
    local netId = VehToNet(vehicle)
    for objectNet, entry in pairs(ropes) do
        if entry.vehicle == netId then return objectNet end
    end
end
CreateThread(function()
    if tow.Enabled == false then return end
    local timeout = GetGameTimer() + 30000
    while GetResourceState('ox_target') ~= 'started' do
        if GetGameTimer() > timeout or GetResourceState('ox_target') == 'missing' then return end
        Wait(500)
    end
    local distance = tonumber(tow.Distance) or 3.0
    exports.ox_target:addGlobalVehicle({ {
        name = 'meta_comic_vending_tow', label = tow.Label or 'Tie vending machine', icon = tow.Icon or 'fas fa-link', distance = distance,
        canInteract = function(entity)
            return not busy and not towedBy(entity) and carrying and (stolen or tow.StolenOnly == false) and not IsPedInAnyVehicle(PlayerPedId(), true) and behind(entity)
        end,
        onSelect = function(data)
            if not progress(tow.ProgressLabel or 'Tying the machine on', tonumber(tow.Duration) or 4000) then return end
            if DoesEntityExist(data.entity) then TriggerServerEvent('meta_comic:server:vendingTow', VehToNet(data.entity)) end
        end,
    }, {
        name = 'meta_comic_vending_untow_vehicle', label = tow.UntieLabel or 'Untie vending machine', icon = 'fas fa-link-slash', distance = distance,
        canInteract = function(entity)
            return not busy and not IsPedInAnyVehicle(PlayerPedId(), true) and behind(entity) and towedBy(entity) ~= nil
        end,
        onSelect = function(data)
            local objectNet = towedBy(data.entity)
            if not objectNet then return end
            if not progress(tow.UntieProgressLabel or 'Untying the machine', tonumber(tow.UntieDuration) or 3000) then return end
            if DoesEntityExist(data.entity) and towedBy(data.entity) == objectNet then
                TriggerServerEvent('meta_comic:server:vendingUntow', objectNet)
            end
        end,
    } })
    exports.ox_target:addModel({ MODEL, BODY }, { {
        name = 'meta_comic_vending_untow', label = tow.UntieLabel or 'Untie vending machine', icon = 'fas fa-link-slash', distance = distance,
        canInteract = function(entity) return not busy and NetworkGetEntityIsNetworked(entity) and ropes[NetworkGetNetworkIdFromEntity(entity)] ~= nil end,
        onSelect = function(data)
            if not progress(tow.UntieProgressLabel or 'Untying the machine', tonumber(tow.UntieDuration) or 3000) then return end
            if DoesEntityExist(data.entity) then TriggerServerEvent('meta_comic:server:vendingUntow', NetworkGetNetworkIdFromEntity(data.entity)) end
        end,
    }, {
        name = 'meta_comic_vending_pickup_snapped', label = tow.PickupLabel or 'Pick up vending machine', icon = 'fas fa-dolly', distance = distance,
        canInteract = function(entity)
            return not busy and NetworkGetEntityIsNetworked(entity) and looseMachines[NetworkGetNetworkIdFromEntity(entity)] ~= nil
        end,
        onSelect = function(data)
            if not progress(tow.PickupLabel or 'Picking up vending machine', tonumber(tow.UntieDuration) or 3000) then return end
            if DoesEntityExist(data.entity) then TriggerServerEvent('meta_comic:server:vendingUntow', NetworkGetNetworkIdFromEntity(data.entity)) end
        end,
    } })
end)

AddEventHandler('onResourceStop', function(name)
    if name ~= GetCurrentResourceName() then return end
    stopping = true
    carrying = false
    removeProps()
    for objectNet in pairs(ropes) do dropRope(objectNet) end
end)
