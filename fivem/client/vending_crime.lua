-- Break-in / hack / steal on vending machines (Config.VendingMachines.Crime). ox_target shows each option only to
-- players carrying its items; the server checks everything again (server/modules/vending_crime.lua).
-- Flow: ask the server -> minigames (client/minigames.lua) with the animation playing -> progress bar -> server.
local cfg = Config.VendingMachines or {}
local crime = cfg.Crime or {}
if cfg.Enabled == false or crime.Enabled == false then return end

local ACTIONS = {
    { id = 'breakin', key = 'BreakIn', label = 'Break in', icon = 'fas fa-screwdriver-wrench' },
    { id = 'hack', key = 'Hack', label = 'Hack payment terminal', icon = 'fas fa-laptop-code' },
    { id = 'steal', key = 'Steal', label = 'Unbolt machine', icon = 'fas fa-dolly' },
    { id = 'disablegps', key = 'DisableGPS', label = 'Disable machine GPS', icon = 'fas fa-satellite' },
    { id = 'enablegps', key = 'EnableGPS', label = 'Enable machine GPS', icon = 'fas fa-satellite' },
    { id = 'installskimmer', key = 'InstallSkimmer', label = 'Install card skimmer', icon = 'fas fa-credit-card' },
    { id = 'collectskimmer', key = 'CollectSkimmer', label = 'Read card skimmer', icon = 'fas fa-credit-card' },
    { id = 'removeskimmer', key = 'RemoveSkimmer', label = 'Remove card skimmer', icon = 'fas fa-screwdriver' },
}
local busy = false
local held -- prop in the player's hand while the minigame runs

local function notify(message, notifyType) TriggerEvent('meta_comic:client:notify', message, notifyType) end
local function loadDict(dict)
    if not dict then return false end
    RequestAnimDict(dict)
    local timeout = GetGameTimer() + 3000
    while not HasAnimDictLoaded(dict) and GetGameTimer() < timeout do Wait(0) end
    return HasAnimDictLoaded(dict)
end
local function loadModel(model)
    local hash = type(model) == 'number' and model or joaat(model)
    if not IsModelInCdimage(hash) then return nil end
    RequestModel(hash)
    local timeout = GetGameTimer() + 3000
    while not HasModelLoaded(hash) and GetGameTimer() < timeout do Wait(0) end
    return HasModelLoaded(hash) and hash or nil
end
local function dropProp()
    if held and DoesEntityExist(held) then DeleteEntity(held) end
    held = nil
end
-- the action's animation (and prop) looping while the minigame is on screen
local function startPose(anim)
    local ped = PlayerPedId()
    if not anim then return end
    if anim.scenario then TaskStartScenarioInPlace(ped, anim.scenario, 0, true) return end
    if loadDict(anim.dict) then TaskPlayAnim(ped, anim.dict, anim.clip, 3.0, 3.0, -1, anim.flag or 49, 0, false, false, false) end
    local hash = anim.prop and loadModel(anim.prop)
    if hash then
        local coords = GetEntityCoords(ped)
        held = CreateObject(hash, coords.x, coords.y, coords.z + 0.2, true, true, false)
        local pos, rot = anim.pos or vec3(0.1, 0.02, -0.02), anim.rot or vec3(-80.0, 0.0, 0.0)
        AttachEntityToEntity(held, ped, GetPedBoneIndex(ped, anim.bone or 57005), pos.x, pos.y, pos.z, rot.x, rot.y, rot.z, true, true, false, true, 1, true)
        SetModelAsNoLongerNeeded(hash)
    end
end
local function stopPose()
    dropProp()
    ClearPedTasks(PlayerPedId())
end

local function progress(data)
    -- The action owns its pose/prop across both minigames and progress. Letting ox_lib
    -- recreate it uses a different attachment rotation order and flips the drill.
    if GetResourceState('ox_lib') == 'started' then
        return exports.ox_lib:progressBar({
            duration = data.duration, label = data.label or 'Working...', canCancel = true,
            disable = { move = true, car = true, combat = true },
        }) == true
    end
    Wait(data.duration)
    return true
