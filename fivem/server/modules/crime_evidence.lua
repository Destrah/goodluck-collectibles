-- Server-selected evidence from validated crime attempts; adapters map external export signatures.
local cfg = Config.CrimeEvidence or {}
local service = {}
MetaComic.CrimeEvidence = service
local function roll(chance) return math.random() * 100 < math.max(0, math.min(100, tonumber(chance) or 0)) end
local bloodRequests, bloodSequence = {}, 0
local function evidenceCoords(source, entry, kind)
    local ped = GetPlayerPed(source)
    local player = ped ~= 0 and DoesEntityExist(ped) and GetEntityCoords and GetEntityCoords(ped) or nil
    if kind == 'blood' then
        local blood = cfg.Blood or {}
        local radius = math.max(0, tonumber(blood.ScatterRadius) or 0.25)
        local angle, distance = math.random() * math.pi * 2, math.sqrt(math.random()) * radius
        return vector3((player and player.x or entry.x) + math.cos(angle) * distance,
            (player and player.y or entry.y) + math.sin(angle) * distance,
            (player and player.z or entry.z) + (tonumber(blood.HeightOffset) or -0.9))
    end
    local position = (cfg.Fingerprints or {}).Placement or {}
    local halfWidth = math.max(0.05, tonumber(position.HalfWidth) or 0.575)
    local halfDepth = math.max(0.05, tonumber(position.HalfDepth) or 0.425)
    local angle = math.rad(tonumber(entry.h) or 0)
    local cos, sin = math.cos(angle), math.sin(angle)
    local dx, dy = player and player.x - entry.x or 0, player and player.y - entry.y or -1
    local px, py = cos * dx + sin * dy, -sin * dx + cos * dy
    local frontNegative = ((Config.VendingMachines or {}).Placement or {}).FrontIsNegativeY ~= false
    local surface = math.max(0.01, tonumber(position.SurfaceOffset) or 0.08)
    local scatter = math.max(0, tonumber(position.ScatterRadius) or 0.18)
    local jitter = (math.random() * 2 - 1) * scatter
    local x, y
    if position.Face ~= 'front' and player and math.abs(px) / halfWidth > math.abs(py) / halfDepth then
        x = (px < 0 and -1 or 1) * (halfWidth + surface)
        y = math.max(-halfDepth + 0.02, math.min(halfDepth - 0.02, py + jitter))
    else
        x = math.max(-halfWidth + 0.02, math.min(halfWidth - 0.02, px + jitter))
        local direction = py < 0 and -1 or 1
        if position.Face == 'front' or not player then direction = frontNegative and -1 or 1 end
        y = direction * (halfDepth + surface)
    end
    local z = entry.z + (tonumber(position.HeightOffset) or 0)
        + (math.random() * 2 - 1) * math.max(0, tonumber(position.VerticalScatter) or 0.12)
    return vector3(entry.x + cos * x - sin * y, entry.y + sin * x + cos * y, z)
end
local function payload(source, entry, action, stage, kind)
    return { source = source, identifier = MetaComic.VendingRegistry.identifierOf(source),
        serial = entry.serial, machineId = entry.id, action = action, stage = stage, kind = kind,
        coords = evidenceCoords(source, entry, kind), timestamp = os.time() }
end
-- Only ground height comes back from the client; chance, identity and XY are server-selected.
RegisterNetEvent('meta_comic:server:crimeBloodGround', function(token, z)
    local source = source
    local request = bloodRequests[source] and bloodRequests[source][token]
    if not request then return end
    bloodRequests[source][token] = nil
    if request.expires < os.time() or type(z) ~= 'number' or z ~= z or math.abs(z - request.coords.z) > 3 then return end
    local ped = GetPlayerPed(source)
    if ped == 0 or not DoesEntityExist(ped) then return end
    local player = GetEntityCoords(ped)
    if (player.x - request.coords.x) ^ 2 + (player.y - request.coords.y) ^ 2 > 9 then return end
    local ok, err = pcall(TriggerEvent, 'evidence:server:CreateBlood', {
        src = source, coords = vector3(request.coords.x, request.coords.y, z + 0.02),
    })
    if not ok then print(('[vending evidence] Blood adapter failed: %s'):format(tostring(err))) end
end)
AddEventHandler('playerDropped', function() bloodRequests[source] = nil end)
local function emit(data)
    for _, adapter in ipairs(cfg.Adapters or {}) do
        if adapter.Enabled ~= false and (not adapter.Kinds or adapter.Kinds[data.kind]) then
            local ok, err = pcall(function()
                if adapter.Type == 'rush-evidence' then
                    if GetResourceState(adapter.Resource or 'rush-evidence') ~= 'started' then return end
                    if data.kind == 'fingerprint' then
                        return TriggerClientEvent('evidence:client:CreateFingerprint', data.source, data.coords)
                    end
                    local pending = bloodRequests[data.source] or {}
                    bloodRequests[data.source] = pending
                    for token, request in pairs(pending) do if request.expires < os.time() then pending[token] = nil end end
                    bloodSequence = bloodSequence + 1
                    local token = ('%s:%d:%d'):format(data.source, os.time(), bloodSequence)
                    pending[token] = { coords = data.coords, expires = os.time() + 10 }
                    return TriggerClientEvent('meta_comic:client:crimeBloodGround', data.source, { token = token, coords = data.coords })
                end
                if type(adapter.Create) == 'function' then return adapter.Create(data) end
                if adapter.Resource and adapter.Export and GetResourceState(adapter.Resource) == 'started' then
                    return exports[adapter.Resource][adapter.Export](data)
                end
            end)
            if not ok then print(('[vending evidence] Adapter failed: %s'):format(tostring(err))) end
        end
    end
end
function service.start(source, entry, action)
    local prints = cfg.Fingerprints or {}
    if cfg.Enabled == false or prints.Enabled == false or not (prints.Actions or {})[action] then return end
    local data = payload(source, entry, action, 'start', 'fingerprint')
    if type(prints.IsWearingGloves) == 'function' then
        local ok, gloves = pcall(prints.IsWearingGloves, source, data)
        if ok and gloves == true then return end
    end
    if roll(prints.Chance) then emit(data) end
end
function service.failure(source, entry, action)
    local injury = cfg.Injury or {}
    local settings = (injury.Actions or {})[action]
    if cfg.Enabled == false or injury.Enabled == false or not settings or not roll(settings.Chance) then return end
    local damage = math.max(0, math.min(100, math.floor(tonumber(settings.Damage) or 0)))
    local ped = GetPlayerPed(source)
    if damage == 0 or ped == 0 or not DoesEntityExist(ped) then return end
    local health = GetEntityHealth(ped)
    if health <= 101 then return end
    -- Server-owned damage selection; no client event accepts arbitrary injury/evidence requests.
    TriggerClientEvent('meta_comic:client:crimeInjury', source, damage)
    local blood = cfg.Blood or {}
    if blood.Enabled ~= false and roll(blood.Chance) then
        local data = payload(source, entry, action, 'fail', 'blood')
        data.damage = damage
        emit(data)
    end
end
