-- Placed vending machines (Config.VendingMachines). Every location lives in memory here; a machine's prop only
-- exists (client-side, not networked) while the player is near it. The distance check sleeps for as long as the
-- player needs to reach the closest spawn / despawn edge, so with nothing nearby it barely runs.
local cfg = Config.VendingMachines or {}
if cfg.Enabled == false then return end

local SPAWN = tonumber(cfg.SpawnDistance) or 100.0
local DESPAWN = math.max(SPAWN + 5.0, tonumber(cfg.DespawnDistance) or SPAWN + 20.0) -- gap stops flicker at the edge
local SPEED = tonumber(cfg.CheckSpeed) or 80.0 -- m/s the player is assumed to travel at most
local MIN_SLEEP, MAX_SLEEP = 250, tonumber(cfg.MaxSleep) or 5000

local machines, count = {}, 0
local access = { manage = false, restock = false, controls = {} } -- which ox_target options this player sees (the server re-checks)
local missingModels = {}
local byEntity = {} -- spawned prop -> machine, for ox_target lookups
local ghost

local function notify(message, notifyType) TriggerEvent('meta_comic:client:notify', message, notifyType) end

local function loadModel(hash)
    if not IsModelInCdimage(hash) then return nil end
    RequestModel(hash)
    local timeout = GetGameTimer() + 5000
    while not HasModelLoaded(hash) and GetGameTimer() < timeout do Wait(0) end
    return HasModelLoaded(hash) and hash or nil
end

local function despawn(machine)
    machine.padlockGeneration = (machine.padlockGeneration or 0) + 1
    if machine.padlockProp and DoesEntityExist(machine.padlockProp) then DeleteEntity(machine.padlockProp) end
    machine.padlockProp = nil
    if machine.skimmerProp and DoesEntityExist(machine.skimmerProp) then DeleteEntity(machine.skimmerProp) end
    machine.skimmerProp = nil
    for _, prop in ipairs(machine.sealProps or {}) do if DoesEntityExist(prop) then DeleteEntity(prop) end end
    machine.sealProps = nil
    for _, prop in ipairs(machine.packProps or {}) do if DoesEntityExist(prop) then DeleteEntity(prop) end end
    machine.packProps, machine.packKey, machine.packParent = nil, nil, nil -- the door module re-sends the parent on rebuild
    machine.packRetries, machine.packRetryToken = 0, (machine.packRetryToken or 0) + 1 -- cancel a pending pack retry
    machine.packGen = (machine.packGen or 0) + 1 -- abandon a sync still loading models
    if machine.entity then
        if DoesEntityExist(machine.entity) then DeleteEntity(machine.entity) end
        byEntity[machine.entity] = nil
        machine.entity = nil
    end
end

local function syncPadlock(machine)
    machine.padlockGeneration = (machine.padlockGeneration or 0) + 1
    local generation = machine.padlockGeneration
    if machine.padlockProp and DoesEntityExist(machine.padlockProp) then DeleteEntity(machine.padlockProp) end
    machine.padlockProp = nil
    local settings = (cfg.Keys or {}).Padlock or {}
    if not machine.padlock or not machine.entity then return end
    local parent = machine.entity
    local hash = loadModel(joaat(settings.Model or 'prop_cs_padlock'))
    if not hash then return end
    if machines[machine.id] ~= machine or machine.entity ~= parent or not DoesEntityExist(parent)
        or generation ~= machine.padlockGeneration or not machine.padlock then return SetModelAsNoLongerNeeded(hash) end
    local coords = GetEntityCoords(parent)
    local prop = CreateObjectNoOffset(hash, coords.x, coords.y, coords.z, false, false, false)
    SetEntityCollision(prop, false, false)
    local offset, rotation = settings.Offset or vector3(0.54, -0.46, 0.32), settings.Rotation or vector3(0.0, 0.0, 0.0)
    AttachEntityToEntity(prop, parent, -1, offset.x, offset.y, offset.z, rotation.x, rotation.y, rotation.z, false, false, false, false, 2, true)
    machine.padlockProp = prop
    SetModelAsNoLongerNeeded(hash)
end

local syncSkimmer
syncSkimmer = function(machine)
    if machine.skimmerProp and DoesEntityExist(machine.skimmerProp) then DeleteEntity(machine.skimmerProp) end
    machine.skimmerProp = nil
    local settings = cfg.Skimmer or {}
    if not machine.skimmer or settings.Enabled == false or not settings.Model or not machine.entity then return end
    local parent = machine.entity
    local hash = loadModel(joaat(settings.Model))
    if not hash then
        -- right after a script restart the streamed prop can take a moment to register: keep retrying every 2s while
        -- this machine prop is spawned (a despawn or a newer sync cancels it), and only warn once
        machine.skimmerTries = (machine.skimmerTries or 0) + 1
        if machine.skimmerTries == 15 and not missingModels[joaat(settings.Model)] then
            missingModels[joaat(settings.Model)] = true
            print('[meta-comic] Skimmer model is not streamed (still retrying): ' .. settings.Model)
        end
        machine.skimmerToken = (machine.skimmerToken or 0) + 1
        local token = machine.skimmerToken
        SetTimeout(2000, function()
            if machines[machine.id] == machine and machine.entity == parent and machine.skimmerToken == token and machine.skimmer
                and not machine.skimmerProp then syncSkimmer(machine) end
        end)
        return
    end
    machine.skimmerTries = 0
    if machines[machine.id] ~= machine or machine.entity ~= parent or not DoesEntityExist(parent) or not machine.skimmer then
        return SetModelAsNoLongerNeeded(hash)
    end
    local coords = GetEntityCoords(parent)
    local prop = CreateObjectNoOffset(hash, coords.x, coords.y, coords.z, false, false, false)
    SetEntityCollision(prop, false, false)
    local offset, rotation = settings.Offset or vector3(0.35, -0.44, 0.15), settings.Rotation or vector3(0.0, 0.0, 0.0)
    AttachEntityToEntity(prop, parent, -1, offset.x, offset.y, offset.z, rotation.x, rotation.y, rotation.z, false, false, false, false, 2, true)
    machine.skimmerProp = prop
    SetModelAsNoLongerNeeded(hash)
end

-- Chain and padlock round a machine secured after a break-in (Config.VendingMachines.Keys.Seal). It follows the
-- server's record, so it's back after restarts and reconnects. One base game chain lock (a flat loop with a padlock on
-- one long side) lies against each face, half of it inside the machine: on the front the padlock side faces out, on the
-- other faces it's tucked inside so only the plain chain shows. Placement comes from the model's own size.
local SEAL_FACES = {
    front = { n = vector2(0.0, -1.0) }, back = { n = vector2(0.0, 1.0) },
    left = { n = vector2(-1.0, 0.0) }, right = { n = vector2(1.0, 0.0) },
}
local function clearSeal(machine)
    for _, prop in ipairs(machine.sealProps or {}) do if DoesEntityExist(prop) then DeleteEntity(prop) end end
    machine.sealProps = nil
end
local function firstModel(list)
    for _, name in ipairs(type(list) == 'table' and list or { list }) do
        local hash = loadModel(type(name) == 'number' and name or joaat(name))
        if hash then return hash, name end
    end
