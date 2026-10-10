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
        -- Move one whole slot between two inventories (player <-> binder container). toSlot nil = any free slot.
        -- Checks room first, then removes and adds the exact item; puts it back where it was if the add fails.
        moveSlot = function(fromInv, fromSlot, toInv, toSlot)
            if type(fromInv) == 'table' then fromInv = fromInv.id end
            if type(toInv) == 'table' then toInv = toInv.id end
            fromSlot, toSlot = tonumber(fromSlot), tonumber(toSlot)
            if fromInv == nil or toInv == nil or not fromSlot then return false end
            local item = exports.ox_inventory:GetSlot(fromInv, fromSlot)
            if type(item) ~= 'table' then return false end
            if toSlot and exports.ox_inventory:GetSlot(toInv, toSlot) ~= nil then return false, 'occupied' end
            local count = tonumber(item.count) or 1
            local metadata = item.metadata
            local ok, encoded = pcall(json.encode, metadata or {})
            if ok and encoded then metadata = json.decode(encoded) or metadata end
            if exports.ox_inventory:CanCarryItem(toInv, item.name, count, metadata) ~= true then return false, 'full' end

            if exports.ox_inventory:RemoveItem(fromInv, item.name, count, metadata, fromSlot, false, true) ~= true then return false end
            local added = exports.ox_inventory:AddItem(toInv, item.name, count, metadata, toSlot)
            if added ~= true then
                exports.ox_inventory:AddItem(fromInv, item.name, count, metadata, fromSlot)
                return false
            end
            return true
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
        -- Card snapshots contain nested metadata. ox_lib's partial matcher only
        -- handles flat values; use deep matching after checking the exact slot.
        removeExact = function(source, item, count, metadata, slot)
            slot = tonumber(slot)
            if not slot or type(metadata) ~= 'table' then return false end
            local live = exports.ox_inventory:GetSlot(source, slot)
            local function same(a, b)
                if type(a) ~= type(b) then return false end
                if type(a) ~= 'table' then return a == b end
                for k, v in pairs(a) do if not same(v, b[k]) then return false end end
                for k in pairs(b) do if a[k] == nil then return false end end
                return true
            end
            if not live or live.name ~= item or (tonumber(live.count) or 0) < (count or 1)
                or not same(live.metadata or {}, metadata) then return false end
            local success = exports.ox_inventory:RemoveItem(source, item, count or 1, metadata, slot, false, true)
            return success == true
        end,
        add = function(source, item, count, metadata)
            local success = exports.ox_inventory:AddItem(source, item, count or 1, metadata)
            return success == true
        end,
        canCarry = function(source, item, count, metadata)
            return exports.ox_inventory:CanCarryItem(source, item, count, metadata) == true
        end,
    }
end
