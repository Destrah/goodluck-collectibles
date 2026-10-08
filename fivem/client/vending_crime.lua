-- Break-in / hack / steal on vending machines (Config.VendingMachines.Crime). ox_target shows each option only to
-- players carrying its items; the server checks everything again (server/modules/vending_crime.lua).
-- Flow: ask the server -> minigames (client/minigames.lua) with the animation playing -> progress bar -> server.
local cfg = Config.VendingMachines or {}
local crime = cfg.Crime or {}
if cfg.Enabled == false or crime.Enabled == false then return end

local ACTIONS = {
    { id = 'breakin', key = 'BreakIn', label = 'Break in', icon = 'fas fa-screwdriver-wrench' },
    { id = 'hack', key = 'Hack', label = 'Hack payment terminal', icon = 'fas fa-laptop-code' },
    { id = 'fullhack', key = 'FullHack', label = 'Take over machine operating system', icon = 'fas fa-user-secret' },
    { id = 'replaceboard', key = 'ReplaceBoard', label = 'Replace machine control board', icon = 'fas fa-microchip' },
    { id = 'secure', key = 'Secure', label = 'Secure vending machine', icon = 'fas fa-lock' },
    { id = 'steal', key = 'Steal', label = 'Unbolt machine', icon = 'fas fa-dolly' },
    { id = 'takemachine', key = 'TakeMachine', label = 'Steal Machine', icon = 'fas fa-dolly' },
    { id = 'bolt', key = 'BoltMachine', label = 'Bolt machine down', icon = 'fas fa-screwdriver-wrench' },
    { id = 'disablegps', key = 'DisableGPS', label = 'Disable machine GPS', icon = 'fas fa-satellite' },
    { id = 'enablegps', key = 'EnableGPS', label = 'Enable machine GPS', icon = 'fas fa-satellite' },
    { id = 'installskimmer', key = 'InstallSkimmer', label = 'Install card skimmer', icon = 'fas fa-credit-card' },
    { id = 'collectskimmer', key = 'CollectSkimmer', label = 'Read card skimmer', icon = 'fas fa-credit-card' },
    { id = 'removeskimmer', key = 'RemoveSkimmer', label = 'Remove card skimmer', icon = 'fas fa-screwdriver' },
    { id = 'adjustskimmer', key = 'AdjustSkimmer', label = 'Adjust card skimmer', icon = 'fas fa-sliders' },
    { id = 'inspectpanel', key = 'InspectPanel', label = 'Check coin panel for tampering', icon = 'fas fa-magnifying-glass' },
}
local busy = false
local looting = false
local lootGeneration = 0
local stopLootVisual
local held -- prop in the player's hand while the minigame runs

RegisterNetEvent('meta_comic:client:crimeInjury', function(damage)
    if source ~= 65535 then return end -- accept only server delivery
    local ped = PlayerPedId()
    if IsEntityDead(ped) then return end
    if GetEntityHealth(ped) <= 101 then return end
    local amount = math.max(0, math.min(100, tonumber(damage) or 0))
    SetEntityHealth(ped, math.max(101, GetEntityHealth(ped) - amount))
    TriggerEvent('meta_comic:client:notify', 'You injured yourself working on the machine.', 'error')
end)

RegisterNetEvent('meta_comic:client:crimeBloodGround', function(data)
    if source ~= 65535 or type(data) ~= 'table' or not data.coords then return end
    local coords = data.coords
    local handle = StartExpensiveSynchronousShapeTestLosProbe(coords.x, coords.y, coords.z + 1.5,
        coords.x, coords.y, coords.z - 3.0, 1, PlayerPedId(), 4)
    local _, hit, ground = GetShapeTestResult(handle)
    if (hit == true or hit == 1) and ground then
        TriggerServerEvent('meta_comic:server:crimeBloodGround', data.token, ground.z)
    end
end)

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
    if stopLootVisual then stopLootVisual() end
    dropProp()
    ClearPedTasks(PlayerPedId())
end

