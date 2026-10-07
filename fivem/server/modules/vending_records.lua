-- Vending machine records for people (Config.VendingMachines.Records):
--   admin UI "Machine records" tab: register owners, set each owner's tax rate, assign machines by serial, reset hacked
--     routing, pay out business earnings held in the records, print record items
--   'vending_registration' item: one machine's registration certificate. Using it shows that machine's CURRENT record
--     (owner, routing, where it is), so a stolen or hacked machine shows up when someone checks the papers
--   'vending_ledger' item: the business's ledger book. Using it lists every registered owner and machine
local cfg = Config.VendingMachines or {}
if cfg.Enabled == false then return end
local records = cfg.Records or {}
local Registry = MetaComic.VendingRegistry
local Vending = MetaComic.Vending
local CERTIFICATE = records.CertificateItem or 'vending_registration'
local LEDGER = records.LedgerItem or 'vending_ledger'

MetaComic.VendingRecords = {}
local service = MetaComic.VendingRecords

local function notify(source, message, notifyType)
    if MetaComic.Framework.notify then MetaComic.Framework.notify(source, message, notifyType) end
end
local function canManage(source) return MetaComic.CanManage and MetaComic.CanManage(source) == true end
local function hasItem(source, item) return (MetaComic.Inventory.count and MetaComic.Inventory.count(source, item) or 0) > 0 end

function service.giveCertificate(source, serial)
    local record = Registry.get(serial)
    if not record then return notify(source, 'Unknown serial number.', 'error') end
    local view = Registry.view(record)
    local metadata = {
        serial = serial, owner = view.ownerName, routing = view.ownerRouting, tax = view.tax, issued = os.date('%Y-%m-%d'),
        label = ('Registration %s'):format(serial),
        description = ('Vending machine %s · registered to %s · routing %s'):format(serial, view.ownerName, view.ownerRouting or '-'),
    }
    if MetaComic.Inventory.canCarry and not MetaComic.Inventory.canCarry(source, CERTIFICATE, 1) then return notify(source, 'You cannot carry the certificate.', 'error') end
    if MetaComic.Inventory.add(source, CERTIFICATE, 1, metadata) then
        Registry.update(serial, nil, 'Registration certificate printed', Registry.nameOf(source))
        notify(source, ('Registration certificate for %s printed.'):format(serial), 'success')
        return true
    end
    notify(source, 'Could not give the certificate.', 'error')
end

