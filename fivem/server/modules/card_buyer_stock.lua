-- One durable receipt per card, never an unbounded settings JSON. Runtime indexes serve browsing and pricing.
local cfg=(Config.CardBuyers or {}).Stock or {}
if cfg.Enabled==false then return end
local service={};MetaComic.CardBuyerStock=service
service.version=0
local records,populations,seen,loaded,loading={}, {}, {}, false,false
local resource=GetCurrentResourceName()
local tableName='goodluck_collectibles_card_buyer_stock'
local useMysql=MetaComic.Persistence.name=='mysql'
local function db() return exports[Config.Database.Resource or 'oxmysql'] end
local function countRow(row)
        if row.state=='available' or row.state=='withdrawn' or row.state=='withdrawing' then
            local card=row.meta.cardSnapshot or {}
            local grade=tonumber((card.graded or {}).grade)
            local identity=row.meta.instanceId or card.instanceId or (card.graded or {}).cert
            if grade and identity then
                local key=tostring(card.baseCardId or row.meta.baseCardId or card.id)..'::'..tostring(card.variantId or row.meta.variantId)..'::'..grade
                local unique=key..'::'..tostring(identity)
                if not seen[unique] then populations[key]=(populations[key] or 0)+1;seen[unique]=true end
            end
        end
end
local function rebuild()
    populations,seen={},{}
    local processed=0
    for _,row in pairs(records) do
        countRow(row);processed=processed+1
        if processed%100==0 then Wait(0) end
    end
end
local function load()
    if loaded then return end
    if loading then while loading do Wait(0) end;if loaded then return end end
    loading=true
    local ok,err=pcall(function()
        if useMysql then
            if Config.Database.AutoCreateSchema then
                assert(db():query_async(('CREATE TABLE IF NOT EXISTS `%s` (receipt_id VARCHAR(100) COLLATE utf8mb4_bin PRIMARY KEY,buyer_id VARCHAR(100) NOT NULL,state VARCHAR(20) NOT NULL,purchased_at BIGINT NOT NULL,data_json LONGTEXT NOT NULL,INDEX buyer_state (buyer_id,state,purchased_at)) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4'):format(tableName)), 'Could not create buyer stock table')
            end
            local rows=assert(db():query_async(('SELECT data_json FROM `%s`'):format(tableName)),'Could not load buyer stock')
            for index,entry in ipairs(rows) do
                local row=json.decode(entry.data_json);records[row.id]=row
                if index%100==0 then Wait(0) end
            end
        else
            local handle=StartFindKvp('metacomic_buyer_stock:')
            if handle and handle~=-1 then
                local processed=0
                while true do local key=FindKvp(handle);if not key then break end
                    local row=json.decode(GetResourceKvpString(key));records[row.id]=row
                    processed=processed+1;if processed%100==0 then Wait(0) end
                end
                EndFindKvp(handle)
            end
        end
        if MetaComic.RuntimeSaves then
            for id,row in pairs(MetaComic.RuntimeSaves.pending('card_buyer_stock')) do records[id]=row end
        end
        rebuild();loaded=true
    end)
    loading=false
    if not ok then error('Could not load buyer stock: '..tostring(err)) end
end
local function write(_,row)
    if useMysql then
        assert(db():query_async(('INSERT INTO `%s` (receipt_id,buyer_id,state,purchased_at,data_json) VALUES (?,?,?,?,?) ON DUPLICATE KEY UPDATE state=VALUES(state),data_json=VALUES(data_json)'):format(tableName),{row.id,row.buyer,row.state,row.at,json.encode(row)}),'Could not save buyer stock')
    else SetResourceKvp('metacomic_buyer_stock:'..row.id,json.encode(row)) end
    return true
end
if MetaComic.RuntimeSaves then MetaComic.RuntimeSaves.register('card_buyer_stock',write) end
local function save(row)
    records[row.id]=row
    local queue=MetaComic.RuntimeSaves
    if queue then
        queue.mark('card_buyer_stock',row.id,MetaComic.CopyTable(row))
        local ok=queue.immediate('card_buyer_stock',row.id,function() return write(row.id,row) end)
        if not ok then queue.checkpoint() end
        return ok
    end
    local ok,result=pcall(write,row.id,row);return ok and result==true
end
function service.population(card,meta)
    load()
    local grade=tonumber((card.graded or {}).grade)
    if not grade then return 0 end
    return populations[tostring(card.baseCardId or meta.baseCardId or card.id)..'::'..tostring(card.variantId or meta.variantId)..'::'..grade] or 0
end
function service.prepare(buyer,items,source)
    load();local batch={}
    for _,item in ipairs(items) do
        local id=('%d-%d-%d-%09d'):format(os.time(),GetGameTimer(),source,math.random(1,999999999))
        while records[id] do id=id..'x' end
        local row={id=id,buyer=buyer,state='pending',at=os.time(),price=item.price,meta=MetaComic.CopyTable(item.meta)}
        batch[#batch+1]=row
        if not save(row) then service.finish(batch,false);return nil end
    end
    return batch
end
function service.finish(batch,success)
    for _,row in ipairs(batch or {}) do row.state=success and 'available' or 'cancelled';save(row);if success then countRow(row) end end
    if success then service.version=service.version+1 end
end
function service.page(buyer,page,size)
    load();local items={}
    for _,row in pairs(records) do if row.buyer==buyer and row.state=='available' then items[#items+1]=row end end
    table.sort(items,function(a,b) if a.at==b.at then return a.id>b.id end;return a.at>b.at end)
    local count=#items;local result={}
    for i=(page-1)*size+1,math.min(page*size,count) do
        local row=items[i];local card=row.meta.cardSnapshot or {}
        result[#result+1]={id=row.id,label=row.meta.label or card.title or 'Trading card',price=row.price,at=row.at,grade=(card.graded or {}).grade}
    end
    return result,count
end
function service.retrieve(source,buyer,id)
    load();local row=records[id]
    if not row or row.buyer~=buyer or row.state~='available' then return false,'That card is no longer in business stock.' end
    row.state='withdrawing'
    if not save(row) then row.state='available';save(row);return false,'Could not save the stock withdrawal.' end
    local ok,added=pcall(MetaComic.Inventory.add,source,Config.Items.TradingCard,1,MetaComic.CopyTable(row.meta))
    if not ok or added~=true then row.state='available';save(row);return false,'Make room in your inventory for this card.' end
    row.state='withdrawn';row.withdrawnAt=os.time();save(row)
    return true,'Card retrieved with its original condition, grade and certificate.'
end
