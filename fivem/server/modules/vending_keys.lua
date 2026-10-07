-- Physical keys are inventory items, not ownership. The permanent archive is never subject to HistoryLength.
local cfg = Config.VendingMachines or {}
local keys = cfg.Keys or {}
if cfg.Enabled == false or keys.Enabled ~= true then return end
local Registry, Vending = MetaComic.VendingRegistry, MetaComic.Vending
local service, sessions, pending, locks = {}, {}, {}, {}
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
function service.busy(entry) return entry and (locks[entry.serial] == true or service.replacing(entry)) end
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
function service.access(src, entry, required, moving)
    if not entry then return false end
    local ped = GetPlayerPed(src)
    if ped == 0 or GetEntityHealth and GetEntityHealth(ped) <= 100 then return false end
    local record = entry and Registry.get(entry.serial)
    local session = sessions[src] and sessions[src][entry.serial]
    -- a damaged / sealed cylinder still turns for its current keys: after a break-in is secured the key holders keep
    -- running the machine until the cylinder is replaced (sealing bumps lockRevision, so they unlock once more)
    if not record or not record.keyArchive or not session
        or session.revision ~= record.lockRevision or session.untilAt <= os.time()
        or not Vending.near(src, entry, moving and (tonumber(cfg.PlaceDistance) or 15) + 10 or Vending.reach()) then return false end
    return findKey(src, record, required, session.keyId) ~= nil
end
function service.invalidate(record)
    record.lockRevision = (record.lockRevision or 0) + 1
