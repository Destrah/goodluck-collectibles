-- Card condition and grading, server side. Mirrors src/grading/condition.js: keep the thresholds, deductions and
-- match radii the same in both. Each pulled card copy gets a condition (small print imperfections), handling wears
-- unprotected cards, and a grader's marks are checked here so nobody can grade a flaw that isn't there.
MetaComic.Grading = {}
local G = MetaComic.Grading

local function r2(n) return math.floor(n * 100 + 0.5) / 100 end
local function clamp(n, lo, hi) return math.min(math.max(n, lo), hi) end
local function gauss(random)
    random=random or math.random
    local u, v = 0, 0
    while u == 0 do u = random() end
    while v == 0 do v = random() end
    return math.sqrt(-2 * math.log(u)) * math.cos(2 * math.pi * v)
end

G.LIMITS = { centeringFront = 0.1, centeringBack = 0.5, art = 0.6, text = 0.5, foil = 1.5, foilHue = 18, mask = 0.8, wear = 0.15 }
local LIMITS = G.LIMITS
G.TEXT_SECTIONS = { 'subtitle','title','hp','info','description','attack','footer' }
local LABELS = { centering = 'Off-centre', art = 'Artwork misaligned', text = 'Text misaligned', foil = 'Foil / holo off', mask = 'Mask effect off',
    corner = 'Corner wear', edge = 'Edge wear', scratch = 'Surface scratch', dent = 'Dent / dimple', crease = 'Crease', bend = 'Bend', tear = 'Tear',
    roller = 'Roller marks', printline = 'Print line', inkspot = 'Ink spot / fisheye', stain = 'Stain' }
G.LABELS = LABELS
-- what each marked flaw costs (s: severity 0..1) and how close a grader's click must be: mirrors condition.js
local MARK_DEDUCTIONS = { tear = function(s) return 3 + 2 * s end, crease = function(s) return 2 + 2 * s end, bend = function(s) return 1.5 + s end,
    dent = function() return 1 end, roller = function(s) return 1 + s end, stain = function(s) return 0.5 + s * 0.5 end,
    inkspot = function() return 0.5 end, printline = function(s) return 0.5 + s * 0.5 end }
local function markDeduction(kind, s) return (MARK_DEDUCTIONS[kind] or function(v) return 0.5 + v * 0.5 end)(s) end
local MARK_RADIUS = { bend = 12, roller = 12, dent = 8, inkspot = 6, stain = 10, printline = 6 }
local POINT_MARKS = { dent = true, inkspot = true, stain = true }
local FACTORY_MARKS = { { 'roller', 0.02 }, { 'printline', 0.03 }, { 'inkspot', 0.04 }, { 'stain', 0.015 } }
local CORNER_POINTS = { { 0, 0 }, { 100, 0 }, { 100, 100 }, { 0, 100 } }
local CORNER_NAMES = { 'top left', 'top right', 'bottom right', 'bottom left' }
local EDGE_NAMES = { 'top', 'right', 'bottom', 'left' }
G.GRADE_NAMES = { [10] = 'GEM MT', [9.5] = 'MINT+', [9] = 'MINT', [8.5] = 'NM-MT+', [8] = 'NM-MT', [7.5] = 'NM+', [7] = 'NM', [6.5] = 'EX-MT+', [6] = 'EX-MT',
    [5.5] = 'EX+', [5] = 'EX', [4.5] = 'VG-EX+', [4] = 'VG-EX', [3.5] = 'VG+', [3] = 'VG', [2.5] = 'GOOD+', [2] = 'GOOD', [1.5] = 'FAIR', [1] = 'POOR' }

local function tieredWear(s) return s > 0.7 and 1.5 or (s > 0.4 and 1 or 0.5) end
local function off(v) return math.sqrt(((v and v[1]) or 0) ^ 2 + ((v and v[2]) or 0) ^ 2) end

function G.flawOptions(card)
    local hasMask = false
    for _, layer in ipairs(type(card) == 'table' and type(card.subjectLayers) == 'table' and card.subjectLayers or {}) do
        if type(layer) == 'table' and layer.image and layer.image ~= '' then hasMask = true break end
    end
    return { hasFoil = type(card) == 'table' and card.holo ~= nil and card.holo ~= '' and card.holo ~= 'none', hasMask = hasMask, layout = card and card.layout }
end

