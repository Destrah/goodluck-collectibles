local cfg = Config.VendingMachines or {}
local keys = cfg.Keys or {}
if cfg.Enabled == false or keys.Enabled ~= true then return end
local replacing = false
local keyUsing, keyGeneration, handKey = false, 0, nil
local openingId, openingUntil
local closingForLock
RegisterNetEvent('meta_comic:client:vendingKeyCloseForLock', function(id, kind)
    if source == 65535 and closingForLock and closingForLock.id == id and closingForLock.kind == (kind or 'cylinder') then
        closingForLock.confirmed = true
    end
end)
MetaComic.VendingKeyWorkBusy = function() return replacing or keyUsing or MetaComic.PropTuneBusy and MetaComic.PropTuneBusy() end
local keySessions = {}
RegisterNetEvent('meta_comic:client:vendingKeyAccess', function(data)
    if source ~= 65535 then return end
    if (data.seconds or 0) <= 0 then keySessions[data.id] = nil; return end
    keySessions[data.id] = { serial = data.serial, revision = data.revision, full = data.full, expires = GetGameTimer() + data.seconds * 1000 }
end)
MetaComic.VendingHasKeyAccess = function(id, full)
    local session = keySessions[id]
    local machine = MetaComic.VendingMachineById and MetaComic.VendingMachineById(id)
    return session ~= nil and machine ~= nil and session.expires > GetGameTimer()
        and session.serial == machine.serial and session.revision == machine.lockRevision and (not full or session.full == true)
end
local function notify(text, kind) TriggerEvent('meta_comic:client:notify', text, kind or 'info') end
local function clearHandKey()
    if handKey and DoesEntityExist(handKey) then DeleteEntity(handKey) end
    handKey = nil
