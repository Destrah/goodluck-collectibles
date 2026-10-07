-- Skill checks / minigames (Config.Minigames). Crime actions name presets from that table; each preset uses one of:
--   'builtin'        this resource's own NUI games: lockpick, wires, keypad, sequence (no other resource needed)
--   'ox_skillcheck'  ox_lib skillCheck          'ps-ui'          ps-ui circle / maze / varhack / thermite / scrambler
--   'bl_ui'          bl_ui games                 'memorygame'     memorygame thermite grid
--   'qb-minigames'   qb-minigames skillbar / lockpick / hacking / keyminigame
--   'utk_fingerprint' utk_fingerprint             'glow_minigames' glow_minigames path / spot / math
--   'custom'         run = function() return true / false end (in Config.Minigames, runs on the client)
-- MetaComic.RunMinigames(names) runs a list in order and returns true only if every one passed. A preset whose
-- resource isn't running falls back to Config.MinigameFallback (default: the built-in lockpick at the same level).
local presets = Config.Minigames or {}
local nuiGame

local function started(name) return GetResourceState(name) == 'started' end
local function await(start)
    local p = promise.new()
    local ok, err = pcall(start, function(result) p:resolve(result == true or result == 1) end)
    if not ok then print('[meta-comic] minigame failed to start: ' .. tostring(err)); return false end
    return Citizen.Await(p)
end

local function builtin(preset)
    if nuiGame then return false end
    local id = ('%d'):format(GetGameTimer())
    nuiGame = { id = id, promise = promise.new() }
    SetNuiFocus(true, true)
    local game = {}
    for key, value in pairs(preset) do if type(value) ~= 'function' then game[key] = value end end
    game.id = id
    SendNUIMessage({ type = 'metaComic:open', view = 'pack', overlay = true, mode = 'minigame', minigame = game })
    local result = Citizen.Await(nuiGame.promise)
    nuiGame = nil
    SetNuiFocus(false, false)
    SendNUIMessage({ type = 'metaComic:close' })
    return result
end
RegisterNUICallback('minigameResult', function(data, cb)
    cb({ ok = true })
    if nuiGame and data and tostring(data.id) == nuiGame.id then nuiGame.promise:resolve(data.success == true) end
end)

local runners = {}
runners.builtin = builtin
runners.ox_skillcheck = function(p)
    if not started('ox_lib') then return nil end
    return exports.ox_lib:skillCheck(p.difficulty or { 'easy', 'medium' }, p.inputs) == true
end
runners['ps-ui'] = function(p)
    if not started('ps-ui') then return nil end
    local game = p.game or 'circle'
    return await(function(done)
        if game == 'circle' then exports['ps-ui']:Circle(done, p.circles or 3, p.seconds or 10)
        elseif game == 'maze' then exports['ps-ui']:Maze(done, p.seconds or 20)
        elseif game == 'varhack' then exports['ps-ui']:VarHack(done, p.blocks or 5, p.seconds or 5)
        elseif game == 'thermite' then exports['ps-ui']:Thermite(done, p.seconds or 10, p.grid or 5, p.incorrect or 3)
        else exports['ps-ui']:Scrambler(done, p.scramble or 'numeric', p.seconds or 30, p.mirrored or 0) end
    end)
end
runners.bl_ui = function(p)
    if not started('bl_ui') then return nil end
    local game = p.game or 'CircleProgress'
    return exports.bl_ui[game](exports.bl_ui, p.iterations or 3, p.config or p.difficulty or 50) == true
end
runners.memorygame = function(p)
    if not started('memorygame') then return nil end
    return await(function(done)
        exports['memorygame']:thermiteminigame(p.correct or 10, p.incorrect or 3, p.show or 3, p.lose or 10, function() done(true) end, function() done(false) end)
    end)
end
runners['qb-minigames'] = function(p)
    if not started('qb-minigames') then return nil end
    local game = p.game or 'Skillbar'
    if game == 'Lockpick' then return exports['qb-minigames']:Lockpick(p.pins or 3) == true end
    if game == 'Hacking' then return exports['qb-minigames']:Hacking(p.length or 5, p.seconds or 30) == true end
    if game == 'KeyMinigame' then local result = exports['qb-minigames']:KeyMinigame(p.keys or 10); return type(result) == 'table' and result.quit == false and (result.faults or 0) == 0 or result == true end
    return exports['qb-minigames']:Skillbar(p.difficulty or 'medium', p.keys or '1234') == true
end
runners.utk_fingerprint = function(p)
    if not started('utk_fingerprint') then return nil end
    return await(function(done)
        TriggerEvent('utk_fingerprint:Start', p.levels or 2, p.lives or 3, p.minutes or 2, function(outcome) done(outcome == true) end)
    end)
end
runners.glow_minigames = function(p)
    if not started('glow_minigames') then return nil end
    return await(function(done) exports['glow_minigames']:StartMinigame(done, p.game or 'path', p.settings) end)
end
runners.custom = function(p)
    if type(p.run) ~= 'function' then return nil end
    return p.run() == true
end
runners.none = function() return true end

local FALLBACK_LEVEL = { easy = 'lockpick_easy', medium = 'lockpick_medium', hard = 'lockpick_hard' }

