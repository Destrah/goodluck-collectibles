-- Shipping crate opening in the world (Config.ShippingCrates): the crate prop is set on the ground in front of the
-- player, who pries it open with a crowbar; once the server has handed out the contents the closed crate is swapped
-- for the open one, the lid comes off, and the 3D reveal of what was inside plays in the NUI.
local cfg = Config.ShippingCrates or {}
if cfg.Enabled == false then return end

local scene = { objects = {} }
local busy = false
local openingRun = 0

local function notify(message, notifyType) TriggerEvent('meta_comic:client:notify', message, notifyType) end
local function loadModel(model)
    if not model then return nil end
    local hash = type(model) == 'number' and model or joaat(model)
    if not IsModelInCdimage(hash) then return nil end
    RequestModel(hash)
    local timeout = GetGameTimer() + 5000
    while not HasModelLoaded(hash) and GetGameTimer() < timeout do Wait(0) end
    return HasModelLoaded(hash) and hash or nil
end
local function loadDict(dict)
    if not dict then return false end
    RequestAnimDict(dict)
    local timeout = GetGameTimer() + 3000
    while not HasAnimDictLoaded(dict) and GetGameTimer() < timeout do Wait(0) end
    return HasAnimDictLoaded(dict)
end
local function spawn(model, coords, heading, networked)
    local hash = loadModel(model)
    if not hash then return nil end
    local object = CreateObjectNoOffset(hash, coords.x, coords.y, coords.z, networked == true, false, false)
    SetEntityHeading(object, heading or 0.0)
    FreezeEntityPosition(object, true)
    SetModelAsNoLongerNeeded(hash)
    scene.objects[#scene.objects + 1] = object
    return object
end
local function clearScene()
    for _, object in ipairs(scene.objects) do if DoesEntityExist(object) then DeleteEntity(object) end end
    scene = { objects = {} }
end

-- a spot on the ground in front of the player, the crate's base resting on it
local function groundSpot(hash, distance)
    local ped = PlayerPedId()
    local coords = GetOffsetFromEntityInWorldCoords(ped, 0.0, distance, 0.0)
    local found, z = GetGroundZFor_3dCoord(coords.x, coords.y, coords.z + 1.0, false)
    local minimum = hash and GetModelDimensions(hash) or vector3(0, 0, 0)
    return vector3(coords.x, coords.y, (found and z or coords.z - 0.95) - minimum.z), GetEntityHeading(ped) + 180.0
end

local function useCrate(...)
    for i = 1, select('#', ...) do
        local value = select(i, ...)
        if type(value) == 'table' and tonumber(value.slot) then return TriggerServerEvent('meta_comic:server:crateUse', tonumber(value.slot)) end
        if tonumber(value) then return TriggerServerEvent('meta_comic:server:crateUse', tonumber(value)) end
    end
end
exports('UseShippingCrate', useCrate) -- ox_inventory item: client = { export = '<resource>.UseShippingCrate' }

RegisterNetEvent('meta_comic:client:crateStart', function(data)
    if busy then return end
    busy = true
    openingRun = openingRun + 1
    local run = openingRun
    TriggerEvent('meta_comic:client:crateCarryPause', true)
    clearScene()
    local models = data.models or cfg.Models or {}
    local closedHash = loadModel(models.Closed)
    local spot, heading = groundSpot(closedHash, (cfg.Scene and cfg.Scene.Distance) or 1.3)
    scene.coords, scene.heading = spot, heading
    scene.crate = closedHash and spawn(models.Closed, spot, heading, cfg.Scene and cfg.Scene.Networked ~= false) or nil
    if scene.crate then PlaceObjectOnGroundProperly(scene.crate); scene.coords = GetEntityCoords(scene.crate) end
    if scene.crate and models.SeparateLid and models.Lid then
        local lidHash = loadModel(models.Lid)
        if lidHash then
            local minimum,maximum = GetModelDimensions(closedHash)
            local lidMin,lidMax = GetModelDimensions(lidHash)
            local o = MetaComic.VendingCargoGeometry.topAttachment(minimum,maximum,lidMin,lidMax)
            scene.lid = spawn(models.Lid,scene.coords,heading,cfg.Scene and cfg.Scene.Networked ~= false)
            if scene.lid then
                SetEntityCollision(scene.lid,false,false)
                AttachEntityToEntity(scene.lid,scene.crate,-1,o.x,o.y,o.z,0.0,0.0,0.0,false,false,false,false,2,true)
            end
        end
    end

    local ped = PlayerPedId()
    TaskTurnPedToFaceCoord(ped, spot.x, spot.y, spot.z, 800)
    Wait(800)
    local anim = cfg.Animation or {}
    local finished
    if GetResourceState('ox_lib') == 'started' then
        finished = exports.ox_lib:progressBar({
            duration = data.duration, label = ('Opening %s'):format(data.label or 'the crate'),
            canCancel = true, disable = { move = true, car = true, combat = true },
            anim = anim.dict and { dict = anim.dict, clip = anim.clip, flag = anim.flag or 1 } or nil,
            prop = anim.prop and { model = anim.prop, bone = anim.bone or 57005, pos = anim.pos or vec3(0.08, 0.02, -0.02), rot = anim.rot or vec3(-80.0, 0.0, 0.0) } or nil,
        })
    else
        if loadDict(anim.dict) then TaskPlayAnim(ped, anim.dict, anim.clip, 3.0, 3.0, data.duration, anim.flag or 1, 0, false, false, false) end
        Wait(data.duration)
        ClearPedTasks(ped)
        finished = true
    end
    if finished then
        TriggerServerEvent('meta_comic:server:crateFinish')
        SetTimeout(10000, function()
            if openingRun ~= run then return end
            busy = false;TriggerEvent('meta_comic:client:crateCarryPause', false)
        end) -- server answers or opening failed
    else
        TriggerServerEvent('meta_comic:server:crateCancel')
        clearScene()
        busy = false
        TriggerEvent('meta_comic:client:crateCarryPause', false)
        notify('Stopped opening the crate.', 'info')
    end
end)

-- the lid lifts, drifts back and tips onto the ground behind the crate
local function animateLid(lid, from, heading)
    local offset = (cfg.Scene and cfg.Scene.LidLanding) or vector3(0.0, -1.0, 0.0)
    local rad = math.rad(heading)
    local landing = vector3(from.x + offset.x * math.cos(rad) - offset.y * math.sin(rad), from.y + offset.x * math.sin(rad) + offset.y * math.cos(rad), from.z + offset.z)
    local found, groundZ = GetGroundZFor_3dCoord(landing.x, landing.y, landing.z + 2.0, false)
    if found then landing = vector3(landing.x, landing.y, groundZ + 0.05) end
    local start, duration = GetGameTimer(), 1100
    while true do
        local k = math.min(1.0, (GetGameTimer() - start) / duration)
        local lift = math.sin(k * math.pi) * 0.45
        SetEntityCoordsNoOffset(lid, from.x + (landing.x - from.x) * k, from.y + (landing.y - from.y) * k, from.z + (landing.z - from.z) * k + lift, false, false, false)
        SetEntityRotation(lid, -75.0 * k, 0.0, heading, 2, true)
        if k >= 1.0 then break end
        Wait(0)
    end
end

RegisterNUICallback('claimCrate', function(_, cb) TriggerServerEvent('meta_comic:server:crateClaim'); cb({ ok = true }) end)

RegisterNetEvent('meta_comic:client:crateOpened', function(result)
    local models = cfg.Models or {}
    local coords, heading = scene.coords, scene.heading
    local sealedLid = scene.lid and DoesEntityExist(scene.lid) and scene.lid or nil
    if sealedLid then DetachEntity(sealedLid,true,false);FreezeEntityPosition(sealedLid,true) end
    if coords and models.Open and loadModel(models.Open) then
        if models.Open ~= models.Closed then
            if scene.crate and DoesEntityExist(scene.crate) then DeleteEntity(scene.crate) end
            scene.crate = spawn(models.Open, coords, heading, cfg.Scene and cfg.Scene.Networked ~= false)
            if scene.crate then PlaceObjectOnGroundProperly(scene.crate) end
        end
        if sealedLid then
            local from = GetEntityCoords(sealedLid)
            CreateThread(function() animateLid(sealedLid,from,heading) end)
        elseif scene.crate and models.Lid and loadModel(models.Lid) then
            local lidOffset = (cfg.Scene and cfg.Scene.LidOffset) or vector3(0.0, 0.0, 0.0)
            local lidAt = GetOffsetFromEntityInWorldCoords(scene.crate, lidOffset.x, lidOffset.y, lidOffset.z)
            local lid = spawn(models.Lid, lidAt, heading, cfg.Scene and cfg.Scene.Networked ~= false)
            if lid then CreateThread(function() animateLid(lid, lidAt, heading) end) end
        end
    end
    PlaySoundFrontend(-1, 'Drill_Pin_Break', 'DLC_HEIST_FLEECA_SOUNDSET', true)
    Wait((cfg.Scene and cfg.Scene.RevealDelay) or 900)
    if cfg.Reveal3D ~= false then
        SetNuiFocus(true, true)
        SendNUIMessage({ type = 'metaComic:open', view = 'pack', overlay = true, mode = 'crate', crate = result })
    else
        local lines = {}
        for _, row in ipairs(result.contents or {}) do lines[#lines + 1] = row.label end
        notify('Crate contents: ' .. table.concat(lines, ', '), 'success')
    end
    busy = false
    TriggerEvent('meta_comic:client:crateCarryPause', false)
    local keep = (cfg.Scene and cfg.Scene.KeepSeconds) or 20
    SetTimeout(keep * 1000, function() if not busy then clearScene() end end)
end)

AddEventHandler('onResourceStop', function(name)
    if name == GetCurrentResourceName() then clearScene() end
end)