end
local function useKeyAtLock(id, kind, mode, alreadyOpen)
    if replacing or keyUsing or MetaComic.PropTuneBusy and MetaComic.PropTuneBusy() or MetaComic.VendingActionBusy and MetaComic.VendingActionBusy() then
        return notify('Finish your current action first.', 'error')
    end
    local visual = keys.UseAnimation or {}
    local profileName = ({ padlock = 'Padlock', cylinder = 'Cylinder', cashbox = 'Cashbox', rack = 'Rack' })[kind]
    local installing = kind == 'padlock' and mode == 'install'
    local locking = installing or mode == 'lock' or mode == false
    if installing then profileName = 'InstallPadlock' end
    local profile = (visual.Profiles or {})[profileName] or {}
    local anim = profile.Animation or visual.Animation
        or { dict = 'anim@scripted@heist@ig13_jailor_key_turn@generic@male@', clip = 'action', flag = 0 }
    local function request()
        if kind == 'padlock' then TriggerServerEvent('meta_comic:server:vendingPadlock', id, installing and 'install' or 'remove')
        elseif kind == 'cashbox' then TriggerServerEvent('meta_comic:server:vendingCashboxKey', id, not locking)
        elseif kind == 'rack' then TriggerServerEvent('meta_comic:server:vendingRackKey', id, not locking)
        elseif locking then TriggerServerEvent('meta_comic:server:vendingKeyLock', id)
        else TriggerServerEvent('meta_comic:server:vendingKeyUnlock', id, mode) end
    end
    if visual.Enabled == false or alreadyOpen then return request() end
    if GetResourceState('ox_lib') ~= 'started' then return notify('Key interactions need ox_lib.', 'error') end
    local machine = MetaComic.VendingMachineById and MetaComic.VendingMachineById(id)
    local ped = PlayerPedId()
    if not machine or not machine.entity or not DoesEntityExist(machine.entity) or IsPedInAnyVehicle(ped, false) then
        return notify('Stand at the vending machine first.', 'error')
    end
    keyUsing, keyGeneration = true, keyGeneration + 1
    local generation = keyGeneration
    ClearEntityLastDamageEntity(ped)
    local function current()
        return keyUsing and keyGeneration == generation and DoesEntityExist(machine.entity)
            and not IsEntityDead(ped) and not HasEntityBeenDamagedByAnyPed(ped)
            and not IsPedRagdoll(ped) and not IsPedBeingStunned(ped, 0)
    end
    local function finish()
        if keyGeneration ~= generation then return end
        closingForLock = nil
        clearHandKey()
        ClearPedTasks(ped)
        if keyGeneration == generation then keyUsing = false; keyGeneration = keyGeneration + 1 end
    end
    local closedInterior = false
    if locking then
        if not installing then
            closingForLock = { id = id, kind = kind }
            if kind == 'cylinder' then TriggerServerEvent('meta_comic:server:vendingKeyCloseForLock', id)
            else request() end
            local confirmDeadline = GetGameTimer() + 5000
            while current() and not closingForLock.confirmed and GetGameTimer() < confirmDeadline do Wait(0) end
            if not current() or not closingForLock or not closingForLock.confirmed then
                finish()
                return notify('The door or lid could not be closed for locking.', 'error')
            end
        end
        local closeDeadline = GetGameTimer() + 5000
        local function stillOpen()
            if MetaComic.VendingLockPartsOpen then return MetaComic.VendingLockPartsOpen(id, kind) end
            return kind == 'cylinder' and MetaComic.VendingDoorOpen and MetaComic.VendingDoorOpen(id)
        end
        while current() and stillOpen() and GetGameTimer() < closeDeadline do Wait(0) end
        if not current() or stillOpen() then
            finish()
            return notify('Wait for the door and lids to close before locking.', 'error')
        end
        closedInterior = not installing and kind ~= 'cylinder'
        closingForLock = nil
    end
    local spot = profile.Spot or kind == 'cashbox' and (visual.CashboxSpot or vec3(0.40, -1.05, -0.95))
        or kind == 'rack' and (visual.RackSpot or vec3(0.35, -0.95, -0.95))
        or kind == 'padlock' and (visual.PadlockSpot or vec3(0.58, -0.98, -0.95))
        or (visual.CylinderSpot or vec3(0.49, -0.98, -0.95))
    local target = GetOffsetFromEntityInWorldCoords(machine.entity, spot.x, spot.y, spot.z)
    local lock = profile.Target or kind == 'padlock' and ((keys.Padlock or {}).Offset or vec3(0.58, -0.44, 0.14))
        or kind == 'cashbox' and vec3(0.40, -0.44, -0.55)
        or kind == 'rack' and vec3(0.35, -0.44, 0.0) or vec3(0.49, -0.44, 0.24)
    local face = GetOffsetFromEntityInWorldCoords(machine.entity, lock.x, lock.y, lock.z)
    local heading = GetHeadingFromVector_2d(face.x - target.x, face.y - target.y)
    local approachMs = math.max(500, math.min(2000, tonumber(visual.ApproachMs) or 1000))
    ClearPedTasks(ped)
    TaskGoStraightToCoord(ped, target.x, target.y, GetEntityCoords(ped).z, 1.0, approachMs + 200, heading, 0.1)
    local deadline = GetGameTimer() + approachMs
    while current() and GetGameTimer() < deadline do Wait(0) end
    local arrived = GetEntityCoords(ped)
    -- Keep the player's real ground height: the model's origin/ground offset varies by export.
    if not current() or (arrived.x - target.x)^2 + (arrived.y - target.y)^2 > 2.0^2 then finish(); return end
    local moved = GetOffsetFromEntityInWorldCoords(machine.entity, spot.x, spot.y, spot.z)
    if #(moved - target) > 0.3 then finish(); return notify('The machine moved out of reach.', 'error') end
    ClearPedTasks(ped)
    SetEntityCoordsNoOffset(ped, target.x, target.y, GetEntityCoords(ped).z, false, false, false)
    SetEntityHeading(ped, heading)
    Wait(0)
    local model = installing and ((keys.Padlock or {}).Model or 'prop_cs_padlock')
        or kind == 'cylinder' and (visual.CabinetModel or 'h4_prop_h4_key_desk_01')
        or (visual.Model or 'tr_prop_tr_car_keys_01a')
    local hash = joaat(model)
    if IsModelInCdimage(hash) then
        RequestModel(hash)
        deadline = GetGameTimer() + 3000
        while current() and not HasModelLoaded(hash) and GetGameTimer() < deadline do Wait(0) end
        if current() and HasModelLoaded(hash) then
            local here = GetEntityCoords(ped)
            handKey = CreateObject(hash, here.x, here.y, here.z, true, true, false)
            local pos, rot = profile.Offset or visual.Offset or vec3(0.04, 0.01, 0.0), profile.Rotation or visual.Rotation or vec3(0.0, 0.0, -90.0)
            SetEntityCollision(handKey, false, false)
            -- A skeletal finger follows the rendered/IK hand; the PH hand helper can lag behind it.
            local gripBone = GetPedBoneIndex(ped, profile.Bone or visual.Bone or 57005)
            if gripBone == -1 then gripBone = GetPedBoneIndex(ped, 57005) end
            AttachEntityToEntity(handKey, ped, gripBone,
                pos.x, pos.y, pos.z, rot.x, rot.y, rot.z, true, true, false, true, 1, true)
        end
        SetModelAsNoLongerNeeded(hash)
    end
    if not current() then finish(); return end
    RequestAnimDict(anim.dict)
    deadline = GetGameTimer() + 3000
    while current() and not HasAnimDictLoaded(anim.dict) and GetGameTimer() < deadline do Wait(0) end
    if not current() or not HasAnimDictLoaded(anim.dict) then
        finish()
        return notify('The lock animation could not be loaded.', 'error')
    end
    -- Anchor to the actual settled ped, not the theoretical model-local floor point.
    local anchor = GetEntityCoords(ped)
    local duration = tonumber(profile.Duration) or tonumber(visual.Duration) or 4500
    local startedAt = GetGameTimer()
    local reachStart = math.max(0, math.min(1, tonumber(profile.ReachStart) or 0.20))
    local reachEnd = math.max(reachStart, math.min(1, tonumber(profile.ReachEnd) or 0.80))
    CreateThread(function()
        while keyUsing and keyGeneration == generation do
            if not current() or #(GetEntityCoords(ped) - anchor) > 0.65 then
                pcall(function() if exports.ox_lib:progressActive() then exports.ox_lib:cancelProgress() end end)
                finish()
                return
            end
            -- Right-arm IK is valid for one frame: aim at the real lock during insertion/turning.
            -- Let the animation lower the hand normally before and after contact.
            local phase = (GetGameTimer() - startedAt) / duration
            if SetIkTarget and phase >= reachStart and phase <= reachEnd then
                local hand = GetOffsetFromEntityInWorldCoords(machine.entity, lock.x, lock.y, lock.z)
                SetIkTarget(ped, 4, 0, -1, hand.x, hand.y, hand.z, 16, 200, 200)
            end
            Wait(0)
        end
    end)
    local label = installing and 'Fitting and locking the padlock'
        or kind == 'padlock' and 'Unlocking the padlock'
        or kind == 'cashbox' and (locking and 'Closing and locking the cash box' or 'Unlocking the cash box')
        or kind == 'rack' and (locking and 'Closing and locking the server rack' or 'Unlocking the server rack')
        or (locking and 'Closing and locking the cabinet' or 'Turning the cabinet key')
    local done = exports.ox_lib:progressBar({ duration = duration,
        label = label, canCancel = true,
        disable = { move = true, car = true, combat = true },
        anim = anim }) == true
    local valid = current()
    finish()
    if not done or not valid then return notify('Key use stopped.', 'info') end
    -- Inventory, key validity, padlock removal and opening remain server-authoritative.
    if kind == 'cylinder' and not locking then openingId, openingUntil = id, GetGameTimer() + 4000 end
    if not closedInterior then request() end
