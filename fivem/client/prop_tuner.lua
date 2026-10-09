local session, generation = nil, 0
MetaComic.PropTuneBusy = function() return session ~= nil end
local function notify(message, kind) TriggerEvent('meta_comic:client:notify', message, kind or 'info') end
local function vector(value)
    value = value or {}
    return { x = tonumber(value.x) or 0, y = tonumber(value.y) or 0, z = tonumber(value.z) or 0 }
end
local function stop()
    generation = generation + 1
    local s = session
    session = nil
    if not s then return end
    if s.prop and DoesEntityExist(s.prop) then DeleteEntity(s.prop) end
    if DoesEntityExist(s.ped) then
        ClearPedTasks(s.ped)
        FreezeEntityPosition(s.ped, s.wasFrozen)
    end
end
local function attach(s)
    local p, r = s.offset, s.rotation
    AttachEntityToEntity(s.prop, s.ped, GetPedBoneIndex(s.ped, s.bone), p.x, p.y, p.z, r.x, r.y, r.z,
        true, true, false, true, 1, true)
end
local function report(s)
    print(('[prop tune] %s | Model = %q | dict = %q, clip = %q, flag = %d | Phase = %.3f'):format(
        s.label, s.model, s.dict, s.clip, s.flag, s.phase))
    print(('Bone = %d, Offset = vec3(%.4f, %.4f, %.4f), Rotation = vec3(%.2f, %.2f, %.2f),'):format(
        s.bone, s.offset.x, s.offset.y, s.offset.z, s.rotation.x, s.rotation.y, s.rotation.z))
    if s.machine then print(('Machine = %s, Profile = %s, Spot = vec3(%.4f, %.4f, %.4f), Target = vec3(%.4f, %.4f, %.4f)'):format(
        s.machine.id, s.label, s.spot.x, s.spot.y, s.spot.z, s.target.x, s.target.y, s.target.z)) end
    notify('Calibration printed to F8. Copy both lines (and the machine profile line).')
end
local function text(message)
    SetTextFont(0); SetTextScale(0.0, 0.30); SetTextColour(255, 255, 255, 255); SetTextOutline()
    BeginTextCommandDisplayText('STRING'); AddTextComponentSubstringPlayerName(message); EndTextCommandDisplayText(0.02, 0.64)
end
local function start(options)
    if type(options) ~= 'table' or type(options.model) ~= 'string' or type(options.dict) ~= 'string' or type(options.clip) ~= 'string' then
        return notify('Calibration needs a model, animation dictionary and clip.', 'error')
    end
    if session then stop() end
    if MetaComic.VendingKeyWorkBusy and MetaComic.VendingKeyWorkBusy() or MetaComic.VendingActionBusy and MetaComic.VendingActionBusy() then
        return notify('Finish the current vending action before calibrating.', 'error')
    end
    local ped = PlayerPedId()
    if IsPedInAnyVehicle(ped, false) or IsEntityDead(ped) then return notify('Stand on foot to calibrate.', 'error') end
    local s = options
    s.ped, s.offset, s.rotation = ped, vector(s.offset), vector(s.rotation)
    s.bone, s.flag, s.phase = tonumber(s.bone) or 64096, tonumber(s.flag) or 1, math.max(0, math.min(.99, tonumber(s.phase) or .5))
    s.label, s.mode = s.label or s.model, 'position'
    s.wasFrozen = IsEntityPositionFrozen and IsEntityPositionFrozen(ped) or false
    if GetPedBoneIndex(ped, s.bone) == -1 then return notify('That bone is not available on this ped.', 'error') end
    local hash = joaat(s.model)
    if not IsModelInCdimage(hash) or not IsModelValid(hash) then return notify('Prop model was not found.', 'error') end
    session = s; generation = generation + 1
    local token = generation
    RequestModel(hash); RequestAnimDict(s.dict)
    local deadline = GetGameTimer() + 5000
    while session == s and (not HasModelLoaded(hash) or not HasAnimDictLoaded(s.dict)) and GetGameTimer() < deadline do Wait(0) end
    if session ~= s then SetModelAsNoLongerNeeded(hash); return end
    if not HasModelLoaded(hash) or not HasAnimDictLoaded(s.dict) then
        SetModelAsNoLongerNeeded(hash); stop(); return notify('Prop or animation could not be loaded.', 'error')
    end
    if s.machine then
        local at = GetOffsetFromEntityInWorldCoords(s.machine.entity, s.spot.x, s.spot.y, s.spot.z)
        local face = GetOffsetFromEntityInWorldCoords(s.machine.entity, s.target.x, s.target.y, s.target.z)
        SetEntityCoordsNoOffset(ped, at.x, at.y, GetEntityCoords(ped).z, false, false, false)
        SetEntityHeading(ped, GetHeadingFromVector_2d(face.x-at.x, face.y-at.y))
    end
    local at = GetEntityCoords(ped)
    s.prop = CreateObject(hash, at.x, at.y, at.z, false, false, false)
    SetModelAsNoLongerNeeded(hash)
    if not DoesEntityExist(s.prop) then stop(); return notify('Could not create the calibration prop.', 'error') end
    SetEntityCollision(s.prop, false, false); attach(s)
    FreezeEntityPosition(ped, true); ClearEntityLastDamageEntity(ped)
    TaskPlayAnim(ped, s.dict, s.clip, 8.0, 8.0, -1, s.flag, 0, false, false, false)
    Wait(200)
    if session ~= s then return end
    if not IsEntityPlayingAnim(ped, s.dict, s.clip, 3) then stop(); return notify('Animation clip was not found.', 'error') end
    notify('Prop calibration started. R switches move/rotate; arrows and Page Up/Down adjust; Enter prints; Esc exits.')
    CreateThread(function()
        while session == s and generation == token do
            if IsEntityDead(ped) or IsPedRagdoll(ped) or HasEntityBeenDamagedByAnyPed(ped)
                or not DoesEntityExist(s.prop) or s.machine and not DoesEntityExist(s.machine.entity) then stop(); break end
            -- Keep the exact same pose while retaining the lock interaction's right-arm IK.
            SetEntityAnimSpeed(ped, s.dict, s.clip, 0.0)
            SetEntityAnimCurrentTime(ped, s.dict, s.clip, s.phase)
            if s.machine and SetIkTarget then
                local target = GetOffsetFromEntityInWorldCoords(s.machine.entity, s.target.x, s.target.y, s.target.z)
                SetIkTarget(ped, 4, 0, -1, target.x, target.y, target.z, 16, 200, 200)
            end
            for _, control in ipairs({30,31,24,25,37,44,45,172,173,174,175,10,11,200,201,202,21,36}) do DisableControlAction(0, control, true) end
            if IsDisabledControlJustPressed(0, 202) then stop(); break end
            if IsDisabledControlJustPressed(0, 45) then s.mode = s.mode == 'position' and 'rotation' or 'position' end
            if IsDisabledControlJustPressed(0, 201) then report(s) end
            local fine, coarse = IsDisabledControlPressed(0, 21), IsDisabledControlPressed(0, 36)
            local step = s.mode == 'position' and (fine and .001 or coarse and .02 or .005) or (fine and .25 or coarse and 10 or 2)
            local values, changed = s.mode == 'position' and s.offset or s.rotation, false
            for _, entry in ipairs({{174,'x',-1},{175,'x',1},{173,'y',-1},{172,'y',1},{11,'z',-1},{10,'z',1}}) do
                if IsDisabledControlJustPressed(0, entry[1]) then values[entry[2]]=values[entry[2]]+step*entry[3]; changed=true end
            end
            if changed then attach(s) end
            text(('PROP TUNE: %s | %s | step %.3f~n~Arrows: X/Y | Page Up/Down: Z | R: move/rotate~n~Shift: fine | Ctrl: coarse | Enter: print | Esc: stop~n~Offset %.4f %.4f %.4f~n~Rotation %.2f %.2f %.2f | phase %.3f'):format(
                s.label, s.mode, step, s.offset.x,s.offset.y,s.offset.z,s.rotation.x,s.rotation.y,s.rotation.z,s.phase))
            Wait(0)
        end
    end)
