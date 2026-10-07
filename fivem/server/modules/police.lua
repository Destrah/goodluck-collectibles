-- Police alerts (Config.Police) for vending machine break-ins, hacks and thefts. System:
--   'auto'           the first dispatch resource that is running (list below), otherwise 'builtin'
--   'ps-dispatch' | 'cd_dispatch' | 'qs-dispatch' | 'tk_dispatch'   sent from the suspect's client (their exports are client side)
--   'rush-dispatch'                                              client CustomAlert export from the supplied fork
--   'core_dispatch' | 'rcore_dispatch' | 'lb-tablet'                 sent from the server
--   'builtin'        a notification and a map blip for every online police player (Config.Police.Jobs)
--   'custom'         Config.Police.Custom(source, alert) on the server
--   'none'           no alerts
local cfg = Config.Police or {}
MetaComic.Police = {}
local service = MetaComic.Police
local AUTO = { 'rush-dispatch', 'ps-dispatch', 'cd_dispatch', 'qs-dispatch', 'core_dispatch', 'rcore_dispatch', 'lb-tablet', 'tk_dispatch' }
local CLIENT_SIDE = { ['rush-dispatch'] = true, ['ps-dispatch'] = true, ['cd_dispatch'] = true, ['qs-dispatch'] = true, ['tk_dispatch'] = true }
local phoneSent = {}

local function jobs() return type(cfg.Jobs) == 'table' and cfg.Jobs or { 'police' } end
function service.isPolice(source)
    local test = MetaComic.VendingTestRole and MetaComic.VendingTestRole(source)
    if test then return test.police == true end
    local job = MetaComic.Framework.getJob and MetaComic.Framework.getJob(source)
    if not job or not job.name then return false end
    for _, name in ipairs(jobs()) do
        if job.name == name then return cfg.OnDutyOnly == false or job.onDuty ~= false end
    end
    return false
end
function service.count()
    local count = 0
    for _, player in ipairs(GetPlayers()) do if service.isPolice(tonumber(player)) then count = count + 1 end end
    return count
end
local function system()
    local name = cfg.System or 'auto'
    if name ~= 'auto' then return name end
    for _, candidate in ipairs(AUTO) do
        if GetResourceState(candidate) == 'started' then return candidate end
    end
    return 'builtin'
end
service.system = system

local function render(template, fields)
    return tostring(template):gsub('{([%w_]+)}', function(key) return tostring(fields[key] or '?') end)
end

-- The dispatch ZIP has no phone export: LB Phone's server exports deliver messages.
-- Resolve control from current records, not the suspect's identity or an expired hack.
function service.phone(source, alert)
    local phone = cfg.Phone or {}
    local resource = phone.Resource or 'lb-phone'
    if phone.Enabled ~= true or GetResourceState(resource) ~= 'started' then return false end
    if (phone.Stages or { start = true, success = true })[alert.stage] ~= true then return false end
    local registry = MetaComic.VendingRegistry
    local target
    if phone.Recipient == 'actor' then
        target = source
    elseif registry then
        local record = registry.get(alert.serial)
        local id = phone.Recipient == 'owner' and record and record.owner or nil
        if phone.Recipient ~= 'owner' then id = registry.controller(record) end
        if id and id ~= registry.BUSINESS then target = registry.onlineSource(id) or id end
    end
    if not target then return false end -- no personal chip controller (business-owned machine)
    local key = table.concat({ tostring(target), tostring(alert.serial), alert.action, alert.stage }, ':')
    local now = os.time()
    if phoneSent[key] and now - phoneSent[key] < math.max(0, tonumber(phone.Cooldown) or 60) then return false end
    -- Prune expired keys so alerts for old machines/recipients do not accumulate.
    for previous, at in pairs(phoneSent) do if now - at >= math.max(0, tonumber(phone.Cooldown) or 60) then phoneSent[previous] = nil end end
    phoneSent[key] = now
    local ok, result = pcall(function()
        local number = exports[resource]:GetEquippedPhoneNumber(target)
        if not number then return false end
        local message = render(phone.Message or '{title}: {message} ({stage})', alert):sub(1, 500)
        if phone.Mode == 'sms' then
            if type(phone.FromNumber) ~= 'string' or phone.FromNumber == '' then error('Config.Police.Phone.FromNumber is required for SMS') end
            return exports[resource]:SendMessage(phone.FromNumber, number, message)
        end
        return exports[resource]:SendNotification(number, {
            app = phone.App or 'information-app', title = render(phone.Title or 'Vending machine security', alert), content = message,
        })
    end)
    if not ok or result == false or result == nil then
        phoneSent[key] = nil
        if not ok then print('[meta-comic] phone crime alert failed: ' .. tostring(result)) end
        return false
    end
    return true
