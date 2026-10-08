-- Vending machine front door (Config.VendingMachines.Door). The normal one-piece model stays while the door is shut;
-- when the server says a machine's door is open, this swaps it for the body model with a separate door prop on the
-- hinge and swings the door open (and back shut afterwards). Needs metacomics_vending_body / metacomics_vending_door
-- streamed; without them nothing changes. metacomics_vending_cashlid adds the cash box lid (optional).
local cfg = Config.VendingMachines or {}
local door = cfg.Door or {}
if cfg.Enabled == false or door.Enabled == false then return end

local BODY = joaat(door.BodyModel or 'metacomics_vending_body')
local DOOR = joaat(door.DoorModel or 'metacomics_vending_door')
local hinge = door.Hinge or vec3(-0.5825, -0.435, 0.0)
local HINGE = vector3(hinge.x + 0.0, hinge.y + 0.0, hinge.z + 0.0)
local ANGLE = tonumber(door.Angle) or 105.0           -- how far it swings open (degrees)
local SPEED = tonumber(door.Speed) or 90.0            -- degrees per second
local SIGN = (tonumber(door.Direction) or -1) < 0 and -1 or 1 -- flip if it swings into the machine
local DISTANCE = tonumber(door.Distance) or 60.0      -- only animate doors this close
-- cash box behind the door: a lid hinged on its back edge, filled with cash props by how much cash the machine holds
local box = door.CashBox or {}
local LID = joaat(box.LidModel or 'metacomics_vending_cashlid')
local lidAt = box.LidHinge or vec3(0.402, 0.405, -0.6395)
local LIDPOS = vector3(lidAt.x + 0.0, lidAt.y + 0.0, lidAt.z + 0.0)
local LIDANGLE = tonumber(box.LidAngle) or 80.0
local LIDSIGN = (tonumber(box.LidDirection) or -1) < 0 and -1 or 1
local CASH_MODELS = box.CashProps or { 'prop_cash_pile_01', 'prop_anim_cash_note' }
local COIN_MODELS = box.CoinProps or { 'vw_prop_vw_coin_01a' }
local OVERFLOW_AT = tonumber(box.OverflowAt) or 3000   -- from this amount the box looks overflowing
local LAYER = tonumber(box.CashLayerHeight) or 0.035  -- height of each stacked layer
-- 2x2 grid pulled in toward the middle so piles never poke through the walls
-- (inner box x 0.282..0.522, y 0.122..0.393, floor z -0.833, rim z -0.64)
local CASH_SPOTS = box.CashSpots or { vec3(0.375, 0.21, -0.83), vec3(0.43, 0.21, -0.83), vec3(0.375, 0.305, -0.83), vec3(0.43, 0.305, -0.83) }
local INSIDE_LAYERS = math.max(1, math.floor(0.17 / LAYER)) -- layers that fit under the rim
local INSIDE_MAX = #CASH_SPOTS * INSIDE_LAYERS
-- cash per prop: by default the box is exactly full at OverflowAt, so taking cash visibly lowers the pile
local CASH_PER_PROP = tonumber(box.CashPerProp) or OVERFLOW_AT / INSIDE_MAX
-- above OverflowAt: { offset, pitch, heading } heaped over the rim, kept over the box
local OVERFLOW_SPOTS = box.OverflowSpots or {
    { vec3(0.40, 0.257, -0.625), 0.0, 0.0 }, { vec3(0.38, 0.23, -0.605), 6.0, 180.0 }, { vec3(0.42, 0.29, -0.605), -6.0, 0.0 },
    { vec3(0.40, 0.257, -0.585), 4.0, 90.0 }, { vec3(0.37, 0.15, -0.635), 25.0, 0.0 }, { vec3(0.44, 0.15, -0.635), 25.0, 180.0 },
}
-- above OverflowAt: notes and coins on the bay floor in front of the cash box, inside the machine
local BAY_SPOTS = box.BaySpots or {
    { vec3(0.35, 0.02, -0.815), 'cash', 15.0 }, { vec3(0.45, -0.06, -0.815), 'cash', 100.0 }, { vec3(0.38, -0.16, -0.815), 'cash', 200.0 },
    { vec3(0.32, -0.08, -0.815), 'coin', 0.0 }, { vec3(0.47, 0.04, -0.815), 'coin', 60.0 }, { vec3(0.42, -0.24, -0.815), 'coin', 120.0 },
    { vec3(0.34, -0.28, -0.815), 'coin', 200.0 },
}
-- after a break-in: some spilled onto the ground at the machine's front right (ground is z -0.95, front face y -0.44)
local GROUND_SPOTS = box.GroundSpots or {
    { vec3(0.30, -0.62, -0.95), 'cash', 20.0 }, { vec3(0.46, -0.70, -0.95), 'cash', 110.0 }, { vec3(0.62, -0.55, -0.95), 'cash', 250.0 },
    { vec3(0.38, -0.78, -0.95), 'coin', 0.0 }, { vec3(0.52, -0.60, -0.95), 'coin', 40.0 }, { vec3(0.25, -0.74, -0.95), 'coin', 80.0 },
    { vec3(0.66, -0.72, -0.95), 'coin', 130.0 }, { vec3(0.44, -0.86, -0.95), 'coin', 200.0 },
    { vec3(0.05, -0.70, -0.95), 'pack', 35.0 }, { vec3(-0.18, -0.82, -0.95), 'pack', 160.0 }, { vec3(0.20, -0.95, -0.95), 'pack', 280.0 },
}
local PACK_MODELS = door.PackProps or { 'prop_boosterpack_01' }
-- now and then a pack is stuck where it failed to drop into the PUSH chute, seen once the door opens (WedgedPackChance %)
local WEDGE_CHANCE = tonumber(door.WedgedPackChance) or 25
local WEDGE_AT = door.WedgedPackOffset or vec3(-0.15, -0.37, -0.36) -- below row C, above the PUSH chute: a pack that never dropped
local brokenBoxes = {} -- machine id -> true while its open box was broken into (cash spills onto the ground)
local lids = {} -- machine id -> cash level while its lid is open (from the server)
-- server rack right of the window: a lid hinged on its left edge, with status LEDs on the top unit inside
local rack = door.Rack or {}
local RACK_ON = rack.Enabled ~= false
local RACKLID = joaat(rack.LidModel or 'metacomics_vending_racklid')
local rackAt = rack.LidHinge or vec3(0.282, -0.40, -0.208)
local RACKPOS = vector3(rackAt.x + 0.0, rackAt.y + 0.0, rackAt.z + 0.0)
local RACKANGLE = tonumber(rack.LidAngle) or 100.0
local RACKSIGN = (tonumber(rack.LidDirection) or -1) < 0 and -1 or 1
local RACK_NEEDS = {}
for _, action in ipairs(rack.Required or { 'hack', 'fullhack', 'replaceboard', 'disablegps', 'enablegps', 'system' }) do RACK_NEEDS[action] = true end
RACK_NEEDS.falsifylogs = true
local leds = rack.Lights or {}
local LEDS = RACK_ON and leds.Enabled ~= false
local LED_GPS, LED_OS = leds.Gps or vec3(0.4595, -0.363, 0.5231), leds.Os or vec3(0.4826, -0.363, 0.5231)
local LED_SIZE, LED_RANGE = tonumber(leds.Size) or 0.012, tonumber(leds.Range) or 0.25
local LED_INTENSITY, LED_DISTANCE = tonumber(leds.Intensity) or 3.0, tonumber(leds.Distance) or 15.0
local racks = {} -- machine id -> true while its rack is open (from the server)

