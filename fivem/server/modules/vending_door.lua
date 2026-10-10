-- Vending machine front door (Config.VendingMachines.Door): the door swings open for everyone nearby while someone
-- restocks, unlocks the cabinet with a key (or rekeys it), loots it or breaks in / unbolts it, so other players can see the machine is being
-- worked on. This file only listens to the events the other vending modules already handle (they still do every
-- check); it keeps which doors are open and tells the clients, which swap the machine for the body + door models.
local cfg = Config.VendingMachines or {}
local door = cfg.Door or {}
if cfg.Enabled == false or door.Enabled == false then return end
local Vending = MetaComic.Vending
local open = {}      -- machine id -> { until = os.time() (nil while held), holders = { [source] = true } }
local refreshLids
local closeCabinet
local holding = {}   -- source -> machine id it keeps open (crime / looting until it ends)
local closing, ajar = {}, {}
local manuallyClosed = {} -- a damaged lock cannot lock; closing its door only changes its position

local function seconds(key, default) return math.max(1, tonumber(door[key]) or default) end
local function observation(id, text, actor)
    local entry = Vending.get(id)
    if entry then MetaComic.VendingRegistry.sensor(entry.serial, text, actor) end
end
local function send(id, isOpen, actor)
    observation(id, isOpen and 'Main door opened' or 'Main door closed', actor)
    TriggerClientEvent('meta_comic:client:vendingDoor', -1, id, isOpen)
end

local function setOpen(id, untilAt, source, actor)
    local entry = Vending.get(id)
    local record = entry and MetaComic.VendingRegistry.get(entry.serial)
    if record and (record.padlock or record.securitySeal) then return end
    manuallyClosed[id] = nil
    local state = open[id]
    if not state then state = { holders = {} }; open[id] = state; send(id, true, actor or source) end
    if source then state.holders[source] = true; holding[source] = id end
    if untilAt then state['until'] = math.max(state['until'] or 0, untilAt) end
end
local function release(source)
    local id = holding[source]
    holding[source] = nil
    local state = id and open[id]
    if not state then return end
    state.holders[source] = nil
    state['until'] = math.max(state['until'] or 0, os.time() + seconds('CloseDelay', 2))
end

-- someone at the machine: opened for `secs`, or held open by `source` until release (capped by MaxSeconds)
local function trigger(source, id, secs, hold)
    local entry = Vending.get(id)
    if not entry or not Vending.near(source, entry, Vending.reach() + 1.0) then return end
    local record = MetaComic.VendingRegistry.get(entry.serial)
    if record and record.padlock then return end
    if hold then
        setOpen(entry.id, os.time() + seconds('MaxSeconds', 120), source)
    else
        setOpen(entry.id, os.time() + secs, nil, source)
    end
end

-- the skimmer goes on the outside of the coin panel, so installing, reading or removing it leaves the door shut
local CRIME = { breakin = true, pickseal = true, steal = true, fullhack = true, replaceboard = true }
local afterBreakIn  -- set below with the cash box: opens the door, then the box
-- The door only opens once an action actually went through: the module that checks it (restock, crime, loot,
-- rekey) fires this server-only event after its checks pass. A refused or failed attempt never opens the door.
-- reason: 'restock', 'loot', 'rekey' or 'crime' (with the crime action)
AddEventHandler('meta_comic:server:vendingDoorSuccess', function(src, id, reason, action)
    if reason == 'restock' then return trigger(src, id, seconds('RestockSeconds', 20)) end
    if reason == 'loot' or reason == 'rekey' then return trigger(src, id, nil, true) end
    if reason ~= 'crime' or door.Crime == false or not CRIME[action] then return end
    if action == 'breakin' or action == 'pickseal' then return afterBreakIn(src, id) end
    trigger(src, id, seconds('CrimeSeconds', 10))
end)
-- only once the key actually unlocked it (the key module opens a cabinet session for that player)
local function unlocked(source, entry)
    local keys = MetaComic.VendingKeys
    return not keys or not keys.access or keys.access(source, entry, 'service') == true
end
-- Only close after the key module has validated and saved the lock operation.
-- Listening to the request raced its yielding save and saw the lock as busy.
AddEventHandler('meta_comic:server:vendingKeyLockSuccess', function(src, id)
    if closeCabinet then closeCabinet(tonumber(id), src) end
end)
AddEventHandler('meta_comic:server:vendingKeyCloseForLockSuccess', function(src, id)
    if closeCabinet then closeCabinet(tonumber(id), src) end
end)
AddEventHandler('meta_comic:server:vendingSecured', function(src, id)
    if closeCabinet then closeCabinet(tonumber(id), src) end
end)
-- key system (server/modules/vending_keys.lua): replacing the lock cylinder holds the door open until it's done
-- (opened through vendingDoorSuccess once the replacement really started)
RegisterNetEvent('meta_comic:server:vendingRekeyFinish', function() release(source) end)
RegisterNetEvent('meta_comic:server:vendingRekeyCancel', function() release(source) end)
RegisterNetEvent('meta_comic:server:lootCancel', function() release(source) end)
AddEventHandler('meta_comic:server:vendingLootStopped', function(src) release(src) end)
AddEventHandler('playerDropped', function() release(source) end)

