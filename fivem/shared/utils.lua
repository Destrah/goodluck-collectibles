RushCards = RushCards or {}
RushCards.FrameworkAdapters = RushCards.FrameworkAdapters or {}
RushCards.InventoryAdapters = RushCards.InventoryAdapters or {}
RushCards.PersistenceAdapters = RushCards.PersistenceAdapters or {}

function RushCards.Debug(...)
    if not Config.Debug then return end
    print('[rush-tradingcards]', ...)
end

function RushCards.CopyTable(source)
    local target = {}
    for key, value in pairs(source or {}) do
        if type(value) == 'table' then
            target[key] = RushCards.CopyTable(value)
        else
            target[key] = value
        end
    end
    return target
end

function RushCards.GetLicense(source)
    for _, identifier in ipairs(GetPlayerIdentifiers(source)) do
        if identifier:sub(1, 9) == 'license2:' then return identifier end
    end
    for _, identifier in ipairs(GetPlayerIdentifiers(source)) do
        if identifier:sub(1, 8) == 'license:' then return identifier end
    end
    return ('source:%s'):format(source)
end
