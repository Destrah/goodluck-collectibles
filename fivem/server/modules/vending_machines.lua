-- Placed vending machine props (Config.VendingMachines). The server owns the list and saves it with the configured
-- persistence (MySQL table, otherwise a JSON file); every client keeps a copy in memory and spawns the props itself
-- only while it is near them (client/vending_machines.lua).
-- Each machine has its own products: { set, kind = 'pack' | 'box', price, stock }, a serial number and the cash paid
-- into it. Who owns it and where its card payments go is in the serial's record (server/modules/vending_registry.lua).
-- Managers can run every machine; a private owner (or a hacker who rerouted it) runs their own: products and prices
-- with "Manage", stock with "Restock" (always real sealed packs / boxes from their inventory), cash with "Collect".
-- Machines are also an item ('vending_machine'): using it places it, "Pick up" turns it back into the item, and the
-- serial, owner, stock and stored cash travel with it.
-- A new machine starts with Config.VendingMachines.Shop.Items.
local cfg = Config.VendingMachines or {}
if cfg.Enabled == false then return end

local resource = GetCurrentResourceName()
local tableName = cfg.Table or 'goodluck_collectibles_vending_machines'
local fileName = cfg.File or 'data/vending_machines.json'
local useMysql = MetaComic.Persistence.name == 'mysql'
local shop = cfg.Shop or {}
local restock = cfg.Restock or {}
local own = cfg.Ownership or {}
local Registry = MetaComic.VendingRegistry
local ITEM = cfg.Item or 'vending_machine'
local MAX_PRODUCTS, MAX_PRICE = 30, 10000000
local MAX_STOCK = math.max(1, math.floor(tonumber(restock.MaxStock) or 100))
-- per kind: Restock.MaxBoxStock caps booster boxes (default: MaxStock)
local function maxStockOf(kind)
    if kind == 'box' then return math.max(1, math.floor(tonumber(restock.MaxBoxStock) or MAX_STOCK)) end
    return MAX_STOCK
end
local MAX_CASH = math.max(0, math.floor(tonumber(shop.MaxCash) or 0)) -- 0: no limit
local machines, order, nextId, ready = {}, {}, 1, false
local stockTransfers = {}
assert(tableName:match('^[%w_]+$'), 'Config.VendingMachines.Table may only use letters, digits and underscores')

local function db() return exports[Config.Database.Resource or 'oxmysql'] end
local function notify(source, message, notifyType)
    if MetaComic.Framework.notify then MetaComic.Framework.notify(source, message, notifyType) end
end
local function canManage(source) return MetaComic.CanManage and MetaComic.CanManage(source) == true end
local function isEmployee(source)
    local test = MetaComic.VendingTestRole and MetaComic.VendingTestRole(source)
    if test then return test.employee == true end
    local job = MetaComic.Framework.getJob and MetaComic.Framework.getJob(source)
    local minGrade = job and job.name and type(restock.Jobs) == 'table' and restock.Jobs[job.name]
    return minGrade ~= nil and minGrade ~= false and (tonumber(job.grade) or 0) >= (tonumber(minGrade) or 0)
end
local function round(n, places) local m = 10 ^ places; return math.floor(n * m + 0.5) / m end
local function finite(n) return type(n) == 'number' and n == n and n ~= math.huge and n ~= -math.huge end
local function whole(n, min, max)
    n = tonumber(n)
    if not finite(n) then return nil end
    n = math.floor(n)
    return n >= min and n <= max and n or nil
end
local function kindOf(kind) return kind == 'box' and 'box' or 'pack' end
local function kindLabel(kind) return kind == 'box' and 'Booster Box' or 'Booster Pack' end
local function getSet(id) return MetaComic.Sets and MetaComic.Sets.get(tostring(id or '')) end
local function playerId(source) return Registry.identifierOf(source) end
local function playerName(source) return Registry.nameOf(source) end

-- Who may do what -----------------------------------------------------------------------------------------------------
local function recordOf(entry) return entry and entry.serial and Registry.get(entry.serial) or nil end
-- the business (managers) runs every machine; a person runs the machines they own, and a hacker the ones they rerouted
-- (the owner keeps access too, so they can reset the routing when they find their machine)
local function controlledBy(record, id)
    if not id then return false end
    return (record ~= nil and record.owner == id) or Registry.controller(record) == id
end
local function controls(source, entry) return controlledBy(recordOf(entry), playerId(source)) end
local function canControl(source, entry) return canManage(source) or controls(source, entry) end
local function canRestock(source, entry)
    if MetaComic.VendingKeys then return MetaComic.VendingKeys.access(source, entry, 'service') end
    if canControl(source, entry) then return true end
    return isEmployee(source) and Registry.controller(recordOf(entry)) == nil -- employees stock the business's machines
end
-- employees look after the business's machines, so they may check those for skimmers (Check coin panel for tampering)
local function businessStaff(source, entry)
    local record = recordOf(entry)
    return record ~= nil and isEmployee(source) and Registry.controller(record) == nil
end
-- a machine chained shut after a break-in (server/modules/vending_keys.lua): players are told so, not "not allowed"
local function sealedText(entry)
    local keysModule = MetaComic.VendingKeys
    return keysModule and keysModule.sealText and keysModule.sealText(recordOf(entry)) or nil