local function ledgerList()
    local machines, people = {}, {}
    for _, record in ipairs(Registry.all()) do
        if record.status ~= 'removed' or records.LedgerShowsRemoved then machines[#machines + 1] = Registry.view(record) end
    end
    for _, person in ipairs(Registry.people()) do people[#people + 1] = { name = person.name, routing = person.routing, tax = person.tax } end
    return machines, people
end

-- items ---------------------------------------------------------------------------------------------------------------
local function useCertificate(source, slot)
    local item = slot and MetaComic.Inventory.getSlot and MetaComic.Inventory.getSlot(source, tonumber(slot))
    if not item or item.name ~= CERTIFICATE then return end
    local printed = item.metadata or item.info or {}
    local record = Registry.get(printed.serial)
    TriggerClientEvent('meta_comic:client:vendingRecord', source, {
        kind = 'certificate', printed = printed, current = Registry.view(record), business = Registry.businessName,
    })
end
local function useLedger(source, slot)
    local item = slot and MetaComic.Inventory.getSlot and MetaComic.Inventory.getSlot(source, tonumber(slot))
    if not item or item.name ~= LEDGER then return end
    local machines, people = ledgerList()
    TriggerLatentClientEvent('meta_comic:client:vendingRecord', source, 256 * 1024, { kind = 'ledger', machines = machines, people = people, business = Registry.businessName })
end
RegisterNetEvent('meta_comic:server:useVendingRecord', function(kind, slot)
    if kind == 'ledger' then useLedger(source, slot) else useCertificate(source, slot) end
end)
if MetaComic.Framework.registerUsableItem and Config.Items.RegisterUsableItems ~= false then
    MetaComic.Framework.registerUsableItem(CERTIFICATE, function(source, item) useCertificate(source, item and item.slot) end)
    MetaComic.Framework.registerUsableItem(LEDGER, function(source, item) useLedger(source, item and item.slot) end)
end

-- admin UI --------------------------------------------------------------------------------------------------------------
local function onlinePlayers()
    local list = {}
    for _, player in ipairs(GetPlayers()) do
        player = tonumber(player)
        list[#list + 1] = { serverId = player, id = Registry.identifierOf(player), name = Registry.nameOf(player) }
    end
    table.sort(list, function(a, b) return a.serverId < b.serverId end)
    return list
end
local function snapshot()
    local machines, people = {}, {}
    local counts = {}
    for _, record in ipairs(Registry.all()) do
        local view = Registry.view(record, true)
        local entry = record.status == 'placed' and Vending.bySerial(record.serial)
        view.cash = entry and entry.cash or nil
        machines[#machines + 1] = view
        if record.owner and record.status ~= 'removed' then counts[record.owner] = (counts[record.owner] or 0) + 1 end
    end
    for _, person in ipairs(Registry.people()) do
        people[#people + 1] = { id = person.id, name = person.name, routing = person.routing, tax = person.tax, registeredAt = person.registeredAt,
            machines = counts[person.id] or 0, pending = Registry.pending(person.id) }
    end
    return {
        ok = true, machines = machines, people = people, online = onlinePlayers(), business = Registry.businessName,
        businessRouting = Registry.businessRouting(), businessPending = Registry.businessPending(),
        defaultTax = tonumber((cfg.Ownership or {}).DefaultTax) or 10,
    }
end

if MetaComic.RpcHandlers then
    MetaComic.RpcHandlers.getVendingRecords = function(source)
        if not canManage(source) then return { ok = false, error = 'You are not allowed to see the machine records.' } end
        return snapshot()
    end
    -- payload.action: 'register' { serverId | id, name, tax } | 'tax' { id, tax } (or { taxes = { [id] = rate } })
    --   | 'unregister' { id } | 'assign' { serial, owner } | 'resetRouting' { serial } | 'withdraw' { amount }
    --   | 'certificate' { serial } | 'ledger'
    MetaComic.RpcHandlers.saveVendingRecords = function(source, payload)
        if not canManage(source) then return { ok = false, error = 'You are not allowed to change the machine records.' } end
        local action, by = payload.action, Registry.nameOf(source)
        local ok, err = true, nil
        if action == 'register' then
            local id, name = payload.id, payload.name
            local target = tonumber(payload.serverId)
            if target and GetPlayerName(target) then id, name = Registry.identifierOf(target), name or Registry.nameOf(target) end
            if type(id) ~= 'string' or id == '' then return { ok = false, error = 'Pick an online player or enter their identifier.' } end
            ok, err = Registry.register(id, type(name) == 'string' and name ~= '' and name:sub(1, 60) or id, payload.tax, by)
        elseif action == 'tax' then
            for id, rate in pairs(type(payload.taxes) == 'table' and payload.taxes or { [tostring(payload.id)] = payload.tax }) do
                ok, err = Registry.setTax(id, rate)
                if not ok then break end
            end
        elseif action == 'unregister' then
            ok, err = Registry.unregister(payload.id)
        elseif action == 'assign' then
            ok, err = Registry.assign(payload.serial, payload.owner, by)
            if ok then Vending.sendAccessAll() end
        elseif action == 'resetRouting' then
            if not Registry.get(payload.serial) then return { ok = false, error = 'Unknown serial number.' } end
            Registry.resetRouting(payload.serial, by)
            Vending.sendAccessAll()
        elseif action == 'withdraw' then
            ok, err = Registry.withdrawBusiness(source, payload.amount)
        elseif action == 'certificate' then
            ok = service.giveCertificate(source, payload.serial) == true
            err = not ok and 'Could not give the certificate.' or nil
        elseif action == 'ledger' then
            ok = MetaComic.Inventory.add(source, LEDGER, 1, { label = ('%s machine ledger'):format(Registry.businessName), description = 'Registered vending machine owners and serial numbers.' }) == true
            err = not ok and 'Could not give the ledger.' or nil
        else
            return { ok = false, error = 'Unknown action.' }
        end
        if not ok then return { ok = false, error = err or 'Could not save the records.' } end
        return snapshot()
    end
end
