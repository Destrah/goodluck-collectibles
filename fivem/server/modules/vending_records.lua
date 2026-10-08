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
local KEY_REPORT = (cfg.Keys or {}).ReportItem or 'vending_key_record'
local REPORTS_KEY, printedReports, printing = 'vending_key_reports', nil, false

MetaComic.VendingRecords = {}
local service = MetaComic.VendingRecords

local function notify(source, message, notifyType)
    if MetaComic.Framework.notify then MetaComic.Framework.notify(source, message, notifyType) end
end
local function canManage(source) return MetaComic.CanManage and MetaComic.CanManage(source) == true end
local function hasItem(source, item) return (MetaComic.Inventory.count and MetaComic.Inventory.count(source, item) or 0) > 0 end
RegisterNetEvent('meta_comic:server:vendingOSAccess', function(serial, target, allowed)
    local src = source
    local ok, err = Registry.setOSAccess(src, serial, target, allowed == true)
    notify(src, ok and 'OS operating access updated.' or err, ok and 'success' or 'error')
end)
for _, command in ipairs({ 'vendingosgrant', 'vendingosrevoke' }) do
    RegisterCommand(command, function(src, args)
        if src <= 0 then return end
        local ok, err = Registry.setOSAccess(src, args[1], args[2], command == 'vendingosgrant')
        notify(src, ok and 'OS operating access updated.' or err, ok and 'success' or 'error')
    end, false)
end

-- Read the physical identification plate without a cabinet key or access to private lock records.
RegisterNetEvent('meta_comic:server:vendingInspectSerial', function(id)
    local src = source
    if not (MetaComic.Police and MetaComic.Police.isPolice and MetaComic.Police.isPolice(src)) then return end
    local entry = Vending.get(id)
    if not entry or not Vending.near(src, entry, Vending.reach()) then return notify(src, 'Stand at the vending machine to read its serial number.', 'error') end
    if type(entry.serial) ~= 'string' or entry.serial == '' then return notify(src, 'The machine serial number is unavailable.', 'error') end
    TriggerClientEvent('meta_comic:client:vendingSerial', src, { serial = entry.serial })
end)

local function canReadKeys(source, record)
    return MetaComic.VendingKeys and (MetaComic.VendingKeys.authority(source, record)
        or MetaComic.Police and MetaComic.Police.isPolice and MetaComic.Police.isPolice(source))
end
local function keyReport(record, source)
    local view = Registry.viewFor(record, source, true)
    return { serial = record.serial, ownerName = view.ownerName, lockId = view.lockId,
        lockCondition = view.lockCondition, securitySeal = MetaComic.CopyTable(view.securitySeal),
        archive = view.keyArchive, printedAt = os.time() }
end
local function reportStore()
    if printedReports then return printedReports end
    local saved = MetaComic.Settings.get(REPORTS_KEY, {})
    printedReports = type(saved) == 'table' and saved or {}
    printedReports.reports = type(printedReports.reports) == 'table' and printedReports.reports or {}
    printedReports.nextId = tonumber(printedReports.nextId) or 0
    return printedReports
end
function service.giveKeyReport(source, serial)
    local record = Registry.get(serial)
    if not record or not (canReadKeys(source, record) or Registry.osMember(record, Registry.identifierOf(source))) then return false, 'No access to these key records.' end
    if not MetaComic.VendingKeys.ensure(record) then return false, 'Could not load the cylinder records.' end
    if printing then return false, 'The records printer is busy. Try again.' end
    printing = true
    local report = keyReport(record, source)
    local store = reportStore()
    local previousId = store.nextId
    store.nextId = previousId + 1
    local reportId = ('VKR-%s-%06d'):format(os.time(), store.nextId)
    report.reportId = reportId
    store.reports[reportId] = report
    if not MetaComic.Settings.set(REPORTS_KEY, store) then
        store.reports[reportId], store.nextId, printing = nil, previousId, false
        return false, 'Could not save the printed evidence snapshot.'
    end
    -- Keep immutable snapshots on the server: ox_inventory metadata updates must stay small.
    local metadata = { reportId = reportId, serial = serial, lockId = report.lockId, printedAt = report.printedAt,
        label = ('Key records %s'):format(serial),
        description = ('Machine %s | Report %s | Permanent archive including retired keys.'):format(serial, reportId) }
    local ok, added = pcall(MetaComic.Inventory.add, source, KEY_REPORT, 1, metadata)
    printing = false
    if not ok or not added then return false, 'Could not give the key record.' end
    return true
