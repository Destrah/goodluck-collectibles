MetaComic = MetaComic or {}
MetaComic.FrameworkAdapters = MetaComic.FrameworkAdapters or {}
MetaComic.InventoryAdapters = MetaComic.InventoryAdapters or {}
MetaComic.PersistenceAdapters = MetaComic.PersistenceAdapters or {}

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
