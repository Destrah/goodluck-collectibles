local cfg = Config.VendingMachines or {}
local keys = cfg.Keys or {}
if cfg.Enabled == false or keys.Enabled ~= true then return end
local replacing = false
local function notify(text, kind) TriggerEvent('meta_comic:client:notify', text, kind or 'info') end
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
    if data.canUnseal then
        options[#options + 1] = { title = 'Remove security seal and open cabinet', description = 'The cylinder remains damaged until repaired or replaced.', icon = 'unlock',
            onSelect = function() TriggerServerEvent('meta_comic:server:vendingDamagedDoor', data.id, true) end }
    elseif data.damagedUnsealed then
        options[#options + 1] = { title = data.cabinetOpen and 'Close damaged cabinet' or 'Open damaged cabinet', description = 'Closing the door does not secure its damaged lock.', icon = 'door-open',
            onSelect = function() TriggerServerEvent('meta_comic:server:vendingDamagedDoor', data.id, not data.cabinetOpen) end }
    end
    if data.cabinetOpen and data.session then
        -- already open with your key: the cash box opens and shuts on its own
        if data.boxEnabled and data.fullSession then
            options[#options + 1] = data.boxOpen
                and { title = 'Close cash box', description = 'The machine stays open', icon = 'box',
                    onSelect = function() TriggerServerEvent('meta_comic:server:vendingCashboxKey', data.id, false) end }
                or { title = 'Open cash box', icon = 'box-open',
                    onSelect = function() TriggerServerEvent('meta_comic:server:vendingCashboxKey', data.id, true) end }
        end
        -- server rack: needed open for board, OS, payment and GPS work (server/modules/vending_door.lua)
        if data.rackEnabled and data.fullSession then
            options[#options + 1] = data.rackOpen
                and { title = 'Close server rack', description = 'The machine stays open', icon = 'server',
                    onSelect = function() TriggerServerEvent('meta_comic:server:vendingRackKey', data.id, false) end }
                or { title = 'Open server rack', description = 'Board, operating system, payment and GPS work', icon = 'server',
                    onSelect = function() TriggerServerEvent('meta_comic:server:vendingRackKey', data.id, true) end }
        end
    elseif not data.damagedUnsealed then
        options[#options + 1] = { title = withBox and 'Open machine only' or 'Unlock cabinet with key', icon = 'unlock', disabled = data.sealText ~= nil,
            description = data.sealText or (withBox and 'The cash box stays shut' or nil),
            onSelect = function() TriggerServerEvent('meta_comic:server:vendingKeyUnlock', data.id, 'door') end }
        if withBox then
            options[#options + 1] = { title = 'Open machine and cash box', icon = 'box-open', disabled = data.sealText ~= nil, description = data.sealText,
                onSelect = function() TriggerServerEvent('meta_comic:server:vendingKeyUnlock', data.id, 'both') end }
        end
    end
    if not data.damagedUnsealed then
        options[#options + 1] = { title = data.boxOpen and 'Close machine and cash box' or data.rackOpen and 'Close machine and server rack' or 'Close and lock cabinet', description = 'Locks the cabinet and ends all key access sessions', icon = 'lock',
            onSelect = function() TriggerServerEvent('meta_comic:server:vendingKeyLock', data.id) end }
    end
    if data.canRepair then
        options[#options + 1] = { title = 'Repair damaged cylinder', icon = 'wrench',
            description = ('Uses %s. Keeps the current keys and removes the chain and padlock.'):format(data.repairItems or 'repair parts'),
            onSelect = function()
                if exports.ox_lib:alertDialog({ header = 'Repair cylinder', content = ('Repair the lock cylinder using %s? Existing keys keep working.'):format(data.repairItems or 'repair parts'), cancel = true }) == 'confirm' then
                    TriggerServerEvent('meta_comic:server:vendingRepairStart', data.id)
                end
            end }
    end
    if data.canReplace then
        options[#options + 1] = { title = 'Replace / rekey cylinder', description = 'Consumes a cylinder and issues one new key. Old keys remain readable but stop working.', icon = 'screwdriver-wrench',
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
    exports.ox_lib:registerContext({ id = 'meta_comic_vending_keys', title = 'Cabinet lock and keys', options = options })
    exports.ox_lib:showContext('meta_comic_vending_keys')
end)
RegisterNetEvent('meta_comic:client:vendingRekeyStart', function(data)
    if replacing then return TriggerServerEvent('meta_comic:server:vendingRekeyCancel') end
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
    if replacing then return TriggerServerEvent('meta_comic:server:vendingRepairCancel') end
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
            canInteract = function(entity) return not replacing and MetaComic.VendingMachineOf(entity) ~= nil end,
            onSelect = function(data) local machine = MetaComic.VendingMachineOf(data.entity); if machine then TriggerServerEvent('meta_comic:server:vendingKeyMenu', machine.id) end end },
    })
end)
