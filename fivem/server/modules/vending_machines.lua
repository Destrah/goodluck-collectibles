-- Placed vending machine props (Config.VendingMachines). The server owns the list and saves it with the configured
-- persistence (MySQL table, otherwise a JSON file); every client keeps a copy in memory and spawns the props itself
-- only while it is near them (client/vending_machines.lua).
-- Each machine has its own products: { set, kind = 'pack' | 'box', price, stock }. Managers change them from the
-- ox_target "Manage" option; managers and employees (Config.VendingMachines.Restock.Jobs) refill stock with "Restock",
-- which always takes that many sealed packs / boxes of the set from their inventory.
-- A new machine starts with Config.VendingMachines.Shop.Items.
local cfg = Config.VendingMachines or {}
if cfg.Enabled == false then return end

local resource = GetCurrentResourceName()
local tableName = cfg.Table or 'goodluck_collectibles_vending_machines'
local fileName = cfg.File or 'data/vending_machines.json'
local useMysql = MetaComic.Persistence.name == 'mysql'
local shop = cfg.Shop or {}
local restock = cfg.Restock or {}
local MAX_PRODUCTS, MAX_PRICE = 30, 10000000
local MAX_STOCK = math.max(1, math.floor(tonumber(restock.MaxStock) or 100))
local machines, order, nextId, ready = {}, {}, 1, false
assert(tableName:match('^[%w_]+$'), 'Config.VendingMachines.Table may only use letters, digits and underscores')

local function db() return exports[Config.Database.Resource or 'oxmysql'] end
local function notify(source, message, notifyType)
    if MetaComic.Framework.notify then MetaComic.Framework.notify(source, message, notifyType) end
end
local function canManage(source) return MetaComic.CanManage and MetaComic.CanManage(source) == true end
local function isEmployee(source)
    local job = MetaComic.Framework.getJob and MetaComic.Framework.getJob(source)
    local minGrade = job and job.name and type(restock.Jobs) == 'table' and restock.Jobs[job.name]
    return minGrade ~= nil and minGrade ~= false and (tonumber(job.grade) or 0) >= (tonumber(minGrade) or 0)
end
local function canRestock(source) return canManage(source) or isEmployee(source) end
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
                set = product.set, setName = set.name or set.id, kind = product.kind, price = product.price, stock = product.stock,
                logo = withLogos and MetaComic.SetLogos and MetaComic.SetLogos.get('trading_card', product.set) or nil,
            }
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
    return { id = entry.id, model = entry.model, x = entry.x, y = entry.y, z = entry.z, h = entry.h, products = clientProducts(entry) }
end
local function saveJson()
    assert(SaveResourceFile(resource, fileName, json.encode(list()), -1), 'Could not save ' .. fileName)
end
-- saves one machine's products; returns true or false
local function saveProducts(entry)
    local ok, err = pcall(function()
        if useMysql then
            assert(db():query_async(('UPDATE `%s` SET products_json = ? WHERE id = ?'):format(tableName), { json.encode(entry.products), entry.id }), 'database update failed')
        else
            saveJson()
        end
    end)
    if not ok then print('[meta-comic] vending machine save failed: ' .. tostring(err)) end
    return ok
