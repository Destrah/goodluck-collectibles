-- Each module owns its definitions, presentation, and container opening rules.
-- Inventory mutation remains in server handlers/adapters, never client modules.
MetaComic.Collectables = { types = {}, containers = {} }
local registry = MetaComic.Collectables

local function register(target, id, definition)
    assert(type(id) == 'string' and id:match('^[%w_]+$'), 'Invalid collectable module id')
    assert(type(definition) == 'table', 'Module definition must be a table')
    assert(target[id] == nil, 'Duplicate collectable module: ' .. id)
    target[id] = definition
end

function registry.registerType(id, definition)
    register(registry.types, id, definition)
end

function registry.registerContainer(id, definition)
    assert(registry.types[definition.typeId], 'Register the collectable type before its containers')
    assert(type(definition.open) == 'function' or registry.containers[definition.contains], 'Container requires a server handler or registered contents')
    register(registry.containers, id, definition)
end

function registry.snapshot(typeId, item)
    assert(registry.types[typeId], 'Unknown collectable type: ' .. tostring(typeId))
    assert(type(item) == 'table', 'Collectable snapshot must be a table')
    local snapshot = MetaComic.CopyTable(item)
    snapshot.collectableType = typeId
    return snapshot
end

function registry.open(containerId, context)
    local container = registry.containers[containerId]
    if not container then return nil, 'Unknown collectable container' end
    if not container.open then return nil, 'This container dispenses other containers through its server inventory handler' end
    local items, err, definition = container.open(context)
    if not items then return nil, err end
    local snapshots = {}
    for index, item in ipairs(items) do snapshots[index] = registry.snapshot(container.typeId, item) end
    return snapshots, err, definition
end

function registry.containerCount(containerId)
    local container = assert(registry.containers[containerId], 'Unknown collectable container')
    local count = type(container.count) == 'function' and container.count() or container.count
    return math.max(1, math.floor(tonumber(count) or 1))
end