-- Cash box behind the door (Config.VendingMachines.Door.CashBox). Its lid opens with the door when the cabinet is
-- unlocked with a key; after a break-in it stays padlocked until someone breaks that padlock too, and looting cash
-- waits for it (server/modules/vending_loot.lua asks MetaComic.VendingCashbox.allows). Clients fill the open box
-- with cash props by how much cash the machine holds.
local box = door.CashBox or {}
local lids = {}     -- machine id -> cash level (0 empty .. 3 full) while its lid is open
local racks = {}    -- machine id -> true while its server rack is open
local padlocks = {} -- source -> { token, id, at } while breaking a padlock
local function notify(source, message, kind) if MetaComic.Framework.notify then MetaComic.Framework.notify(source, message, kind or 'info') end end
local function cashLevel(entry) -- the client stacks cash props from the amount
    return math.floor(math.max(0, tonumber(entry.cash) or 0))
end
local function wasBrokenIn(id)
    local entry = Vending.get(id)
    return entry ~= nil and MetaComic.VendingLoot ~= nil and MetaComic.VendingLoot.isOpen(entry) == true
end
local lidState = {}
local function sendLid(id, level, actor)
    local isOpen = level ~= nil
    if (lidState[id] == true) ~= isOpen then
        observation(id, isOpen and 'Cashbox opened' or 'Cashbox closed', actor)
        lidState[id] = isOpen
    end
    TriggerClientEvent('meta_comic:client:vendingCashbox', -1, id, level, level ~= nil and wasBrokenIn(id))
end -- nil level = shut
local function openLid(entry, actor)
    if box.Enabled == false or lids[entry.id] then return end
    lids[entry.id] = cashLevel(entry)
    sendLid(entry.id, lids[entry.id], actor)
end
-- Server rack in the recess right of the window (Config.VendingMachines.Door.Rack). The board, OS and payment hacks
-- and the GPS switch (Rack.Required) need the cabinet and this rack open: a full key opens it from the key menu,
-- anyone else picks its lock. It shuts whenever the cabinet does.
local rack = door.Rack or {}
local RACK_ON = rack.Enabled ~= false
local RACK_NEEDS = {}
for _, action in ipairs(rack.Required or { 'hack', 'fullhack', 'replaceboard', 'disablegps', 'enablegps', 'system' }) do RACK_NEEDS[action] = true end
local rackJobs = {} -- source -> { token, id, at } while picking a rack lock
local function sendRack(id, isOpen, actor)
    observation(id, isOpen and 'Server cabinet opened' or 'Server cabinet closed', actor)
    TriggerClientEvent('meta_comic:client:vendingRack', -1, id, isOpen == true)
end
local function openRack(entry, actor)
    if not RACK_ON or racks[entry.id] then return end
    racks[entry.id] = true
    sendRack(entry.id, true, actor)
end
local function closeRack(id, actor)
    if not racks[id] then return end
    racks[id] = nil
    sendRack(id, false, actor)
end
closeCabinet = function(id, actor)
    local state = open[id]
    ajar[id]=nil
    TriggerClientEvent('meta_comic:client:vendingAjar',-1,id,nil)
    if not state then return end
    for holder in pairs(state.holders) do if holding[holder] == id then holding[holder] = nil end end
    open[id], lids[id] = nil, nil
    closeRack(id, actor)
    sendLid(id, nil, actor)
    send(id, false, actor)
end
-- what an action needs open besides the cabinet: 'rack', 'cashbox', 'cabinet' or nothing
local function needs(action)
    if action == 'falsifylogs' then return 'rack' end
    if RACK_ON and RACK_NEEDS[action] then return 'rack' end
    if action == 'hack' or action == 'fullhack' or action == 'replaceboard' then return box.Enabled ~= false and 'cashbox' or 'cabinet' end
end
local function ready(entry, action)
    local need = needs(action)
    if not need then return true end
    if entry == nil or open[entry.id] == nil then return false end
    if need == 'rack' then return racks[entry.id] ~= nil end
    return need ~= 'cashbox' or lids[entry.id] ~= nil
