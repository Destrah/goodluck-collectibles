-- Optional template for custom persistence.
-- Set Config.Persistence = 'custom' after implementing these methods.
RushCards.PersistenceAdapters.custom = function()
    return {
        name = 'custom',
        init = function() return true end,
        addCards = function(ownerIdentifier, cards)
            -- Persist owned card instances here.
            return true
        end,
        getCollection = function(ownerIdentifier)
            return {}
        end,
    }
end
