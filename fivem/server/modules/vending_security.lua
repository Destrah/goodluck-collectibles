-- GPS and skimmers are stored against the serial, so they follow inventory items and towing.
local cfg = Config.VendingMachines or {}
if cfg.Enabled == false then return end
local gps, skimmer = cfg.GPS or {}, cfg.Skimmer or {}
local Registry, Vending = MetaComic.VendingRegistry, MetaComic.Vending
local service = {}
MetaComic.VendingSecurity = service
local tracked, alerted, locks = {}, {}, {}

local function notify(source, message, kind)
    if MetaComic.Framework.notify then MetaComic.Framework.notify(source, message, kind) end
end
local function write(record, field, value, event, source)
    local old, history, updated = record[field], record.history, record.updatedAt
    record[field] = value
    record.history = MetaComic.CopyTable(history or {})
    table.insert(record.history, 1, { at = os.time(), event = event, by = source and Registry.nameOf(source) })
    local limit = math.max(1, tonumber((cfg.Ownership or {}).HistoryLength) or 25)
    while #record.history > limit do table.remove(record.history) end
    record.updatedAt = os.time()
    if Registry.save() then return true end
    record[field], record.history, record.updatedAt = old, history, updated
    return false
end
function service.track(serial, entity) if serial then tracked[serial] = entity end end
function service.gps(source, entry, enabled)
    if gps.Enabled == false or locks[entry.serial] then return false end
    local record = Registry.get(entry.serial)
    if not record or (enabled and not Vending.canControl(source, entry)) then return false end
    locks[entry.serial] = true
    local oldOrigin = record.gpsOrigin
    if enabled then record.gpsOrigin = { x = entry.x, y = entry.y, z = entry.z } end
    local ok = write(record, 'gpsDisabled', not enabled, enabled and 'GPS rearmed at this location' or 'GPS disabled', source)
    if not ok then record.gpsOrigin = oldOrigin end
    locks[entry.serial] = nil
    if ok then Vending.broadcast(entry); notify(source, enabled and 'GPS enabled at this spot.' or 'GPS disabled.', 'success') end
    return ok
end
function service.install(source, entry)
    local record = Registry.get(entry.serial)
    if skimmer.Enabled == false or not record or record.skimmer or locks[entry.serial] then return false end
    locks[entry.serial] = true
    local item = skimmer.Item or 'card_skimmer'
    if not MetaComic.Inventory.remove(source, item, 1) then locks[entry.serial] = nil; return false end
    local ok = write(record, 'skimmer', { installer = Registry.identifierOf(source), installedAt = os.time(), balance = 0, transactions = {} }, 'Card skimmer installed', source)
    if not ok then MetaComic.Inventory.add(source, item, 1) end
    locks[entry.serial] = nil
    if ok then Vending.broadcast(entry); notify(source, 'Card skimmer installed.', 'success') end
    return ok
end
function service.cardSale(entry, source, amount)
    while locks[entry.serial] do Wait(0) end -- preserve every card purchase while collection/save yields
    local record = Registry.get(entry.serial)
    local device = record and record.skimmer
    if skimmer.Enabled == false or not device then return amount end
    locks[entry.serial] = true
    local nextDevice = MetaComic.CopyTable(device)
    local mode = skimmer.Mode or 'record'
    local retained = mode == 'divert' and amount or mode == 'cut' and math.floor(amount * math.max(0, math.min(100, tonumber(skimmer.Percent) or 15)) / 100) or 0
    nextDevice.balance = (tonumber(device.balance) or 0) + retained
    nextDevice.transactions = nextDevice.transactions or {}
    table.insert(nextDevice.transactions, 1, { at = os.time(), amount = amount, retained = retained })
    while #nextDevice.transactions > math.max(1, tonumber(skimmer.MaxRecords) or 50) do table.remove(nextDevice.transactions) end
    local ok = write(record, 'skimmer', nextDevice, 'Card purchase recorded by skimmer')
    locks[entry.serial] = nil
    return ok and amount - retained or amount -- never take money if the skimmer write failed
end
function service.collect(source, entry)
    local record = Registry.get(entry.serial)
    local device = record and record.skimmer
    if not device or device.installer ~= Registry.identifierOf(source) or locks[entry.serial] then return false end
    locks[entry.serial] = true
    local amount = math.max(0, math.floor(tonumber(device.balance) or 0))
    local nextDevice = MetaComic.CopyTable(device)
    nextDevice.balance = 0
    local ok = write(record, 'skimmer', nextDevice, 'Skimmer funds collected', source)
    if ok and amount > 0 and not MetaComic.Money.add(source, (cfg.Ownership or {}).PayoutAccount or 'bank', amount, 'card-skimmer') then
        write(record, 'skimmer', device, 'Skimmer payout failed', source)
        ok = false
    end
    locks[entry.serial] = nil
    if ok then notify(source, ('Skimmer: %d recorded card purchases; $%d collected.'):format(#(device.transactions or {}), amount), 'success') end
    return ok
end
function service.remove(source, entry)
    local record = Registry.get(entry.serial)
    local device = record and record.skimmer
    if not device or locks[entry.serial] or (device.installer ~= Registry.identifierOf(source) and not Vending.canControl(source, entry)) then return false end
    if (tonumber(device.balance) or 0) > 0 then
        notify(source, 'The skimmer holds funds. Its installer must collect them before removal.', 'error')
        return false
    end
    locks[entry.serial] = true
    if not MetaComic.Inventory.add(source, skimmer.Item or 'card_skimmer', 1) then locks[entry.serial] = nil; return false end
    local ok = write(record, 'skimmer', nil, 'Card skimmer removed', source)
    if not ok then MetaComic.Inventory.remove(source, skimmer.Item or 'card_skimmer', 1) end
    locks[entry.serial] = nil
    if ok then Vending.broadcast(entry) end
    return ok
end

CreateThread(function()
    if gps.Enabled == false then return end
    while true do
        Wait(math.max(1000, tonumber(gps.CheckInterval) or 5000))
        for _, record in ipairs(Registry.all()) do
            if record.status ~= 'removed' and not record.gpsDisabled then
                local coords, actor
                local entity = tracked[record.serial]
                if entity and DoesEntityExist(entity) then coords = GetEntityCoords(entity)
                else
                    tracked[record.serial] = nil
                    local entry = Vending.bySerial(record.serial)
                    if entry then
                        coords = vector3(entry.x, entry.y, entry.z)
                        if not record.gpsOrigin then write(record, 'gpsOrigin', { x = entry.x, y = entry.y, z = entry.z }, 'GPS position initialized') end
                    elseif record.holder and record.holder.id then
                        actor = Registry.onlineSource(record.holder.id)
                        local ped = actor and GetPlayerPed(actor)
                        if ped and ped ~= 0 then coords = GetEntityCoords(ped) end
                    end
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
