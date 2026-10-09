MetaComic = MetaComic or {}
MetaComic.FrameworkAdapters = MetaComic.FrameworkAdapters or {}
MetaComic.InventoryAdapters = MetaComic.InventoryAdapters or {}
MetaComic.PersistenceAdapters = MetaComic.PersistenceAdapters or {}

-- Only the server chooses action durations; clients receive the captured job duration.
-- Keep production config values intact, including security deadlines and loot batch rates.
function MetaComic.VendingProgressDuration(duration)
    if GetConvarInt and GetConvarInt('metacomic_dev_testing', 0) == 1 then
        local limit = math.max(10000, math.min(15000, GetConvarInt('metacomic_dev_progress_ms', 15000)))
        return math.min(duration, limit)
    end
    return duration
end

function MetaComic.Debug(...)
    if not Config.Debug then return end
    print('[meta-comic]', ...)
end

function MetaComic.CopyTable(source)
    local target = {}
    for key, value in pairs(source or {}) do
        if type(value) == 'table' then
            target[key] = MetaComic.CopyTable(value)
        else
            target[key] = value
        end
    end
    return target
end

function MetaComic.GetLicense(source)
    for _, identifier in ipairs(GetPlayerIdentifiers(source)) do
        if identifier:sub(1, 9) == 'license2:' then return identifier end
    end
    for _, identifier in ipairs(GetPlayerIdentifiers(source)) do
        if identifier:sub(1, 8) == 'license:' then return identifier end
    end
    return ('source:%s'):format(source)
end

-- Identical zone checks in preview and server placement; geometry/road natives are client-only.
function MetaComic.VendingPlacementZone(x, y, z)
    local cfg = (Config.VendingMachines or {}).Placement or {}
    if cfg.Enabled == false then return true end
    local margin = math.max(0, tonumber(cfg.ZoneMargin) or 1.0)
    for _, zone in ipairs(cfg.ForbiddenZones or {}) do
        local center = zone.Center
        if center then
            local inHeight = (not zone.MinZ or z >= zone.MinZ) and (not zone.MaxZ or z <= zone.MaxZ)
            local dx, dy = x - center.x, y - center.y
            if zone.Radius and inHeight and dx * dx + dy * dy <= (zone.Radius + margin) ^ 2 then
                return false, 'This path or road is a no-placement zone.'
            end
            if zone.Size then
                local angle = math.rad(tonumber(zone.Heading) or 0)
                local lx, ly = dx * math.cos(angle) + dy * math.sin(angle), -dx * math.sin(angle) + dy * math.cos(angle)
                if math.abs(lx) <= zone.Size.x * 0.5 + margin and math.abs(ly) <= zone.Size.y * 0.5 + margin
                    and math.abs(z - center.z) <= zone.Size.z * 0.5 + margin then
                    return false, 'This path or alley is a no-placement zone.'
                end
            end
        end
    end
    return true
end
