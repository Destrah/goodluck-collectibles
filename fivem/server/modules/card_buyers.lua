-- Prices, employee presence, inventory and funds are exclusively server-authoritative.
local cfg = Config.CardBuyers or {}
if cfg.Enabled == false then return end
local service = {}; MetaComic.CardBuyers = service
-- Small, independent settings rows; Settings caches these in server memory.
function service.setPayoutMultiplier(setId)
    local value=MetaComic.Settings and MetaComic.Settings.get('card_set_payout:'..tostring(setId),1)
    value=tonumber(value)
    return value and value==value and math.max(0.1,math.min(10,value)) or 1
end
local locked, lastMenu = {}, {}
local funds, active = nil, {}
local function option(buyer, key)
    if buyer[key] ~= nil then return buyer[key] end
    return cfg[key]
end
local function notify(source, message, kind) MetaComic.Framework.notify(source, message, kind or 'error') end
local function attempt(callback,...)
    local ok,result=pcall(callback,...)
    if not ok then print('[meta-comic] card buyer adapter failed: '..tostring(result)) end
    return ok and result==true
end
local function pool()
    if not funds then
        funds = MetaComic.Settings.get('card_buyer_funds', {})
        if type(funds) ~= 'table' then funds = {} end
    end
    return funds
end
-- Financial transactions save immediately; there is only one small balance per configured buyer.
local function saveFunds() return attempt(MetaComic.Settings.set,'card_buyer_funds',pool()) end
local function returnCard(source,meta)
    if attempt(MetaComic.Inventory.add,source,Config.Items.TradingCard,1,meta) then return ' Your card was returned.' end
    print(('[meta-comic] card buyer refund failed: player=%s instance=%s'):format(source,tostring(meta.instanceId)))
    return ' Your card could not be returned; contact an administrator.'
end
local function employee(source, buyer, funding)
    local job = MetaComic.Framework.getJob and MetaComic.Framework.getJob(source)
    local grade = job and (buyer.EmployeeJobs or {})[job.name]
    return grade ~= nil and grade ~= false and job.onDuty == true
        and (tonumber(job.grade) or 0) >= math.max(tonumber(grade) or 0, funding and (tonumber(option(buyer,'FundingMinGrade')) or 0) or 0)