local doors = {} -- machine id -> { target, angle, entity (machine prop it replaced), body, door }
MetaComic.VendingDoorOpen = function(id)
    local state = doors[tonumber(id) or 0]
    return state ~= nil and (state.target > 0 or state.angle > 0)
end
-- the hacks need the cabinet and its cash box open (client/vending_crime.lua)
MetaComic.VendingHackReady = function(id) return box.Enabled == false or lids[tonumber(id) or 0] ~= nil end
-- the hacks and the GPS switch in Rack.Required need the server rack open instead (the server checks again)
MetaComic.VendingTechReady = function(id, action)
    id = tonumber(id) or 0
    if RACK_ON and RACK_NEEDS[action] then return racks[id] ~= nil end
    if action == 'hack' or action == 'fullhack' then return box.Enabled == false or lids[id] ~= nil end
    return true
end
MetaComic.VendingRackOpen = function(id) return racks[tonumber(id) or 0] ~= nil end
-- the cabinet door stands open, for whatever reason: the loot option shows (client/vending_crime.lua)
MetaComic.VendingCabinetOpen = function(id) local state = doors[tonumber(id) or 0]; return state ~= nil and (state.target or 0) > 0 end
local available, warned

local function modelsReady()
    -- only a positive result is kept: right after a (re)start the streamed models can briefly be missing
    if not available then
        available = IsModelInCdimage(BODY) and IsModelInCdimage(DOOR)
        if not available and not warned then
            warned = true
            print('[meta-comic] vending door: metacomics_vending_body / metacomics_vending_door are not streamed yet, so the door cannot open')
        end
    end
    return available