end
refreshLids = function()
    for id in pairs(racks) do
        if not open[id] or not Vending.get(id) then closeRack(id) end
    end
    for id, level in pairs(lids) do
        local entry = Vending.get(id)
        if not open[id] or not entry then
            lids[id] = nil
            sendLid(id, nil)
        else
            local now = cashLevel(entry)
            if now ~= level then lids[id] = now; sendLid(id, now) end
        end
    end
end
local function brokenIn(entry) return MetaComic.VendingLoot and MetaComic.VendingLoot.isOpen(entry) end
local function padlockReady(source, entry)
    -- broken into, or the cabinet is open for any other reason (unlocked with a key, being serviced)
    local record = entry and MetaComic.VendingRegistry.get(entry.serial)
    return box.Enabled ~= false and box.Lock ~= false and entry and record and not record.securitySeal and not record.padlock
        and not lids[entry.id] and open[entry.id] ~= nil and Vending.near(source, entry, Vending.reach() + 1.0)
end
local function duration()
    local ms = math.max(1000, tonumber(box.Duration) or 8000)
    return MetaComic.VendingProgressDuration and MetaComic.VendingProgressDuration(ms) or ms
end

MetaComic.VendingCashbox = {
    closing = function(id) return closing[tonumber(id) or 0] ~= nil end,
    isOpen = function(id) return lids[tonumber(id) or 0] ~= nil end,
    -- looting cash needs the lid open; with Lock = false the box never stops anyone
    allows = function(entry, mode) return entry ~= nil and open[entry.id] ~= nil
        and (box.Enabled == false or box.Lock == false or mode == 'stock' or lids[entry.id] ~= nil) end,
    -- hacks reach the board through the open server rack, or the cash box without one (server/modules/vending_crime.lua)
    hackReady = function(entry) return ready(entry, 'hack') end,
    needs = needs, ready = ready,
    rackOpen = function(id) return racks[tonumber(id) or 0] ~= nil end,
    -- full-key holders open and shut the server rack from the key menu (client/vending_keys.lua)
    keyRack = RACK_ON and rack.OpenWithKey ~= false,
    -- the cabinet door stands open (key unlock, servicing, break-in): anyone there can loot it (server/modules/vending_loot.lua)
    cabinetOpen = function(id) return open[tonumber(id) or 0] ~= nil end,
    -- full-key holders can open and shut the box on its own from the key menu (client/vending_keys.lua)
    keyBox = box.Enabled ~= false and box.OpenWithKey ~= false,
}
local function restoreClose(job)
    closing[job.id]=nil
    local entry=Vending.get(job.id)
    if not entry or entry.serial~=job.serial then return end
    local parts={cabinet=job.kind=='cylinder' and open[job.id]~=nil,
        cashbox=(job.kind=='cylinder' or job.kind=='cashbox') and lids[job.id]~=nil,
        rack=(job.kind=='cylinder' or job.kind=='rack') and racks[job.id]~=nil}
    if not parts.cabinet and not parts.cashbox and not parts.rack then return end
    local previous=ajar[job.id] or {}
    for part,value in pairs(previous) do if value then parts[part]=true end end
    ajar[job.id]=parts
    -- Authoritative state never closed: restore the unlocked parts with a slower, partial swing.
    if parts.cabinet then TriggerClientEvent('meta_comic:client:vendingDoor',-1,job.id,true) end
    if parts.cashbox then TriggerClientEvent('meta_comic:client:vendingCashbox',-1,job.id,lids[job.id],wasBrokenIn(job.id)) end
    if parts.rack then TriggerClientEvent('meta_comic:client:vendingRack',-1,job.id,true) end
    TriggerClientEvent('meta_comic:client:vendingAjar',-1,job.id,parts)
    TriggerClientEvent('meta_comic:client:vendingMenuRefresh',job.source,job.id)