end
function service.analysisBuyers(source)
    local analysis=cfg.Analysis or {}
    if analysis.Enabled==false then return {} end
    local admin=MetaComic.CanManage and MetaComic.CanManage(source)==true
    local job=MetaComic.Framework.getJob and MetaComic.Framework.getJob(source)
    local result={}
    for index,buyer in ipairs(cfg.Peds or {}) do
        local minimum=job and (buyer.EmployeeJobs or {})[job.name]
        if admin or (minimum~=nil and minimum~=false and (tonumber(job.grade) or 0)>=(tonumber(minimum) or 0)
            and (analysis.RequireDuty==false or job.onDuty==true)) then
            result[#result+1]={index=index,id=buyer.id or tostring(index),label=buyer.label or 'Card buyer'}
        end
    end
    return result
end
local function inBox(position, box)
    if MetaComic.CardBuyerZones then return MetaComic.CardBuyerZones.contains(position,box) end
    local c, size = box.coords, box.size
    if not c or not size then return false end
    local angle = math.rad(tonumber(box.heading) or 0)
    local dx, dy = position.x-c.x, position.y-c.y
    local x, y = dx*math.cos(angle)+dy*math.sin(angle), -dx*math.sin(angle)+dy*math.cos(angle)
    return math.abs(x)<=size.x/2 and math.abs(y)<=size.y/2 and math.abs(position.z-c.z)<=size.z/2
end
function service.available(buyer)
    if option(buyer,'HideWhenEmployeesPresent') == false then return true end
    for _, player in ipairs(GetPlayers()) do
        local source = tonumber(player)
        if employee(source,buyer) then
            local ped = GetPlayerPed(source)
            if ped and ped ~= 0 then
                local position = GetEntityCoords(ped)
                local checks = {}
                if buyer.Store and buyer.Store.coords then
                    local c = buyer.Store.coords
                    checks[#checks+1] = #(position-vector3(c.x,c.y,c.z)) <= (tonumber(buyer.Store.radius) or 20)
                end
                if buyer.Bounds then checks[#checks+1] = inBox(position,buyer.Bounds) end
                if #checks == 0 then
                    local c = buyer.coords
                    checks[1] = #(position-vector3(c.x,c.y,c.z)) <= 20
                end
                local present = buyer.PresenceMode == 'all'
                for _, check in ipairs(checks) do
                    if buyer.PresenceMode == 'all' then present = present and check else present = present or check end
                end
                if present then return false end
            end
        end
    end
    return true
end
local function near(source,buyer)
    if not buyer or not buyer.coords then return false end
    local ped = GetPlayerPed(source)
    if not ped or ped == 0 then return false end
    local c = buyer.coords
    return #(GetEntityCoords(ped)-vector3(c.x,c.y,c.z)) <= (tonumber(option(buyer,'Distance')) or 2)+1
end
local function snapshot(item)
    if not item or item.name ~= Config.Items.TradingCard then return nil end
    local meta = item.metadata or item.info or {}
    local card = type(meta.cardSnapshot)=='table' and meta.cardSnapshot
        or (meta.baseCardId and MetaComic.Cards.resolve(meta.baseCardId,meta.variantId))
    return card,meta
end
local function offsetLength(value)
    return type(value)=='table' and math.sqrt((tonumber(value[1]) or 0)^2+(tonumber(value[2]) or 0)^2) or 0
end
local function conditionFactor(buyer,card,meta)
    local settings=option(buyer,'ConditionPricing') or {}
    if settings.Enabled==false then return 1,'Condition pricing disabled',{} end
    local graded=type(card.graded)=='table' and card.graded or nil
    local grade=tonumber(graded and graded.grade)
    if grade then
        local multipliers=settings.GradeMultipliers or {[1]=0.15,[2]=0.25,[3]=0.35,[4]=0.45,[5]=0.55,[6]=0.65,[7]=0.8,[8]=1,[8.5]=1.15,[9]=1.4,[9.5]=1.75,[10]=2.5}
        grade=math.max(1,math.min(10,grade))
        local lo,hi=math.floor(grade),math.ceil(grade)
        local factor=tonumber(multipliers[grade]) or (lo==hi and 1 or ((tonumber(multipliers[lo]) or 1)*(hi-grade)+(tonumber(multipliers[hi]) or 1)*(grade-lo)))
        factor=math.max(0,factor)
        return factor,('Graded %s (%sx)'):format(grade,factor),{}
    end
    local condition=card.condition or meta.condition
    local grading=MetaComic.Grading
    if type(condition)~='table' or not grading then return 1,'No obvious defects',{} end
    local limits=settings.Obvious or {centeringFront=0.2,centeringBack=0.7,art=1.5,text=1.2,foil=3,foilHue=30,mask=1.6,wear=0.4}
    local severities=settings.MarkSeverity or {scratch=0.5,dent=0.7,crease=0.2,bend=0.4,tear=0.15,roller=0.7,printline=0.5,inkspot=0.7,stain=0.5}
    local lengths=settings.MinMarkLength or {scratch=12,crease=8,bend=10,tear=2,printline=20,roller=15}
    local visible,deduction={},0
    for _,flaw in ipairs(grading.listFlaws(condition,grading.flawOptions(card))) do
        local obvious=false
        if flaw.type=='centering' then
            local v=(condition.centering or {})[flaw.side] or {}
            obvious=math.max(math.abs(v[1] or 0),math.abs(v[2] or 0))>(limits[flaw.side=='front' and 'centeringFront' or 'centeringBack'] or 0.7)
        elseif flaw.type=='text' then
            local v=condition.text or {};if flaw.textPart then v=v[flaw.textPart] end
            obvious=offsetLength(v)>(limits.text or 1.2)
        elseif flaw.type=='art' or flaw.type=='mask' then obvious=offsetLength(condition[flaw.type])>(limits[flaw.type] or 1.6)
        elseif flaw.type=='foil' then obvious=offsetLength(condition.foil)>(limits.foil or 3) or math.abs((condition.foil or {})[3] or 0)>(limits.foilHue or 30)
        elseif flaw.type=='corner' or flaw.type=='edge' then
            local values=(condition[flaw.type=='corner' and 'corners' or 'edges'] or {})[flaw.side] or {}
            obvious=(values[(flaw.index or 0)+1] or 0)>(limits.wear or 0.4)
        elseif flaw.mark then
            local mark=flaw.mark
            local length=math.sqrt(((mark.x2 or mark.x1 or 0)-(mark.x1 or 0))^2+((mark.y2 or mark.y1 or 0)-(mark.y1 or 0))^2)
            obvious=(mark.s or 0)>=(severities[flaw.type] or 0.6) and length>=(lengths[flaw.type] or 0)
        end
        if obvious then visible[#visible+1]=flaw.label;deduction=deduction+(flaw.deduction or 0) end
    end
    local discount=math.min(math.max(0,tonumber(settings.MaxDiscount) or 0.8),deduction*math.max(0,tonumber(settings.DiscountPerGradePoint) or 0.08))
    return math.max(0,1-discount),#visible>0 and ('Obvious defects: -%d%%'):format(math.floor(discount*100+0.5)) or 'No obvious defects',visible
end
function service.valuation(buyer,card,meta,payoutOverride)
    meta=meta or {}
    if not card or (option(buyer,'AcceptManualPrints') ~= true and (card.manualPrint or meta.manualPrint)) then return nil end
    local minimum = math.max(1,math.floor(tonumber(option(buyer,'MinPrice')) or 1))
    local maximum = math.max(minimum,math.floor(tonumber(option(buyer,'MaxPrice')) or 1000))
    local base, variant = tostring(card.baseCardId or meta.baseCardId or card.id), tostring(card.variantId or meta.variantId)
    local fixed = option(buyer,'FixedPrices') or {}
    local override = tonumber(fixed[base..'::'..variant] or fixed[base])
    local fixedPrice=option(buyer,'FixedPricesEnabled')==true and override~=nil
    if fixedPrice and override<=0 then return nil end
    local rarity = tostring(card.rarityKey or card.rarity or meta.rarity or 'common'):lower():gsub('[%s%-]+','_')
    local multipliers=option(buyer,'RarityMultipliers')
    local price=multipliers and minimum*math.max(1,tonumber(multipliers[rarity]) or 1)
        or minimum+(maximum-minimum)*math.max(0,math.min(1,tonumber((option(buyer,'RarityScores') or {})[rarity]) or 0))
    local mode = option(buyer,'Pricing') or 'combined'
    if mode ~= 'rarity' then
        local odds = MetaComic.Cards.printOdds(card.setId or meta.setId)
        local chance, best = tonumber(odds[base..'::'..variant]), 0
        for _, value in pairs(odds) do best = math.max(best,tonumber(value) or 0) end
        if chance and chance>0 and best>0 then
            local oddsPrice=minimum*math.max(1,best/chance)^math.max(0,tonumber(option(buyer,'OddsExponent')) or 1)
            price = mode=='odds' and oddsPrice or math.max(price,oddsPrice)
        elseif mode=='odds' then price=minimum end
    end
    if not fixedPrice then
        local multiplier=payoutOverride or service.setPayoutMultiplier(card.setId or meta.setId or (MetaComic.Sets and MetaComic.Sets.defaultId()))
        price=price*multiplier
    end
    local uncapped=fixedPrice and option(buyer,'FixedPricesIgnoreMaximum')==true
    price=math.max(minimum,uncapped and override or math.min(maximum,fixedPrice and override or price))
    local factor,note,flaws=conditionFactor(buyer,card,meta)
    local population,populationFactor=0,1
    local populationConfig=option(buyer,'GradedPopulation') or {}
    if populationConfig.Enabled==true and MetaComic.CardBuyerStock and type(card.graded)=='table' then
        population=MetaComic.CardBuyerStock.population(card,meta)
        local reference=math.max(1,tonumber(populationConfig.ReferenceCount) or 4)
        populationFactor=math.max(tonumber(populationConfig.MinMultiplier) or 0.75,math.min(tonumber(populationConfig.MaxMultiplier) or 1.25,
            (reference/math.max(1,population))^math.max(0,tonumber(populationConfig.Exponent) or 0.35)))
    end
    factor=factor*populationFactor
    local adjusted=math.max(minimum,math.floor(price*factor+0.5+1e-9))
    if not uncapped then adjusted=math.min(maximum,adjusted) end
    return {price=adjusted,basePrice=math.floor(price+0.5),conditionFactor=factor,conditionNote=note,obviousFlaws=flaws,
        gradedPopulation=population,populationFactor=populationFactor}
end
function service.price(buyer,card,meta,payoutOverride)
    local value=service.valuation(buyer,card,meta,payoutOverride)
    return value and value.price or nil
end
local function getBuyer(index) return (cfg.Peds or {})[tonumber(index) or 0] end
local function key(buyer,index) return tostring(buyer.id or index) end
RegisterNetEvent('meta_comic:server:cardBuyerMenu',function(index)
    local source=source;local buyer=getBuyer(index)
    if not near(source,buyer) then return end
    if not service.available(buyer) then notify(source,'Employees are serving customers. Speak to a business employee.');return end
    if lastMenu[source] and GetGameTimer()-lastMenu[source]<1000 then return end
    lastMenu[source]=GetGameTimer()
    local offers={}
    for _,item in ipairs(MetaComic.Inventory.slotsOf(source,Config.Items.TradingCard) or {}) do
        local card,meta=snapshot(item);local price=service.price(buyer,card,meta)
        if price then
            offers[#offers+1]={slot=item.slot,price=price,instanceId=meta.instanceId or '',label=meta.label or card.title or 'Trading Card',count=item.count or item.amount or 1}
        end
    end
    if #offers==0 then notify(source,'You have no eligible trading cards in your pockets.');return end
    TriggerLatentClientEvent('meta_comic:client:cardBuyerMenu',source,25000,tonumber(index),offers,
        option(buyer,'RequireBusinessFunds')==true and (tonumber(pool()[key(buyer,index)]) or 0) or false)
end)
RegisterNetEvent('meta_comic:server:sellTradingCard',function(index,slot,expectedPrice,expectedInstance)
    local source=source;local buyer=getBuyer(index)
    if not near(source,buyer) or locked[source] then return end
    if not service.available(buyer) then notify(source,'Employees are serving customers. Speak to a business employee.');return end
    if buyer.SellArea and buyer.SellArea.Bounds and not inBox(GetEntityCoords(GetPlayerPed(source)),buyer.SellArea.Bounds) then
        notify(source,'Stand inside the selling counter area.');return
    end
    local id=key(buyer,index)
    if locked.funds then notify(source,'The buyer is finishing another transaction. Try again.');return end
    locked[source],locked[id],locked.funds=true,true,true
    local ok,err=pcall(function()
        local item=MetaComic.Inventory.getSlot(source,tonumber(slot))
        local card,meta=snapshot(item);local price=service.price(buyer,card,meta)
        if not price or price~=tonumber(expectedPrice) or tostring(meta.instanceId or '')~=tostring(expectedInstance or '') then
            notify(source,'The card or price changed. Open the buyer menu again.');return
        end
        local funded=option(buyer,'RequireBusinessFunds')==true
        local balance=tonumber(pool()[id]) or 0
        if funded and balance<price then notify(source,'The business has not supplied enough money for this purchase.');return end
        if not attempt(MetaComic.Inventory.removeExact or MetaComic.Inventory.remove,source,Config.Items.TradingCard,1,meta,item.slot) then notify(source,'The card could not be handed over.');return end
        local stock=MetaComic.CardBuyerStock
        local receipt=stock and stock.prepare(id,{{meta=meta,price=price}},source)
        if stock and not receipt then notify(source,'Could not record the business purchase.'..returnCard(source,meta));return end
        if funded then
            pool()[id]=balance-price
            if not saveFunds() then
                pool()[id]=balance
                if stock then stock.finish(receipt,false) end
                notify(source,'Could not save the business funds.'..returnCard(source,meta));return
            end
        end
        if not attempt(MetaComic.Money.add,source,option(buyer,'Account') or 'cash',price,'trading-card-buyback') then
            if stock then stock.finish(receipt,false) end
            if funded then
                pool()[id]=balance
                if not saveFunds() then MetaComic.Settings.stage('card_buyer_funds',pool()) end
            end
            notify(source,'Payment failed.'..returnCard(source,meta));return
        end
        if stock then stock.finish(receipt,true) end
        notify(source,('Sold %s for $%d.'):format(meta.label or card.title or 'Trading Card',price),'success')
    end)
    locked[source],locked[id],locked.funds=nil,nil,nil
    if not ok then print('[meta-comic] card buyer transaction failed: '..tostring(err));notify(source,'The buyer could not complete the transaction.') end
end)
RegisterCommand(cfg.FundCommand or 'fundcardbuyer',function(source,args)
    if source<=0 then return end
    local index=tonumber(args[1]);local buyer=getBuyer(index)
    local amount=math.floor(tonumber(args[2]) or 0)
    if not near(source,buyer) or not employee(source,buyer,true) then notify(source,'Only an on-duty business employee at this buyer can deposit money.');return end
    if amount<=0 or amount>100000000 then notify(source,'Use /'..(cfg.FundCommand or 'fundcardbuyer')..' <buyer number> <amount>.');return end
    local id=key(buyer,index)
    if locked.funds or locked[source] then notify(source,'Another transaction is in progress.');return end
    locked[id],locked[source],locked.funds=true,true,true
    local ok,err=pcall(function()
        local balance=tonumber(pool()[id]) or 0
        if not attempt(MetaComic.Money.remove,source,option(buyer,'FundingAccount') or 'bank',amount,'card-buyer-funding') then notify(source,'You do not have enough money to deposit.');return end
        pool()[id]=balance+amount
        if not saveFunds() then
            pool()[id]=balance
            if not attempt(MetaComic.Money.add,source,option(buyer,'FundingAccount') or 'bank',amount,'card-buyer-refund') then
                print(('[meta-comic] card buyer deposit refund failed: player=%s amount=%d'):format(source,amount))
            end
            notify(source,'Could not save the deposit.');return
        end
        notify(source,('Deposited $%d. Buyer balance: $%d.'):format(amount,pool()[id]),'success')
    end)
    locked[id],locked[source],locked.funds=nil,nil,nil
    if not ok then print('[meta-comic] card buyer funding failed: '..tostring(err)) end
end,false)
RegisterNetEvent('meta_comic:server:cardBuyerStatus',function()
    local source=source
    for index,buyer in ipairs(cfg.Peds or {}) do active[index]=service.available(buyer) end
    TriggerClientEvent('meta_comic:client:cardBuyerStatus',source,active)
end)
CreateThread(function()
    while true do
        local changed=false
        for index,buyer in ipairs(cfg.Peds or {}) do
            local available=service.available(buyer)
            if active[index]~=available then active[index]=available;changed=true end
        end
        if changed then TriggerClientEvent('meta_comic:client:cardBuyerStatus',-1,active) end
        Wait(math.max(1000,tonumber(cfg.CheckInterval) or 3000))
    end
end)
AddEventHandler('playerDropped',function() lastMenu[source]=nil end)

-- A quote describes server-owned slots. The cart moves no inventory until the whole sale commits.
local quotes={}
local function same(a,b)
    if type(a)~=type(b) then return false end
    if type(a)~='table' then return a==b end
    for k,v in pairs(a) do if not same(v,b[k]) then return false end end
    for k in pairs(b) do if a[k]==nil then return false end end
    return true
end
function service.ui(source,payload)
    local index=tonumber(payload.index);local buyer=getBuyer(index)
    if not near(source,buyer) then return {ok=false,error='Approach the buyer first.'} end
    if not service.available(buyer) then return {ok=false,error='Speak to a business employee while they are serving customers.'} end
    local offers,locations,holders={},{},{}
    local function add(item,location,holderSlot,container)
        local card,meta=snapshot(item);local valuation=service.valuation(buyer,card,meta);local price=valuation and valuation.price
        if not card then return end
        local ref=location..':'..tostring(item.slot)
        locations[ref]={slot=item.slot,holderSlot=holderSlot,container=container,meta=MetaComic.CopyTable(meta),price=price}
        offers[#offers+1]={ref=ref,slot=item.slot,location=location,card=MetaComic.CopyTable(card),label=meta.label or card.title or 'Trading Card',
            price=price or false,valuation=valuation,reason=not price and 'This buyer does not accept this card' or nil}
    end
    for _,item in ipairs(MetaComic.Inventory.slotsOf(source,Config.Items.TradingCard) or {}) do add(item,'hand') end
    if MetaComic.Inventory.getContainer then
        for _,kind in ipairs({'Binder','CardCase'}) do
            local names=Config.Items[kind];if type(names)=='string' then names={names} end
            for _,name in ipairs(names or {}) do
                for _,holder in ipairs(MetaComic.Inventory.slotsOf(source,name) or {}) do
                    local container=MetaComic.Inventory.getContainer(source,holder.slot)
                    if container and container.id then
                        local location='holder:'..holder.slot
                        holders[#holders+1]={id=location,kind=kind=='Binder' and 'binder' or 'case',label=(holder.metadata or holder.info or {}).label or holder.label or kind,
                            slots=container.slots or 36}
                        for slot,item in pairs(container.items or {}) do
                            if type(item)=='table' then item.slot=item.slot or tonumber(slot);add(item,location,holder.slot,container.id) end
                        end
                    end
                end
            end
        end
    end
    local token=('%s:%s:%s'):format(source,GetGameTimer(),math.random(100000,999999))
    quotes[source]={token=token,index=index,locations=locations,expires=os.time()+math.max(30,tonumber(cfg.QuoteSeconds) or 300)}
    return {ok=true,index=index,token=token,label=buyer.label or 'Trading card buyer',offers=offers,holders=holders,
        balance=option(buyer,'RequireBusinessFunds')==true and (tonumber(pool()[key(buyer,index)]) or 0) or false,
        maxCards=tonumber(cfg.MaxCartCards) or 60,sellArea=buyer.SellArea}
end
local function cart(source,payload)
    local quote=quotes[source];local buyer=quote and getBuyer(quote.index)
    if not quote or payload.token~=quote.token or quote.expires<os.time() then return nil,'Your quote expired. Refresh the inventory.' end
    if not near(source,buyer) then return nil,'You moved away from the buyer.' end
    if not service.available(buyer) then return nil,'Employees are serving customers. Speak to an employee.' end
    if buyer.SellArea and buyer.SellArea.Bounds and not inBox(GetEntityCoords(GetPlayerPed(source)),buyer.SellArea.Bounds) then return nil,'Stand inside the selling counter area.' end
    local refs=payload.refs
    if type(refs)~='table' or #refs<1 or #refs>math.max(1,tonumber(cfg.MaxCartCards) or 60) then return nil,'Select a valid number of cards.' end
    local selected,seen,total={},{},0
    for _,ref in ipairs(refs) do
        local location=quote.locations[ref]
        if not location or seen[ref] or not location.price then return nil,'The selected cards are invalid. Refresh the inventory.' end
        seen[ref]=true
        local inv=source
        if location.holderSlot then
            -- The caller must still possess the exact binder/case; a guessed container ID is never accepted.
            local container=MetaComic.Inventory.getContainer(source,location.holderSlot)
            if not container or container.id~=location.container then return nil,'A selected binder or case moved. Refresh the inventory.' end
            inv=container.id
        end
        local item=MetaComic.Inventory.getSlot(inv,location.slot)
        local card,meta=snapshot(item)
        if not card or not same(meta,location.meta) or service.price(buyer,card,meta)~=location.price then return nil,'A card or its price changed. Refresh and review the sale again.' end
        total=total+location.price
        selected[#selected+1]={inv=inv,slot=location.slot,meta=meta,price=location.price}
    end
    local id=key(buyer,quote.index)
    if option(buyer,'RequireBusinessFunds')==true and (tonumber(pool()[id]) or 0)<total then return nil,'The business cannot afford the whole pile.' end
    return {buyer=buyer,id=id,total=total,selected=selected,quote=quote}
end
function service.checkCart(source,payload)
    local data,err=cart(source,payload)
    if not data then return {ok=false,error=err} end
    return {ok=true,total=data.total,count=#data.selected,sellArea=data.buyer.SellArea}
end
function service.sellCart(source,payload)
    if locked.funds or locked[source] then return {ok=false,error='Another transaction is in progress. Try again.'} end
    locked.funds,locked[source]=true,true
    local removed,data,funded,balance={},nil,false,0
    local stock,receipt=MetaComic.CardBuyerStock,nil
    local function refund()
        if stock and receipt then stock.finish(receipt,false);receipt=nil end
        for _,item in ipairs(removed) do
            if not attempt(MetaComic.Inventory.add,item.inv,Config.Items.TradingCard,1,item.meta) then
                -- If the holder disappeared while an adapter yielded, return to the player's pockets.
                if not attempt(MetaComic.Inventory.add,source,Config.Items.TradingCard,1,item.meta) then
                    print(('[meta-comic] cart refund failed: player=%s instance=%s'):format(source,tostring(item.meta.instanceId)))
                end
            end
        end
        removed={}
    end
    local ok,result=pcall(function()
        local err;data,err=cart(source,payload)
        if not data then return {ok=false,error=err} end
        for _,item in ipairs(data.selected) do
            if not attempt(MetaComic.Inventory.removeExact or MetaComic.Inventory.remove,item.inv,Config.Items.TradingCard,1,item.meta,item.slot) then
                refund();return {ok=false,error='A card could not be handed over. No sale was made; refresh the inventory.'}
            end
            removed[#removed+1]=item
        end
        receipt=stock and stock.prepare(data.id,data.selected,source)
        if stock and not receipt then refund();return {ok=false,error='Could not record the business purchase. No sale was made.'} end
        funded=option(data.buyer,'RequireBusinessFunds')==true
        balance=tonumber(pool()[data.id]) or 0
        if funded then
            pool()[data.id]=balance-data.total
            if not saveFunds() then pool()[data.id]=balance;refund();return {ok=false,error='Could not save the buyer balance. No sale was made.'} end
        end
        if not attempt(MetaComic.Money.add,source,option(data.buyer,'Account') or 'cash',data.total,'trading-card-cart') then
            if funded then pool()[data.id]=balance;if not saveFunds() then MetaComic.Settings.stage('card_buyer_funds',pool()) end end
            refund();return {ok=false,error='Payment failed. No sale was made; refresh the inventory.'}
        end
        removed={};quotes[source]=nil
        if stock then stock.finish(receipt,true);receipt=nil end
        return {ok=true,total=data.total,count=#data.selected}
    end)
    if not ok then
        refund()
        print('[meta-comic] cart sale failed: '..tostring(result))
        result={ok=false,error='The sale could not complete. Refresh your inventory.'}
    end
    locked.funds,locked[source]=nil,nil
    return result
end
if MetaComic.RpcHandlers then
    MetaComic.RpcHandlers.getCardBuyerUI=service.ui
    MetaComic.RpcHandlers.checkCardBuyerCart=service.checkCart
    MetaComic.RpcHandlers.sellCardBuyerCart=service.sellCart
end
AddEventHandler('playerDropped',function() quotes[source]=nil end)

local function stockManager(source,buyer)
    local settings=option(buyer,'Stock') or {}
    local job=MetaComic.Framework.getJob and MetaComic.Framework.getJob(source)
    return MetaComic.CardBuyerStock and near(source,buyer) and employee(source,buyer,false)
        and (tonumber(job and job.grade) or 0)>=(tonumber(settings.ManagementMinGrade) or 2)
end
local function stockPage(source,index,page)
    local buyer=getBuyer(index)
    if not buyer or not stockManager(source,buyer) then notify(source,'Only an on-duty business manager at this buyer can access purchased cards.');return end
    local settings=option(buyer,'Stock') or {}
    local size=math.max(1,math.min(50,tonumber(settings.PageSize) or 20))
    page=math.max(1,math.floor(tonumber(page) or 1))
    local rows,total=MetaComic.CardBuyerStock.page(key(buyer,index),page,size)
    TriggerLatentClientEvent('meta_comic:client:cardBuyerStock',source,25000,index,rows,page,math.max(1,math.ceil(total/size)),total)
end
RegisterCommand((cfg.Stock or {}).Command or 'cardbuyerstock',function(source,args)
    if source>0 then stockPage(source,tonumber(args[1]) or 1,args[2]) end
end,false)
RegisterNetEvent('meta_comic:server:cardBuyerStock',function(index,page) stockPage(source,tonumber(index),page) end)
RegisterNetEvent('meta_comic:server:retrieveBuyerCard',function(index,id,page)
    local source=source;local buyer=getBuyer(index)
    if not buyer or not stockManager(source,buyer) then notify(source,'You cannot access this business stock.');return end
    if locked.funds or locked[source] then notify(source,'Another transaction is in progress.');return end
    locked.funds,locked[source]=true,true
    local ok,success,message=pcall(MetaComic.CardBuyerStock.retrieve,source,key(buyer,index),tostring(id))
    locked.funds,locked[source]=nil,nil
    notify(source,ok and message or 'Could not retrieve the card.',ok and success and 'success' or 'error')
    if ok and success then stockPage(source,index,page) end
end)