end
local function cabinetAccess(source, entry, level, moving)
    -- a broken-open cabinet needs no key: its owner or a manager can work on it directly (thieves still can't)
    if MetaComic.VendingKeys and MetaComic.VendingLoot and MetaComic.VendingLoot.isOpen(entry) and canControl(source, entry) then return true end
    if MetaComic.VendingKeys then return MetaComic.VendingKeys.access(source, entry, level or 'full', moving) end
    return canControl(source, entry)
end

-- Products ----------------------------------------------------------------------------------------------------------
local function defaultProducts()
    local result, seen = {}, {}
    for _, item in ipairs(shop.Enabled ~= false and type(shop.Items) == 'table' and shop.Items or {}) do
        local setId = (item.set and item.set ~= '') and item.set or (MetaComic.Sets and MetaComic.Sets.defaultId())
        local kind = kindOf(item.kind)
        if setId and not seen[setId .. '|' .. kind] then
            seen[setId .. '|' .. kind] = true
            result[#result + 1] = { set = setId, kind = kind, price = whole(item.price, 0, MAX_PRICE) or 0, stock = 0 }
        end
    end
    return result
end
local function findProduct(entry, setId, kind)
    for index, product in ipairs(entry.products) do
        if product.set == setId and product.kind == kind then return product, index end
    end
end
-- what clients see: products whose set still exists, with names for the menus. withLogos adds each set's logo
-- (menus and the map only; the copy every player keeps in memory stays small)
local function clientProducts(entry, withLogos)
    local result = {}
    for _, product in ipairs(entry.products) do
        local set = getSet(product.set)
        if set then
            result[#result + 1] = {
                set = product.set, setName = set.name or set.id, kind = product.kind, price = product.price, stock = product.stock, maxStock = maxStockOf(product.kind),
                logo = withLogos and MetaComic.SetLogos and MetaComic.SetLogos.get('trading_card', product.set) or nil,
            }
        end
    end
    return result
end
-- sane products from item metadata / old saves
local function cleanProducts(list)
    if type(list) ~= 'table' then return nil end
    local result = {}
    for _, product in ipairs(list) do
        if type(product) == 'table' and product.set and #result < MAX_PRODUCTS then
            result[#result + 1] = { set = tostring(product.set), kind = kindOf(product.kind), price = whole(product.price, 0, MAX_PRICE) or 0, stock = whole(product.stock, 0, maxStockOf(kindOf(product.kind))) or 0 }
        end
    end
    return result
end

-- Storage -----------------------------------------------------------------------------------------------------------
local function list()
    local result = {}
    for _, id in ipairs(order) do result[#result + 1] = machines[id] end
    return result
end
local function clientEntry(entry)
    local record = recordOf(entry)
    return { id = entry.id, model = entry.model, x = entry.x, y = entry.y, z = entry.z, h = entry.h, serial = entry.serial, products = clientProducts(entry),
        systemTakenOver = Registry.systemController(record) ~= nil,
        unlockedUntil = record and record.unlockedUntil or 0,
        lockCondition = record and record.lockCondition, securitySeal = record and record.securitySeal,
        gpsDisabled = record and record.gpsDisabled == true or false, skimmer = record and record.skimmer ~= nil or false }
end
local function saveJson()
    assert(SaveResourceFile(resource, fileName, json.encode(list()), -1), 'Could not save ' .. fileName)
end
local function metaOf(entry) return json.encode({ serial = entry.serial, cash = entry.cash or 0 }) end
-- saves one machine's products, serial and cash; returns true or false
local function saveEntry(entry)
    local ok, err = pcall(function()
        if useMysql then
            assert(db():query_async(('UPDATE `%s` SET products_json = ?, meta_json = ? WHERE id = ?'):format(tableName), { json.encode(entry.products), metaOf(entry), entry.id }), 'database update failed')
        else
            saveJson()
        end
    end)
    if not ok then print('[meta-comic] vending machine save failed: ' .. tostring(err)) end
    return ok
end
local saveProducts = saveEntry
local function index(entry)
    if type(entry.products) ~= 'table' then entry.products = defaultProducts() end
    entry.cash = math.max(0, math.floor(tonumber(entry.cash) or 0))
    machines[entry.id] = entry
    order[#order + 1] = entry.id
    if entry.id >= nextId then nextId = entry.id + 1 end
end
local function unindex(id)
    machines[id] = nil
    for i, value in ipairs(order) do if value == id then table.remove(order, i); break end end
end
local function access(player)
    local controlled = {}
    local fullHack = {}
    local replaceBoard = {}
    local skimmers = {} -- machines with a skimmer this player installed: only they see its Read / Remove options
    local staffed = {} -- business machines an employee may check for skimmers
    local employee = isEmployee(player)
    local manager = canManage(player)
    local id = playerId(player)
    for _, machineId in ipairs(order) do
        if controlledBy(recordOf(machines[machineId]), id) then controlled[#controlled + 1] = machineId end
        local record = recordOf(machines[machineId])
        if record and type(record.skimmer) == 'table' and id and record.skimmer.installer == id then skimmers[#skimmers + 1] = machineId end
        if employee and record and Registry.controller(record) == nil then staffed[#staffed + 1] = machineId end
        if record and record.owner ~= id and not Registry.systemController(record) then fullHack[#fullHack + 1] = machineId end
        if record and Registry.systemController(record) and (manager or record.owner == id) then replaceBoard[#replaceBoard + 1] = machineId end
    end
    local ace = (cfg.Placement or {}).BypassAce
    local police = MetaComic.Police and MetaComic.Police.isPolice and MetaComic.Police.isPolice(player) == true or false
    return { manage = manager, restock = manager or isEmployee(player), controls = controlled, fullHack = fullHack, replaceBoard = replaceBoard,
        skimmers = skimmers, police = police, staffed = staffed,
        placementBypass = type(ace) == 'string' and IsPlayerAceAllowed and IsPlayerAceAllowed(player, ace) == true }
end
local function sendAccess(player) TriggerClientEvent('meta_comic:client:vendingAccess', player, access(player)) end
local function sendAccessAll() for _, player in ipairs(GetPlayers()) do sendAccess(tonumber(player)) end end
local function sendAll(target)
    local payload = {}
    for _, id in ipairs(order) do payload[#payload + 1] = clientEntry(machines[id]) end
    for _, player in ipairs(target == -1 and GetPlayers() or { target }) do
        player = tonumber(player)
        TriggerLatentClientEvent('meta_comic:client:vendingMachines', player, 128 * 1024, payload, access(player))
    end
end
local function broadcast(entry) TriggerClientEvent('meta_comic:client:vendingMachineAdded', -1, clientEntry(entry)) end

-- the serial's record follows the machine: placed here, with these coordinates
local function recordPlaced(entry, event, by)
    local record = recordOf(entry)
    local location = { x = entry.x, y = entry.y, z = entry.z }
    Registry.update(entry.serial, { status = 'placed', machineId = entry.id, coords = location, holder = false,
        gpsOrigin = record and record.gpsOrigin or location }, event, by)
    if MetaComic.VendingKeys then MetaComic.VendingKeys.ensure(Registry.get(entry.serial)) end
end

CreateThread(function()
    if useMysql then
        if Config.Database.AutoCreateSchema then
            db():query_async(([[CREATE TABLE IF NOT EXISTS `%s` (
 `id` INT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
 `model` VARCHAR(64) NOT NULL,
 `x` DOUBLE NOT NULL,
 `y` DOUBLE NOT NULL,
 `z` DOUBLE NOT NULL,
 `heading` DOUBLE NOT NULL,
 `products_json` LONGTEXT NULL,
 `meta_json` LONGTEXT NULL,
 `placed_by` VARCHAR(100) NULL,
 `placed_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4]]):format(tableName))
            -- tables created before machines had their own products / serial numbers
            for _, column in ipairs({ { 'products_json', 'heading' }, { 'meta_json', 'products_json' } }) do
                local found = db():query_async('SELECT 1 FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = ? AND COLUMN_NAME = ?', { tableName, column[1] })
                if not found or not found[1] then
                    db():query_async(('ALTER TABLE `%s` ADD COLUMN `%s` LONGTEXT NULL AFTER `%s`'):format(tableName, column[1], column[2]))
                end
            end
        end
        local rows = db():query_async(('SELECT id, model, x, y, z, heading, products_json, meta_json FROM `%s` ORDER BY id'):format(tableName)) or {}
        for _, row in ipairs(rows) do
            local products, meta
            if row.products_json and row.products_json ~= '' then
                local ok, decoded = pcall(json.decode, row.products_json)
                products = ok and type(decoded) == 'table' and decoded or nil
            end
            if row.meta_json and row.meta_json ~= '' then
                local ok, decoded = pcall(json.decode, row.meta_json)
                meta = ok and type(decoded) == 'table' and decoded or nil
            end
            meta = meta or {}
            index({ id = tonumber(row.id), model = row.model, x = row.x, y = row.y, z = row.z, h = row.heading, products = products, serial = meta.serial, cash = meta.cash })
        end
    else
        local raw = LoadResourceFile(resource, fileName)
        local ok, decoded = pcall(json.decode, raw or '')
        for _, entry in ipairs(ok and type(decoded) == 'table' and decoded or {}) do
            if tonumber(entry.id) then entry.id = tonumber(entry.id); index(entry) end
        end
    end
    -- machines placed before serial numbers: give them one, owned by the business
    for _, id in ipairs(order) do
        local entry = machines[id]
        if not entry.serial or not Registry.get(entry.serial) then
            entry.serial = entry.serial or Registry.newSerial()
            Registry.ensure(entry.serial, {})
            recordPlaced(entry, 'Registered (placed before serial numbers)')
            saveEntry(entry)
        end
    end
    -- the card sets load from the database in their own thread (server/main.lua). The client list leaves out every
    -- product whose set isn't known yet, so sending before they're in gave empty windows after a restart: wait for them
    local function setsLoaded() return MetaComic.Sets and #MetaComic.Sets.getAll() > 0 end
    local waitUntil = GetGameTimer() + 15000
    while not setsLoaded() and GetGameTimer() < waitUntil do Wait(250) end
    ready = true
    print(('[meta-comic] %d vending machine%s loaded (%s)'):format(#order, #order == 1 and '' or 's', useMysql and 'mysql' or fileName))
    sendAll(-1) -- players already online (resource restart) get the list now
    if not setsLoaded() then -- slow database: send the list again once the sets arrive
        waitUntil = GetGameTimer() + 120000
        while not setsLoaded() and GetGameTimer() < waitUntil do Wait(1000) end
        if setsLoaded() then sendAll(-1) end
    end
end)

-- a client loaded this resource and wants the list (before loading finished, the broadcast above covers it)
RegisterNetEvent('meta_comic:server:vendingMachines', function()
    local source = source
    if ready then sendAll(source) end
    Registry.claimPending(source) -- earnings paid while they were offline
end)
-- job changes: the client asks again which vending options it may see
RegisterNetEvent('meta_comic:server:vendingAccess', function()
    local source = source
    sendAccess(source)
    Registry.claimPending(source)
end)

-- the client's ped position, when the server knows it (OneSync); nil otherwise
local function pedCoords(source)
    local ped = GetPlayerPed(source)
    if not ped or ped == 0 then return nil end
    local coords = GetEntityCoords(ped)
    if coords.x == 0.0 and coords.y == 0.0 and coords.z == 0.0 then return nil end
    return coords
end
local function near(source, entry, reach)
    local ped = pedCoords(source)
    return not ped or #(ped - vector3(entry.x, entry.y, entry.z)) <= reach
end
local function interactReach() return (tonumber(shop.TargetDistance) or 2.0) + 3.0 end

-- Placing / removing ------------------------------------------------------------------------------------------------
-- adds a machine at the spot and saves it; returns the entry or nil, error
local function createMachine(source, x, y, z, heading, fields)
    local entry = { model = cfg.Model or 'metacomics_vending_machine', x = round(x, 3), y = round(y, 3), z = round(z, 3), h = round(heading % 360.0, 2),
        products = fields.products or defaultProducts(), serial = fields.serial, cash = fields.cash or 0 }
    if useMysql then
        local id = db():insert_async(('INSERT INTO `%s` (model, x, y, z, heading, products_json, meta_json, placed_by) VALUES (?, ?, ?, ?, ?, ?, ?, ?)'):format(tableName),
            { entry.model, entry.x, entry.y, entry.z, entry.h, json.encode(entry.products), metaOf(entry), MetaComic.GetLicense(source) })
        if not id then return nil, 'Could not save the vending machine.' end
        entry.id = tonumber(id)
        index(entry)
    else
        entry.id = nextId
        index(entry)
        local ok, err = pcall(saveJson)
        if not ok then
            unindex(entry.id)
            print('[meta-comic] ' .. tostring(err))
            return nil, 'Could not save the vending machine.'
        end
    end
    return entry
end
-- deletes the saved machine; returns true or false
local function deleteMachine(entry)
    if useMysql and not db():query_async(('DELETE FROM `%s` WHERE id = ?'):format(tableName), { entry.id }) then return false end
    unindex(entry.id)
    if not useMysql then
        local ok, err = pcall(saveJson)
        if not ok then print('[meta-comic] ' .. tostring(err)) end
    end
    TriggerClientEvent('meta_comic:client:vendingMachineRemoved', -1, entry.id)
    return true
end
local function spotOk(source, x, y, z, heading)
    if not (finite(x) and finite(y) and finite(z) and finite(heading)) then return false end
    local ace = (cfg.Placement or {}).BypassAce
    local bypass = type(ace) == 'string' and IsPlayerAceAllowed and IsPlayerAceAllowed(source, ace)
    if not bypass and (cfg.Placement or {}).Enabled ~= false then
        if type(MetaComic.VendingPlacementZone) ~= 'function' then
            return false, 'Placement checks are unavailable. Update shared/utils.lua and restart rush-tradingcards.'
        end
        local valid, reason = MetaComic.VendingPlacementZone(x, y, z)
        if not valid then return false, reason end
    end
    return near(source, { x = x, y = y, z = z }, (tonumber(cfg.PlaceDistance) or 15.0) + 10.0), 'That spot is too far away from you.'
end

-- managers: /placevending puts down a new machine owned by the business
RegisterNetEvent('meta_comic:server:placeVendingMachine', function(x, y, z, heading)
    local source = source
    if not ready then return notify(source, 'Vending machines are still loading, try again in a moment.', 'error') end
    if not canManage(source) then return notify(source, 'You are not allowed to place vending machines.', 'error') end
    if not (finite(x) and finite(y) and finite(z) and finite(heading)) then return end
    local valid, reason = spotOk(source, x, y, z, heading)
    if not valid then return notify(source, reason or 'Invalid placement location.', 'error') end
    local serial = Registry.newSerial()
    Registry.ensure(serial, {})
    local entry, err = createMachine(source, x, y, z, heading, { serial = serial })
    if not entry then return notify(source, err, 'error') end
    recordPlaced(entry, 'Placed by the business', playerName(source))
    broadcast(entry)
    notify(source, ('Vending machine #%d placed (serial %s).'):format(entry.id, serial), 'success')
end)

RegisterNetEvent('meta_comic:server:removeVendingMachine', function(id)
    local source = source
    id = tonumber(id)
    if not ready or not id then return end
    if not canManage(source) then return notify(source, 'You are not allowed to remove vending machines.', 'error') end
    local entry = machines[id]
    if entry and (stockTransfers[entry.id] or MetaComic.VendingLoot and MetaComic.VendingLoot.busy(entry)) then return notify(source, 'The machine is busy. Wait for the current action to finish.', 'error') end
    if not entry then return notify(source, 'That vending machine no longer exists.', 'error') end
    if not near(source, entry, (tonumber(cfg.RemoveDistance) or 5.0) + 10.0) then
        return notify(source, 'That vending machine is too far away from you.', 'error')
    end
    if not deleteMachine(entry) then return notify(source, 'Could not remove the vending machine.', 'error') end
    if entry.serial then Registry.update(entry.serial, { status = 'removed', machineId = false, coords = false }, 'Removed by the business', playerName(source)) end
    sendAccessAll()
    notify(source, ('Vending machine #%d removed.'):format(id), 'success')
end)

-- Manage > Move machine: same checks as placing, plus the player has to be standing at the machine
RegisterNetEvent('meta_comic:server:moveVendingMachine', function(id, x, y, z, heading)
    local source = source
    local entry = ready and machines[tonumber(id) or 0]
    if entry and (stockTransfers[entry.id] or MetaComic.VendingLoot and MetaComic.VendingLoot.busy(entry)) then return notify(source, 'The machine is busy. Wait for the current action to finish.', 'error') end
    if not entry then return notify(source, 'That vending machine no longer exists.', 'error') end
    if MetaComic.VendingKeys and MetaComic.VendingKeys.busy(entry) then return end
    if not cabinetAccess(source, entry, 'full', true) then return notify(source, 'Unlock the cabinet with a full-access key before moving it.', 'error') end
    if not (finite(x) and finite(y) and finite(z) and finite(heading)) then return end
    local reach = (tonumber(cfg.PlaceDistance) or 15.0) + 10.0
    local target = { x = round(x, 3), y = round(y, 3), z = round(z, 3), h = round(heading % 360.0, 2) }
    if not near(source, entry, reach) or not near(source, target, reach) then
        return notify(source, 'That spot is too far away from you.', 'error')
    end
    local valid, reason = spotOk(source, x, y, z, heading)
    if not valid then return notify(source, reason or 'Invalid placement location.', 'error') end
    local old = { x = entry.x, y = entry.y, z = entry.z, h = entry.h }
    entry.x, entry.y, entry.z, entry.h = target.x, target.y, target.z, target.h
    local ok, err = pcall(function()
        if useMysql then
            assert(db():query_async(('UPDATE `%s` SET x = ?, y = ?, z = ?, heading = ? WHERE id = ?'):format(tableName),
                { entry.x, entry.y, entry.z, entry.h, entry.id }), 'database update failed')
        else
            saveJson()
        end
    end)
    if not ok then
        entry.x, entry.y, entry.z, entry.h = old.x, old.y, old.z, old.h
        print('[meta-comic] vending machine move failed: ' .. tostring(err))
        return notify(source, 'Could not save the new position.', 'error')
    end
    recordPlaced(entry, nil)
    broadcast(entry) -- clients see the new coordinates and respawn the prop there
    notify(source, ('Vending machine #%d moved.'):format(entry.id), 'success')
end)

-- The machine as an item --------------------------------------------------------------------------------------------
local function itemMetadata(serial, products, cash)
    local record = Registry.get(serial)
    local stock = 0
    for _, product in ipairs(products or {}) do stock = stock + (product.stock or 0) end
    return {
        serial = serial, products = products, cash = cash or 0,
        label = ('Vending Machine %s'):format(serial),
        description = ('Serial %s Â· owner %s%s'):format(serial, Registry.ownerName(record), stock > 0 and (' Â· %d in stock'):format(stock) or ''),
    }
end
local function giveMachineItem(source, serial, products, cash)
    if MetaComic.VendingKeys and not MetaComic.VendingKeys.ensure(Registry.get(serial)) then return false end
    if MetaComic.Inventory.canCarry and not MetaComic.Inventory.canCarry(source, ITEM, 1) then return false end
    return MetaComic.Inventory.add(source, ITEM, 1, itemMetadata(serial, products, cash))
end

-- crafting result { type = 'vending' }: a new machine owned by the business
MetaComic.Rewards.register('vending', {
    label = function(result) return ('%dx Vending Machine'):format(result.count or 1) end,
    canGive = function(source, result, amount)
        return not MetaComic.Inventory.canCarry or MetaComic.Inventory.canCarry(source, ITEM, (result.count or 1) * amount)
    end,
    give = function(source, result, amount)
        for _ = 1, (result.count or 1) * amount do
            local serial = Registry.newSerial()
            Registry.update(serial, { status = 'item', holder = { id = playerId(source), name = playerName(source) } }, 'Built', playerName(source))
            if not giveMachineItem(source, serial, nil, 0) then
                Registry.update(serial, { status = 'removed', holder = false }, 'Could not be given')
                return false, 'You cannot carry the vending machine.'
            end
        end
        return true
    end,
})

local function slotMachine(source, slot)
    local item = slot and MetaComic.Inventory.getSlot and MetaComic.Inventory.getSlot(source, slot)
    if not item or item.name ~= ITEM then return nil end
    return item, item.metadata or item.info or {}
end
local placing = {} -- source -> { slot, serial }

local function useMachineItem(source, slot)
    if not ready then return notify(source, 'Vending machines are still loading, try again in a moment.', 'error') end
    local item, metadata = slotMachine(source, tonumber(slot))
    if not item then return notify(source, 'Use the vending machine from your inventory.', 'error') end
    if own.ItemPlacement == 'managers' and not canManage(source) then return notify(source, 'Only the business can set up vending machines.', 'error') end
    local record = metadata.serial and Registry.get(metadata.serial)
    if record and record.status == 'placed' then return notify(source, 'This machine is already standing somewhere (duplicate serial).', 'error') end
    placing[source] = { slot = tonumber(slot), serial = metadata.serial }
    TriggerClientEvent('meta_comic:client:placeVendingItem', source, tonumber(slot))
end
RegisterNetEvent('meta_comic:server:useVendingItem', function(slot) useMachineItem(source, slot) end)
if MetaComic.Framework.registerUsableItem and Config.Items.RegisterUsableItems ~= false then
    MetaComic.Framework.registerUsableItem(ITEM, function(source, item) useMachineItem(source, item and item.slot) end)
end

RegisterNetEvent('meta_comic:server:placeVendingItem', function(x, y, z, heading)
    local source = source
    local job = placing[source]
    placing[source] = nil
    if not job or not ready then return end
    local valid, reason = spotOk(source, x, y, z, heading)
    if not valid then return notify(source, reason or 'Invalid placement location.', 'error') end
    local item, metadata = slotMachine(source, job.slot)
    if not item or metadata.serial ~= job.serial then return notify(source, 'The vending machine is no longer in your inventory.', 'error') end
    local serial = metadata.serial or Registry.newSerial() -- items given by other scripts without one
    local record = Registry.get(serial)
    if record and record.status == 'placed' then return notify(source, 'This machine is already standing somewhere (duplicate serial).', 'error') end
    -- match on the serial only: ox_inventory compares nested metadata (products) by reference, so the full table never matches
    if not MetaComic.Inventory.remove(source, ITEM, 1, metadata.serial and { serial = metadata.serial } or nil, job.slot) then return notify(source, 'Could not take the vending machine item.', 'error') end
    Registry.ensure(serial, {})
    local entry, err = createMachine(source, x, y, z, heading, { serial = serial, products = cleanProducts(metadata.products), cash = whole(metadata.cash, 0, MAX_PRICE * 10) or 0 })
    if not entry then
        MetaComic.Inventory.add(source, ITEM, 1, metadata) -- put it back
        return notify(source, err, 'error')
    end
    local stolen = record and record.status == 'stolen'
    recordPlaced(entry, stolen and ('Set up by %s (stolen machine)'):format(playerName(source)) or ('Set up by %s'):format(playerName(source)), playerName(source))
    if stolen then Registry.update(serial, { stolenAt = record.stolenAt or os.time() }) end
    broadcast(entry)
    sendAccessAll()
    notify(source, ('Vending machine %s set up.'):format(serial), 'success')
end)
RegisterNetEvent('meta_comic:server:cancelVendingItem', function() placing[source] = nil end)

-- turns a standing machine into an item for `source` (owner pick-up, or a thief unbolting it)
local function pickUp(source, entry, status, event)
    if stockTransfers[entry.id] or MetaComic.VendingLoot and MetaComic.VendingLoot.busy(entry) then return false, 'The machine is busy. Wait for the current action to finish.' end
    if MetaComic.Inventory.canCarry and not MetaComic.Inventory.canCarry(source, ITEM, 1) then return false, 'You cannot carry the vending machine.' end
    if not deleteMachine(entry) then return false, 'Could not remove the vending machine.' end
    if not giveMachineItem(source, entry.serial, entry.products, entry.cash) then
        -- inventory refused after all: stand it back up
        local again = createMachine(source, entry.x, entry.y, entry.z, entry.h, { serial = entry.serial, products = entry.products, cash = entry.cash })
        if again then broadcast(again) end
        return false, 'You cannot carry the vending machine.'
    end
    Registry.update(entry.serial, { status = status or 'item', machineId = false, coords = false, holder = { id = playerId(source), name = playerName(source) },
        stolenAt = status == 'stolen' and os.time() or false }, event or ('Picked up by %s'):format(playerName(source)), playerName(source))
    sendAccessAll()
    return true
end

-- Buy / Restock menus: always opened with the server's current products and stock -----------------------------------
local function paymentMethods()
    local mode = shop.Payment or 'both'
    return { cash = mode ~= 'card', card = mode ~= 'cash' }
end
RegisterNetEvent('meta_comic:server:vendingOpen', function(id, mode)
    local source = source
    local entry = ready and machines[tonumber(id) or 0]
    if not entry then return notify(source, 'That vending machine no longer exists.', 'error') end
    mode = mode == 'restock' and 'restock' or 'buy'
    if mode == 'restock' and sealedText(entry) then return notify(source, sealedText(entry), 'error') end
    if mode == 'restock' and not canRestock(source, entry) then return notify(source, 'You are not allowed to restock this vending machine.', 'error') end
    if not near(source, entry, interactReach()) then return notify(source, 'You need to stand at the vending machine.', 'error') end
    if mode == 'restock' then TriggerEvent('meta_comic:server:vendingDoorSuccess', source, entry.id, 'restock') end
    TriggerLatentClientEvent('meta_comic:client:vendingOpen', source, 512 * 1024, entry.id, mode, clientProducts(entry, true), MAX_STOCK, paymentMethods())
end)

-- Manage ------------------------------------------------------------------------------------------------------------
local function setChoices()
    local result = {}
    for _, set in ipairs(MetaComic.Sets and MetaComic.Sets.getAll() or {}) do result[#result + 1] = { id = set.id, name = set.name or set.id } end
    return result
end
local function manageInfo(source, entry)
    local record = recordOf(entry)
    local view = Registry.view(record) or {}
    local manager = canManage(source)
    local people
    local system = Registry.systemController(record)
    local systemAccess = system == playerId(source) or not system and (manager or record and record.owner == playerId(source))
    if manager then
        people = {}
        for _, person in ipairs(Registry.people()) do people[#people + 1] = { id = person.id, name = person.name, routing = person.routing, tax = person.tax } end
    end
    return {
        serial = entry.serial, ownerName = view.ownerName, owner = view.owner, routing = view.routing, routingName = view.routingName,
        ownerRouting = view.ownerRouting, tampered = view.tampered, tax = view.tax, cash = entry.cash or 0, manager = manager,
        gpsDisabled = record and record.gpsDisabled == true,
        canSwitchGPS = (cfg.GPS or {}).Enabled ~= false and systemAccess and cabinetAccess(source, entry, 'full'),
        canSetPayments = systemAccess and cabinetAccess(source, entry, 'full'),
        canReplaceBoard = system ~= nil and (manager or record and record.owner == playerId(source)),
        systemTakenOver = Registry.systemController(record) ~= nil,
        keysEnabled = MetaComic.VendingKeys ~= nil,
        fullAccess = cabinetAccess(source, entry, 'full'),
        lockId = record and record.lockId, lockCondition = record and record.lockCondition, securitySeal = record and record.securitySeal,
        isOwner = record and record.owner ~= nil and record.owner == playerId(source), people = people, business = Registry.businessName,
        sales = record and (manager or record.owner == playerId(source) or controlledBy(record, playerId(source))) and MetaComic.CopyTable(record.sales or {}) or nil,
    }
end
local function openManage(source, entry)
    TriggerLatentClientEvent('meta_comic:client:vendingManage', source, 512 * 1024, entry.id, clientProducts(entry, true), setChoices(), MAX_STOCK, manageInfo(source, entry))
end

RegisterNetEvent('meta_comic:server:vendingManage', function(id)
    local source = source
    local entry = ready and machines[tonumber(id) or 0]
    if not entry then return end
    if sealedText(entry) then return notify(source, sealedText(entry), 'error') end
    if not near(source, entry, interactReach()) or not cabinetAccess(source, entry, 'service') then return notify(source, 'Stand at the machine and unlock its cabinet with a current key.', 'error') end
    openManage(source, entry)
end)

-- action: 'add' { set, kind, price, stock } | 'price' { set, kind, price } | 'stock' { set, kind, stock } | 'remove' { set, kind }
-- One change at a time, so sales made while the menu is open are never overwritten.
local function withdrawStock(source, entry, product, position, target, removeProduct)
    local amount = product.stock - target
    local item = product.kind == 'box' and Config.Items.BoosterBox or Config.Items.BoosterPack
    if amount > 0 and MetaComic.Inventory.canCarry and not MetaComic.Inventory.canCarry(source, item, amount) then
        return notify(source, 'You cannot carry that stock.', 'error')
    end
    stockTransfers[entry.id] = true
    local backup = MetaComic.CopyTable(entry.products)
    product.stock = target
    if removeProduct then table.remove(entry.products, position) end
    local saved = saveProducts(entry)
    local given, reason = true, nil
    if saved and MetaComic.VendingKeys and not cabinetAccess(source, entry, 'full') then given, reason = false, 'Key access expired or changed.' end
    if saved and given and amount > 0 then
        local ok, result, message = pcall(MetaComic.GiveSealed, source, product.kind, product.set, amount)
        given, reason = ok and result == true, ok and message or result
    end
    if not saved or not given then
        entry.products = backup
        if saved then saveProducts(entry) end
        stockTransfers[entry.id] = nil
        broadcast(entry)
        return notify(source, tostring(reason or 'Could not save or return the stock.'), 'error')
    end
    stockTransfers[entry.id] = nil
    broadcast(entry)
    notify(source, ('Took out %d stock item(s).'):format(amount), 'success')
    openManage(source, entry)
end

RegisterNetEvent('meta_comic:server:vendingProduct', function(id, action, data)
    local source = source
    local entry = ready and machines[tonumber(id) or 0]
    if entry and (stockTransfers[entry.id] or MetaComic.VendingLoot and MetaComic.VendingLoot.busy(entry)) then return notify(source, 'The machine is busy. Wait for the current action to finish.', 'error') end
    if not entry or type(data) ~= 'table' then return end
    if MetaComic.VendingKeys and MetaComic.VendingKeys.busy(entry) then return end
    if not cabinetAccess(source, entry, action == 'price' and 'service' or 'full') then return notify(source, 'Unlock with a current key with sufficient access.', 'error') end
    if not near(source, entry, 15.0) then return notify(source, 'That vending machine is too far away from you.', 'error') end
    local setId, kind = tostring(data.set or ''), kindOf(data.kind)
    local set = getSet(setId)
    local product, position = findProduct(entry, setId, kind)
    local backup = MetaComic.CopyTable(entry.products)
    if action == 'add' then
        if not set then return notify(source, ('Unknown card set: %s'):format(setId), 'error') end
        local price = whole(data.price, 0, MAX_PRICE)
        if not price then return notify(source, ('Price must be 0-%d.'):format(MAX_PRICE), 'error') end
        if product then
            product.price = price
        else
            if #entry.products >= MAX_PRODUCTS then return notify(source, ('A machine can sell at most %d products.'):format(MAX_PRODUCTS), 'error') end
            entry.products[#entry.products + 1] = { set = setId, kind = kind, price = price, stock = 0 } -- filled with Restock
        end
    elseif not product then
        return notify(source, 'That product is not in this machine anymore.', 'error')
    elseif action == 'price' then
        local price = whole(data.price, 0, MAX_PRICE)
        if not price then return notify(source, ('Price must be 0-%d.'):format(MAX_PRICE), 'error') end
        product.price = price
    elseif action == 'stock' then
        if not near(source, entry, interactReach()) then return notify(source, 'Stand at the machine to take stock out.', 'error') end
        -- Lowering returns real items; additions still require Restock.
        local stock = whole(data.stock, 0, product.stock)
        if not stock then return notify(source, ('Stock can only be lowered here (0-%d). Use Restock to add.'):format(product.stock), 'error') end
        return withdrawStock(source, entry, product, position, stock, false)
    elseif action == 'withdraw' then
        if not near(source, entry, interactReach()) then return notify(source, 'Stand at the machine to take stock out.', 'error') end
        local amount = whole(data.amount, 1, product.stock)
        if not amount or product.stock <= 0 then return notify(source, 'Choose an available stock amount.', 'error') end
        return withdrawStock(source, entry, product, position, product.stock - amount, false)
    elseif action == 'remove' then
        if not near(source, entry, interactReach()) then return notify(source, 'Stand at the machine to take stock out.', 'error') end
        return withdrawStock(source, entry, product, position, 0, true)
    else
        return
    end
    if not saveProducts(entry) then
        entry.products = backup
        return notify(source, 'Could not save the vending machine.', 'error')
    end
    broadcast(entry)
    openManage(source, entry)
end)

local startWork -- timed restocking / cash collection, below
-- Owner actions: 'collect' (cash), 'pickup', 'resetRouting', 'assign' { owner }, 'certificate'
local function ownerAction(source, id, action, data, timed)
    local entry = ready and machines[tonumber(id) or 0]
    if entry and (stockTransfers[entry.id] or MetaComic.VendingLoot and MetaComic.VendingLoot.busy(entry)) then return notify(source, 'The machine is busy. Wait for the current action to finish.', 'error') end
    if not entry then return notify(source, 'That vending machine no longer exists.', 'error') end
    if not near(source, entry, interactReach()) then return notify(source, 'You need to stand at the vending machine.', 'error') end
    local record = recordOf(entry)
    local manager = canManage(source)
    local by = playerName(source)
    if MetaComic.VendingKeys and MetaComic.VendingKeys.busy(entry) then return end
    if not cabinetAccess(source, entry, 'full') then return notify(source, 'Unlock the cabinet with a full-access key first.', 'error') end
    if action == 'assign' then
        if not manager then return notify(source, 'Only the business can assign owners.', 'error') end
        local ok, err = Registry.assign(entry.serial, type(data) == 'table' and data.owner or Registry.BUSINESS, by)
        if not ok then return notify(source, err, 'error') end
        sendAccessAll()
        notify(source, ('%s now belongs to %s.'):format(entry.serial, Registry.ownerName(ok)), 'success')
        broadcast(entry)
        if type(data) == 'table' and data.certificate and MetaComic.VendingRecords then MetaComic.VendingRecords.giveCertificate(source, entry.serial) end
        return openManage(source, entry)
    end
    if not MetaComic.VendingKeys and not canControl(source, entry) then return notify(source, 'You are not allowed to do that.', 'error') end
    if action == 'payments' then
        local system = Registry.systemController(record)
        if system and system ~= playerId(source) or not system and not manager and not (record and record.owner == playerId(source)) then
            return notify(source, 'Full operating-system access is required to change payment recipients.', 'error')
        end
        if type(data) ~= 'table' then return end
        local recipient
        if data.mode == 'player' then
            local target = tonumber(data.value)
            if target and target >= 1 and target <= 65535 and target == math.floor(target) and GetPlayerPing(target) > 0 then
                local identifier = Registry.identifierOf(target)
                local person = Registry.person(identifier)
                recipient = { id = identifier, name = Registry.nameOf(target), number = person and person.routing or Registry.newRouting(), manual = true }
            end
        elseif data.mode == 'routing' and type(data.value) == 'string' and #data.value <= 64 then
            for _, person in ipairs(Registry.people()) do
                if person.routing == data.value then recipient = { id = person.id, name = person.name, number = person.routing, manual = true }; break end
            end
            if data.value == Registry.businessRouting() then
                recipient = { id = Registry.BUSINESS, name = Registry.businessName, number = data.value, manual = true }
            end
        end
        if not recipient then return notify(source, 'Choose an online player ID or a registered routing number.', 'error') end
        local old = MetaComic.CopyTable(record)
        Registry.update(entry.serial, { routing = recipient, tampered = true,
            routingUntil = false }, 'Payment recipient changed manually', by)
        if not Registry.save() then
            for key in pairs(record) do record[key] = nil end
            for key, value in pairs(old) do record[key] = value end
            return notify(source, 'Could not save the payment recipient.', 'error')
        end
        sendAccessAll()
        notify(source, 'Card payments will go to the selected recipient.', 'success')
        return openManage(source, entry)
    end
    if action == 'gps' then
        local system = Registry.systemController(record)
        if system and system ~= playerId(source) or not system and not manager and not (record and record.owner == playerId(source)) then
            return notify(source, 'Full operating-system access is required to switch GPS here.', 'error')
        end
        if MetaComic.VendingSecurity.gps(source, entry, record and record.gpsDisabled == true) then return openManage(source, entry) end
        return
    end
    if action == 'collect' then
        -- the business collects from its own machines; a person's cash is theirs (or the hacker's who took it over)
        if not MetaComic.VendingKeys and not controls(source, entry) and Registry.controller(record) ~= nil then return notify(source, 'This cash belongs to the machine\'s owner.', 'error') end
        local amount = entry.cash or 0
        if amount <= 0 then return notify(source, 'There is no cash in this machine.', 'error') end
        -- taking the cash plays out first (Config.VendingMachines.Work); this runs again when it's done
        if not timed and startWork then return startWork(source, entry, 'cash', amount, { id, action, data }) end
        stockTransfers[entry.id] = true
        entry.cash = 0
        if not saveEntry(entry) then entry.cash = amount; stockTransfers[entry.id] = nil; return notify(source, 'Could not save the vending machine.', 'error') end
        if MetaComic.VendingKeys and not cabinetAccess(source, entry, 'full') then
            entry.cash = amount; saveEntry(entry); stockTransfers[entry.id] = nil
            return notify(source, 'Key access expired or changed. Cash remains in the machine.', 'error')
        end
        -- a person's machine: the business's tax share of the cash goes straight to the business
        local tax = record and record.owner == playerId(source) and Registry.cashTax(record, amount) or 0
        if not MetaComic.Money.add(source, shop.CashAccount or 'cash', amount - tax, 'vending cash') then
            entry.cash = amount; saveEntry(entry)
            stockTransfers[entry.id] = nil
            return notify(source, 'Could not give you the cash.', 'error')
        end
        Registry.update(entry.serial, nil, ('$%d cash collected by %s'):format(amount, by), by)
        stockTransfers[entry.id] = nil
        notify(source, tax > 0 and ('Collected $%d ($%d tax to %s).'):format(amount - tax, tax, Registry.businessName) or ('Collected $%d.'):format(amount), 'success')
        return openManage(source, entry)
    elseif action == 'pickup' then
        if own.AllowPickup == false and not manager then return notify(source, 'Only the business can pick machines up.', 'error') end
        local ok, err = pickUp(source, entry, 'item')
        return notify(source, ok and ('Picked up vending machine %s.'):format(entry.serial) or err, ok and 'success' or 'error')
    elseif action == 'resetRouting' then
        -- the owner (or the business) fixes a hacked machine; a hacker can't "reset" it to themselves
        if not manager and not (record and record.owner == playerId(source)) then return notify(source, 'Only the owner can reset the routing.', 'error') end
        local ok, err = Registry.resetRouting(entry.serial, by)
        if not ok then return notify(source, err, 'error') end
        sendAccessAll()
        broadcast(entry)
        notify(source, 'Card payments go to the owner again.', 'success')
        return openManage(source, entry)
    elseif action == 'certificate' then
        if MetaComic.VendingRecords then MetaComic.VendingRecords.giveCertificate(source, entry.serial) end
    end
end
RegisterNetEvent('meta_comic:server:vendingOwner', function(id, action, data) ownerAction(source, id, action, data, false) end)

-- Map of every machine for managers (admin UI "Vending machines" tab) ------------------------------------------------
if MetaComic.RpcHandlers then
    MetaComic.RpcHandlers.getVendingMachines = function(source)
        -- managers see every machine; owners using the portal (Config.Portal) only their own
        local ownerId = not canManage(source) and MetaComic.Portal and MetaComic.Portal.ownerScope(source, 'vending')
        if not canManage(source) and not ownerId then return { ok = false, error = 'You are not allowed to manage vending machines.' } end
        local list = {}
        for _, id in ipairs(order) do
            local entry = machines[id]
            local record = recordOf(entry)
            if not ownerId or record and record.owner == ownerId then
                local view = Registry.view(record) or {}
                list[#list + 1] = { id = entry.id, x = entry.x, y = entry.y, z = entry.z, products = clientProducts(entry), serial = entry.serial,
                    ownerName = view.ownerName, tampered = view.tampered, cash = entry.cash or 0 }
            end
        end
        -- machines with GPS on that aren't standing anywhere: their last fix (carried as an item, dropped, towed)
        local security = MetaComic.VendingSecurity
        if security and security.gpsPosition then
            local n = 0
            for _, record in ipairs(Registry.all()) do
                local fix = record.status ~= 'removed' and not record.gpsDisabled and security.gpsPosition(record.serial)
                if fix and (not ownerId or record.owner == ownerId) then
                    n = n + 1
                    local view = Registry.view(record) or {}
                    list[#list + 1] = { id = -n, x = fix.x, y = fix.y, z = fix.z, serial = record.serial, ownerName = view.ownerName,
                        tampered = view.tampered, tracked = fix.how, holderName = fix.holder, seenAt = fix.at }
                end
            end
        end
        return {
            ok = true,
            machines = list,
            logos = MetaComic.SetLogos and MetaComic.SetLogos.all('trading_card') or {}, -- once per set, not per product
            maxStock = MAX_STOCK,
            map = cfg.Map or {},
        }
    end
end

-- Restock -----------------------------------------------------------------------------------------------------------
-- The player's inventory slots holding sealed pack / box items of this set, and how many items they hold together.
local function sealedSlots(source, kind, setId)
    local item = kind == 'box' and Config.Items.BoosterBox or Config.Items.BoosterPack
    local defaultId = MetaComic.Sets and MetaComic.Sets.defaultId()
    local slots, total = {}, 0
    for _, slot in pairs(MetaComic.Inventory.slotsOf and MetaComic.Inventory.slotsOf(source, item) or {}) do
        local metadata = type(slot) == 'table' and (slot.metadata or slot.info) or {}
        if tostring(metadata.setId or metadata.seriesId or metadata.set or defaultId) == setId then
            local count = tonumber(slot.count or slot.amount) or 1
            slots[#slots + 1] = { slot = slot.slot, metadata = metadata, count = count }
            total = total + count
        end
    end
    return item, slots, total
end
-- Takes exactly `wanted` items of this set, or nothing (whatever was taken is given back). Returns true / false, held.
local function takeSealed(source, kind, setId, wanted)
    local item, slots, total = sealedSlots(source, kind, setId)
    if total < wanted then return false, total end
    local taken = 0
    for _, slot in ipairs(slots) do
        local amount = math.min(wanted - taken, slot.count)
        if amount > 0 and MetaComic.Inventory.remove(source, item, amount, slot.metadata, slot.slot) then taken = taken + amount end
        if taken >= wanted then break end
    end
    if taken < wanted then
        if taken > 0 then MetaComic.GiveSealed(source, kind, setId, taken) end
        return false, total
    end
    return true, total
end

local function restock(source, id, setId, kind, amount, timed)
    local entry = ready and machines[tonumber(id) or 0]
    if entry and (stockTransfers[entry.id] or MetaComic.VendingLoot and MetaComic.VendingLoot.busy(entry)) then return notify(source, 'The machine is busy. Wait for the current action to finish.', 'error') end
    if not entry then return end
    if MetaComic.VendingKeys and MetaComic.VendingKeys.busy(entry) then return end
    if sealedText(entry) then return notify(source, sealedText(entry), 'error') end
    if not canRestock(source, entry) then return notify(source, 'You are not allowed to restock this vending machine.', 'error') end
    if not near(source, entry, interactReach()) then return notify(source, 'You need to stand at the vending machine.', 'error') end
    setId, kind = tostring(setId or ''), kindOf(kind)
    local product = findProduct(entry, setId, kind)
    if not product then return notify(source, 'That product is not in this machine anymore.', 'error') end
    local room = maxStockOf(product.kind) - product.stock
    amount = whole(amount, 1, math.max(1, room))
    if room <= 0 or not amount then return notify(source, ('This product is full (%d).'):format(maxStockOf(product.kind)), 'error') end
    -- loading the packs plays out first (Config.VendingMachines.Work); this runs again when it's done
    if not timed and startWork then return startWork(source, entry, 'restock', amount, { id, setId, kind, amount }, product.kind) end
    stockTransfers[entry.id] = true
    -- everyone restocks with the real items: that many sealed packs / boxes of this set from their inventory
    local taken, held = takeSealed(source, kind, setId, amount)
    if taken and MetaComic.VendingKeys and not canRestock(source, entry) then
        MetaComic.GiveSealed(source, kind, setId, amount)
        stockTransfers[entry.id] = nil
        return notify(source, 'Key access expired or changed. Stock returned.', 'error')
    end
    if not taken then
        stockTransfers[entry.id] = nil
        local set = getSet(setId)
        return notify(source, ('You need %d %s %s%s in your inventory (you have %d).'):format(amount, set and set.name or setId, kindLabel(kind), amount == 1 and '' or (kind == 'box' and 'es' or 's'), held), 'error')
    end
    product.stock = product.stock + amount
    if not saveProducts(entry) then
        product.stock = product.stock - amount
        MetaComic.GiveSealed(source, kind, setId, amount) -- give the items back so nothing is lost
        stockTransfers[entry.id] = nil
        return notify(source, 'Could not save the vending machine.', 'error')
    end
    broadcast(entry)
    TriggerEvent('meta_comic:server:vendingDoorSuccess', source, entry.id, 'restock')
    notify(source, ('Restocked %d (now %d).'):format(amount, product.stock), 'success')
    stockTransfers[entry.id] = nil
end
RegisterNetEvent('meta_comic:server:vendingRestock', function(id, setId, kind, amount) restock(source, id, setId, kind, amount, false) end)

-- Timed restocking and cash collection (Config.VendingMachines.Work): the player plays it out (loading packs / taking
-- the cash) behind a progress bar, and the server only applies it once that time has really passed.
local work = cfg.Work or {}
local working = {} -- source -> job
local function workSettings(kind) return (kind == 'cash' and work.Cash or work.Restock) or {} end
local function workTime(kind, units)
    local s = workSettings(kind)
    local unit = kind == 'cash' and math.max(1, tonumber(s.Unit) or 100) or 1
    local ms = (tonumber(s.BaseMs) or 2000) + (tonumber(s.PerUnitMs) or (kind == 'cash' and 1000 or 1500)) * math.ceil(units / unit)
    return math.floor(math.max(1000, math.min(tonumber(s.MaxMs) or 45000, ms)))
end
local function finishWork(source, job)
    if job.kind == 'cash' then return ownerAction(source, job.args[1], job.args[2], job.args[3], true) end
    restock(source, job.args[1], job.args[2], job.args[3], job.args[4], true)
end
startWork = function(source, entry, kind, units, args, productKind)
    if work.Enabled == false then return finishWork(source, { kind = kind, args = args }) end
    local job = working[source]
    if job and GetGameTimer() - job.at < job.duration + 10000 then return notify(source, 'Finish what you are doing first.', 'error') end
    local s = workSettings(kind)
    job = { token = ('%d:%d:%d'):format(source, GetGameTimer(), math.random(1, 1000000000)), kind = kind, args = args,
        at = GetGameTimer(), duration = workTime(kind, units) }
    working[source] = job
    if kind == 'restock' then TriggerEvent('meta_comic:server:vendingDoorSuccess', source, entry.id, 'restock') end
    TriggerClientEvent('meta_comic:client:vendingWork', source, { token = job.token, id = entry.id, kind = kind, productKind = productKind,
        duration = job.duration, cycle = tonumber(s.CycleMs) or (kind == 'cash' and 2500 or 2000),
        label = kind == 'cash' and 'Taking the cash' or ('Loading %d %s'):format(units, productKind == 'box' and 'card boxes' or 'card packs') })
end
RegisterNetEvent('meta_comic:server:vendingWorkFinish', function(token)
    local source, job = source, working[source]
    working[source] = nil
    if not job or job.token ~= token then return end
    if GetGameTimer() - job.at < job.duration * 0.9 then return notify(source, 'You stopped too early.', 'error') end
    finishWork(source, job)
end)
RegisterNetEvent('meta_comic:server:vendingWorkCancel', function() working[source] = nil end)
AddEventHandler('playerDropped', function() working[source] = nil end)

-- Buying ------------------------------------------------------------------------------------------------------------
-- Cash goes into the machine (it can be collected, or stolen in a break-in). Card payments go straight to whoever
-- the machine's serial routes to (the owner, minus their tax for the business), unless it was hacked.
local buying = {}
local function cardAccount() return shop.Account or 'bank' end
local function cashAccount() return shop.CashAccount or 'cash' end

RegisterNetEvent('meta_comic:server:vendingBuy', function(id, setId, kind, method)
    local source = source
    local entry = ready and machines[tonumber(id) or 0]
    if entry and (stockTransfers[entry.id] or MetaComic.VendingLoot and MetaComic.VendingLoot.busy(entry)) then return notify(source, 'The machine is busy. Wait for the current action to finish.', 'error') end
    if not entry or buying[source] or shop.Enabled == false then return end
    setId, kind = tostring(setId or ''), kindOf(kind)
    local methods = paymentMethods()
    method = method == 'cash' and 'cash' or method == 'card' and 'card' or (methods.card and 'card' or 'cash')
    if not methods[method] then return notify(source, 'This machine does not take that payment.', 'error') end
    local product = findProduct(entry, setId, kind)
    if not product then return notify(source, 'That product is not in this machine anymore.', 'error') end
    if not near(source, entry, interactReach()) then return notify(source, 'You need to stand at the vending machine.', 'error') end
    local price = product.price
    if method == 'cash' and MAX_CASH > 0 and (entry.cash or 0) + price > MAX_CASH then
        return notify(source, 'The cash box is full: pay by card.', 'error')
    end
    local item = kind == 'box' and Config.Items.BoosterBox or Config.Items.BoosterPack
    if MetaComic.Inventory.canCarry and not MetaComic.Inventory.canCarry(source, item, 1) then
        return notify(source, 'You cannot carry that.', 'error')
    end
    -- check and reserve with nothing in between that could wait, so two buyers can never both take the last one
    if product.stock < 1 then return notify(source, 'Sold out.', 'error') end
    buying[source] = true
    stockTransfers[entry.id] = true
    product.stock = product.stock - 1
    local sold, soldName = false, nil
    local account = method == 'cash' and cashAccount() or cardAccount()
    local ok, err = pcall(function()
        if price > 0 and not MetaComic.Money.remove(source, account, price, 'trading-card-vending') then
            return notify(source, method == 'cash' and ('You need $%d in cash.'):format(price) or ('You need $%d in your account.'):format(price), 'error')
        end
        -- everyone nearby sees the pack drop into the tray; the buyer gets it once it lands
        local drop = cfg.SlotPacks or {}
        if drop.Enabled ~= false then
            TriggerClientEvent('meta_comic:client:vendingDrop', -1, entry.id, product.set, kind)
            Wait(math.max(0, tonumber(drop.DropMs) or 1500) + 200)
        end
        local given, result = MetaComic.GiveSealed(source, kind, setId, 1)
        if not given then
            if price > 0 then MetaComic.Money.add(source, account, price, 'trading-card-vending-refund') end
            return notify(source, result, 'error')
        end
        sold = true
        soldName = ('%s %s'):format(result.name or result.id, kindLabel(kind))
        notify(source, ('Bought %s %s for $%d (%s).'):format(result.name or result.id, kindLabel(kind), price, method), 'success')
    end)
    buying[source] = nil
    if not sold then product.stock = product.stock + 1 end
    if not ok then print('[meta-comic] vending purchase failed: ' .. tostring(err)) end
    if sold then
        local settlementOk, settlementError = pcall(function()
            if price > 0 then
                if method == 'cash' then
                    entry.cash = (entry.cash or 0) + price
                    if Registry.logSale then Registry.logSale(entry.serial, { at = os.time(), method = 'cash', price = price, item = soldName }) end
                else
                    local remaining = MetaComic.VendingSecurity and MetaComic.VendingSecurity.cardSale(entry, source, price) or price
                    local paid, tax = Registry.paySale(Registry.ensure(entry.serial), remaining)
                    if Registry.logSale then Registry.logSale(entry.serial, { at = os.time(), method = 'card', price = price, tax = tax, paid = paid, item = soldName }) end
                end
            end
            saveEntry(entry)
            broadcast(entry)
        end)
        if not settlementOk then print('[meta-comic] vending settlement failed: ' .. tostring(settlementError)) end
    end
    stockTransfers[entry.id] = nil
end)
AddEventHandler('playerDropped', function() buying[source] = nil; placing[source] = nil end)

-- Commands are registered on the server so only managers can start placement / removal.
local function command(name, clientEvent, deniedMessage)
    if not name or name == '' then return end
    RegisterCommand(name, function(source)
        if source == 0 then return print('[meta-comic] /' .. name .. ' is an in-game command.') end
        if not canManage(source) then return notify(source, deniedMessage, 'error') end
        TriggerClientEvent(clientEvent, source)
    end, false)
end
command(cfg.Command or 'placevending', 'meta_comic:client:placeVendingMachine', 'You are not allowed to place vending machines.')
command(cfg.RemoveCommand or 'removevending', 'meta_comic:client:removeVendingMachine', 'You are not allowed to remove vending machines.')

-- For the crime and records modules
MetaComic.Vending = {
    get = function(id) return ready and machines[tonumber(id) or 0] or nil end,
    bySerial = function(serial) for _, id in ipairs(order) do if machines[id].serial == serial then return machines[id] end end end,
    all = list,
    save = saveEntry,
    broadcast = broadcast,
    near = near,
    reach = interactReach,
    pickUp = pickUp,
    canManage = canManage,
    isTransferringStock = function(entry) return entry and stockTransfers[entry.id] == true end,
    canControl = canControl,
    openManage = openManage,
    sendAccessAll = sendAccessAll,
    sendAccess = sendAccess,
    businessStaff = businessStaff,
    giveMachineItem = giveMachineItem,
    giveSealed = function(source, kind, setId, count) return MetaComic.GiveSealed(source, kind, setId, count) end,
}

-- other scripts: exports['<resource>']:GiveVendingMachine(source) gives a new machine item owned by the business
exports('GiveVendingMachine', function(source, count)
    return MetaComic.Rewards.give(tonumber(source), { type = 'vending', count = 1 }, math.max(1, math.floor(tonumber(count) or 1)))
end)
