RushCards.PersistenceAdapters.mysql = function()
    local tableName = Config.Database.Table
    local dbResource = Config.Database.Resource or 'oxmysql'

    local function ensureAvailable()
        return GetResourceState(dbResource) == 'started'
    end

    local function query(sql, params)
        return exports[dbResource]:query_async(sql, params or {})
    end

    local function insert(sql, params)
        return exports[dbResource]:insert_async(sql, params or {})
    end

    return {
        name = 'mysql',
        init = function()
            if not ensureAvailable() then
                error(('MySQL persistence selected but %s is not started'):format(dbResource))
            end
            if Config.Database.AutoCreateSchema then
                query(([=[
                    CREATE TABLE IF NOT EXISTS `%s` (
                      `id` BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
                      `owner_identifier` VARCHAR(96) NOT NULL,
                      `instance_id` VARCHAR(96) NOT NULL,
                      `card_key` VARCHAR(160) NOT NULL,
                      `card_id` VARCHAR(160) NULL,
                      `variant_id` VARCHAR(180) NULL,
                      `card_json` LONGTEXT NOT NULL,
                      `acquired_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
                      PRIMARY KEY (`id`),
                      UNIQUE KEY `ux_instance_id` (`instance_id`),
                      KEY `ix_owner` (`owner_identifier`),
                      KEY `ix_card_key` (`card_key`)
                    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
                ]=]):format(tableName))
            end
            return true
        end,
        addCards = function(owner, cards)
            for _, card in ipairs(cards or {}) do
                insert(([[
                    INSERT INTO `%s`
                    (`owner_identifier`, `instance_id`, `card_key`, `card_id`, `variant_id`, `card_json`)
                    VALUES (?, ?, ?, ?, ?, ?)
                ]]):format(tableName), {
                    owner,
                    card.instanceId,
                    card.cardKey or '',
                    card.baseCardId or card.id,
                    card.variantId,
                    json.encode(card),
                })
            end
            return true
        end,
        getCollection = function(owner)
            local rows = query(([[SELECT `card_json` FROM `%s` WHERE `owner_identifier` = ? ORDER BY `id` DESC]]):format(tableName), { owner }) or {}
            local cards = {}
            for _, row in ipairs(rows) do
                local ok, decoded = pcall(json.decode, row.card_json)
                if ok and decoded then cards[#cards + 1] = decoded end
            end
            return cards
        end,
    }
end
