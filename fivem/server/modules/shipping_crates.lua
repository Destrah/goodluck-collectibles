-- Shipping crates (Config.ShippingCrates): one inventory item that breaks down into the big collectible containers
-- (booster boxes, plushie cases, coin bag boxes, ...). Using it puts the crate prop on the ground in front of the
-- player, who pries it open; when the timer runs out the server takes the crate item and gives its contents.
-- The crate kind travels in the item metadata ({ crate = 'mixed', serial = ... }).
local cfg = Config.ShippingCrates or {}
if cfg.Enabled == false then return end

MetaComic.ShippingCrates = {}
local service = MetaComic.ShippingCrates
local ITEM = cfg.Item or 'shipping_crate'
local pending = {}
local unpacking = {} -- opened crates whose contents are handed over when the 3D reveal ends (crate item kept until then)
local serial = 0

local function notify(source, message, notifyType)
    if MetaComic.Framework.notify then MetaComic.Framework.notify(source, message, notifyType) end
end
local function crateOf(id) local crate = (cfg.Crates or {})[id]; return type(crate) == 'table' and crate or nil end
local function crateLabel(id) local crate = crateOf(id); return crate and crate.label or 'Shipping Crate' end
local function newSerial() serial = serial + 1; return ('CR-%s-%04d'):format(os.date('%y%m%d'), (os.time() + serial) % 10000) end