end
local function index(entry)
    if type(entry.products) ~= 'table' then entry.products = defaultProducts() end
    machines[entry.id] = entry
    order[#order + 1] = entry.id
    if entry.id >= nextId then nextId = entry.id + 1 end
end
local function access(player) return { manage = canManage(player), restock = canRestock(player) } end
local function sendAll(target)
    local payload = {}
    for _, id in ipairs(order) do payload[#payload + 1] = clientEntry(machines[id]) end
    for _, player in ipairs(target == -1 and GetPlayers() or { target }) do
        player = tonumber(player)
        TriggerLatentClientEvent('meta_comic:client:vendingMachines', player, 128 * 1024, payload, access(player))
    end
end
local function broadcast(entry) TriggerClientEvent('meta_comic:client:vendingMachineAdded', -1, clientEntry(entry)) end

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
 `placed_by` VARCHAR(100) NULL,
 `placed_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4]]):format(tableName))
            -- tables created before machines had their own products
            local column = db():query_async('SELECT 1 FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = ? AND COLUMN_NAME = ?', { tableName, 'products_json' })
            if not column or not column[1] then
                db():query_async(('ALTER TABLE `%s` ADD COLUMN `products_json` LONGTEXT NULL AFTER `heading`'):format(tableName))
            end
        end
        local rows = db():query_async(('SELECT id, model, x, y, z, heading, products_json FROM `%s` ORDER BY id'):format(tableName)) or {}
        for _, row in ipairs(rows) do
            local products
            if row.products_json and row.products_json ~= '' then
                local ok, decoded = pcall(json.decode, row.products_json)
                products = ok and type(decoded) == 'table' and decoded or nil
            end
            index({ id = tonumber(row.id), model = row.model, x = row.x, y = row.y, z = row.z, h = row.heading, products = products })
        end
    else
        local raw = LoadResourceFile(resource, fileName)
        local ok, decoded = pcall(json.decode, raw or '')
        for _, entry in ipairs(ok and type(decoded) == 'table' and decoded or {}) do
            if tonumber(entry.id) then entry.id = tonumber(entry.id); index(entry) end
        end
    end
    ready = true
    print(('[meta-comic] %d vending machine%s loaded (%s)'):format(#order, #order == 1 and '' or 's', useMysql and 'mysql' or fileName))
    sendAll(-1) -- players already online (resource restart) get the list now
end)

-- a client loaded this resource and wants the list (before loading finished, the broadcast above covers it)
RegisterNetEvent('meta_comic:server:vendingMachines', function()
    if ready then sendAll(source) end
end)
-- job changes: the client asks again which vending options it may see
RegisterNetEvent('meta_comic:server:vendingAccess', function()
    TriggerClientEvent('meta_comic:client:vendingAccess', source, access(source))
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
RegisterNetEvent('meta_comic:server:placeVendingMachine', function(x, y, z, heading)
    local source = source
    if not ready then return notify(source, 'Vending machines are still loading, try again in a moment.', 'error') end
    if not canManage(source) then return notify(source, 'You are not allowed to place vending machines.', 'error') end
    if not (finite(x) and finite(y) and finite(z) and finite(heading)) then return end
    local entry = { model = cfg.Model or 'metacomics_vending_machine', x = round(x, 3), y = round(y, 3), z = round(z, 3), h = round(heading % 360.0, 2), products = defaultProducts() }
    if not near(source, entry, (tonumber(cfg.PlaceDistance) or 15.0) + 10.0) then
        return notify(source, 'That spot is too far away from you.', 'error')
    end
    if useMysql then
        local id = db():insert_async(('INSERT INTO `%s` (model, x, y, z, heading, products_json, placed_by) VALUES (?, ?, ?, ?, ?, ?, ?)'):format(tableName),
            { entry.model, entry.x, entry.y, entry.z, entry.h, json.encode(entry.products), MetaComic.GetLicense(source) })
        if not id then return notify(source, 'Could not save the vending machine.', 'error') end
        entry.id = tonumber(id)
        index(entry)
    else
        entry.id = nextId
        index(entry)
        local ok, err = pcall(saveJson)
        if not ok then
            machines[entry.id] = nil; order[#order] = nil
            print('[meta-comic] ' .. tostring(err))
            return notify(source, 'Could not save the vending machine.', 'error')
        end
    end
    broadcast(entry)
    notify(source, ('Vending machine #%d placed.'):format(entry.id), 'success')
end)

RegisterNetEvent('meta_comic:server:removeVendingMachine', function(id)
    local source = source
    id = tonumber(id)
    if not ready or not id then return end
    if not canManage(source) then return notify(source, 'You are not allowed to remove vending machines.', 'error') end
    local entry = machines[id]
    if not entry then return notify(source, 'That vending machine no longer exists.', 'error') end
    if not near(source, entry, (tonumber(cfg.RemoveDistance) or 5.0) + 10.0) then
        return notify(source, 'That vending machine is too far away from you.', 'error')
    end
    if useMysql then
        if not db():query_async(('DELETE FROM `%s` WHERE id = ?'):format(tableName), { id }) then
            return notify(source, 'Could not remove the vending machine.', 'error')
        end
    end
    machines[id] = nil
    for i, value in ipairs(order) do if value == id then table.remove(order, i); break end end
    if not useMysql then
        local ok, err = pcall(saveJson)
        if not ok then print('[meta-comic] ' .. tostring(err)) end
    end
    TriggerClientEvent('meta_comic:client:vendingMachineRemoved', -1, id)
    notify(source, ('Vending machine #%d removed.'):format(id), 'success')
end)

-- Manage > Move machine: same checks as placing, plus the manager has to be standing at the machine
RegisterNetEvent('meta_comic:server:moveVendingMachine', function(id, x, y, z, heading)
    local source = source
    local entry = ready and machines[tonumber(id) or 0]
    if not entry then return notify(source, 'That vending machine no longer exists.', 'error') end
    if not canManage(source) then return notify(source, 'You are not allowed to move vending machines.', 'error') end
    if not (finite(x) and finite(y) and finite(z) and finite(heading)) then return end
    local reach = (tonumber(cfg.PlaceDistance) or 15.0) + 10.0
    local target = { x = round(x, 3), y = round(y, 3), z = round(z, 3), h = round(heading % 360.0, 2) }
    if not near(source, entry, reach) or not near(source, target, reach) then
        return notify(source, 'That spot is too far away from you.', 'error')
    end
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
    broadcast(entry) -- clients see the new coordinates and respawn the prop there
    notify(source, ('Vending machine #%d moved.'):format(entry.id), 'success')
end)

-- Buy / Restock menus: always opened with the server's current products and stock -----------------------------------
RegisterNetEvent('meta_comic:server:vendingOpen', function(id, mode)
    local source = source
    local entry = ready and machines[tonumber(id) or 0]
    if not entry then return notify(source, 'That vending machine no longer exists.', 'error') end
    mode = mode == 'restock' and 'restock' or 'buy'
    if mode == 'restock' and not canRestock(source) then return notify(source, 'You are not allowed to restock vending machines.', 'error') end
    if not near(source, entry, interactReach()) then return notify(source, 'You need to stand at the vending machine.', 'error') end
    TriggerLatentClientEvent('meta_comic:client:vendingOpen', source, 512 * 1024, entry.id, mode, clientProducts(entry, true), MAX_STOCK)
end)

-- Manage (ox_target option for managers) ----------------------------------------------------------------------------
local function setChoices()
    local result = {}
    for _, set in ipairs(MetaComic.Sets and MetaComic.Sets.getAll() or {}) do result[#result + 1] = { id = set.id, name = set.name or set.id } end
    return result
end
local function openManage(source, entry)
    TriggerLatentClientEvent('meta_comic:client:vendingManage', source, 512 * 1024, entry.id, clientProducts(entry, true), setChoices(), MAX_STOCK)
end

RegisterNetEvent('meta_comic:server:vendingManage', function(id)
    local source = source
    local entry = ready and machines[tonumber(id) or 0]
    if not entry then return end
    if not canManage(source) then return notify(source, 'You are not allowed to manage vending machines.', 'error') end
    openManage(source, entry)
end)

-- action: 'add' { set, kind, price, stock } | 'price' { set, kind, price } | 'stock' { set, kind, stock } | 'remove' { set, kind }
-- One change at a time, so sales made while the menu is open are never overwritten.
RegisterNetEvent('meta_comic:server:vendingProduct', function(id, action, data)
    local source = source
    local entry = ready and machines[tonumber(id) or 0]
    if not entry or type(data) ~= 'table' then return end
    if not canManage(source) then return notify(source, 'You are not allowed to manage vending machines.', 'error') end
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
        -- lowering only (correcting a count); adding stock always goes through Restock with real items
        local stock = whole(data.stock, 0, product.stock)
        if not stock then return notify(source, ('Stock can only be lowered here (0-%d). Use Restock to add.'):format(product.stock), 'error') end
        product.stock = stock
    elseif action == 'remove' then
        table.remove(entry.products, position)
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

-- Map of every machine for managers (admin UI "Vending machines" tab) ------------------------------------------------
if MetaComic.RpcHandlers then
    MetaComic.RpcHandlers.getVendingMachines = function(source)
        if not canManage(source) then return { ok = false, error = 'You are not allowed to manage vending machines.' } end
        local list = {}
        for _, id in ipairs(order) do
            local entry = machines[id]
            list[#list + 1] = { id = entry.id, x = entry.x, y = entry.y, z = entry.z, products = clientProducts(entry) }
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

-- Restock (managers and employees) ----------------------------------------------------------------------------------
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

RegisterNetEvent('meta_comic:server:vendingRestock', function(id, setId, kind, amount)
    local source = source
    local entry = ready and machines[tonumber(id) or 0]
    if not entry then return end
    if not canRestock(source) then return notify(source, 'You are not allowed to restock vending machines.', 'error') end
    if not near(source, entry, interactReach()) then return notify(source, 'You need to stand at the vending machine.', 'error') end
    setId, kind = tostring(setId or ''), kindOf(kind)
    local product = findProduct(entry, setId, kind)
    if not product then return notify(source, 'That product is not in this machine anymore.', 'error') end
    local room = MAX_STOCK - product.stock
    amount = whole(amount, 1, math.max(1, room))
    if room <= 0 or not amount then return notify(source, ('This product is full (%d).'):format(MAX_STOCK), 'error') end
    -- everyone restocks with the real items: that many sealed packs / boxes of this set from their inventory
    local taken, held = takeSealed(source, kind, setId, amount)
    if not taken then
        local set = getSet(setId)
        return notify(source, ('You need %d %s %s%s in your inventory (you have %d).'):format(amount, set and set.name or setId, kindLabel(kind), amount == 1 and '' or (kind == 'box' and 'es' or 's'), held), 'error')
    end
    product.stock = product.stock + amount
    if not saveProducts(entry) then
        product.stock = product.stock - amount
        MetaComic.GiveSealed(source, kind, setId, amount) -- give the items back so nothing is lost
        return notify(source, 'Could not save the vending machine.', 'error')
    end
    broadcast(entry)
    notify(source, ('Restocked %d (now %d).'):format(amount, product.stock), 'success')
end)

-- Buying ------------------------------------------------------------------------------------------------------------
local buying = {}

-- 'money' with ox_inventory is the money item; otherwise a QBCore / Qbox account ('money' means 'cash' there)
local function payment(source, amount, refund)
    local account = shop.Account or 'money'
    if account == 'money' and MetaComic.Inventory.name == 'ox_inventory' then
        if refund then return exports.ox_inventory:AddItem(source, 'money', amount) == true end
        if (exports.ox_inventory:GetItemCount(source, 'money') or 0) < amount then return false end
        return exports.ox_inventory:RemoveItem(source, 'money', amount) == true
    end
    local player = MetaComic.Framework.getPlayer and MetaComic.Framework.getPlayer(source)
    if not (player and player.Functions) then return false end
    if account == 'money' then account = 'cash' end
    if refund then return player.Functions.AddMoney(account, amount, 'trading-card-vending-refund') ~= false end
    return player.Functions.RemoveMoney(account, amount, 'trading-card-vending') == true
end

RegisterNetEvent('meta_comic:server:vendingBuy', function(id, setId, kind)
    local source = source
    local entry = ready and machines[tonumber(id) or 0]
    if not entry or buying[source] or shop.Enabled == false then return end
    setId, kind = tostring(setId or ''), kindOf(kind)
    local product = findProduct(entry, setId, kind)
    if not product then return notify(source, 'That product is not in this machine anymore.', 'error') end
    if not near(source, entry, interactReach()) then return notify(source, 'You need to stand at the vending machine.', 'error') end
    local price = product.price
    local item = kind == 'box' and Config.Items.BoosterBox or Config.Items.BoosterPack
    if MetaComic.Inventory.canCarry and not MetaComic.Inventory.canCarry(source, item, 1) then
        return notify(source, 'You cannot carry that.', 'error')
    end
    -- check and reserve with nothing in between that could wait, so two buyers can never both take the last one
    if product.stock < 1 then return notify(source, 'Sold out.', 'error') end
    buying[source] = true
    product.stock = product.stock - 1
    local sold = false
    local ok, err = pcall(function()
        if price > 0 and not payment(source, price) then
            return notify(source, ('You need $%d.'):format(price), 'error')
        end
        local given, result = MetaComic.GiveSealed(source, kind, setId, 1)
        if not given then
            if price > 0 then payment(source, price, true) end
            return notify(source, result, 'error')
        end
        sold = true
        notify(source, ('Bought %s %s for $%d.'):format(result.name or result.id, kindLabel(kind), price), 'success')
    end)
    buying[source] = nil
    if not sold then product.stock = product.stock + 1 end
    if not ok then print('[meta-comic] vending purchase failed: ' .. tostring(err)) end
    if sold then
        saveProducts(entry)
        broadcast(entry)
    end
end)
AddEventHandler('playerDropped', function() buying[source] = nil end)

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