end
local function readKeyReport(source, serial, print)
    local record = type(serial) == 'string' and Registry.get(serial)
    if not record or not (canReadKeys(source, record) or Registry.osMember(record, Registry.identifierOf(source))) then return notify(source, 'No accessible key records for that serial.', 'error') end
    if not MetaComic.VendingKeys.ensure(record) then return end
    if print == true then
        local ok, err = service.giveKeyReport(source, serial)
        return notify(source, ok and 'Permanent key records printed, including retired cylinders and keys.' or err, ok and 'success' or 'error')
    end
    TriggerLatentClientEvent('meta_comic:client:vendingRecord', source, 128 * 1024,
        { kind = 'keyreport', printed = keyReport(record, source), business = Registry.businessName })
end
RegisterNetEvent('meta_comic:server:vendingKeyReport', function(serial, print) readKeyReport(source, serial, print) end)
if MetaComic.VendingKeys then
    RegisterCommand((cfg.Keys or {}).PoliceCommand or 'vendingkeys', function(source, args)
        if source > 0 then readKeyReport(source, args[1], args[2] == 'print') end
    end, false)
end

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

local function ledgerList(source)
    local machines, people = {}, {}
    for _, record in ipairs(Registry.all()) do
        if record.status ~= 'removed' or records.LedgerShowsRemoved then machines[#machines + 1] = Registry.viewFor(record, source) end
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
        kind = 'certificate', printed = printed, current = Registry.viewFor(record, source), business = Registry.businessName,
    })
end
local function useLedger(source, slot)
    local item = slot and MetaComic.Inventory.getSlot and MetaComic.Inventory.getSlot(source, tonumber(slot))
    if not item or item.name ~= LEDGER then return end
    local machines, people = ledgerList(source)
    TriggerLatentClientEvent('meta_comic:client:vendingRecord', source, 256 * 1024, { kind = 'ledger', machines = machines, people = people, business = Registry.businessName })
end
local function useKeyReport(source, slot)
    local item = slot and MetaComic.Inventory.getSlot and MetaComic.Inventory.getSlot(source, tonumber(slot))
    if not item or item.name ~= KEY_REPORT then return end
    -- A printed report is an immutable snapshot, readable by anyone holding the evidence item.
    local metadata = item.metadata or item.info or {}
    local report = type(metadata.reportId) == 'string' and reportStore().reports[metadata.reportId]
    if not report then return notify(source, 'The printed report snapshot is unavailable.', 'error') end
    TriggerLatentClientEvent('meta_comic:client:vendingRecord', source, 128 * 1024,
        { kind = 'keyreport', printed = MetaComic.CopyTable(report), business = Registry.businessName })
end
local function useKey(source, slot)
    local item = slot and MetaComic.Inventory.getSlot and MetaComic.Inventory.getSlot(source, tonumber(slot))
    if not MetaComic.VendingKeys or not item or item.name ~= ((cfg.Keys or {}).Item or 'vending_key') then return end
    local metadata = item.metadata or item.info or {}
    local record = Registry.get(metadata.serial)
    -- Never rewrite old key metadata when a cylinder is replaced.
    TriggerClientEvent('meta_comic:client:vendingRecord', source, { kind = 'key', printed = metadata,
        currentLockId = (Registry.viewFor(record, source) or {}).lockId, business = Registry.businessName })
