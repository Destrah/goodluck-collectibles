-- Timed, incremental server payouts from an unlocked cabinet. No client tick can grant loot.
local cfg = Config.VendingMachines or {}
local crime = cfg.Crime or {}
local loot = (crime.BreakIn or {}).Loot or {}
if cfg.Enabled == false or crime.Enabled == false or loot.Enabled == false and (cfg.Keys or {}).Enabled ~= true then return end
local Registry, Vending = MetaComic.VendingRegistry, MetaComic.Vending
local service, sessions, players, locks = {}, {}, {}, {}
MetaComic.VendingLoot = service
local function notify(source, message, kind) if MetaComic.Framework.notify then MetaComic.Framework.notify(source, message, kind or 'info') end end
local function setting(name, fallback) return math.max(1, math.floor(tonumber(loot[name]) or fallback)) end
local function record(entry) return entry and Registry.get(entry.serial) end
function service.isOpen(entry)
    local r = record(entry)
    return r ~= nil and not r.securitySeal and (tonumber(r.unlockedUntil) or 0) > os.time()
end
function service.busy(entry) return entry and (sessions[entry.serial] ~= nil or locks[entry.serial] == true) end
-- broken into, or its door stands open for any other reason (unlocked with a key, being serviced): anyone there can
-- take the stock, and the cash too once the cash box is open (a padlocked box gives the same choices as a break-in)
function service.lootable(entry)
    if service.isOpen(entry) then return true end
    local r = record(entry)
    local cashbox = MetaComic.VendingCashbox
    return r ~= nil and not r.securitySeal and cashbox ~= nil and cashbox.cabinetOpen ~= nil and cashbox.cabinetOpen(entry.id) == true
end
local function permitted(source, entry)
    if not service.lootable(entry) or not Vending.near(source, entry, Vending.reach()) then return false end
    return crime.OwnersCanRob or Registry.controller(record(entry)) ~= Registry.identifierOf(source)
end
local function stock(entry)
    local total = 0
    for _, product in ipairs(entry.products or {}) do total = total + math.max(0, tonumber(product.stock) or 0) end
    return total
end
local function level(amount, thresholds)
    if amount <= 0 then return 'empty' end
    thresholds = thresholds or {}
    if amount <= (tonumber(thresholds[1]) or 10) then return 'low' end
    if amount <= (tonumber(thresholds[2]) or 40) then return 'medium' end
    return 'high'
end
function service.stop(source, reason)
    local job = players[source]
    if not job then return end
    players[source] = nil
    if sessions[job.serial] == job then sessions[job.serial] = nil end
    job.canceled = true
    TriggerClientEvent('meta_comic:client:lootStopped', source, reason or 'Looting stopped.')
    TriggerEvent('meta_comic:server:vendingLootStopped', source) -- lets the door close
end
local function active(job)
    local entry = Vending.get(job.id)
    local ped = GetPlayerPed(job.source)
    if ped == 0 or not DoesEntityExist(ped) or GetEntityHealth and GetEntityHealth(ped) <= 100 then return false end
    -- hit while looting (an owner or employee stepping in): stop
    if job.health and GetEntityHealth and GetEntityHealth(ped) < job.health then job.interrupted = true; return false end
    return not job.canceled and sessions[job.serial] == job and entry and entry.serial == job.serial
        and Registry.identifierOf(job.source) == job.identifier and permitted(job.source, entry)
end
function service.inspect(source, entry)
    if loot.Enabled == false then return end
    if not permitted(source, entry) then return end
    local cash, quantity = math.max(0, entry.cash or 0), stock(entry)
    local stockMs = 0
    for _, product in ipairs(entry.products or {}) do stockMs = stockMs + math.ceil(product.stock / setting('StockBatch', 1)) * setting('StockBatchMs', 5000) end
    TriggerClientEvent('meta_comic:client:lootInspect', source, {
        id = entry.id, cash = level(cash, loot.CashLevels or { 500, 2000 }), stock = level(quantity, loot.StockLevels),
        cashMs = math.ceil(cash / setting('CashBatch', 100)) * setting('CashBatchMs', 4000),
        stockMs = stockMs,
        unlockedUntil = record(entry).unlockedUntil,
        -- padlocked cash box (server/modules/vending_door.lua): the menu explains it and offers to break the padlock
        cashLocked = MetaComic.VendingCashbox ~= nil and not MetaComic.VendingCashbox.allows(entry, 'cash') or nil,
    })
