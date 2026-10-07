-- Small saved settings edited in game (crafting recipes, vending owner tax rates, ...): one JSON value per key in
-- MySQL (goodluck_collectibles_settings) or data/settings.json, following Config.Persistence.
MetaComic.Settings = {}
local service = MetaComic.Settings
local resource = GetCurrentResourceName()
local useMysql = MetaComic.Persistence.name == 'mysql'
local tableName = 'goodluck_collectibles_settings'
local fileName = 'data/settings.json'
local values, loaded = {}, false

local function db() return exports[Config.Database.Resource or 'oxmysql'] end

local loading = false
local function load()
    if loaded then return end
    -- another caller is mid-query: wait for it, or this caller would see empty values (and a save would wipe the table)
    if loading then while not loaded do Wait(0) end return end
    loading = true
    local done, err = pcall(function()
    if useMysql then
        if Config.Database.AutoCreateSchema then
            db():query_async(([[CREATE TABLE IF NOT EXISTS `%s` (
 `setting_key` VARCHAR(100) COLLATE utf8mb4_bin PRIMARY KEY,
 `value_json` LONGTEXT NOT NULL,
 `updated_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4]]):format(tableName))
        end
        for _, row in ipairs(db():query_async(('SELECT setting_key, value_json FROM `%s`'):format(tableName)) or {}) do
            local ok, decoded = pcall(json.decode, row.value_json)
            if ok then values[row.setting_key] = decoded end
        end
    else
        local ok, decoded = pcall(json.decode, LoadResourceFile(resource, fileName) or '')
        values = ok and type(decoded) == 'table' and decoded or {}
    end
    end)
    if not done then print('[meta-comic] settings load failed: ' .. tostring(err)) end
    loaded = true
end

function service.get(key, default)
    load()
    local value = values[key]
    if value == nil then return default end
    return value
end

-- returns true, or false and an error
function service.set(key, value)
    load()
    local ok, err = pcall(function()
        if useMysql then
            assert(db():query_async(('INSERT INTO `%s` (setting_key, value_json) VALUES (?, ?) ON DUPLICATE KEY UPDATE value_json = VALUES(value_json)'):format(tableName),
                { key, json.encode(value) }), 'database write failed')
            values[key] = value
        else
            local nextValues = MetaComic.CopyTable(values)
            nextValues[key] = value
            assert(SaveResourceFile(resource, fileName, json.encode(nextValues), -1), 'Could not save ' .. fileName)
            values = nextValues
        end
    end)
    if not ok then print('[meta-comic] settings save failed: ' .. tostring(err)) end
    return ok, not ok and tostring(err) or nil
end

CreateThread(load)
