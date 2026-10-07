-- The criminal side of vending machines (Config.VendingMachines.Crime):
--   breakin  unlock the cabinet for inspection and timed looting (legacy immediate rewards are opt-in)
--   hack     reroute the machine's card payments to the hacker's own account (and take the machine over)
--   steal    unbolt a machine that was just broken into and carry it away as an item. It keeps its serial, so it still
--            pays its owner wherever it is set up again, until someone hacks it
-- Each needs its items (Items), passes its minigames (client/minigames.lua, Config.Minigames), plays its animation for
-- Duration ms, and may alert the police (Config.Police). The server checks the items, distance, police count and
-- cooldowns when it starts, and that the full time passed when it finishes.
local cfg = Config.VendingMachines or {}
local crime = cfg.Crime or {}
if cfg.Enabled == false or crime.Enabled == false then return end
local Registry = MetaComic.VendingRegistry
local Vending = MetaComic.Vending
local ACTIONS = { breakin = 'BreakIn', hack = 'Hack', fullhack = 'FullHack', steal = 'Steal', disablegps = 'DisableGPS', enablegps = 'EnableGPS',
    installskimmer = 'InstallSkimmer', collectskimmer = 'CollectSkimmer', removeskimmer = 'RemoveSkimmer', replaceboard = 'ReplaceBoard', secure = 'Secure',
    inspectpanel = 'InspectPanel', adjustskimmer = 'AdjustSkimmer' }
local pending, cooldowns = {}, {}
MetaComic.VendingCrimeBusy = function(source) return pending[source] ~= nil end

local function notify(source, message, notifyType)
    if MetaComic.Framework.notify then MetaComic.Framework.notify(source, message, notifyType) end
end
local function settings(action) local key = ACTIONS[action]; return key and type(crime[key]) == 'table' and crime[key] or nil end
local function count(source, item) return MetaComic.Inventory.count and MetaComic.Inventory.count(source, item) or 0 end
local function itemsOf(action)
    if action == 'installskimmer' then return { { item = (cfg.Skimmer or {}).Item or 'card_skimmer', label = 'card skimmer', count = 1 } } end
    return type(settings(action).Items) == 'table' and settings(action).Items or {}
end
local function itemName(entry) return type(entry) == 'table' and entry.item or entry end
local function missingItem(source, action)
    for _, entry in ipairs(itemsOf(action)) do
        local needed = type(entry) == 'table' and tonumber(entry.count) or 1
        if count(source, itemName(entry)) < needed then return type(entry) == 'table' and entry.label or itemName(entry) end
    end
end
local function cooldownKey(entry, action) return ('%s:%s'):format(entry.serial or entry.id, action) end
-- fitting / reading / removing a skimmer and checking the coin panel never put the machine on a tamper cooldown
local function noCooldown(action) return action:find('skimmer') ~= nil or action == 'inspectpanel' end
local function coords(entry) return vector3(entry.x, entry.y, entry.z) end

