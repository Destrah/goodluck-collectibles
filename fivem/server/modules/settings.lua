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
    local recovered = MetaComic.RuntimeSaves and MetaComic.RuntimeSaves.pending('settings') or {}
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
    for key, pending in pairs(recovered) do values[key] = pending.value end
    loaded = true
end

local function writeRuntime(key, pending)
    if not loaded then return false end
    if useMysql then
        assert(db():query_async(('INSERT INTO `%s` (setting_key, value_json) VALUES (?, ?) ON DUPLICATE KEY UPDATE value_json = VALUES(value_json)'):format(tableName),
            { key, json.encode(pending.value) }), 'database write failed')
    else
        assert(SaveResourceFile(resource, fileName, json.encode(values), -1), 'Could not save ' .. fileName)
    end
    return true
end
if MetaComic.RuntimeSaves then MetaComic.RuntimeSaves.register('settings', writeRuntime) end

-- Runtime state is authoritative immediately; database errors are retried by the queue.
function service.stage(key, value)
    if not MetaComic.RuntimeSaves then return service.set(key, value) end
    load()
    values[key] = value
    return MetaComic.RuntimeSaves.mark('settings', key, { value = value })
end

function service.get(key, default)
    load()
    local value = values[key]
    if value == nil then return default end
    return value
end
-- Drop migrated legacy blobs from the small-settings cache without touching the database.
function service.forget(key) values[key] = nil end

-- returns true, or false and an error
function service.set(key, value)
    load()
    local queue = MetaComic.RuntimeSaves
    local function write()
        local before = queue and queue.revision('settings', key)
        if useMysql then
            assert(db():query_async(('INSERT INTO `%s` (setting_key, value_json) VALUES (?, ?) ON DUPLICATE KEY UPDATE value_json = VALUES(value_json)'):format(tableName),
                { key, json.encode(value) }), 'database write failed')
            if not queue or queue.revision('settings', key) == before then values[key] = value end
        else
            local nextValues = MetaComic.CopyTable(values)
            nextValues[key] = value
            assert(SaveResourceFile(resource, fileName, json.encode(nextValues), -1), 'Could not save ' .. fileName)
            values = nextValues
        end
        return true
    end
    local ok, err
    if queue then ok, err = queue.immediate('settings', key, write)
    else ok, err = pcall(write) end
    if not ok then print('[meta-comic] settings save failed: ' .. tostring(err)) end
    return ok, not ok and tostring(err) or nil
end

CreateThread(load)