end
function MetaComic.VendingCashbox.beginKeyClose(src,entry,kind)
    kind=kind or 'cylinder'
    if kind~='cylinder' and kind~='cashbox' and kind~='rack' or closing[entry.id] then return end
    if not open[entry.id] or kind=='cashbox' and lids[entry.id]==nil or kind=='rack' and not racks[entry.id] then return end
    local record=MetaComic.VendingRegistry.get(entry.serial)
    local visual=((cfg.Keys or {}).UseAnimation or {})
    local profile=(visual.Profiles or {})[({cylinder='Cylinder',cashbox='Cashbox',rack='Rack'})[kind]] or {}
    local token=('%s:%s:%s'):format(src,GetGameTimer(),math.random(1,1000000000))
    local job={source=src,id=entry.id,serial=entry.serial,revision=record.lockRevision,kind=kind,token=token,at=GetGameTimer(),minDuration=tonumber(profile.Duration) or tonumber(visual.Duration) or 4500}
    closing[entry.id]=job
    if kind=='cylinder' then TriggerClientEvent('meta_comic:client:vendingDoor',-1,entry.id,false,nil,true) end
    if kind=='cylinder' or kind=='cashbox' then TriggerClientEvent('meta_comic:client:vendingCashbox',-1,entry.id,nil) end
    if kind=='cylinder' or kind=='rack' then TriggerClientEvent('meta_comic:client:vendingRack',-1,entry.id,false) end
    TriggerClientEvent('meta_comic:client:vendingKeyCloseForLock',src,entry.id,kind,token)
    SetTimeout(math.max(15000,(tonumber(profile.Duration) or tonumber(visual.Duration) or 4500)+15000),function()
        if closing[entry.id]==job then restoreClose(job) end
    end)
    return token
end
RegisterNetEvent('meta_comic:server:vendingKeyCloseFinish',function(id,token,success)
    local src=source
    local job=closing[tonumber(id) or 0]
    if not job or job.source~=src or job.token~=token then return end
    local entry=Vending.get(job.id)
    local keys=MetaComic.VendingKeys
    local record=entry and MetaComic.VendingRegistry.get(entry.serial)
    if success~=true or not record or entry.serial~=job.serial or record.lockRevision~=job.revision
        or not Vending.near(src,entry,Vending.reach()+1.0) or not keys.access(src,entry,job.kind=='cylinder' and 'service' or 'full') then return restoreClose(job) end
    if GetGameTimer()-job.at<job.minDuration then return restoreClose(job) end
    closing[job.id]=nil
    if job.kind=='cylinder' then
        if not keys.lockCabinet(src,entry) then return restoreClose(job) end
    else
        if job.kind=='cashbox' then
            lids[job.id]=nil;sendLid(job.id,nil,src)
            if record.cashboxOpenFor then record.cashboxOpenFor=nil;MetaComic.VendingRegistry.save() end
        else
            closeRack(job.id,src)
            if record.rackOpenFor then record.rackOpenFor=nil;MetaComic.VendingRegistry.save() end
        end
        local parts=ajar[job.id]
        if parts then
            parts[job.kind]=nil
            if not parts.cabinet and not parts.cashbox and not parts.rack then parts=nil end
        end
        ajar[job.id]=parts
        TriggerClientEvent('meta_comic:client:vendingAjar',-1,job.id,parts)
    end
    TriggerClientEvent('meta_comic:client:vendingMenuRefresh',src,entry.id)
end)
RegisterNetEvent('meta_comic:server:vendingOpenAjar',function(id)
    local src=source;id=tonumber(id) or 0
    local entry=Vending.get(id)
    if not entry or not ajar[id] or closing[id] or not Vending.near(src,entry,Vending.reach()+1.0) then return end
    local parts=ajar[id]
    ajar[id]=nil
    TriggerClientEvent('meta_comic:client:vendingAjar',-1,id,nil)
    if parts.cabinet then TriggerClientEvent('meta_comic:client:vendingDoor',-1,id,open[id]~=nil) end
    if parts.cashbox then TriggerClientEvent('meta_comic:client:vendingCashbox',-1,id,lids[id],wasBrokenIn(id)) end
    if parts.rack then TriggerClientEvent('meta_comic:client:vendingRack',-1,id,racks[id]==true) end
    TriggerClientEvent('meta_comic:client:vendingMenuRefresh',src,id)
end)
AddEventHandler('playerDropped',function()
    for _,job in pairs(closing) do if job.source==source then restoreClose(job) end end
end)
RegisterNetEvent('meta_comic:server:vendingDamagedDoor', function(id, wantOpen)
    local src, entry = source, Vending.get(id)
    local keys, registry = MetaComic.VendingKeys, MetaComic.VendingRegistry
    local record = entry and registry.get(entry.serial)
    if not record or not keys or not Vending.near(src, entry, Vending.reach()) then return end
    if MetaComic.VendingLoot and MetaComic.VendingLoot.busy(entry) then
        if wantOpen == false then
            notify(src, 'You cannot close the main door while someone is looting this machine.', 'error')
        end
        return
    end
    if keys.busy(entry) or Vending.isTransferringStock(entry) then return end
    if record.securitySeal then
        if wantOpen ~= true or not keys.unseal(src, entry) then return end
    end
    if record.lockCondition ~= 'damaged' then return end
    if wantOpen == true then
        trigger(src, entry.id, seconds('UnlockSeconds', 30))
    elseif wantOpen == false then
        local state = open[entry.id]
        if state and next(state.holders) then return end
        manuallyClosed[entry.id] = true
        open[entry.id], lids[entry.id] = nil, nil
        send(entry.id, false)
        sendLid(entry.id, nil)
        closeRack(entry.id)
    end
    TriggerClientEvent('meta_comic:client:vendingMenuRefresh',src,entry.id)
end)
-- Consume the validated key operation synchronously; menu snapshots now see the completed door state.
AddEventHandler('meta_comic:server:vendingKeyUnlockSuccess', function(src, id, mode)
    local entry = Vending.get(id)
    if not entry or not unlocked(src, entry) then return end
    trigger(src, id, seconds('UnlockSeconds', 30))
    local keys = MetaComic.VendingKeys
    if mode ~= 'door' and box.OpenWithKey ~= false and open[entry.id] and not brokenIn(entry)
        and (not keys or not keys.access or keys.access(src, entry, 'full') == true) then openLid(entry, src) end
    TriggerClientEvent('meta_comic:client:vendingMenuRefresh', src, entry.id)
end)
-- a full key opens or shuts the cash box of an open cabinet without locking the machine
RegisterNetEvent('meta_comic:server:vendingCashboxKey', function(id, wantOpen)
    local source = source
    local entry = Vending.get(id)
    if entry and closing[entry.id] then return notify(source,'Wait for the current lock operation.', 'error') end
    if box.Enabled == false then return notify(source, 'Cash box access is disabled.', 'error') end
    if not entry or not Vending.near(source, entry, Vending.reach() + 1.0) then return notify(source, 'Stand at the vending machine first.', 'error') end
    local keys = MetaComic.VendingKeys
    if keys and keys.access and keys.access(source, entry, 'full') ~= true then return notify(source, 'Unlock the cabinet with a full-access key first.', 'error') end
    if wantOpen then
        if not open[entry.id] then return notify(source, 'Open the machine first.', 'error') end
        if lids[entry.id] ~= nil then return notify(source, 'The cash box is already open.', 'error') end
        openLid(entry, source)
        notify(source, 'Cash box opened.', 'success')
    elseif lids[entry.id] then
        lids[entry.id] = nil
        sendLid(entry.id, nil, source)
        local record = MetaComic.VendingRegistry and MetaComic.VendingRegistry.get(entry.serial)
        if record and record.cashboxOpenFor then record.cashboxOpenFor = nil; MetaComic.VendingRegistry.save() end
        notify(source, 'Cash box closed.', 'success')
        TriggerClientEvent('meta_comic:client:vendingKeyCloseForLock', source, entry.id, 'cashbox')
    else
        notify(source, 'The cash box is already closed.', 'error')
    end
    TriggerClientEvent('meta_comic:client:vendingMenuRefresh',source,entry.id)
end)
-- a successful break-in opens the door, then after BreakInDelay ms the cash box (unless PadlockAfterBreakIn)
afterBreakIn = function(source, id)
    local tries = 0
    local function check() -- the crime module marks the cabinet broken in while handling the same event
        tries = tries + 1
        local entry = Vending.get(id)
        if not entry then return end
        if not brokenIn(entry) then if tries < 6 then SetTimeout(500, check) end return end
        setOpen(entry.id, os.time() + seconds('UnlockSeconds', 30))
        open[entry.id].breakIn = true
        if box.Enabled == false or box.PadlockAfterBreakIn ~= false then return end
        SetTimeout(math.max(0, tonumber(box.BreakInDelay) or 2500), function()
            if open[entry.id] and brokenIn(entry) then openLid(entry) end
        end)
    end
    SetTimeout(300, check)
