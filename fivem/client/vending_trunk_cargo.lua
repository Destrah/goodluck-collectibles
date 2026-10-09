local cfg = (Config.VendingCarry or {}).TrunkCargo or {}
if cfg.Enabled == false or (Config.VendingCarry or {}).Enabled == false then return end
local known, probes = {}, {}
local visualChecks = {}
local vehicles, scanAt, nextProbeAt = {}, 0, 0
local profiles = {}
local geometry = MetaComic.VendingCargoGeometry
local limits, dimensions = {}, {}
local loadingModels = {}
local spawnBudget = 0
local function discard(object)
    if object and DoesEntityExist(object) then DeleteEntity(object) end
end
local function discardVisual(visual)
    discard(visual.lid);discard(visual.object)
end
local function syncVisuals(vehicle, cargo)
    local model = tonumber(cargo.model) or joaat(cargo.model or 'metacomics_vending_machine')
    if loadingModels[model] ~= nil then loadingModels[model] = true end
    if cargo.lid then
        local lidModel = tonumber(cargo.lid) or joaat(cargo.lid)
        if loadingModels[lidModel] ~= nil then loadingModels[lidModel] = true end
    end
    local now = GetGameTimer()
    if now < (visualChecks[vehicle] or 0) then return end
    visualChecks[vehicle] = now + 500
    local entry = known[vehicle]
    if not entry then entry = {};known[vehicle] = entry end
    local wanted = {}
    for index, slot in ipairs(cargo.slots or {}) do
        local o, r = slot.offset, slot.rotation
        local signature = table.concat({model,o.x,o.y,o.z,r.x,r.y,r.z,tostring(slot.alignBottom),tostring(cargo.lid)}, ':')
        wanted[index] = true
        local visual = entry[index]
        if visual and (visual.signature ~= signature or not DoesEntityExist(visual.object)) then
            discardVisual(visual);entry[index] = nil;visual = nil;limits[vehicle] = nil
        end
        if not visual and spawnBudget > 0 and IsModelInCdimage(model) and IsModelValid(model) then
            -- Poll loading without yielding inside the spawn/attach lifecycle.
            RequestModel(model)
            loadingModels[model] = true
            if HasModelLoaded(model) then
                local coords = GetEntityCoords(vehicle)
                local object = CreateObjectNoOffset(model,coords.x,coords.y,coords.z-10.0,false,false,false)
                if object and object ~= 0 then
                    spawnBudget = spawnBudget - 1
                    -- No frame or physics tick can run between creation and disabling collision.
                    SetEntityVisible(object,false,false)
                    FreezeEntityPosition(object,true)
                    SetEntityCollision(object,false,false)
                    SetEntityInvincible(object,true)
                    visual = { object=object,signature=signature }
                    entry[index] = visual;limits[vehicle] = nil
                end
                SetModelAsNoLongerNeeded(model)
                loadingModels[model] = nil
            end
        end
        if visual then
            local object = visual.object
            if not IsEntityAttachedToEntity(object,vehicle) then
                visual.ready = false
                SetEntityVisible(object,false,false)
                FreezeEntityPosition(object,true)
                SetEntityCollision(object,false,false)
                local z = o.z
                if slot.alignBottom then
                    -- Crate placements specify floor height; their model origin can be above/below its base.
                    local minimum = GetModelDimensions(model)
                    z = z - minimum.z
                end
                AttachEntityToEntity(object,vehicle,-1,o.x,o.y,z,r.x,r.y,r.z,false,false,false,false,2,true)
                limits[vehicle] = nil
            end
            if not visual.ready and IsEntityAttachedToEntity(object,vehicle) then
                FreezeEntityPosition(object,false)
                SetEntityVisible(object,true,false)
                visual.ready = true
            end
            if visual.ready and cargo.lid and (not visual.lid or not DoesEntityExist(visual.lid)) and spawnBudget > 0 then
                local lidModel = tonumber(cargo.lid) or joaat(cargo.lid)
                if IsModelInCdimage(lidModel) and IsModelValid(lidModel) then
                    RequestModel(lidModel);loadingModels[lidModel] = true
                    if HasModelLoaded(lidModel) then
                        local coords = GetEntityCoords(vehicle)
                        local lid = CreateObjectNoOffset(lidModel,coords.x,coords.y,coords.z-10.0,false,false,false)
                        if lid and lid ~= 0 then
                            spawnBudget = spawnBudget - 1
                            SetEntityVisible(lid,false,false);FreezeEntityPosition(lid,true);SetEntityCollision(lid,false,false)
                            local minimum,maximum = GetModelDimensions(model)
                            local lidMin,lidMax = GetModelDimensions(lidModel)
                            local p = geometry.topAttachment(minimum,maximum,lidMin,lidMax)
                            AttachEntityToEntity(lid,object,-1,p.x,p.y,p.z,0.0,0.0,0.0,false,false,false,false,2,true)
                            if IsEntityAttachedToEntity(lid,object) then
                                FreezeEntityPosition(lid,false);SetEntityVisible(lid,true,false);visual.lid = lid
                            else discard(lid) end
                        end
                        SetModelAsNoLongerNeeded(lidModel);loadingModels[lidModel] = nil
                    end
                end
            end
        end
    end
    for index, visual in pairs(entry) do
        if not wanted[index] then discardVisual(visual);entry[index] = nil;limits[vehicle] = nil end
    end
