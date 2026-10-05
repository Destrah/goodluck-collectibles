MetaComic.InventoryAdapters.ox_inventory = function()
    return {
        name = 'ox_inventory',
        count = function(source, item)
            return exports.ox_inventory:GetItemCount(source, item, nil, false) or 0
        end,
        getSlot = function(source, slot)
            return exports.ox_inventory:GetSlot(source, slot)
        end,
        setMetadata = function(source, slot, metadata)
            exports.ox_inventory:SetMetadata(source, slot, metadata)
            return true
        end,
        -- the inventory of a container item (e.g. a card binder) sitting in the player's slot
        getContainer = function(source, slot)
            return exports.ox_inventory:GetContainerFromSlot(source, slot)
        end,
        -- Reorder two binder slots inside the live ox_inventory container.
        -- If both slots contain cards we swap their complete metadata records in-place. Every physical trading
        -- card uses the same unique/non-stackable item and all card identity lives in metadata, so this keeps the
        -- live slot objects and their persistence semantics intact.
        -- If the destination is empty, SetMetadata cannot create a new slot. In that case remove the exact source
        -- item and AddItem it back into the requested destination slot, then verify the live inventory. AddItem's
        -- fifth argument is the exact slot according to the ox_inventory server API.
        swapSlots = function(containerId, slotA, slotB)
            if type(containerId) == 'table' then containerId = containerId.id end
            if containerId == nil then return false end
            slotA, slotB = tonumber(slotA), tonumber(slotB)
            if not slotA or not slotB or slotA == slotB then return false end

            local a = exports.ox_inventory:GetSlot(containerId, slotA)
            local b = exports.ox_inventory:GetSlot(containerId, slotB)
            if type(a) ~= 'table' then return false end
            if b ~= nil and (type(b) ~= 'table' or a.name ~= b.name) then return false end

            local function cloneMetadata(item)
                local source = type(item) == 'table' and item.metadata or nil
                if type(source) ~= 'table' then return {} end
                local ok, encoded = pcall(json.encode, source)
                if not ok or not encoded then return source end
                local decoded = json.decode(encoded)
                return type(decoded) == 'table' and decoded or source
            end

            local function identity(item)
                local m = type(item) == 'table' and item.metadata or nil
                if type(m) ~= 'table' then return nil end
                return tostring(m.instanceId or '') .. '|' .. tostring(m.cardKey or '') .. '|' .. tostring(m.baseCardId or '') .. '|' .. tostring(m.variantId or '') .. '|' .. tostring(m.printedAt or '')
            end

            local metaA = cloneMetadata(a)

            if b then
                local metaB = cloneMetadata(b)
                exports.ox_inventory:SetMetadata(containerId, slotA, metaB)
                exports.ox_inventory:SetMetadata(containerId, slotB, metaA)

                local checkA = exports.ox_inventory:GetSlot(containerId, slotA)
                local checkB = exports.ox_inventory:GetSlot(containerId, slotB)
                if identity(checkA) ~= identity(b) or identity(checkB) ~= identity(a) then
                    -- Best-effort rollback if an ox fork rejected one of the writes.
                    exports.ox_inventory:SetMetadata(containerId, slotA, metaA)
                    exports.ox_inventory:SetMetadata(containerId, slotB, metaB)
                    return false
                end
                return true, checkA, checkB, 'swap'
            end

            local count = tonumber(a.count) or 1
            local removed = exports.ox_inventory:RemoveItem(containerId, a.name, count, metaA, slotA, false, true)
            if removed ~= true then return false end

            local added = exports.ox_inventory:AddItem(containerId, a.name, count, metaA, slotB)
            if added ~= true then
                -- Best effort rollback to the original pocket. The source slot should still be empty here.
                exports.ox_inventory:AddItem(containerId, a.name, count, metaA, slotA)
                return false
            end

            local checkA = exports.ox_inventory:GetSlot(containerId, slotA)
            local checkB = exports.ox_inventory:GetSlot(containerId, slotB)
            if checkA ~= nil or identity(checkB) ~= identity(a) then
                -- Roll back if a fork ignored the requested AddItem slot or otherwise produced an unexpected move.
                local moved = checkB
                if type(moved) == 'table' then
                    exports.ox_inventory:RemoveItem(containerId, moved.name, tonumber(moved.count) or count, moved.metadata, slotB, false, true)
                end
                exports.ox_inventory:AddItem(containerId, a.name, count, metaA, slotA)
                return false
            end

            return true, nil, checkB, 'move'
        end,
        slotsOf = function(source, item)
            return exports.ox_inventory:Search(source, 'slots', item) or {}
        end,
        has = function(source, item, count, metadata)
            local found = exports.ox_inventory:GetItemCount(source, item, metadata, false)
            return (found or 0) >= (count or 1)
        end,
        remove = function(source, item, count, metadata, slot)
            local success = exports.ox_inventory:RemoveItem(source, item, count or 1, metadata, slot, false, false)
            return success == true
        end,
        add = function(source, item, count, metadata)
            local success = exports.ox_inventory:AddItem(source, item, count or 1, metadata)
            return success == true
        end,
        canCarry = function(source, item, count)
            return exports.ox_inventory:CanCarryItem(source, item, count) == true
        end,
    }
end
