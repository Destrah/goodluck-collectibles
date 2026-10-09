-- Reusable write-behind queue for state already owned by this resource's server memory.
-- Explicit editor saves and external inventory/money transactions remain synchronous.
local service = {}
MetaComic.RuntimeSaves = service
local resource, file = GetCurrentResourceName(), 'data/runtime-pending.json'
local writers, dirty, version, flushing, stopping = {}, {}, 0, false, false
local ok, recovered = pcall(json.decode, LoadResourceFile(resource, file) or '')
if ok and type(recovered) == 'table' then
    for channel, entries in pairs(recovered) do
        if type(entries) == 'table' then
            dirty[channel] = {}
            for key, value in pairs(entries) do
                version = version + 1
                dirty[channel][key] = { value = value, version = version }
            end
        end
    end
end
local function checkpoint()
    local pending = {}
    for channel, entries in pairs(dirty) do
        pending[channel] = {}
        for key, entry in pairs(entries) do pending[channel][key] = entry.value end
    end
    local saved, error = pcall(function()
        assert(SaveResourceFile(resource, file, json.encode(pending), -1), 'Could not write runtime checkpoint')
    end)
    if not saved then print('[meta-comic] runtime checkpoint failed: ' .. tostring(error)) end
    return saved
end
function service.register(channel, writer) writers[channel] = writer end
service.checkpoint = checkpoint
function service.revision(channel, key)
    local entry = dirty[channel] and dirty[channel][tostring(key)]
    return entry and entry.version
end
function service.pending(channel)
    local result = {}
    for key, entry in pairs(dirty[channel] or {}) do
        if type(entry.value) == 'table' then result[key] = MetaComic.CopyTable(entry.value)
        else result[key] = entry.value end
    end
    return result
end
function service.mark(channel, key, value)
    version = version + 1
    dirty[channel] = dirty[channel] or {}
    dirty[channel][tostring(key)] = { value = value, version = version }
    if stopping then checkpoint() end
    return true
end
function service.discard(channel, key)
    if dirty[channel] then dirty[channel][tostring(key)] = nil end
    checkpoint() -- removal must also remove a recovered snapshot before another restart
end
-- Serialize an explicit save against the periodic writer so an older queued value cannot overwrite it.
function service.immediate(channel, key, callback)
    while flushing do Wait(0) end
    flushing = true
    local before = service.revision(channel, key)
    local saved, result = pcall(callback)
    if saved and result == true and service.revision(channel, key) == before then
        if dirty[channel] then dirty[channel][tostring(key)] = nil end
        checkpoint()
    end
    flushing = false
    return saved and result == true, not saved and tostring(result) or nil
end
function service.flush()
    if flushing then return false end
    local hasPending = false
    for _, entries in pairs(dirty) do if next(entries) then hasPending = true; break end end
    if not hasPending then return true end
    flushing = true
    -- Snapshot before any database await; new changes get another version and stay dirty.
    local snapshot = MetaComic.CopyTable(dirty)
    checkpoint()
    local success = true
    for channel, entries in pairs(snapshot) do
        local writer = writers[channel]
        if writer then
            for key, entry in pairs(entries) do
                local saved, result = pcall(writer, key, entry.value)
                if saved and result == true then
                    local live = dirty[channel] and dirty[channel][key]
                    if live and live.version == entry.version then dirty[channel][key] = nil end
                else
                    success = false
                    print(('[meta-comic] runtime save %s/%s failed; retrying next interval: %s'):format(channel, key, tostring(result)))
                end
            end
        end
    end
    checkpoint()
    flushing = false
    return success
end
CreateThread(function()
    while not stopping do
        Wait(math.max(1, tonumber((Config.RuntimeSaves or {}).IntervalSeconds) or 30) * 1000)
        if not stopping then service.flush() end
    end
end)
AddEventHandler('onResourceStop', function(name)
    if name ~= resource then return end
    stopping = true
    -- Stop handlers cannot safely await oxmysql: its callback can outlive this resource's Lua references.
    -- The next start overlays this durable checkpoint and the normal queue persists it.
    checkpoint()
end)
