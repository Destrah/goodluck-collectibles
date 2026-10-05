MetaComic.FrameworkAdapters.qbcore = function()
    local QBCore = exports['qb-core']:GetCoreObject()
    return {
        name = 'qbcore',
        getIdentifier = function(source)
            local player = QBCore.Functions.GetPlayer(source)
            return player and player.PlayerData and player.PlayerData.citizenid or MetaComic.GetLicense(source)
        end,
        getName = function(source)
            local player = QBCore.Functions.GetPlayer(source)
            local info = player and player.PlayerData and player.PlayerData.charinfo
            if info then return (('%s %s'):format(info.firstname or '', info.lastname or '')):gsub('^%s+', ''):gsub('%s+$', '') end
            return GetPlayerName(source) or ('Player %s'):format(source)
        end,
        notify = function(source, message, notifyType)
            TriggerClientEvent('QBCore:Notify', source, message, notifyType or 'primary')
        end,
        registerUsableItem = function(itemName, callback)
            QBCore.Functions.CreateUseableItem(itemName, function(source, item)
                callback(source, item)
            end)
            return true
        end,
        getPlayer = function(source)
            return QBCore.Functions.GetPlayer(source)
        end,
        getJob = function(source)
            local player = QBCore.Functions.GetPlayer(source)
            local job = player and player.PlayerData and player.PlayerData.job
            if not job then return nil end
            local grade = job.grade
            if type(grade) == 'table' then grade = grade.level or grade.grade or 0 end
            return { name = job.name, grade = tonumber(grade) or 0, onDuty = job.onduty == true }
        end,
        hasPermission = function(source, permission)
            if not QBCore.Functions.HasPermission then return false end
            local ok, allowed = pcall(QBCore.Functions.HasPermission, source, permission)
            return ok and allowed == true
        end,
    }
end