end
RegisterNetEvent('meta_comic:server:useVendingKey', function(slot) useKey(source, slot) end)
RegisterNetEvent('meta_comic:server:useVendingRecord', function(kind, slot)
    if kind == 'keyreport' then useKeyReport(source, slot) elseif kind == 'ledger' then useLedger(source, slot) else useCertificate(source, slot) end
end)
if MetaComic.Framework.registerUsableItem and Config.Items.RegisterUsableItems ~= false then
    MetaComic.Framework.registerUsableItem(CERTIFICATE, function(source, item) useCertificate(source, item and item.slot) end)
    MetaComic.Framework.registerUsableItem(LEDGER, function(source, item) useLedger(source, item and item.slot) end)
    if MetaComic.VendingKeys then
        MetaComic.Framework.registerUsableItem(KEY_REPORT, function(source, item) useKeyReport(source, item and item.slot) end)
        MetaComic.Framework.registerUsableItem((cfg.Keys or {}).Item or 'vending_key', function(source, item) useKey(source, item and item.slot) end)
    end
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
-- ownerId: an owner using the portal (Config.Portal) sees only their own machines and record
local function snapshot(ownerId, source)
    local machines, people = {}, {}
    local counts = {}
    for _, record in ipairs(Registry.all()) do
        local osAccess = Registry.osMember(record, Registry.identifierOf(source))
        if ownerId and record.owner ~= ownerId and not osAccess then goto continue end
        if MetaComic.VendingKeys then MetaComic.VendingKeys.ensure(record) end
        local view = Registry.viewFor(record, source, true)
        local entry = record.status == 'placed' and Vending.bySerial(record.serial)
        if not view.remoteOffline then view.cash = entry and entry.cash or nil end
        machines[#machines + 1] = view
        if record.owner and record.status ~= 'removed' then counts[record.owner] = (counts[record.owner] or 0) + 1 end
        ::continue::
    end
    for _, person in ipairs(Registry.people()) do
        if not ownerId or person.id == ownerId then
            people[#people + 1] = { id = person.id, name = person.name, routing = person.routing, tax = person.tax, registeredAt = person.registeredAt,
                machines = counts[person.id] or 0, pending = Registry.pending(person.id) }
        end
    end
    return {
        ok = true, machines = machines, people = people, online = ownerId and {} or onlinePlayers(), business = Registry.businessName,
        scope = ownerId and (Registry.hasOSAccess(source) and 'os' or 'owner') or 'manager',
        businessRouting = Registry.businessRouting(), businessPending = not ownerId and Registry.businessPending() or 0,
        defaultTax = tonumber((cfg.Ownership or {}).DefaultTax) or 10,
        keysEnabled = MetaComic.VendingKeys ~= nil,
    }
end

if MetaComic.RpcHandlers then
    local function ownerScope(source)
        if canManage(source) then return false end
        if Registry.hasOSAccess(source) then return Registry.identifierOf(source) end
        return MetaComic.Portal and MetaComic.Portal.ownerScope(source, 'records') or nil
    end
    MetaComic.RpcHandlers.getVendingRecords = function(source)
        local ownerId = ownerScope(source)
        if ownerId == nil then return { ok = false, error = 'You are not allowed to see the machine records.' } end
        return snapshot(ownerId or nil, source)
    end
    -- payload.action: 'register' { serverId | id, name, tax } | 'tax' { id, tax } (or { taxes = { [id] = rate } })
    --   | 'unregister' { id } | 'assign' { serial, owner } | 'resetRouting' { serial } | 'withdraw' { amount }
    --   | 'certificate' { serial } | 'ledger'
    MetaComic.RpcHandlers.saveVendingRecords = function(source, payload)
        if type(payload) ~= 'table' then return { ok = false, error = 'Invalid record action.' } end
        if payload.action == 'osAccess' then
            local ok, err = Registry.setOSAccess(source, payload.serial, payload.serverId, payload.allowed == true)
            if not ok then return { ok = false, error = err } end
            return snapshot(not canManage(source) and Registry.identifierOf(source) or nil, source)
        end
        local ownerId = ownerScope(source)
        if ownerId == nil then return { ok = false, error = 'You are not allowed to change the machine records.' } end
        if ownerId then -- owners may only print papers for their own machines
            local record = Registry.get(payload.serial)
            if payload.action == 'keyReport' and Registry.osMember(record, Registry.identifierOf(source)) then
                local ok, err = service.giveKeyReport(source, payload.serial)
                if not ok then return { ok = false, error = err } end
                return snapshot(ownerId, source)
            end
            if (payload.action ~= 'certificate' and payload.action ~= 'keyReport') or not record or record.owner ~= ownerId then
                return { ok = false, error = 'Only the business can do that.' }
            end
        end
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
            ok, err = Registry.resetRouting(payload.serial, by)
            if ok then Vending.sendAccessAll() end
        elseif action == 'withdraw' then
            ok, err = Registry.withdrawBusiness(source, payload.amount)
        elseif action == 'certificate' then
            ok = service.giveCertificate(source, payload.serial) == true
            err = not ok and 'Could not give the certificate.' or nil
        elseif action == 'issueKey' then
            if not MetaComic.VendingKeys then return { ok = false, error = 'Physical keys are disabled.' } end
            ok, err = MetaComic.VendingKeys.issue(source, payload.serial, payload.serverId, payload.access)
        elseif action == 'keyReport' then
            ok, err = service.giveKeyReport(source, payload.serial)
        elseif action == 'ledger' then
            ok = MetaComic.Inventory.add(source, LEDGER, 1, { label = ('%s machine ledger'):format(Registry.businessName), description = 'Registered vending machine owners and serial numbers.' }) == true
            err = not ok and 'Could not give the ledger.' or nil
        else
            return { ok = false, error = 'Unknown action.' }
        end
        if not ok then return { ok = false, error = err or 'Could not save the records.' } end
        return snapshot(ownerId or nil, source)
    end
end