end
MetaComic.VendingUseKeyAtLock = useKeyAtLock
RegisterNetEvent('meta_comic:client:vendingKeyUnlocked', function(data)
    if source ~= 65535 or not data.open or openingId ~= data.id or GetGameTimer() > (openingUntil or 0) then return end
    openingId = nil
    if keyUsing or replacing or MetaComic.VendingActionBusy and MetaComic.VendingActionBusy() then return end
    local machine = MetaComic.VendingMachineById and MetaComic.VendingMachineById(data.id)
    local ped = PlayerPedId()
    if not machine or not DoesEntityExist(machine.entity) or IsEntityDead(ped) or IsPedRagdoll(ped) then return end
    local anim = (keys.UseAnimation or {}).OpenAnimation or { dict = 'mp_common', clip = 'givetake1_a', flag = 1, Duration = 650 }
    RequestAnimDict(anim.dict)
    local deadline = GetGameTimer() + 1000
    while not HasAnimDictLoaded(anim.dict) and GetGameTimer() < deadline do Wait(0) end
    if HasAnimDictLoaded(anim.dict) and not keyUsing and not replacing and not IsEntityDead(ped)
        and not HasEntityBeenDamagedByAnyPed(ped) and not IsPedRagdoll(ped) then
        TaskPlayAnim(ped, anim.dict, anim.clip, 3.0, 3.0, tonumber(anim.Duration) or 650, anim.flag or 1, 0, false, false, false)
    end
end)
AddEventHandler('onResourceStop', function(resource)
    if resource ~= GetCurrentResourceName() then return end
    if keyUsing then ClearPedTasks(PlayerPedId()) end
    keyUsing = false; keyGeneration = keyGeneration + 1; openingId = nil; closingForLock = nil
    clearHandKey()
end)
local function slotOf(...)
    for i = 1, select('#', ...) do
        local value = select(i, ...)
        if type(value) == 'table' and tonumber(value.slot) then return tonumber(value.slot) end
        if tonumber(value) then return tonumber(value) end
    end