-- Per-batch visual lifecycle. These props/animations never award inventory or cash.
local lootProp, lootAnim, visualToken = nil, nil, 0
local lootMachine -- machine id being looted
-- keepPose: between batches only the hand prop goes; the pose carries on so the cash kneel doesn't restart
stopLootVisual = function(keepPose)
    visualToken = visualToken + 1
    if lootProp and DoesEntityExist(lootProp) then DeleteEntity(lootProp) end
    lootProp = nil
    if keepPose then return end
    if lootAnim then StopAnimTask(PlayerPedId(), lootAnim.dict, lootAnim.clip, 2.0) end
    lootAnim = nil
end
local function animateLootBatch(data, deadline, generation)
    stopLootVisual(true)
    local visuals = ((crime.BreakIn or {}).Loot or {}).Visuals or {}
    if visuals.Enabled == false then return end
    local token = visualToken
    local function current()
        if data.isCurrent then return data.isCurrent() and visualToken == token and not IsEntityDead(PlayerPedId()) end
        return looting and lootGeneration == generation and visualToken == token and not IsEntityDead(PlayerPedId())
    end
    CreateThread(function()
        local ped = PlayerPedId()
        local key = data.kind == 'cash' and 'Cash' or data.productKind == 'box' and 'Box' or 'Pack'
        local base = key == 'Cash' and {} or (Config.Props or {})[key] or {}
        local prop = visuals[key] or {}
        local model = prop.model or base.model or (key == 'Cash' and 'prop_anim_cash_note'
            or key == 'Box' and 'prop_boosterbox_01' or 'prop_boosterpack_01')
        if type(model) == 'table' then model = model[1] end
        local reach = visuals.Reach or { dict = 'mp_common', clip = 'givetake1_a', flag = 49 }
        local stash = visuals.Stash or { dict = 'anim@heists@ornate_bank@grab_cash', clip = 'grab', flag = 49 }
        -- cash: kneel at the cash box (lower right); packs / boxes: stand in front of the window and grab
        if key == 'Cash' then
            reach = visuals.CashPose or { dict = 'amb@medic@standing@tendtodead@idle_a', clip = 'idle_a', flag = 1 }
            stash = reach
        elseif data.placing then
            -- restocking: the same moves the other way round, out of the bag first, then into the machine where it stays
            reach, stash = stash, reach
        end
        -- load everything before moving the ped, so a slow load can't eat the batch
        local hash = loadModel(model)
        local reachLoaded, stashLoaded = loadDict(reach.dict), loadDict(stash.dict)
        if not reachLoaded or not stashLoaded then
            print(('[meta-comic] loot animation dict did not load: %s'):format(not reachLoaded and reach.dict or stash.dict))
        end
        if not current() or GetGameTimer() >= deadline then
            if hash then SetModelAsNoLongerNeeded(hash) end
            return
        end
        local function playing(anim) return anim.dict and IsEntityPlayingAnim(ped, anim.dict, anim.clip, 3) end
        -- same pose still running from the last batch (cash kneel): leave the ped alone, no snap / restart
        local steady = lootAnim and lootAnim.dict == reach.dict and lootAnim.clip == reach.clip and playing(reach)
        local spots = visuals.Spots or {}
        -- cash: the kneel clip leans ~0.4m forward, so the cash spot sits back from the box
        local spot = key == 'Cash' and (spots.Cash or vec3(0.40, -1.30, -0.95)) or (spots.Stock or vec3(-0.15, -0.90, -0.95))
        local machine = lootMachine and MetaComic.VendingMachineById and MetaComic.VendingMachineById(lootMachine)
        if not steady and machine and machine.entity and DoesEntityExist(machine.entity) then
            local target = GetOffsetFromEntityInWorldCoords(machine.entity, spot.x, spot.y, spot.z)
            local heading = GetEntityHeading(machine.entity)
            local away = #(GetEntityCoords(ped).xy - target.xy)
            -- switching pose (e.g. cash kneel -> pack grab), or the turn-to-face from lootStarted still running: clear
            -- it here, before the snap and Wait(0) below, so the clear can't land after the TaskPlayAnim and wipe the grab
            ClearPedTasks(ped)
            lootAnim = nil
            if away > 1.5 then
                TaskGoStraightToCoord(ped, target.x, target.y, target.z, 1.0, 2000, heading, 0.1)
                local walkUntil = math.min(deadline - 500, GetGameTimer() + 2000)
                while current() and GetGameTimer() < walkUntil and #(GetEntityCoords(ped).xy - target.xy) > 0.3 do Wait(0) end
            end
            -- snap to the exact spot so every batch starts from the same place (no shuffling)
            if away > 0.05 then
                local here = GetEntityCoords(ped)
                SetEntityCoordsNoOffset(ped, target.x, target.y, here.z, false, false, false)
            end
            SetEntityHeading(ped, heading)
            Wait(0) -- let the teleport settle (it can reset the ped's tasks) before the anim goes on
        end
        local function play(anim)
            if not current() or GetGameTimer() >= deadline then return false end
            if not HasAnimDictLoaded(anim.dict) then return true end
            if lootAnim and lootAnim.dict == anim.dict and lootAnim.clip == anim.clip and playing(anim) then
                return true -- already in this pose; replaying it restarts the blend and drifts the ped
            end
            -- no end time: the pose holds across batches and stopLootVisual() ends it when looting stops
            -- the ped can't walk while looting, so the grab plays full body: as an upper-body / secondary clip (flags 16 / 32)
            -- it got dropped by the task still on the ped and never showed. Visuals.UpperBody = true keeps the configured flag.
            local flag = anim.flag or 49
            if not visuals.UpperBody then flag = flag & ~48 end
            TaskPlayAnim(ped, anim.dict, anim.clip, 3.0, 3.0, -1, flag, 0, false, false, false)
            lootAnim = anim
            return true
        end
        if not play(reach) then if hash then SetModelAsNoLongerNeeded(hash) end; return end
        local want, retryAt = reach, GetGameTimer() + 300
        local duration = math.max(1, tonumber(data.duration) or 1)
        local started = deadline - duration
        local handAt = math.max(0, math.min(0.9, tonumber(visuals.HandFraction) or 0.25))
        local stashAt = math.max(handAt, math.min(0.95, tonumber(visuals.StashFraction) or 0.55))
        local hideAt = math.max(stashAt, math.min(0.99, tonumber(visuals.HideFraction) or 0.88))
        local shown, stashed, hidden = false, false, false
        while current() and GetGameTimer() < deadline do
            local phase = (GetGameTimer() - started) / duration
            if not shown and phase >= handAt then
                shown = true
                if hash then
                    local coords = GetEntityCoords(ped)
                    lootProp = CreateObject(hash, coords.x, coords.y, coords.z, true, true, false)
                    SetModelAsNoLongerNeeded(hash); hash = nil
                    if lootProp ~= 0 then
                        SetEntityCollision(lootProp, false, false)
                        local offset = prop.offset or base.offset or vec3(0.10, 0.02, -0.02)
                        local rotation = prop.rotation or base.rotation or vec3(0.0, 0.0, 0.0)
                        AttachEntityToEntity(lootProp, ped, GetPedBoneIndex(ped, prop.bone or base.bone or 57005),
                            offset.x, offset.y, offset.z, rotation.x, rotation.y, rotation.z, true, true, false, true, 1, true)
                    end
                end
            end
            if not stashed and phase >= stashAt then
                stashed, want = true, stash
                if not play(stash) then break end
            end
            -- something else (teleport settle, ox_lib, another script) knocked the pose off: put it back
            if GetGameTimer() >= retryAt and (want.flag or 49) % 2 == 1 and not playing(want) then
                retryAt = GetGameTimer() + 300
                if not play(want) then break end
            end
            if not hidden and phase >= hideAt then
                hidden = true
                if data.placing and lootProp then -- left in the machine
                    if DoesEntityExist(lootProp) then DeleteEntity(lootProp) end
                    lootProp = nil
                elseif lootProp and DoesEntityExist(lootProp) then
                    local pocket = visuals.Pocket or {}
                    local offset, rotation = pocket.pos or vec3(0.18, 0.02, -0.03), pocket.rot or vec3(0.0, 90.0, 0.0)
                    AttachEntityToEntity(lootProp, ped, GetPedBoneIndex(ped, pocket.bone or 11816),
                        offset.x, offset.y, offset.z, rotation.x, rotation.y, rotation.z, true, true, false, true, 1, true)
                    SetEntityAlpha(lootProp, 100, false)
                end
            end
            if hidden and phase >= math.min(0.99, hideAt + 0.04) and lootProp then
                if DoesEntityExist(lootProp) then DeleteEntity(lootProp) end
                lootProp = nil
            end
            Wait(0)
        end
        if hash then SetModelAsNoLongerNeeded(hash) end
        if visualToken == token then stopLootVisual(true) end
    end)
end

-- Timed restocking / cash collection by someone allowed to (server/modules/vending_machines.lua, Config.VendingMachines.Work):
-- the looting moves on a loop, loading packs into the machine or taking the cash, behind a progress bar.
local working, workGeneration = false, 0
RegisterNetEvent('meta_comic:client:vendingWork', function(data)
    if busy or looting or working then return TriggerServerEvent('meta_comic:server:vendingWorkCancel') end
    working = true
    workGeneration = workGeneration + 1
    local generation = workGeneration
    lootMachine = tonumber(data.id)
    local finishAt = GetGameTimer() + math.max(1000, tonumber(data.duration) or 1000)
    local function current() return working and workGeneration == generation end
    CreateThread(function()
        local cycle = math.max(1200, tonumber(data.cycle) or 2000)
        while current() and GetGameTimer() < finishAt - 400 do
            local deadline = math.min(finishAt, GetGameTimer() + cycle)
            animateLootBatch({ kind = data.kind == 'cash' and 'cash' or 'stock', productKind = data.productKind, duration = deadline - GetGameTimer(),
                placing = data.kind ~= 'cash', isCurrent = current }, deadline, 0)
            while current() and GetGameTimer() < deadline do Wait(50) end
        end
    end)
    local completed = true
    if GetResourceState('ox_lib') == 'started' then
        completed = exports.ox_lib:progressBar({ duration = finishAt - GetGameTimer(), label = data.label or 'Working...', canCancel = true,
            disable = { move = true, car = true, combat = true } }) == true
    else
        Wait(math.max(0, finishAt - GetGameTimer()))
    end
    working = false
    workGeneration = workGeneration + 1
    stopPose()
    if completed then TriggerServerEvent('meta_comic:server:vendingWorkFinish', data.token)
    else TriggerServerEvent('meta_comic:server:vendingWorkCancel') end
end)

RegisterNetEvent('meta_comic:client:lootInspect', function(data)
    local timeout = GetGameTimer() + 3000
    while busy and GetGameTimer() < timeout do Wait(0) end
    if busy or looting then return end
    if GetResourceState('ox_lib') ~= 'started' then return notify('Loot selection needs ox_lib.', 'error') end
    local options = {}
    local function choice(mode, title, duration, enabled)
        options[#options + 1] = { title = title, disabled = not enabled,
            description = ('About %d seconds to take the current contents; cancel anytime'):format(math.ceil(duration / 1000)),
            onSelect = function() TriggerServerEvent('meta_comic:server:lootStart', data.id, mode) end }
    end
    options[#options + 1] = { title = ('Cash: %s · Stock: %s'):format(data.cash, data.stock), readOnly = true }
    if data.cashLocked then
        -- the cash box is padlocked: say so, and offer to break the padlock (the server checks tools and access again)
        options[#options + 1] = { title = 'Take cash (cash box padlocked)', icon = 'lock', disabled = data.cash == 'empty',
            description = 'The cash box is padlocked. Select to break the padlock first.',
            onSelect = function()
                CreateThread(function()
                    local answer = exports.ox_lib:alertDialog({ header = 'Cash box padlocked',
                        content = 'The cash is behind a padlock. Break the padlock now?', centered = true, cancel = true,
                        labels = { confirm = 'Break padlock', cancel = 'Not now' } })
                    if answer == 'confirm' then TriggerServerEvent('meta_comic:server:cashboxStart', data.id) end
                end)
            end }
    else
        choice('cash', 'Take cash', data.cashMs, data.cash ~= 'empty')
    end
    choice('stock', 'Take stock', data.stockMs, data.stock ~= 'empty')
    if data.cashLocked then
        options[#options + 1] = { title = 'Take cash and stock', disabled = true,
            description = 'Only the stock is reachable until the cash box padlock is broken.' }
    else
        choice('both', 'Take cash and stock', data.cashMs + data.stockMs, data.cash ~= 'empty' or data.stock ~= 'empty')
    end
    exports.ox_lib:registerContext({ id = 'meta_comic_vending_loot', title = 'Unlocked vending machine', options = options })
    exports.ox_lib:showContext('meta_comic_vending_loot')
end)
RegisterNetEvent('meta_comic:client:lootStarted', function(data)
    if busy or looting then return TriggerServerEvent('meta_comic:server:lootCancel') end
    looting = true
    lootMachine = tonumber(data.id)
    lootGeneration = lootGeneration + 1
    local generation = lootGeneration
    local machine = MetaComic.VendingMachineById and MetaComic.VendingMachineById(data.id)
    if machine and machine.entity and DoesEntityExist(machine.entity) then TaskTurnPedToFaceEntity(PlayerPedId(), machine.entity, 500) end
    startPose(data.animation)
    local ped0 = PlayerPedId()
    ClearEntityLastDamageEntity(ped0)
    local visuals = ((crime.BreakIn or {}).Loot or {}).Visuals or {}
    local pushLimit = tonumber(visuals.PushDistance) or 0.6
    local settleAt, anchor = GetGameTimer() + 800, nil
    CreateThread(function()
        while looting and lootGeneration == generation do
            -- punched, shoved or knocked over (an owner or employee stepping in): stop
            local ped = PlayerPedId()
            if not anchor and GetGameTimer() >= settleAt then anchor = GetEntityCoords(ped) end
            if HasEntityBeenDamagedByAnyPed(ped) or IsPedRagdoll(ped) or IsPedBeingStunned(ped, 0)
                or anchor and #(GetEntityCoords(ped) - anchor) > pushLimit then
                TriggerServerEvent('meta_comic:server:lootCancel')
                looting = false
                stopPose()
                notify('You were interrupted and stopped looting.', 'error')
                return
            end
            DisableControlAction(0, 21, true)
            DisableControlAction(0, 24, true)
            DisableControlAction(0, 23, true)
            for _, control in ipairs({ 30, 31, 32, 33, 34, 35, 22, 44 }) do DisableControlAction(0, control, true) end -- no walking off
            -- pushed / dragged away from the machine: stop
            local here = machine and machine.entity and DoesEntityExist(machine.entity) and GetEntityCoords(machine.entity)
            if here and #(GetEntityCoords(PlayerPedId()) - here) > (tonumber((((crime.BreakIn or {}).Loot or {}).Visuals or {}).CancelDistance) or 3.0) then
                TriggerServerEvent('meta_comic:server:lootCancel')
                looting = false
                stopPose()
                return
            end
            if IsControlJustPressed(0, 177) or IsEntityDead(PlayerPedId()) then
                TriggerServerEvent('meta_comic:server:lootCancel')
                looting = false
                stopPose()
                return
            end
            BeginTextCommandDisplayHelp('STRING')
            AddTextComponentSubstringPlayerName('Looting vending machine · ~INPUT_CELLPHONE_CANCEL~ Stop · moving away stops looting')
            EndTextCommandDisplayHelp(0, false, false, -1)
            Wait(0)
        end
    end)
end)
RegisterNetEvent('meta_comic:client:lootReward', function(data)
    notify(data.kind == 'cash' and ('$%d taken.'):format(data.amount) or ('%d stock item(s) taken.'):format(data.amount), 'success')
end)
RegisterNetEvent('meta_comic:client:lootBatch', function(data)
    if not looting then return end
    local generation = lootGeneration
    local deadline = GetGameTimer() + math.max(1, tonumber(data.duration) or 1)
    animateLootBatch(data, deadline, generation)
    if GetResourceState('ox_lib') ~= 'started' then return end
    while looting and lootGeneration == generation do
        local ok, active = pcall(function() return exports.ox_lib:progressActive() end)
        if not ok or not active then break end
        Wait(50)
    end
    if not looting or lootGeneration ~= generation then return end
    if GetGameTimer() >= deadline then return end
    local completed = exports.ox_lib:progressBar({ duration = math.max(1, deadline - GetGameTimer()),
        label = data.kind == 'cash' and 'Taking cash' or data.productKind == 'box' and 'Taking card boxes' or 'Taking card packs', canCancel = true,
        disable = { car = true, combat = true } })
    if completed ~= true and looting and lootGeneration == generation then TriggerServerEvent('meta_comic:server:lootCancel') end
end)
RegisterNetEvent('meta_comic:client:lootStopped', function(reason)
    looting = false
    lootGeneration = lootGeneration + 1
    if GetResourceState('ox_lib') == 'started' then pcall(function() exports.ox_lib:cancelProgress() end) end
    stopPose()
    notify(reason or 'Looting stopped.', 'info')
end)

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
    if busy or looting then return TriggerServerEvent('meta_comic:server:crimeCancel') end
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
    -- asks the server to start an action; fitting or adjusting a skimmer first asks for its cut
    local function start(machineId, id)
        local option
        if (id == 'installskimmer' or id == 'adjustskimmer') and GetResourceState('ox_lib') == 'started' then
            local sk = cfg.Skimmer or {}
            local max = math.max(0, math.min(100, tonumber(sk.MaxPercent) or 50))
            local result = exports.ox_lib:inputDialog('Card skimmer', {
                { type = 'slider', label = 'Skim from each card payment (%)', min = 0, max = max, step = 1,
                    default = math.min(max, tonumber(sk.Percent) or 15) },
            })
            if not result then return end
            option = { percent = tonumber(result[1]) }
        end
        TriggerServerEvent('meta_comic:server:crimeStart', machineId, id, option)
    end
    -- Read / Adjust / Remove share one "Manage card skimmer" target option (installer only) that opens a menu
    local SKIMMER_MENU = { collectskimmer = true, adjustskimmer = true, removeskimmer = true }
    local skimmerMenu = {}
    for _, action in ipairs(ACTIONS) do
        local s = crime[action.key]
        if type(s) == 'table' and s.Enabled ~= false and SKIMMER_MENU[action.id] then
            skimmerMenu[#skimmerMenu + 1] = { id = action.id, label = s.Label or action.label, icon = s.Icon or action.icon }
        elseif type(s) == 'table' and s.Enabled ~= false then
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
                    if not machine or busy or looting then return false end
                    local controlled = MetaComic.VendingControls and MetaComic.VendingControls(machine.id)
                    if action.id == 'bolt' then return machine.bolted == false end -- server verifies installer, owner, employee or full key
                    if action.id == 'steal' and machine.bolted == false then return false end
                    if action.id == 'takemachine' and machine.bolted ~= false then return false end
                    -- hacks and the GPS switch only show with the machine and its server rack (or cash box) open (client/vending_door.lua)
                    if MetaComic.VendingTechReady then
                        if not MetaComic.VendingTechReady(machine.id, action.id) then return false end
                    elseif (action.id == 'hack' or action.id == 'fullhack') and MetaComic.VendingHackReady and not MetaComic.VendingHackReady(machine.id) then return false end
                    if action.id == 'fullhack' then return not machine.systemTakenOver and MetaComic.VendingCanFullHack and MetaComic.VendingCanFullHack(machine.id) == true end
                    if action.id == 'replaceboard' then return machine.systemTakenOver and MetaComic.VendingCanReplaceBoard and MetaComic.VendingCanReplaceBoard(machine.id) == true end
                    if action.id == 'secure' then return not machine.securitySeal and ((machine.unlockedUntil or 0) > 0 or machine.lockCondition == 'damaged') end
                    if action.id == 'disablegps' then return (cfg.GPS or {}).Enabled ~= false and not machine.gpsDisabled end
                    if action.id == 'enablegps' then return (cfg.GPS or {}).Enabled ~= false and machine.gpsDisabled == true
                        and MetaComic.VendingCanOperateSystem and MetaComic.VendingCanOperateSystem(machine.id) == true end
                    -- a skimmer is meant to go unnoticed: its options only show to whoever installed it, and Install shows
                    -- whether or not one is already fitted. Owners and police check the panel instead.
                    if action.id == 'inspectpanel' then return MetaComic.VendingCanInspectPanel and MetaComic.VendingCanInspectPanel(machine.id) == true end
                    if action.id:find('skimmer') then
                        if (cfg.Skimmer or {}).Enabled == false then return false end
                        local mine = MetaComic.VendingMySkimmer and MetaComic.VendingMySkimmer(machine.id)
                        if action.id == 'installskimmer' then return not mine and (crime.OwnersCanRob or not controlled) end
                        return machine.skimmer == true and mine -- the server checks the installer again
                    end
                    if action.id == 'breakin' and (cfg.Keys or {}).Enabled == true then return true end -- server checks recovery permission
                    return crime.OwnersCanRob or not (MetaComic.VendingControls and MetaComic.VendingControls(machine.id))
                end,
                onSelect = function(data)
                    if action.id == 'installskimmer' then
                        local model = (cfg.Skimmer or {}).Model
                        if not model or not IsModelInCdimage(joaat(model)) then return notify('The configured skimmer prop has not been streamed yet.', 'error') end
                    end
                    local machine = MetaComic.VendingMachineOf(data.entity)
                    if machine then start(machine.id, action.id) end
                end,
            }
        end
    end
    if #skimmerMenu > 0 and (cfg.Skimmer or {}).Enabled ~= false then
        options[#options + 1] = {
            name = 'meta_comic_vending_skimmer', label = 'Manage card skimmer', icon = 'fas fa-credit-card',
            distance = (cfg.Shop and cfg.Shop.TargetDistance) or 2.0,
            canInteract = function(entity)
                local machine = MetaComic.VendingMachineOf and MetaComic.VendingMachineOf(entity)
                return machine ~= nil and not busy and not looting and machine.skimmer == true
                    and MetaComic.VendingMySkimmer ~= nil and MetaComic.VendingMySkimmer(machine.id) == true
            end,
            onSelect = function(data)
                local machine = MetaComic.VendingMachineOf(data.entity)
                if not machine then return end
                if GetResourceState('ox_lib') ~= 'started' then return notify('The skimmer menu needs ox_lib.', 'error') end
                local rows = {}
                for _, entry in ipairs(skimmerMenu) do
                    rows[#rows + 1] = { title = entry.label, icon = entry.icon:gsub('^fas fa%-', ''), onSelect = function() start(machine.id, entry.id) end }
                end
                exports.ox_lib:registerContext({ id = 'meta_comic_vending_skimmer', title = 'Card skimmer', options = rows })
                exports.ox_lib:showContext('meta_comic_vending_skimmer')
            end,
        }
    end
    if ((crime.BreakIn or {}).Loot or {}).Enabled ~= false then
        options[#options + 1] = {
            name = 'meta_comic_vending_loot', label = 'Inspect / loot unlocked machine', icon = 'fas fa-box-open', distance = 2.0,
            canInteract = function(entity)
                local machine = MetaComic.VendingMachineOf and MetaComic.VendingMachineOf(entity)
                -- broken into, or the door stands open (unlocked with a key, being serviced)
                return machine and not busy and not looting and ((machine.unlockedUntil or 0) > 0
                    or MetaComic.VendingCabinetOpen ~= nil and MetaComic.VendingCabinetOpen(machine.id) and not machine.securitySeal)
            end,
            onSelect = function(data)
                local machine = MetaComic.VendingMachineOf(data.entity)
                if machine then TriggerServerEvent('meta_comic:server:lootInspect', machine.id) end
            end,
        }
    end
    if #options > 0 then exports.ox_target:addModel(cfg.Model or 'metacomics_vending_machine', options) end
end)

AddEventHandler('onResourceStop', function(name)
    if name == GetCurrentResourceName() then
        if looting and GetResourceState('ox_lib') == 'started' then pcall(function() exports.ox_lib:cancelProgress() end) end
        looting = false
        stopLootVisual()
        dropProp()
    end
end)
