-- Each module owns its definitions, presentation, and container opening rules.
-- Inventory mutation remains in server handlers/adapters, never client modules.
MetaComic.Collectibles = { types = {}, containers = {} }
local registry = MetaComic.Collectibles

local function register(target, id, definition)
    assert(type(id) == 'string' and id:match('^[%w_]+$'), 'Invalid collectible module id')
    assert(type(definition) == 'table', 'Module definition must be a table')
    assert(target[id] == nil, 'Duplicate collectible module: ' .. id)
    target[id] = definition
end

function registry.registerType(id, definition)
    register(registry.types, id, definition)
end

function registry.registerContainer(id, definition)
    assert(registry.types[definition.typeId], 'Register the collectible type before its containers')
    assert(type(definition.open) == 'function' or registry.containers[definition.contains], 'Container requires a server handler or registered contents')
    register(registry.containers, id, definition)
end

-- Items saved before the "collectible" spelling fix (inventory metadata, item_json, data/collectibles.json) name
-- their type with the old misspelled key. Read types through typeOf, and rename loaded data with normalize.
local LEGACY_TYPE_KEY = 'collectableType'
function registry.typeOf(item)
    if type(item) ~= 'table' then return nil end
    return item.collectibleType or item[LEGACY_TYPE_KEY]
end
function registry.normalize(value, depth)
    depth = depth or 0
    if type(value) ~= 'table' or depth > 16 then return value end
    if value[LEGACY_TYPE_KEY] ~= nil then
        if value.collectibleType == nil then value.collectibleType = value[LEGACY_TYPE_KEY] end
        value[LEGACY_TYPE_KEY] = nil
    end
    for _, child in pairs(value) do
        if type(child) == 'table' then registry.normalize(child, depth + 1) end
    end
    return value
end

function registry.snapshot(typeId, item)
    assert(registry.types[typeId], 'Unknown collectible type: ' .. tostring(typeId))
    assert(type(item) == 'table', 'Collectible snapshot must be a table')
    local snapshot = MetaComic.CopyTable(item)
    snapshot.collectibleType = typeId
    return snapshot
end

function registry.open(containerId, context)
    local container = registry.containers[containerId]
    if not container then return nil, 'Unknown collectible container' end
    if not container.open then return nil, 'This container dispenses other containers through its server inventory handler' end
    local items, err, definition = container.open(context)
    if not items then return nil, err end
    local snapshots = {}
    for index, item in ipairs(items) do snapshots[index] = registry.snapshot(container.typeId, item) end
    return snapshots, err, definition
end

function registry.containerCount(containerId)
    local container = assert(registry.containers[containerId], 'Unknown collectible container')
    local count = type(container.count) == 'function' and container.count() or container.count
    return math.max(1, math.floor(tonumber(count) or 1))
end