end
exports('UseVendingKey', function(...) local slot = slotOf(...); if slot then TriggerServerEvent('meta_comic:server:useVendingKey', slot) end end)
exports('UseVendingKeyRecord', function(...) local slot = slotOf(...); if slot then TriggerServerEvent('meta_comic:server:useVendingRecord', 'keyreport', slot) end end)
RegisterNetEvent('meta_comic:client:vendingKeyMenu', function(data)
    if GetResourceState('ox_lib') ~= 'started' then return notify('Cabinet menus need ox_lib.', 'error') end
    local options = {
        { title = data.serial, description = ('Cylinder %s | %s'):format(data.lockId, data.sealText and 'chained and padlocked' or data.condition), readOnly = true, icon = 'key' },
    }
    local withBox = data.boxEnabled and data.hasFull
    if data.padlock then
        options[#options + 1] = { title = 'Unlock and remove padlock', icon = 'unlock', disabled = not data.hasKey,
            description = 'Requires a valid key for the current cylinder. Returns the padlock to your inventory.',
            onSelect = function() useKeyAtLock(data.id, 'padlock') end }
    end
    if data.canPadlock then
        options[#options + 1] = { title = 'Install padlock', icon = 'lock', disabled = not data.hasPadlockItem,
            description = 'Consumes one vending padlock. The main door must be closed.',
            onSelect = function() useKeyAtLock(data.id, 'padlock', 'install') end }
    end
    if data.padlockReturn then
        options[#options + 1] = { title = 'Collect removed padlock', icon = 'lock',
            onSelect = function() TriggerServerEvent('meta_comic:server:vendingPadlock', data.id, 'collect') end }
    end
    if data.canUnseal then
        options[#options + 1] = { title = 'Remove security seal and open cabinet', description = 'The cylinder remains damaged until repaired or replaced.', icon = 'unlock',
            onSelect = function() TriggerServerEvent('meta_comic:server:vendingDamagedDoor', data.id, true) end }
    elseif data.damagedUnsealed then
        options[#options + 1] = { title = data.cabinetOpen and 'Close damaged cabinet' or 'Open damaged cabinet', disabled = data.looting,
            description = data.looting and 'Wait until looting finishes.' or 'Closing the door does not secure its damaged lock.', icon = 'door-open',
            onSelect = function() TriggerServerEvent('meta_comic:server:vendingDamagedDoor', data.id, not data.cabinetOpen) end }
    end
    if data.cabinetOpen and data.session then
        -- already open with your key: the cash box opens and shuts on its own
        if data.boxEnabled and data.fullSession then
            options[#options + 1] = data.boxOpen
                and { title = 'Close cash box', description = 'The machine stays open', icon = 'box',
                    onSelect = function() useKeyAtLock(data.id, 'cashbox', false) end }
                or { title = 'Open cash box', icon = 'box-open',
                    onSelect = function() useKeyAtLock(data.id, 'cashbox') end }
        end
        -- server rack: needed open for board, OS, payment and GPS work (server/modules/vending_door.lua)
        if data.rackEnabled and data.fullSession then
            options[#options + 1] = data.rackOpen
                and { title = 'Close server rack', description = 'The machine stays open', icon = 'server',
                    onSelect = function() useKeyAtLock(data.id, 'rack', false) end }
                or { title = 'Open server rack', description = 'Board, operating system, payment and GPS work', icon = 'server',
                    onSelect = function() useKeyAtLock(data.id, 'rack') end }
        end
    elseif not data.damagedUnsealed and not data.padlock then
        options[#options + 1] = { title = data.cabinetOpen and 'Authenticate cabinet key' or withBox and 'Open machine only' or 'Unlock cabinet with key', icon = 'unlock', disabled = data.sealText ~= nil or not data.hasKey,
            description = data.sealText or (not data.hasKey and 'Requires a matching current cylinder key.' or data.cabinetOpen and 'The cabinet is already open. Use your key to access its controls.' or withBox and 'The cash box stays shut' or nil),
            onSelect = function() useKeyAtLock(data.id, 'cylinder', 'door', data.cabinetOpen) end }
        if withBox and not data.cabinetOpen then
            options[#options + 1] = { title = 'Open machine and cash box', icon = 'box-open', disabled = data.sealText ~= nil or not data.hasKey, description = data.sealText,
                onSelect = function() useKeyAtLock(data.id, 'cylinder', 'both') end }
        end
    end
    if not data.damagedUnsealed and data.cabinetOpen then
        options[#options + 1] = { title = data.boxOpen and 'Close machine and cash box' or data.rackOpen and 'Close machine and server rack' or 'Close and lock cabinet',
            disabled = not data.session or data.looting, description = data.looting and 'Wait until looting finishes.' or not data.session and 'Authenticate a current cabinet key first.' or 'Locks the cabinet and ends all key access sessions', icon = 'lock',
            onSelect = function() useKeyAtLock(data.id, 'cylinder', 'lock') end }
    end
    if data.canRepair then
        options[#options + 1] = { title = 'Repair damaged cylinder', icon = 'wrench', disabled = data.repairMissing ~= nil,
            description = ('Uses %s. Requires the main door open and keeps the current keys.'):format(data.repairItems or 'repair parts'),
            onSelect = function()
                if exports.ox_lib:alertDialog({ header = 'Repair cylinder', content = ('Repair the lock cylinder using %s? Existing keys keep working.'):format(data.repairItems or 'repair parts'), cancel = true }) == 'confirm' then
                    TriggerServerEvent('meta_comic:server:vendingRepairStart', data.id)
                end
            end }
    end
    if data.canReplace then
        options[#options + 1] = { title = 'Replace / rekey cylinder', disabled = data.hasCylinder == false, description = 'Requires a replacement cylinder. Issues a new key; old keys stop working.', icon = 'screwdriver-wrench',
            onSelect = function()
                if exports.ox_lib:alertDialog({ header = 'Replace cylinder', content = 'Invalidate all existing keys and remove any chain and padlock?', cancel = true }) == 'confirm' then
                    TriggerServerEvent('meta_comic:server:vendingRekeyStart', data.id)
                end
            end }
    end
    if data.replacementKeyDue then
        options[#options + 1] = { title = 'Collect replacement key', description = 'Collect the full-access key included with your cylinder replacement.', icon = 'key',
            onSelect = function() TriggerServerEvent('meta_comic:server:vendingReplacementKey', data.id) end }
    end
    if data.canIssue then
        options[#options + 1] = { title = 'Issue / duplicate numbered key', icon = 'key', onSelect = function()
            local result = exports.ox_lib:inputDialog('Issue vending key', {
                { type = 'number', label = 'Recipient server ID', min = 1, required = true },
                { type = 'select', label = 'Access', default = 'full', required = true, options = { { value = 'full', label = 'Full: stock, prices, cash, bolts' }, { value = 'service', label = 'Service: restock and prices' } } },
            })
            if result then TriggerServerEvent('meta_comic:server:vendingIssueKey', data.serial, result[1], result[2]) end
        end }
    end
    if data.canRead then
        options[#options + 1] = { title = 'Read permanent key records', icon = 'book', onSelect = function() TriggerServerEvent('meta_comic:server:vendingKeyReport', data.serial, false) end }
        options[#options + 1] = { title = 'Print permanent key records', icon = 'print', onSelect = function() TriggerServerEvent('meta_comic:server:vendingKeyReport', data.serial, true) end }
    end
    if data.busy then
        for _, option in ipairs(options) do
            if option.onSelect and option.icon ~= 'book' and option.icon ~= 'print' then
                option.disabled, option.description = true, 'The machine is busy. Wait for its current action to finish.'
            end
        end
    end
    exports.ox_lib:registerContext({ id = 'meta_comic_vending_keys', title = 'Cabinet lock and keys', options = options })
    exports.ox_lib:showContext('meta_comic_vending_keys')
end)
RegisterNetEvent('meta_comic:client:vendingRekeyStart', function(data)
    if replacing or keyUsing then return TriggerServerEvent('meta_comic:server:vendingRekeyCancel') end
    if GetResourceState('ox_lib') ~= 'started' then
        TriggerServerEvent('meta_comic:server:vendingRekeyCancel')
        return notify('Cylinder replacement needs ox_lib.', 'error')
    end
    replacing = true
    local machine = MetaComic.VendingMachineById and MetaComic.VendingMachineById(data.id)
    local ped = PlayerPedId()
    if not machine or not machine.entity or not DoesEntityExist(machine.entity) or IsPedInAnyVehicle(ped, false) then
        replacing = false
        return TriggerServerEvent('meta_comic:server:vendingRekeyCancel')
    end
    local offset = keys.ReplaceOffset or vector3(0.85, -0.15, 0.0)
    local position = GetOffsetFromEntityInWorldCoords(machine.entity, offset.x, offset.y, offset.z)
    local center = GetEntityCoords(machine.entity)
    local heading = GetHeadingFromVector_2d(center.x - position.x, center.y - position.y)
    local function atSide()
        local coords = GetEntityCoords(ped)
        return (coords.x - position.x)^2 + (coords.y - position.y)^2 <= 0.35^2
    end
    -- Walk to the side rather than moving the player through a wall or the cabinet.
    TaskGoStraightToCoord(ped, position.x, position.y, GetEntityCoords(ped).z, 1.0, 6000, heading, 0.1)
    local deadline = GetGameTimer() + 6000
    while not atSide() and GetGameTimer() < deadline and not IsEntityDead(ped) do Wait(100) end
    ClearPedTasks(ped)
    if not atSide() or IsEntityDead(ped) then
        replacing = false
        TriggerServerEvent('meta_comic:server:vendingRekeyCancel')
        return notify('The right side of the machine must be reachable to replace its cylinder.', 'error')
    end
    SetEntityHeading(ped, heading)
    -- Keep the work pose and movement restrictions through the difficult minigames as well as the timer.
    local working = true
    RequestAnimDict('mini@repair')
    local animDeadline = GetGameTimer() + 5000
    while not HasAnimDictLoaded('mini@repair') and GetGameTimer() < animDeadline do Wait(0) end
    if not HasAnimDictLoaded('mini@repair') then
        replacing = false
        return TriggerServerEvent('meta_comic:server:vendingRekeyCancel')
    end
    CreateThread(function()
        while working do
            DisableControlAction(0, 30, true); DisableControlAction(0, 31, true)
            DisableControlAction(0, 21, true); DisableControlAction(0, 22, true)
            DisableControlAction(0, 23, true); DisableControlAction(0, 24, true); DisableControlAction(0, 25, true)
            if not IsEntityDead(ped) and not IsEntityPlayingAnim(ped, 'mini@repair', 'fixing_a_ped', 3) then
                TaskPlayAnim(ped, 'mini@repair', 'fixing_a_ped', 3.0, 3.0, -1, 1, 0.0, false, false, false)
            end
            Wait(0)
        end
    end)
    if data.minigame and (not MetaComic.RunMinigames or not MetaComic.RunMinigames(data.minigame)) then
        working, replacing = false, false
        ClearPedTasks(ped)
        TriggerServerEvent('meta_comic:server:vendingRekeyCancel')
        return notify('Cylinder fitting failed. Your replacement cylinder was not consumed.', 'error')
    end
    local completed = exports.ox_lib:progressBar({ duration = data.duration, label = 'Replacing the vending lock cylinder', canCancel = true,
        disable = { move = true, car = true, combat = true }, anim = { dict = 'mini@repair', clip = 'fixing_a_ped', flag = 1 } })
    working = false
    ClearPedTasks(ped)
    TriggerServerEvent(completed and 'meta_comic:server:vendingRekeyFinish' or 'meta_comic:server:vendingRekeyCancel', completed and data.token or nil)
    replacing = false
end)
RegisterNetEvent('meta_comic:client:vendingRepairStart', function(data)
    if replacing or keyUsing then return TriggerServerEvent('meta_comic:server:vendingRepairCancel') end
    if GetResourceState('ox_lib') ~= 'started' then
        TriggerServerEvent('meta_comic:server:vendingRepairCancel')
        return notify('Cylinder repair needs ox_lib.', 'error')
    end
    replacing = true
    local completed = exports.ox_lib:progressBar({ duration = data.duration, label = 'Repairing the vending lock cylinder', canCancel = true,
        disable = { move = true, car = true, combat = true }, anim = { dict = 'mini@repair', clip = 'fixing_a_ped' } })
    TriggerServerEvent(completed and 'meta_comic:server:vendingRepairFinish' or 'meta_comic:server:vendingRepairCancel', completed and data.token or nil)
    replacing = false
end)
CreateThread(function()
    local deadline = GetGameTimer() + 30000
    while GetResourceState('ox_target') ~= 'started' do if GetGameTimer() > deadline then return end; Wait(500) end
    exports.ox_target:addModel(cfg.Model or 'metacomics_vending_machine', {
        { name = 'meta_comic_vending_keys', label = 'Cabinet lock / keys', icon = 'fas fa-key', distance = (cfg.Shop or {}).TargetDistance or 2,
            canInteract = function(entity) return not replacing and not keyUsing and MetaComic.VendingMachineOf(entity) ~= nil end,
            onSelect = function(data) local machine = MetaComic.VendingMachineOf(data.entity); if machine then TriggerServerEvent('meta_comic:server:vendingKeyMenu', machine.id) end end },
    })
end)