end
local function load(hash)
    RequestModel(hash)
    local timeout = GetGameTimer() + 3000
    while not HasModelLoaded(hash) and GetGameTimer() < timeout do Wait(0) end
    return HasModelLoaded(hash)
end

local function clearCash(state)
    for _, prop in ipairs(state.cash or {}) do if DoesEntityExist(prop) then DeleteEntity(prop) end end
    state.cash, state.cashLevel = nil, nil
end
local function addCash(state, i, offset, pitch, heading, models)
    models = models or CASH_MODELS
    local hash = joaat(models[(i - 1) % #models + 1])
    if not (IsModelInCdimage(hash) and load(hash)) then return end
    local prop = CreateObjectNoOffset(hash, 0.0, 0.0, 0.0, false, false, false)
    SetEntityCollision(prop, false, false)
    AttachEntityToEntity(prop, state.body, 0, offset.x, offset.y, offset.z, pitch, 0.0, heading, false, false, false, false, 2, true)
    SetModelAsNoLongerNeeded(hash)
    state.cash[#state.cash + 1] = prop
end
local function fillCash(state, amount, broken)
    clearCash(state)
    state.cashLevel, state.cashBroken = amount, broken
    state.cash = {}
    amount = tonumber(amount) or 0
    if amount <= 0 then return end
    -- stacked bottom up, so as cash is taken the top layer goes first; never past the rim below OverflowAt
    local count = math.min(math.max(1, math.ceil(amount / CASH_PER_PROP)), INSIDE_MAX)
    for i = 1, count do
        local layer = (i - 1) // #CASH_SPOTS
        local spot = CASH_SPOTS[(i - 1) % #CASH_SPOTS + 1]
        addCash(state, i, vector3(spot.x, spot.y, spot.z + layer * LAYER), 0.0, (i % 2) * 180.0)
    end
    if broken then
        for i, spot in ipairs(GROUND_SPOTS) do addCash(state, i, spot[1], 0.0, spot[3] + 0.0, spot[2] == 'coin' and COIN_MODELS or spot[2] == 'pack' and PACK_MODELS or CASH_MODELS) end
    end
    if amount < OVERFLOW_AT then return end
    -- overflow grows with the extra cash (full heap at twice OverflowAt) and drains first when looted
    local extra = math.min(1.0, (amount - OVERFLOW_AT) / OVERFLOW_AT + 0.01)
    for i = 1, math.max(1, math.ceil(#OVERFLOW_SPOTS * extra)) do
        local spill = OVERFLOW_SPOTS[i]
        addCash(state, count + i, spill[1], spill[2] + 0.0, spill[3] + 0.0)
    end
    for i = 1, math.max(1, math.ceil(#BAY_SPOTS * extra)) do
        local spot = BAY_SPOTS[i]
        addCash(state, i, spot[1], 0.0, spot[3] + 0.0, spot[2] == 'coin' and COIN_MODELS or CASH_MODELS)
    end
end

-- the card skimmer sits on the coin panel, which is part of the door: it rides on the door while the door is swapped in
local function skimmerOffset()
    local sk = cfg.Skimmer or {}
    local o, r = sk.Offset or vector3(0.359, -0.4405, 0.352), sk.Rotation or vector3(0.0, 0.0, 0.0)
    return vector3(o.x + 0.0, o.y + 0.0, o.z + 0.0), vector3(r.x + 0.0, r.y + 0.0, r.z + 0.0)
end
local function moveSkimmer(state, toDoor)
    local prop = state.skimmer
    if not prop or not DoesEntityExist(prop) then state.skimmer = nil; return end
    local o, r = skimmerOffset()
    if toDoor and state.body and DoesEntityExist(state.body) then
        -- hang it on the body, swung round the hinge by the door's angle: GTA doesn't reliably carry a prop that is
        -- attached to another attached prop (the door), so it's posed alongside the door every frame instead
        SetEntityVisible(prop, true, false) -- hiding the full machine also hid the skimmer attached to it
        local d = (cfg.Skimmer or {}).DoorAdjust or vector3(0.0, -0.004, 0.0)
        local a = math.rad(SIGN * (state.angle or 0.0))
        local x, y = o.x + d.x - HINGE.x, o.y + d.y - HINGE.y
        AttachEntityToEntity(prop, state.body, 0, HINGE.x + x * math.cos(a) - y * math.sin(a), HINGE.y + x * math.sin(a) + y * math.cos(a),
            o.z + d.z, r.x, r.y, r.z + SIGN * (state.angle or 0.0), false, false, false, false, 2, true)
    elseif state.entity and DoesEntityExist(state.entity) then
        AttachEntityToEntity(prop, state.entity, -1, o.x, o.y, o.z, r.x, r.y, r.z, false, false, false, false, 2, true)
    end
end

local function restore(state)
    moveSkimmer(state, false)
    state.skimmer = nil
    clearCash(state)
    if state.wedge and DoesEntityExist(state.wedge) then DeleteEntity(state.wedge) end
    state.wedge = nil
    if state.lid and DoesEntityExist(state.lid) then DeleteEntity(state.lid) end
    state.lid = nil
    if state.rackLid and DoesEntityExist(state.rackLid) then DeleteEntity(state.rackLid) end
    state.rackLid = nil
    if state.door and DoesEntityExist(state.door) then DeleteEntity(state.door) end
    if state.entity then TriggerEvent('meta_comic:client:vendingPackParent', state.entity, nil) end
    if state.body and DoesEntityExist(state.body) then DeleteEntity(state.body) end
    if state.entity and DoesEntityExist(state.entity) then SetEntityVisible(state.entity, true, false) end
    state.door, state.body, state.entity = nil, nil, nil
end

local function build(state, entity)
    if not load(BODY) or not load(DOOR) then available = false; return false end
    local coords, heading = GetEntityCoords(entity), GetEntityHeading(entity)
    local body = CreateObjectNoOffset(BODY, coords.x, coords.y, coords.z, false, false, false)
    SetEntityHeading(body, heading)
    FreezeEntityPosition(body, true)
    SetEntityCollision(body, false, false) -- the hidden machine keeps its collision, so ox_target options still work
    SetEntityInvincible(body, true)
    local front = CreateObjectNoOffset(DOOR, coords.x, coords.y, coords.z, false, false, false)
    SetEntityCollision(front, false, false)
    SetEntityInvincible(front, true)
    SetModelAsNoLongerNeeded(BODY); SetModelAsNoLongerNeeded(DOOR)
    if IsModelInCdimage(LID) and load(LID) then
        state.lid = CreateObjectNoOffset(LID, coords.x, coords.y, coords.z, false, false, false)
        SetEntityCollision(state.lid, false, false)
        SetModelAsNoLongerNeeded(LID)
    end
    if RACK_ON and IsModelInCdimage(RACKLID) and load(RACKLID) then
        state.rackLid = CreateObjectNoOffset(RACKLID, coords.x, coords.y, coords.z, false, false, false)
        SetEntityCollision(state.rackLid, false, false)
        SetModelAsNoLongerNeeded(RACKLID)
    end
    if math.random(100) <= WEDGE_CHANCE then
        local hash = joaat(PACK_MODELS[math.random(#PACK_MODELS)])
        if IsModelInCdimage(hash) and load(hash) then
            state.wedge = CreateObjectNoOffset(hash, coords.x, coords.y, coords.z, false, false, false)
            SetEntityCollision(state.wedge, false, false)
            AttachEntityToEntity(state.wedge, body, 0, WEDGE_AT.x + math.random(-20, 20) / 100, WEDGE_AT.y, WEDGE_AT.z, -35.0 + math.random(-10, 10), math.random(-25, 25) + 0.0, math.random(-20, 20) + 0.0, false, false, false, false, 2, true)
            SetModelAsNoLongerNeeded(hash)
        end
    end
    SetEntityVisible(entity, false, false)
    state.entity, state.body, state.door = entity, body, front
    TriggerEvent('meta_comic:client:vendingPackParent', entity, body)
    return true
end

local function pose(state)
    AttachEntityToEntity(state.door, state.body, 0, HINGE.x, HINGE.y, HINGE.z, 0.0, 0.0, SIGN * state.angle, false, false, false, false, 2, true)
    if state.lid then
        AttachEntityToEntity(state.lid, state.body, 0, LIDPOS.x, LIDPOS.y, LIDPOS.z, LIDSIGN * (state.lidAngle or 0.0), 0.0, 0.0, false, false, false, false, 2, true)
    end
    if state.rackLid then
        AttachEntityToEntity(state.rackLid, state.body, 0, RACKPOS.x, RACKPOS.y, RACKPOS.z, 0.0, 0.0, RACKSIGN * (state.rackAngle or 0.0), false, false, false, false, 2, true)
    end
end

-- status LEDs on the rack's top unit: red blinks while the GPS is on; green blinks for the original board, blue once
-- the operating system was taken over. Only with the rack lid model streamed (the new body has the rack in it).
local function led(body, at, r, g, b, glow)
    local p = GetOffsetFromEntityInWorldCoords(body, at.x, at.y, at.z)
    DrawMarker(28, p.x, p.y, p.z, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, LED_SIZE, LED_SIZE, LED_SIZE, r, g, b, 255, false, false, 2, false, nil, nil, false)
    if glow then -- only with the lid open, so the light doesn't shine through it
        local q = GetOffsetFromEntityInWorldCoords(body, at.x, at.y - 0.03, at.z)
        DrawLightWithRange(q.x, q.y, q.z, r, g, b, LED_RANGE, LED_INTENSITY)
    end
end
local function drawLeds(state, machine, ped)
    if not LEDS or not state.rackLid or not machine or #(GetEntityCoords(state.body) - ped) > LED_DISTANCE then return end
    local t, glow = GetGameTimer(), (state.rackAngle or 0.0) > 10.0
    if (cfg.GPS or {}).Enabled ~= false and not machine.gpsDisabled and t % 1000 < 450 then led(state.body, LED_GPS, 255, 0, 0, glow) end
    if (t + 300) % 1600 < 1100 then
        if machine.systemTakenOver then led(state.body, LED_OS, 0, 90, 255, glow) else led(state.body, LED_OS, 0, 255, 40, glow) end
    end
end

local running = false
local function animate()
    if running then return end
    running = true
    CreateThread(function()
        while next(doors) do
            local dt = GetFrameTime()
            local ped = GetEntityCoords(PlayerPedId())
            local anyNear = false
            for id, state in pairs(doors) do
                local machine = MetaComic.VendingMachineById and MetaComic.VendingMachineById(id)
                local entity = machine and machine.entity
                local near = entity and DoesEntityExist(entity) and #(GetEntityCoords(entity) - ped) <= DISTANCE
                if not near then
                    restore(state)
                    state.angle = state.target -- out of view: jump to the end state
                    state.lidAngle = lids[id] and state.target > 0 and LIDANGLE or 0.0
                    state.rackAngle = racks[id] and state.target > 0 and RACKANGLE or 0.0
                    if state.target == 0 then doors[id] = nil end
                else
                    anyNear = true
                    if state.entity ~= entity then restore(state) end
                    if (state.target > 0 or state.angle > 0) and not state.body then
                        if build(state, entity) then pose(state); state.skimmer = machine.skimmerProp; moveSkimmer(state, true) else doors[id] = nil end -- hang the door on the body first, so the skimmer follows it
                    end
                    if state.body then
                        -- the skimmer rides on the door; a skimmer (re)spawned while the door is open moves onto it too
                        state.skimmer = machine.skimmerProp -- picks up a skimmer fitted or re-synced while the door is open
                        local step = SPEED * dt
                        if state.angle < state.target then state.angle = math.min(state.target, state.angle + step)
                        elseif state.angle > state.target then state.angle = math.max(state.target, state.angle - step) end
                        local level = lids[id]
                        local lidTarget = level and state.target > 0 and LIDANGLE or 0.0
                        state.lidAngle = state.lidAngle or 0.0
                        if state.lidAngle < lidTarget then state.lidAngle = math.min(lidTarget, state.lidAngle + step)
                        elseif state.lidAngle > lidTarget then state.lidAngle = math.max(lidTarget, state.lidAngle - step) end
                        local rackTarget = racks[id] and state.target > 0 and RACKANGLE or 0.0
                        state.rackAngle = state.rackAngle or 0.0
                        if state.rackAngle < rackTarget then state.rackAngle = math.min(rackTarget, state.rackAngle + step)
                        elseif state.rackAngle > rackTarget then state.rackAngle = math.max(rackTarget, state.rackAngle - step) end
                        if level and (state.cashLevel ~= level or state.cashBroken ~= brokenBoxes[id]) then fillCash(state, level, brokenBoxes[id])
                        elseif not level and state.cash and state.lidAngle == 0 then clearCash(state) end
                        pose(state)
                        moveSkimmer(state, true)
                        drawLeds(state, machine, ped)
                        if state.target == 0 and state.angle == 0 and state.lidAngle == 0 and state.rackAngle == 0 then restore(state); doors[id] = nil end
                    end
                end
            end
            Wait(anyNear and 0 or 500)
        end
        running = false
    end)
end

local function setDoor(id, isOpen)
    id = tonumber(id)
    if not id or not modelsReady() then return end
    local state = doors[id]
    if not state then
        if not isOpen then return end
        state = { target = 0, angle = 0 }
        doors[id] = state
    end
    state.target = isOpen and ANGLE or 0
    -- the cabinet closed on its own (key session ran out): close a menu this player had open at it
    if not isOpen and state.entity and DoesEntityExist(state.entity) and lib and lib.getOpenContextMenu and lib.getOpenContextMenu()
        and #(GetEntityCoords(PlayerPedId()) - GetEntityCoords(state.entity)) < 4.0 then
        lib.hideContext(false)
    end
    animate()
end

RegisterNetEvent('meta_comic:client:vendingDoor', setDoor)
RegisterNetEvent('meta_comic:client:vendingDoors', function(list)
    for _, id in ipairs(list or {}) do setDoor(id, true) end
end)
CreateThread(function() Wait(3000); TriggerServerEvent('meta_comic:server:vendingDoors') end)
RegisterNetEvent('meta_comic:client:vendingCashbox', function(id, level, broken)
    id = tonumber(id) or 0
    lids[id], brokenBoxes[id] = level, broken == true or nil
end)
RegisterNetEvent('meta_comic:client:vendingCashboxes', function(list)
    for _, pair in ipairs(list or {}) do
        local id = tonumber(pair[1]) or 0
        lids[id], brokenBoxes[id] = pair[2], pair[3] == true or nil
    end
end)
RegisterNetEvent('meta_comic:client:vendingRack', function(id, isOpen) racks[tonumber(id) or 0] = isOpen == true or nil end)
RegisterNetEvent('meta_comic:client:vendingRacks', function(list)
    for _, id in ipairs(list or {}) do racks[tonumber(id) or 0] = true end
end)

-- breaking the cash box padlock on a broken-in machine (the server checks everything again)
local breaking = false
if box.Enabled ~= false and box.Lock ~= false and GetResourceState('ox_target') ~= 'missing' then
    CreateThread(function()
        while GetResourceState('ox_target') ~= 'started' do Wait(500) end
        local items = {}
        for _, item in ipairs(box.Items or {}) do
            items[type(item) == 'table' and item.item or item] = type(item) == 'table' and tonumber(item.count) or 1
        end
        exports.ox_target:addModel(cfg.Model or 'metacomics_vending_machine', { {
            name = 'meta_comic_vending_cashbox', label = box.Label or 'Break cash box padlock', icon = box.Icon or 'fa-solid fa-lock-open',
            distance = box.Distance or (cfg.Shop and cfg.Shop.TargetDistance) or 2.0,
            items = next(items) and items or nil,
            canInteract = function(entity)
                local machine = MetaComic.VendingMachineOf and MetaComic.VendingMachineOf(entity)
                -- broken into, or the cabinet is open for any other reason (unlocked with a key, being serviced)
                local cabinetOpen = (machine and (machine.unlockedUntil or 0) > 0) or (machine and doors[machine.id] ~= nil and (doors[machine.id].target or 0) > 0)
                return machine and not breaking and lids[machine.id] == nil and cabinetOpen and not machine.securitySeal
            end,
            onSelect = function(data)
                local machine = MetaComic.VendingMachineOf and MetaComic.VendingMachineOf(data.entity)
                if machine then TriggerServerEvent('meta_comic:server:cashboxStart', machine.id) end
            end,
        } })
    end)
end
-- picking the server rack lock on an open machine (the server checks everything again)
if RACK_ON and rack.Lock ~= false and GetResourceState('ox_target') ~= 'missing' then
    CreateThread(function()
        while GetResourceState('ox_target') ~= 'started' do Wait(500) end
        local items = {}
        for _, item in ipairs(rack.Items or {}) do
            items[type(item) == 'table' and item.item or item] = type(item) == 'table' and tonumber(item.count) or 1
        end
        exports.ox_target:addModel(cfg.Model or 'metacomics_vending_machine', { {
            name = 'meta_comic_vending_rack', label = rack.Label or 'Pick server rack lock', icon = rack.Icon or 'fa-solid fa-server',
            distance = rack.Distance or (cfg.Shop and cfg.Shop.TargetDistance) or 2.0,
            items = next(items) and items or nil,
            canInteract = function(entity)
                local machine = MetaComic.VendingMachineOf and MetaComic.VendingMachineOf(entity)
                local cabinetOpen = (machine and (machine.unlockedUntil or 0) > 0) or (machine and doors[machine.id] ~= nil and (doors[machine.id].target or 0) > 0)
                return machine and not breaking and racks[machine.id] == nil and cabinetOpen and not machine.securitySeal
            end,
            onSelect = function(data)
                local machine = MetaComic.VendingMachineOf and MetaComic.VendingMachineOf(data.entity)
                if machine then TriggerServerEvent('meta_comic:server:rackStart', machine.id) end
            end,
        } })
    end)
end
-- breaking the cash box padlock or picking the rack lock: minigame, then the rest of the time on a progress bar
local function breakOpen(data)
    local finish = data.finish or 'meta_comic:server:cashboxFinish'
    if breaking then return TriggerServerEvent(finish, data.token, false) end
    breaking = true
    local ped = PlayerPedId()
    local anim = data.animation or { dict = 'mini@safe_cracking', clip = 'idle_base', flag = 1 }
    if anim.dict then
        RequestAnimDict(anim.dict)
        local timeout = GetGameTimer() + 2000
        while not HasAnimDictLoaded(anim.dict) and GetGameTimer() < timeout do Wait(0) end
        TaskPlayAnim(ped, anim.dict, anim.clip, 3.0, 3.0, -1, anim.flag or 1, 0, false, false, false)
    end
    local started = GetGameTimer()
    local passed = true
    if data.minigame and MetaComic.RunMinigames then passed = MetaComic.RunMinigames(data.minigame) == true end
    local rest = data.duration - (GetGameTimer() - started)
    if passed and rest > 0 then
        if GetResourceState('ox_lib') == 'started' then
            passed = exports.ox_lib:progressBar({ duration = rest, label = data.label or 'Breaking the padlock', canCancel = true,
                disable = { move = true, car = true, combat = true } }) == true
        else
            Wait(rest)
        end
    end
    if anim.dict then StopAnimTask(ped, anim.dict, anim.clip, 2.0) end
    breaking = false
    TriggerServerEvent(finish, data.token, passed)
end
RegisterNetEvent('meta_comic:client:cashboxStart', breakOpen)
RegisterNetEvent('meta_comic:client:rackStart', breakOpen)

-- Loose door on a moving machine: a broken-into machine that is carried on a dolly or dragged behind a car (the
-- networked prop vending_carry spawns, flagged with the metaComicDoorLoose state bag) shows its door hanging open
-- and swinging with the movement, like a pendulum on its hinge. Purely visual, every client simulates its own.
local loose = {} -- prop entity -> { body, door, angle, speed, last = velocity }
local LOOSE = door.Loose or {}
local REST = tonumber(LOOSE.RestAngle) or 35.0      -- where the door settles when the machine stands still
local MAXANGLE = tonumber(LOOSE.MaxAngle) or 165.0
local PUSH = tonumber(LOOSE.Strength) or 260.0      -- how hard movement throws the door around
local DAMP = tonumber(LOOSE.Damping) or 2.2
local SPRING = tonumber(LOOSE.Spring) or 6.0

local function dropLoose(object, state)
    if state.door and DoesEntityExist(state.door) then DeleteEntity(state.door) end
    -- The body is the actual shared/carry entity; this module owns only the door.
    if state.ownsBody then
        if DoesEntityExist(state.body) then DeleteEntity(state.body) end
        if DoesEntityExist(object) then ResetEntityAlpha(object); SetEntityVisible(object, true, false) end
    end
    loose[object] = nil
end
local function buildLoose(object)
    if not load(DOOR) or not DoesEntityExist(object) then return nil end
    local coords = GetEntityCoords(object)
    -- Carrying keeps its existing full-machine parent and visual body swap.
    -- Towing now uses the collision-equipped body directly, with no proxy.
    local ownsBody = GetEntityModel(object) ~= BODY
    if ownsBody and not load(BODY) then return nil end
    local body = ownsBody and CreateObjectNoOffset(BODY, coords.x, coords.y, coords.z, false, false, false) or object
    local front = CreateObjectNoOffset(DOOR, coords.x, coords.y, coords.z, false, false, false)
    if not DoesEntityExist(object) or not DoesEntityExist(body) or not DoesEntityExist(front) then
        if ownsBody and DoesEntityExist(body) then DeleteEntity(body) end
        if front and DoesEntityExist(front) then DeleteEntity(front) end
        SetModelAsNoLongerNeeded(DOOR)
        return nil
    end
    if ownsBody then
        SetEntityCollision(body, false, false)
        local parentMin = GetModelDimensions(GetEntityModel(object))
        local visualMin = GetModelDimensions(BODY)
        AttachEntityToEntity(body, object, -1, 0.0, 0.0, parentMin.z - visualMin.z, 0.0, 0.0, 0.0, false, false, false, false, 2, true)
        SetModelAsNoLongerNeeded(BODY)
        SetEntityVisible(object, true, false)
        SetEntityAlpha(object, 0, false)
    end
    SetEntityCollision(front, false, false)
    AttachEntityToEntity(front, body, -1, HINGE.x, HINGE.y, HINGE.z, 0.0, 0.0, SIGN * REST, false, false, false, false, 2, true)
    SetModelAsNoLongerNeeded(DOOR)
    return { body = body, ownsBody = ownsBody, door = front, angle = REST, speed = 0.0, last = vector3(0.0, 0.0, 0.0), lastCoords = coords }
end

if LOOSE.Enabled ~= false then
    CreateThread(function()
        local fullModel = joaat(cfg.Model or 'metacomics_vending_machine')
        local seen, nextScan = {}, 0
        while true do
            local near = false
            if modelsReady() then
                local ped = GetEntityCoords(PlayerPedId())
                if GetGameTimer() >= nextScan then
                nextScan = GetGameTimer() + 500
                seen = {}
                for _, object in ipairs(GetGamePool('CObject')) do
                    if NetworkGetEntityIsNetworked(object)
                        and (GetEntityModel(object) == BODY or GetEntityModel(object) == fullModel) and Entity(object).state.metaComicDoorLoose
                        and #(GetEntityCoords(object) - ped) <= DISTANCE then
                        seen[object] = true
                        if not loose[object] then loose[object] = buildLoose(object) end
                    end
                end
                end
                local dt = GetFrameTime()
                for object, state in pairs(loose) do
                    if not seen[object] or not DoesEntityExist(object) or not DoesEntityExist(state.door) then
                        dropLoose(object, state)
                    elseif state.door then
                        near = true
                        -- acceleration in the machine's own frame; sideways and forward shoves swing the door
                        -- Attached dolly props can report zero native velocity;
                        -- displacement keeps the door responsive while carried too.
                        local coords = GetEntityCoords(object)
                        local velocity = (coords - state.lastCoords) / math.max(dt, 0.001)
                        state.lastCoords = coords
                        local accel = (velocity - state.last) / math.max(dt, 0.001)
                        state.last = velocity
                        local heading = math.rad(GetEntityHeading(object))
                        local side = accel.x * math.cos(heading) + accel.y * math.sin(heading)
                        local forward = -accel.x * math.sin(heading) + accel.y * math.cos(heading)
                        local rad = math.rad(state.angle)
                        -- Inertia trails the cabinet's acceleration rather than following it.
                        local torque = -PUSH * 0.01 * (side * math.cos(rad) - forward * math.sin(rad)) * SIGN
                        torque = torque - SPRING * math.rad(state.angle - REST) - DAMP * math.rad(state.speed)
                        state.speed = state.speed + math.deg(torque) * dt
                        state.angle = state.angle + state.speed * dt
                        if state.angle < 2.0 then state.angle, state.speed = 2.0, math.abs(state.speed) * 0.35 end -- bounces off the frame
                        if state.angle > MAXANGLE then state.angle, state.speed = MAXANGLE, -math.abs(state.speed) * 0.35 end
                        AttachEntityToEntity(state.door, state.body, 0, HINGE.x, HINGE.y, HINGE.z, 0.0, 0.0, SIGN * state.angle,
                            false, false, false, false, 2, true)
                    end
                end
            end
            Wait(near and 0 or 750)
        end
    end)
end

AddEventHandler('onResourceStop', function(name)
    if name ~= GetCurrentResourceName() then return end
    for _, state in pairs(doors) do restore(state) end
    for object, state in pairs(loose) do dropLoose(object, state) end
end)
