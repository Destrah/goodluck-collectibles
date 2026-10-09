local cfg=(Config.CardBuyers or {}).ZoneTool or {}
local active,last=nil,nil
local modes={'width','length','height','rotation','offset X','offset Y','offset Z'}
local function notify(message,kind) TriggerEvent('meta_comic:client:notify',message,kind or 'info') end
local function ray()
    local p,r=GetGameplayCamCoord(),GetGameplayCamRot(2)
    local pitch,yaw=math.rad(r.x),math.rad(r.z)
    local d=vector3(-math.sin(yaw)*math.cos(pitch),math.cos(yaw)*math.cos(pitch),math.sin(pitch))
    local to=p+d*math.max(1,tonumber(cfg.RayDistance) or 30)
    local handle=StartExpensiveSynchronousShapeTestLosProbe(p.x,p.y,p.z,to.x,to.y,to.z,19,PlayerPedId(),4)
    local _,hit,point=GetShapeTestResult(handle)
    return (hit==1 or hit==true) and point or nil
end
local function corners(s)
    local result={};local a=math.rad(s.heading);local co,si=math.cos(a),math.sin(a)
    for _,z in ipairs({-1,1}) do for _,y in ipairs({-1,1}) do for _,x in ipairs({-1,1}) do
        local dx,dy=x*s.size.x/2,y*s.size.y/2
        result[#result+1]=s.center+vector3(dx*co-dy*si,dx*si+dy*co,z*s.size.z/2)
    end end end
    return result
end
local edges={{1,2},{1,3},{2,4},{3,4},{5,6},{5,7},{6,8},{7,8},{1,5},{2,6},{3,7},{4,8}}
local function draw(s)
    if s.center then
        local c=corners(s)
        for _,edge in ipairs(edges) do local a,b=c[edge[1]],c[edge[2]]
            DrawLine(a.x,a.y,a.z,b.x,b.y,b.z,s.pinned and 80 or 245,s.valid and 220 or 80,160,255)
        end
    end
    SetTextFont(0);SetTextScale(0,0.32);SetTextColour(255,255,255,255);SetTextOutline()
    BeginTextCommandDisplayText('STRING')
    AddTextComponentSubstringPlayerName(('Box: %s | %s~n~Aim + LMB: place | R: aim again | LEFT/RIGHT: adjustment | Wheel/Q/E: adjust | SHIFT: fine~n~Mode: %s | Size %.2f / %.2f / %.2f | Heading %.1f~n~Offset %.2f / %.2f / %.2f | G: capture standing spot~n~ENTER: export to F8/clipboard | BACKSPACE/ESC: cancel'):format(
        s.name,s.pinned and 'placed' or (s.valid and 'surface found' or 'aim at a collision surface'),modes[s.mode],s.size.x,s.size.y,s.size.z,s.heading,s.offset.x,s.offset.y,s.offset.z))
    EndTextCommandDisplayText(0.02,0.65)
end
local function adjust(s,direction,fine)
    local step=(s.mode==4 and (fine and 1 or 5) or (fine and .01 or .1))*direction
    if s.mode<=3 then local axis=({'x','y','z'})[s.mode];s.size[axis]=math.max(.1,math.min(100,s.size[axis]+step))
    elseif s.mode==4 then s.heading=(s.heading+step)%360
    else local axis=({'x','y','z'})[s.mode-4];s.offset[axis]=math.max(-100,math.min(100,s.offset[axis]+step)) end
end
local function report(s)
    s.center=s.anchor+vector3(s.offset.x,s.offset.y,s.offset.z+s.size.z/2)
    last={name=s.name,coords={x=s.center.x,y=s.center.y,z=s.center.z},size=s.size,heading=s.heading,spot=s.spot}
    local output=('Bounds = { coords = vec3(%.4f, %.4f, %.4f), size = vec3(%.4f, %.4f, %.4f), heading = %.2f },'):format(
        s.center.x,s.center.y,s.center.z,s.size.x,s.size.y,s.size.z,s.heading)
    if s.spot then output=output..('\nSpot = vec4(%.4f, %.4f, %.4f, %.2f),'):format(s.spot.x,s.spot.y,s.spot.z,s.spot.w) end
    print('[box zone] '..s.name..'\n'..output)
    if GetResourceState('ox_lib')=='started' then pcall(function() exports.ox_lib:setClipboard(output) end) end
    notify('Box exported to F8; clipboard copied when available. Paste Bounds into your buyer config (and Spot into SellArea).')
end
RegisterNetEvent('meta_comic:client:boxZoneTool',function(options)
    options=options or {}
    if active then return notify('Finish or cancel the current box preview first.','error') end
    if IsNuiFocused() then return notify('Close the current menu before creating a box zone.','error') end
    if MetaComic.PropTuneBusy and MetaComic.PropTuneBusy() or MetaComic.VendingActionBusy and MetaComic.VendingActionBusy() then return notify('Finish the current action first.','error') end
    local size=options.size or cfg.DefaultSize or vector3(4,4,3)
    local s={name=tostring(options.name or 'box'),size={x=size.x or 4,y=size.y or 4,z=size.z or 3},
        heading=tonumber(options.heading) or GetEntityHeading(PlayerPedId()),offset={x=0,y=0,z=0},mode=1,valid=false}
    active=s
    CreateThread(function()
        local nextRay=0
        while active==s do
            local ped=PlayerPedId()
            if IsNuiFocused() then active=nil;notify('Box preview cancelled because a menu opened. Close it and run /'..tostring(cfg.Command or 'cardzone')..' again.','error');break end
            if IsEntityDead(ped) or IsPedInAnyVehicle(ped,false) then active=nil;notify('Box preview cancelled.');break end
            for _,control in ipairs({24,25,37,44,38,140,141,142,174,175,200,241,242}) do DisableControlAction(0,control,true) end
            if not s.pinned and GetGameTimer()>=nextRay then s.anchor=ray();s.valid=s.anchor~=nil;nextRay=GetGameTimer()+50 end
            if s.anchor then
                -- Anchor the bottom on the hit surface; offsets move from that contact point.
                s.center=s.anchor+vector3(s.offset.x,s.offset.y,s.offset.z+s.size.z/2)
            end
            draw(s)
            if IsDisabledControlJustPressed(0,24) and s.valid then s.pinned=true end
            if IsControlJustPressed(0,45) then s.pinned=false;s.valid=false end
            if IsDisabledControlJustPressed(0,175) then s.mode=s.mode%#modes+1 end
            if IsDisabledControlJustPressed(0,174) then s.mode=(s.mode-2)%#modes+1 end
            local direction=0
            if IsDisabledControlJustPressed(0,241) or IsDisabledControlJustPressed(0,38) then direction=1 end
            if IsDisabledControlJustPressed(0,242) or IsDisabledControlJustPressed(0,44) then direction=-1 end
            if direction~=0 then adjust(s,direction,IsControlPressed(0,21)) end
            if IsControlJustPressed(0,47) then local p=GetEntityCoords(ped);s.spot={x=p.x,y=p.y,z=p.z,w=GetEntityHeading(ped)};notify('Standing spot captured.') end
            if IsControlJustPressed(0,191) then
                if s.pinned and s.center then report(s);active=nil else notify('Aim at a surface and click to place the box first.','error') end
            elseif IsControlJustPressed(0,177) or IsDisabledControlJustPressed(0,200) then active=nil;notify('Box preview cancelled.') end
            Wait(0)
        end
    end)
end)
exports('GetLastBoxZone',function() return last and MetaComic.CopyTable(last) or nil end)
AddEventHandler('onResourceStop',function(name) if name==GetCurrentResourceName() then active=nil end end)