local function run(name, depth)
    local preset = type(name) == 'table' and name or presets[name]
    if type(preset) ~= 'table' then
        print(('[meta-comic] unknown minigame preset %s (Config.Minigames)'):format(tostring(name)))
        return true
    end
    local runner = runners[preset.type or 'builtin']
    local result = runner and runner(preset)
    if result == nil then -- that resource isn't running
        local fallback = preset.fallback or Config.MinigameFallback or FALLBACK_LEVEL[preset.level or 'medium']
        if (depth or 0) < 2 and fallback and fallback ~= name then return run(fallback, (depth or 0) + 1) end
        return builtin({ game = 'lockpick', pins = 3, speed = 1.0, zone = 0.16, time = 25, mistakes = 3 })
    end
    return result == true
end

-- names: a preset name, a list of names (all must pass), or { random = { names... } } (one of them)
function MetaComic.RunMinigames(names)
    if names == nil or names == false then return true end
    if type(names) == 'string' then return run(names) end
    if type(names) == 'table' and type(names.random) == 'table' and #names.random > 0 then return run(names.random[math.random(1, #names.random)]) end
    if type(names) == 'table' and names.type then return run(names) end
    for _, name in ipairs(names) do
        if not MetaComic.RunMinigames(name) then return false end -- entries can be { random = { ... } } too
    end
    return true
end

-- other scripts: exports['<resource>']:Minigame('lockpick_hard') -> true / false
exports('Minigame', function(names) return MetaComic.RunMinigames(names) end)

-- Admin UI "Minigames" tab: lists Config.Minigames and runs a preset at a test speed. Built-in games play inside the
-- page; presets from other resources run here, then the admin UI opens again on that tab with the result.
-- Speed: moving parts faster, time limits shorter (same rules as src/minigames/presets.js scalePreset).
local TEST_FASTER = { speed = true }
local TEST_SHORTER = { time = true, seconds = true, show = true, perKey = true, minutes = true, lose = true, life = true }
local OX_LEVELS = { easy = { areaSize = 50, speedMultiplier = 1 }, medium = { areaSize = 40, speedMultiplier = 1.5 }, hard = { areaSize = 25, speedMultiplier = 1.75 } }
local RESOURCE_OF = { ox_skillcheck = 'ox_lib', ['ps-ui'] = 'ps-ui', bl_ui = 'bl_ui', memorygame = 'memorygame',
    ['qb-minigames'] = 'qb-minigames', utk_fingerprint = 'utk_fingerprint', glow_minigames = 'glow_minigames' }
local lastTest

local function testScale(preset, speed)
    local out = {}
    for key, value in pairs(preset) do
        if type(value) == 'number' and TEST_FASTER[key] then
            value = value * speed
        elseif type(value) == 'number' and TEST_SHORTER[key] then
            local integer = math.type(value) == 'integer'
            value = math.max(integer and 1 or 0.5, value / speed)
            if integer then value = math.floor(value + 0.5) end
        end
        out[key] = value
    end
    if out.type == 'ox_skillcheck' and out.difficulty then
        local list = (type(out.difficulty) == 'table' and not out.difficulty.areaSize) and out.difficulty or { out.difficulty }
        local scaled = {}
        for i, level in ipairs(list) do
            local base = type(level) == 'table' and level or OX_LEVELS[level] or OX_LEVELS.medium
            scaled[i] = { areaSize = base.areaSize or 40, speedMultiplier = (base.speedMultiplier or 1) * speed }
        end
        out.difficulty = scaled
    elseif out.type == 'bl_ui' and type(out.difficulty) == 'number' then
        out.difficulty = math.min(100, math.max(1, math.floor(out.difficulty * speed + 0.5)))
    end
    return out
end

RegisterNUICallback('getMinigames', function(_, cb)
    local list = {}
    for name, preset in pairs(presets) do
        if type(preset) == 'table' then
            local entry = { name = name }
            for key, value in pairs(preset) do if type(value) ~= 'function' then entry[key] = value end end
            local kind = preset.type or 'builtin'
            entry.available = kind == 'builtin' or kind == 'none' or (kind == 'custom' and type(preset.run) == 'function')
                or (RESOURCE_OF[kind] ~= nil and started(RESOURCE_OF[kind]))
            list[#list + 1] = entry
        end
    end
    table.sort(list, function(a, b) return a.name < b.name end)
    cb({ ok = true, presets = list, lastResult = lastTest })
end)

RegisterNUICallback('testMinigame', function(data, cb)
    local name = tostring(data and data.name or '')
    local preset = presets[name]
    if type(preset) ~= 'table' then cb({ ok = false, error = 'Unknown minigame preset ' .. name }); return end
    local speed = math.min(4, math.max(0.25, tonumber(data.speed) or 1))
    cb({ ok = true })
    CreateThread(function()
        local resource = GetCurrentResourceName()
        exports[resource]:CloseCards()
        Wait(200)
        local startedAt = GetGameTimer()
        local success = run(testScale(preset, speed))
        lastTest = { at = GetCloudTimeAsInt() * 1000 + startedAt % 1000, name = name, speed = speed, success = success == true,
            seconds = math.floor((GetGameTimer() - startedAt) / 100 + 0.5) / 10 }
        Wait(300)
        exports[resource]:OpenAdmin('minigames')
    end)
end)
