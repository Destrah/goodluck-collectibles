MetaComic.InventoryAdapters.none = function()
    return {
        name = 'none',
        has = function() return true end,
        remove = function() return true end,
        add = function() return true end,
    }
end
