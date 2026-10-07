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
local serial = 0

local function notify(source, message, notifyType)
    if MetaComic.Framework.notify then MetaComic.Framework.notify(source, message, notifyType) end
end
local function crateOf(id) local crate = (cfg.Crates or {})[id]; return type(crate) == 'table' and crate or nil end
local function crateLabel(id) local crate = crateOf(id); return crate and crate.label or 'Shipping Crate' end
local function newSerial() serial = serial + 1; return ('CR-%s-%04d'):format(os.date('%y%m%d'), (os.time() + serial) % 10000) end

function service.choices()
    local list = {}
    for id, crate in pairs(cfg.Crates or {}) do list[#list + 1] = { id = id, label = crate.label or id } end
    table.sort(list, function(a, b) return a.label < b.label end)
    return list
end
function service.metadata(id)
    local crate = crateOf(id)
    local lines = {}
    for _, entry in ipairs(crate and crate.contents or {}) do
        if (entry.chance or 100) >= 100 then lines[#lines + 1] = MetaComic.Rewards.label(entry) end
    end
    return {
        crate = id, serial = newSerial(), label = crate and crate.label or 'Shipping Crate',
        description = #lines > 0 and ('Contains ' .. table.concat(lines, ', ')) or 'A sealed shipping crate.',
        instanceId = ('crate-%s-%s'):format(os.time(), GetGameTimer() + serial),
    }
end

-- crafting result { type = 'crate', crate = 'mixed' }
MetaComic.Rewards.register('crate', {
    label = function(result) return ('%dx %s'):format(result.count or 1, crateLabel(result.crate)) end,
    validate = function(result) return crateOf(result.crate) ~= nil end,
    canGive = function(source, result, amount)
        return not MetaComic.Inventory.canCarry or MetaComic.Inventory.canCarry(source, ITEM, (result.count or 1) * amount)
    end,
    give = function(source, result, amount)
        for _ = 1, (result.count or 1) * amount do
            if not MetaComic.Inventory.add(source, ITEM, 1, service.metadata(result.crate)) then return false, 'You cannot carry the crate.' end
        end
        return true
    end,
})
if MetaComic.Crafting then MetaComic.Crafting.crateChoices = service.choices end

-- what one crate holds this time: entries with a chance under 100 are rolled
local function roll(crate)
    local list = {}
    for _, entry in ipairs(crate.contents or {}) do
        local chance = tonumber(entry.chance) or 100
        if chance >= 100 or math.random() * 100 < chance then
            if MetaComic.Rewards.valid(entry) then list[#list + 1] = entry
            else print(('[meta-comic] shipping crate content skipped (not valid): %s'):format(json.encode(entry))) end
        end
    end
    return list
end

local function slotItem(source, slot)
    local item = MetaComic.Inventory.getSlot and MetaComic.Inventory.getSlot(source, slot)
    if not item or item.name ~= ITEM then return nil end
    return item, item.metadata or item.info or {}
end

local function startOpening(source, slot)
    slot = tonumber(slot)
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
AddEventHandler('playerDropped', function() pending[source] = nil end)

RegisterNetEvent('meta_comic:server:crateFinish', function()
    local source = source
    local job = pending[source]
    pending[source] = nil
    if not job then return end
    if GetGameTimer() - job.startedAt < job.duration - 750 then return notify(source, 'Opening the crate was interrupted.', 'error') end
    local item, metadata = slotItem(source, job.slot)
    if not item or metadata.instanceId ~= job.instanceId then return notify(source, 'The crate is no longer in your inventory.', 'error') end
    local crate = crateOf(job.crateId)
    local contents = roll(crate)
    for _, entry in ipairs(contents) do
        if not MetaComic.Rewards.canGive(source, entry, 1) then return notify(source, 'Make room first: you cannot carry everything in this crate.', 'error') end
    end
    local identity = metadata.instanceId and { instanceId = metadata.instanceId } or nil
    if not MetaComic.Inventory.remove(source, ITEM, 1, identity, job.slot) then return notify(source, 'Could not open the crate.', 'error') end
    local given, failed = {}, {}
    for _, entry in ipairs(contents) do
        local ok, err = MetaComic.Rewards.give(source, entry, 1)
        local row = { label = MetaComic.Rewards.label(entry), type = entry.type, kind = entry.kind, collectible = entry.collectible, outer = entry.outer == true, count = entry.count or 1, set = entry.set }
        if ok then given[#given + 1] = row else failed[#failed + 1] = row; print('[meta-comic] crate content not given: ' .. tostring(err)) end
    end
    if #given == 0 and #contents > 0 then
        MetaComic.Inventory.add(source, ITEM, 1, metadata) -- nothing came out: the crate goes back
        return notify(source, 'Could not unpack the crate; it was returned.', 'error')
    end
    if #failed > 0 then notify(source, ('%d item(s) from the crate could not be given.'):format(#failed), 'error') end
    TriggerLatentClientEvent('meta_comic:client:crateOpened', source, 64 * 1024, { crate = job.crateId, label = crate.label, serial = metadata.serial, contents = given,
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
if cfg.GiveCommand and cfg.GiveCommand ~= '' then
    RegisterCommand(cfg.GiveCommand, function(source, args)
        if source == 0 or not (MetaComic.CanManage and MetaComic.CanManage(source)) then return end
        local id = args[1] or cfg.Default or 'mixed'
        if not crateOf(id) then return notify(source, 'Unknown crate: ' .. id, 'error') end
        local ok, err = MetaComic.Rewards.give(source, { type = 'crate', crate = id, count = 1 }, math.max(1, math.min(20, tonumber(args[2]) or 1)))
        notify(source, ok and 'Crate given.' or (err or 'Could not give the crate.'), ok and 'success' or 'error')
    end, false)
end
