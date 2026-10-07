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
    if data.cabinetOpen and data.session then
        -- already open with your key: the cash box opens and shuts on its own
        if data.boxEnabled and data.fullSession then
            options[#options + 1] = data.boxOpen
                and { title = 'Close cash box', description = 'The machine stays open', icon = 'box',
                    onSelect = function() TriggerServerEvent('meta_comic:server:vendingCashboxKey', data.id, false) end }
                or { title = 'Open cash box', icon = 'box-open',
                    onSelect = function() TriggerServerEvent('meta_comic:server:vendingCashboxKey', data.id, true) end }
        end
    else
        options[#options + 1] = { title = withBox and 'Open machine only' or 'Unlock cabinet with key', icon = 'unlock', disabled = data.sealText ~= nil,
            description = data.sealText or (withBox and 'The cash box stays shut' or nil),
            onSelect = function() TriggerServerEvent('meta_comic:server:vendingKeyUnlock', data.id, 'door') end }
        if withBox then
            options[#options + 1] = { title = 'Open machine and cash box', icon = 'box-open', disabled = data.sealText ~= nil, description = data.sealText,
                onSelect = function() TriggerServerEvent('meta_comic:server:vendingKeyUnlock', data.id, 'both') end }
        end
    end
    options[#options + 1] = { title = data.boxOpen and 'Close machine and cash box' or 'Close and lock cabinet', description = 'Locks the cabinet and ends all key access sessions', icon = 'lock',
        onSelect = function() TriggerServerEvent('meta_comic:server:vendingKeyLock', data.id) end }
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
    local completed = exports.ox_lib:progressBar({ duration = data.duration, label = 'Replacing the vending lock cylinder', canCancel = true,
        disable = { move = true, car = true, combat = true }, anim = { dict = 'mini@repair', clip = 'fixing_a_ped' } })
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
