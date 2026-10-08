-- GPS and skimmers are stored against the serial, so they follow inventory items and towing.
local cfg = Config.VendingMachines or {}
if cfg.Enabled == false then return end
local gps, skimmer = cfg.GPS or {}, cfg.Skimmer or {}
local SKIMMER_ITEM, DATA_ITEM = skimmer.Item or 'card_skimmer', skimmer.DataItem or 'skimmer_card_data'
local Registry, Vending = MetaComic.VendingRegistry, MetaComic.Vending
local service = {}
MetaComic.VendingSecurity = service
local tracked, alerted, locks = {}, {}, {}

local function notify(source, message, kind)
    if MetaComic.Framework.notify then MetaComic.Framework.notify(source, message, kind) end
end
local function write(record, field, value, event, source, authenticated)
    if record.systemController and not Registry.ensureOS(record) then return false end
    local historyField = record.systemController and 'osHistory' or 'history'
    local old, history, updated = record[field], record[historyField], record.updatedAt
    record[field] = value
    if event then -- no event = nothing in the machine's history (card copying must not show up there)
        record[historyField] = MetaComic.CopyTable(history or {})
        table.insert(record[historyField], 1, { at = os.time(), event = event, by = source and Registry.nameOf(source), authenticated = authenticated == true and Registry.identifiedOperator(record, source) == true })
        local limit = math.max(1, tonumber((cfg.Ownership or {}).HistoryLength) or 25)
        while #record[historyField] > limit do table.remove(record[historyField]) end
    end
    record.updatedAt = os.time()
    if Registry.save() then return true end
    record[field], record[historyField], record.updatedAt = old, history, updated
    return false
end
function service.track(serial, entity) if serial then tracked[serial] = entity end end
-- last GPS fix of machines that aren't standing anywhere (carried as an item, dropped, towed): the admin map shows them
local positions = {}
function service.gpsPosition(serial) return serial and positions[serial] or nil end
function service.gps(source, entry, enabled, authenticated)
    if gps.Enabled == false or locks[entry.serial] then return false end
    local record = Registry.get(entry.serial)
    if not record or (enabled and not (Vending.canOperateSystem or Vending.canControl)(source, entry)) then return false end
    locks[entry.serial] = true
    local oldOrigin = record.gpsOrigin
    if enabled then record.gpsOrigin = { x = entry.x, y = entry.y, z = entry.z } end
    local ok = write(record, 'gpsDisabled', not enabled, enabled and 'GPS rearmed at this location' or 'GPS disabled', source, authenticated)
    if not ok then record.gpsOrigin = oldOrigin end
    locks[entry.serial] = nil
    if ok then Vending.broadcast(entry); notify(source, enabled and 'GPS enabled at this spot.' or 'GPS disabled.', 'success') end
    return ok
end
-- the cut the installer may set (Skimmer.MaxPercent), default Skimmer.Percent
function service.cutOf(value)
    local max = math.max(0, math.min(100, tonumber(skimmer.MaxPercent) or 50))
    local cut = math.floor(tonumber(value) or tonumber(skimmer.Percent) or 15)
    return math.max(0, math.min(max, cut))
end
function service.install(source, entry, percent)
    local record = Registry.get(entry.serial)
    if skimmer.Enabled == false or not record or record.skimmer or locks[entry.serial] then return false end
    locks[entry.serial] = true
    local item = skimmer.Item or 'card_skimmer'
    if not MetaComic.Inventory.remove(source, item, 1) then locks[entry.serial] = nil; return false end
    local ok = write(record, 'skimmer', { installer = Registry.identifierOf(source), installedAt = os.time(), percent = service.cutOf(percent), cards = 0, total = 0, skimmed = 0 }, 'Card skimmer installed', source)
    if not ok then MetaComic.Inventory.add(source, item, 1) end
    locks[entry.serial] = nil
    if ok then
        Vending.broadcast(entry)
        if Vending.sendAccess then Vending.sendAccess(source) end -- the installer's own Read / Remove options
        notify(source, 'Card skimmer installed.', 'success')
    end
    return ok