end
for model in pairs(cfg.Profiles or {}) do profiles[(tonumber(model) or joaat(model)) & 0xffffffff] = true end
local function modelBounds(entity)
    local model = GetEntityModel(entity)
    if not dimensions[model] then
        local minimum, maximum = GetModelDimensions(model)
        dimensions[model] = {minimum, maximum}
    end
    return dimensions[model][1], dimensions[model][2]
end
local function doorLimits(vehicle, cargo)
    local candidates = cargo.collisionDoors or cargo.doors or {}
    if #candidates == 0 then return {} end
    local cache = limits[vehicle]
    -- Cargo and door geometry are fixed in vehicle space. Movement/ownership changes do not change clearance.
    -- syncVisuals invalidates this only when a visual is added, removed, moved or reattached.
    if cache then return cache.values end
    local values = {}
    -- Explicit obstruction configuration is a fallback for models without usable rear-door bones.
    for _, door in ipairs(cargo.doors or {}) do values[door] = tonumber(cargo.doorStopAngle) or 0.25 end
    local left = GetEntityBoneIndexByName(vehicle, 'door_dside_r')
    local right = GetEntityBoneIndexByName(vehicle, 'door_pside_r')
    if not cargo.slidingDoors and (left < 0 or right < 0) then return values end
    local function localPoint(point) return GetOffsetFromEntityGivenWorldCoords(vehicle,point.x,point.y,point.z) end
    local hinges, width = {}, 0
    if not cargo.slidingDoors then
        hinges = { [2] = localPoint(GetWorldPositionOfEntityBone(vehicle,left)), [3] = localPoint(GetWorldPositionOfEntityBone(vehicle,right)) }
        width = math.abs(hinges[2].x-hinges[3].x)/2
        if width < 0.1 then return values end
    end
    local boxes = {}
    for index in ipairs(cargo.slots or {}) do
        local visual = known[vehicle] and known[vehicle][index]
        if not visual or not DoesEntityExist(visual.object) then return values end
        local object = visual.object
        if not IsEntityAttachedToEntity(object,vehicle) then return values end
        local minimum, maximum = modelBounds(object)
        local box = geometry.bounds(minimum,maximum,function(x,y,z)
            return localPoint(GetOffsetFromEntityInWorldCoords(object,x,y,z))
        end)
        if not box then return values end
        boxes[#boxes+1] = box
    end
    if #boxes == 0 then return values end
    local minimum, maximum = modelBounds(vehicle)
    for _, door in ipairs(candidates) do
        local hinge = hinges[door]
        local sliding = cargo.slidingDoors and (cargo.slidingDoors[door] or cargo.slidingDoors[tostring(door)])
        if sliding then
            values[door] = geometry.slidingLimit(boxes,sliding,cargo.collisionClearance)
        elseif hinge then
            values[door] = geometry.limit(boxes,hinge,hinge.x<0 and 1 or -1,width,
                minimum.z+0.35,maximum.z-0.05,cargo.doorMaxDegrees,cargo.collisionClearance)
        end
    end
    limits[vehicle] = { at=GetGameTimer(),values=values }
    return values
end
local function release(vehicle)
    -- Do not issue a close command on unloading; the door remains wherever the player left it.
    for _, visual in pairs(known[vehicle] or {}) do discardVisual(visual) end
    known[vehicle] = nil
    visualChecks[vehicle] = nil
    limits[vehicle] = nil
end
CreateThread(function()
    while true do
        local active = false
        local now, here = GetGameTimer(), GetEntityCoords(PlayerPedId())
        local seen = {}
        spawnBudget = math.max(1,math.floor(tonumber(cfg.SpawnPerTick) or 2))
        for model in pairs(loadingModels) do loadingModels[model] = false end
        if now >= scanAt then
            vehicles = {}
            for _,vehicle in ipairs(GetGamePool('CVehicle')) do
                if profiles[GetEntityModel(vehicle) & 0xffffffff] then vehicles[#vehicles+1] = vehicle end
            end
            scanAt = now + 1000
        end
        for _, vehicle in ipairs(vehicles) do
            if DoesEntityExist(vehicle) then
                local cargo = Entity(vehicle).state.metaComicTrunkCargo
                if cargo then
                    seen[vehicle], active = true, true
                    -- Local, non-colliding replicas follow the network vehicle on every observer.
                    syncVisuals(vehicle,cargo)
                    -- Only the vehicle's controlling client changes its networked doors.
                    if NetworkHasControlOfEntity(vehicle) then
                        for door, minimum in pairs(doorLimits(vehicle,cargo)) do
                            if minimum > 0 and GetVehicleDoorAngleRatio(vehicle, door) < minimum - 0.01 then
                                -- Correct only penetration into the cargo, never repeatedly force the door fully open.
                                SetVehicleDoorControl(vehicle, door, 1, minimum)
                            end
                        end
                    end
                elseif known[vehicle] then release(vehicle) end
                if now >= nextProbeAt and profiles[GetEntityModel(vehicle) & 0xffffffff] and #(here - GetEntityCoords(vehicle)) < 50 and now - (probes[vehicle] or -10000) > 10000 then
                    probes[vehicle] = now
                    nextProbeAt = now + 1200
                    TriggerServerEvent('meta_comic:server:vendingTrunkProbe', VehToNet(vehicle))
                end
            end
        end
        for vehicle in pairs(known) do if not seen[vehicle] then release(vehicle) end end
        for vehicle in pairs(probes) do if not DoesEntityExist(vehicle) then probes[vehicle] = nil end end
        for model, requested in pairs(loadingModels) do
            if not requested then SetModelAsNoLongerNeeded(model);loadingModels[model] = nil end
        end
        Wait(active and 250 or 1000)
    end
end)
exports('CanCloseVendingCargoDoor', function(vehicle, door)
    local cargo = DoesEntityExist(vehicle) and Entity(vehicle).state.metaComicTrunkCargo
    return not cargo or (doorLimits(vehicle,cargo)[door] or 0) == 0
end)
AddEventHandler('onResourceStop', function(name)
    if name ~= GetCurrentResourceName() then return end
    for vehicle in pairs(known) do release(vehicle) end
    for model in pairs(loadingModels) do SetModelAsNoLongerNeeded(model) end
end)