end
function service.unlock(source, entry)
    if service.isOpen(entry) then service.inspect(source, entry); return true end
    local r = record(entry)
    if MetaComic.VendingKeys and (not MetaComic.VendingKeys.ensure(r) or MetaComic.VendingKeys.busy(entry)) then return false end
    if not r or locks[entry.serial] then return false end
    locks[entry.serial] = true
    local old = MetaComic.CopyTable(r)
    local opened = { id = Registry.identifierOf(source), at = os.time() }
    local fields = { unlockedUntil = os.time() + setting('UnlockSeconds', 600), unlockedBy = opened }
    if MetaComic.VendingKeys then fields.lockCondition = 'damaged'; fields.securitySeal = false; fields.lockRevision = (r.lockRevision or 0) + 1 end
    Registry.update(entry.serial, fields, 'Cabinet forced open', Registry.nameOf(source))
    if not Registry.save() then
        for key in pairs(r) do r[key] = nil end
        for key, value in pairs(old) do r[key] = value end
        locks[entry.serial] = nil
        return false
    end
    entry.openedBy = opened
    locks[entry.serial] = nil
    Vending.broadcast(entry)
    service.inspect(source, entry)
    return true
end
function service.canSecure(source, entry)
    local s = crime.Secure or {}
    local r = record(entry)
    if s.Enabled == false or not r or not (service.isOpen(entry) or MetaComic.VendingKeys and r.lockCondition == 'damaged' and not r.securitySeal) then return false end
    if MetaComic.VendingKeys and MetaComic.VendingKeys.busy(entry) then return false end
    if Vending.isTransferringStock and Vending.isTransferringStock(entry) then return false end
    local access = MetaComic.VendingKeys and (cfg.Keys or {}).SecureAccess or s.Access or 'anyone'
    local police = MetaComic.Police and MetaComic.Police.isPolice and MetaComic.Police.isPolice(source)
    local controller = MetaComic.VendingKeys and MetaComic.VendingKeys.authority(source, r) or not MetaComic.VendingKeys and Vending.canControl(source, entry)
    return access == 'anyone' or access == 'police' and police or access == 'controllers' and controller
        or access == 'police_or_controllers' and (police or controller)
end
function service.secure(source, entry)
    if not service.canSecure(source, entry) or not Vending.near(source, entry, Vending.reach()) then return false end
    local job = sessions[entry.serial]
    if job then service.stop(job.source, 'Someone secured the vending machine.') end
    while locks[entry.serial] do Wait(0) end
    if not service.canSecure(source, entry) or not Vending.near(source, entry, Vending.reach()) then return false end
    locks[entry.serial] = true
    local r = record(entry)
    local old = MetaComic.CopyTable(r)
    -- who chained it shows on the machine ("secured with a chain and padlock by the police")
    local police = MetaComic.Police and MetaComic.Police.isPolice and MetaComic.Police.isPolice(source)
    local kind = police and 'police' or (r.owner and r.owner == Registry.identifierOf(source)) and 'owner' or Vending.canManage(source) and 'business' or nil
    local fields = MetaComic.VendingKeys and MetaComic.VendingKeys.sealFields(r, Registry.nameOf(source), kind) or { unlockedUntil = false, unlockedBy = false }
    Registry.update(entry.serial, fields, MetaComic.VendingKeys and 'Chain and padlock fitted; cylinder still damaged' or 'Cabinet secured', Registry.nameOf(source))
    if not Registry.save() then
        for key in pairs(r) do r[key] = nil end
        for key, value in pairs(old) do r[key] = value end
        locks[entry.serial] = nil
        return false
    end
    entry.openedBy = nil
    locks[entry.serial] = nil
    Vending.broadcast(entry)
    return true
