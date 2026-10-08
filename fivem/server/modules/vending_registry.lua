-- Vending machine ownership records (Config.VendingMachines.Ownership). Every machine has a serial number; the
-- record for a serial says who owns it, which account its card payments are routed to, where it is (placed / an item
-- in someone's inventory / stolen) and what happened to it. Records are the single source of truth: a machine picked
-- up and placed again, or stolen and placed somewhere else, still pays its owner until someone hacks its routing.
-- People have to be registered by the business (admin UI "Machine records") before they can be assigned machines;
-- each registered person gets a routing number and their own tax rate, taken from their sales for the business.
-- Saved with MetaComic.Settings (MySQL settings table or data/settings.json).
local cfg = Config.VendingMachines or {}
if cfg.Enabled == false then return end
local own = cfg.Ownership or {}

MetaComic.VendingRegistry = {}
local service = MetaComic.VendingRegistry
local KEY = 'vending_registry'
local HISTORY = math.max(1, math.floor(tonumber(own.HistoryLength) or 25))
local BUSINESS = 'business'

local function notify(source, message, notifyType)
    if MetaComic.Framework.notify then MetaComic.Framework.notify(source, message, notifyType) end
end
-- a vending test role (/vendingtestrole, server/modules/vending_testing.lua) can make a player someone else here
local function testRole(source) return MetaComic.VendingTestRole and MetaComic.VendingTestRole(source) end
local function identifierOf(source)
    local test = testRole(source)
    if test and test.identifier then return test.identifier end
    return MetaComic.Framework.getIdentifier and MetaComic.Framework.getIdentifier(source) or MetaComic.GetLicense(source)
end
local function nameOf(source)
    local test = testRole(source)
    if test and test.name then return test.name end
    return MetaComic.Framework.getName and MetaComic.Framework.getName(source) or GetPlayerName(source) or ('Player %s'):format(source)
end
service.identifierOf, service.nameOf = identifierOf, nameOf
local function clampTax(rate) rate = tonumber(rate); if not rate or rate ~= rate then return nil end; return math.max(0, math.min(100, math.floor(rate * 100 + 0.5) / 100)) end
local function defaultTax() return clampTax(own.DefaultTax) or 10 end
service.BUSINESS = BUSINESS
service.businessName = own.BusinessName or 'Collectibles Co.'

-- data = { people = { [id] = person }, serials = { [serial] = record }, pending = { [id] = amount }, business = { pending } }
local data
local function load()
    if data then return data end
    local saved = MetaComic.Settings.get(KEY, nil)
    data = type(saved) == 'table' and saved or {}
    data.people = type(data.people) == 'table' and data.people or {}
    data.serials = type(data.serials) == 'table' and data.serials or {}
    data.pending = type(data.pending) == 'table' and data.pending or {}
    data.business = type(data.business) == 'table' and data.business or { pending = 0 }
    data.business.pending = tonumber(data.business.pending) or 0
    return data
end
local function save()
    local ok, err = MetaComic.Settings.set(KEY, load())
    if not ok then print('[meta-comic] vending records save failed: ' .. tostring(err)) end
    return ok
end
service.save = save

-- Serial / routing numbers ------------------------------------------------------------------------------------------
local ALPHABET = '23456789ABCDEFGHJKLMNPQRSTUVWXYZ' -- no 0/O/1/I
local function randomCode(length)
    local out = {}
    for i = 1, length do local n = math.random(1, #ALPHABET); out[i] = ALPHABET:sub(n, n) end
    return table.concat(out)
end
function service.newSerial()
    local prefix = own.SerialPrefix or 'VM'
    for _ = 1, 50 do
        local serial = ('%s-%s-%s'):format(prefix, randomCode(4), randomCode(4))
        if not load().serials[serial] then return serial end
    end
    return ('%s-%s'):format(prefix, os.time())
end
local function routingInUse(number)
    if number == service.businessRouting() then return true end
    for _, person in pairs(load().people) do if person.routing == number then return true end end
    return false
end
local function newRouting()
    for _ = 1, 50 do
        local number = ('%09d'):format(math.random(0, 999999999))
        if not routingInUse(number) then return number end
    end
    return tostring(os.time())
end
function service.businessRouting() return tostring(own.BusinessRouting or '000000001') end
service.newRouting = newRouting

-- People ------------------------------------------------------------------------------------------------------------
function service.person(id) return id and load().people[id] or nil end
function service.people()
    local list = {}
    for _, person in pairs(load().people) do list[#list + 1] = person end
    table.sort(list, function(a, b) return (a.name or '') < (b.name or '') end)
    return list
end
function service.register(id, name, tax, by)
    if type(id) ~= 'string' or id == '' then return nil, 'Unknown person.' end
    local people = load().people
    local person = people[id]
    if not person then
        person = { id = id, name = name or id, routing = newRouting(), tax = clampTax(tax) or defaultTax(), registeredAt = os.time(), registeredBy = by }
        people[id] = person
    else
        person.name = name or person.name
        if tax ~= nil then person.tax = clampTax(tax) or person.tax end
        person.active = nil
    end
    if not save() then people[id] = nil; return nil, 'Could not save the records.' end
    return person
end
function service.unregister(id)
    local person = load().people[id]
    if not person then return false, 'Not registered.' end
    for _, record in pairs(load().serials) do
        if record.owner == id then return false, ('%s still owns %s. Assign it to someone else first.'):format(person.name, record.serial) end
    end
    load().people[id] = nil
    return save()
end
function service.setTax(id, tax)
    local person = load().people[id]
    local rate = clampTax(tax)
    if not person or not rate then return false, 'Unknown person or tax rate.' end
    local old = person.tax
    person.tax = rate
    if not save() then person.tax = old; return false, 'Could not save the records.' end
    return true
end
function service.taxRate(ownerId)
    if not ownerId or ownerId == BUSINESS then return 0 end
    local person = load().people[ownerId]
    return person and person.tax or defaultTax()
end

-- Serial records ----------------------------------------------------------------------------------------------------
-- record = { serial, owner (person id or nil = the business), routing = { id, name, number } | nil (= the owner),
--   status = 'item' | 'placed' | 'stolen' | 'removed', machineId, coords, holder = { id, name }, tampered, history }
function service.get(serial) return serial and load().serials[serial] or nil end
function service.ensure(serial, fields)
    local serials = load().serials
    local record = serials[serial]
    if not record then
        record = { serial = serial, createdAt = os.time(), status = 'item', history = {} }
        serials[serial] = record
    end
    for key, value in pairs(fields or {}) do record[key] = value end
    return record
end
-- changes fields (use false to clear one) and logs what happened; saves
function service.update(serial, fields, event, by)
    local record = service.ensure(serial)
    if record.systemController and not record.osBusinessSnapshot and not (fields and fields.osBusinessSnapshot) then service.ensureOS(record) end
    for key, value in pairs(fields or {}) do
        if value == false then record[key] = nil else record[key] = value end
    end
    if event then
        local field = record.systemController and 'osHistory' or 'history'
        record[field] = type(record[field]) == 'table' and record[field] or {}
        table.insert(record[field], 1, { at = os.time(), event = event, by = by })
        while #record[field] > HISTORY do table.remove(record[field]) end
    end
    record.updatedAt = os.time()
    save()
    return record
end
function service.ownerName(record)
    if not record or not record.owner then return service.businessName end
    local person = load().people[record.owner]
    return person and person.name or record.ownerName or record.owner
end
function service.businessOwned(record)
    return record ~= nil and (not record.owner or record.owner == BUSINESS)
end
function service.ownedBy(record, id)
    return record ~= nil and id ~= nil and id ~= BUSINESS and record.owner == id
end
-- a hack that expired (Crime.Hack.Hours) counts as fixed
local function rerouted(record)
    if not (record and type(record.routing) == 'table' and record.routing.id) then return false end
    return not record.routingUntil or os.time() < record.routingUntil
end
service.rerouted = rerouted
-- who card payments go to now: { id, name, number }
function service.routing(record)
    if rerouted(record) then return record.routing end
    if record and record.owner then
        local person = load().people[record.owner]
        return { id = record.owner, name = service.ownerName(record), number = person and person.routing or '?' }
    end
    return { id = BUSINESS, name = service.businessName, number = service.businessRouting() }
end
-- the identifier that runs the machine: a hacker who rerouted it, otherwise its owner (nil = the business)
function service.systemController(record)
    if record and record.systemController then return record.systemController end
end
function service.osMember(record, id)
    return record ~= nil and record.systemController ~= nil and id ~= nil
        and (record.systemController == id or type(record.osDelegates) == 'table' and record.osDelegates[id] == true)
end
function service.hasOSAccess(source)
    local id = identifierOf(source)
    for _, record in ipairs(service.all()) do if service.osMember(record, id) then return true end end
    return false
end
function service.setOSAccess(source, serial, target, allowed)
    local record = service.get(serial)
    if not record or record.systemController ~= identifierOf(source) then return false, 'Only this OS controller can change remote access.' end
    local id
    if allowed ~= true and type(target) == 'string' and record.osDelegates and record.osDelegates[target] then
        id = target -- existing delegates may be revoked while offline
    else
        target = tonumber(target)
        if not target or target ~= math.floor(target) or not GetPlayerName(target) then return false, 'Choose an online player ID.' end
        id = identifierOf(target)
    end
    if not id or id == record.systemController then return false, 'The controller always retains access.' end
    local previous = MetaComic.CopyTable(record)
    local delegates = MetaComic.CopyTable(record.osDelegates or {})
    delegates[id] = allowed == true or nil
    service.update(serial, { osDelegates = delegates }, allowed and 'OS operating access granted' or 'OS operating access revoked', nameOf(source))
    if not service.save() then
        for k in pairs(record) do record[k] = nil end
        for k, v in pairs(previous) do record[k] = v end
        return false, 'Could not save OS access.'
    end
    if MetaComic.Vending and MetaComic.Vending.sendAccessAll then MetaComic.Vending.sendAccessAll() end
    return true
end
function service.osStartFields(record, id)
    return { systemController = id, systemUntil = false, osDelegates = {}, osHistory = {}, osSales = {}, osStartedAt = os.time(),
        osBusinessSnapshot = MetaComic.CopyTable(service.view(record, true)),
        osKeyBaseline = #(record.keyArchive and record.keyArchive.keys or {}),
        osCylinderBaseline = #(record.keyArchive and record.keyArchive.cylinders or {}) }
end
function service.ensureOS(record)
    if not record or not record.systemController or record.osBusinessSnapshot then return true end
    -- Upgrade an already-taken-over machine without giving its existing records to the new OS.
    local old = MetaComic.CopyTable(record)
    for key, value in pairs(service.osStartFields(record, record.systemController)) do
        if value == false then record[key] = nil else record[key] = value end
    end
    if service.save() then return true end
    for k in pairs(record) do record[k] = nil end
    for k, v in pairs(old) do record[k] = v end
    return false
end
function service.osRecoveryFields(record)
    local archives = MetaComic.CopyTable(record.osArchives or {})
    archives[#archives + 1] = { controller = record.systemController, startedAt = record.osStartedAt, endedAt = os.time(),
        history = MetaComic.CopyTable(record.osHistory or {}), sales = MetaComic.CopyTable(record.osSales or {}) }
    local fields = { systemController = false, systemUntil = false, osDelegates = false, osHistory = false, osSales = false,
        osStartedAt = false, osBusinessSnapshot = false, osKeyBaseline = false, osCylinderBaseline = false, osArchives = archives }
    if record.osBusinessSnapshot and record.osBusinessSnapshot.keyArchive then
        fields.registeredKeyArchive = MetaComic.CopyTable(record.osBusinessSnapshot.keyArchive)
        fields.registeredLockId = record.osBusinessSnapshot.lockId
    end
    return fields
end
function service.controller(record)
    local system = service.systemController(record)
    if system then return system end
    return record and record.owner or nil
end
function service.assign(serial, ownerId, by)
    local record = service.get(serial)
    if not record then return nil, 'Unknown serial number.' end
    if ownerId and ownerId ~= BUSINESS and not load().people[ownerId] then return nil, 'That person is not registered.' end
    local owner = ownerId ~= BUSINESS and ownerId or false
    local name = owner and load().people[owner].name or service.businessName
    local fields = { owner = owner, ownerName = owner and name or false }
    if not service.systemController(record) then fields.routing = false; fields.tampered = false; fields.routingUntil = false end
    return service.update(serial, fields,
        ('Assigned to %s'):format(name), by)
end
function service.resetRouting(serial, by)
    if service.systemController(service.get(serial)) then return nil, 'Physically replace the control board to recover this machine.' end
    return service.update(serial, { routing = false, tampered = false, routingUntil = false }, 'Routing reset to the owner', by)
end
-- a view for the records UI / record items (no history unless asked)
-- Business records only know cylinders registered by an owner, manager or authorized employee.
-- Physical lock/key state remains separate, including unreported replacements.
function service.keyRecords(record)
    if not record then return {} end
    return { lockId = record.registeredLockId or record.lockId,
        archive = MetaComic.CopyTable(record.registeredKeyArchive or record.keyArchive) }
end
function service.view(record, withHistory)
    if not record then return nil end
    local routing = service.routing(record)
    local person = record.owner and load().people[record.owner]
    local tampered = record.tampered == true and rerouted(record)
    local keyRecords = service.keyRecords(record)
    return {
        serial = record.serial, owner = record.owner or BUSINESS, ownerName = service.ownerName(record),
        ownerRouting = person and person.routing or (not record.owner and service.businessRouting() or nil),
        tax = service.taxRate(record.owner), routing = routing.number, tampered = tampered,
        routingName = tampered and not own.RevealHacker and 'Unknown account' or routing.name,
        status = record.status, machineId = record.machineId, coords = record.coords, holder = record.holder,
        systemTakenOver = service.systemController(record) ~= nil, worldState = record.worldState,
        createdAt = record.createdAt, updatedAt = record.updatedAt, history = withHistory and record.history or nil,
        lockId = keyRecords.lockId, lockCondition = record.lockCondition, securitySeal = record.securitySeal,
        keyArchive = withHistory and keyRecords.archive or nil,
        sales = withHistory and MetaComic.CopyTable(record.sales or {}) or nil, -- Ownership.SalesLog, newest first
    }
end
function service.viewFor(record, source, withHistory)
    if not record then return nil end
    if not record.systemController then return service.view(record, withHistory) end
    service.ensureOS(record)
    if service.osMember(record, identifierOf(source)) then
        -- The replacement OS receives only records generated during this takeover.
        local archive = { keys = {}, cylinders = {} }
        for i, key in ipairs(record.keyArchive and record.keyArchive.keys or {}) do
            if i > (record.osKeyBaseline or #record.keyArchive.keys) then archive.keys[#archive.keys + 1] = MetaComic.CopyTable(key) end
        end
        for i, cylinder in ipairs(record.keyArchive and record.keyArchive.cylinders or {}) do
            if i > (record.osCylinderBaseline or #record.keyArchive.cylinders) then archive.cylinders[#archive.cylinders + 1] = MetaComic.CopyTable(cylinder) end
        end
        local known = {}
        for _, cylinder in ipairs(archive.cylinders) do known[cylinder.id] = true end
        for _, key in ipairs(archive.keys) do
            if not known[key.lockId] then
                -- New key issuance identifies its cylinder, but supplies no old installation or key history.
                archive.cylinders[#archive.cylinders + 1] = { id = key.lockId, installedBy = 'Identified by new OS key issuance' }
                known[key.lockId] = true
            end
        end
        local routing = service.routing(record)
        local operators = {}
        for id, allowed in pairs(record.osDelegates or {}) do if allowed then operators[#operators + 1] = id end end
        table.sort(operators)
        return { serial = record.serial, ownerName = 'Taken-over OS', osView = true, systemTakenOver = true,
            status = record.status, machineId = record.machineId, coords = MetaComic.CopyTable(record.coords),
            holder = MetaComic.CopyTable(record.holder), worldState = record.worldState,
            routing = routing.number, routingName = routing.name, tampered = record.tampered,
            createdAt = record.osStartedAt, updatedAt = record.updatedAt,
            history = withHistory and MetaComic.CopyTable(record.osHistory or {}) or nil,
            sales = withHistory and MetaComic.CopyTable(record.osSales or {}) or nil,
            keyArchive = withHistory and archive or nil, lockId = known[record.lockId] and record.lockId or nil,
            lockCondition = known[record.lockId] and record.lockCondition or nil,
            osOperators = operators, canManageOSAccess = record.systemController == identifierOf(source) }
    end
    local view = MetaComic.CopyTable(record.osBusinessSnapshot or {
        serial = record.serial, owner = record.owner or BUSINESS, ownerName = service.ownerName(record), history = {}, sales = {} })
    view.coords, view.machineId, view.holder, view.worldState, view.cash = nil, nil, nil, nil, nil
    view.remoteOffline, view.systemTakenOver = true, true
    if not withHistory then view.history, view.sales, view.keyArchive = nil, nil, nil end
    return view
end
function service.all()
    local list = {}
    for _, record in pairs(load().serials) do list[#list + 1] = record end
    table.sort(list, function(a, b) return (a.serial or '') < (b.serial or '') end)
    return list
end

-- Money -------------------------------------------------------------------------------------------------------------
local function onlineSource(id)
    for _, player in ipairs(GetPlayers()) do
        player = tonumber(player)
        if identifierOf(player) == id then return player end
    end
end
service.onlineSource = onlineSource

-- Business account (Ownership.Business): society / job account money goes to when the business is paid
local function depositBusiness(amount, reason)
    local business = own.Business or {}
    local account, banking = business.Account or 'cardshop', business.Banking or 'auto'
    local function started(name) return GetResourceState(name) == 'started' end
    if banking == 'auto' then
        for _, name in ipairs({ 'Renewed-Banking', 'okokBanking', 'qb-banking', 'qb-management', 'ox_core' }) do
            if started(name) then banking = name; break end
        end
    end
    if banking == 'custom' and type(business.Deposit) == 'function' then
        local ok, result = pcall(business.Deposit, account, amount, reason)
        return ok and result ~= false
    end
    local ok, result = pcall(function()
        if banking == 'Renewed-Banking' then return exports['Renewed-Banking']:addAccountMoney(account, amount) end
        if banking == 'okokBanking' then return exports.okokBanking:AddMoney(account, amount) end
        if banking == 'qb-banking' then return exports['qb-banking']:AddMoney(account, amount, reason) end
        if banking == 'qb-management' then return exports['qb-management']:AddMoney(account, amount) end
        if banking == 'ox_core' then
            local group = exports.ox_core:GetGroupAccount(account)
            local accountId = type(group) == 'table' and (group.accountId or group.id) or group
            return exports.ox_core:CallAccount(accountId, 'addBalance', { amount = amount, message = reason })
        end
        return false
    end)
    if not ok then print('[meta-comic] business deposit failed: ' .. tostring(result)) end
    return ok and result ~= false and result ~= nil
end

-- pays a person's bank (online) or keeps it until they join; the business share goes to its account, or is held in the
-- records ("Business earnings" in the admin UI) when no banking resource takes it
function service.pay(id, amount, reason)
    amount = math.floor(tonumber(amount) or 0)
    if amount <= 0 then return true end
    local d = load()
    if id == BUSINESS or not id then
        if depositBusiness(amount, reason) then return true end
        d.business.pending = d.business.pending + amount
        return save()
    end
    local source = onlineSource(id)
    if source and MetaComic.Money.add(source, own.PayoutAccount or 'bank', amount, reason) then
        if own.NotifyPayouts ~= false then notify(source, ('$%d paid into your account (%s).'):format(amount, reason), 'success') end
        return true
    end
    d.pending[id] = (tonumber(d.pending[id]) or 0) + amount
    return save()
end
-- a card sale: the owner's tax rate goes to the business, the rest to whoever the machine routes to
-- the machine's recent sales (Ownership.SalesLog), shown to its owner in Manage
function service.logSale(serial, sale)
    local record = serial and load().serials[serial]
    if not record then return end
    if record.systemController then service.ensureOS(record) end
    local field = record.systemController and 'osSales' or 'sales'
    record[field] = type(record[field]) == 'table' and record[field] or {}
    sale.when = sale.when or os.date('%Y-%m-%d %H:%M', sale.at or os.time())
    table.insert(record[field], 1, sale)
    local limit = math.max(1, tonumber(own.SalesLog) or 50)
    while #record[field] > limit do table.remove(record[field]) end
    save()
end
function service.paySale(record, amount)
    local routing = service.routing(record)
    local tax = record.owner and math.floor(amount * service.taxRate(record.owner) / 100 + 0.5) or 0
    if tax > 0 then service.pay(BUSINESS, tax, ('vending tax %s'):format(record.serial)) end
    service.pay(routing.id, amount - tax, ('vending sale %s'):format(record.serial))
    return amount - tax, tax
end
-- cash taken out of the machine by its owner: the business takes its tax share of it
function service.cashTax(record, amount)
    if not record or not record.owner then return 0 end
    local tax = math.floor(amount * service.taxRate(record.owner) / 100 + 0.5)
    if tax > 0 then service.pay(BUSINESS, tax, ('vending tax %s'):format(record.serial)) end
    return tax
end
-- earnings kept while a player was offline
function service.claimPending(source)
    local id = identifierOf(source)
    local d = load()
    local amount = tonumber(d.pending[id]) or 0
    if amount <= 0 then return end
    d.pending[id] = nil
    if not save() then d.pending[id] = amount; return end
    if not MetaComic.Money.add(source, own.PayoutAccount or 'bank', amount, 'vending earnings') then
        d.pending[id] = amount; save()
        return
    end
    notify(source, ('$%d in vending machine earnings were paid into your account.'):format(amount), 'success')
end
function service.pending(id) return tonumber(load().pending[id]) or 0 end
function service.businessPending() return load().business.pending end
function service.withdrawBusiness(source, amount)
    local d = load()
    amount = math.floor(tonumber(amount) or d.business.pending)
    if amount <= 0 or amount > d.business.pending then return false, 'Not that much held.' end
    d.business.pending = d.business.pending - amount
    if not save() then d.business.pending = d.business.pending + amount; return false, 'Could not save the records.' end
    if not MetaComic.Money.add(source, own.PayoutAccount or 'bank', amount, 'vending business earnings') then
        d.business.pending = d.business.pending + amount; save()
        return false, 'Could not pay you.'
    end
    return true
end

CreateThread(function() Wait(500); load() end)