end
function service.cardSale(entry, source, amount)
    while locks[entry.serial] do Wait(0) end -- preserve every card purchase while collection/save yields
    local record = Registry.get(entry.serial)
    local device = record and record.skimmer
    if skimmer.Enabled == false or not device then return amount end
    local cards, total, firstAt = service.counts(device)
    if cards >= math.max(1, tonumber(skimmer.Capacity) or 200) then return amount end -- memory full: copies nothing until it is read
    locks[entry.serial] = true
    -- the installer's cut never reaches the owner: it sits on the skimmer's records until a buyer recovers it
    local percent = device.percent ~= nil and service.cutOf(device.percent) or service.cutOf(nil)
    local withheld = math.floor(amount * percent / 100)
    local nextDevice = { installer = device.installer, installedAt = device.installedAt, percent = percent, cards = cards + 1, total = total + amount,
        skimmed = math.max(0, math.floor(tonumber(device.skimmed) or 0)) + withheld, firstAt = firstAt or os.time(), lastAt = os.time() }
    local ok = write(record, 'skimmer', nextDevice)
    locks[entry.serial] = nil
    return ok and amount - withheld or amount -- never take money if the skimmer write failed
end
-- copied card purchases on a skimmer: count, total $, first copy time (skimmers fitted before card data had a list)
function service.counts(device)
    if type(device) ~= 'table' then return 0, 0 end
    if device.cards == nil and type(device.transactions) == 'table' then
        local total = 0
        for _, sale in ipairs(device.transactions) do total = total + math.max(0, tonumber(sale.amount) or 0) end
        local oldest = device.transactions[#device.transactions]
        return #device.transactions, math.floor(total), oldest and oldest.at
    end
    return math.max(0, math.floor(tonumber(device.cards) or 0)), math.max(0, math.floor(tonumber(device.total) or 0)), device.firstAt
end
local function stamp(at) return at and os.date('%Y-%m-%d %H:%M', at) or '?' end
-- item metadata carrying the copied card data (on the card data printout, or on a removed skimmer)
local function cardData(serial, device)
    local cards, total, firstAt = service.counts(device)
    if cards <= 0 then return nil end
    local skimmed = math.max(0, math.floor(tonumber(device.skimmed) or 0))
    return { dataId = ('SKM-%s-%06d'):format(os.time(), math.random(0, 999999)), serial = serial, cards = cards, total = total, skimmed = skimmed,
        from = stamp(firstAt), to = stamp(device.lastAt or os.time()),
        label = ('Card data (%d cards)'):format(cards),
        description = ('Card details from %d purchases at vending machine %s. $%d skimmed, waiting to be recovered.'):format(cards, serial or '?', skimmed) }
end
local function emptied(device) return { installer = device.installer, installedAt = device.installedAt, percent = device.percent, cards = 0, total = 0, skimmed = 0 } end
function service.collect(source, entry)
    local record = Registry.get(entry.serial)
    local device = record and record.skimmer
    if not device or device.installer ~= Registry.identifierOf(source) or locks[entry.serial] then return false end
    local data = cardData(entry.serial, device)
    if not data then notify(source, 'The skimmer has not copied any cards yet.', 'inform'); return true end
    if MetaComic.Inventory.canCarry and not MetaComic.Inventory.canCarry(source, DATA_ITEM, 1) then
        notify(source, 'You cannot carry the card data.', 'error')
        return false
    end
    locks[entry.serial] = true
    local ok = write(record, 'skimmer', emptied(device))
    if ok and not MetaComic.Inventory.add(source, DATA_ITEM, 1, data) then
        write(record, 'skimmer', device)
        ok = false
    end
    locks[entry.serial] = nil
    if ok then notify(source, ('You copy the card details from %d purchases off the skimmer ($%d skimmed).'):format(data.cards, data.skimmed), 'success') end
    return ok
end
-- the installer changes the cut while it stays fitted (Crime.AdjustSkimmer); it applies to card payments from now on
function service.adjust(source, entry, percent)
    local record = Registry.get(entry.serial)
    local device = record and record.skimmer
    if not device or locks[entry.serial] or device.installer ~= Registry.identifierOf(source) then return false end
    local old, cut = service.cutOf(device.percent), service.cutOf(percent)
    locks[entry.serial] = true
    local nextDevice = MetaComic.CopyTable(device)
    nextDevice.percent = cut
    local ok = write(record, 'skimmer', nextDevice)
    locks[entry.serial] = nil
    if ok then notify(source, ('Skimmer now keeps %d%% of each card payment (was %d%%).'):format(cut, old), 'success') end
    return ok
end
function service.remove(source, entry)
    local record = Registry.get(entry.serial)
    local device = record and record.skimmer
    if not device or locks[entry.serial] or device.installer ~= Registry.identifierOf(source) then return false end
    locks[entry.serial] = true
    -- anything it copied stays on the device: use the item (or its Read button) to print it out
    local data = cardData(entry.serial, device)
    if data then
        data.label = ('Card skimmer (%d cards stored)'):format(data.cards)
        data.description = ('Holds card details copied from %d purchases. Use it to print them out.'):format(data.cards)
    end
    if not MetaComic.Inventory.add(source, SKIMMER_ITEM, 1, data) then locks[entry.serial] = nil; return false end
    local ok = write(record, 'skimmer', nil, 'Card skimmer removed', source)
    if not ok then MetaComic.Inventory.remove(source, SKIMMER_ITEM, 1, data and { dataId = data.dataId }) end
    locks[entry.serial] = nil
    if ok then
        Vending.broadcast(entry)
        if Vending.sendAccess then Vending.sendAccess(source) end
    end
    return ok
end
-- the owner, whoever controls the machine, managers or police check the coin panel: a skimmer they find comes off
-- (anything it held is lost) and goes to them as evidence (Skimmer.EvidenceItem, false = destroyed)
function service.inspect(source, entry)
    local record = Registry.get(entry.serial)
    if not record or locks[entry.serial] then return false end
    local device = record.skimmer
    if not device then
        notify(source, 'Nothing unusual on the coin panel.', 'info')
        return true
    end
    locks[entry.serial] = true
    local ok = write(record, 'skimmer', nil, 'Card skimmer found and removed', source)
    locks[entry.serial] = nil
    if not ok then return false end
    if skimmer.EvidenceItem ~= false then MetaComic.Inventory.add(source, skimmer.EvidenceItem or SKIMMER_ITEM, 1) end -- wiped: no card data
    Vending.broadcast(entry)
    local installer = device.installer and Registry.onlineSource and Registry.onlineSource(device.installer)
    if installer and Vending.sendAccess then Vending.sendAccess(installer) end
    notify(source, 'You found a card skimmer on the coin panel and removed it.', 'success')
    return true
end

-- Items: a removed skimmer with card data prints it out as a card data item; using the card data shows what it holds.
local reading, selling = {}, {}
local function useSkimmer(source, slot)
    local item = slot and MetaComic.Inventory.getSlot and MetaComic.Inventory.getSlot(source, tonumber(slot))
    if not item or item.name ~= SKIMMER_ITEM or reading[source] then return end
    local stored = item.metadata or item.info or {}
    if (tonumber(stored.cards) or 0) <= 0 or type(stored.dataId) ~= 'string' then return notify(source, 'This skimmer holds no card data.', 'inform') end
    reading[source] = true
    local data = MetaComic.CopyTable(stored)
    data.label = ('Card data (%d cards)'):format(tonumber(data.cards) or 0)
    data.description = ('Card details from %d purchases at vending machine %s. $%d skimmed, waiting to be recovered.'):format(tonumber(data.cards) or 0, data.serial or '?', tonumber(data.skimmed) or 0)
    local ok = MetaComic.Inventory.remove(source, SKIMMER_ITEM, 1, { dataId = stored.dataId }, tonumber(slot))
    if ok and not MetaComic.Inventory.add(source, DATA_ITEM, 1, data) then
        MetaComic.Inventory.add(source, SKIMMER_ITEM, 1, stored)
        ok = false
    end
    if ok then MetaComic.Inventory.add(source, SKIMMER_ITEM, 1) end -- the emptied skimmer can be fitted again
    reading[source] = nil
    notify(source, ok and ('You print the card details from %d purchases off the skimmer.'):format(tonumber(data.cards) or 0) or 'Could not read the skimmer.', ok and 'success' or 'error')
end
local function useData(source, slot)
    local item = slot and MetaComic.Inventory.getSlot and MetaComic.Inventory.getSlot(source, tonumber(slot))
    if not item or item.name ~= DATA_ITEM then return end
    local data = item.metadata or item.info or {}
    TriggerClientEvent('meta_comic:client:skimmerData', source, { cards = tonumber(data.cards) or 0, total = tonumber(data.total) or 0, skimmed = tonumber(data.skimmed) or 0,
        serial = data.serial, from = data.from, to = data.to, label = data.label })
end
RegisterNetEvent('meta_comic:server:useSkimmerItem', function(kind, slot)
    if kind == 'data' then useData(source, slot) else useSkimmer(source, slot) end
end)
if MetaComic.Framework.registerUsableItem and Config.Items.RegisterUsableItems ~= false then
    MetaComic.Framework.registerUsableItem(SKIMMER_ITEM, function(source, item) useSkimmer(source, item and item.slot) end)
    MetaComic.Framework.registerUsableItem(DATA_ITEM, function(source, item) useData(source, item and item.slot) end)
end

-- Card data buyers (Skimmer.Buyers): pay Percent of every copied purchase for all the card data the player carries.
local buyers = skimmer.Buyers or {}
local function buyerList() return buyers.Peds or (buyers.Ped and { buyers.Ped }) or {} end
RegisterNetEvent('meta_comic:server:sellCardData', function(index)
    local source = source
    local buyer = buyerList()[tonumber(index) or 0]
    if buyers.Enabled == false or skimmer.Enabled == false or not buyer or not buyer.coords or selling[source] then return end
    local ped = GetPlayerPed(source)
    local c = buyer.coords
    if not ped or ped == 0 or #(GetEntityCoords(ped) - vector3(c.x, c.y, c.z)) > (tonumber(buyers.Distance) or 2.0) + 3.0 then return end
    selling[source] = true
    local taken, cards, skimmed = {}, 0, 0
    for _, item in ipairs(MetaComic.Inventory.slotsOf and MetaComic.Inventory.slotsOf(source, DATA_ITEM) or {}) do
        local data = item.metadata or item.info or {}
        local count = math.max(1, tonumber(item.count or item.amount) or 1)
        if type(data.dataId) == 'string' and MetaComic.Inventory.remove(source, DATA_ITEM, count, { dataId = data.dataId }, item.slot) then
            taken[#taken + 1] = { count = count, data = data }
            cards = cards + (tonumber(data.cards) or 0) * count
            skimmed = skimmed + (tonumber(data.skimmed) or 0) * count
        end
    end
    -- the buyer recovers the skimmed money and gives the seller Percent of it
    local percent = math.max(0, math.min(100, tonumber(buyer.Percent or buyers.Percent) or 50))
    local payout = math.floor(skimmed * percent / 100)
    if #taken == 0 then
        notify(source, 'You have no card data to sell.', 'error')
    elseif payout > 0 and not MetaComic.Money.add(source, buyers.Account or 'cash', payout, 'card-data') then
        for _, back in ipairs(taken) do MetaComic.Inventory.add(source, DATA_ITEM, back.count, back.data) end
        notify(source, 'The buyer could not pay you.', 'error')
    else
        notify(source, ('The buyer recovered $%d from %d cards and paid you $%d.'):format(skimmed, cards, payout), 'success')
    end
    selling[source] = nil
end)

CreateThread(function()
    if gps.Enabled == false then return end
    while true do
        Wait(math.max(1000, tonumber(gps.CheckInterval) or 5000))
        for _, record in ipairs(Registry.all()) do
            if record.status == 'removed' or record.gpsDisabled then positions[record.serial] = nil end
            if record.status ~= 'removed' and not record.gpsDisabled then
                local coords, actor, how
                local entity = tracked[record.serial]
                if entity and DoesEntityExist(entity) then coords, how = GetEntityCoords(entity), record.worldState == 'towed' and 'towed' or 'ground'
                else
                    tracked[record.serial] = nil
                    local entry = Vending.bySerial(record.serial)
                    if entry then
                        coords = vector3(entry.x, entry.y, entry.z)
                        if not record.gpsOrigin then write(record, 'gpsOrigin', { x = entry.x, y = entry.y, z = entry.z }, 'GPS position initialized') end
                    elseif record.holder and record.holder.id then
                        actor = Registry.onlineSource(record.holder.id)
                        local ped = actor and GetPlayerPed(actor)
                        if ped and ped ~= 0 then coords, how = GetEntityCoords(ped), 'carried' end
                    end
                end
                if how and coords then
                    positions[record.serial] = { x = coords.x, y = coords.y, z = coords.z, at = os.time(), how = how,
                        holder = how == 'carried' and record.holder and record.holder.name or nil }
                elseif Vending.bySerial(record.serial) then
                    positions[record.serial] = nil -- standing again: the map shows it as a machine
                end
                local origin = record.gpsOrigin
                if coords and origin and #(coords - vector3(origin.x, origin.y, origin.z)) > math.max(0.1, tonumber(gps.MovementThreshold) or 2.0) then
                    local controller = Registry.controller(record)
                    local key = record.serial .. ':' .. tostring(controller)
                    if not alerted[key] or os.time() - alerted[key] >= math.max(1, tonumber(gps.Cooldown) or 60) then
                        alerted[key] = os.time()
                        local recipient = controller and Registry.onlineSource(controller)
                        if recipient and gps.NotifyController ~= false then
                            notify(recipient, ('GPS: vending machine %s moved from its registered spot. Location: %.1f, %.1f.'):format(record.serial, coords.x, coords.y), 'error')
                        end
                        local dispatchSource = actor or recipient or tonumber(GetPlayers()[1]) or 0
                        if MetaComic.Police then MetaComic.Police.alert(dispatchSource, { action = 'gps', stage = 'movement', serial = record.serial, coords = coords }) end
                    end
                end
            end
        end
    end
end)