end

-- data: { action = 'breakin' | 'hack' | 'steal', coords = vector3 | { x, y, z }, serial, stage = 'start' | 'fail' | 'success' }
-- Each action's Config.Police.Alerts entry decides the chance per stage, the title, code and blip.
function service.alert(source, data)
    if type(data) ~= 'table' or not data.action or not data.coords then return false end
    local preset = (cfg.Alerts or {})[data.action] or {}
    local blip = {}
    for key, value in pairs(cfg.Blip or {}) do blip[key] = value end
    for key, value in pairs(preset.blip or {}) do blip[key] = value end
    local coords = data.coords
    local fields = {}
    for key, value in pairs(data) do fields[key] = value end
    fields.location = ('GPS %.1f, %.1f, %.1f'):format(coords.x, coords.y, coords.z)
    local alert = {
        action = data.action, stage = data.stage or 'start', serial = data.serial,
        title = preset.title or 'Vending machine tampering',
        message = render(preset.message or 'Someone is tampering with vending machine {serial}', fields),
        code = preset.code or cfg.Code or '10-90', priority = preset.priority or 2,
        coords = { x = coords.x + 0.0, y = coords.y + 0.0, z = coords.z + 0.0 },
        blip = blip, jobs = jobs(), dispatchJobs = cfg.DispatchJobs, rushDispatchJobs = cfg.RushDispatchJobs,
    }
    service.phone(source, alert)
    if alert.action ~= 'gps' and alert.stage ~= (cfg.CrimeAlertStage or 'start') then return false end
    if cfg.Enabled == false or system() == 'none' or preset.enabled == false then return false end
    local chance = tonumber((preset.chance or {})[alert.stage]) or (alert.stage == 'start' and 100 or 0)
    if chance <= 0 or math.random() * 100 >= chance then return false end
    local name = system()
    if name == 'custom' then
        if type(cfg.Custom) == 'function' then
            local ok, err = pcall(cfg.Custom, source, alert)
            if not ok then print('[meta-comic] Config.Police.Custom failed: ' .. tostring(err)) end
        end
        return true
    end
    if CLIENT_SIDE[name] then
        TriggerClientEvent('meta_comic:client:dispatch', source, name, alert)
        return true
    end
    local ok, err = pcall(function()
        if name == 'core_dispatch' then
            for _, job in ipairs(alert.jobs) do
                exports['core_dispatch']:addCall(alert.code, alert.message, { { icon = 'fa-cash-register', info = alert.title } },
                    { alert.coords.x, alert.coords.y, alert.coords.z }, job, (blip.time or 60) * 1000, blip.sprite or 52, blip.color or 1)
            end
        elseif name == 'rcore_dispatch' then
            TriggerEvent('rcore_dispatch:server:sendAlert', {
                code = alert.code, default_priority = alert.priority <= 1 and 'high' or 'medium', coords = vector3(alert.coords.x, alert.coords.y, alert.coords.z),
                job = alert.jobs, text = alert.message, type = 'alerts', blip_time = blip.time or 60,
                blip = { sprite = blip.sprite or 52, colour = blip.color or 1, scale = blip.scale or 1.0, text = alert.title, flashes = true, radius = 0 },
            })
        elseif name == 'lb-tablet' then
            for _, job in ipairs(alert.jobs) do
                exports['lb-tablet']:AddDispatch({
                    priority = alert.priority <= 1 and 'high' or 'medium', code = alert.code, title = alert.title, description = alert.message,
                    location = { label = alert.title, coords = vector2(alert.coords.x, alert.coords.y) }, time = blip.time or 60, job = job,
                })
            end
        else -- builtin
            for _, player in ipairs(GetPlayers()) do
                player = tonumber(player)
                if service.isPolice(player) then TriggerClientEvent('meta_comic:client:policeAlert', player, alert) end
            end
        end
    end)
    if not ok then print(('[meta-comic] police alert through %s failed: %s'):format(name, tostring(err))) end
    return ok
end

-- other scripts: exports['<resource>']:PoliceAlert(source, { action = 'breakin', coords = vector3(...), stage = 'start' })
exports('PoliceAlert', function(source, data) return service.alert(tonumber(source), data or {}) end)
