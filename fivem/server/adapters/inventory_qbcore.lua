MetaComic.InventoryAdapters.qbcore = function()
    return {
        name = 'qbcore',
        count = function(source, item)
            local player = MetaComic.Framework.getPlayer and MetaComic.Framework.getPlayer(source)
            local total = 0
            for _, entry in pairs(player and player.PlayerData and player.PlayerData.items or {}) do
                if entry and entry.name == item then total = total + (tonumber(entry.amount or entry.count) or 0) end
            end
            return total
        end,
        getSlot = function(source, slot)
            local player = MetaComic.Framework.getPlayer and MetaComic.Framework.getPlayer(source)
            if not player then return nil end
            if player.Functions.GetItemBySlot then return player.Functions.GetItemBySlot(tonumber(slot)) end
            return player.PlayerData and player.PlayerData.items and player.PlayerData.items[tonumber(slot)] or nil
        end,
        slotsOf = function(source, item)
            local player = MetaComic.Framework.getPlayer and MetaComic.Framework.getPlayer(source)
            local result = {}
            for slot, entry in pairs(player and player.PlayerData and player.PlayerData.items or {}) do
                if entry and entry.name == item then
                    entry.slot = entry.slot or tonumber(slot)
                    result[#result + 1] = entry
                end
            end
            table.sort(result, function(a, b) return (tonumber(a.slot) or 0) < (tonumber(b.slot) or 0) end)
            return result
        end,
        has = function(source, item, count)
            local player = MetaComic.Framework.getPlayer and MetaComic.Framework.getPlayer(source)
            if not player then return false end
            local total = 0
            for _, entry in pairs(player.PlayerData and player.PlayerData.items or {}) do
                if entry and entry.name == item then total = total + (tonumber(entry.amount or entry.count) or 0) end
            end
            return total >= (count or 1)
        end,
        remove = function(source, item, count, metadata, slot)
            local player = MetaComic.Framework.getPlayer and MetaComic.Framework.getPlayer(source)
            if not player then return false end
            return player.Functions.RemoveItem(item, count or 1, slot)
        end,
        add = function(source, item, count, metadata)
            local player = MetaComic.Framework.getPlayer and MetaComic.Framework.getPlayer(source)
            if not player then return false end
            return player.Functions.AddItem(item, count or 1, false, metadata)
        end,
    }
end
