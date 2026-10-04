RushCards.FrameworkAdapters.standalone = function()
    return {
        name = 'standalone',
        getIdentifier = function(source)
            return RushCards.GetLicense(source)
        end,
        getName = function(source)
            return GetPlayerName(source) or ('Player %s'):format(source)
        end,
        notify = function(source, message, notifyType)
            TriggerClientEvent('rush_cards:client:notify', source, message, notifyType or 'inform')
        end,
        registerUsableItem = function() return false end,
    }
end