end
RegisterNetEvent('meta_comic:server:lootInspect', function(id)
    if MetaComic.VendingCrimeBusy and MetaComic.VendingCrimeBusy(source) then return end
    local entry = Vending.get(id)
    if entry then
        if not service.lootable(entry) then return notify(source, 'This machine is secured.') end
        service.inspect(source, entry)
    end
end)
RegisterNetEvent('meta_comic:server:lootCancel', function() service.stop(source) end)
AddEventHandler('playerDropped', function() service.stop(source) end)
AddEventHandler('onResourceStop', function(name)
    if name == GetCurrentResourceName() then for source in pairs(players) do service.stop(source) end end
end)
RegisterNetEvent('meta_comic:server:lootStart', function(id, mode)
    if loot.Enabled == false then return end
    local source = source
    local entry = Vending.get(id)
    if mode ~= 'cash' and mode ~= 'stock' and mode ~= 'both' then return end
    if entry and MetaComic.VendingCashbox and not MetaComic.VendingCashbox.allows(entry, mode) then
        if mode == 'cash' then return notify(source, 'The cash box is still padlocked. Break the padlock first.', 'error') end
        mode = 'stock' -- the cash box is padlocked: only the cards come out
    end
    if not entry or not permitted(source, entry) or players[source] or service.busy(entry)
        or Vending.isTransferringStock and Vending.isTransferringStock(entry)
        or MetaComic.VendingCrimeBusy and MetaComic.VendingCrimeBusy(source) then return end
    local ped = GetPlayerPed(source)
    local job = { source = source, id = entry.id, serial = entry.serial, identifier = Registry.identifierOf(source), mode = mode, nextKind = 'cash',
        health = ped ~= 0 and GetEntityHealth and GetEntityHealth(ped) or nil }
    sessions[entry.serial], players[source] = job, job
    if MetaComic.CrimeEvidence then MetaComic.CrimeEvidence.start(source, entry, 'loot') end
    TriggerEvent('meta_comic:server:vendingDoorSuccess', source, entry.id, 'loot')
    TriggerClientEvent('meta_comic:client:lootStarted', source, { id = entry.id, mode = mode, animation = loot.Visuals and loot.Visuals.Enabled == false and (crime.BreakIn or {}).Animation or nil })
    CreateThread(function()
        while active(job) do
            local entry = Vending.get(job.id)
            local hasCash = (entry.cash or 0) > 0 and mode ~= 'stock'
            local hasStock = stock(entry) > 0 and mode ~= 'cash'
            if not hasCash and not hasStock then break end
            -- taking both: pick cash or stock at random each batch (with a lean towards repeating the last one)
            local kind
            if hasCash and hasStock then
                kind = math.random(100) <= (job.lastKind and 65 or 50) and (job.lastKind or 'cash') or (job.lastKind == 'cash' and 'stock' or 'cash')
            else kind = hasCash and 'cash' or 'stock' end
            job.lastKind = kind
            local duration = kind == 'cash' and setting('CashBatchMs', 4000) or setting('StockBatchMs', 5000)
            local deadline = GetGameTimer() + duration
            local productKind
            if kind == 'stock' then
                for _, product in ipairs(entry.products or {}) do
                    if product.stock > 0 then productKind = product.kind; break end
                end
            end
            TriggerClientEvent('meta_comic:client:lootBatch', source, { duration = duration, kind = kind, productKind = productKind })
            repeat Wait(math.min(200, duration)) until not active(job) or GetGameTimer() >= deadline
            if not active(job) then break end
            locks[job.serial] = true
            local product, amount, old
            if kind == 'cash' then
                old = entry.cash or 0
                amount = math.min(old, setting('CashBatch', 100))
                entry.cash = old - amount
            else
                for _, candidate in ipairs(entry.products or {}) do if candidate.stock > 0 then product = candidate; break end end
                if product then old = product.stock; amount = math.min(old, setting('StockBatch', 1)); product.stock = old - amount end
            end
            local saveOk, saveResult = false, false
            if amount and amount > 0 then saveOk, saveResult = pcall(Vending.save, entry) end
            local saved = saveOk and saveResult == true
            local given = false
            if saved and active(job) then
                local ok, result
                if kind == 'stock' then ok, result = pcall(Vending.giveSealed, source, product.kind, product.set, amount)
                else
                    local reward = crime.BreakIn or {}
                    if reward.RewardItem then ok, result = pcall(MetaComic.Inventory.add, source, reward.RewardItem, amount, reward.RewardMetadata)
                    else ok, result = pcall(MetaComic.Money.add, source, reward.RewardAccount or 'cash', amount, 'vending looting') end
                end
                given = ok and result == true
            end
            if not given then
                if kind == 'cash' and old then entry.cash = old elseif product then product.stock = old end
                if saved then pcall(Vending.save, entry) end
            end
            locks[job.serial] = nil
            Vending.broadcast(entry)
            if not given then notify(source, 'Looting stopped; the unfinished batch was not taken.'); break end
            TriggerClientEvent('meta_comic:client:lootReward', source, { kind = kind, amount = amount })
        end
        if players[source] == job then service.stop(source, job.interrupted and 'You were hit and stopped looting. Completed batches are yours.' or 'Looting stopped. Completed batches are yours.') end
    end)
end)

CreateThread(function()
    while true do
        Wait(2000)
        for _, r in ipairs(Registry.all()) do
            if r.unlockedUntil and r.unlockedUntil <= os.time() then
                local job = sessions[r.serial]
                if job then service.stop(job.source, MetaComic.VendingKeys and 'The automatic security seal closed the cabinet.' or 'The vending machine locked again.') end
                while locks[r.serial] do Wait(0) end
                -- Recheck after a yielding loot transaction; a fresh break-in may have extended the deadline.
                if r.unlockedUntil and r.unlockedUntil <= os.time() then
                    locks[r.serial] = true
                    local old = MetaComic.CopyTable(r)
                    local fields = MetaComic.VendingKeys and MetaComic.VendingKeys.sealFields(r) or { unlockedUntil = false, unlockedBy = false }
                    Registry.update(r.serial, fields, MetaComic.VendingKeys and 'Automatic chain and padlock fitted; cylinder still damaged' or 'Cabinet unlock expired')
                    if not Registry.save() then
                        for k in pairs(r) do r[k] = nil end
                        for k, v in pairs(old) do r[k] = v end
                    end
                    locks[r.serial] = nil
                end
                local entry = Vending.bySerial(r.serial)
                if entry then
                    if not r.unlockedUntil then entry.openedBy = nil end
                    Vending.broadcast(entry)
                end
            end
        end
    end
end)
