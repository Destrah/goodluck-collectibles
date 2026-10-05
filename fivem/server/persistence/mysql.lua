-- Kept in the adapter so startup does not depend on a separate manifest entry.
local BrandingMigration = {}
local previousPrefixes = {'rush_trading_', 'goodluck_trading_'}
function BrandingMigration.normalizeDatabaseConfig(db)
    for _, key in ipairs({'Table','CardsTable','PrintsTable','SetsTable','SetCardsTable','StorageTable','DefinitionsTable'}) do
        if type(db[key]) == 'string' then
            for _, prefix in ipairs(previousPrefixes) do db[key] = db[key]:gsub('^' .. prefix, 'goodluck_collectibles_') end
        end
    end
end
function BrandingMigration.renameTables(query, names)
    local renames = {}
    local function exists(name)
        return query('SELECT 1 FROM information_schema.TABLES WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = ?', {name})[1] ~= nil
    end
    for _, key in ipairs({'instances','cards','prints','sets','members','storage','legacy'}) do
        local target, source = names[key], nil
        if target:match('^goodluck_collectibles_') then
            for _, prefix in ipairs(previousPrefixes) do
                local previous = target:gsub('^goodluck_collectibles_', prefix)
                if exists(previous) then
                    if source or exists(target) then error('Both old and new collectable tables exist; refusing to overwrite or merge them: ' .. target) end
                    source = previous
                end
            end
            if source then renames[#renames+1] = ('`%s` TO `%s`'):format(source,target) end
        end
    end
    if #renames > 0 then
        query('RENAME TABLE ' .. table.concat(renames, ', '))
        print('[meta-comic] database table branding migration complete')
    end
end

MetaComic.PersistenceAdapters.mysql = function()
    local db = Config.Database
    BrandingMigration.normalizeDatabaseConfig(db)
    local instanceTable = db.Table
    local prefix = instanceTable:gsub('_instances$', '')
    local names = {
        instances = instanceTable,
        cards = db.CardsTable or (instanceTable == 'goodluck_collectibles_card_instances' and 'goodluck_collectibles_cards' or (prefix .. '_cards')),
        prints = db.PrintsTable or (prefix .. '_prints'),
        sets = db.SetsTable or (prefix .. '_sets'),
        members = db.SetCardsTable or (prefix .. '_set_cards'),
        storage = db.StorageTable or (prefix .. '_storage'),
        legacy = db.DefinitionsTable or (instanceTable .. '_definitions'),
    }
    local usedNames = {}
    for _, name in pairs(names) do
        if type(name) ~= 'string' or #name > 55 or not name:match('^[%w_]+$') or usedNames[name] then
            error('Meta Comic database tables must have distinct names using letters, digits and underscores (up to 55 characters)')
        end
        usedNames[name] = true
    end
    local dbResource = db.Resource or 'oxmysql'
    local catalog, sets, writing = {}, {}, false
    local refreshing, refreshOk, refreshError = false, nil, nil
    local function query(sql, params)
        local result = exports[dbResource]:query_async(sql, params or {})
        if result == nil then error('Meta Comic MySQL query failed') end
        return result
    end
    local function decode(raw)
        if type(raw) == 'table' then return MetaComic.CopyTable(raw) end
        local ok, data = pcall(json.decode, raw or '')
        if not ok or type(data) ~= 'table' then error('Invalid Meta Comic JSON data in database/import') end
        return data
    end
    local function equal(a, b)
        if type(a) ~= type(b) then return false end
        if type(a) ~= 'table' then return a == b end
        for k, v in pairs(a) do if not equal(v, b[k]) then return false end end
        for k in pairs(b) do if a[k] == nil then return false end end
        return true
    end
    -- Scalar fields are queryable columns; only variable nested structures use JSON.
    local cardFields = {
        {'title', 'title', 'Untitled Card'}, {'subtitle', 'subtitle', ''}, {'hp', 'hp', 100},
        {'type', 'type', 'civilian'}, {'chanceWeight', 'chance_weight', 100}, {'image', 'image', ''},
        {'description', 'description', ''}, {'accent', 'accent', '#f59e0b'},
        {'foilA', 'foil_a', '#ff4d8d'}, {'foilB', 'foil_b', '#4df3ff'}, {'foilC', 'foil_c', '#ffe66d'},
        {'attacks', 'attacks_json', {}},
    }
    local printFields = {
        {'name', 'name', 'Standard'}, {'rarity', 'rarity', 'Common'}, {'rarityKey', 'rarity_key', 'common'},
        {'chanceWeight', 'chance_weight', 100}, {'layout', 'layout', 'classic'}, {'holo', 'holo', 'none'},
        {'holoStrength', 'holo_strength', 55}, {'image', 'image', ''},
        {'imagePositionX', 'image_position_x', 50}, {'imagePositionY', 'image_position_y', 50}, {'imageZoom', 'image_zoom', 100},
        {'accent', 'accent', ''}, {'foilA', 'foil_a', ''}, {'foilB', 'foil_b', ''}, {'foilC', 'foil_c', ''},
        {'subjectLayers', 'subject_layers_json', {}},
    }
    local setFields = {{'name', 'name', ''}, {'code', 'code', ''}, {'description', 'description', ''}}
    local function fieldsFor(kind) return kind == 'cards' and cardFields or kind == 'prints' and printFields or setFields end
    local function canonical(input, fields)
        local output = MetaComic.CopyTable(input)
        for _, field in ipairs(fields) do
            if output[field[1]] == nil then output[field[1]] = type(field[3]) == 'table' and {} or field[3] end
        end
        return output
    end
    local function validateId(id, limit)
        if type(id) ~= 'string' or id == '' or #id > limit then error('Invalid or oversized Meta Comic definition ID') end
    end
    local function prepareCatalog(list)
        local result, seen = {}, {}
        for _, input in ipairs(list) do
            local card = canonical(input, cardFields)
            validateId(card.id, 160)
            if seen[card.id] then error('Duplicate card ID: ' .. card.id) end
            seen[card.id] = true
            card.variants = {}
            local prints = {}
            for _, inputPrint in ipairs(input.variants or {}) do
                validateId(inputPrint.id, 180)
                if prints[inputPrint.id] then error('Duplicate print ID within card: ' .. inputPrint.id) end
                prints[inputPrint.id] = true
                local variant = canonical(inputPrint, printFields)
                local art = tostring(inputPrint.image or ''):match('^%s*(.-)%s*$')
                local separate = art ~= '' and art ~= tostring(input.image or ''):match('^%s*(.-)%s*$')
                for key, default in pairs({imagePositionX = 50, imagePositionY = 50, imageZoom = 100}) do
                    variant[key] = tonumber(inputPrint[key]) or (not separate and tonumber(input[key])) or default
                end
                card.variants[#card.variants + 1] = variant
            end
            card.imagePositionX, card.imagePositionY, card.imageZoom = nil, nil, nil
            result[#result + 1] = card
        end
        return result
    end
    local function prepareSets(list, cards, importing)
        local known, seen, result = {}, {}, {}
        for _, card in ipairs(cards) do known[card.id] = true end
        for index, input in ipairs(list) do
            local id = tostring(input.id or input.code or input.name or ('set-' .. index)):lower():gsub('[^%w]+', '-'):gsub('^-+', ''):gsub('-+$', '')
            if id == '' then id = 'set' end
            validateId(id, 160)
            if seen[id] then error('Duplicate set ID: ' .. id) end
            seen[id] = true
            local code = tostring(input.code or id):upper():gsub('[^%w%-_]', '')
            local set = {id = id, name = tostring(input.name or id), code = code ~= '' and code or id:upper(), description = tostring(input.description or ''), cardIds = {}}
            local members = {}
            for _, cardId in ipairs(input.cardIds or {}) do
                cardId = tostring(cardId)
                if not known[cardId] then
                    if not importing then error('Unknown set card ID: ' .. cardId) end
                    if importing == true then
                        print(('[meta-comic] migration skipped missing card %s in set %s'):format(cardId, id))
                    end
                elseif not members[cardId] then
                    members[cardId] = true
                    set.cardIds[#set.cardIds + 1] = cardId
                end
            end
            result[#result + 1] = set
        end
        return result
    end
    local function append(statements, sql, values)
        statements[#statements + 1] = {query = sql, values = values or {}}
    end
    local function rowStatement(statements, kind, item, order, cardId, prior)
        if prior then
            local changes, params = {}, {}
            if prior.order ~= order then changes[#changes + 1], params[#params + 1] = '`sort_order` = ?', order end
            local extra, oldExtra = MetaComic.CopyTable(item), MetaComic.CopyTable(prior.item)
            extra.id, extra.variants, extra.cardIds = nil, nil, nil
            oldExtra.id, oldExtra.variants, oldExtra.cardIds = nil, nil, nil
            for _, field in ipairs(fieldsFor(kind)) do
                local key = field[1]
                if not equal(item[key], prior.item[key]) then
                    changes[#changes + 1] = '`' .. field[2] .. '` = ?'
                    params[#params + 1] = type(field[3]) == 'table' and json.encode(item[key]) or item[key]
                end
                extra[key], oldExtra[key] = nil, nil
            end
            if kind ~= 'sets' and not equal(extra, oldExtra) then
                changes[#changes + 1], params[#params + 1] = '`extra_json` = ?', json.encode(extra)
            end
            if #changes == 0 then return end
            params[#params + 1] = item.id
            local where = '`id` = ?'
            if cardId then where, params[#params + 1] = where .. ' AND `card_id` = ?', cardId end
            append(statements, ('UPDATE `%s` SET %s WHERE %s'):format(names[kind], table.concat(changes, ', '), where), params)
            return
        end
        local columns, values, updates = {'`id`', '`sort_order`'}, {item.id, order}, {'`sort_order` = VALUES(`sort_order`)'}
        if cardId then columns[#columns + 1], values[#values + 1] = '`card_id`', cardId end
        local extra = MetaComic.CopyTable(item)
        extra.id, extra.variants, extra.cardIds = nil, nil, nil
        for _, field in ipairs(fieldsFor(kind)) do
            local col = '`' .. field[2] .. '`'
            columns[#columns + 1] = col
            values[#values + 1] = type(field[3]) == 'table' and json.encode(item[field[1]]) or item[field[1]]
            updates[#updates + 1] = col .. ' = VALUES(' .. col .. ')'
            extra[field[1]] = nil
        end
        if kind ~= 'sets' then
            columns[#columns + 1], values[#values + 1] = '`extra_json`', json.encode(extra)
            updates[#updates + 1] = '`extra_json` = VALUES(`extra_json`)'
        end
        local placeholders = {}
        for _ in ipairs(columns) do placeholders[#placeholders + 1] = '?' end
        append(statements, ('INSERT INTO `%s` (%s) VALUES (%s) ON DUPLICATE KEY UPDATE %s'):format(names[kind], table.concat(columns, ', '), table.concat(placeholders, ', '), table.concat(updates, ', ')), values)
    end
    local function indexById(list)
        local map = {}
        for order, item in ipairs(list) do map[item.id] = {item = item, order = order} end
        return map
    end
    local function catalogChanges(statements, nextCatalog, previous)
        local old, current = indexById(previous), indexById(nextCatalog)
        for order, card in ipairs(nextCatalog) do
            local prior = old[card.id]
            local base, oldBase = MetaComic.CopyTable(card), prior and MetaComic.CopyTable(prior.item)
            base.variants = nil
            if oldBase then oldBase.variants = nil end
            if not prior or prior.order ~= order or not equal(base, oldBase) then rowStatement(statements, 'cards', card, order, nil, prior) end
            local oldPrints, newPrints = indexById(prior and prior.item.variants or {}), indexById(card.variants)
            for printOrder, variant in ipairs(card.variants) do
                local oldPrint = oldPrints[variant.id]
                if not oldPrint or oldPrint.order ~= printOrder or not equal(variant, oldPrint.item) then rowStatement(statements, 'prints', variant, printOrder, card.id, oldPrint) end
            end
            for id in pairs(oldPrints) do
                if not newPrints[id] then append(statements, ('DELETE FROM `%s` WHERE `card_id` = ? AND `id` = ?'):format(names.prints), {card.id, id}) end
            end
        end
        for id in pairs(old) do
            if not current[id] then append(statements, ('DELETE FROM `%s` WHERE `id` = ?'):format(names.cards), {id}) end
        end
    end
    local function setChanges(statements, nextSets, previous)
        local old, current = indexById(previous), indexById(nextSets)
        for order, set in ipairs(nextSets) do
            local prior = old[set.id]
            local base, oldBase = MetaComic.CopyTable(set), prior and MetaComic.CopyTable(prior.item)
            base.cardIds = nil
            if oldBase then oldBase.cardIds = nil end
            if not prior or prior.order ~= order or not equal(base, oldBase) then rowStatement(statements, 'sets', set, order, nil, prior) end
            local oldMembers = {}
            for position, id in ipairs(prior and prior.item.cardIds or {}) do oldMembers[id] = position end
            local newMembers = {}
            for position, id in ipairs(set.cardIds) do
                newMembers[id] = true
                if oldMembers[id] ~= position then
                    append(statements, ('INSERT INTO `%s` (`set_id`, `card_id`, `sort_order`) VALUES (?, ?, ?) ON DUPLICATE KEY UPDATE `sort_order` = VALUES(`sort_order`)'):format(names.members), {set.id, id, position})
                end
            end
            for id in pairs(oldMembers) do
                if not newMembers[id] then append(statements, ('DELETE FROM `%s` WHERE `set_id` = ? AND `card_id` = ?'):format(names.members), {set.id, id}) end
            end
        end
        for id in pairs(old) do
            if not current[id] then append(statements, ('DELETE FROM `%s` WHERE `id` = ?'):format(names.sets), {id}) end
        end
    end
    local function transaction(statements)
        if #statements == 0 then return true end
        return exports[dbResource]:transaction_async(statements) == true
    end
    local function readRow(kind, row)
        local item = kind == 'sets' and {} or decode(row.extra_json)
        item.id = row.id
        for _, field in ipairs(fieldsFor(kind)) do
            item[field[1]] = type(field[3]) == 'table' and decode(row[field[2]]) or row[field[2]]
        end
        return item
    end
    local function hydrate()
        local nextCatalog, nextSets, byCard, bySet = {}, {}, {}, {}
        for _, row in ipairs(query(('SELECT * FROM `%s` ORDER BY `sort_order`, `id`'):format(names.cards))) do
            local card = readRow('cards', row)
            card.variants = {}
            byCard[card.id], nextCatalog[#nextCatalog + 1] = card, card
        end
        for _, row in ipairs(query(('SELECT * FROM `%s` ORDER BY `card_id`, `sort_order`, `id`'):format(names.prints))) do
            local card = byCard[row.card_id]
            if not card then error('Orphaned Meta Comic print row') end
            card.variants[#card.variants + 1] = readRow('prints', row)
        end
        for _, row in ipairs(query(('SELECT * FROM `%s` ORDER BY `sort_order`, `id`'):format(names.sets))) do
            local set = readRow('sets', row)
            set.cardIds = {}
            bySet[set.id], nextSets[#nextSets + 1] = set, set
        end
        for _, row in ipairs(query(('SELECT * FROM `%s` ORDER BY `set_id`, `sort_order`, `card_id`'):format(names.members))) do
            local set = bySet[row.set_id]
            if not set or not byCard[row.card_id] then error('Orphaned Meta Comic membership row') end
            set.cardIds[#set.cardIds + 1] = row.card_id
        end
        catalog, sets = nextCatalog, nextSets
    end
    local function migrate()
        local marker = query(('SELECT `storage_value` FROM `%s` WHERE `storage_key` = ?'):format(names.storage), {'schema'})
        if marker[1] then
            if marker[1].storage_value ~= 'relational_v1' then error('Unsupported Meta Comic database schema version') end
            return
        end
        for _, kind in ipairs({'cards', 'prints', 'sets', 'members'}) do
            if query(('SELECT 1 FROM `%s` LIMIT 1'):format(names[kind]))[1] then
                -- Another startup may have finished migration after our first marker read.
                local winner = query(('SELECT `storage_value` FROM `%s` WHERE `storage_key` = ?'):format(names.storage), {'schema'})
                if winner[1] and winner[1].storage_value == 'relational_v1' then return end
                error('Meta Comic relational tables contain data without a migration marker; refusing to overwrite')
            end
        end
        local hasLegacy = query('SELECT 1 FROM information_schema.TABLES WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = ?', {names.legacy})[1] ~= nil
        local function seed(key, file)
            if hasLegacy then
                local rows = query(('SELECT `definition_json` FROM `%s` WHERE `definition_key` = ?'):format(names.legacy), {key})
                if rows[1] then return decode(rows[1].definition_json) end
            end
            return decode(LoadResourceFile(GetCurrentResourceName(), file))
        end
        local importedCards = prepareCatalog(seed('catalog', Config.Catalog.File))
        local importedSets = prepareSets(seed('sets', (Config.Sets and Config.Sets.File) or 'data/sets.json'), importedCards, true)
        local statements = {}
        -- The unique marker serializes simultaneous migrations in the same transaction.
        append(statements, ('INSERT INTO `%s` (`storage_key`, `storage_value`) VALUES (?, ?)'):format(names.storage), {'schema', 'relational_v1'})
        catalogChanges(statements, importedCards, {})
        setChanges(statements, importedSets, {})
        if not transaction(statements) then
            local winner = query(('SELECT `storage_value` FROM `%s` WHERE `storage_key` = ?'):format(names.storage), {'schema'})
            if not winner[1] or winner[1].storage_value ~= 'relational_v1' then error('Meta Comic relational migration failed; source data was preserved') end
        end
        print('[meta-comic] relational database migration complete; legacy documents and JSON were preserved')
    end
    local function save(kind, data)
        if writing then return false, 'Another database save is in progress. Please retry.' end
        writing = true
        local ok, result = pcall(function()
            local statements, nextCatalog, nextSets = {}, catalog, sets
            if kind == 'catalog' then
                nextCatalog = prepareCatalog(data)
                catalogChanges(statements, nextCatalog, catalog)
                -- Cascades remove deleted links; keep remaining membership order and caches aligned.
                nextSets = prepareSets(sets, nextCatalog, 'prune')
                setChanges(statements, nextSets, sets)
            else
                nextSets = prepareSets(data, catalog, false)
                setChanges(statements, nextSets, sets)
            end
            if not transaction(statements) then error('Database transaction rolled back') end
            catalog, sets = nextCatalog, nextSets
            return true
        end)
        writing = false
        if not ok then
            print(('[meta-comic] MySQL %s save failed: %s'):format(kind, tostring(result)))
            return false, ('Could not save %s to MySQL. Check the server database logs.'):format(kind)
        end
        return true
    end
    local function restoreMissingDefinitions()
        if writing then return false, 'Another database save is in progress. Please retry.' end
        writing = true
        local ok, result = pcall(function()
            local nextCatalog, nextSets = MetaComic.CopyTable(catalog), MetaComic.CopyTable(sets)
            local byCard, bySet = {}, {}
            local counts = {cards = 0, prints = 0, sets = 0, memberships = 0}
            for _, card in ipairs(nextCatalog) do byCard[card.id] = card end
            for _, set in ipairs(nextSets) do bySet[set.id] = set end
            local sources = {}
            local hasLegacy = query('SELECT 1 FROM information_schema.TABLES WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = ?', {names.legacy})[1] ~= nil
            if hasLegacy then
                local source = {}
                for _, key in ipairs({'catalog', 'sets'}) do
                    local rows = query(('SELECT `definition_json` FROM `%s` WHERE `definition_key` = ?'):format(names.legacy), {key})
                    if rows[1] then source[key] = decode(rows[1].definition_json) end
                end
                if source.catalog or source.sets then sources[#sources + 1] = source end
            end
            local source = {}
            for key, file in pairs({catalog = Config.Catalog.File, sets = (Config.Sets and Config.Sets.File) or 'data/sets.json'}) do
                local raw = LoadResourceFile(GetCurrentResourceName(), file)
                if raw and raw ~= '' then source[key] = decode(raw) end
            end
            if source.catalog or source.sets then sources[#sources + 1] = source end
            if #sources == 0 then error('No preserved database definitions or JSON seed files are available for recovery') end
            -- Merge by stable IDs. Existing relational records always win; nothing is deleted.
            for _, input in ipairs(sources) do
                for _, card in ipairs(prepareCatalog(input.catalog or {})) do
                    local existing = byCard[card.id]
                    if not existing then
                        nextCatalog[#nextCatalog + 1], byCard[card.id] = card, card
                        counts.cards = counts.cards + 1
                        counts.prints = counts.prints + #card.variants
                    else
                        local prints = indexById(existing.variants)
                        for _, variant in ipairs(card.variants) do
                            if not prints[variant.id] then
                                existing.variants[#existing.variants + 1] = variant
                                prints[variant.id] = {item = variant}
                                counts.prints = counts.prints + 1
                            end
                        end
                    end
                end
            end
            for _, input in ipairs(sources) do
                for _, set in ipairs(prepareSets(input.sets or {}, nextCatalog, true)) do
                    local existing = bySet[set.id]
                    if not existing then
                        nextSets[#nextSets + 1], bySet[set.id] = set, set
                        counts.sets = counts.sets + 1
                        counts.memberships = counts.memberships + #set.cardIds
                    else
                        local members = {}
                        for _, id in ipairs(existing.cardIds) do members[id] = true end
                        for _, id in ipairs(set.cardIds) do
                            if not members[id] then
                                existing.cardIds[#existing.cardIds + 1], members[id] = id, true
                                counts.memberships = counts.memberships + 1
                            end
                        end
                    end
                end
            end
            local statements = {}
            catalogChanges(statements, nextCatalog, catalog)
            setChanges(statements, nextSets, sets)
            if not transaction(statements) then error('Recovery transaction rolled back') end
            catalog, sets = nextCatalog, nextSets
            return counts
        end)
        writing = false
        if not ok then return false, tostring(result) end
        return true, result
    end
    return {
        name = 'mysql',
        init = function()
            if GetResourceState(dbResource) ~= 'started' then error(('MySQL persistence selected but %s is not started'):format(dbResource)) end
            BrandingMigration.renameTables(query, names)
            if db.AutoCreateSchema then
                local schema = LoadResourceFile(GetCurrentResourceName(), 'data/mysql.sql')
                if not schema then error('Missing data/mysql.sql relational schema') end
                local defaults = {instances = 'goodluck_collectibles_card_instances', cards = 'goodluck_collectibles_cards', prints = 'goodluck_collectibles_card_prints', sets = 'goodluck_collectibles_card_sets', members = 'goodluck_collectibles_card_set_cards', storage = 'goodluck_collectibles_card_storage'}
                schema = schema:gsub('%-%-[^\n]*', '')
                schema = schema:gsub('`([%w_]+)`', function(name)
                    for kind, default in pairs(defaults) do if name == default then return '`' .. names[kind] .. '`' end end
                    return '`' .. name .. '`'
                end)
                for statement in schema:gmatch('[^;]+') do
                    if statement:match('%S') then query(statement) end
                end
            end
            migrate()
            hydrate()
            return true
        end,
        loadCatalog = function() return MetaComic.CopyTable(catalog) end,
        reloadDefinitions = function()
            if refreshing then
                repeat Wait(0) until not refreshing
                return refreshOk, refreshError
            end
            if writing then return false, 'Another database operation is in progress. Reopen /cardadmin to retry.' end
            writing, refreshing = true, true
            local ok, err = pcall(hydrate)
            refreshOk, refreshError = ok, err
            writing, refreshing = false, false
            return ok, err
        end,
        saveCatalog = function(cards) return save('catalog', cards) end,
        saveCard = function(card)
            local nextCatalog = MetaComic.CopyTable(catalog)
            for index, existing in ipairs(nextCatalog) do
                if existing.id == card.id then
                    nextCatalog[index] = MetaComic.CopyTable(card)
                    return save('catalog', nextCatalog)
                end
            end
            nextCatalog[#nextCatalog + 1] = MetaComic.CopyTable(card)
            return save('catalog', nextCatalog)
        end,
        deleteCard = function(id)
            if #catalog <= 1 then return false, 'at least one card must remain in the catalog' end
            local nextCatalog, found = {}, false
            for _, card in ipairs(catalog) do
                if card.id == id then found = true else nextCatalog[#nextCatalog + 1] = MetaComic.CopyTable(card) end
            end
            if not found then return false, 'card was not found' end
            return save('catalog', nextCatalog)
        end,
        loadSets = function() return MetaComic.CopyTable(sets) end,
        saveSets = function(list) return save('sets', list) end,
        restoreMissingDefinitions = restoreMissingDefinitions,
        addCards = function(owner, cards)
            local statements = {}
            for _, card in ipairs(cards or {}) do
                append(statements, ('INSERT INTO `%s` (`owner_identifier`, `instance_id`, `card_key`, `card_id`, `variant_id`, `card_json`) VALUES (?, ?, ?, ?, ?, ?)'):format(names.instances), {
                    owner, card.instanceId, card.cardKey or '', card.baseCardId or card.id, card.variantId or '', json.encode(card),
                })
            end
            if not transaction(statements) then error('Could not persist acquired cards') end
            return true
        end,
        getCollection = function(owner)
            local rows = query(('SELECT `card_json` FROM `%s` WHERE `owner_identifier` = ? ORDER BY `id` DESC'):format(names.instances), {owner})
            local result = {}
            for _, row in ipairs(rows) do
                local ok, card = pcall(json.decode, row.card_json)
                if ok and type(card) == 'table' then result[#result + 1] = card end
            end
            return result
        end,
    }
end