end
RegisterNetEvent('meta_comic:server:cashboxStart', function(id)
    local source = source
    local entry = Vending.get(id)
    if not entry then return notify(source, 'That vending machine no longer exists.', 'error') end
    if not Vending.near(source, entry, Vending.reach() + 1.0) then return notify(source, 'Stand at the vending machine first.', 'error') end
    if padlocks[source] or rackJobs[source] or MetaComic.VendingCrimeBusy and MetaComic.VendingCrimeBusy(source) then return notify(source, 'Finish or cancel your current action first.', 'error') end
    if not open[entry.id] then return notify(source, 'Open the main cabinet door before breaking the cash box lock.', 'error') end
    if lids[entry.id] ~= nil then return notify(source, 'The cash box is already open.', 'error') end
    if not padlockReady(source, entry) then return notify(source, 'The cash box lock cannot be accessed while the machine is secured.', 'error') end
    if MetaComic.VendingKeys and MetaComic.VendingKeys.busy(entry) or Vending.isTransferringStock(entry)
        or MetaComic.VendingLoot and MetaComic.VendingLoot.busy(entry) then return notify(source, 'The machine is busy. Wait for the current action to finish.', 'error') end
    for _, item in ipairs(box.Items or {}) do
        local name = type(item) == 'table' and item.item or item
        local needed = type(item) == 'table' and tonumber(item.count) or 1
        if (MetaComic.Inventory.count and MetaComic.Inventory.count(source, name) or 0) < needed then
            return notify(source, ('You need a %s.'):format(type(item) == 'table' and item.label or name), 'error')
        end
    end
    local token = ('%d:%d:%d'):format(source, os.time(), math.random(1, 1000000000))
    padlocks[source] = { token = token, id = entry.id, at = GetGameTimer(), duration = duration() }
    if MetaComic.Police and MetaComic.Police.watch then
        local job=padlocks[source];job.action='cashbox'
        MetaComic.Police.watch(source,job,entry,'breakin',function() return padlocks[source]==job end)
    end
    setOpen(entry.id, os.time() + seconds('MaxSeconds', 120), source)
    TriggerClientEvent('meta_comic:client:cashboxStart', source, { token = token, witness = true, id = entry.id, minigame = box.Minigame,
        duration = padlocks[source].duration, animation = box.Animation })
end)
RegisterNetEvent('meta_comic:server:cashboxFinish', function(token, success, cancelled)
    local source = source
    local job = padlocks[source]
    if not job or job.token ~= token then return end
    padlocks[source] = nil
    release(source)
    if MetaComic.Police and MetaComic.Police.unwatch then MetaComic.Police.unwatch(source) end
    local alertEntry=Vending.get(job.id)
    if success~=true and cancelled~=true and alertEntry and Vending.near(source,alertEntry,Vending.reach()+2.0) and MetaComic.Police and MetaComic.Police.attempt then
        MetaComic.Police.attempt(source,job,alertEntry,'breakin','fail')
    end
    if success ~= true then return notify(source, 'Cash box lock attempt canceled or failed.', 'error') end
    if GetGameTimer() - job.at < job.duration * 0.9 then return notify(source, 'You stopped before the cash box lock was opened.', 'error') end
    local entry = Vending.get(job.id)
    if not padlockReady(source, entry) then return notify(source, 'The cabinet closed, was secured, or the cash box changed before you finished.', 'error') end
    for _, item in ipairs(box.Items or {}) do
        if type(item) == 'table' and (tonumber(item.breakChance) or 0) > 0 and math.random() * 100 < tonumber(item.breakChance) then
            if MetaComic.Inventory.remove(source, item.item, 1) then notify(source, ('Your %s broke.'):format(item.label or item.item), 'error') end
        end
    end
    if MetaComic.Police and MetaComic.Police.attempt then MetaComic.Police.attempt(source,job,entry,'breakin','success') end
    openLid(entry)
    -- remembered for this break-in (keyed by its unlock time) so the box stays open across restarts
    local record = MetaComic.VendingRegistry and MetaComic.VendingRegistry.get(entry.serial)
    if record then record.cashboxOpenFor = record.unlockedUntil; MetaComic.VendingRegistry.save() end
    notify(source, 'The cash box padlock snapped open.', 'success')
end)
AddEventHandler('playerDropped', function() padlocks[source] = nil; rackJobs[source] = nil end)
-- a full key opens or shuts the server rack of an open cabinet
RegisterNetEvent('meta_comic:server:vendingRackKey', function(id, wantOpen)
    local source = source
    local entry = Vending.get(id)
    if entry and closing[entry.id] then return notify(source,'Wait for the current lock operation.', 'error') end
    if not RACK_ON or rack.OpenWithKey == false then return notify(source, 'Server rack access with a key is disabled.', 'error') end
    if not entry or not Vending.near(source, entry, Vending.reach() + 1.0) then return notify(source, 'Stand at the vending machine first.', 'error') end
    local keys = MetaComic.VendingKeys
    if keys and keys.access and keys.access(source, entry, 'full') ~= true then return notify(source, 'Unlock the cabinet with a full-access key first.', 'error') end
    if wantOpen then
        if not open[entry.id] then return notify(source, 'Open the machine first.', 'error') end
        if racks[entry.id] then return notify(source, 'The server rack is already open.', 'error') end
        openRack(entry, source)
        notify(source, 'Server rack opened.', 'success')
    elseif racks[entry.id] then
        closeRack(entry.id, source)
        local record = MetaComic.VendingRegistry and MetaComic.VendingRegistry.get(entry.serial)
        if record and record.rackOpenFor then record.rackOpenFor = nil; MetaComic.VendingRegistry.save() end
        notify(source, 'Server rack closed.', 'success')
        TriggerClientEvent('meta_comic:client:vendingKeyCloseForLock', source, entry.id, 'rack')
    else
        notify(source, 'The server rack is already closed.', 'error')
    end
    TriggerClientEvent('meta_comic:client:vendingMenuRefresh',source,entry.id)
end)
local function rackDuration()
    local ms = math.max(1000, tonumber(rack.Duration) or 10000)
    return MetaComic.VendingProgressDuration and MetaComic.VendingProgressDuration(ms) or ms