end
-- kind: who chained it ('police', 'owner', 'business'; 'automatic' for the security timer, nil for anyone else)
function service.sealFields(record, by, kind)
    return { unlockedUntil = false, unlockedBy = false, lockCondition = 'damaged',
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
    if not Vending.canManage(src) and not (replacement and target == src and service.authority(src, record)) then return false, 'Only the business can issue keys.' end
    if not target or target ~= math.floor(target) or not GetPlayerName(target) then return false, 'Choose an online recipient.' end
    if access ~= 'full' and access ~= 'service' then return false, 'Choose full or service access.' end
    if not service.ensure(record) then return false, 'Could not initialize the lock record.' end
    if locks[serial] or service.replacing({ serial = serial }) then return false, 'The lock is being serviced.' end
    if record.lockCondition ~= 'intact' or record.securitySeal then return false, 'Repair or replace the damaged cylinder before issuing keys.' end
    locks[serial] = true
    local old = MetaComic.CopyTable(record)
    local key = { id = ('%s-K%06d'):format(serial, #record.keyArchive.keys + 1), lockId = record.lockId, access = access,
        issuedAt = os.time(), issuedTo = Registry.identifierOf(target), issuedToName = Registry.nameOf(target),
        issuedBy = Registry.identifierOf(src), issuedByName = Registry.nameOf(src) }
    record.keyArchive.keys[#record.keyArchive.keys + 1] = key
    local metadata = { serial = serial, lockId = key.lockId, keyId = key.id, access = access,
        label = ('Vending key %s (%s)'):format(serial, access),
        description = ('Machine: %s | Cylinder: %s | Key: %s | Access: %s'):format(serial, key.lockId, key.id, access) }
    local ok = persist(record, old)
    local added, result = false, false
    if ok then added, result = pcall(MetaComic.Inventory.add, target, ITEM, 1, metadata) end
    if ok and (not added or not result) then
        -- Keep the number reserved, recording the failed delivery rather than reusing an evidence identifier.
        key.deliveryFailed = true
        Registry.save()
        ok = false
    end
    locks[serial] = nil
    if not ok then return false, 'Could not save or deliver the key.' end
    notify(target, ('Received %s key for %s.'):format(access, serial), 'success')
    return true
end
function service.issue(src, serial, target, access) return issue(src, serial, target, access, false) end
function service.unlock(src, entry, slot)
    local record = entry and Registry.get(entry.serial)
    if not entry or not Vending.near(src, entry, Vending.reach()) then return notify(src, 'Stand at the machine.') end
    if not service.ensure(record) or service.busy(entry) then return notify(src, 'The lock is unavailable or being serviced.') end
    if MetaComic.VendingLoot and MetaComic.VendingLoot.isOpen(entry) then return notify(src, 'Secure and repair the broken-in cabinet first.') end
    if record.securitySeal then return notify(src, service.sealText(record)) end -- chained shut: the key can't reach the cabinet
    local key
    if slot then
        local item = MetaComic.Inventory.getSlot(src, tonumber(slot))
        if item and item.name == ITEM and (tonumber(item.count or item.amount) or 0) > 0 then key = archivedKey(record, item.metadata or item.info) end
    else key = findKey(src, record, 'full') or findKey(src, record, 'service') end
    if not key then return notify(src, 'You need a matching current key. Retired keys cannot unlock this cylinder.') end
    sessions[src] = sessions[src] or {}
    sessions[src][entry.serial] = { keyId = key.id, revision = record.lockRevision, untilAt = os.time() + math.max(10, tonumber(keys.SessionSeconds) or 300) }
    notify(src, ('Cabinet unlocked (%s access).'):format(key.access), 'success')
    if record.securitySeal or record.lockCondition ~= 'intact' then notify(src, 'The lock is still damaged. Repair or replace the cylinder to make the machine secure again.', 'info') end
    Vending.openManage(src, entry)
end
RegisterNetEvent('meta_comic:server:vendingKeyUnlock', function(id) service.unlock(source, Vending.get(id)) end)
RegisterNetEvent('meta_comic:server:vendingIssueKey', function(serial, target, access)
    local src = source -- saving can yield, and `source` is gone after a yield
    local ok, err = service.issue(src, serial, target, access)
    notify(src, ok and 'Numbered key issued and permanently recorded.' or err, ok and 'success' or 'error')
end)
-- Repairing a damaged cylinder (Config.VendingMachines.Keys.Repair) keeps it and every key cut for it: it uses up the
-- configured items and takes the chain and padlock off. Replacing the cylinder (further down) retires the old keys instead.
local repair = keys.Repair or {}
local repairing = {} -- src -> repair job
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
    return repair.Enabled ~= false and record ~= nil and service.authority(src, record) and (record.lockCondition ~= 'intact' or record.securitySeal ~= nil)
end
RegisterNetEvent('meta_comic:server:vendingRepairStart', function(id)
    local src, entry = source, Vending.get(id)
    local record = entry and Registry.get(entry.serial)
    local busyJob = repairing[src]
    if busyJob and GetGameTimer() - busyJob.at < busyJob.duration + 30000 then return end
    if pending[src] or not entry or not canRepair(src, record) or not Vending.near(src, entry, Vending.reach()) then return end
    if not service.ensure(record) or service.busy(entry) or Vending.isTransferringStock(entry)
        or MetaComic.VendingLoot and MetaComic.VendingLoot.busy(entry) then return notify(src, 'The machine is busy.') end
    local missing = missingRepairItem(src)
    if missing then return notify(src, ('You need %dx %s to repair the cylinder.'):format(missing.count, missing.label)) end
    local duration = math.max(1000, tonumber(repair.Duration) or 30000)
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
    -- same cylinder, same keys; open key sessions still close (new revision)
    Registry.update(record.serial, { lockCondition = 'intact', securitySeal = false, unlockedUntil = false, unlockedBy = false,
        lockRevision = (record.lockRevision or 0) + 1 }, 'Lock cylinder repaired; chain and padlock removed', Registry.nameOf(src))
    local ok = persist(record, old)
    if not ok then giveBack() end
    locks[job.serial] = nil
    if not ok then return notify(src, 'Could not save the repair. Your items were returned.') end
    entry.openedBy = nil
    Vending.broadcast(entry)
    notify(src, 'Lock cylinder repaired and the chain removed. The existing keys still work.', 'success')
end)
AddEventHandler('playerDropped', function() repairing[source] = nil end)

RegisterNetEvent('meta_comic:server:vendingKeyMenu', function(id)
    local src = source -- creating the lock record can yield, and `source` is gone after a yield
    local entry = Vending.get(id)
    if not entry or not Vending.near(src, entry, Vending.reach()) then return end
    local record = Registry.get(entry.serial)
    if not service.ensure(record) then return end
    local police = MetaComic.Police and MetaComic.Police.isPolice and MetaComic.Police.isPolice(src)
    local box = MetaComic.VendingCashbox
    local session = service.access(src, entry, 'service')
    TriggerClientEvent('meta_comic:client:vendingKeyMenu', src, {
        -- open / close the machine and its cash box separately (server/modules/vending_door.lua)
        hasFull = findKey(src, record, 'full') ~= nil, session = session, fullSession = session and service.access(src, entry, 'full'),
        cabinetOpen = box ~= nil and box.cabinetOpen(entry.id), boxOpen = box ~= nil and box.isOpen(entry.id),
        boxEnabled = box ~= nil and box.keyBox == true,
        id = entry.id, serial = entry.serial, lockId = record.lockId, condition = record.lockCondition, sealed = record.securitySeal ~= nil,
        canReplace = service.authority(src, record), canIssue = Vending.canManage(src),
        sealText = service.sealText(record), canRepair = canRepair(src, record), repairItems = repairLabel(),
        canRead = police or service.authority(src, record),
    })
end)
RegisterNetEvent('meta_comic:server:vendingKeyLock', function(id)
    local src = source -- saving can yield, and `source` is gone after a yield
    local entry = Vending.get(id)
    if not service.access(src, entry, 'service') then return end
    if service.busy(entry) or Vending.isTransferringStock(entry) or MetaComic.VendingLoot and MetaComic.VendingLoot.busy(entry) then return end
    local record = Registry.get(entry.serial)
    if locks[entry.serial] then return end
    locks[entry.serial] = true
    local old = MetaComic.CopyTable(record)
    service.invalidate(record)
    local ok = persist(record, old)
    locks[entry.serial] = nil
    if ok then notify(src, 'Cabinet locked. All cabinet sessions closed.', 'success') end
end)

-- Lost/stolen keys and broken locks use the same verified physical replacement service.
RegisterNetEvent('meta_comic:server:vendingRekeyStart', function(id)
    local src, entry = source, Vending.get(id)
    local record = entry and Registry.get(entry.serial)
    if pending[src] or not service.authority(src, record) or not entry or not Vending.near(src, entry, Vending.reach()) then return end
    if not service.ensure(record) or service.busy(entry) or Vending.isTransferringStock(entry)
        or MetaComic.VendingLoot and MetaComic.VendingLoot.busy(entry) then return notify(src, 'The machine is busy.') end
    local item = keys.CylinderItem or 'vending_lock_cylinder'
    if (MetaComic.Inventory.count(src, item) or 0) < 1 then return notify(src, 'You need a replacement lock cylinder.') end
    local duration = math.max(1000, tonumber(keys.ReplaceDuration) or 60000)
    local token = ('%s:%s:%s'):format(src, GetGameTimer(), record.lockRevision)
    pending[src] = { id = entry.id, serial = entry.serial, revision = record.lockRevision, token = token, at = GetGameTimer(), duration = duration }
    TriggerClientEvent('meta_comic:client:vendingRekeyStart', src, { token = token, duration = duration })
    TriggerEvent('meta_comic:server:vendingDoorSuccess', src, entry.id, 'rekey')
end)
RegisterNetEvent('meta_comic:server:vendingRekeyCancel', function() pending[source] = nil end)
RegisterNetEvent('meta_comic:server:vendingRekeyFinish', function(token)
    local src, job = source, pending[source]
    pending[src] = nil
    if not job or job.token ~= token or GetGameTimer() - job.at < job.duration then return end
    local entry, record = Vending.get(job.id), Registry.get(job.serial)
    if not entry or entry.serial ~= job.serial or not service.authority(src, record) or not Vending.near(src, entry, Vending.reach())
        or record.lockRevision ~= job.revision or service.busy(entry) or Vending.isTransferringStock(entry)
        or MetaComic.VendingLoot and MetaComic.VendingLoot.busy(entry) then return notify(src, 'The machine changed or became busy. Replacement stopped.') end
    locks[job.serial] = true
    local item = keys.CylinderItem or 'vending_lock_cylinder'
    if not MetaComic.Inventory.remove(src, item, 1) then locks[job.serial] = nil; return notify(src, 'You need a replacement lock cylinder.') end
    local old = MetaComic.CopyTable(record)
    local cylinders = record.keyArchive.cylinders
    local previous = cylinders[#cylinders]
    previous.retiredAt, previous.retiredBy, previous.retiredById = os.time(), Registry.nameOf(src), Registry.identifierOf(src)
    local generation = previous.generation + 1
    local cylinder = { id = ('%s-C%04d'):format(job.serial, generation), generation = generation, installedAt = os.time(), installedBy = Registry.nameOf(src), installedById = Registry.identifierOf(src) }
    cylinders[#cylinders + 1] = cylinder
    record.lockId, record.lockCondition, record.securitySeal = cylinder.id, 'intact', nil
    record.unlockedUntil, record.unlockedBy = nil, nil
    service.invalidate(record)
    local ok = persist(record, old)
    if not ok then MetaComic.Inventory.add(src, item, 1) end
    locks[job.serial] = nil
    if not ok then return notify(src, 'Could not save the cylinder replacement. Your cylinder was returned.') end
    entry.openedBy = nil
    Vending.broadcast(entry)
    -- A replacement includes one numbered full-access key for the verified requester.
    -- Owners may receive this service key without gaining the business's general key-issuance permission.
    local issued, err = issue(src, record.serial, src, 'full', true)
    notify(src, issued and 'Cylinder replaced; old keys retired. A new full-access key was issued.' or ('Cylinder replaced. ' .. err), issued and 'success' or 'error')
end)
AddEventHandler('playerDropped', function() sessions[source], pending[source] = nil, nil end)
CreateThread(function()
    Wait(1000)
    for _, record in ipairs(Registry.all()) do service.ensure(record) end
    while true do
        Wait(1000)
        for src, job in pairs(pending) do
            local entry = Vending.get(job.id)
            local ped = GetPlayerPed(src)
            if not entry or entry.serial ~= job.serial or not Vending.near(src, entry, Vending.reach())
                or ped == 0 or GetEntityHealth(ped) <= 100 or GetGameTimer() - job.at > job.duration + 30000 then
                pending[src] = nil
            end
        end
        for src, machines in pairs(sessions) do
            for serial, session in pairs(machines) do
                local entry = Vending.bySerial(serial)
                if session.untilAt <= os.time() or not entry or not service.access(src, entry, 'service', true) then machines[serial] = nil end
            end
            if not next(machines) then sessions[src] = nil end
        end
    end
end)