RegisterNetEvent('meta_comic:server:crimeStart', function(id, action, option)
    local source = source
    local s = settings(action)
    local entry = Vending.get(id)
    if not s or s.Enabled == false or not entry or pending[source] then return end
    if not Vending.near(source, entry, Vending.reach()) then return notify(source, 'You need to stand at the vending machine.', 'error') end
    local record = Registry.get(entry.serial)
    local keys = MetaComic.VendingKeys
    if keys and (not keys.ensure(record) or keys.busy(entry)) then return notify(source, 'The cabinet lock is being serviced.', 'error') end
    local looting = MetaComic.VendingLoot
    if action == 'breakin' and (s.Loot or {}).Enabled ~= false and not looting then
        return notify(source, 'Timed looting is unavailable. Ask staff to check server/modules/vending_loot.lua in fxmanifest.lua.', 'error')
    end
    if Vending.isTransferringStock and Vending.isTransferringStock(entry) then return end
    if looting and looting.busy(entry) and action ~= 'secure' then return notify(source, 'Someone is looting this machine.', 'error') end
    if action == 'secure' and (not looting or not looting.canSecure(source, entry)) then return end
    -- already open (broken into, or unlocked with a key): go straight to the inspect / loot menu
    if action == 'breakin' and looting and (looting.lootable or looting.isOpen)(entry) then return looting.inspect(source, entry) end
    local maintenance = action == 'disablegps' or action == 'enablegps' or action == 'collectskimmer' or action == 'removeskimmer' or action == 'replaceboard' or action == 'secure' or action == 'inspectpanel' or action == 'adjustskimmer'
    local criminal = action ~= 'enablegps' and action ~= 'collectskimmer' and action ~= 'removeskimmer' and action ~= 'replaceboard' and action ~= 'secure' and action ~= 'inspectpanel' and action ~= 'adjustskimmer'
    -- checking the coin panel for a skimmer: the owner, whoever controls the machine, managers and police
    if action == 'inspectpanel' and not (Vending.canControl(source, entry) or Vending.businessStaff and Vending.businessStaff(source, entry)
        or MetaComic.Police and MetaComic.Police.isPolice and MetaComic.Police.isPolice(source)) then return end
    if action == 'replaceboard' and (not record or not Registry.systemController(record) or not (record.owner == Registry.identifierOf(source) or Vending.canManage(source))) then return end
    if action ~= 'fullhack' and not maintenance and not crime.OwnersCanRob and Registry.controller(record) == Registry.identifierOf(source) then return notify(source, 'This is your own machine.', 'error') end
    if action == 'disablegps' and ((cfg.GPS or {}).Enabled == false or record and record.gpsDisabled) then return end
    if action == 'enablegps' and ((cfg.GPS or {}).Enabled == false or not (record and record.gpsDisabled) or not Vending.canControl(source, entry)) then return end
    if action:find('skimmer') then
        if (cfg.Skimmer or {}).Enabled == false then return end
        local device = record and record.skimmer
        if action == 'installskimmer' and device then return notify(source, 'There is no room on this coin panel.', 'error') end
        if action ~= 'installskimmer' and not device then return end
        -- only the installer reads or removes it; owners and police find it with 'inspectpanel'
        if action ~= 'installskimmer' and device.installer ~= Registry.identifierOf(source) then return end
    end
    if action == 'fullhack' and record and (record.owner == Registry.identifierOf(source) or Registry.systemController(record) ~= nil) then return end
    -- hacks need the machine open (broken into or unlocked) and its cash box open
    local cashbox = MetaComic.VendingCashbox
    if (action == 'hack' or action == 'fullhack') and cashbox and cashbox.hackReady and not cashbox.hackReady(entry) then
        return notify(source, 'Open the machine and its cash box first.', 'error')
    end
    local missing = missingItem(source, action)
    if missing then return notify(source, ('You need a %s.'):format(missing), 'error') end
    local minPolice = tonumber(s.MinPolice or crime.MinPolice) or 0
    if minPolice > 0 and MetaComic.Police and MetaComic.Police.count() < minPolice then return notify(source, 'This is not possible right now.', 'error') end
    local until_ = not noCooldown(action) and cooldowns[cooldownKey(entry, action)]
    if until_ and os.time() < until_ then return notify(source, s.CooldownMessage or 'This machine was tampered with recently. Try again later.', 'error') end
    if action == 'breakin' and not looting and (entry.cash or 0) < (tonumber(s.MinCash) or 0) and (tonumber(s.StockChance) or 0) <= 0 then
        return notify(source, 'There is nothing worth taking.', 'error')
    end
    -- the bolts are inside: the machine has to be open, whether broken into or unlocked with a key, by anyone
    if action == 'steal' and s.NeedsBreakIn ~= false and looting and not (looting.lootable or looting.isOpen)(entry) then
        return notify(source, 'Open the machine first to get at its bolts.', 'error')
    end
    if action == 'steal' and s.NeedsGPSDisabled == true and (cfg.GPS or {}).Enabled ~= false and not (record and record.gpsDisabled) then
        return notify(source, 'Disable the machine GPS before unbolting it.', 'error')
    end
    local token = ('%d-%d'):format(source, GetGameTimer())
    local duration = math.max(1000, math.floor(tonumber(s.Duration) or 8000))
    local minigame = s.Minigame
    if action == 'breakin' and keys and record.securitySeal then
        local seal = (cfg.Keys or {}).Seal or {}
        duration = duration + math.max(1000, tonumber(seal.BreakDuration) or 20000)
        minigame = {}
        if seal.Minigame then minigame[#minigame + 1] = seal.Minigame end
        for _, game in ipairs(type(s.Minigame) == 'table' and s.Minigame or { s.Minigame }) do minigame[#minigame + 1] = game end
    end
    pending[source] = { token = token, id = entry.id, serial = entry.serial, revision = record and record.lockRevision, action = action, startedAt = GetGameTimer(), duration = duration,
        percent = (action == 'installskimmer' or action == 'adjustskimmer') and MetaComic.VendingSecurity.cutOf(type(option) == 'table' and option.percent) or nil }
    if criminal and MetaComic.Police then MetaComic.Police.alert(source, { action = action, stage = 'start', coords = coords(entry), serial = entry.serial }) end
    if MetaComic.CrimeEvidence then MetaComic.CrimeEvidence.start(source, entry, action) end
    TriggerClientEvent('meta_comic:client:crimeStart', source, {
        token = token, id = entry.id, action = action, label = s.ProgressLabel or s.Label, duration = duration,
        minigame = minigame, animation = s.Animation, minigameFirst = s.MinigameFirst ~= false,
    })
end)

RegisterNetEvent('meta_comic:server:crimeCancel', function() pending[source] = nil end)
AddEventHandler('playerDropped', function() pending[source] = nil end)

local function breakTools(source, action)
    for _, entry in ipairs(itemsOf(action)) do
        if type(entry) == 'table' and (tonumber(entry.breakChance) or 0) > 0 and math.random() * 100 < tonumber(entry.breakChance) then
            if MetaComic.Inventory.remove(source, entry.item, 1) then notify(source, ('Your %s broke.'):format(entry.label or entry.item), 'error') end
        end
    end
end
local function useUpItems(source, action)
    for _, entry in ipairs(itemsOf(action)) do
        if type(entry) == 'table' and entry.remove then MetaComic.Inventory.remove(source, entry.item, tonumber(entry.count) or 1) end
    end
end

local handlers = {}
function handlers.breakin(source, entry, s)
    if (s.Loot or {}).Enabled ~= false then
        if not MetaComic.VendingLoot then
            return notify(source, 'Timed looting is unavailable. Ask staff to check server/modules/vending_loot.lua in fxmanifest.lua.', 'error')
        end
        return MetaComic.VendingLoot.unlock(source, entry)
    end
    local cash = entry.cash or 0
    local taken = math.floor(cash * math.max(0, math.min(100, tonumber(s.TakePercent) or 100)) / 100)
    local grabbed = {}
    entry.cash = cash - taken
    for _, product in ipairs(entry.products) do
        if product.stock > 0 and math.random() * 100 < (tonumber(s.StockChance) or 0) then
            local amount = math.random(1, math.max(1, math.min(product.stock, tonumber(s.StockMax) or 1)))
            product.stock = product.stock - amount
            grabbed[#grabbed + 1] = { product = product, amount = amount }
        end
    end
    entry.openedBy = { id = Registry.identifierOf(source), at = os.time() }
    if not Vending.save(entry) then
        entry.cash = cash
        for _, grab in ipairs(grabbed) do grab.product.stock = grab.product.stock + grab.amount end
        return notify(source, 'The cash box jammed.', 'error')
    end
    if taken > 0 then
        if s.RewardItem then MetaComic.Inventory.add(source, s.RewardItem, taken, s.RewardMetadata)
        else MetaComic.Money.add(source, s.RewardAccount or 'cash', taken, 'vending break-in') end
    end
    for _, grab in ipairs(grabbed) do Vending.giveSealed(source, grab.product.kind, grab.product.set, grab.amount) end
    local fields
    if MetaComic.VendingKeys then
        local record = Registry.get(entry.serial)
        fields = { unlockedUntil = os.time() + math.max(1, tonumber((s.Loot or {}).UnlockSeconds) or 600), unlockedBy = entry.openedBy,
            lockCondition = 'damaged', securitySeal = false, lockRevision = (record.lockRevision or 0) + 1 }
    end
    Registry.update(entry.serial, fields, taken > 0 and ('Broken into: $%d cash taken'):format(taken) or 'Broken into')
    Vending.broadcast(entry)
    local stock = #grabbed > 0 and ' and some stock' or ''
    notify(source, taken > 0 and ('You took $%d%s.'):format(taken, stock) or (#grabbed > 0 and 'You grabbed some stock. The cash box was empty.' or 'The cash box was empty.'), taken > 0 and 'success' or 'info')
    return true
end
function handlers.hack(source, entry, s)
    local hours = tonumber(s.Hours) or 0
    Registry.update(entry.serial, {
        routing = { id = Registry.identifierOf(source), name = Registry.nameOf(source), number = Registry.newRouting() },
        tampered = true, routingUntil = hours > 0 and os.time() + math.floor(hours * 3600) or false,
    }, 'Payment routing changed')
    Vending.sendAccessAll() -- the hacker can run the machine now
    notify(source, hours > 0 and ('Card payments from this machine come to you for %s hour%s.'):format(hours, hours == 1 and '' or 's')
        or 'Card payments from this machine come to you now. You can manage it too.', 'success')
    return true
end
function handlers.fullhack(source, entry, s)
    local id = Registry.identifierOf(source)
    local record = Registry.get(entry.serial)
    if not record then return false end
    local old = MetaComic.CopyTable(record)
    Registry.update(entry.serial, {
        systemController = id, systemUntil = false,
    }, 'Operating system taken over')
    if not Registry.save() then
        for key in pairs(record) do record[key] = nil end
        for key, value in pairs(old) do record[key] = value end
        notify(source, 'Could not save the operating-system takeover. Try again later.', 'error')
        return false
    end
    Vending.sendAccessAll()
    Vending.broadcast(entry)
    notify(source, 'Operating system taken over. Manage the machine to switch GPS or choose the payment recipient.', 'success')
    return true
end
function handlers.steal(source, entry, s)
    -- Recheck prerequisites at completion: GPS may be rearmed during drilling,
    -- and a break-in window can expire during the longer theft attempt.
    local record = Registry.get(entry.serial)
    if s.NeedsGPSDisabled == true and (cfg.GPS or {}).Enabled ~= false and not (record and record.gpsDisabled) then
        return notify(source, 'The machine GPS is active. Theft stopped.', 'error')
    end
    local looting = MetaComic.VendingLoot
    if s.NeedsBreakIn ~= false and looting and not (looting.lootable or looting.isOpen)(entry) then
        return notify(source, 'The machine was shut. Theft stopped.', 'error')
    end
    local ok, err = Vending.pickUp(source, entry, 'stolen', 'Stolen')
    if not ok then return notify(source, err, 'error') end
    notify(source, ('You unbolted vending machine %s.'):format(entry.serial), 'success')
    return true
end
function handlers.disablegps(source, entry) return MetaComic.VendingSecurity.gps(source, entry, false) end
function handlers.secure(source, entry) return MetaComic.VendingLoot and MetaComic.VendingLoot.secure(source, entry) end
function handlers.replaceboard(source, entry)
    local record = Registry.get(entry.serial)
    if not record or not Registry.systemController(record) or not (record.owner == Registry.identifierOf(source) or Vending.canManage(source)) then return false end
    local item = ((crime.ReplaceBoard or {}).Items or {})[1]
    local name = item and itemName(item) or 'vending_control_board'
    local count_ = type(item) == 'table' and tonumber(item.count) or 1
    if not MetaComic.Inventory.remove(source, name, count_ or 1) then return false end
    local old = MetaComic.CopyTable(record)
    Registry.update(entry.serial, { systemController = false, systemUntil = false, routing = false, routingUntil = false, tampered = false,
        gpsDisabled = false, gpsOrigin = { x = entry.x, y = entry.y, z = entry.z } }, 'Control board physically replaced', Registry.nameOf(source))
    if not Registry.save() then
        for key in pairs(record) do record[key] = nil end
        for key, value in pairs(old) do record[key] = value end
        MetaComic.Inventory.add(source, name, count_ or 1)
        return false
    end
    Vending.sendAccessAll()
    Vending.broadcast(entry)
    notify(source, 'Control board replaced. Owner control and payment routing restored; GPS rearmed.', 'success')
    return true
end
function handlers.enablegps(source, entry) return MetaComic.VendingSecurity.gps(source, entry, true) end
function handlers.installskimmer(source, entry, _, job) return MetaComic.VendingSecurity.install(source, entry, job and job.percent) end
function handlers.adjustskimmer(source, entry, _, job) return MetaComic.VendingSecurity.adjust(source, entry, job and job.percent) end
function handlers.collectskimmer(source, entry) return MetaComic.VendingSecurity.collect(source, entry) end
function handlers.removeskimmer(source, entry) return MetaComic.VendingSecurity.remove(source, entry) end
function handlers.inspectpanel(source, entry) return MetaComic.VendingSecurity.inspect(source, entry) end

RegisterNetEvent('meta_comic:server:crimeFinish', function(token, success)
    local source = source
    local job = pending[source]
    pending[source] = nil
    if not job or job.token ~= token then return end
    local s = settings(job.action)
    local entry = Vending.get(job.id)
    if not entry then return notify(source, 'That vending machine is gone.', 'error') end
    if MetaComic.VendingKeys then
        local record = Registry.get(entry.serial)
        if entry.serial ~= job.serial or MetaComic.VendingKeys.busy(entry) or not record or record.lockRevision ~= job.revision then
            return notify(source, 'The cabinet security changed. Start a new attempt.', 'error')
        end
    end
    if Vending.isTransferringStock and Vending.isTransferringStock(entry) then return notify(source, 'The machine is busy. Start a new attempt.', 'error') end
    local key = cooldownKey(entry, job.action)
    if not Vending.near(source, entry, Vending.reach() + 2.0) then return notify(source, 'You moved away from the machine.', 'error') end
    if success ~= true then
        if MetaComic.CrimeEvidence then MetaComic.CrimeEvidence.failure(source, entry, job.action) end
        breakTools(source, job.action)
        if not noCooldown(job.action) then cooldowns[key] = os.time() + math.floor(tonumber(s.FailCooldown) or 30) end
        if MetaComic.Police then MetaComic.Police.alert(source, { action = job.action, stage = 'fail', coords = coords(entry), serial = entry.serial }) end
        Registry.update(entry.serial, nil, ({ breakin = 'Failed break-in attempt', hack = 'Failed hacking attempt', steal = 'Failed theft attempt' })[job.action] or ('Failed ' .. job.action .. ' attempt'))
        return notify(source, s.FailMessage or 'You failed.', 'error')
    end
    if GetGameTimer() - job.startedAt < job.duration - 750 then return notify(source, 'You stopped too early.', 'error') end
    local cashbox = MetaComic.VendingCashbox
    if (job.action == 'hack' or job.action == 'fullhack') and cashbox and cashbox.hackReady and not cashbox.hackReady(entry) then
        return notify(source, 'The cash box was shut before you finished.', 'error')
    end
    local missing = missingItem(source, job.action)
    if missing then return notify(source, ('You need a %s.'):format(missing), 'error') end
    if handlers[job.action](source, entry, s, job) then
        useUpItems(source, job.action)
        if not noCooldown(job.action) then cooldowns[key] = os.time() + math.floor(tonumber(s.Cooldown) or 600) end
        if MetaComic.Police and job.action ~= 'inspectpanel' then MetaComic.Police.alert(source, { action = job.action, stage = 'success', coords = coords(entry), serial = entry.serial }) end
        TriggerEvent('meta_comic:server:vendingDoorSuccess', source, entry.id, 'crime', job.action) -- the door opens on success only
    end
end)
