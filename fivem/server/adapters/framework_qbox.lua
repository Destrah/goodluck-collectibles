MetaComic.FrameworkAdapters.qbox = function()
    return {
        name = 'qbox',
        getIdentifier = function(source)
            local player = exports.qbx_core:GetPlayer(source)
            return player and player.PlayerData and player.PlayerData.citizenid or MetaComic.GetLicense(source)
        end,
        getName = function(source)
            local player = exports.qbx_core:GetPlayer(source)
            local info = player and player.PlayerData and player.PlayerData.charinfo
            if info then return (('%s %s'):format(info.firstname or '', info.lastname or '')):gsub('^%s+', ''):gsub('%s+$', '') end
            return GetPlayerName(source) or ('Player %s'):format(source)
        end,
        notify = function(source, message, notifyType)
            exports.qbx_core:Notify(source, message, notifyType or 'inform')
        end,
        registerUsableItem = function(itemName, callback)
            exports.qbx_core:CreateUseableItem(itemName, function(source, item)
                callback(source, item)
            end)
            return true
        end,
        getPlayer = function(source)
            return exports.qbx_core:GetPlayer(source)
        end,
        getJob = function(source)
            local player = exports.qbx_core:GetPlayer(source)
            local job = player and player.PlayerData and player.PlayerData.job
            if not job then return nil end
            local grade = job.grade
            if type(grade) == 'table' then grade = grade.level or grade.grade or 0 end
            return { name = job.name, grade = tonumber(grade) or 0, onDuty = job.onduty == true }
        end,
        hasGroup = function(source, filter)
            local ok, allowed = pcall(function() return exports.qbx_core:HasGroup(source, filter) end)
            return ok and allowed == true
        end,
    }
end