end
local function rackPickReady(source, entry)
    local record = entry and MetaComic.VendingRegistry.get(entry.serial)
    return RACK_ON and rack.Lock ~= false and entry and record and not record.securitySeal and not record.padlock
        and not racks[entry.id] and open[entry.id] ~= nil and Vending.near(source, entry, Vending.reach() + 1.0)
end
RegisterNetEvent('meta_comic:server:rackStart', function(id)
    local source = source
    local entry = Vending.get(id)
    if not entry then return notify(source, 'That vending machine no longer exists.', 'error') end
    if not Vending.near(source, entry, Vending.reach() + 1.0) then return notify(source, 'Stand at the vending machine first.', 'error') end
    if rackJobs[source] or padlocks[source] or MetaComic.VendingCrimeBusy and MetaComic.VendingCrimeBusy(source) then return notify(source, 'Finish or cancel your current action first.', 'error') end
    if not open[entry.id] then return notify(source, 'Open the main cabinet door before picking the server rack lock.', 'error') end
    if racks[entry.id] then return notify(source, 'The server rack is already open.', 'error') end
    if not rackPickReady(source, entry) then return notify(source, 'The server rack lock cannot be accessed while the machine is secured.', 'error') end
    if MetaComic.VendingKeys and MetaComic.VendingKeys.busy(entry) or Vending.isTransferringStock(entry)
        or MetaComic.VendingLoot and MetaComic.VendingLoot.busy(entry) then return notify(source, 'The machine is busy. Wait for the current action to finish.', 'error') end
    for _, item in ipairs(rack.Items or {}) do
        local name = type(item) == 'table' and item.item or item
        local needed = type(item) == 'table' and tonumber(item.count) or 1
        if (MetaComic.Inventory.count and MetaComic.Inventory.count(source, name) or 0) < needed then
            return notify(source, ('You need a %s.'):format(type(item) == 'table' and item.label or name), 'error')
        end
    end
    local token = ('%d:%d:%d'):format(source, os.time(), math.random(1, 1000000000))
    rackJobs[source] = { token = token, id = entry.id, at = GetGameTimer(), duration = rackDuration() }
    if MetaComic.Police and MetaComic.Police.watch then
        local job=rackJobs[source];job.action='rackpick'
        MetaComic.Police.watch(source,job,entry,'breakin',function() return rackJobs[source]==job end)
    end
    setOpen(entry.id, os.time() + seconds('MaxSeconds', 120), source)
    TriggerClientEvent('meta_comic:client:rackStart', source, { token = token, witness = true, id = entry.id, minigame = rack.Minigame,
        duration = rackJobs[source].duration, animation = rack.Animation, finish = 'meta_comic:server:rackFinish', label = 'Picking the rack lock' })
end)
RegisterNetEvent('meta_comic:server:rackFinish', function(token, success, cancelled)
    local source = source
    local job = rackJobs[source]
    if not job or job.token ~= token then return end
    rackJobs[source] = nil
    release(source)
    if MetaComic.Police and MetaComic.Police.unwatch then MetaComic.Police.unwatch(source) end
    local alertEntry=Vending.get(job.id)
    if success~=true and cancelled~=true and alertEntry and Vending.near(source,alertEntry,Vending.reach()+2.0) and MetaComic.Police and MetaComic.Police.attempt then
        MetaComic.Police.attempt(source,job,alertEntry,'breakin','fail')
    end
    if success ~= true then return notify(source, 'Server rack lock attempt canceled or failed.', 'error') end
    if GetGameTimer() - job.at < job.duration * 0.9 then return notify(source, 'You stopped before the server rack lock was opened.', 'error') end
    local entry = Vending.get(job.id)
    if not rackPickReady(source, entry) then return notify(source, 'The cabinet closed, was secured, or the server rack changed before you finished.', 'error') end
    for _, item in ipairs(rack.Items or {}) do
        if type(item) == 'table' and (tonumber(item.breakChance) or 0) > 0 and math.random() * 100 < tonumber(item.breakChance) then
            if MetaComic.Inventory.remove(source, item.item, 1) then notify(source, ('Your %s broke.'):format(item.label or item.item), 'error') end
        end
    end
    if MetaComic.Police and MetaComic.Police.attempt then MetaComic.Police.attempt(source,job,entry,'breakin','success') end
    openRack(entry)
    -- remembered for this break-in (keyed by its unlock time) so the rack stays open across restarts
    local record = MetaComic.VendingRegistry and MetaComic.VendingRegistry.get(entry.serial)
    if record and brokenIn(entry) then record.rackOpenFor = record.unlockedUntil; MetaComic.VendingRegistry.save() end
    notify(source, 'The server rack lock turned.', 'success')
end)
exports('SetVendingRack', function(id, isOpen)
    local entry = Vending.get(tonumber(id) or 0)
    if not entry then return false end
    if isOpen then openRack(entry) else closeRack(entry.id) end
    return true
end)
exports('SetVendingCashbox', function(id, isOpen)
    local entry = Vending.get(tonumber(id) or 0)
    if not entry then return false end
    if isOpen then openLid(entry) elseif lids[entry.id] then lids[entry.id] = nil; sendLid(entry.id, nil) end
    return true
end)