end

RegisterNetEvent('meta_comic:client:crimeStart', function(data)
    if busy then return TriggerServerEvent('meta_comic:server:crimeCancel') end
    busy = true
    local machine = MetaComic.VendingMachineById and MetaComic.VendingMachineById(data.id)
    if machine and machine.entity and DoesEntityExist(machine.entity) then
        TaskTurnPedToFaceEntity(PlayerPedId(), machine.entity, 700)
        Wait(700)
    end
    local passed = true
    startPose(data.animation)
    if data.minigame then
        passed = MetaComic.RunMinigames(data.minigame)
    end
    if not passed then
        stopPose()
        TriggerServerEvent('meta_comic:server:crimeFinish', data.token, false)
        busy = false
        return
    end
    local finished = progress(data)
    stopPose()
    if finished then
        TriggerServerEvent('meta_comic:server:crimeFinish', data.token, true)
    else
        TriggerServerEvent('meta_comic:server:crimeCancel')
        notify('Stopped.', 'info')
    end
    busy = false
end)

CreateThread(function()
    local timeout = GetGameTimer() + 30000
    while GetResourceState('ox_target') ~= 'started' do
        if GetGameTimer() > timeout or GetResourceState('ox_target') == 'missing' then return end
        Wait(500)
    end
    local options = {}
    for _, action in ipairs(ACTIONS) do
        local s = crime[action.key]
        if type(s) == 'table' and s.Enabled ~= false then
            local items = {}
            for _, entry in ipairs(s.Items or {}) do
                local name = type(entry) == 'table' and entry.item or entry
                items[name] = type(entry) == 'table' and tonumber(entry.count) or 1
            end
            if action.id == 'installskimmer' then items = { [(cfg.Skimmer or {}).Item or 'card_skimmer'] = 1 } end
            options[#options + 1] = {
                name = 'meta_comic_vending_' .. action.id, label = s.Label or action.label, icon = s.Icon or action.icon,
                distance = s.Distance or (cfg.Shop and cfg.Shop.TargetDistance) or 2.0,
                items = next(items) and items or nil,
                canInteract = function(entity)
                    local machine = MetaComic.VendingMachineOf and MetaComic.VendingMachineOf(entity)
                    if not machine or busy then return false end
                    local controlled = MetaComic.VendingControls and MetaComic.VendingControls(machine.id)
                    if action.id == 'disablegps' then return (cfg.GPS or {}).Enabled ~= false and not machine.gpsDisabled end
                    if action.id == 'enablegps' then return (cfg.GPS or {}).Enabled ~= false and controlled == true end
                    if action.id:find('skimmer') then
                        if (cfg.Skimmer or {}).Enabled == false then return false end
                        if action.id == 'installskimmer' then return not machine.skimmer and (crime.OwnersCanRob or not controlled) end
                        return machine.skimmer == true -- the server validates installer/controller permissions
                    end
                    return crime.OwnersCanRob or not (MetaComic.VendingControls and MetaComic.VendingControls(machine.id))
                end,
                onSelect = function(data)
                    if action.id == 'installskimmer' then
                        local model = (cfg.Skimmer or {}).Model
                        if not model or not IsModelInCdimage(joaat(model)) then return notify('The configured skimmer prop has not been streamed yet.', 'error') end
                    end
                    local machine = MetaComic.VendingMachineOf(data.entity)
                    if machine then TriggerServerEvent('meta_comic:server:crimeStart', machine.id, action.id) end
                end,
            }
        end
    end
    if #options > 0 then exports.ox_target:addModel(cfg.Model or 'metacomics_vending_machine', options) end
end)

AddEventHandler('onResourceStop', function(name)
    if name == GetCurrentResourceName() then dropProp() end
end)
