MetaComic.PersistenceAdapters.none = function()
    return {
        name = 'none',
        init = function() return true end,
        addCards = function() return true end,
        getCollection = function() return {} end,
    }
end
