-- Player money for crafting, vending machines and payouts. Accounts: 'cash' (or 'money') and 'bank', plus any other
-- framework account name (e.g. 'crypto'). How each one is paid is set in Config.Money:
--   'framework'  QBCore / Qbox player.Functions.AddMoney / RemoveMoney(account), ox_core bank account
--   'item'       an inventory item (Config.Money.CashItem, e.g. the ox_inventory 'money' item used by ox_core)
--   'auto'       cash: 'item' on ox_core (its cash is the ox_inventory money item), else 'framework'
--   Config.Money.Custom = { add = function(source, account, amount, reason) return true end, remove = ..., balance = ... }
--   replaces all of it with your own functions (return nil from one to fall back to the built-in handling).
-- remove / add return true or false. Only online players.
MetaComic.Money = {}
local service = MetaComic.Money
local settings = Config.Money or {}

local function accountName(account)
    if account == 'money' or account == 'cash' then return 'cash' end
    return account or 'bank'
end

-- 'item' or 'framework' for this account
local function method(account)
    local configured = account == 'cash' and (settings.Cash or 'auto') or (settings.Bank or 'framework')
    if account ~= 'cash' and account ~= 'bank' then configured = settings.Other or 'framework' end
    if configured == 'auto' then
        local framework = MetaComic.Framework.name
        configured = (framework == 'ox_core' or framework == 'ox') and MetaComic.Inventory.name == 'ox_inventory' and 'item' or 'framework'
    end
    return configured
end
local function cashItem() return settings.CashItem or 'money' end

local function itemMove(source, amount, refund)
    local item = cashItem()
    if refund then return MetaComic.Inventory.add(source, item, amount) == true end
    if MetaComic.Inventory.has and not MetaComic.Inventory.has(source, item, amount) then return false end
    return MetaComic.Inventory.remove(source, item, amount) == true
end

local function frameworkMove(source, account, amount, reason, refund)
    if MetaComic.Framework.moveMoney then -- ox_core bank accounts
        local moved = MetaComic.Framework.moveMoney(source, account, amount, reason, refund)
        if moved ~= nil then return moved end
    end
    local player = MetaComic.Framework.getPlayer and MetaComic.Framework.getPlayer(source)
    if not (player and player.Functions) then return false end
    if refund then return player.Functions.AddMoney(account, amount, reason) ~= false end
    return player.Functions.RemoveMoney(account, amount, reason) == true
end

local function move(source, account, amount, reason, refund)
    amount = math.floor(tonumber(amount) or 0)
    if amount <= 0 then return true end
    account = accountName(account)
    local custom = type(settings.Custom) == 'table' and settings.Custom[refund and 'add' or 'remove']
    if type(custom) == 'function' then
        local ok, result = pcall(custom, source, account, amount, reason)
        if not ok then print('[meta-comic] Config.Money.Custom failed: ' .. tostring(result)) return false end
        if result ~= nil then return result == true end
    end
    if method(account) == 'item' then return itemMove(source, amount, refund) end
    return frameworkMove(source, account, amount, reason, refund)
end

function service.remove(source, account, amount, reason) return move(source, account, amount, reason or 'collectibles', false) end
function service.add(source, account, amount, reason) return move(source, account, amount, reason or 'collectibles', true) end

-- how much a player has; nil when it can't be read
function service.balance(source, account)
    account = accountName(account)
    local custom = type(settings.Custom) == 'table' and settings.Custom.balance
    if type(custom) == 'function' then
        local ok, result = pcall(custom, source, account)
        if ok and result ~= nil then return tonumber(result) end
    end
    if method(account) == 'item' then
        if MetaComic.Inventory.name == 'ox_inventory' then return exports.ox_inventory:GetItemCount(source, cashItem()) or 0 end
        return nil
    end
    local player = MetaComic.Framework.getPlayer and MetaComic.Framework.getPlayer(source)
    local money = player and player.PlayerData and player.PlayerData.money
    if money then return tonumber(money[account]) end
    if player and player.Functions and player.Functions.GetMoney then return tonumber(player.Functions.GetMoney(account)) end
    return nil
end