end
local function syncSeal(machine)
    clearSeal(machine)
    local seal = (cfg.Keys or {}).Seal or {}
    if not machine.securitySeal or seal.Props == false or not machine.entity then return end
    local parent = machine.entity
    -- Model: the long chain round all four faces, its own padlocks tucked inside the machine.
    -- Lock.Model: a short chain lock on the front with its padlock facing out. Each: one name or a list (first one found).
    local lock = seal.Lock or {}
    local hash, model = firstModel(seal.Model or 'm23_2_prop_m32_chainlock_01a')
    local lockHash, lockModel
    if lock.Enabled ~= false then lockHash, lockModel = firstModel(lock.Model or 'h4_prop_h4_chain_lock_01a') end
    local fallback = false
    if not hash and not lockHash then
        if not missingModels['seal'] then
            missingModels['seal'] = true
            print('[meta-comic] No chain lock model from Keys.Seal is in this game build, using a padlock')
        end
        if seal.FallbackModel == false then return end
        hash, fallback = loadModel(joaat(seal.FallbackModel or 'prop_cs_padlock')), true
        if not hash then return end
    end
    local function release()
        if hash then SetModelAsNoLongerNeeded(hash) end
        if lockHash then SetModelAsNoLongerNeeded(lockHash) end
    end
    if machines[machine.id] ~= machine or machine.entity ~= parent or not DoesEntityExist(parent) or not machine.securitySeal then
        return release()
    end
    local coords = GetEntityCoords(parent)
    local props = {}
    local function place(model, offset, heading)
        local prop = CreateObjectNoOffset(model, coords.x, coords.y, coords.z, false, false, false)
        SetEntityCollision(prop, false, false)
        AttachEntityToEntity(prop, parent, -1, offset.x, offset.y, offset.z, 0.0, 0.0, heading, false, false, false, false, 2, true)
        props[#props + 1] = prop
    end
    if fallback then
        place(hash, seal.FallbackOffset or vector3(0.0, -0.46, 0.0), 0.0)
    else
        -- the machine's outer faces, from its own model (machine offsets, front = -y); Seal.Box overrides
        local size = seal.Box
        if not size then
            local mMin, mMax = GetModelDimensions(GetEntityModel(parent))
            size = { x = math.max(-mMin.x, mMax.x), front = mMin.y, back = mMax.y }
        end
        local gap = tonumber(seal.Gap) or 0.015
        -- lays a flat chain loop against one face: long axis along the face, outer strand just outside it, the rest
        -- inside the machine. lockOut turns the model's padlock side outwards (else inwards, hidden).
        -- lockSide: which end of the short axis the padlock is on in the model (flip 1 / -1 if it shows on the wrong side)
        -- lockTile: on the front, the middle copy turns its padlock outwards (the visible lock); the rest stay hidden
        local function fit(h, label, face, key, lockOut, lockSide, height, tile, lockTile)
            local min, max = GetModelDimensions(h)
            local dx, dy = max.x - min.x, max.y - min.y
            if seal.Debug and face == 'front' then
                print(('[meta-comic] seal model %s size %.2f x %.2f x %.2f m; machine faces x %.3f front %.3f back %.3f'):format(
                    tostring(label), dx, dy, max.z - min.z, size.x, size.front, size.back))
            end
            local center = vector2((min.x + max.x) / 2, (min.y + max.y) / 2)
            local longIsX = dx >= dy
            local width = longIsX and dy or dx
            local lockAxis = longIsX and vector2(0.0, lockSide) or vector2(lockSide, 0.0)
            local n = SEAL_FACES[face].n
            local facePos = n.x ~= 0.0 and vector2(n.x * size.x, 0.0) or vector2(0.0, n.y < 0 and size.front or size.back)
            local target = facePos + n * (gap - width / 2)
            -- yaw that turns the model's lock axis onto `want` (GTA yaw: x' = x cos - y sin, y' = x sin + y cos), and
            -- where the model's centre ends up, so the loop sits in the same spot whichever way it faces
            local function turn(out)
                local want = out and n or -n
                local yaw = math.atan(want.y, want.x) - math.atan(lockAxis.y, lockAxis.x)
                local c, s = math.cos(yaw), math.sin(yaw)
                return yaw, vector2(center.x * c - center.y * s, center.x * s + center.y * c)
            end
            -- fine tuning (Seal.Adjust, or live with /vendingsealtune): along the face, out from it, up, yaw
            local adjust = (seal.Adjust or {})[key] or {}
            local along = vector2(-n.y, n.x)
            -- tile: enough overlapping copies along a face wider than the chain to read as one continuous chain
            local long = longIsX and dx or dy
            local faceLength = n.x ~= 0.0 and (size.back - size.front) or size.x * 2
            -- the chains run out to the outer corners (they stand Out + Gap off each face) and a little round them
            local out = tonumber(seal.Out) or 0.0
            local span = faceLength + 2 * (gap + out) + 2 * (tonumber(seal.CornerReach) or 0.03)
            local spread = tile and math.max(0.0, span - long) or 0.0
            local count = spread > 0 and math.ceil(spread / (long * (tonumber(seal.Overlap) or 0.85))) + 1 or 1
            for i = 1, count do
                local slide = count > 1 and (-spread / 2 + spread * (i - 1) / (count - 1)) or 0.0
                local yaw, rotated = turn(lockOut or (lockTile and i == math.ceil(count / 2)))
                local nudge = along * ((tonumber(adjust[1]) or 0.0) + slide) + n * ((tonumber(adjust[2]) or 0.0) + out)
                place(h, vector3(target.x - rotated.x + nudge.x, target.y - rotated.y + nudge.y,
                    height - (min.z + max.z) / 2 + (tonumber(adjust[3]) or 0.0)), math.deg(yaw) + (tonumber(adjust[4]) or 0.0))
            end
        end
        local height = tonumber(seal.Height) or 0.02
        if hash then
            for _, face in ipairs(seal.Faces or { 'front', 'left', 'right', 'back' }) do
                if SEAL_FACES[face] then
                    fit(hash, model, face, face, false, tonumber(seal.LockSide) or 1, height, seal.Tile ~= false,
                        face == 'front' and seal.FrontLock ~= false)
                end
            end
        end
        if lockHash then fit(lockHash, lockModel, 'front', 'lock', true, tonumber(lock.LockSide) or 1, tonumber(lock.Height) or height, false) end
    end
    machine.sealProps = props
    release()
end

-- /vendingsealtune <front|left|right|back|lock> <along> <out> <up> <yaw>: moves that chain live on every chained
-- machine near you (Seal.Debug only) and prints the Adjust line to paste into the config
if ((cfg.Keys or {}).Seal or {}).Debug then
    RegisterCommand('vendingsealtune', function(_, args)
        local seal = cfg.Keys.Seal
        local face = args[1]
        if face == 'out' then -- /vendingsealtune out 0.1: push every chain further out (Seal.Out)
            seal.Out = tonumber(args[2]) or 0.0
            for _, machine in pairs(machines) do if machine.securitySeal and machine.entity then CreateThread(function() syncSeal(machine) end) end end
            return print(('[meta-comic] config: Out = %.3f,'):format(seal.Out))
        end
        if not SEAL_FACES[face] and face ~= 'lock' then return print('usage: /vendingsealtune <front|left|right|back|lock> <along> <out> <up> <yaw>') end
        seal.Adjust = seal.Adjust or {}
        seal.Adjust[face] = { tonumber(args[2]) or 0.0, tonumber(args[3]) or 0.0, tonumber(args[4]) or 0.0, tonumber(args[5]) or 0.0 }
        for _, machine in pairs(machines) do if machine.securitySeal and machine.entity then CreateThread(function() syncSeal(machine) end) end end
        local parts = {}
        for _, name in ipairs({ 'front', 'left', 'right', 'back', 'lock' }) do
            local a = seal.Adjust[name]
            if a then parts[#parts + 1] = ('%s = { %.3f, %.3f, %.3f, %.1f }'):format(name, a[1], a[2], a[3], a[4]) end
        end
        print('[meta-comic] config: Adjust = { ' .. table.concat(parts, ', ') .. ' },')
    end, false)
end

-- Packs in the window (Config.VendingMachines.SlotPacks): pack props stand in the 15 slots (rows A-C, columns 1-5)
-- and show how full the machine is. Each product gets an equal run of slots (A1, A2, ... in order); each filled slot
-- shows one prop standing for a share of the stock (scaled from the product's stock against Restock.MaxStock).
local slotPacks = cfg.SlotPacks or {}
local SLOT_ROWS = slotPacks.Rows or { 0.37, 0.05, -0.275 }                -- z of each row's shelf (machine offsets)
local SLOT_COLUMNS = slotPacks.Columns or { -0.413, -0.281, -0.15, -0.019, 0.108 } -- x of each column
local SLOT_FRONT = tonumber(slotPacks.Front) or -0.33                    -- y of the front pack (glass is at -0.428)
-- a bought pack slides out to DropFront, then falls to the PUSH tray at DropZ, then disappears
local DROP_FRONT = tonumber(slotPacks.DropFront) or -0.40
local DROP_Z = tonumber(slotPacks.DropZ) or -0.62
local DROP_MS = math.max(300, tonumber(slotPacks.DropMs) or 1500)
local SLOT_ROTATION = slotPacks.Rotation or vector3(0.0, 0.0, 0.0)
-- booster boxes stand on their side, their back reaching into the machine (Config: BoxRotation / BoxOffset)
local BOX_ROTATION = slotPacks.BoxRotation or vector3(0.0, 90.0, 0.0)
local BOX_OFFSET = slotPacks.BoxOffset or vector3(0.0, 0.05, 0.054)
-- a bought box turns its thin side to the glass while sliding forward, so it drops between the glass and the slots
local BOX_DROP_ROTATION = slotPacks.BoxDropRotation or vector3(0.0, 90.0, 90.0)
local BOX_DROP_FRONT = tonumber(slotPacks.BoxDropFront) or -0.38
local MAX_STOCK = math.max(1, tonumber((cfg.Restock or {}).MaxStock) or 100)

local packOffsets = {} -- pack prop -> vector3 offset in its slot
local packRotations = {} -- prop -> rotation when it isn't SLOT_ROTATION (booster boxes)
-- packs hang off the machine prop, or off the open-door body while the door module has the machine swapped out
local function packParent(machine)
    if machine.packParent and DoesEntityExist(machine.packParent) then return machine.packParent end
    return machine.entity
end
local function attachPack(machine, prop, offset, pitch)
    local rotation = packRotations[prop] or SLOT_ROTATION
    AttachEntityToEntity(prop, packParent(machine), -1, offset.x, offset.y, offset.z, rotation.x + (pitch or 0.0), rotation.y, rotation.z, false, false, false, false, 2, true)
end
local function clearPacks(machine)
    for _, prop in ipairs(machine.packProps or {}) do packOffsets[prop] = nil; packRotations[prop] = nil; if DoesEntityExist(prop) then DeleteEntity(prop) end end
    machine.packProps, machine.packKey, machine.packSlots = nil, nil, nil
end
local function syncPacks(machine)
    if slotPacks.Enabled == false or not machine.entity or not DoesEntityExist(machine.entity) then return clearPacks(machine) end
    local slotCount = #SLOT_ROWS * #SLOT_COLUMNS
    local products = {}
    for _, product in ipairs(machine.products or {}) do if #products < slotCount then products[#products + 1] = product end end
    local function physicalStock(product)
        local amount = machine.displayStock and machine.displayStock[product.set .. ':' .. product.kind]
        if amount == nil then amount = product.stock end
        return math.max(0, tonumber(amount) or 0)
    end
    -- which slots each product uses (kept on the product, which is replaced on every stock update)
    for i, product in ipairs(products) do
        local per = slotCount // #products
        product.packFirst, product.packLast = (i - 1) * per + 1, i * per
    end
    local key = {}
    for _, product in ipairs(products) do
        key[#key + 1] = product.set .. ':' .. tostring(product.kind) .. ':' .. tostring(physicalStock(product)) .. ':' .. tostring(product.maxStock or MAX_STOCK)
    end
    key = table.concat(key, ',')
    if machine.packKey == key and machine.packProps then return end
    clearPacks(machine)
    machine.packGen = (machine.packGen or 0) + 1 -- a newer sync (stock update while this one loads a model) wins
    local gen = machine.packGen
    machine.packKey, machine.packProps, machine.packSlots = key, {}, {}
    if #products == 0 then return end
    local parent = machine.entity
    local perProduct = slotCount // #products
    local slot, missing = 0, nil
    for _, product in ipairs(products) do
        local isBox = product.kind == 'box'
        local model = isBox and (slotPacks.BoxModel or 'prop_boosterbox_01') or slotPacks.Model or 'prop_boosterpack_01'
        local shift = isBox and BOX_OFFSET or vector3(0.0, 0.0, 0.0)
        local hash = loadModel(joaat(model))
        local stock = physicalStock(product)
        if not hash and stock > 0 then missing = model end
        local shown = stock > 0 and math.max(1, math.ceil(math.min(1, stock / (tonumber(product.maxStock) or MAX_STOCK)) * perProduct)) or 0
        for j = 1, perProduct do
            slot = slot + 1
            local row = SLOT_ROWS[(slot - 1) // #SLOT_COLUMNS + 1]
            local column = SLOT_COLUMNS[(slot - 1) % #SLOT_COLUMNS + 1]
            if hash and j <= shown then
                if machine.entity ~= parent or machine.packGen ~= gen or not DoesEntityExist(parent) then return end
                local prop = CreateObjectNoOffset(hash, machine.coords.x, machine.coords.y, machine.coords.z, false, false, false)
                SetEntityCollision(prop, false, false)
                packOffsets[prop] = vector3(column + shift.x, SLOT_FRONT + shift.y, row + shift.z)
                if isBox then packRotations[prop] = BOX_ROTATION end
                attachPack(machine, prop, packOffsets[prop])
                machine.packProps[#machine.packProps + 1] = prop
                machine.packSlots[slot] = machine.packSlots[slot] or { row = row + shift.z, column = column + shift.x, front = SLOT_FRONT + shift.y, box = isBox }
                table.insert(machine.packSlots[slot], prop)
            end
        end
        if hash then SetModelAsNoLongerNeeded(hash) end
    end
    -- right after a restart / stream-in the pack model can still be missing: don't remember an incomplete window,
    -- keep retrying every 2s while this prop is spawned (a newer sync or a despawn cancels the pending retry)
    if machine.packGen ~= gen then return end
    machine.packRetryToken = (machine.packRetryToken or 0) + 1
    if not missing then machine.packRetries = 0; return end
    machine.packKey, machine.packRetries = nil, (machine.packRetries or 0) + 1
    if machine.packRetries == 10 then print('[meta-comic] slot pack model still not loaded, retrying: ' .. missing) end
    local token = machine.packRetryToken
    SetTimeout(2000, function()
        if machines[machine.id] == machine and machine.packRetryToken == token and machine.entity == parent and DoesEntityExist(parent) then
            syncPacks(machine)
        end
    end)
end

local function spawn(machine)
    if machine.entity or machine.loading or missingModels[machine.hash] then return end
    machine.loading = true
    local hash = loadModel(machine.hash)
    machine.loading = false
    if not hash then
        missingModels[machine.hash] = true
        print(('[meta-comic] vending machine model %s is not streamed (is stream/metacomics_props.ytyp loaded?)'):format(machine.model))
        return
    end
    if machines[machine.id] ~= machine then return SetModelAsNoLongerNeeded(hash) end -- removed while loading
    local entity = CreateObjectNoOffset(hash, machine.coords.x, machine.coords.y, machine.coords.z, false, false, false)
    SetEntityHeading(entity, machine.heading)
    FreezeEntityPosition(entity, true)
    SetEntityInvincible(entity, true)
    SetModelAsNoLongerNeeded(hash)
    machine.entity = entity
    byEntity[entity] = machine
    machine.packKey, machine.packRetries = nil, 0 -- fresh prop: always rebuild the window, retries start over
    syncSkimmer(machine)
    syncSeal(machine)
    syncPadlock(machine)
    syncPacks(machine)
end

local function add(entry)
    local id = tonumber(entry.id)
    if not id then return end
    local coords, heading = vector3(entry.x + 0.0, entry.y + 0.0, entry.z + 0.0), (entry.h or 0.0) + 0.0
    local existing = machines[id]
    if existing and existing.model == entry.model and existing.coords == coords and existing.heading == heading then
        existing.products = entry.products or {} -- stock / price update: keep the spawned prop
        existing.displayStock = entry.displayStock
        if existing.entity then CreateThread(function() syncPacks(existing) end) end
        existing.systemTakenOver = entry.systemTakenOver == true
        existing.unlockedUntil = entry.unlockedUntil or 0
        existing.bolted = entry.bolted ~= false
        existing.serial, existing.lockRevision = entry.serial, entry.lockRevision
        if existing.padlock ~= (entry.padlock == true) then
            existing.padlock = entry.padlock == true
            if existing.entity then CreateThread(function() syncPadlock(existing) end) end
        end
        local wasSealed = existing.securitySeal ~= nil
        existing.lockCondition, existing.securitySeal = entry.lockCondition, entry.securitySeal
        if existing.entity and wasSealed ~= (existing.securitySeal ~= nil) then CreateThread(function() syncSeal(existing) end) end
        existing.gpsDisabled = entry.gpsDisabled == true
        if existing.skimmer ~= (entry.skimmer == true) then
            existing.skimmer = entry.skimmer == true
            syncSkimmer(existing)
        end
        return existing
    end
    if existing then despawn(existing) else count = count + 1 end
    machines[id] = {
        id = id,
        serial = entry.serial, lockRevision = entry.lockRevision,
        model = entry.model,
        hash = joaat(entry.model),
        coords = coords,
        heading = heading,
        products = entry.products or {},
        displayStock = entry.displayStock,
        systemTakenOver = entry.systemTakenOver == true,
        unlockedUntil = entry.unlockedUntil or 0,
        bolted = entry.bolted ~= false,
        padlock = entry.padlock == true,
        lockCondition = entry.lockCondition, securitySeal = entry.securitySeal,
        gpsDisabled = entry.gpsDisabled == true,
        skimmer = entry.skimmer == true,
    }
    return machines[id]
end

local function remove(id)
    local machine = machines[id]
    if not machine then return end
    despawn(machine)
    machines[id] = nil
    count = count - 1
end

-- controls: ids of the machines this player owns (or took over), as a set
local function setAccess(playerAccess)
    if type(playerAccess) ~= 'table' then return end
    local controls = {}
    for _, id in ipairs(playerAccess.controls or {}) do controls[tonumber(id)] = true end
    local fullHack = {}
    for _, id in ipairs(playerAccess.fullHack or {}) do fullHack[tonumber(id)] = true end
    local replaceBoard = {}
    for _, id in ipairs(playerAccess.replaceBoard or {}) do replaceBoard[tonumber(id)] = true end
    local skimmers = {}
    for _, id in ipairs(playerAccess.skimmers or {}) do skimmers[tonumber(id)] = true end
    local staffed = {}
    for _, id in ipairs(playerAccess.staffed or {}) do staffed[tonumber(id)] = true end
    local systemControls = {}
    for _, id in ipairs(playerAccess.systemControls or {}) do systemControls[tonumber(id)] = true end
    access = { manage = playerAccess.manage == true, restock = playerAccess.restock == true, controls = controls, fullHack = fullHack, replaceBoard = replaceBoard,
        skimmers = skimmers, police = playerAccess.police == true, staffed = staffed, systemControls = systemControls,
        placementBypass = playerAccess.placementBypass == true }
    SendNUIMessage({ type = 'metaComic:vendingRemoteAccessChanged' })
end

RegisterNetEvent('meta_comic:client:vendingMachines', function(list, playerAccess)
    local keep = {}
    for _, entry in ipairs(list or {}) do keep[tonumber(entry.id) or 0] = true end
    for id in pairs(machines) do if not keep[id] then remove(id) end end
    for _, entry in ipairs(list or {}) do add(entry) end
    setAccess(playerAccess)
end)

RegisterNetEvent('meta_comic:client:vendingAccess', setAccess)
-- a new job can add or take away the Restock option
RegisterNetEvent('QBCore:Client:OnJobUpdate', function() TriggerServerEvent('meta_comic:server:vendingAccess') end)
RegisterNetEvent('QBCore:Client:OnPlayerLoaded', function() TriggerServerEvent('meta_comic:server:vendingAccess') end)
RegisterNetEvent('ox:playerLoaded', function() TriggerServerEvent('meta_comic:server:vendingAccess') end) -- ox_core
RegisterNetEvent('ox:setGroup', function() TriggerServerEvent('meta_comic:server:vendingAccess') end)
RegisterNetEvent('ox:setActiveGroup', function() TriggerServerEvent('meta_comic:server:vendingAccess') end)

RegisterNetEvent('meta_comic:client:vendingMachineAdded', function(entry)
    local machine = add(entry)
    -- show a fresh placement right away instead of waiting for the next distance check
    if machine and #(GetEntityCoords(PlayerPedId()) - machine.coords) <= SPAWN then spawn(machine) end
end)

-- a purchase: the front pack of a random slot of that product slides forward and drops into the PUSH tray
RegisterNetEvent('meta_comic:client:vendingDrop', function(id, set, kind)
    local machine = machines[tonumber(id) or 0]
    if not machine or not machine.entity or not machine.packSlots then return end
    local choices = {}
    for _, product in ipairs(machine.products or {}) do
        if product.set == set and product.kind == kind and product.packFirst then
            for slot = product.packFirst, product.packLast do
                if machine.packSlots[slot] and #machine.packSlots[slot] > 0 then choices[#choices + 1] = slot end
            end
        end
    end
    if #choices == 0 then return end
    local info = machine.packSlots[choices[#choices]] -- same slot on every client (not random), so everyone sees the same pack drop
    local prop = table.remove(info, 1)
    if not prop or not DoesEntityExist(prop) then return end
    packOffsets[prop] = nil
    local front = info.front or SLOT_FRONT
    local start = GetGameTimer()
    while true do
        local t = (GetGameTimer() - start) / DROP_MS
        if t >= 1.0 or not DoesEntityExist(prop) or not machine.entity then break end
        local y, z, pitch
        if info.box then -- slide forward while turning thin side to the glass, then drop straight down
            local s = math.min(1.0, t / 0.4)
            packRotations[prop] = BOX_ROTATION + (BOX_DROP_ROTATION - BOX_ROTATION) * s
            local k = t < 0.4 and 0.0 or (t - 0.4) / 0.6
            y, z, pitch = front + (BOX_DROP_FRONT - front) * s, info.row + (DROP_Z - info.row) * k * k, 0.0
        elseif t < 0.4 then -- slide out of the slot
            y, z, pitch = front + (DROP_FRONT - front) * (t / 0.4), info.row, 0.0
        else -- tip over and fall to the tray, speeding up
            local k = (t - 0.4) / 0.6
            y, z, pitch = DROP_FRONT, info.row + (DROP_Z - info.row) * k * k, -80.0 * math.min(1.0, k * 1.6)
        end
        attachPack(machine, prop, vector3(info.column, y, z), pitch)
        Wait(0)
    end
    Wait(250)
    packRotations[prop] = nil
    if DoesEntityExist(prop) then DeleteEntity(prop) end
end)
-- client/vending_door.lua hides the machine prop while the door is open (children of a hidden prop hide too),
-- so the packs move onto the visible body and back
AddEventHandler('meta_comic:client:vendingPackParent', function(entity, parent)
    local machine = byEntity[entity]
    if not machine then return end
    machine.packParent = parent
    for _, prop in ipairs(machine.packProps or {}) do
        if DoesEntityExist(prop) and packOffsets[prop] then
            DetachEntity(prop, false, false) -- re-attaching while still attached is ignored
            attachPack(machine, prop, packOffsets[prop])
            SetEntityVisible(prop, true, false)
        end
    end
    -- e.g. door already open after a restart: the window may still be empty or retrying, rebuild it on the new parent
    if machine.entity and not (machine.packKey and machine.packProps) then CreateThread(function() syncPacks(machine) end) end
end)
RegisterNetEvent('meta_comic:client:vendingMachineRemoved', function(id) remove(tonumber(id)) end)

CreateThread(function()
    while not NetworkIsPlayerActive(PlayerId()) do Wait(500) end
    TriggerServerEvent('meta_comic:server:vendingMachines')
end)

CreateThread(function()
    while true do
        local sleep = MAX_SLEEP
        if count > 0 then
            local position = GetEntityCoords(PlayerPedId())
            local margin = math.huge -- metres until any machine has to change state
            local toSpawn = {}
            for _, machine in pairs(machines) do
                local distance = #(position - machine.coords)
                if machine.entity and distance > DESPAWN then despawn(machine) end
                if machine.entity then
                    margin = math.min(margin, DESPAWN - distance)
                elseif distance <= SPAWN then
                    toSpawn[#toSpawn + 1] = machine
                    margin = math.min(margin, DESPAWN - distance)
                else
                    margin = math.min(margin, distance - SPAWN)
                end
            end
            -- spawned after the loop: loading a model waits, and the list may change meanwhile
            for _, machine in ipairs(toSpawn) do spawn(machine) end
            sleep = math.floor(math.max(MIN_SLEEP, math.min(MAX_SLEEP, margin / SPEED * 1000)))
        end
        Wait(sleep)
    end
end)

-- Placement --------------------------------------------------------------------------------------------------------
local CONTROLS = {
    place = { 24, 191 },       -- left mouse, Enter
    cancel = { 25, 177, 200 }, -- right mouse, Backspace, Esc
    left = 44, right = 38,     -- Q / E (held)
    wheelUp = 241, wheelDown = 242,
    fine = 21,                 -- Shift
}
local BLOCKED = { 14, 15, 16, 17, 24, 25, 37, 38, 44, 45, 47, 58, 69, 70, 86, 92, 140, 141, 142, 143, 177, 191, 200, 241, 242, 257, 263, 264 }
local HELP = '~INPUT_ATTACK~ Place   ~INPUT_AIM~ Cancel~n~~INPUT_COVER~ ~INPUT_PICKUP~ or scroll: rotate   ~INPUT_SPRINT~ fine'

local function anyPressed(list)
    for _, control in ipairs(list) do if IsDisabledControlJustPressed(0, control) then return true end end
    return false
end

local function cameraRay(distance)
    local from = GetGameplayCamCoord()
    local rotation = GetGameplayCamRot(2)
    local pitch, yaw = math.rad(rotation.x), math.rad(rotation.z)
    local flat = math.abs(math.cos(pitch))
    local to = from + vector3(-math.sin(yaw) * flat, math.cos(yaw) * flat, math.sin(pitch)) * distance
    -- 1 world + 2 vehicles + 16 objects; the ghost has no collision so it is never hit
    local handle = StartExpensiveSynchronousShapeTestLosProbe(from.x, from.y, from.z, to.x, to.y, to.z, 19, PlayerPedId(), 4)
    local _, hit, coords, normal = GetShapeTestResult(handle)
    return hit == 1 or hit == true, coords, normal
end

local function placementClear(entity, hash, surface, normal)
    local policy = cfg.Placement or {}
    if policy.Enabled == false or access.placementBypass then return true end
    if type(MetaComic.VendingPlacementZone) ~= 'function' then
        return false, 'Placement checks are unavailable. Update shared/utils.lua and restart rush-tradingcards.'
    end
    local valid, reason = MetaComic.VendingPlacementZone(surface.x, surface.y, surface.z)
    if not valid then return false, reason end
    if normal and normal.z < (tonumber(policy.MinSurfaceNormalZ) or 0.85) then return false, 'Choose a flat ground surface.' end
    local minimum, maximum = GetModelDimensions(hash)
    local margin = tonumber(policy.RoadMargin) or 0.25
    local needsSidewalkSupport = false
    local function groundAt(x, y, z, above, below)
        local handle = StartExpensiveSynchronousShapeTestLosProbe(x, y, z + above, x, y, z - below, 1, entity, 4)
        local _, hit, coords, surfaceNormal = GetShapeTestResult(handle)
        if hit ~= true and hit ~= 1 then return nil end
        if not coords or not surfaceNormal or surfaceNormal.z < (tonumber(policy.MinSurfaceNormalZ) or 0.85) then return nil end
        return coords.z
    end
    local function blocksRoad(point)
        if not IsPointOnRoad(point.x, point.y, point.z, 0) then return false end
        -- The broad native road region can include pavement/plazas. Confirm that
        -- this footprint sample falls inside the estimated driving corridor.
        if policy.RoadCheckMode == 'native' or not GetClosestRoad then return true end
        local found, from, to, forward, backward, median = GetClosestRoad(point.x, point.y, point.z, 0.0, 1, false)
        if not found or not from or not to then return true end
        local lanes = (tonumber(forward) or 0) + (tonumber(backward) or 0)
        local dx, dy = to.x - from.x, to.y - from.y
        local lengthSquared = dx * dx + dy * dy
        if lanes <= 0 or lengthSquared < 0.01 then return true end
        local t = math.max(0, math.min(1, ((point.x - from.x) * dx + (point.y - from.y) * dy) / lengthSquared))
        local roadX, roadY, roadZ = from.x + t * dx, from.y + t * dy, from.z + t * (to.z - from.z)
        if math.abs(point.z - roadZ) > math.max(0, tonumber(policy.RoadHeightTolerance) or 2.5) then return false end
        -- GetClosestRoad's width output describes the median gap, not lane width.
        local halfWidth = (lanes * math.max(0.5, tonumber(policy.RoadLaneWidth) or 3.5)
            + math.max(0, tonumber(median) or 0)) * 0.5
        if (point.x - roadX) ^ 2 + (point.y - roadY) ^ 2 <= halfWidth ^ 2 then return true end
        -- Lane estimates alone must never clear a native road hit. Confirm a
        -- raised, level pavement surface at EVERY flagged footprint sample.
        local ground = groundAt(point.x, point.y, point.z, 0.5, 1.0)
        local roadGround = groundAt(roadX, roadY, roadZ, 2.5, 2.5)
        if not ground or not roadGround then return true end
        local minimumRise = math.max(0.01, tonumber(policy.RoadSidewalkMinRise) or 0.08)
        local tolerance = math.max(0.01, tonumber(policy.SurfaceHeightTolerance) or 0.08)
        if ground - roadGround < minimumRise or math.abs(point.z - ground) > tolerance then return true end
        needsSidewalkSupport = true
        return false
    end
    if policy.BlockRoads ~= false then
        for _, x in ipairs({ minimum.x - margin, 0, maximum.x + margin }) do
            for _, y in ipairs({ minimum.y - margin, 0, maximum.y + margin }) do
                local point = GetOffsetFromEntityInWorldCoords(entity, x, y, minimum.z)
                if blocksRoad(point) then return false, 'The machine would obstruct a road.' end
            end
        end
    end
    local function obstructed(x1, y1, x2, y2, height)
        local from = GetOffsetFromEntityInWorldCoords(entity, x1, y1, minimum.z + height)
        local to = GetOffsetFromEntityInWorldCoords(entity, x2, y2, minimum.z + height)
        local handle = StartExpensiveSynchronousShapeTestLosProbe(from.x, from.y, from.z, to.x, to.y, to.z, 19, entity, 4)
        local _, hit = GetShapeTestResult(handle)
        return hit == true or hit == 1
    end
    local negative = policy.FrontIsNegativeY ~= false
    local front, back = negative and minimum.y or maximum.y, negative and maximum.y or minimum.y
    local sign = negative and -1 or 1
    local clearance = math.max(0, tonumber(policy.FrontClearance) or 1.5)
    local sides = math.max(0, tonumber(policy.SideClearance) or 0.15)
    for _, height in ipairs({ 0.3, 1.0, math.min(1.6, maximum.z - minimum.z - 0.1) }) do
        for _, x in ipairs({ minimum.x + 0.05, (minimum.x + maximum.x) * 0.5, maximum.x - 0.05 }) do
            -- Keep the supporting rear wall out of the passage probe. Check the
            -- cabinet interior separately, with a small contact tolerance at its edges.
            if obstructed(x, back + sign * 0.05, x, front - sign * 0.05, height) then
                return false, 'The cabinet would overlap an obstruction.'
            end
            if clearance > 0 and obstructed(x, front + sign * 0.05, x, front + sign * clearance, height) then
                return false, 'Leave a clear passage in front of the machine.'
            end
        end
        for _, y in ipairs({ minimum.y + 0.05, (minimum.y + maximum.y) * 0.5, maximum.y - 0.05 }) do
            if obstructed(minimum.x - sides, y, maximum.x + sides, y, height) then return false, 'The cabinet would overlap an obstruction.' end
        end
    end
    if policy.RequireRearWall ~= false or needsSidewalkSupport then
        local distance = math.max(0, tonumber(policy.RearWallDistance) or 0.8)
        local supported = false
        local centerX = (minimum.x + maximum.x) * 0.5
        for _, height in ipairs(policy.RearWallProbeHeights or { 0.3, 0.6, 1.0 }) do
            height = tonumber(height)
            if height and height > 0 and height < maximum.z - minimum.z then
                -- Support must span the back at the same height, not just touch
                -- one centre ray (which could be a pole or roadside sign).
                local inset = (maximum.x - minimum.x) * 0.1
                local spansBack = true
                for _, x in ipairs({ minimum.x + inset, centerX, maximum.x - inset }) do
                    if not obstructed(x, back + sign * 0.05, x, back - sign * distance, height) then
                        spansBack = false
                        break
                    end
                end
                if spansBack then supported = true; break end
            end
        end
        if not supported then return false, 'Place the full back against a wall or low barrier; poles and signs do not count.' end
    end
    return true
end

local function outline(entity, valid)
    if not SetEntityDrawOutline then return end
    if valid ~= nil and SetEntityDrawOutlineColor then
        if valid then SetEntityDrawOutlineColor(80, 220, 120, 255) else SetEntityDrawOutlineColor(235, 70, 70, 255) end
    end
    SetEntityDrawOutline(entity, valid ~= nil)
end

local function clearGhost()
    if ghost and DoesEntityExist(ghost) then outline(ghost, nil); DeleteEntity(ghost) end
    ghost = nil
end

-- shows the see-through preview until the player places it (returns vector4) or cancels (returns nil).
-- startHeading: initial rotation, otherwise facing the camera
local function placeGhost(modelName, startHeading)
    local hash = loadModel(joaat(modelName))
    if not hash then return notify(('Model %s is not streamed. Check stream/metacomics_props.ytyp.'):format(modelName), 'error') end

    local minimum = GetModelDimensions(hash)
    local lift = -minimum.z -- puts the model's base on the surface wherever its origin is
    local reach = tonumber(cfg.PlaceDistance) or 15.0
    local heading = startHeading or (GetGameplayCamRot(2).z + 180.0) % 360.0 -- start facing the camera
    local start = GetEntityCoords(PlayerPedId())
    ghost = CreateObjectNoOffset(hash, start.x, start.y, start.z - 50.0, false, false, false)
    SetModelAsNoLongerNeeded(hash)
    SetEntityAlpha(ghost, tonumber(cfg.GhostAlpha) or 150, false)
    SetEntityCollision(ghost, false, false)
    FreezeEntityPosition(ghost, true)
    SetEntityInvincible(ghost, true)

    local placed
    local nextCheck, placementValid, placementReason = 0, false, nil
    while ghost do
        local playerId, ped = PlayerId(), PlayerPedId()
        DisablePlayerFiring(playerId, true)
        for _, control in ipairs(BLOCKED) do DisableControlAction(0, control, true) end

        local hit, coords, normal = cameraRay(reach + 10.0)
        local valid = hit and #(GetEntityCoords(ped) - coords) <= reach
        SetEntityVisible(ghost, hit, false)
        if hit then
            SetEntityCoordsNoOffset(ghost, coords.x, coords.y, coords.z + lift, false, false, false)
            SetEntityHeading(ghost, heading)
        end

        local fine = IsControlPressed(0, CONTROLS.fine) or IsDisabledControlPressed(0, CONTROLS.fine)
        local step = fine and 1.0 or 15.0
        local speed = (fine and 20.0 or 90.0) * GetFrameTime()
        if IsDisabledControlJustPressed(0, CONTROLS.wheelUp) then heading = heading + step end
        if IsDisabledControlJustPressed(0, CONTROLS.wheelDown) then heading = heading - step end
        if IsDisabledControlPressed(0, CONTROLS.left) then heading = heading + speed end
        if IsDisabledControlPressed(0, CONTROLS.right) then heading = heading - speed end
        heading = heading % 360.0
        if hit then
            SetEntityHeading(ghost, heading)
            if GetGameTimer() >= nextCheck then
                placementValid, placementReason = placementClear(ghost, hash, coords, normal)
                nextCheck = GetGameTimer() + math.max(100, tonumber((cfg.Placement or {}).CheckInterval) or 250)
            end
            valid = valid and placementValid
            outline(ghost, valid)
        end

        BeginTextCommandDisplayHelp('STRING')
        AddTextComponentSubstringPlayerName(HELP .. ('~n~Heading: %d deg'):format(math.floor(heading + 0.5) % 360)
            .. (placementReason and ('~n~' .. placementReason) or ''))
        EndTextCommandDisplayHelp(0, false, false, -1)

        if anyPressed(CONTROLS.cancel) then
            break
        elseif anyPressed(CONTROLS.place) then
            if hit and #(GetEntityCoords(ped) - coords) <= reach then valid, placementReason = placementClear(ghost, hash, coords, normal) end
            if valid then
                placed = vector4(coords.x, coords.y, coords.z + lift, heading)
                break
            end
            notify(placementReason or (hit and 'Too far away: move closer.' or 'Look at the ground where it should stand.'), 'error')
        end
        Wait(0)
    end
    clearGhost()
    return placed
end

RegisterNetEvent('meta_comic:client:placeVendingMachine', function()
    if ghost then return notify('You are already placing a vending machine.', 'error') end
    local placed = placeGhost(cfg.Model or 'metacomics_vending_machine')
    if placed then
        TriggerServerEvent('meta_comic:server:placeVendingMachine', placed.x, placed.y, placed.z, placed.w)
    else
        notify('Vending machine placement cancelled.', 'info')
    end
end)

-- Manage > Move machine: the current prop is hidden while the preview is out, and comes back if cancelled
local function moveMachine(id)
    local machine = machines[id]
    if not machine then return notify('That vending machine no longer exists.', 'error') end
    if ghost then return notify('You are already placing a vending machine.', 'error') end
    local entity = machine.entity
    if entity and DoesEntityExist(entity) then
        SetEntityVisible(entity, false, false)
        SetEntityCollision(entity, false, false) -- or the aim ray would hit the old machine
    end
    local placed = placeGhost(machine.model, machine.heading)
    if entity and DoesEntityExist(entity) then
        SetEntityVisible(entity, true, false)
        SetEntityCollision(entity, true, true)
    end
    if placed then
        TriggerServerEvent('meta_comic:server:moveVendingMachine', id, placed.x, placed.y, placed.z, placed.w)
    else
        notify('Move cancelled.', 'info')
    end
end

RegisterNetEvent('meta_comic:client:removeVendingMachine', function()
    local position = GetEntityCoords(PlayerPedId())
    local nearest, best = nil, tonumber(cfg.RemoveDistance) or 5.0
    for id, machine in pairs(machines) do
        local distance = #(position - machine.coords)
        if distance <= best then nearest, best = id, distance end
    end
    if not nearest then return notify('No vending machine close enough to remove.', 'error') end
    TriggerServerEvent('meta_comic:server:removeVendingMachine', nearest)
end)


-- ox_target + ox_lib menus ------------------------------------------------------------------------------------------
-- Buy: everyone. Restock: managers and employees (Config.VendingMachines.Restock.Jobs). Manage: managers.
-- The server checks permission, distance, price and stock on every action.
local shop = cfg.Shop or {}
local MAX_STOCK = math.max(1, math.floor(tonumber((cfg.Restock or {}).MaxStock) or 100))

local function machineOf(entity)
    return entity and byEntity[entity] or nil
end
local function controls(machine) return machine ~= nil and access.controls[machine.id] == true end
-- for client/vending_crime.lua
MetaComic.VendingMachineOf = machineOf
MetaComic.VendingMachineById = function(id) return machines[tonumber(id)] end
MetaComic.VendingNearestMachine = function(radius)
    local nearest, distance = nil, tonumber(radius) or 3.0
    local here = GetEntityCoords(PlayerPedId())
    for _, machine in pairs(machines) do
        if machine.entity and DoesEntityExist(machine.entity) then
            local gap = #(GetEntityCoords(machine.entity) - here)
            if gap <= distance then nearest, distance = machine, gap end
        end
    end
    return nearest
end
MetaComic.VendingControls = function(id) return access.controls[tonumber(id)] == true end
MetaComic.VendingCanSecure = function(id)
    id = tonumber(id)
    local permission = (cfg.Keys or {}).Enabled == true and (cfg.Keys or {}).SecureAccess or ((cfg.Crime or {}).Secure or {}).Access or 'anyone'
    local controller = access.manage or access.controls[id] or access.staffed and access.staffed[id]
    return permission == 'anyone' or permission == 'police' and access.police or permission == 'controllers' and controller
        or permission == 'police_or_controllers' and (access.police or controller)
end
MetaComic.VendingCanOperateSystem = function(id) return access.systemControls ~= nil and access.systemControls[tonumber(id)] == true end
MetaComic.VendingMySkimmer = function(id) return access.skimmers ~= nil and access.skimmers[tonumber(id)] == true end
-- may check the coin panel for a skimmer: controls the machine, manages them, police, or an employee at a business machine
MetaComic.VendingCanInspectPanel = function(id)
    id = tonumber(id)
    return access.manage == true or access.police == true or access.controls[id] == true or (access.staffed ~= nil and access.staffed[id] == true)
        or MetaComic.VendingHasKeyAccess and MetaComic.VendingHasKeyAccess(id)
end
MetaComic.VendingCanFullHack = function(id) return access.fullHack and access.fullHack[tonumber(id)] == true end
MetaComic.VendingCanReplaceBoard = function(id) return access.replaceBoard and access.replaceBoard[tonumber(id)] == true end
local function kindLabel(kind) return kind == 'box' and 'Booster Box' or 'Booster Pack' end
local function productTitle(product) return ('%s %s'):format(product.setName or product.set, kindLabel(product.kind)) end
local function money(n) return ('$%d'):format(math.floor(tonumber(n) or 0)) end
-- the set's logo as the option icon (URLs) and as the picture beside the menu
local function productIcon(product, fallback)
    local logo = product.logo
    if type(logo) == 'string' and (logo:match('^https?://') or logo:match('^nui://')) then return logo end
    return fallback
end
local function productImage(product) return type(product.logo) == 'string' and product.logo ~= '' and product.logo or nil end
local workspace
local openWorkspace
local requestWorkspace
local function workBusy()
    return (MetaComic.VendingActionBusy and MetaComic.VendingActionBusy())
        or (MetaComic.VendingKeyWorkBusy and MetaComic.VendingKeyWorkBusy()) or ghost~=nil
end
local function menu(id, title, options, parent, registerOnly)
    local managed=workspace and id~='meta_comic_vending_buy'
    if managed then
        for _,option in ipairs(options) do
            local action=option.onSelect
            if action then option.onSelect=function(...)
                local session=workspace
                session.actionRunning=true
                session.response=nil
                local waiting=action(...)~=false
                if workspace~=session then return end
                CreateThread(function()
                    while workspace==session and workBusy() do Wait(100) end
                    if workspace~=session then return end
                    session.actionRunning=nil
                    -- A server reply may have arrived while the local animation was finishing.
                    -- Register it immediately, but reveal it only once the action is over.
                    if session.response and not session.refreshNeeded then
                        local response=session.response
                        session.response=nil
                        exports.ox_lib:showContext(response)
                    elseif not option.waitForResponse or not waiting or session.refreshNeeded then
                        session.response=nil
                        session.refreshNeeded=nil
                        requestWorkspace(session)
                    end
                end)
            end end
        end
    end
    exports.ox_lib:registerContext({id=id,title=title,menu=parent,options=options,
        onExit=managed and function() workspace=nil;MetaComic.VendingMenuActive=nil end or nil,
        onBack=managed and function() if workspace then workspace.view=parent;if parent=='meta_comic_vending_manage_root' then openWorkspace(workspace.id) end end end or nil})
    if not registerOnly then
        if managed then
            workspace.view=id
            workspace.awaiting=nil
            if workspace.actionRunning then workspace.response=id;return end
        end
        local visible=lib and lib.getOpenContextMenu and lib.getOpenContextMenu()
        if visible~=id then exports.ox_lib:showContext(id) end
    end
end
MetaComic.VendingContextMenu=menu
openWorkspace=function(id)
    id=tonumber(id)
    if not id or GetResourceState('ox_lib')~='started' then return end
    if not workspace or workspace.id~=id then
        workspace={id=id};MetaComic.VendingMenuActive=id
        local session=workspace
        CreateThread(function()
            while workspace==session do
                local machine=MetaComic.VendingMachineById and MetaComic.VendingMachineById(id)
                if not machine or not machine.entity or not DoesEntityExist(machine.entity)
                    or #(GetEntityCoords(PlayerPedId())-GetEntityCoords(machine.entity))>4.0 then
                    workspace=nil;MetaComic.VendingMenuActive=nil;exports.ox_lib:hideContext(false);return
                end
                Wait(500)
            end
        end)
    end
    local options={
        {title='Cabinet lock / keys',icon='key',arrow=true,waitForResponse=true,disabled=(cfg.Keys or {}).Enabled~=true,
            onSelect=function() TriggerServerEvent('meta_comic:server:vendingKeyMenu',id) end},
        {title='Restock',icon='truck-ramp-box',arrow=true,waitForResponse=true,onSelect=function() TriggerServerEvent('meta_comic:server:vendingOpen',id,'restock') end},
        {title='Machine management',waitForResponse=true,description='Products, prices, cash, ownership and operating controls',icon='gears',arrow=true,
            onSelect=function() TriggerServerEvent('meta_comic:server:vendingManage',id) end},
    }
    if MetaComic.VendingIsAjar and MetaComic.VendingIsAjar(id) then
        options[#options+1]={title='Open ajar doors fully',icon='door-open',waitForResponse=true,onSelect=function() TriggerServerEvent('meta_comic:server:vendingOpenAjar',id) end}
    end
    menu('meta_comic_vending_manage_root',('Manage Vending Machine #%d'):format(id),options)
end
MetaComic.OpenVendingManage=openWorkspace
requestWorkspace=function(session)
    if workspace~=session or session.awaiting then return end
    session.awaiting=true
    if session.view=='meta_comic_vending_keys' then TriggerServerEvent('meta_comic:server:vendingKeyMenu',session.id)
    elseif session.view=='meta_comic_vending_restock' then TriggerServerEvent('meta_comic:server:vendingOpen',session.id,'restock')
    elseif session.view=='meta_comic_vending_manage_root' then
        session.awaiting=nil
        openWorkspace(session.id)
    else TriggerServerEvent('meta_comic:server:vendingManage',session.id) end
end
RegisterNetEvent('meta_comic:client:vendingMenuRefresh',function(id)
    if not workspace or workspace.id~=id then return end
    if workspace.actionRunning then workspace.refreshNeeded=true;return end
    requestWorkspace(workspace)
end)
local function input(title, rows)
    return exports.ox_lib:inputDialog(title, rows)
end
local function needsOxLib()
    if GetResourceState('ox_lib') == 'started' then return true end
    notify('Vending machine menus need ox_lib.', 'error')
    return false
end

-- methods = { cash = true, card = true }: with both, picking a product asks how to pay
local function openBuy(machine, methods)
    if not needsOxLib() then return end
    methods = type(methods) == 'table' and methods or { card = true }
    local options = {}
    for _, product in ipairs(machine.products) do
        local soldOut = (product.stock or 0) < 1
        local function buy(method) TriggerServerEvent('meta_comic:server:vendingBuy', machine.id, product.set, product.kind, method) end
        options[#options + 1] = {
            title = productTitle(product),
            description = soldOut and 'Sold out' or ('%s | %d left'):format(money(product.price), product.stock),
            icon = productIcon(product, product.kind == 'box' and 'boxes-stacked' or 'box-open'),
            image = productImage(product),
            disabled = soldOut or MetaComic.VendingDoorOpen and MetaComic.VendingDoorOpen(machine.id),
            arrow = methods.cash and methods.card,
            onSelect = function()
                if not (methods.cash and methods.card) then return buy(methods.cash and 'cash' or 'card') end
                menu('meta_comic_vending_pay', ('%s | %s'):format(productTitle(product), money(product.price)), {
                    { title = 'Pay with card', description = 'Charged to your bank account', icon = 'credit-card', onSelect = function() buy('card') end },
                    { title = 'Pay with cash', description = 'Cash goes into the machine', icon = 'money-bill-wave', onSelect = function() buy('cash') end },
                }, 'meta_comic_vending_buy')
            end,
        }
    end
    if #options == 0 then options[1] = { title = 'Nothing for sale', disabled = true } end
    menu('meta_comic_vending_buy', 'Vending Machine', options)
end

local function openRestock(machine, maxStock)
    if not needsOxLib() then return end
    local MAX_STOCK = maxStock or MAX_STOCK
    local options = {}
    for _, product in ipairs(machine.products) do
        local MAX_STOCK = tonumber(product.maxStock) or MAX_STOCK
        options[#options + 1] = {
            title = productTitle(product),
            description = ('Stock %d / %d'):format(product.stock or 0, MAX_STOCK),
            icon = productIcon(product, 'truck-ramp-box'),
            image = productImage(product),
            disabled = (product.stock or 0) >= MAX_STOCK,
            waitForResponse = true,
            onSelect = function()
                local room = MAX_STOCK - (product.stock or 0)
                local result = input(('Restock %s'):format(productTitle(product)), {
                    { type = 'number', label = 'Amount (taken from your inventory)', description = ('You need that many %s in your inventory.'):format(productTitle(product)), default = 1, min = 1, max = room, required = true },
                })
                if result and tonumber(result[1]) then
                    TriggerServerEvent('meta_comic:server:vendingRestock', machine.id, product.set, product.kind, tonumber(result[1]))
                    return true
                end
                return false -- Dismissed the amount dialog: no server action is pending.
            end,
        }
    end
    if #options == 0 then options[1] = { title = 'This machine sells nothing yet', disabled = true } end
    menu('meta_comic_vending_restock', 'Restock Vending Machine', options,workspace and 'meta_comic_vending_manage_root')
end

-- the server answers Buy / Restock with this machine's current products, so the menus never show a stale copy
RegisterNetEvent('meta_comic:client:vendingOpen', function(id, mode, products, maxStock, methods)
    local machine = { id = id, products = products or {} }
    if machines[id] then machines[id].products = machine.products; CreateThread(function() syncPacks(machines[id]) end) end
    if mode == 'restock' then openRestock(machine, tonumber(maxStock)) else openBuy(machine, methods) end
end)

local function sendProduct(id, action, data) TriggerServerEvent('meta_comic:server:vendingProduct', id, action, data) end

-- the server sends this after "Manage" and after every change, so the menu always shows saved values
local function ownerAction(id, action, data) TriggerServerEvent('meta_comic:server:vendingOwner', id, action, data) end
local function confirm(header, content)
    return exports.ox_lib:alertDialog({ header = header, content = content, cancel = true }) == 'confirm'
end
-- ownership part of Manage: serial, owner, where card payments go, the cash box
local function ownerOptions(id, info)
    local options = {}
    if type(info) ~= 'table' or not info.serial then return options end
    if not info.systemRackClosed and (((cfg.Crime or {}).FalsifyLogs or {}).Enabled ~= false) and (cfg.Crime or {}).Enabled ~= false then
        options[#options + 1] = { title = 'Falsify sensor log identities', icon = 'laptop-code', disabled = info.falsifyMissing ~= nil,
            description = info.falsifyMissing and ('Requires ' .. info.falsifyMissing) or nil,
            onSelect = function()
                local result = exports.ox_lib:inputDialog('Falsify sensor records', {
                    { type = 'input', label = 'Registered employee name or identifier', required = true },
                })
                if result then TriggerServerEvent('meta_comic:server:crimeStart', id, 'falsifylogs', { employee = result[1] }) end
            end }
    end
    options[#options + 1] = { title = 'Reconcile recorded cash and stock', icon = 'arrows-rotate', disabled = not info.canResync,
        description = 'Authorized OS access and an open server rack required',
        onSelect = function() ownerAction(id, 'resync') end }
    options[#options + 1] = {
        title = ('Serial %s'):format(info.serial),
        description = ('Owner: %s%s'):format(info.ownerName or '?', info.owner ~= 'business' and (' | tax %s%%'):format(info.tax or 0) or ''),
        icon = 'id-card', readOnly = true,
    }
    options[#options + 1] = {
        title = info.tampered and 'Card payments: REROUTED' or ('Card payments: %s'):format(info.routingName or '?'),
        description = info.tampered and ('Going to account %s, not the owner\'s (%s)'):format(info.routing or '?', info.ownerRouting or '?') or ('Routing number %s'):format(info.routing or '?'),
        icon = info.tampered and 'triangle-exclamation' or 'building-columns', iconColor = info.tampered and '#e5484d' or nil,
        disabled = info.systemTakenOver or info.systemRackClosed or not (info.tampered and (info.manager or info.isOwner)),
        onSelect = function()
            if confirm('Reset routing', 'Send this machine\'s card payments to its owner again?') then ownerAction(id, 'resetRouting') end
        end,
    }
    if info.sales then
        -- every sale with what was actually paid out: a card payment that pays out less than price minus tax is a clue
        options[#options + 1] = {
            title = ('Sales records (%d)'):format(#info.sales), description = 'Recent sales, the tax taken and what was paid out',
            icon = 'receipt', arrow = true, disabled = #info.sales == 0,
            onSelect = function()
                local rows = {}
                for _, sale in ipairs(info.sales) do
                    local when = sale.when or ''
                    rows[#rows + 1] = sale.method == 'card' and {
                        title = ('Card %s'):format(money(sale.price)), icon = 'credit-card', readOnly = true,
                        description = ('%s - tax %s - paid out %s'):format(when, money(sale.tax), money(sale.paid)),
                    } or {
                        title = ('Cash %s'):format(money(sale.price)), icon = 'money-bill', readOnly = true,
                        description = ('%s - kept in the cash box'):format(when),
                    }
                end
                menu('meta_comic_vending_sales', ('Sales records %s'):format(info.serial), rows, 'meta_comic_vending_manage')
            end,
        }
    end
    options[#options + 1] = {
        title = ('Collect cash (%s)'):format(money(info.cash)), description = info.canCollect == false and 'Open the cabinet and cash box with full access first.' or 'Cash payments are kept in the machine until collected',
        icon = 'sack-dollar', disabled = info.canCollect == false or (info.cash or 0) <= 0 or info.keysEnabled and not info.fullAccess, onSelect = function() ownerAction(id, 'collect') end,
    }
    if info.canSetPayments then
        options[#options + 1] = {
            title = 'Change card payment recipient', icon = 'building-columns',
            description = info.systemRackClosed and 'Open the machine and its server rack first' or 'Choose an online player or a registered routing number',
            disabled = info.systemRackClosed == true,
            onSelect = function()
                local result = input('Card payment recipient', {
                    { type = 'select', label = 'Recipient type', required = true, options = {
                        { value = 'player', label = 'Online player ID' }, { value = 'routing', label = 'Registered routing number' },
                    } },
                    { type = 'input', label = 'Player ID or routing number', required = true },
                })
                if result and result[1] and result[2] then ownerAction(id, 'payments', { mode = result[1], value = result[2] }) end
            end,
        }
    end
    if info.canSwitchGPS then
        options[#options + 1] = {
            title = info.gpsDisabled and 'Enable machine GPS' or 'Disable machine GPS', icon = 'satellite',
            description = info.gpsRackClosed and 'Open the machine and its server rack first'
                or info.gpsDisabled and 'Register this spot as the home location' or 'Switch off movement tracking',
            disabled = info.gpsRackClosed == true,
            onSelect = function() ownerAction(id, 'gps') end,
        }
    end
    if info.systemTakenOver then
        options[#options + 1] = { title = 'Operating system compromised', icon = 'user-secret', readOnly = true }
    end
    if info.canManageOSAccess then
        options[#options + 1] = { title = 'Manage OS operating access', icon = 'users', description = 'Grant or revoke remote map, new records and operating controls.',
            onSelect = function()
                local result = input('OS operating access', {
                    { type = 'number', label = 'Online player server ID', min = 1, required = true },
                    { type = 'select', label = 'Access', required = true, options = { { value = 'grant', label = 'Grant' }, { value = 'revoke', label = 'Revoke' } } },
                })
                if result then TriggerServerEvent('meta_comic:server:vendingOSAccess', info.serial, result[1], result[2] == 'grant') end
            end }
    end
    if info.canReplaceBoard and (cfg.Crime or {}).ReplaceBoard and cfg.Crime.ReplaceBoard.Enabled ~= false then
        options[#options + 1] = {
            title = 'Replace machine control board', icon = 'microchip',
            disabled = info.boardMissing ~= nil or info.systemRackClosed == true,
            description = info.boardMissing and ('Requires ' .. info.boardMissing) or info.systemRackClosed and 'Open the machine and server rack first.' or 'Restores the owner system and payment routing.',
            onSelect = function() TriggerServerEvent('meta_comic:server:crimeStart', id, 'replaceboard') end,
        }
    end
    if info.manager then
        local people = { { value = 'business', label = info.business or 'The business' } }
        for _, person in ipairs(info.people or {}) do people[#people + 1] = { value = person.id, label = ('%s (tax %s%%)'):format(person.name, person.tax or 0) } end
        options[#options + 1] = {
            title = 'Assign owner', icon = 'user-tag',
            description = info.systemRackClosed and 'Open the machine and its server rack first' or 'Registered owners only (admin UI: Machine records)',
            disabled = info.keysEnabled and not info.fullAccess or info.systemRackClosed == true,
            onSelect = function()
                local result = input('Assign owner', {
                    { type = 'select', label = 'Owner', options = people, default = info.owner, required = true },
                    { type = 'checkbox', label = 'Print a registration certificate', checked = true },
                })
                if result and result[1] then ownerAction(id, 'assign', { owner = result[1], certificate = result[2] == true }) end
            end,
        }
    end
    options[#options + 1] = {
        title = 'Print registration certificate', description = 'A record item showing who owns this machine', icon = 'file-signature',
        disabled = info.keysEnabled and not info.fullAccess, onSelect = function() ownerAction(id, 'certificate') end,
    }
    options[#options + 1] = {
        title = 'Pick up machine', description = 'Becomes an item again (keeps its serial, stock and cash)', icon = 'dolly',
        disabled = info.keysEnabled and not info.fullAccess,
        onSelect = function()
            if confirm('Pick up', ('Pick up vending machine %s?'):format(info.serial)) then ownerAction(id, 'pickup') end
        end,
    }
    return options
end

RegisterNetEvent('meta_comic:client:vendingManage', function(id, products, sets, maxStock, info)
    if not needsOxLib() then return end
    maxStock = tonumber(maxStock) or MAX_STOCK
    local options = ownerOptions(id, info)
    local fullAccess = not (info and info.keysEnabled) or info.fullAccess == true
    if info and info.keysEnabled then
        options[#options + 1] = { title = 'Lock cabinet', description = 'Closes all key access sessions', icon = 'lock', onSelect = function()
            if MetaComic.VendingUseKeyAtLock then MetaComic.VendingUseKeyAtLock(id, 'cylinder', 'lock') end
        end }
    end
    local inspect = ((cfg.Crime or {}).InspectPanel or {})
    if info and info.canInspectPanel and inspect.Enabled ~= false and (cfg.Crime or {}).Enabled ~= false then
        options[#options + 1] = { title = inspect.Label or 'Check coin panel for tampering', icon = 'magnifying-glass',
            onSelect = function() TriggerServerEvent('meta_comic:server:crimeStart', id, 'inspectpanel') end }
    end
    for _, product in ipairs(products or {}) do
        local key = { set = product.set, kind = product.kind }
        local subId = ('meta_comic_vending_product_%s_%s'):format(product.set, product.kind)
        options[#options + 1] = {
            title = productTitle(product),
            description = ('%s | stock %d / %d'):format(money(product.price), product.stock or 0, tonumber(product.maxStock) or maxStock),
            icon = productIcon(product, product.kind == 'box' and 'boxes-stacked' or 'box-open'),
            image = productImage(product),
            arrow = true,
            onSelect = function()
                menu(subId, productTitle(product), {
                    { title = 'Change price', description = money(product.price), icon = 'tag', onSelect = function()
                        local result = input('Price', { { type = 'number', label = 'Price ($)', default = product.price, min = 0, required = true } })
                        if result and tonumber(result[1]) then sendProduct(id, 'price', { set = key.set, kind = key.kind, price = tonumber(result[1]) }) end
                    end },
                    { title = 'Take out stock', description = 'Move sealed packs / boxes into your inventory', icon = 'box-open', disabled = not fullAccess or (product.stock or 0) < 1, onSelect = function()
                        local result = input('Take out stock', { { type = 'number', label = 'Amount to take', default = 1, min = 1, max = product.stock or 0, required = true } })
                        if result and tonumber(result[1]) then sendProduct(id, 'withdraw', { set = key.set, kind = key.kind, amount = tonumber(result[1]) }) end
                    end },
                    { title = 'Lower stock', description = ('%d / %d; removed stock is returned to you'):format(product.stock or 0, tonumber(product.maxStock) or maxStock), icon = 'warehouse', disabled = not fullAccess or (product.stock or 0) < 1, onSelect = function()
                        local result = input('Lower stock', { { type = 'number', label = 'Stock', default = product.stock or 0, min = 0, max = product.stock or 0, required = true } })
                        if result and tonumber(result[1]) then sendProduct(id, 'stock', { set = key.set, kind = key.kind, stock = tonumber(result[1]) }) end
                    end },
                    { title = 'Remove from machine', icon = 'trash', disabled = not fullAccess, onSelect = function()
                        local confirm = exports.ox_lib:alertDialog({ header = 'Remove product', content = ('Stop selling %s here? Remaining stock returns to your inventory.'):format(productTitle(product)), cancel = true })
                        if confirm == 'confirm' then sendProduct(id, 'remove', key) end
                    end },
                }, 'meta_comic_vending_manage')
            end,
        }
    end
    local setOptions = {}
    for _, set in ipairs(sets or {}) do setOptions[#setOptions + 1] = { value = set.id, label = set.name } end
    options[#options + 1] = {
        title = 'Move machine',
        disabled = not fullAccess,
        description = 'Pick it up and place it somewhere else nearby',
        icon = 'up-down-left-right',
        onSelect = function() CreateThread(function() moveMachine(id) end) end,
    }
    options[#options + 1] = {
        title = 'Add product',
        description = 'Sell booster packs and/or boxes of a set here (stock them with Restock)',
        icon = 'plus',
        disabled = not fullAccess or #setOptions == 0,
        onSelect = function()
            local result = input('Add product', {
                { type = 'select', label = 'Card set', options = setOptions, required = true },
                { type = 'multi-select', label = 'Sell', options = { { value = 'pack', label = 'Booster Packs' }, { value = 'box', label = 'Booster Boxes' } }, default = { 'pack' }, required = true },
                { type = 'number', label = 'Pack price ($)', default = 250, min = 0 },
                { type = 'number', label = 'Box price ($)', default = 2500, min = 0 },
            })
            if not result or not result[1] then return end
            for _, kind in ipairs(type(result[2]) == 'table' and result[2] or { result[2] }) do
                sendProduct(id, 'add', {
                    set = result[1], kind = kind,
                    price = tonumber(kind == 'box' and result[4] or result[3]) or 0,
                })
            end
        end,
    }
    if info and info.busy then
        for _, option in ipairs(options) do
            if option.onSelect then option.disabled, option.description = true, 'The machine is busy. Wait for the current action to finish.' end
        end
    end
    if not workspace or workspace.id~=id then openWorkspace(id) end
    local show=workspace and (workspace.view=='meta_comic_vending_manage' or workspace.view=='meta_comic_vending_manage_root' or tostring(workspace.view):find('meta_comic_vending_product_',1,true))
    menu('meta_comic_vending_manage', 'Machine management', options,'meta_comic_vending_manage_root',not show)
end)

CreateThread(function()
    local timeout = GetGameTimer() + 30000
    while GetResourceState('ox_target') ~= 'started' do
        if GetGameTimer() > timeout or GetResourceState('ox_target') == 'missing' then return end
        Wait(500)
    end
    local distance = tonumber(shop.TargetDistance) or 2.0
    exports.ox_target:addModel(cfg.Model or 'metacomics_vending_machine', {
        {
            name = 'meta_comic_vending_inspect_serial', label = 'Inspect machine serial number', icon = 'fas fa-barcode', distance = distance,
            canInteract = function(entity) return access.police == true and machineOf(entity) ~= nil end,
            onSelect = function(data)
                local machine = machineOf(data.entity)
                if machine then TriggerServerEvent('meta_comic:server:vendingInspectSerial', machine.id) end
            end,
        },
        {
            name = 'meta_comic_vending_buy', label = 'Buy', icon = 'fas fa-cart-shopping', distance = distance,
            canInteract = function(entity)
                local machine = machineOf(entity)
                return shop.Enabled ~= false and machine ~= nil
                    and not (MetaComic.VendingDoorOpen and MetaComic.VendingDoorOpen(machine.id))
            end,
            onSelect = function(data)
                local machine = machineOf(data.entity)
                if machine then TriggerServerEvent('meta_comic:server:vendingOpen', machine.id, 'buy') end
            end,
        },
        {name='meta_comic_vending_ajar',label='Open ajar doors',icon='fas fa-door-open',distance=distance,
            canInteract=function(entity) local machine=machineOf(entity);return machine and MetaComic.VendingIsAjar and MetaComic.VendingIsAjar(machine.id) end,
            onSelect=function(data) local machine=machineOf(data.entity);if machine then TriggerServerEvent('meta_comic:server:vendingOpenAjar',machine.id) end end},
        {
            name = 'meta_comic_vending_manage', label = 'Manage', icon = 'fas fa-gear', distance = distance,
            canInteract = function(entity)
                local machine = machineOf(entity)
                return machine~=nil
            end,
            onSelect = function(data)
                local machine = machineOf(data.entity)
                if machine then openWorkspace(machine.id) end
            end,
        },
    })
end)

-- the vending machine item: place it like /placevending, then the server checks the item is still there
RegisterNetEvent('meta_comic:client:vendingSerial', function(data)
    if type(data) ~= 'table' or type(data.serial) ~= 'string' then return end
    if not needsOxLib() then return notify(('Machine serial: %s'):format(data.serial), 'info') end
    menu('meta_comic_vending_serial', 'Machine identification plate', {
        { title = data.serial, description = 'Compare this serial with the owner\'s vending registration document.', icon = 'barcode', readOnly = true },
    })
end)

RegisterNetEvent('meta_comic:client:placeVendingItem', function()
    if ghost then return notify('You are already placing a vending machine.', 'error') end
    local placed = placeGhost(cfg.Model or 'metacomics_vending_machine')
    if placed then
        TriggerServerEvent('meta_comic:server:placeVendingItem', placed.x, placed.y, placed.z, placed.w)
    else
        TriggerServerEvent('meta_comic:server:cancelVendingItem')
        notify('Vending machine placement cancelled.', 'info')
    end
end)

-- ox_inventory items: client = { export = '<resource>.UseVendingMachine' } (also UseVendingRecord / UseVendingLedger)
local function slotOf(...)
    for i = 1, select('#', ...) do
        local value = select(i, ...)
        if type(value) == 'table' and tonumber(value.slot) then return tonumber(value.slot) end
        if tonumber(value) then return tonumber(value) end
    end
end
exports('UseVendingMachine', function(...) local slot = slotOf(...); if slot then TriggerServerEvent('meta_comic:server:useVendingItem', slot) end end)
exports('UseVendingRecord', function(...) local slot = slotOf(...); if slot then TriggerServerEvent('meta_comic:server:useVendingRecord', 'certificate', slot) end end)
exports('UseVendingLedger', function(...) local slot = slotOf(...); if slot then TriggerServerEvent('meta_comic:server:useVendingRecord', 'ledger', slot) end end)

-- registration certificate / ledger: shown in the NUI
RegisterNetEvent('meta_comic:client:vendingRecord', function(record)
    SetNuiFocus(true, true)
    SendNUIMessage({ type = 'metaComic:open', view = 'pack', overlay = true, mode = 'vendingRecord', record = record })
end)

-- admin UI map: "Set waypoint" on a machine
RegisterNUICallback('vendingWaypoint', function(data, cb)
    local x, y = tonumber(data and data.x), tonumber(data and data.y)
    if x and y then SetNewWaypoint(x + 0.0, y + 0.0) end
    cb({ ok = x ~= nil and y ~= nil })
end)

-- light over the packs: a spotlight from the top inside the window (Config.VendingMachines.SlotPacks.Light), drawn
-- every frame for machines within Range metres
do
    local light = (cfg.SlotPacks or {}).Light or {}
    if light.Enabled ~= false then
        local at, dir = light.Offset or vec3(-0.15, -0.36, 0.63), light.Direction or vec3(0.0, 0.15, -1.0)
        local color = light.Color or { 255, 244, 225 }
        local range = tonumber(light.Range) or 30.0
        local distance, brightness = tonumber(light.Distance) or 1.4, tonumber(light.Brightness) or 4.0
        local hardness, radius, falloff = tonumber(light.Hardness) or 0.0, tonumber(light.Radius) or 55.0, tonumber(light.Falloff) or 10.0
        CreateThread(function()
            while true do
                local ped = GetEntityCoords(PlayerPedId())
                local any = false
                for _, machine in pairs(machines) do
                    local entity = machine.entity
                    if entity and DoesEntityExist(entity) and #(GetEntityCoords(entity) - ped) <= range then
                        any = true
                        local p = GetOffsetFromEntityInWorldCoords(entity, at.x, at.y, at.z)
                        local d = GetOffsetFromEntityInWorldCoords(entity, at.x + dir.x, at.y + dir.y, at.z + dir.z) - p
                        local len = math.max(#d, 0.001)
                        DrawSpotLight(p.x, p.y, p.z, d.x / len, d.y / len, d.z / len, color[1], color[2], color[3], distance, brightness, hardness, radius, falloff)
                    end
                end
                Wait(any and 0 or 1000)
            end
        end)
    end
end

AddEventHandler('onResourceStop', function(name)
    if name ~= GetCurrentResourceName() then return end
    clearGhost()
    for _, machine in pairs(machines) do despawn(machine) end
end)
