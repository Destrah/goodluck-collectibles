local cfg=Config.CardBuyers or {}
if cfg.Enabled==false then return end
local active,spawned={},{}
local function notify(text) TriggerEvent('meta_comic:client:notify',text,'info') end
local function request(index) TriggerEvent('meta_comic:client:openCardBuyer',index) end
RegisterNetEvent('meta_comic:client:cardBuyerStock',function(index,rows,page,pages,total)
    local title=('Purchased cards · %d · page %d/%d'):format(total,page,pages)
    local options,qb={},{{header=title,isMenuHeader=true}}
    for _,row in ipairs(rows) do
        local label=row.label..(row.grade and (' · grade %s'):format(row.grade) or '')
        local args={index=index,id=row.id,page=page}
        options[#options+1]={title=label,description=('Bought for $%s · Retrieve original card'):format(row.price),event='meta_comic:client:retrieveBuyerCard',args=args}
        qb[#qb+1]={header=label,txt=('Bought for $%s · Retrieve'):format(row.price),params={event='meta_comic:client:retrieveBuyerCard',args=args}}
    end
    for _,p in ipairs({page-1,page+1}) do if p>=1 and p<=pages then
        local label=p<page and 'Previous page' or 'Next page';local args={index=index,page=p}
        options[#options+1]={title=label,event='meta_comic:client:buyerStockPage',args=args}
        qb[#qb+1]={header=label,params={event='meta_comic:client:buyerStockPage',args=args}}
    end end
    if GetResourceState('ox_lib')=='started' then
        exports.ox_lib:registerContext({id='meta_comic_buyer_stock',title=title,options=options});exports.ox_lib:showContext('meta_comic_buyer_stock')
    elseif GetResourceState('qb-menu')=='started' then exports['qb-menu']:openMenu(qb)
    else notify('Purchased card stock requires ox_lib or qb-menu.') end
end)
RegisterNetEvent('meta_comic:client:retrieveBuyerCard',function(args) TriggerServerEvent('meta_comic:server:retrieveBuyerCard',args.index,args.id,args.page) end)
RegisterNetEvent('meta_comic:client:buyerStockPage',function(args) TriggerServerEvent('meta_comic:server:cardBuyerStock',args.index,args.page) end)
RegisterNetEvent('meta_comic:client:cardBuyerStatus',function(status) active=status or {} end)
RegisterNetEvent('meta_comic:client:cardBuyerMenu',function(index,offers,balance)
    local options,qb={},{{header='Sell trading cards',isMenuHeader=true}}
    for _,offer in ipairs(offers or {}) do
        local disabled=balance~=false and balance<offer.price
        local label=('%s — $%d each'):format(offer.label,offer.price)
        local args={index=index,slot=offer.slot,price=offer.price,instanceId=offer.instanceId}
        options[#options+1]={title=label,description=disabled and 'Business funds are too low' or 'Sell one card from this inventory slot',disabled=disabled,
            event='meta_comic:client:sellTradingCard',args=args}
        qb[#qb+1]={header=label,txt=disabled and 'Business funds are too low' or 'Sell one card',disabled=disabled,
            params={event='meta_comic:client:sellTradingCard',args=args}}
    end
    if GetResourceState('ox_lib')=='started' then
        exports.ox_lib:registerContext({id='meta_comic_card_buyer',title='Sell trading cards',options=options})
        exports.ox_lib:showContext('meta_comic_card_buyer')
    elseif GetResourceState('qb-menu')=='started' then exports['qb-menu']:openMenu(qb)
    else
        notify('Card offers (use /'..(cfg.Command or 'sellcards')..' <buyer> <slot> <price> to sell):')
        for _,offer in ipairs(offers or {}) do
            notify(('Buyer %d, slot %d: %s — $%d'):format(index,offer.slot,offer.label,offer.price))
        end
        -- Keep the server's quote identities for the command fallback.
        MetaComicCardBuyerOffers={index=index,offers=offers}
    end
end)
RegisterNetEvent('meta_comic:client:sellTradingCard',function(args)
    if not args then return end
    local done=true
    if GetResourceState('ox_lib')=='started' then
        done=exports.ox_lib:progressBar({duration=2000,label='Handing over the trading card',canCancel=true,
            disable={move=true,car=true,combat=true},anim={dict='mp_common',clip='givetake1_a',flag=49}})==true
    end
    if done then TriggerServerEvent('meta_comic:server:sellTradingCard',args.index,args.slot,args.price,args.instanceId) end
end)
RegisterCommand(cfg.Command or 'sellcards',function(_,args)
    local index=tonumber(args[1])
    if not index then
        local position=GetEntityCoords(PlayerPedId())
        for i,buyer in ipairs(cfg.Peds or {}) do
            local c=buyer.coords
            if active[i] and c and #(position-vector3(c.x,c.y,c.z))<=(tonumber(buyer.Distance or cfg.Distance) or 2)+1 then index=i;break end
        end
    end
    if not index then notify('Approach a trading card buyer first.');return end
    if args[2] then
        local quotes=MetaComicCardBuyerOffers
        for _,offer in ipairs(quotes and quotes.index==index and quotes.offers or {}) do
            if offer.slot==tonumber(args[2]) and offer.price==tonumber(args[3]) then
                TriggerEvent('meta_comic:client:sellTradingCard',{index=index,slot=offer.slot,price=offer.price,instanceId=offer.instanceId});return
            end
        end
        notify('Request current offers first with /'..(cfg.Command or 'sellcards')..' '..index);return
    end
    request(index)
end,false)
local function despawn(index)
    local ped=spawned[index];spawned[index]=nil
    if not ped then return end
    if GetResourceState('ox_target')=='started' then pcall(function() exports.ox_target:removeLocalEntity(ped) end) end
    if GetResourceState('qb-target')=='started' then pcall(function() exports['qb-target']:RemoveTargetEntity(ped) end) end
    if DoesEntityExist(ped) then DeleteEntity(ped) end
end
local function spawn(index,buyer)
    local model=type(buyer.model)=='number' and buyer.model or joaat(buyer.model or 's_m_m_highsec_01')
    if not IsModelInCdimage(model) then return end
    RequestModel(model);local deadline=GetGameTimer()+5000
    while not HasModelLoaded(model) do if GetGameTimer()>deadline then return end;Wait(50) end
    if active[index]~=true then SetModelAsNoLongerNeeded(model);return end
    local c=buyer.coords
    local ped=CreatePed(4,model,c.x,c.y,c.z-1.0,c.w or 0,false,true)
    SetModelAsNoLongerNeeded(model)
    SetEntityInvincible(ped,true);FreezeEntityPosition(ped,true);SetBlockingOfNonTemporaryEvents(ped,true);SetPedCanRagdoll(ped,false)
    if buyer.scenario~=false then TaskStartScenarioInPlace(ped,buyer.scenario or 'WORLD_HUMAN_CLIPBOARD',0,true) end
    spawned[index]=ped
    local distance=tonumber(buyer.Distance or cfg.Distance) or 2
    if GetResourceState('ox_target')=='started' then
        exports.ox_target:addLocalEntity(ped,{{name='meta_comic_card_buyer_'..index,label=buyer.label or 'Sell trading cards',icon='fas fa-money-bill',distance=distance,
            canInteract=function() return active[index]==true end,onSelect=function() request(index) end}})
    elseif GetResourceState('qb-target')=='started' then
        exports['qb-target']:AddTargetEntity(ped,{options={{label=buyer.label or 'Sell trading cards',icon='fas fa-money-bill',
            canInteract=function() return active[index]==true end,action=function() request(index) end}},distance=distance})
    end
end
CreateThread(function()
    TriggerServerEvent('meta_comic:server:cardBuyerStatus')
    while true do
        local position=GetEntityCoords(PlayerPedId())
        for index,buyer in ipairs(cfg.Peds or {}) do
            local c=buyer.coords
            if c then
                local distance=#(position-vector3(c.x,c.y,c.z))
                local range=tonumber(buyer.SpawnDistance or cfg.SpawnDistance) or 60
                if spawned[index] and (active[index]~=true or distance>range+10 or not DoesEntityExist(spawned[index])) then despawn(index) end
                if not spawned[index] and active[index]==true and distance<=range then spawn(index,buyer) end
            end
        end
        Wait(1000)
    end
end)
AddEventHandler('onResourceStop',function(name)
    if name~=GetCurrentResourceName() then return end
    for index in pairs(spawned) do despawn(index) end
end)

local dealing,currentDealProp=false,nil
MetaComic.CardBuyerDeal=function(area,count)
    if not area then return true end
    if dealing then return false end
    dealing=true
    local ped=PlayerPedId()
    local animation=area.Animation or {dict='mp_common',clip='givetake1_a',Duration=850,flag=49}
    local prop
    local function valid()
        return dealing and not IsEntityDead(ped) and not IsPedRagdoll(ped) and not IsPedInAnyVehicle(ped,false)
            and (not area.Bounds or MetaComic.CardBuyerZones.contains(GetEntityCoords(ped),area.Bounds))
    end
    local ok,done=pcall(function()
        if area.Spot then
            local spot=area.Spot
            TaskGoStraightToCoord(ped,spot.x,spot.y,spot.z,1.0,4000,spot.w or 0,0.1)
            local deadline=GetGameTimer()+4000
            while #(GetEntityCoords(ped)-vector3(spot.x,spot.y,spot.z))>0.25 do
                if not valid() or GetGameTimer()>deadline then return false end
                Wait(50)
            end
            SetEntityHeading(ped,spot.w or 0)
        end
        RequestAnimDict(animation.dict)
        local deadline=GetGameTimer()+5000
        while not HasAnimDictLoaded(animation.dict) do if GetGameTimer()>deadline or not valid() then return false end;Wait(25) end
        if animation.Prop and animation.Prop.model then
            local p=animation.Prop;local model=joaat(p.model)
            RequestModel(model);deadline=GetGameTimer()+5000
            while not HasModelLoaded(model) do if GetGameTimer()>deadline or not valid() then return false end;Wait(25) end
            local c=GetEntityCoords(ped);prop=CreateObject(model,c.x,c.y,c.z,false,false,false);currentDealProp=prop
            SetModelAsNoLongerNeeded(model)
            local o,r=p.offset or vec3(0,0,0),p.rotation or vec3(0,0,0)
            AttachEntityToEntity(prop,ped,GetPedBoneIndex(ped,p.bone or 57005),o.x,o.y,o.z,r.x,r.y,r.z,false,false,false,false,2,true)
        end
        for index=1,count do
            if not valid() then return false end
            SendNUIMessage({type='metaComic:cardBuyerDealing',index=index,count=count})
            local clipDuration=GetAnimDuration(animation.dict,animation.clip)*1000
            local duration=math.max(250,math.min(3000,tonumber(animation.Duration) or 850,clipDuration>0 and clipDuration or 3000))
            TaskPlayAnim(ped,animation.dict,animation.clip,4.0,-4.0,duration,animation.flag or 49,0,false,false,false)
            deadline=GetGameTimer()+duration
            while GetGameTimer()<deadline do
                DisableControlAction(0,24,true);DisableControlAction(0,25,true);DisableControlAction(0,21,true)
                DisableControlAction(0,30,true);DisableControlAction(0,31,true)
                if IsControlJustPressed(0,73) or not valid() then return false end
                local elapsed=duration-(deadline-GetGameTimer())
                if elapsed>150 and elapsed<duration-100 and not IsEntityPlayingAnim(ped,animation.dict,animation.clip,3) then return false end
                Wait(0)
            end
        end
        return true
    end)
    ClearPedTasks(ped)
    if prop and DoesEntityExist(prop) then DeleteEntity(prop) end
    currentDealProp=nil
    dealing=false
    SendNUIMessage({type='metaComic:cardBuyerDealing',done=true})
    return ok and done==true
end
AddEventHandler('onResourceStop',function(name)
    if name==GetCurrentResourceName() and dealing then
        dealing=false;ClearPedTasks(PlayerPedId())
        if currentDealProp and DoesEntityExist(currentDealProp) then DeleteEntity(currentDealProp) end
        currentDealProp=nil
    end
end)
