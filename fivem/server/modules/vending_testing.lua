-- /vendingtestrole: try the vending machines as someone else without a second account (managers only).
--   /vendingtestrole                 shows your current role and the list
--   /vendingtestrole player          yourself (owner of what you own, installer of what you fitted) with no manager,
--                                    police or restock-job access
--   /vendingtestrole stranger [tag]  someone else with no access at all; a different tag is a different person
--   /vendingtestrole police [tag]    someone else with police access
--   /vendingtestrole employee [tag]  someone else with the restock job
--   /vendingtestrole manager [tag]   someone else with manager access
--   /vendingtestrole off             back to your real self
-- Only the vending scripts see the role (who you are, manager / police / restock access). Money and items still go to
-- your real character. The admin UI keeps your real access. Roles clear when you leave.
local cfg = Config.VendingMachines or {}
if cfg.Enabled == false then return end
local settings = cfg.Testing or {}
if settings.Enabled == false then return end

local ROLES = {
    player = { help = 'yourself, without manager, police or restock-job access', self = true },
    stranger = { help = 'someone else with no access' },
    police = { help = 'someone else with police access', police = true },
    employee = { help = 'someone else with the restock job', employee = true },
    manager = { help = 'someone else with manager access', manage = true },
}
local ORDER = { 'player', 'stranger', 'police', 'employee', 'manager' }
local roles = {}
MetaComic.VendingTestRole = function(source) return roles[tonumber(source) or -1] end

local function notify(source, message, kind)
    if MetaComic.Framework.notify then MetaComic.Framework.notify(source, message, kind) end
end
local function describe(role)
    if not role then return 'You are yourself (no test role).' end
    return ('Test role: %s%s.'):format(role.role, role.identifier and (' as ' .. role.name) or ' (yourself)')
end

RegisterCommand(settings.Command or 'vendingtestrole', function(source, args)
    if source <= 0 then return end
    local real = MetaComic.CanManageReal or MetaComic.CanManage
    if not real or not real(source) then return notify(source, 'Only managers can use vending test roles.', 'error') end
    local name = tostring(args[1] or ''):lower()
    if name == 'none' then name = 'stranger' end
    if name == '' then
        local list = {}
        for _, key in ipairs(ORDER) do list[#list + 1] = ('%s = %s'):format(key, ROLES[key].help) end
        return notify(source, describe(roles[source]) .. ' Roles: ' .. table.concat(list, '; ') .. '; off = back to normal.', 'inform')
    end
    if name == 'off' or name == 'reset' or name == 'me' then
        roles[source] = nil
    else
        local role = ROLES[name]
        if not role then return notify(source, 'Unknown role. Use player, stranger, police, employee, manager or off.', 'error') end
        local tag = tostring(args[2] or name):gsub('[^%w_%-]', ''):sub(1, 24)
        if tag == '' then tag = name end
        roles[source] = { role = name, manage = role.manage == true, police = role.police == true, employee = role.employee == true,
            identifier = not role.self and ('test:' .. tag) or nil, name = not role.self and ('Test ' .. tag) or nil }
    end
    -- refresh what this player's target options and menus allow
    if MetaComic.Vending and MetaComic.Vending.sendAccess then MetaComic.Vending.sendAccess(source) end
    notify(source, describe(roles[source]), 'success')
end, false)

AddEventHandler('playerDropped', function() roles[source] = nil end)
