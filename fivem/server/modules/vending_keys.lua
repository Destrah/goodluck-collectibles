-- Physical keys are inventory items, not ownership. The permanent archive is never subject to HistoryLength.
local cfg = Config.VendingMachines or {}
local keys = cfg.Keys or {}
if cfg.Enabled == false or keys.Enabled ~= true then return end
local Registry, Vending = MetaComic.VendingRegistry, MetaComic.Vending
local service, sessions, pending, locks = {}, {}, {}, {}
local repairing = {}
MetaComic.VendingKeys = service
local ITEM = keys.Item or 'vending_key'
local function notify(src, message, kind) if MetaComic.Framework.notify then MetaComic.Framework.notify(src, message, kind or 'error') end end
local function restore(record, old)
    for k in pairs(record) do record[k] = nil end
    for k, v in pairs(old) do record[k] = v end
end
local function persist(record, old)
    if Registry.save() then return true end
    restore(record, old)
    return false
end
function service.ensure(record)
    if not record then return false end
    if record.systemController and not Registry.ensureOS(record) then return false end
    if record.keyArchive then
        -- Never recreate an archive over existing evidence, even if a save is malformed.
        if type(record.keyArchive) ~= 'table' or type(record.keyArchive.cylinders) ~= 'table' or type(record.keyArchive.keys) ~= 'table' then return false end
        local cylinder = record.keyArchive.cylinders[#record.keyArchive.cylinders]
        return type(record.lockId) == 'string' and type(cylinder) == 'table' and cylinder.id == record.lockId and type(cylinder.generation) == 'number'
    end
    if locks[record.serial] then return false end
    locks[record.serial] = true
    local old = MetaComic.CopyTable(record)
    record.keyArchive = { cylinders = { { id = record.serial .. '-C0001', generation = 1, installedAt = os.time(), installedBy = 'Initial registration' } }, keys = {} }
    record.lockId, record.lockCondition, record.lockRevision = record.serial .. '-C0001', record.unlockedUntil and 'damaged' or 'intact', 0
    local ok = persist(record, old)
    locks[record.serial] = nil
    return ok
end
function service.authority(src, record)
    return record ~= nil and (Vending.canManage(src) or record.owner == Registry.identifierOf(src))
end
function service.canRegister(src, record)
    local entry = record and Vending.bySerial(record.serial)
    return service.authority(src, record) or Registry.osMember(record, Registry.identifierOf(src))
        or entry and Vending.businessStaff and Vending.businessStaff(src, entry) == true
end
-- Physical possession is recorded by the server when a stolen inventory machine is installed.
-- It permits fitting a cylinder, without transferring ownership, payment routing or general key issuance.
function service.canReplace(src, record)
    local id = Registry.identifierOf(src)
    return service.canRegister(src, record) or record ~= nil and id ~= nil and (
        record.lockInstallerId == id
        or record.stolenAt and record.installedById == id
        or record.lockCondition == 'damaged' and not record.securitySeal
            and (record.displacedOpen == true or (tonumber(record.unlockedUntil) or 0) > os.time()))
end
function service.busy(entry) return entry and ((MetaComic.VendingCashbox and MetaComic.VendingCashbox.closing and MetaComic.VendingCashbox.closing(entry.id)) or locks[entry.serial] == true or service.replacing(entry) or service.repairing(entry)) end
function service.repairing(entry)
    for _, job in pairs(repairing) do
        if job.serial == entry.serial and GetGameTimer() - job.at < job.duration + 30000 then return true end
    end
    return false
end
function service.replacing(entry)
    for _, job in pairs(pending) do if job.serial == entry.serial then return true end end
    return false
end
local function archivedKey(record, metadata)
    if type(metadata) ~= 'table' or metadata.serial ~= record.serial or metadata.lockId ~= record.lockId then return end
    for _, key in ipairs(record.keyArchive.keys) do
        if not key.deliveryFailed and key.id == metadata.keyId and key.lockId == metadata.lockId and key.access == metadata.access then return key end
    end
end
local function findKey(src, record, required, keyId)
    for _, item in pairs(MetaComic.Inventory.slotsOf and MetaComic.Inventory.slotsOf(src, ITEM) or {}) do
        if item.name == ITEM and (tonumber(item.count or item.amount) or 0) > 0 then
            local key = archivedKey(record, item.metadata or item.info)
            if key and (not keyId or key.id == keyId) and (required ~= 'full' or key.access == 'full') then return key end
        end
    end
end
function service.canUnseal(src, record)
    return record ~= nil and (service.canRegister(src, record) or findKey(src, record, 'service') ~= nil)
end
function service.cabinetOpen(entry, src)
    if not entry then return false end
    local box = MetaComic.VendingCashbox
    if box then return box.cabinetOpen(entry.id) end
    return MetaComic.VendingLoot and MetaComic.VendingLoot.isOpen(entry) or src ~= nil and service.access(src, entry, 'service')
end
function service.replacementReady(src, entry, record)
    return record ~= nil and not record.securitySeal and not record.padlock and service.cabinetOpen(entry, src)
        and (service.canReplace(src, record) or record.lockCondition == 'damaged' and service.canUnseal(src, record))
end
function service.unseal(src, entry)
    local record = entry and Registry.get(entry.serial)
    if not record or not Vending.near(src, entry, Vending.reach()) or not service.ensure(record)
        or not record.securitySeal or not service.canUnseal(src, record) or service.busy(entry)
        or Vending.isTransferringStock(entry) then return false end
    locks[entry.serial] = true
    local old = MetaComic.CopyTable(record)
    record.securitySeal = nil
    local loot = ((cfg.Crime or {}).BreakIn or {}).Loot or {}
    record.unlockedUntil = os.time() + math.max(10, tonumber(loot.UnlockSeconds) or 600)
    service.invalidate(record)
    local ok = persist(record, old)
    locks[entry.serial] = nil
    if ok then Vending.broadcast(entry) end
    return ok
end
local function validSession(src, entry, required)
    if not entry then return false end
    local ped = GetPlayerPed(src)
    if ped == 0 or GetEntityHealth and GetEntityHealth(ped) <= 100 then return false end
    local record = entry and Registry.get(entry.serial)
    local session = sessions[src] and sessions[src][entry.serial]
    -- a damaged / sealed cylinder still turns for its current keys: after a break-in is secured the key holders keep
    -- running the machine until the cylinder is replaced (sealing bumps lockRevision, so they unlock once more)
    if not record or record.padlock or not record.keyArchive or not session
        or session.revision ~= record.lockRevision or session.untilAt <= os.time() then return false end
    return findKey(src, record, required, session.keyId) ~= nil
end
function service.access(src, entry, required, moving)
    return validSession(src, entry, required)
        and Vending.near(src, entry, moving and (tonumber(cfg.PlaceDistance) or 15) + 10 or Vending.reach())
end
function service.invalidate(record)
    record.lockRevision = (record.lockRevision or 0) + 1
end
local function sendSession(src, entry, record, session)
    TriggerClientEvent('meta_comic:client:vendingKeyAccess', src, {
        id = entry.id, serial = entry.serial, revision = record.lockRevision,
        seconds = math.max(0, session.untilAt - os.time()), full = findKey(src, record, 'full', session.keyId) ~= nil,
    })
end
-- The optional external padlock is separate from the recovery chain/security seal.
local padlock = keys.Padlock or {}
local PADLOCK_ITEM = padlock.Item or 'vending_padlock'
local function padlockEvent(record, event, src)
    -- Append forensic history in the same save as the item/state transaction.
    local field = record.systemController and 'osHistory' or 'history'
    record[field] = type(record[field]) == 'table' and record[field] or {}
    table.insert(record[field], 1, { at = os.time(), event = event, by = Registry.nameOf(src) })
    local limit = math.max(1, math.min(5000, math.floor(tonumber((cfg.Records or {}).HistoryLimit) or tonumber((cfg.Ownership or {}).HistoryLength) or 25)))
    while #record[field] > limit do table.remove(record[field]) end
    record.updatedAt = os.time()
end
local function padlockReady(src, entry, record)
    return padlock.Enabled ~= false and record and record.lockCondition == 'intact' and not record.securitySeal
        and not record.padlock and not record.padlockReturn and not service.cabinetOpen(entry, src)
        and findKey(src, record, 'service') ~= nil
end
local function returnPadlock(src, entry, record)
    local due = record.padlockReturn
    if not due or due.recipient ~= Registry.identifierOf(src) then return false end
    -- A failed receipt save must not let a repeated request deliver another item.
    local delivered = due.delivered == true
    for _, item in pairs(MetaComic.Inventory.slotsOf(src, PADLOCK_ITEM) or {}) do
        local metadata = item.metadata or item.info or {}
        if metadata.padlockId == due.id then delivered = true end
    end
    if not delivered then
        if MetaComic.Inventory.canCarry and not MetaComic.Inventory.canCarry(src, PADLOCK_ITEM, 1) then
            notify(src, 'Make room in your inventory to collect the padlock.'); return false
        end
        if not MetaComic.Inventory.add(src, PADLOCK_ITEM, 1, { padlockId = due.id }) then
            notify(src, 'The padlock is removed. Collect it from Cabinet lock and keys when your inventory is available.'); return false
        end
        due.delivered = true
    end
    record.padlockReturn = nil
    if not Registry.save() then record.padlockReturn = due end
    return true
end
function service.removePadlock(src, entry, picked)
    local record = entry and Registry.get(entry.serial)
    if not record or not record.padlock or not service.ensure(record) or service.busy(entry)
        or not Vending.near(src, entry, Vending.reach()) or Vending.isTransferringStock(entry)
        or not picked and not findKey(src, record, 'service') then return false end
    if MetaComic.Inventory.canCarry and not MetaComic.Inventory.canCarry(src, PADLOCK_ITEM, 1) then
        notify(src, 'Make room in your inventory before removing the padlock.'); return false
    end
    locks[entry.serial] = true
    local old = MetaComic.CopyTable(record)
    record.padlockReturn = { id = record.padlock.id, recipient = Registry.identifierOf(src) }
    record.padlock = nil
    service.invalidate(record)
    padlockEvent(record, picked and 'External padlock lockpicked' or 'External padlock removed with key', src)
    local ok = persist(record, old)
    if ok then
        returnPadlock(src, entry, record)
        Vending.broadcast(entry)
        notify(src, 'Padlock removed. The cabinet cylinder is still locked.', 'success')
    end
    locks[entry.serial] = nil
    TriggerClientEvent('meta_comic:client:vendingMenuRefresh',src,entry.id)
    return ok
end
RegisterNetEvent('meta_comic:server:vendingPadlock', function(id, action)
    local src, entry = source, Vending.get(id)
    local record = entry and Registry.get(entry.serial)
    if not record or not Vending.near(src, entry, Vending.reach()) then return notify(src, 'Stand at the vending machine first.') end
    if not service.ensure(record) or service.busy(entry) then return notify(src, 'The machine is busy or its lock is unavailable.') end
    if action == 'remove' then
        if not record.padlock then return notify(src, 'There is no cabinet padlock to remove.') end
        if not findKey(src, record, 'service') then return notify(src, 'You need a current matching key to remove the padlock.') end
        return service.removePadlock(src, entry, false)
    end
    if action == 'collect' then
        locks[entry.serial] = true
        returnPadlock(src, entry, record)
        locks[entry.serial] = nil
        return
    end
    if action ~= 'install' or not padlockReady(src, entry, record) or Vending.isTransferringStock(entry)
        or MetaComic.VendingLoot and MetaComic.VendingLoot.busy(entry) then return notify(src, 'Padlock installation requires a closed, intact cabinet, a matching current key and no active machine operation.') end
    locks[entry.serial] = true
    if not MetaComic.Inventory.remove(src, PADLOCK_ITEM, 1) then
        locks[entry.serial] = nil; return notify(src, 'You need a vending padlock.')
    end
    if not padlockReady(src, entry, record) then
        MetaComic.Inventory.add(src, PADLOCK_ITEM, 1)
        locks[entry.serial] = nil; return notify(src, 'The cabinet changed. Padlock installation stopped.')
    end
    local old = MetaComic.CopyTable(record)
    record.padlock = { id = ('%s:%s:%s'):format(record.serial, os.time(), record.lockRevision), lockId = record.lockId }
    record.unlockedUntil, record.unlockedBy, record.displacedOpen = nil, nil, nil
    service.invalidate(record)
    padlockEvent(record, 'External padlock installed', src)
    local ok = persist(record, old)
    if not ok then MetaComic.Inventory.add(src, PADLOCK_ITEM, 1) end
    locks[entry.serial] = nil
    TriggerClientEvent('meta_comic:client:vendingMenuRefresh',src,entry.id)
    if ok then Vending.broadcast(entry); notify(src, 'Padlock installed.', 'success')
    else notify(src, 'Could not save the padlock. Your item was returned.') end
end)
-- kind: who chained it ('police', 'owner', 'business'; 'automatic' for the security timer, nil for anyone else)
function service.sealFields(record, by, kind)
    return { unlockedUntil = false, unlockedBy = false, displacedOpen = false, lockCondition = 'damaged',
        lockRevision = (record.lockRevision or 0) + 1,
        securitySeal = { at = os.time(), by = by or 'Automatic security timer', kind = kind or (not by and 'automatic' or nil),
            label = (keys.Seal or {}).Label or 'Chain and padlock' } }
end
local SEALED_BY = { police = ' by the police', owner = ' by its owner', business = ' by the business' }
-- what players see while a machine is chained shut (key unlock, restock, manage)
function service.sealText(record)
    local seal = record and record.securitySeal
    if not seal then return nil end
    return ('This machine is secured with a chain and padlock%s. Repair or replace the lock cylinder to remove it.'):format(SEALED_BY[seal.kind] or '')
end
local function issue(src, serial, target, access, replacement)
    local record = Registry.get(serial)
    target = tonumber(target)
    if not Vending.canManage(src) and not Registry.osMember(record, Registry.identifierOf(src)) and not (replacement and target == src) then return false, 'Only the business or authorized OS operators can issue keys.' end
    if not target or target ~= math.floor(target) or not GetPlayerName(target) then return false, 'Choose an online recipient.' end
    if access ~= 'full' and access ~= 'service' then return false, 'Choose full or service access.' end
    if not service.ensure(record) then return false, 'Could not initialize the lock record.' end
    if locks[serial] or service.replacing({ serial = serial }) then return false, 'The lock is being serviced.' end
    if record.lockCondition ~= 'intact' or record.securitySeal then return false, 'Repair or replace the damaged cylinder before issuing keys.' end
    if replacement then
        local due = record.replacementKeyDue
        if target ~= src or access ~= 'full' or type(due) ~= 'table' or due.lockId ~= record.lockId
            or due.recipient ~= Registry.identifierOf(src) then return false, 'No included key is waiting for you.' end
    elseif not service.canIssue(src, record) then
        return false, 'You need a working full-access key matching the current cylinder before duplicating keys.'
    end
    locks[serial] = true
    local old = MetaComic.CopyTable(record)
    local key = { id = ('%s-K%06d'):format(serial, #record.keyArchive.keys + 1), lockId = record.lockId, access = access,
        issuedAt = os.time(), issuedTo = Registry.identifierOf(target), issuedToName = Registry.nameOf(target),
        issuedBy = Registry.identifierOf(src), issuedByName = Registry.nameOf(src), replacement = replacement == true or nil }
    record.keyArchive.keys[#record.keyArchive.keys + 1] = key
    if record.registeredKeyArchive and record.registeredLockId == record.lockId then
        record.registeredKeyArchive.keys[#record.registeredKeyArchive.keys + 1] = MetaComic.CopyTable(key)
    end
    local metadata = { serial = serial, lockId = key.lockId, keyId = key.id, access = access,
        label = ('Vending key %s (%s)'):format(serial, access),
        description = ('Machine: %s | Cylinder: %s | Key: %s | Access: %s'):format(serial, key.lockId, key.id, access) }
    local ok = persist(record, old)
    local added, result = false, false
    -- Persistence may yield; losing the source key during that save must not produce a copy.
    if ok and (replacement or service.canIssue(src, record)) then added, result = pcall(MetaComic.Inventory.add, target, ITEM, 1, metadata) end
    if ok and (not added or not result) then
        -- Keep the number reserved, recording the failed delivery rather than reusing an evidence identifier.
        key.deliveryFailed = true
        for _, registered in ipairs(record.registeredKeyArchive and record.registeredKeyArchive.keys or {}) do
            if registered.id == key.id then registered.deliveryFailed = true end
        end
        Registry.save()
        ok = false
    end
    locks[serial] = nil
    if not ok then return false, 'Could not save or deliver the key.' end
    notify(target, ('Received %s key for %s.'):format(access, serial), 'success')
    return true
end
function service.canIssue(src, record)
    return (Vending.canManage(src) or Registry.osMember(record, Registry.identifierOf(src))) and record ~= nil and record.lockCondition == 'intact'
        and not record.securitySeal and findKey(src, record, 'full') ~= nil
end
function service.issue(src, serial, target, access) return issue(src, serial, target, access, false) end
local function replacementKeyDue(src, record)
    local due = record and record.replacementKeyDue
    return type(due) == 'table' and due.lockId == record.lockId and due.recipient == Registry.identifierOf(src)
end
local function deliverReplacementKey(src, record)
    if not replacementKeyDue(src, record) then return false, 'No replacement key is waiting for you.' end
    if service.busy({ serial = record.serial }) then return false, 'The lock is being serviced.' end
    -- A failed marker-clear save must not duplicate an already delivered physical key.
    for _, key in ipairs(record.keyArchive.keys) do
        if key.replacement and not key.deliveryFailed and key.lockId == record.lockId and key.issuedTo == Registry.identifierOf(src) then
            record.replacementKeyDue = nil
            Registry.save()
            return true
        end
    end
    local ok, err = issue(src, record.serial, src, 'full', true)
    if ok then record.replacementKeyDue = nil; Registry.save() end
    return ok, err
end
-- Called only by the verified installation flow. Never bootstrap a replacement or a stolen machine.
function service.initialKey(src, record)
    if not record or not service.ensure(record) or record.status ~= 'placed' or record.installedById ~= Registry.identifierOf(src)
        or record.stolenAt or record.systemController or record.lockCondition ~= 'intact' or record.securitySeal or record.registeredKeyArchive
        or #record.keyArchive.cylinders ~= 1 or record.keyArchive.cylinders[1].generation ~= 1 then return false end
    if record.replacementKeyDue then return deliverReplacementKey(src, record) end
    if #record.keyArchive.keys ~= 0 or service.busy({ serial = record.serial }) then return false end
    local old = MetaComic.CopyTable(record)
    record.replacementKeyDue = { lockId = record.lockId, recipient = Registry.identifierOf(src) }
    if not persist(record, old) then return false end
    local ok, err = deliverReplacementKey(src, record)
    notify(src, ok and 'Received the new machine\'s included full-access key.'
        or ('Machine installed. ' .. err .. ' Use Collect replacement key to retry its included key.'), ok and 'success' or 'error')
    return ok
end
RegisterNetEvent('meta_comic:server:vendingReplacementKey', function(id)
    local src, entry = source, Vending.get(id)
    if not entry or not Vending.near(src, entry, Vending.reach()) then return end
    local record = Registry.get(entry.serial)
    if not service.ensure(record) then return end
    local ok, err = deliverReplacementKey(src, record)
    notify(src, ok and 'Replacement full-access key delivered.' or err, ok and 'success' or 'error')
end)
function service.unlock(src, entry, slot, mode)
    local record = entry and Registry.get(entry.serial)
    if not entry or not Vending.near(src, entry, Vending.reach()) then return notify(src, 'Stand at the machine.') end
    if not service.ensure(record) or service.busy(entry) then return notify(src, 'The lock is unavailable or being serviced.') end
    -- Damage invalidates sessions, not the current numbered keys. A recovered key can authenticate
    -- interior access while the damaged cabinet remains physically unsecured.
    if record.lockCondition ~= 'damaged' and MetaComic.VendingLoot and MetaComic.VendingLoot.isOpen(entry) then return notify(src, 'Secure and repair the broken-in cabinet first.') end
    if record.securitySeal then return notify(src, service.sealText(record)) end -- chained shut: the key can't reach the cabinet
    if record.padlock then return notify(src, 'Unlock and remove the padlock first.') end
    local key
    if slot then
        local item = MetaComic.Inventory.getSlot(src, tonumber(slot))
        if item and item.name == ITEM and (tonumber(item.count or item.amount) or 0) > 0 then key = archivedKey(record, item.metadata or item.info) end
    else key = findKey(src, record, 'full') or findKey(src, record, 'service') end
    if not key then return notify(src, 'You need a matching current key. Retired keys cannot unlock this cylinder.') end
    sessions[src] = sessions[src] or {}
    sessions[src][entry.serial] = { keyId = key.id, revision = record.lockRevision, untilAt = os.time() + math.max(10, tonumber(keys.SessionSeconds) or 300) }
    sendSession(src, entry, record, sessions[src][entry.serial])
    TriggerClientEvent('meta_comic:client:vendingKeyUnlocked', src, { id = entry.id, open = not service.cabinetOpen(entry, src) })
    notify(src, ('Cabinet unlocked (%s access).'):format(key.access), 'success')
    if record.securitySeal or record.lockCondition ~= 'intact' then notify(src, 'The lock is still damaged. Repair or replace the cylinder to make the machine secure again.', 'info') end
    TriggerEvent('meta_comic:server:vendingKeyUnlockSuccess', src, entry.id, mode)
    Vending.openManage(src, entry)
end
RegisterNetEvent('meta_comic:server:vendingKeyUnlock', function(id, mode) service.unlock(source, Vending.get(id), nil, mode) end)
RegisterNetEvent('meta_comic:server:vendingIssueKey', function(serial, target, access)
    local src = source -- saving can yield, and `source` is gone after a yield
    local ok, err = service.issue(src, serial, target, access)
    notify(src, ok and 'Numbered key issued and permanently recorded.' or err, ok and 'success' or 'error')
end)
-- Repairing a damaged cylinder (Config.VendingMachines.Keys.Repair) keeps it and every key cut for it: it uses up the
-- configured items with the cabinet already open. Replacing the cylinder (further down) retires the old keys instead.
local repair = keys.Repair or {}
local function repairItems()
    local list = {}
    for _, item in ipairs(repair.Items or {}) do
        if type(item) == 'table' then
            list[#list + 1] = { item = item.item, label = item.label or item.item, count = math.max(1, math.floor(tonumber(item.count) or 1)) }
        else
            list[#list + 1] = { item = item, label = item, count = 1 }
        end
    end
    return list
end
local function repairLabel()
    local parts = {}
    for _, item in ipairs(repairItems()) do parts[#parts + 1] = ('%dx %s'):format(item.count, item.label) end
    return #parts > 0 and table.concat(parts, ', ') or 'nothing'
end
local function missingRepairItem(src)
    for _, item in ipairs(repairItems()) do
        if (MetaComic.Inventory.count(src, item.item) or 0) < item.count then return item end
    end
end
local function canRepair(src, record)
    return repair.Enabled ~= false and record ~= nil and service.canRegister(src, record) and (record.lockCondition ~= 'intact' or record.securitySeal ~= nil)
end
RegisterNetEvent('meta_comic:server:vendingRepairStart', function(id)
    local src, entry = source, Vending.get(id)
    local record = entry and Registry.get(entry.serial)
    local busyJob = repairing[src]
    if busyJob and GetGameTimer() - busyJob.at < busyJob.duration + 30000 or pending[src] then return notify(src, 'Finish or cancel your current cylinder work first.') end
    if not entry or not Vending.near(src, entry, Vending.reach()) then return notify(src, 'Stand at the vending machine first.') end
    if not canRepair(src, record) then return notify(src, 'Cylinder repair requires a damaged lock and maintenance authority.') end
    if record.padlock or record.securitySeal or not service.cabinetOpen(entry, src) then return notify(src, 'Open the cabinet before repairing its cylinder.') end
    if not service.ensure(record) or service.busy(entry) or Vending.isTransferringStock(entry)
        or MetaComic.VendingLoot and MetaComic.VendingLoot.busy(entry) then return notify(src, 'The machine is busy.') end
    local missing = missingRepairItem(src)
    if missing then return notify(src, ('You need %dx %s to repair the cylinder.'):format(missing.count, missing.label)) end
    local duration = math.max(1000, tonumber(repair.Duration) or 30000)
    if MetaComic.VendingProgressDuration then duration = MetaComic.VendingProgressDuration(duration) end
    local token = ('%s:%s:%s:repair'):format(src, GetGameTimer(), record.lockRevision)
    repairing[src] = { id = entry.id, serial = entry.serial, revision = record.lockRevision, token = token, at = GetGameTimer(), duration = duration }
    TriggerClientEvent('meta_comic:client:vendingRepairStart', src, { token = token, duration = duration })
end)
RegisterNetEvent('meta_comic:server:vendingRepairCancel', function() repairing[source] = nil end)
RegisterNetEvent('meta_comic:server:vendingRepairFinish', function(token)
    local src, job = source, repairing[source]
    repairing[src] = nil
    if not job or job.token ~= token or GetGameTimer() - job.at < job.duration * 0.9 then return end
    local entry, record = Vending.get(job.id), Registry.get(job.serial)
    if not entry or entry.serial ~= job.serial or not canRepair(src, record) or not Vending.near(src, entry, Vending.reach())
        or record.padlock or record.securitySeal or not service.cabinetOpen(entry, src)
        or record.lockRevision ~= job.revision or service.busy(entry) or Vending.isTransferringStock(entry)
        or MetaComic.VendingLoot and MetaComic.VendingLoot.busy(entry) then return notify(src, 'The machine changed or became busy. Repair stopped.') end
    locks[job.serial] = true
    local taken = {}
    local function giveBack() for _, item in ipairs(taken) do MetaComic.Inventory.add(src, item.item, item.count) end end
    for _, item in ipairs(repairItems()) do
        if (MetaComic.Inventory.count(src, item.item) or 0) < item.count or not MetaComic.Inventory.remove(src, item.item, item.count) then
            giveBack()
            locks[job.serial] = nil
            return notify(src, ('You need %dx %s to repair the cylinder.'):format(item.count, item.label))
        end
        taken[#taken + 1] = item
    end
    local old = MetaComic.CopyTable(record)
    local cylinder = record.keyArchive.cylinders[#record.keyArchive.cylinders]
    cylinder.repairs = type(cylinder.repairs) == 'table' and cylinder.repairs or {}
    cylinder.repairs[#cylinder.repairs + 1] = { at = os.time(), by = Registry.nameOf(src), byId = Registry.identifierOf(src) }
    -- Same cylinder and keys. Other sessions expire; the repairing key holder keeps cabinet access.
    Registry.update(record.serial, { lockCondition = 'intact', securitySeal = false, unlockedUntil = false, unlockedBy = false, displacedOpen = false,
        lockRevision = (record.lockRevision or 0) + 1 }, 'Lock cylinder repaired', Registry.nameOf(src))
    local ok = persist(record, old)
    if not ok then giveBack() end
    locks[job.serial] = nil
    if not ok then return notify(src, 'Could not save the repair. Your items were returned.') end
    local session = sessions[src] and sessions[src][entry.serial]
    if session and findKey(src, record, 'service', session.keyId) then
        session.revision = record.lockRevision
        sendSession(src, entry, record, session)
    end
    entry.openedBy = nil
    Vending.broadcast(entry)
    notify(src, 'Lock cylinder repaired. The existing keys still work.', 'success')
    TriggerClientEvent('meta_comic:client:vendingMenuRefresh',src,entry.id)
end)
AddEventHandler('playerDropped', function() repairing[source] = nil end)

local function keyMenu(src, id, attempts)
    local entry = Vending.get(id)
    if not entry or not Vending.near(src, entry, Vending.reach()) then return end
    local record = Registry.get(entry.serial)
    if not service.ensure(record) then return end
    if service.busy(entry) and (attempts or 0)<600 then
        SetTimeout(100,function() keyMenu(src,id,(attempts or 0)+1) end)
        return
    end
    local police = MetaComic.Police and MetaComic.Police.isPolice and MetaComic.Police.isPolice(src)
    local box = MetaComic.VendingCashbox
    local session = service.access(src, entry, 'service')
    TriggerClientEvent('meta_comic:client:vendingKeyMenu', src, {
        -- open / close the machine and its cash box separately (server/modules/vending_door.lua)
        hasFull = findKey(src, record, 'full') ~= nil, session = session, fullSession = session and service.access(src, entry, 'full'),
        cabinetOpen = service.cabinetOpen(entry, src), boxOpen = box ~= nil and box.isOpen(entry.id),
        padlock = record.padlock ~= nil, hasKey = findKey(src, record, 'service') ~= nil,
        canPadlock = padlockReady(src, entry, record), hasPadlockItem = (MetaComic.Inventory.count(src, PADLOCK_ITEM) or 0) > 0,
        padlockReturn = record.padlockReturn and record.padlockReturn.recipient == Registry.identifierOf(src) or false,
        busy = service.busy(entry) or Vending.isTransferringStock(entry), looting = MetaComic.VendingLoot and MetaComic.VendingLoot.busy(entry) or false,
        repairMissing = missingRepairItem(src), hasCylinder = (MetaComic.Inventory.count(src, keys.CylinderItem or 'vending_lock_cylinder') or 0) > 0,
        boxEnabled = box ~= nil and box.keyBox == true,
        rackOpen = box ~= nil and box.rackOpen ~= nil and box.rackOpen(entry.id), rackEnabled = box ~= nil and box.keyRack == true,
        id = entry.id, serial = entry.serial, lockId = record.lockId, condition = record.lockCondition, sealed = record.securitySeal ~= nil,
        canReplace = service.replacementReady(src, entry, record), canIssue = service.canIssue(src, record), replacementKeyDue = replacementKeyDue(src, record),
        canUnseal = record.securitySeal ~= nil and service.canUnseal(src, record), damagedUnsealed = record.lockCondition == 'damaged' and not record.securitySeal,
        sealText = service.sealText(record), canRepair = canRepair(src, record) and not record.securitySeal and not record.padlock and service.cabinetOpen(entry, src), repairItems = repairLabel(),
        canRead = police or service.authority(src, record) or Registry.osMember(record, Registry.identifierOf(src)),
    })
end
RegisterNetEvent('meta_comic:server:vendingKeyMenu',function(id) keyMenu(source,id) end)
-- Shut the physical door before the key-turn pose; the final lock still validates and saves separately.
RegisterNetEvent('meta_comic:server:vendingKeyCloseForLock', function(id, kind)
    local src, entry = source, Vending.get(id)
    if not service.access(src, entry, 'service') then return notify(src, 'Authenticate a current cabinet key before closing and locking the machine.') end
    if MetaComic.VendingLoot and MetaComic.VendingLoot.busy(entry) then
        return notify(src, 'You cannot close the main door while someone is looting this machine.', 'error')
    end
    if service.busy(entry) or Vending.isTransferringStock(entry) then return notify(src, 'The machine is busy. Wait for its current action to finish.') end
    if kind=='cashbox' or kind=='rack' then
        if not service.access(src,entry,'full') then return notify(src,'Full-access key required.') end
    elseif kind~=nil and kind~='cylinder' then return end
    if MetaComic.VendingCashbox and MetaComic.VendingCashbox.beginKeyClose then MetaComic.VendingCashbox.beginKeyClose(src,entry,kind) end
end)
function service.lockCabinet(src, entry)
    if not service.access(src, entry, 'service') then return notify(src, 'Authenticate a current cabinet key before closing and locking the machine.') end
    if MetaComic.VendingLoot and MetaComic.VendingLoot.busy(entry) then
        return notify(src, 'You cannot close the main door while someone is looting this machine.', 'error')
    end
    if service.busy(entry) or Vending.isTransferringStock(entry) then return notify(src, 'The machine is busy. Wait for its current action to finish.') end
    local record = Registry.get(entry.serial)
    if locks[entry.serial] then return end
    locks[entry.serial] = true
    local old = MetaComic.CopyTable(record)
    service.invalidate(record)
    local ok = persist(record, old)
    locks[entry.serial] = nil
    if ok then
        TriggerEvent('meta_comic:server:vendingKeyLockSuccess', src, entry.id)
        Vending.broadcast(entry)
        notify(src, 'Cabinet locked. All cabinet sessions closed.', 'success')
    end
    TriggerClientEvent('meta_comic:client:vendingMenuRefresh',src,entry.id)
    return ok
end
RegisterNetEvent('meta_comic:server:vendingKeyLock',function(id) return service.lockCabinet(source,Vending.get(id)) end)

-- Lost/stolen keys and broken locks use the same verified physical replacement service.
RegisterNetEvent('meta_comic:server:vendingRekeyStart', function(id)
    local src, entry = source, Vending.get(id)
    local record = entry and Registry.get(entry.serial)
    if pending[src] or not entry or not Vending.near(src, entry, Vending.reach()) then return end
    if not service.replacementReady(src, entry, record) then return notify(src, 'Open the cabinet before replacing its cylinder.') end
    if not service.ensure(record) or service.busy(entry) or Vending.isTransferringStock(entry)
        or MetaComic.VendingLoot and MetaComic.VendingLoot.busy(entry) then return notify(src, 'The machine is busy.') end
    local item = keys.CylinderItem or 'vending_lock_cylinder'
    if (MetaComic.Inventory.count(src, item) or 0) < 1 then return notify(src, 'You need a replacement lock cylinder.') end
    local forced = not service.canRegister(src, record)
    local duration = math.max(1000, tonumber(keys.ReplaceDuration) or 60000)
    if forced then duration = math.max(duration, tonumber(keys.ForcedReplaceDuration) or 180000) end
    if MetaComic.VendingProgressDuration then duration = MetaComic.VendingProgressDuration(duration) end
    local token = ('%s:%s:%s'):format(src, GetGameTimer(), record.lockRevision)
    pending[src] = { id = entry.id, serial = entry.serial, revision = record.lockRevision, token = token, at = GetGameTimer(), duration = duration,
        forced = forced, openAccess = record.lockCondition == 'damaged' and not record.securitySeal }
    TriggerClientEvent('meta_comic:client:vendingRekeyStart', src, { id = entry.id, token = token, duration = duration,
        minigame = forced and (keys.ForcedReplaceMinigame or { 'lockpick_hard', 'skimmer_hard' }) or nil })
    TriggerEvent('meta_comic:server:vendingDoorSuccess', src, entry.id, 'rekey')
end)
RegisterNetEvent('meta_comic:server:vendingRekeyCancel', function() pending[source] = nil end)
RegisterNetEvent('meta_comic:server:vendingRekeyFinish', function(token)
    local src, job = source, pending[source]
    pending[src] = nil
    if not job or job.token ~= token or GetGameTimer() - job.at < job.duration then return end
    local entry, record = Vending.get(job.id), Registry.get(job.serial)
    local openAccess = record and job.openAccess and record.lockCondition == 'damaged' and not record.securitySeal
    if not job.forced and not service.canRegister(src, record) then return notify(src, 'Your cylinder service permission changed. Start a new attempt.') end
    if not entry or entry.serial ~= job.serial or not record or record.securitySeal or record.padlock or not service.cabinetOpen(entry, src)
        or not (service.canReplace(src, record) or openAccess or record.lockCondition == 'damaged' and service.canUnseal(src, record)) or not Vending.near(src, entry, Vending.reach())
        or record.lockRevision ~= job.revision or service.busy(entry) or Vending.isTransferringStock(entry)
        or MetaComic.VendingLoot and MetaComic.VendingLoot.busy(entry) then return notify(src, 'The machine changed or became busy. Replacement stopped.') end
    locks[job.serial] = true
    local item = keys.CylinderItem or 'vending_lock_cylinder'
    if not MetaComic.Inventory.remove(src, item, 1) then locks[job.serial] = nil; return notify(src, 'You need a replacement lock cylinder.') end
    local old = MetaComic.CopyTable(record)
    local registered = service.canRegister(src, record)
    -- Freeze what the operating system knows before a stranger changes the physical cylinder.
    if not registered and not record.registeredKeyArchive then
        record.registeredKeyArchive = MetaComic.CopyTable(record.keyArchive)
        record.registeredLockId = record.lockId
    end
    local cylinders = record.keyArchive.cylinders
    local previous = cylinders[#cylinders]
    previous.retiredAt, previous.retiredBy, previous.retiredById = os.time(), Registry.nameOf(src), Registry.identifierOf(src)
    local generation = previous.generation + 1
    local cylinder = { id = ('%s-C%04d'):format(job.serial, generation), generation = generation, installedAt = os.time(), installedBy = Registry.nameOf(src), installedById = Registry.identifierOf(src) }
    cylinders[#cylinders + 1] = cylinder
    if registered and record.registeredKeyArchive then
        local archive = record.registeredKeyArchive
        local known = archive.cylinders[#archive.cylinders]
        known.retiredAt, known.retiredBy, known.retiredById = os.time(), Registry.nameOf(src), Registry.identifierOf(src)
        archive.cylinders[#archive.cylinders + 1] = MetaComic.CopyTable(cylinder)
        record.registeredLockId = cylinder.id
    end
    record.lockId, record.lockCondition, record.securitySeal = cylinder.id, 'intact', nil
    record.lockInstallerId = Registry.identifierOf(src)
    record.unlockedUntil, record.unlockedBy, record.displacedOpen = nil, nil, nil
    record.replacementKeyDue = { lockId = cylinder.id, recipient = Registry.identifierOf(src) }
    service.invalidate(record)
    local ok = persist(record, old)
    if not ok then MetaComic.Inventory.add(src, item, 1) end
    locks[job.serial] = nil
    if not ok then return notify(src, 'Could not save the cylinder replacement. Your cylinder was returned.') end
    entry.openedBy = nil
    Vending.broadcast(entry)
    -- A replacement includes one numbered full-access key for the verified requester.
    -- Owners may receive this service key without gaining the business's general key-issuance permission.
    local issued, err = deliverReplacementKey(src, record)
    notify(src, issued and 'Cylinder replaced; old keys retired. A new full-access key was issued.'
        or ('Cylinder replaced. ' .. err .. ' Use Collect replacement key in the cabinet menu to retry.'), issued and 'success' or 'error')
    TriggerClientEvent('meta_comic:client:vendingMenuRefresh',src,entry.id)
end)
AddEventHandler('playerDropped', function() sessions[source], pending[source] = nil, nil end)
CreateThread(function()
    Wait(1000)
    for index, record in ipairs(Registry.all()) do
        service.ensure(record)
        if index%50==0 then Wait(0) end
    end
    while true do
        Wait(1000)
        for src, job in pairs(pending) do
            local entry = Vending.get(job.id)
            local ped = GetPlayerPed(src)
            if not entry or entry.serial ~= job.serial or not Vending.near(src, entry, Vending.reach())
                or ped == 0 or GetEntityHealth(ped) <= 100 or GetGameTimer() - job.at > job.duration + 180000 then
                pending[src] = nil
            end
        end
        for src, machines in pairs(sessions) do
            for serial, session in pairs(machines) do
                local entry = Vending.bySerial(serial)
                -- Streaming out / walking away must not discard authentication. Actions still require proximity.
                if not validSession(src, entry, 'service') then
                    machines[serial] = nil
                    if entry then TriggerClientEvent('meta_comic:client:vendingKeyAccess', src, { id = entry.id, seconds = 0 }) end
                end
            end
            if not next(machines) then sessions[src] = nil end
        end
    end
end)
