-- ox_core (Overextended): Config.Framework = 'ox_core'. Characters, groups and bank accounts come from ox_core;
-- notifications use ox_lib (ox_core's companion library) when it runs.
-- Usable items go through ox_inventory's item exports (Config.Items.UseMethod 'auto').
MetaComic.FrameworkAdapters.ox_core = function()
    local function running(name)
        local state = GetResourceState(name)
        return state == 'started' or state == 'starting'
    end
    local function core() return running('ox_core') and exports.ox_core or nil end
    if not running('ox_core') then
        print("^3[meta-comic] Config.Framework is 'ox_core' but ox_core is not started; players are identified by license until it is.^0")
    end

    -- ox_core methods are called through CallPlayer from other resources; older builds return callable objects
    local function getPlayer(source)
        local ox = core()
        if not ox then return nil end
        local ok, player = pcall(function() return ox:GetPlayer(source) end)
        return ok and type(player) == 'table' and player or nil
    end
    local function callPlayer(source, method, ...)
        local ox = core()
        if not ox then return nil end
        local args = table.pack(...)
        local ok, a, b = pcall(function() return ox:CallPlayer(source, method, table.unpack(args, 1, args.n)) end)
        if ok then return a, b end
        local player = getPlayer(source)
        if player and type(player[method]) == 'function' then
            local okMethod, x, y = pcall(player[method], player, table.unpack(args, 1, args.n))
            if okMethod then return x, y end
        end
        return nil
    end
    local function field(source, key)
        local player = getPlayer(source)
        if player and player[key] ~= nil then return player[key] end
        return callPlayer(source, 'get', key)
    end
    -- getGroup returns the grade (or name, grade) depending on the ox_core version
    local function groupGrade(source, name)
        local a, b = callPlayer(source, 'getGroup', name)
        local grade = tonumber(b) or tonumber(a)
        return grade
    end

    local NOTIFY_TYPES = { success = 'success', error = 'error', warning = 'warning', inform = 'inform', info = 'inform', primary = 'inform' }

    return {
        name = 'ox_core',
        getIdentifier = function(source)
            local charId = field(source, 'charId')
            return charId and ('char:%s'):format(charId) or MetaComic.GetLicense(source)
        end,
        getName = function(source)
            local first, last = field(source, 'firstName'), field(source, 'lastName')
            if first or last then return (('%s %s'):format(first or '', last or '')):gsub('^%s+', ''):gsub('%s+$', '') end
            return GetPlayerName(source) or ('Player %s'):format(source)
        end,
        notify = function(source, message, notifyType)
            if running('ox_lib') then
                TriggerClientEvent('ox_lib:notify', source, { description = message, type = NOTIFY_TYPES[notifyType] or 'inform' })
            else
                TriggerClientEvent('meta_comic:client:notify', source, message, notifyType or 'inform')
            end
        end,
        registerUsableItem = function() return false end,
        getPlayer = getPlayer,
        -- the character's active group stands in for a job (Config.Management.Jobs, vending Restock.Jobs)
        getJob = function(source)
            local name = field(source, 'activeGroup')
            if type(name) ~= 'string' or name == '' then return nil end
            return { name = name, grade = groupGrade(source, name) or 0, onDuty = true }
        end,
        -- filter: { groupName = minGrade, ... } (Config.Management.OxGroups)
        hasGroup = function(source, filter)
            for name, minGrade in pairs(type(filter) == 'table' and filter or {}) do
                local grade = groupGrade(source, name)
                if grade and grade >= (tonumber(minGrade) or 0) then return true end
            end
            return false
        end,
        -- bank payments (vending machines with Shop.Account = 'bank'); cash is the ox_inventory money item
        moveMoney = function(source, account, amount, reason, refund)
            local ox = core()
            local charId = field(source, 'charId')
            if not ox or not charId or account ~= 'bank' then return nil end
            local ok, result = pcall(function()
                local bank = ox:GetCharacterAccount(charId)
                local accountId = type(bank) == 'table' and (bank.accountId or bank.id) or bank
                local payload = { amount = amount, message = reason }
                if type(bank) == 'table' and type(bank[refund and 'addBalance' or 'removeBalance']) == 'function' then
                    return bank[refund and 'addBalance' or 'removeBalance'](bank, payload)
                end
                return ox:CallAccount(accountId, refund and 'addBalance' or 'removeBalance', payload)
            end)
            if not ok then print('[meta-comic] ox_core bank payment failed: ' .. tostring(result)) return false end
            return result == true or (type(result) == 'table' and result.success == true)
        end,
    }
end
MetaComic.FrameworkAdapters.ox = MetaComic.FrameworkAdapters.ox_core