function G.listFlaws(condition, options)
    options = options or {}
    local flaws = {}
    if type(condition) ~= 'table' then return flaws end
    for _, side in ipairs({ 'front', 'back' }) do
        local c = (condition.centering or {})[side] or {}
        local m = math.max(math.abs(c[1] or 0), math.abs(c[2] or 0))
        local limit = side == 'front' and LIMITS.centeringFront or LIMITS.centeringBack
        if m > limit then
            local deduction = side == 'front' and (m > 0.35 and 3 or (m > 0.2 and 2 or 1)) or (m > 0.7 and 2 or 1)
            flaws[#flaws + 1] = { id = 'centering-' .. side, type = 'centering', side = side, deduction = deduction, label = ('Off-centre (%s)'):format(side) }
        end
    end
    local art, foil = off(condition.art), off(condition.foil)
    if art > LIMITS.art then flaws[#flaws + 1] = { id = 'art', type = 'art', side = 'front', deduction = art > 1.5 and 1.5 or 0.5, label = LABELS.art } end
    local function textFlaw(part,offset,legacy)
      local text=off(offset)
      if text > LIMITS.text then
        local top = (options.layout == nil or options.layout == 'classic') and 58 or 49
        local regions = {subtitle={3,2,82,7},title={3,5,82,15},hp={72,2,98,15},info={3,top,98,top+8},description={3,top+5,98,94},attack={3,top+9,98,94},footer={3,93,98,100}}
        local dx,dy=offset[1] or 0,offset[2] or 0
        for _,r in pairs(regions) do r[1],r[2],r[3],r[4]=r[1]+dx,r[2]+dy,r[3]+dx,r[4]+dy end
        flaws[#flaws + 1] = { id = legacy and 'text' or 'text-'..part, type = 'text', side = 'front', deduction = text > 1.2 and 1 or 0.5,
          label = LABELS.text..' ('..(legacy and 'legacy layer' or part)..')', textPart=not legacy and part or nil, regions=legacy and regions or {[part]=regions[part]} }
      end
    end
    local text=type(condition.text)=='table' and condition.text or {}
    if type(text[1])=='number' or type(text[2])=='number' then textFlaw(nil,text,true)
    else for _,part in ipairs(G.TEXT_SECTIONS) do textFlaw(part,type(text[part])=='table' and text[part] or {},false) end end
    if options.hasFoil and (foil > LIMITS.foil or math.abs((condition.foil or {})[3] or 0) > LIMITS.foilHue) then
        flaws[#flaws + 1] = { id = 'foil', type = 'foil', side = 'front', deduction = foil > 3 and 1 or 0.5, label = LABELS.foil }
    end
    if options.hasMask and off(condition.mask) > LIMITS.mask then flaws[#flaws + 1] = { id = 'mask', type = 'mask', side = 'front', deduction = 0.5, label = LABELS.mask } end
    for _, side in ipairs({ 'front', 'back' }) do
        for index, s in ipairs((condition.corners or {})[side] or {}) do
            if s > LIMITS.wear then
                flaws[#flaws + 1] = { id = ('corner-%s-%d'):format(side, index - 1), type = 'corner', side = side, index = index - 1, x = CORNER_POINTS[index][1], y = CORNER_POINTS[index][2],
                    deduction = tieredWear(s), label = ('Corner wear (%s, %s)'):format(CORNER_NAMES[index], side) }
            end
        end
        for index, s in ipairs((condition.edges or {})[side] or {}) do
            if s > LIMITS.wear then
                flaws[#flaws + 1] = { id = ('edge-%s-%d'):format(side, index - 1), type = 'edge', side = side, index = index - 1, deduction = tieredWear(s), label = ('Edge wear (%s, %s)'):format(EDGE_NAMES[index], side) }
            end
        end
    end
    for _, mark in ipairs(condition.marks or {}) do
        local s = clamp(tonumber(mark.s) or 0.3, 0, 1)
        local deduction = markDeduction(mark.type, s)
        flaws[#flaws + 1] = { id = mark.id, type = mark.type, side = mark.side or 'front', mark = mark, deduction = r2(deduction), label = ('%s (%s)'):format(LABELS[mark.type] or mark.type, mark.side or 'front') }
    end
    return flaws
end

function G.gradeFromFlaws(flaws)
    local total = 0
    for _, flaw in ipairs(flaws) do total = total + (flaw.deduction or 0) end
    local grade = clamp(math.floor((10 - total) * 2) / 2, 1, 10)
    return math.tointeger(grade) or grade -- 9, not 9.0, in labels and JSON
end

function G.gradeFromFound(flaws, found)
    local list = {}
    for _, flaw in ipairs(flaws) do if found[flaw.id] then list[#list + 1] = flaw end end
    return G.gradeFromFlaws(list)
end

-- ---------- factory condition of a newly pulled card ----------
local markSerial = 0
local function markId(kind)
    markSerial = markSerial + 1
    return ('%s-%x-%x'):format(kind, os.time(), markSerial)
end

local function randomMark(kind, side, random)
    local math={random=random or math.random,pi=math.pi,cos=math.cos,sin=math.sin}
    side = side or (math.random() < 0.7 and 'front' or 'back')
    local s = r2(0.2 + math.random() * 0.6)
    if kind == 'tear' then
        local edge, along, depth = math.random(0, 3), 10 + math.random() * 80, 2 + s * 6
        local p = edge == 0 and { along, 0, along + 1, depth } or (edge == 1 and { 100, along, 100 - depth, along + 1 } or (edge == 2 and { along, 100, along - 1, 100 - depth } or { 0, along, depth, along - 1 }))
        return { id = markId(kind), type = kind, side = side, x1 = r2(p[1]), y1 = r2(p[2]), x2 = r2(p[3]), y2 = r2(p[4]), s = s }
    end
    if POINT_MARKS[kind] then
        local x, y = 15 + math.random() * 70, 15 + math.random() * 70
        return { id = markId(kind), type = kind, side = side, x1 = r2(x), y1 = r2(y), x2 = r2(x), y2 = r2(y), s = s }
    end
    -- roller marks follow the feed direction (nearly level); print lines are dead straight, level or upright
    local across = kind == 'crease' or kind == 'bend' or kind == 'roller' or kind == 'printline'
    local angle
    if kind == 'roller' then angle = (math.random() - 0.5) * 0.3
    elseif kind == 'printline' then angle = (math.random() < 0.5 and 0 or math.pi / 2) + (math.random() - 0.5) * 0.06
    else angle = across and ((math.random() < 0.5 and 0 or math.pi / 2) + (math.random() - 0.5) * 0.9) or math.random() * math.pi end
    local length = across and 140 or 8 + math.random() * 22
    local cx, cy = 20 + math.random() * 60, 20 + math.random() * 60
    local dx, dy = math.cos(angle) * length / 2, math.sin(angle) * length / 2
    return { id = markId(kind), type = kind, side = side, x1 = r2(clamp(cx - dx, 0, 100)), y1 = r2(clamp(cy - dy, 0, 100)), x2 = r2(clamp(cx + dx, 0, 100)), y2 = r2(clamp(cy + dy, 0, 100)), s = s }
end

-- A new card from a pack: print defects only. No wear or damage: that only comes from handling (G.applyWear).
function G.generate(random)
    random=random or math.random
    local math={random=random}
    local perfect = math.random() < 0.04
    local function g(scale) return perfect and r2(gauss(random) * scale * 0.25) or r2(gauss(random) * scale) end
    local miscut = not perfect and math.random() < 0.08
    local misprint = not perfect and math.random() < 0.04
    -- (same order of random draws as condition.js generateCondition)
    local marks = {}
    if not perfect then
        for _, entry in ipairs(FACTORY_MARKS) do if math.random() < entry[2] then marks[#marks + 1] = randomMark(entry[1],nil,random) end end
    end
    local sections={}
    for _,part in ipairs(G.TEXT_SECTIONS) do sections[part]=math.random()<0.28 and {g(0.36),g(0.3)} or {0,0} end
    return {
        v = 2,
        centering = {
            front = { r2(clamp(g(miscut and 0.3 or 0.13), -0.8, 0.8)), r2(clamp(g(miscut and 0.18 or 0.09), -0.8, 0.8)) },
            back = { r2(clamp(g(0.36), -0.85, 0.85)), r2(clamp(g(0.28), -0.85, 0.85)) },
        },
        art = { g(misprint and 1.8 or 0.48), g(misprint and 1.4 or 0.38) },
        text = sections,
        foil = { g(1.3), g(1.3), r2(gauss(random) * (perfect and 2 or 12)) },
        mask = { g(0.45), g(0.45) },
        corners = { front = { 0, 0, 0, 0 }, back = { 0, 0, 0, 0 } },
        edges = { front = { 0, 0, 0, 0 }, back = { 0, 0, 0, 0 } },
        marks = marks,
    }
end

-- ---------- wear from handling ----------
G.PROTECTION = { none = 0, sleeve = 1, toploader = 2, slab = 3 }

-- One handling event; returns a changed copy, or the same table when nothing happened. rough: spun hard in the viewer.
function G.applyWear(condition, protection, rough)
    local level = G.PROTECTION[protection or 'none'] or 0
    if type(condition) ~= 'table' or level >= 2 then return condition end
    local chance = rough and (level == 1 and 0.12 or 0.45) or (level == 1 and 0.01 or 0.07)
    if math.random() >= chance then return condition end
    local nextCondition = MetaComic.CopyTable(condition)
    nextCondition.marks = nextCondition.marks or {}
    local side = math.random() < 0.6 and 'front' or 'back'
    local roll = math.random()
    local function bump(list, amount)
        local index = math.random(1, 4)
        list[index] = r2(clamp((list[index] or 0) + amount, 0, 1))
    end
    nextCondition.corners = nextCondition.corners or { front = { 0, 0, 0, 0 }, back = { 0, 0, 0, 0 } }
    nextCondition.edges = nextCondition.edges or { front = { 0, 0, 0, 0 }, back = { 0, 0, 0, 0 } }
    if rough and level == 0 and roll < 0.22 then
        nextCondition.marks[#nextCondition.marks + 1] = randomMark(math.random() < 0.6 and 'crease' or 'bend', side)
    elseif rough and level == 0 and roll < 0.27 then
        nextCondition.marks[#nextCondition.marks + 1] = randomMark('tear', side)
    elseif roll < 0.55 then
        bump(nextCondition.corners[side], 0.08 + math.random() * 0.18)
    elseif roll < 0.85 then
        bump(nextCondition.edges[side], 0.06 + math.random() * 0.15)
    else
        nextCondition.marks[#nextCondition.marks + 1] = randomMark(math.random() < 0.7 and 'scratch' or 'dent', side)
    end
    return nextCondition
end

-- ---------- checking a grader's mark ----------
local function segmentDistance(x, y, mark)
    local ax, ay, bx, by = mark.x1 or 0, mark.y1 or 0, mark.x2 or 0, mark.y2 or 0
    local lx, ly = bx - ax, by - ay
    local length = lx * lx + ly * ly
    local t = length > 0 and clamp(((x - ax) * lx + (y - ay) * ly) / length, 0, 1) or 0
    return math.sqrt((x - (ax + t * lx)) ^ 2 + (y - (ay + t * ly)) ^ 2)
end
local WHOLE_FACE = { centering = true, art = true, foil = true, mask = true }

-- mark = { type, side, x, y } (x / y: % of the card face). Returns the matching flaw not found yet, or nil.
function G.matchMark(flaws, mark, found)
    if type(mark) ~= 'table' then return nil end
    local x, y = tonumber(mark.x) or -100, tonumber(mark.y) or -100
    local side = mark.side == 'back' and 'back' or 'front'
    -- "Off-centre" is how a shifted print looks to a grader: borders, art or the text block
    local accepts = { mark.type }
    for _, accepted in ipairs(accepts) do
    for _, flaw in ipairs(flaws) do
        if not found[flaw.id] and flaw.type == accepted and flaw.side == side then
            local near
            if flaw.type == 'text' then
                local r=flaw.regions and flaw.regions[mark.textPart]
                near=r and x>=r[1] and x<=r[3] and y>=r[2] and y<=r[4]
            elseif WHOLE_FACE[flaw.type] then near = true
            elseif flaw.type == 'corner' then near = math.sqrt((x - flaw.x) ^ 2 + (y - flaw.y) ^ 2) <= 18
            elseif flaw.type == 'edge' then near = ({ y, 100 - x, 100 - y, x })[flaw.index + 1] <= 9
            elseif POINT_MARKS[flaw.type] then near = math.sqrt((x - flaw.mark.x1) ^ 2 + (y - flaw.mark.y1) ^ 2) <= (MARK_RADIUS[flaw.type] or 7)
            else near = segmentDistance(x, y, flaw.mark) <= (MARK_RADIUS[flaw.type] or 7) end
            if near then return flaw end
        end
    end
    end
    return nil
end

function G.certNumber() return tostring(math.random(10000000, 99999999)) end

-- The grader's final pick: within `adjust` (half steps) of what their confirmed calls suggest, clamped to 1..10;
-- anything else falls back to the suggestion. Mirrors allowedGrade in condition.js.
function G.allowedGrade(chosen, suggested, adjust)
    adjust = math.max(0, tonumber(adjust) or 1)
    local grade = tonumber(chosen)
    if not grade or grade ~= grade or grade * 2 ~= math.floor(grade * 2) then return suggested end
    if grade < math.max(1, suggested - adjust) or grade > math.min(10, suggested + adjust) then return suggested end
    return math.tointeger(grade) or grade
end

-- ---------- grading records: kept by cert number so anyone can look a slab up ----------
-- Server KVP (works with every persistence adapter, survives restarts).
local RECORD_KEY = 'metacomic_grade:%s'
function G.saveRecord(record) SetResourceKvp(RECORD_KEY:format(record.cert), json.encode(record)) end
function G.getRecord(cert)
    cert = tostring(cert or ''):gsub('%D', '')
    if cert == '' then return nil end
    local raw = GetResourceKvpString(RECORD_KEY:format(cert))
    if not raw then return nil end
    local ok, record = pcall(json.decode, raw)
    return ok and type(record) == 'table' and record or nil
end
function G.newCert()
    for _ = 1, 20 do
        local cert = G.certNumber()
        if not GetResourceKvpString(RECORD_KEY:format(cert)) then return cert end
    end
    return G.certNumber()
end
