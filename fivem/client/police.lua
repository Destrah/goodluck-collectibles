-- Police alerts (server/modules/police.lua decides when). Dispatch resources whose exports are client side are called
-- from the suspect's client here; the built-in alert shows a notification and a blip to police players.
local function notify(message, notifyType) TriggerEvent('meta_comic:client:notify', message, notifyType) end
local function vec(c) return vector3(c.x + 0.0, c.y + 0.0, c.z + 0.0) end

RegisterNetEvent('meta_comic:client:dispatch', function(name, alert)
    local coords = vec(alert.coords)
    local blip = alert.blip or {}
    local ok, err = pcall(function()
        if name == 'rush-dispatch' then
            exports['rush-dispatch']:CustomAlert({
                dispatchCode = alert.code, message = alert.title, description = alert.message, priority = alert.priority,
                coords = coords, job = alert.rushDispatchJobs or { 'lspd', 'bcso', 'sasp' },
                sprite = blip.sprite or 52, color = blip.color or 1, scale = blip.scale or 1.0,
                -- This fork fades over 128 ticks of length seconds and expects string flags.
                radius = blip.radius or 0, length = (blip.time or 60) / 128, flash = 'true', offset = 'false',
            })
        elseif name == 'ps-dispatch' then
            exports['ps-dispatch']:CustomAlert({
                message = alert.title, code = alert.code, icon = 'fas fa-cash-register', priority = alert.priority, coords = coords,
                description = alert.message, jobs = alert.dispatchJobs or { 'leo' },
                alert = { radius = blip.radius or 0, sprite = blip.sprite or 52, color = blip.color or 1, scale = blip.scale or 1.0, length = blip.length or 3, sound = 'Lose_1st', sound2 = 'GTAO_FM_Events_Soundset', offset = false, flash = true },
            })
        elseif name == 'cd_dispatch' then
            local info = exports['cd_dispatch']:GetPlayerInfo()
            TriggerServerEvent('cd_dispatch:AddNotification', {
                job_table = alert.jobs, coords = coords, title = ('%s - %s'):format(alert.code, alert.title),
                message = ('%s on %s'):format(alert.message, info and info.street or 'an unknown street'), flash = 0, unique_id = info and info.unique_id or tostring(math.random(100000, 999999)), sound = 1,
                blip = { sprite = blip.sprite or 52, scale = blip.scale or 1.0, colour = blip.color or 1, flashes = false, text = alert.title, time = blip.time and math.ceil(blip.time / 60) or 5, radius = blip.radius or 0 },
            })
        elseif name == 'qs-dispatch' then
            TriggerServerEvent('qs-dispatch:server:CreateDispatchCall', {
                job = alert.jobs, callLocation = coords, callCode = { code = alert.code, snippet = alert.title }, message = alert.message, flashes = false, image = nil,
                blip = { sprite = blip.sprite or 52, scale = blip.scale or 1.0, colour = blip.color or 1, flashes = true, text = alert.title, time = (blip.time or 60) * 1000 },
            })
        elseif name == 'tk_dispatch' then
            exports.tk_dispatch:addCall({
                title = alert.title, code = alert.code, priority = ('Priority %d'):format(alert.priority or 2), coords = coords, showLocation = true,
                showGender = false, playSound = true, blip = { color = blip.color or 1, sprite = blip.sprite or 52, scale = blip.scale or 1.0 }, jobs = alert.jobs,
            })
        end
    end)
    if not ok then print(('[meta-comic] %s alert failed: %s'):format(name, tostring(err))) end
end)

-- built-in alert for police players
RegisterNetEvent('meta_comic:client:policeAlert', function(alert)
    local coords = vec(alert.coords)
    local settings = alert.blip or {}
    local street = GetStreetNameFromHashKey(GetStreetNameAtCoord(coords.x, coords.y, coords.z))
    notify(('%s %s: %s%s'):format(alert.code, alert.title, alert.message, street ~= '' and (' (' .. street .. ')') or ''), 'error')
    PlaySoundFrontend(-1, 'Lose_1st', 'GTAO_FM_Events_Soundset', true)
    local blip = AddBlipForCoord(coords.x, coords.y, coords.z)
    SetBlipSprite(blip, settings.sprite or 52)
    SetBlipColour(blip, settings.color or 1)
    SetBlipScale(blip, settings.scale or 1.0)
    SetBlipFlashes(blip, true)
    BeginTextCommandSetBlipName('STRING')
    AddTextComponentSubstringPlayerName(('%s %s'):format(alert.code, alert.title))
    EndTextCommandSetBlipName(blip)
    local area
    if (settings.radius or 0) > 0 then
        area = AddBlipForRadius(coords.x, coords.y, coords.z, settings.radius + 0.0)
        SetBlipColour(area, settings.color or 1)
        SetBlipAlpha(area, 90)
    end
    SetTimeout((settings.time or 60) * 1000, function()
        RemoveBlip(blip)
        if area then RemoveBlip(area) end
    end)
end)

-- Dispatch's getNearPed is private and distance-only. Only ambient human peds with actual sight qualify here.
function MetaComic.WatchCrimeWitness(token, active)
    local settings=(Config.Police or {}).Witness or {}
    local stopped=false
    if settings.Enabled==false or (Config.Police or {}).Enabled==false or (Config.Police or {}).System=='none' then return function() end end
    CreateThread(function()
        while not stopped and active() do
            local actor=PlayerPedId()
            local position=GetEntityCoords(actor)
            local radius=math.max(1,math.min(100,tonumber(settings.Radius) or 25))
            for _,ped in ipairs(GetGamePool('CPed')) do
                local population=GetEntityPopulationType(ped)
                if ped~=actor and population>=1 and population<=5 and not IsPedAPlayer(ped)
                    and IsPedHuman(ped) and not IsEntityDead(ped) and not IsEntityAMissionEntity(ped) then
                    local origin=GetEntityCoords(ped)
                    local delta=position-origin
                    local distance=#delta
                    if distance<=radius and distance>0.01 then
                        local forward=GetEntityForwardVector(ped)
                        local facing=(forward.x*delta.x+forward.y*delta.y)/math.max(0.01,math.sqrt(delta.x*delta.x+delta.y*delta.y))
                        if facing>=(tonumber(settings.FacingDot) or 0.25) and HasEntityClearLosToEntity(ped,actor,17) then
                            if not stopped and active() then TriggerServerEvent('meta_comic:server:crimeWitness',token) end
                            return
                        end
                    end
                end
            end
            Wait(math.max(250,tonumber(settings.Interval) or 1000))
        end
    end)
    return function() stopped=true end
end