local scan
-- closes doors whose time ran out (held doors also close after MaxSeconds)
CreateThread(function()
    while true do
        Wait(1000)
        local now = os.time()
        for id, state in pairs(open) do
            if closing[id] then state['until']=math.max(state['until'] or 0,now+2) end
            -- a broken-in cabinet stays open until it's secured or its unlock runs out
            local entry = Vending.get(id)
            if entry and MetaComic.VendingKeys and (MetaComic.VendingKeys.replacing(entry) or MetaComic.VendingKeys.repairing and MetaComic.VendingKeys.repairing(entry)) then
                state['until'] = math.max(state['until'] or 0, now + seconds('CloseDelay', 2))
            elseif entry and MetaComic.VendingLoot and MetaComic.VendingLoot.isOpen(entry) then
                state['until'] = math.max(state['until'] or 0, now + seconds('CloseDelay', 2))
            elseif state.breakIn and next(state.holders) == nil then
                -- opened by a break-in that has ended (secured or timed out): close right away
                state.breakIn = nil
                state['until'] = math.min(state['until'] or 0, now + seconds('CloseDelay', 2))
            end
            if (not closing[id] and not ajar[id] and (state['until'] or 0) <= now) or not entry then
                for source in pairs(state.holders) do if holding[source] == id then holding[source] = nil end end
                open[id] = nil
                send(id, false)
            end
        end
        refreshLids()
        -- broken-in cabinets that aren't open (e.g. after a restart) open again, with their cash box
        scan = (scan or 0) + 1
        if scan >= 5 and Vending.all and door.Crime ~= false then
            scan = 0
            for _, entry in ipairs(Vending.all()) do
                if not open[entry.id] and not manuallyClosed[entry.id] and brokenIn(entry) then
                    setOpen(entry.id, now + seconds('UnlockSeconds', 30))
                    open[entry.id].breakIn = true
                    local record = MetaComic.VendingRegistry and MetaComic.VendingRegistry.get(entry.serial)
                    local padlockGone = record and record.cashboxOpenFor ~= nil and record.cashboxOpenFor == record.unlockedUntil
                    if box.Enabled ~= false and (box.PadlockAfterBreakIn == false or padlockGone) then openLid(entry) end
                    if record and record.rackOpenFor ~= nil and record.rackOpenFor == record.unlockedUntil then openRack(entry) end
                end
            end
        end
    end
end)

RegisterNetEvent('meta_comic:server:vendingDoors', function()
    local list = {}
    for id in pairs(open) do list[#list + 1] = id end
    TriggerClientEvent('meta_comic:client:vendingDoors', source, list)
    local boxes = {}
    for id, level in pairs(lids) do boxes[#boxes + 1] = { id, level, wasBrokenIn(id) } end
    TriggerClientEvent('meta_comic:client:vendingCashboxes', source, boxes)
    local openRacks = {}
    for id in pairs(racks) do openRacks[#openRacks + 1] = id end
    TriggerClientEvent('meta_comic:client:vendingRacks', source, openRacks)
    for id,parts in pairs(ajar) do TriggerClientEvent('meta_comic:client:vendingAjar',source,id,parts) end
end)

-- other scripts: exports['<resource>']:SetVendingDoor(machineId, true | false, seconds)
exports('SetVendingDoor', function(id, isOpen, secs)
    id = tonumber(id)
    if not id or not Vending.get(id) then return false end
    if isOpen then setOpen(id, os.time() + math.max(1, tonumber(secs) or seconds('RestockSeconds', 20)))
    elseif open[id] then open[id]['until'] = 0 end
    return true
end)
