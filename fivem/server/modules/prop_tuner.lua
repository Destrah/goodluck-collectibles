-- Cosmetic, local-only calibration. Always use real management permission, never a simulated vending role.
local function allowed(src)
    local check = MetaComic.CanManageReal or MetaComic.CanManage
    return src > 0 and check and check(src) == true
end
local function send(src, data)
    if not allowed(src) then
        if MetaComic.Framework.notify then MetaComic.Framework.notify(src, 'Only collectibles admins can calibrate props.', 'error') end
        return false
    end
    TriggerClientEvent('meta_comic:client:propTune', src, data)
    return true
end
RegisterCommand('proptune', function(src, args)
    send(src, { args = args })
end, false)
RegisterCommand('vendingkeytune', function(src, args)
    send(src, { vending = true, args = args })
end, false)
-- Other resources can provide {model, dict, clip, bone, offset, rotation, phase, label, flag}.
-- This export uses the same admin check and never changes inventory or machine access.
exports('StartPropTune', function(src, options) return send(tonumber(src) or 0, { preset = options }) end)
