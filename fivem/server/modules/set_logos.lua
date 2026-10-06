-- Logos for collectible sets, keyed '<collectable type>:<set id>' (card sets: 'trading_card:<id>'). Kept apart from the
-- set definitions so the catalog storage is unchanged; saved with Config.Persistence (MySQL table, otherwise a JSON
-- file). A logo is an image URL; a pasted image is uploaded to Fivemanage (artwork folder) when a key is set.
MetaComic.SetLogos = {}
local service = MetaComic.SetLogos
local resource = GetCurrentResourceName()
local useMysql = MetaComic.Persistence.name == 'mysql'
local tableName = 'goodluck_collectibles_set_logos'
local fileName = 'data/set_logos.json'
local MAX_INLINE = 600 * 1024 -- a pasted logo that could not be uploaded stays inline up to this size
local logos, loaded = {}, false

local function db() return exports[Config.Database.Resource or 'oxmysql'] end

local function load()
    if loaded then return end
    loaded = true
    if useMysql then
        if Config.Database.AutoCreateSchema then
            db():query_async(([[CREATE TABLE IF NOT EXISTS `%s` (
 `set_key` VARCHAR(200) COLLATE utf8mb4_bin PRIMARY KEY,
 `logo` MEDIUMTEXT NOT NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4]]):format(tableName))
        end
        for _, row in ipairs(db():query_async(('SELECT set_key, logo FROM `%s`'):format(tableName)) or {}) do
            logos[row.set_key] = row.logo
        end
    else
        local ok, decoded = pcall(json.decode, LoadResourceFile(resource, fileName) or '')
        logos = ok and type(decoded) == 'table' and decoded or {}
    end
end
CreateThread(load)

function service.get(kind, id)
    load()
    return logos[('%s:%s'):format(kind, tostring(id))]
end

-- logo of every set of one type: { [set id] = logo }
function service.all(kind)
    load()
    local prefix, result = kind .. ':', {}
    for key, logo in pairs(logos) do
        if key:sub(1, #prefix) == prefix then result[key:sub(#prefix + 1)] = logo end
    end
    return result
end

local function clean(logo, upload)
    if type(logo) ~= 'string' then return nil end
    logo = logo:match('^%s*(.-)%s*$')
    if logo == '' then return nil end
    if logo:sub(1, 11) == 'data:image/' then
        local url = upload and upload(logo)
        if url then return url end
        if #logo > MAX_INLINE then error('A logo image is too large; set a Fivemanage key or use a smaller image') end
        return logo
    end
    if not (logo:match('^https?://') or logo:match('^nui://')) or #logo > 2048 then error('A logo must be an image URL or a pasted image') end
    return logo
end

-- Replaces every logo of one type: map = { [set id] = logo } (sets left out lose their logo).
-- upload(dataUrl) -> url turns pasted images into short URLs.
function service.replaceKind(kind, map, upload)
    load()
    local prefix, nextLogos, changed = kind .. ':', {}, {}
    for key, logo in pairs(logos) do
        if key:sub(1, #prefix) ~= prefix then nextLogos[key] = logo end
    end
    for id, logo in pairs(map or {}) do
        local value = clean(logo, upload)
        if value then
            nextLogos[prefix .. tostring(id)] = value
            changed[#changed + 1] = { prefix .. tostring(id), value }
        end
    end
    if useMysql then
        local statements = { { query = ('DELETE FROM `%s` WHERE LEFT(set_key, ?) = ?'):format(tableName), values = { #prefix, prefix } } }
        for _, row in ipairs(changed) do
            statements[#statements + 1] = { query = ('INSERT INTO `%s` (set_key, logo) VALUES (?, ?)'):format(tableName), values = row }
        end
        if not db():transaction_async(statements) then error('Could not save set logos') end
    else
        assert(SaveResourceFile(resource, fileName, json.encode(nextLogos), -1), 'Could not save ' .. fileName)
    end
    logos = nextLogos
end
