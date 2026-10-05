-- Optional template for a custom FiveM framework.
-- Set Config.Framework = 'custom' after replacing these methods.
MetaComic.FrameworkAdapters.custom = function()
    return {
        name = 'custom',
        getIdentifier = function(source)
            return MetaComic.GetLicense(source)
        end,
        getName = function(source)
            return GetPlayerName(source) or ('Player %s'):format(source)
        end,
        notify = function(source, message, notifyType)
            TriggerClientEvent('meta_comic:client:notify', source, message, notifyType or 'inform')
        end,
        registerUsableItem = function(itemName, callback)
            -- Register your framework's usable item here.
            -- callback(source, itemData)
            return false
        end,
        getPlayer = function(source)
            return nil
        end,
    }
end