-- the collectibles a crate holds: 'trading_card' for booster packs / boxes, else the container's collectible type
local function crateTypes(crate)
    local list, seen = {}, {}
    for _, entry in ipairs(crate and crate.contents or {}) do
        local typeId = entry.type == 'sealed' and 'trading_card' or entry.type == 'container' and entry.collectible or nil
        if typeId and not seen[typeId] then seen[typeId] = true; list[#list + 1] = typeId end
    end
    return list
end
function service.choices()
    local list = {}
    for id, crate in pairs(cfg.Crates or {}) do list[#list + 1] = { id = id, label = crate.label or id, types = crateTypes(crate) } end
    table.sort(list, function(a, b) return a.label < b.label end)
    return list
end
-- the sets the admin menu can pick for each collectible in a crate
local function setChoices()
    local out = { trading_card = {} }
    for _, set in ipairs(MetaComic.Sets and MetaComic.Sets.getAll() or {}) do out.trading_card[#out.trading_card + 1] = { id = set.id, name = set.name or set.id } end
    for typeId in pairs(MetaComic.Objects and MetaComic.Objects.types or {}) do
        out[typeId] = {}
        for _, set in ipairs(MetaComic.Objects.data.sets or {}) do
            if MetaComic.Objects.setOf(typeId, set.id) then out[typeId][#out[typeId] + 1] = { id = set.id, name = set.name or set.id } end
        end
    end
    return out
end
-- Which sets a crate's contents come from (admin menu, crafting recipe or Crates[id].sets), per collectible:
-- { trading_card = { card set ids } (one picked at random per box), plushie = set id, challenge_coin = set id }.
-- A plain list means card sets (older crates and recipes). Contents with their own `set` keep it. Unknown or empty
-- sets are dropped; a collectible without one uses its default set / its container's set.
function service.cleanSets(value)
    if type(value) ~= 'table' then return nil end
    if value[1] ~= nil then value = { trading_card = value } end
    local out, any = {}, false
    local cards, seen = {}, {}
    local list = type(value.trading_card) == 'table' and value.trading_card or { value.trading_card }
    for _, id in ipairs(list) do
        local resolved = type(id) == 'string' and MetaComic.Sets and MetaComic.Sets.get(id) and id or nil
        if resolved and not seen[resolved] and #cards < 20 then seen[resolved] = true; cards[#cards + 1] = resolved end
    end
    if #cards > 0 then out.trading_card = cards; any = true end
    for typeId in pairs(MetaComic.Objects and MetaComic.Objects.types or {}) do
        local set = MetaComic.Objects.setOf(typeId, value[typeId])
        if set then out[typeId] = set.id; any = true end
    end
    return any and out or nil
end
local function setNames(sets)
    local names = {}
    for _, id in ipairs(sets and sets.trading_card or {}) do local set = MetaComic.Sets.get(id); names[#names + 1] = set and set.name or id end
    for typeId in pairs(MetaComic.Objects and MetaComic.Objects.types or {}) do
        local set = sets and MetaComic.Objects.setOf(typeId, sets[typeId])
        if set then names[#names + 1] = set.name or set.id end
    end
    return table.concat(names, ', ')
end
function service.metadata(id, sets)
    local crate = crateOf(id)
    sets = service.cleanSets(sets) or service.cleanSets(crate and crate.sets)
    local lines = {}
    for _, entry in ipairs(crate and crate.contents or {}) do
        if (entry.chance or 100) >= 100 then lines[#lines + 1] = MetaComic.Rewards.label(entry) end
    end
    local description = #lines > 0 and ('Contains ' .. table.concat(lines, ', ')) or 'A sealed shipping crate.'
    if sets then description = description .. ' · Sets: ' .. setNames(sets) end
    return {
        crate = id, serial = newSerial(), label = crate and crate.label or 'Shipping Crate', sets = sets,
        description = description,
        instanceId = ('crate-%s-%s'):format(os.time(), GetGameTimer() + serial),
    }
end
function service.give(source, id, amount, sets)
    amount = tonumber(amount) or 1
    if not crateOf(id) then return false, 'Unknown shipping crate.' end
    if amount < 1 or amount % 1 ~= 0 then return false, 'Invalid crate quantity.' end
    if MetaComic.Inventory.canCarry and not MetaComic.Inventory.canCarry(source,ITEM,amount) then return false, 'You cannot carry that many shipping crates.' end
    local given = {}
    for _ = 1, amount do
        local metadata = service.metadata(id, sets)
        if not MetaComic.Inventory.add(source,ITEM,1,metadata) then
            for _, previous in ipairs(given) do
                if not MetaComic.Inventory.remove(source,ITEM,1,{instanceId=previous.instanceId}) then
                    print('[meta-comic] shipping crate grant rollback failed: ' .. previous.instanceId)
                end
            end
            return false, 'Could not give the shipping crates.'
        end
        given[#given+1] = metadata
    end
    return true
end

-- crafting result { type = 'crate', crate = 'mixed' }
MetaComic.Rewards.register('crate', {
    label = function(result)
        local sets = service.cleanSets(result.sets)
        return ('%dx %s%s'):format(result.count or 1, crateLabel(result.crate), sets and (' (' .. setNames(sets) .. ')') or '')
    end,
    validate = function(result) return crateOf(result.crate) ~= nil end,
    canGive = function(source, result, amount)
        return not MetaComic.Inventory.canCarry or MetaComic.Inventory.canCarry(source, ITEM, (result.count or 1) * amount)
    end,
    give = function(source, result, amount)
        return service.give(source,result.crate,(result.count or 1)*amount,result.sets)
    end,
})
if MetaComic.Crafting then MetaComic.Crafting.crateChoices = service.choices end

-- what one crate holds this time: entries with a chance under 100 are rolled. Booster packs / boxes without their own
-- set each come from one of the crate's chosen card sets (picked at random per box when there are several);
-- collectible containers without their own set use the set chosen for that collectible.
local function roll(crate, sets)
    local list = {}
    local function add(entry)
        if MetaComic.Rewards.valid(entry) then list[#list + 1] = entry
        else print(('[meta-comic] shipping crate content skipped (not valid): %s'):format(json.encode(entry))) end
    end
    for _, entry in ipairs(crate.contents or {}) do
        local chance = tonumber(entry.chance) or 100
        if chance >= 100 or math.random() * 100 < chance then
            local cardSets = sets and sets.trading_card
            if entry.type == 'container' and not entry.set and sets and sets[entry.collectible] then
                local copy = MetaComic.CopyTable(entry); copy.set = sets[entry.collectible]
                add(copy)
            elseif entry.type == 'sealed' and not entry.set and cardSets then
                local counts, order = {}, {}
                for _ = 1, math.max(1, math.floor(tonumber(entry.count) or 1)) do
                    local id = cardSets[math.random(#cardSets)]
                    if not counts[id] then counts[id] = 0; order[#order + 1] = id end
                    counts[id] = counts[id] + 1
                end
                for _, id in ipairs(order) do
                    local copy = MetaComic.CopyTable(entry); copy.set, copy.count = id, counts[id]
                    add(copy)
                end
            else
                add(entry)
            end
        end
    end
    return list
end

local function slotItem(source, slot)
    local item = MetaComic.Inventory.getSlot and MetaComic.Inventory.getSlot(source, slot)
    if not item or item.name ~= ITEM then return nil end
    return item, item.metadata or item.info or {}
end

local claimCrate
local function startOpening(source, slot)
    slot = tonumber(slot)
    if unpacking[source] then claimCrate(source) end -- an earlier crate whose reveal never reported back
    if not slot or pending[source] then return end
    local item, metadata = slotItem(source, slot)
    if not item then return notify(source, 'That is not a shipping crate.', 'error') end
    local crateId = metadata.crate or cfg.Default or 'mixed'
    local crate = crateOf(crateId)
    if not crate then return notify(source, 'This crate has an unknown type: ' .. tostring(crateId), 'error') end
    local tool = cfg.Tool
    if type(tool) == 'table' and tool.item and not MetaComic.Inventory.has(source, tool.item, 1) then
        return notify(source, ('You need a %s to open the crate.'):format(tool.label or tool.item), 'error')
    end
    local duration = tonumber(crate.openTime or cfg.OpenTime) or 6000
    pending[source] = { slot = slot, instanceId = metadata.instanceId, crateId = crateId, startedAt = GetGameTimer(), duration = duration }
    TriggerClientEvent('meta_comic:client:crateStart', source, {
        crate = crateId, label = crate.label or 'Shipping Crate', duration = duration,
        animation = crate.animation or cfg.Animation3D or 'random', models = cfg.Models, scene = cfg.Scene,
    })
end
service.startOpening = startOpening

RegisterNetEvent('meta_comic:server:crateUse', function(slot) startOpening(source, slot) end)
RegisterNetEvent('meta_comic:server:crateCancel', function() pending[source] = nil end)
AddEventHandler('playerDropped', function() pending[source] = nil; unpacking[source] = nil end) -- an unclaimed crate stays in the inventory

-- the reveal finished (or was closed): now the crate item goes and its contents arrive in the inventory
claimCrate = function(source)
    local job = unpacking[source]
    unpacking[source] = nil
    if not job then return end
    local item, metadata = slotItem(source, job.slot)
    if not item or metadata.instanceId ~= job.instanceId then return notify(source, 'The crate is no longer in your inventory.', 'error') end
    for _, entry in ipairs(job.contents) do
        if not MetaComic.Rewards.canGive(source, entry, 1) then return notify(source, 'Make room first: you cannot carry everything in this crate. It is still in your inventory.', 'error') end
    end
    local identity = metadata.instanceId and { instanceId = metadata.instanceId } or nil
    if not MetaComic.Inventory.remove(source, ITEM, 1, identity, job.slot) then return notify(source, 'Could not open the crate.', 'error') end
    local given, failed = 0, 0
    for _, entry in ipairs(job.contents) do
        local ok, err = MetaComic.Rewards.give(source, entry, 1)
        if ok then given = given + 1 else failed = failed + 1; print('[meta-comic] crate content not given: ' .. tostring(err)) end
    end
    if given == 0 and #job.contents > 0 then
        MetaComic.Inventory.add(source, ITEM, 1, metadata) -- nothing came out: the crate goes back
        return notify(source, 'Could not unpack the crate; it was returned.', 'error')
    end
    if failed > 0 then notify(source, ('%d item(s) from the crate could not be given.'):format(failed), 'error') end
end
RegisterNetEvent('meta_comic:server:crateClaim', function() claimCrate(source) end)

RegisterNetEvent('meta_comic:server:crateFinish', function()
    local source = source
    local job = pending[source]
    pending[source] = nil
    if not job then return end
    if GetGameTimer() - job.startedAt < job.duration - 750 then return notify(source, 'Opening the crate was interrupted.', 'error') end
    local item, metadata = slotItem(source, job.slot)
    if not item or metadata.instanceId ~= job.instanceId then return notify(source, 'The crate is no longer in your inventory.', 'error') end
    local crate = crateOf(job.crateId)
    local contents = roll(crate, service.cleanSets(metadata.sets) or service.cleanSets(crate.sets))
    for _, entry in ipairs(contents) do
        if not MetaComic.Rewards.canGive(source, entry, 1) then return notify(source, 'Make room first: you cannot carry everything in this crate.', 'error') end
    end
    local rows = {}
    for _, entry in ipairs(contents) do
        local row = { label = MetaComic.Rewards.label(entry), type = entry.type, kind = entry.kind, collectible = entry.collectible, outer = entry.outer == true, count = entry.count or 1, set = entry.set }
        local container = entry.type == 'container' and MetaComic.Objects and MetaComic.Objects.data.containers[entry.collectible]
        if container then -- its saved design, so the crate reveal shows the same 3D model as the container's own opening
            row.containerKind = container.kind == 'bag' and 'bag' or 'box'
            row.look = row.outer and container.outer and container.outer.look or container.look
            row.innerLabel, row.caseCount = container.label, container.outer and container.outer.count
        end
        rows[#rows + 1] = row
    end
    -- nothing changes hands yet: the crate item and its contents are swapped when the reveal reports back (or after
    -- a minute, in case the page never does), so the inventory doesn't spoil the 3D unpacking
    local job3d = { slot = job.slot, instanceId = job.instanceId, contents = contents }
    unpacking[source] = job3d
    if cfg.Reveal3D == false then claimCrate(source) end
    SetTimeout(60000, function() if unpacking[source] == job3d then claimCrate(source) end end)
    TriggerLatentClientEvent('meta_comic:client:crateOpened', source, 64 * 1024, { crate = job.crateId, label = crate.label, serial = metadata.serial, contents = rows,
        animation = crate.animation or cfg.Animation3D or 'random' })
end)

if MetaComic.Framework.registerUsableItem and Config.Items.RegisterUsableItems ~= false then
    MetaComic.Framework.registerUsableItem(ITEM, function(source, item) startOpening(source, item and item.slot) end)
end

-- other scripts: exports['<resource>']:GiveShippingCrate(source, 'mixed', count)
exports('GiveShippingCrate', function(source, crateId, count)
    return MetaComic.Rewards.give(tonumber(source), { type = 'crate', crate = crateId or cfg.Default or 'mixed', count = 1 }, math.max(1, math.floor(tonumber(count) or 1)))
end)

-- managers: /<GiveCommand> [crate] [count] gives crates for testing
local function canCreate(source)
    local check = MetaComic.CanManageReal or MetaComic.CanManage
    return source > 0 and check and check(source) == true
end
if MetaComic.RpcHandlers then
    MetaComic.RpcHandlers.getShippingCrates = function(source)
        if not canCreate(source) then return {ok=false,error='You do not have permission to create shipping crates.'} end
        return {ok=true,crates=service.choices(),default=cfg.Default or 'mixed',sets=setChoices()}
    end
    MetaComic.RpcHandlers.createShippingCrate = function(source,payload)
        if not canCreate(source) then return {ok=false,error='You do not have permission to create shipping crates.'} end
        local amount = math.max(1,math.min(20,math.floor(tonumber(payload.amount) or 1)))
        local id = payload.crate or cfg.Default or 'mixed'
        local ok,err = service.give(source,id,amount,payload.sets)
        return {ok=ok == true,error=err,amount=ok and amount or 0,crate=id}
    end
end
if cfg.GiveCommand and cfg.GiveCommand ~= '' then
    RegisterCommand(cfg.GiveCommand, function(source, args)
        if not canCreate(source) then return notify(source,'You do not have permission to create shipping crates.','error') end
        local id = args[1] or cfg.Default or 'mixed'
        if not crateOf(id) then return notify(source, 'Unknown crate: ' .. id, 'error') end
        local ok, err = service.give(source,id,math.max(1,math.min(20,math.floor(tonumber(args[2]) or 1))))
        notify(source, ok and 'Crate given.' or (err or 'Could not give the crate.'), ok and 'success' or 'error')
    end, false)
end