end
local function vending(args)
    local name = ({padlock='Padlock',cabinet='Cylinder',cylinder='Cylinder',cashbox='Cashbox',rack='Rack',server='Rack',install='InstallPadlock'})[tostring(args[1] or 'padlock'):lower()]
    if not name then return notify('Use /vendingkeytune padlock|cabinet|cashbox|rack|install [machine ID]', 'error') end
    local cfg = Config.VendingMachines or {}; local keys = cfg.Keys or {}; local visual = keys.UseAnimation or {}
    local p = (visual.Profiles or {})[name]
    local machine = args[2] and MetaComic.VendingMachineById(tonumber(args[2])) or MetaComic.VendingNearestMachine(3.0)
    if not p or not machine or not machine.entity or not DoesEntityExist(machine.entity)
        or #(GetEntityCoords(PlayerPedId())-GetEntityCoords(machine.entity)) > 3.0 then return notify('Stand within three metres of a vending machine.', 'error') end
    local anim = p.Animation or visual.Animation
    start({model=name=='Cylinder' and visual.CabinetModel or name=='InstallPadlock' and (keys.Padlock or {}).Model or visual.Model,
        dict=anim.dict,clip=anim.clip,flag=anim.flag,bone=p.Bone or visual.Bone,offset=p.Offset or visual.Offset,
        rotation=p.Rotation or visual.Rotation, label=name, machine=machine,spot=p.Spot,target=p.Target})
end
RegisterNetEvent('meta_comic:client:propTune', function(data)
    if source ~= 65535 or type(data) ~= 'table' then return end
    local args = data.args or {}; local command = tostring(args[1] or ''):lower()
    if data.preset then return start(data.preset) end
    if data.vending then return vending(args) end
    if command == 'stop' then stop(); return end
    if command == 'print' and session then report(session); return end
    if command == 'phase' and session then session.phase=math.max(0,math.min(.99,tonumber(args[2]) or .5)); return end
    if command == 'bone' and session then
        local bone = tonumber(args[2]); if bone and GetPedBoneIndex(session.ped,bone) ~= -1 then session.bone=bone; attach(session) end
        return
    end
    if (command == 'move' or command == 'rotate') and session then
        local values = command == 'move' and session.offset or session.rotation
        for i, axis in ipairs({'x','y','z'}) do values[axis]=values[axis]+(tonumber(args[i+1]) or 0) end
        attach(session); return
    end
    if command == 'set' and session then
        if not tonumber(args[7]) then return notify('Use /proptune set x y z rx ry rz', 'error') end
        session.offset={x=tonumber(args[2]) or 0,y=tonumber(args[3]) or 0,z=tonumber(args[4]) or 0}
        session.rotation={x=tonumber(args[5]) or 0,y=tonumber(args[6]) or 0,z=tonumber(args[7])}; attach(session); return
    end
    if command == 'start' and args[2] and args[3] and args[4] then
        return start({model=args[2],dict=args[3],clip=args[4],bone=tonumber(args[5]),flag=tonumber(args[6])})
    end
    notify('Use /proptune start MODEL DICT CLIP [BONE] [FLAG], or move/rotate/set/bone/phase/print/stop.')
end)
AddEventHandler('onResourceStop', function(resource) if resource == GetCurrentResourceName() then stop() end end)
