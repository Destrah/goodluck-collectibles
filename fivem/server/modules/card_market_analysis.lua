-- Server-authoritative payout settings and read-only projections. Never issue inventory, grades, certificates or change observed population.
local service={};MetaComic.CardMarketAnalysis=service
local cache,busy={},{}
local function canAdjust(source)
    local ace=((Config.CardBuyers or {}).Analysis or {}).PayoutAce or (Config.Management or {}).Ace or 'metacomic.manage'
    return type(ace)=='string' and ace~='' and IsPlayerAceAllowed(source,ace)==true
end
local function validMultiplier(value)
    return type(value)=='number' and value==value and value>=0.1 and value<=10
end
local function allowed(source,index)
    if not MetaComic.CardBuyers then return false end
    for _,buyer in ipairs(MetaComic.CardBuyers.analysisBuyers(source)) do if buyer.index==index then return true end end
    return false
end
local function rng(seed)
    return function(a,b)
        seed=(seed*48271)%2147483647
        local value=seed/2147483647
        if a then if not b then b=a;a=1 end;return a+math.floor(value*(b-a+1)) end
        return value
    end
end
local function summary(values,exactMean,exactVariance)
    table.sort(values)
    local sum,squares,histogram=0,0,{}
    for _,v in ipairs(values) do sum=sum+v;squares=squares+v*v;histogram[v]=(histogram[v] or 0)+1 end
    local n=#values;local mean=sum/n
    local variance=math.max(0,(squares-sum*sum/n)/math.max(1,n-1))
    local error=1.96*math.sqrt(variance/n);local bins={}
    for value,count in pairs(histogram) do bins[#bins+1]={value=value,count=count} end
    table.sort(bins,function(a,b) return a.value<b.value end)
    return {mean=exactMean or mean,variance=exactVariance or variance,standardDeviation=math.sqrt(exactVariance or variance),
        exact=exactMean~=nil,sampleMean=mean,confidence95={mean-error,mean+error},samples=n,min=values[1],max=values[n],
        p10=values[math.max(1,math.ceil(n*.1))],median=values[math.ceil(n*.5)],p90=values[math.ceil(n*.9)],histogram=bins}
end
function service.calculate(buyer,setId,samples,payoutMultiplier)
    payoutMultiplier=payoutMultiplier or MetaComic.CardBuyers.setPayoutMultiplier(setId)
    local slots=MetaComic.Cards.packDistribution(setId)
    if slots then slots=MetaComic.CopyTable(slots) end
    if not slots then return nil,'This set has no pullable cards.' end
    samples=math.max(100,math.min(5000,math.floor(tonumber(samples) or 2000)))
    local random=rng(17017);local prints,byPrint,details={}, {}, {}
    local mean,variance=0,0
    local gradeValues={};for _,grade in ipairs({1,5,8,9,9.5,10}) do gradeValues[#gradeValues+1]={grade=grade,mean=0} end
    for _,slot in ipairs(slots) do
        local slotMean,slotSquare=0,0
        for _,outcome in ipairs(slot.outcomes) do
            local card=outcome.card
            card.condition=nil;card.graded=nil
            outcome.price=MetaComic.CardBuyers.price(buyer,card,{},payoutMultiplier) or 0
            slotMean=slotMean+outcome.chance*outcome.price;slotSquare=slotSquare+outcome.chance*outcome.price^2
            local key=card.cardKey
            if not byPrint[key] then
                local row={key=key,label=card.title,variant=card.variantName,rarity=card.rarityKey,expectedCopies=0,cleanPrice=outcome.price,
                    grades={}}
                byPrint[key]=row;prints[#prints+1]=row
                for _,gradeValue in ipairs(gradeValues) do
                    card.graded={grade=gradeValue.grade}
                    local value=MetaComic.CardBuyers.valuation(buyer,card,{},payoutMultiplier)
                    row.grades[#row.grades+1]={grade=gradeValue.grade,price=value and value.price or 0,population=value and value.gradedPopulation or 0}
                end
                card.graded=nil
            end
            local row=byPrint[key];row.expectedCopies=row.expectedCopies+slot.count*outcome.chance
            for i,gradeValue in ipairs(gradeValues) do gradeValue.mean=gradeValue.mean+slot.count*outcome.chance*row.grades[i].price end
        end
        details[#details+1]={label=slot.label,count=slot.count,tier=slot.tier,mean=slotMean*slot.count}
        mean=mean+slot.count*slotMean;variance=variance+slot.count*(slotSquare-slotMean^2)
    end
    local clean,fresh,graded,gradeCounts={}, {}, {}, {}
    for sample=1,samples do
        local cleanTotal,freshTotal,gradedTotal=0,0,0
        for _,slot in ipairs(slots) do for _=1,slot.count do
            local roll=random();local outcome=slot.outcomes[#slot.outcomes]
            for _,candidate in ipairs(slot.outcomes) do roll=roll-candidate.chance;if roll<=0 then outcome=candidate;break end end
            if not outcome then return nil,'A pack slot has no valid print.' end
            local card=outcome.card;card.graded=nil
            card.condition=MetaComic.Grading.generate(random)
            cleanTotal=cleanTotal+outcome.price
            freshTotal=freshTotal+(MetaComic.CardBuyers.price(buyer,card,{},payoutMultiplier) or 0)
            local grade=MetaComic.Grading.gradeFromFlaws(MetaComic.Grading.listFlaws(card.condition,MetaComic.Grading.flawOptions(card)))
            gradeCounts[grade]=(gradeCounts[grade] or 0)+1
            card.graded={grade=grade}
            gradedTotal=gradedTotal+(MetaComic.CardBuyers.price(buyer,card,{},payoutMultiplier) or 0)
            card.graded=nil;card.condition=nil
        end end
        clean[sample],fresh[sample],graded[sample]=cleanTotal,freshTotal,gradedTotal
        if sample%100==0 then Wait(0) end
    end
    table.sort(prints,function(a,b) return a.expectedCopies*a.cleanPrice>b.expectedCopies*b.cleanPrice end)
    local gradeDistribution={};for grade,count in pairs(gradeCounts) do gradeDistribution[#gradeDistribution+1]={grade=grade,chance=count/(samples*5)} end
    table.sort(gradeDistribution,function(a,b) return a.grade>b.grade end)
    return {setId=setId,clean=summary(clean,mean,math.max(0,variance)),fresh=summary(fresh),graded=summary(graded),gradeScenarios=gradeValues,
        gradeDistribution=gradeDistribution,prints=prints,slots=details,samples=samples,populationHeldConstant=true,calculatedAt=os.time(),
        packsPerBox=math.max(1,tonumber((Config.Items or {}).PacksPerBox) or 12)}
end
function service.options(source)
    local buyers=MetaComic.CardBuyers and MetaComic.CardBuyers.analysisBuyers(source) or {}
    if #buyers==0 then return {ok=false,error='Pricing analysis requires collectibles management or an authorized card-buyer employee job.'} end
    local result=MetaComic.RpcHandlers.getSets(source)
    if not result.ok then return result end
    local sets={};for _,set in ipairs(result.sets or {}) do sets[#sets+1]={id=set.id,name=set.name,code=set.code,cardCount=#(set.cardIds or {})} end
    return {ok=true,buyers=buyers,sets=sets,canAdjustPayouts=canAdjust(source)}
end
function service.report(source,payload)
    payload=type(payload)=='table' and payload or {}
    local index=tonumber(payload.index)
    if not allowed(source,index) then return {ok=false,error='You cannot analyze this buyer.'} end
    local defs=MetaComic.RpcHandlers.getSets(source);if not defs.ok then return defs end
    local setId=tostring(payload.setId or '')
    if not MetaComic.Sets.get(setId) then return {ok=false,error='Choose a valid card set.'} end
    local savedMultiplier=MetaComic.CardBuyers.setPayoutMultiplier(setId)
    local multiplier=savedMultiplier
    if payload.previewMultiplier~=nil then
        if not canAdjust(source) then return {ok=false,error='Only collectibles administrators can adjust payouts.'} end
        if not validMultiplier(payload.previewMultiplier) then return {ok=false,error='Payout must be between 10% and 1000%.'} end
        multiplier=payload.previewMultiplier
    end
    local cfg=Config.CardBuyers;local buyer=cfg.Peds[index];local analysis=cfg.Analysis or {}
    local key=tostring(index)..':'..setId
    local signature=tostring(multiplier)..":"..tostring(savedMultiplier)..":"..tostring(payload.previewMultiplier~=nil)..":"..tostring(MetaComic.Cards.printOdds(setId))..json.encode({cfg,buyer})..tostring(MetaComic.CardBuyerStock and MetaComic.CardBuyerStock.version or 0)
    local previous=cache[key]
    if previous and previous.signature==signature and os.time()-previous.at<math.max(0,tonumber(analysis.CacheSeconds) or 120) then return {ok=true,report=previous.report} end
    local pending=busy[key]
    if pending then
        -- Join the existing calculation rather than fail duplicate NUI requests.
        while not pending.done do Wait(50) end
        if pending.signature==signature then return pending.result end
        return service.report(source,payload)
    end
    local job={signature=signature};busy[key]=job
    local ok,report,err=pcall(service.calculate,buyer,setId,analysis.SamplePacks,multiplier)
    local function finish(result)
        job.result=result;job.done=true
        if busy[key]==job then busy[key]=nil end
        return result
    end
    if not ok then print('[meta-comic] pricing analysis failed: '..tostring(report));return finish({ok=false,error='Could not calculate pack pricing.'}) end
    if not report then return finish({ok=false,error=err}) end
    report.payoutMultiplier=multiplier;report.savedPayoutMultiplier=savedMultiplier;report.payoutPreview=payload.previewMultiplier~=nil
    local set=MetaComic.Sets.get(setId);report.setName=set.name;report.buyerName=buyer.label or 'Card buyer'
    for _,product in ipairs(((Config.VendingMachines or {}).Shop or {}).Items or {}) do
        if (product.set or MetaComic.Sets.defaultId())==setId and product.kind~='box' then report.defaultPackPrice=product.price;break end
    end
    cache[key]={signature=signature,at=os.time(),report=report}
    return finish({ok=true,report=report})
end
MetaComic.RpcHandlers.getCardMarketOptions=service.options
MetaComic.RpcHandlers.getCardMarketAnalysis=service.report

MetaComic.RpcHandlers.saveCardSetPayout=function(source,payload)
    if not canAdjust(source) then return {ok=false,error='Only collectibles administrators can adjust payouts.'} end
    payload=type(payload)=='table' and payload or {}
    local setId=tostring(payload.setId or '')
    if not MetaComic.Sets.get(setId) then return {ok=false,error='Choose a valid card set.'} end
    if not validMultiplier(payload.multiplier) then return {ok=false,error='Payout must be between 10% and 1000%.'} end
    local ok,err=MetaComic.Settings.set('card_set_payout:'..setId,payload.multiplier)
    if not ok then return {ok=false,error=err or 'Could not save payout adjustment.'} end
    cache={}
    return {ok=true,multiplier=payload.multiplier}
end
