-- Generic object definitions/sets are separate from card prints and immutable inventory snapshots.
MetaComic.Objects = {data = {definitions={}, sets={}, containers={}, instances={}, sealed={}}}
local service = MetaComic.Objects
local types = {
 plushie={item='collectible_plushie',inner='plushie_box',outer='plushie_case'},
 challenge_coin={item='challenge_coin',inner='coin_bag',outer='coin_bag_box'},
}
Config.Collectibles = Config.Collectibles or {}
for id, defaults in pairs(types) do
 local configured = Config.Collectibles[id] or {}
 for key,value in pairs(defaults) do defaults[key] = configured[key] or value end
 MetaComic.Collectables.registerType(id,{label=id,itemName=defaults.item,snapshotVersion=1})
end
service.types = types
local resource = GetCurrentResourceName()
local function query(sql,params) return exports[Config.Database.Resource or 'oxmysql']:query_async(sql,params or {}) end
local function transaction(statements)
 if not exports[Config.Database.Resource or 'oxmysql']:transaction_async(statements) then error('Collectible database write rolled back') end
end
local function statement(sql,values) return {query=sql,values=values or {}} end
local function copy(value) return MetaComic.CopyTable(value) end
local function decode(raw) if type(raw)=='table' then return copy(raw) end;local value=json.decode(raw); assert(type(value)=='table','Invalid collectible JSON');return value end
local function find(list,id) for _,item in ipairs(list) do if item.id==id then return item end end end

-- Rarity tiers shared with the trading cards.
local RARITY_LABELS={common='Common',uncommon='Uncommon',rare='Rare',ultra_rare='Ultra Rare',legendary='Legendary'}
local function rarityKeyOf(value)
 if type(value)~='string' then return 'common' end
 local key=value:lower():gsub('[%s%-]+','_')
 return RARITY_LABELS[key] and key or 'common'
end
local function weightOf(entry) return math.max(1,tonumber(entry.chanceWeight) or 1) end
local function weightedPick(list)
 local total=0;for _,entry in ipairs(list) do total=total+weightOf(entry) end
 local roll=math.random()*total
 for _,entry in ipairs(list) do roll=roll-weightOf(entry);if roll<=0 then return entry end end
 return list[#list]
end
-- A collectible's prints (versions: accent, finish, stitching, colours, rarity...). Definitions saved before prints
-- existed behave as one "Standard" print of themselves.
local function printsOf(item)
 if type(item.prints)=='table' and #item.prints>0 then return item.prints end
 return {{id='base',name='Standard',chanceWeight=1,rarityKey=rarityKeyOf(item.rarityKey or item.rarity)}}
end
-- The snapshot a pulled collectible carries: the definition with its print's fields laid over it
-- (an empty print field inherits the definition's value).
local function withPrint(item,print)
 local merged=copy(item);merged.prints=nil
 for key,value in pairs(print) do if key~='id' and key~='name' and value~=nil and value~='' then merged[key]=type(value)=='table' and copy(value) or value end end
 merged.definitionId=item.id;merged.printId=print.id or 'base';merged.printName=print.name or 'Standard'
 merged.rarityKey=rarityKeyOf(print.rarityKey or item.rarityKey or item.rarity);merged.rarity=RARITY_LABELS[merged.rarityKey]
 merged.chanceWeight=item.chanceWeight
 return merged
end
service.withPrint=withPrint

-- every definition + print, for the inventory icon pipeline in server/main.lua
function service.iconPrints()
 local list={}
 for _,item in ipairs(service.data.definitions) do
  if types[item.collectableType] then
   for _,print in ipairs(printsOf(item)) do local snap=withPrint(item,print);snap.collectableType=item.collectableType;list[#list+1]=snap end
  end
 end
 return list
end

-- metadata stored on a coin / plushie inventory item: the snapshot is what the game UI renders
local function collectibleMetadata(typeId,snapshot)
 local imageurl,image
 if service.icon then imageurl,image=service.icon(snapshot) end
 local printPart=snapshot.printName and snapshot.printName~='Standard' and (' ('..snapshot.printName..')') or ''
 return {instanceId=snapshot.instanceId,collectableType=typeId,label=(snapshot.title or 'Collectible')..printPart,
  description=('%s · %s'):format(snapshot.rarity or 'Common',snapshot.printName or 'Standard')..(snapshot.description and snapshot.description~='' and ('\n'..snapshot.description) or ''),
  rarity=snapshot.rarity,rarityKey=snapshot.rarityKey,printName=snapshot.printName,imageurl=imageurl,image=image,collectibleSnapshot=copy(snapshot)}
end
local function validType(id) assert(types[id],'Unknown collectible type');return types[id] end
local function bounded(value,max) local n=tonumber(value); assert(n and n==n and n>=1 and n<=max and n%1==0,'Invalid container count');return n end
local function validId(id) assert(type(id)=='string' and #id>0 and #id<=80 and id:match('^[%w_-]+$'),'Invalid collectible id') end
local function replace(list,item) local next={};for _,entry in ipairs(list) do if entry.id~=item.id then next[#next+1]=entry end end;next[#next+1]=copy(item);return next end
local function persistJson(next)
 assert(SaveResourceFile(resource,'data/collectibles.json',json.encode(next),-1),'Could not save collectibles.json')
end

function service.init()
 local next={definitions={},sets={},containers={},instances={},sealed={}}
 if MetaComic.Persistence.name=='mysql' then
  if Config.Database.AutoCreateSchema then
   local schema=assert(LoadResourceFile(resource,'data/collectibles.sql'),'Missing data/collectibles.sql')
   for sql in schema:gmatch('[^;]+') do if sql:match('%S') then query(sql) end end
  end
  for _,row in ipairs(query('SELECT item_json FROM goodluck_collectibles_items ORDER BY id')) do next.definitions[#next.definitions+1]=decode(row.item_json) end
  local byId={}
  for _,row in ipairs(query('SELECT id,collectable_type,name FROM goodluck_collectibles_sets ORDER BY id')) do local set={id=row.id,collectableType=row.collectable_type,name=row.name,itemIds={}};byId[set.id]=set;next.sets[#next.sets+1]=set end
  for _,row in ipairs(query('SELECT set_id,item_id FROM goodluck_collectibles_set_items ORDER BY position')) do if byId[row.set_id] then table.insert(byId[row.set_id].itemIds,row.item_id) end end
  for _,row in ipairs(query('SELECT collectable_type,container_json FROM goodluck_collectibles_containers')) do next.containers[row.collectable_type]=decode(row.container_json) end
 else
  local raw=LoadResourceFile(resource,'data/collectibles.json')
  if raw and raw~='' then next=decode(raw) end
 end
 next.definitions=next.definitions or {};next.sets=next.sets or {};next.containers=next.containers or {};next.instances={};next.sealed={}
 service.data=next
end

local function saveOperation(payload)
 local next=copy(service.data)
 local statements={}
 if payload.kind=='definition' then
  local item=copy(payload.value or {});validType(item.collectableType);validId(item.id)
  assert(type(item.title)=='string' and item.title:match('%S') and #item.title<=255,'Give the collectible a name')
  local previous=find(next.definitions,item.id);assert(not previous or previous.collectableType==item.collectableType,'Cannot change a collectible type')
  item.chanceWeight=math.min(100000,math.max(1,tonumber(item.chanceWeight) or 1))
  item.rarityKey=rarityKeyOf(item.rarityKey or item.rarity);item.rarity=RARITY_LABELS[item.rarityKey]
  if item.prints~=nil then
   assert(type(item.prints)=='table' and #item.prints<=50,'A collectible can have at most 50 prints')
   local seen={}
   for index,print in ipairs(item.prints) do
    assert(type(print)=='table' and type(print.id)=='string' and #print.id>0 and #print.id<=80 and not seen[print.id],'Each print needs its own id')
    seen[print.id]=true
    assert(type(print.name)=='string' and print.name:match('%S') and #print.name<=120,'Give every print a name')
    print.chanceWeight=math.min(100000,math.max(1,tonumber(print.chanceWeight) or 1))
    print.rarityKey=rarityKeyOf(print.rarityKey);print.rarity=RARITY_LABELS[print.rarityKey]
    item.prints[index]=print
   end
  end
  next.definitions=replace(next.definitions,item)
  statements[1]=statement('INSERT INTO goodluck_collectibles_items (id,collectable_type,title,item_json) VALUES (?,?,?,?) ON DUPLICATE KEY UPDATE title=VALUES(title),item_json=VALUES(item_json)',{item.id,item.collectableType,item.title,json.encode(item)})
 elseif payload.kind=='delete' then
  validId(payload.id);local item=assert(find(next.definitions,payload.id),'Unknown collectible')
  local kept={};for _,entry in ipairs(next.definitions) do if entry.id~=item.id then kept[#kept+1]=entry end end;next.definitions=kept
  for _,set in ipairs(next.sets) do local members={};for _,id in ipairs(set.itemIds) do if id~=item.id then members[#members+1]=id end end;set.itemIds=members end
  statements[1]=statement('DELETE FROM goodluck_collectibles_items WHERE id=?',{item.id})
 elseif payload.kind=='set' then
  local set=copy(payload.value or {});validType(set.collectableType);validId(set.id);set.itemIds=set.itemIds or {}
  assert(type(set.name)=='string' and set.name:match('%S') and #set.name<=255,'Give the set a name')
  local previous=find(next.sets,set.id);assert(not previous or previous.collectableType==set.collectableType,'Cannot change a set type')
  local seen={};for _,id in ipairs(set.itemIds or {}) do local item=assert(find(next.definitions,id),'Unknown set member');assert(item.collectableType==set.collectableType and not seen[id],'Invalid or duplicate set member');seen[id]=true end
  next.sets=replace(next.sets,set)
  statements[#statements+1]=statement('INSERT INTO goodluck_collectibles_sets (id,collectable_type,name) VALUES (?,?,?) ON DUPLICATE KEY UPDATE name=VALUES(name)',{set.id,set.collectableType,set.name})
  statements[#statements+1]=statement('DELETE FROM goodluck_collectibles_set_items WHERE set_id=?',{set.id})
  for index,id in ipairs(set.itemIds or {}) do statements[#statements+1]=statement('INSERT INTO goodluck_collectibles_set_items (set_id,item_id,position) VALUES (?,?,?)',{set.id,id,index}) end
 elseif payload.kind=='container' then
  local container=copy(payload.value or {});validType(payload.typeId);local set=assert(find(next.sets,container.setId),'Unknown set');assert(set.collectableType==payload.typeId and #set.itemIds>0,'Choose a non-empty set of the same type')
  assert(type(container.label)=='string' and container.label:match('%S'),'Give the container a name')
  container.count=bounded(container.count,24);container.outer=container.outer or {};container.outer.count=bounded(container.outer.count,100)
  assert(type(container.outer.label)=='string' and container.outer.label:match('%S'),'Give the outer box a name')
  container.kind=payload.typeId=='challenge_coin' and 'bag' or 'box'
  next.containers[payload.typeId]=container
  statements[1]=statement('INSERT INTO goodluck_collectibles_containers (collectable_type,set_id,container_json) VALUES (?,?,?) ON DUPLICATE KEY UPDATE set_id=VALUES(set_id),container_json=VALUES(container_json)',{payload.typeId,container.setId,json.encode(container)})
 else error('Unknown collectible save operation') end
 if MetaComic.Persistence.name=='mysql' then transaction(statements) else persistJson(next) end
 service.data=next
 return true
end

local saving=false
function service.save(payload)
 assert(not saving,'Another collectible save is in progress; retry shortly')
 saving=true;local ok,result=pcall(saveOperation,payload);saving=false
 if not ok then error(result) end
 return result
end

function service.get(source)
 local data={definitions=copy(service.data.definitions),sets=copy(service.data.sets),containers=copy(service.data.containers),instances={},sealed={}}
 if MetaComic.Inventory.slotsOf then
  for typeId,names in pairs(types) do
   for _,slot in pairs(MetaComic.Inventory.slotsOf(source,names.item)) do local meta=slot.metadata or slot.info or {};if type(meta.collectibleSnapshot)=='table' then data.instances[#data.instances+1]=copy(meta.collectibleSnapshot) end end
   for _,slot in pairs(MetaComic.Inventory.slotsOf(source,names.inner)) do local meta=slot.metadata or slot.info or {};if type(meta.containerSnapshot)=='table' then data.sealed[#data.sealed+1]={instanceId=meta.instanceId,collectableType=typeId,containerSnapshot=copy(meta.containerSnapshot),label=meta.label,slot=slot.slot} end end
  end
 end
 return data
end

local serial=0
local function unique() serial=serial+1;return ('%s-%s-%s'):format(os.time(),GetGameTimer(),serial) end
local function containerMetadata(typeId,container,outer)
 return {instanceId=unique(),collectableType=typeId,containerSnapshot=copy(container),outer=outer==true,label=outer and container.outer.label or container.label,description='Meta Comics · '..(outer and (container.outer.count..' sealed containers') or (container.count..' collectables'))}
end
local busy,last={},{ }
local function deliver(source,outputs,consumed)
 if MetaComic.Inventory.canCarry and #outputs>0 then
  if not MetaComic.Inventory.canCarry(source,outputs[1].name,#outputs) then
   if consumed then assert(MetaComic.Inventory.add(source,consumed.name,1,consumed.metadata or consumed.info),'Could not return consumed container') end
   error(consumed and 'Not enough inventory space; container was returned' or 'Not enough inventory space; collectible delivery is pending. Free space and close the opening again.')
  end
 end
 local inserted={}
 for _,output in ipairs(outputs) do
  if not MetaComic.Inventory.add(source,output.name,1,output.metadata) then
   local rolledBack=true
   for _,entry in ipairs(inserted) do if not MetaComic.Inventory.remove(source,entry.name,1,{instanceId=entry.metadata.instanceId}) then rolledBack=false end end
   if rolledBack and consumed then rolledBack=MetaComic.Inventory.add(source,consumed.name,1,consumed.metadata or consumed.info)==true end
   assert(rolledBack,'Inventory could not roll back partial delivery; contact an administrator')
   error(consumed and 'Not enough inventory space; container was returned' or 'Not enough inventory space; collectible delivery is pending. Free space and close the opening again.')
  end
  inserted[#inserted+1]=output
 end
end

local claimBusy={}
local pendingJson
local function ownerOf(source) return assert(MetaComic.Framework.getIdentifier(source),'Player identity is unavailable') end
local function pendingFor(owner)
 if MetaComic.Persistence.name=='mysql' then
  local list={};for _,row in ipairs(query('SELECT id,outputs_json FROM goodluck_collectibles_openings WHERE owner=?',{owner})) do list[#list+1]={id=row.id,outputs=decode(row.outputs_json)} end;return list
 end
 if not pendingJson then local raw=LoadResourceFile(resource,'data/collectible_openings.json');pendingJson=raw and raw~='' and decode(raw) or {} end
 local list={};for id,entry in pairs(pendingJson) do if entry.owner==owner then list[#list+1]={id=id,outputs=copy(entry.outputs)} end end;return list
end
local function savePending(id,owner,outputs)
 if MetaComic.Persistence.name=='mysql' then
  if outputs then query('INSERT INTO goodluck_collectibles_openings (id,owner,outputs_json) VALUES (?,?,?)',{id,owner,json.encode(outputs)})
  else query('DELETE FROM goodluck_collectibles_openings WHERE id=? AND owner=?',{id,owner}) end
 else
  pendingFor(owner)
  local next=copy(pendingJson);next[id]=outputs and {owner=owner,outputs=copy(outputs)} or nil
  assert(SaveResourceFile(resource,'data/collectible_openings.json',json.encode(next),-1),'Could not save pending collectible delivery');pendingJson=next
 end
end

-- Receipts belong to a character, not a transient player source. They survive
-- disconnects/restarts and only the server's frozen outputs can be claimed.
function service.claim(source)
 local owner=ownerOf(source);assert(not claimBusy[owner],'Collectible delivery is already in progress')
 claimBusy[owner]=true
 local ok,result=pcall(function()
  local given=0
  for _,receipt in ipairs(pendingFor(owner)) do
   local missing={}
   for _,output in ipairs(receipt.outputs) do
    local exists=false
    for _,slot in pairs(MetaComic.Inventory.slotsOf(source,output.name) or {}) do
     local meta=slot.metadata or slot.info or {};if meta.instanceId==output.metadata.instanceId then exists=true;break end
    end
    if not exists then missing[#missing+1]=output end
   end
   deliver(source,missing)
   savePending(receipt.id,owner,nil);given=given+#missing
  end
  return given
 end)
 claimBusy[owner]=nil;if not ok then error(result) end;return result
end

function service.create(source,payload)
 local names=validType(payload.typeId);local container=assert(service.data.containers[payload.typeId],'Save this container first');local outer=payload.outer==true
 local outputs={};for _=1,bounded(payload.amount or 1,100) do outputs[#outputs+1]={name=outer and names.outer or names.inner,metadata=containerMetadata(payload.typeId,container,outer)} end
 deliver(source,outputs)
 return service.get(source)
end

function service.open(source,payload,management)
 assert(not busy[source] and (not last[source] or GetGameTimer()-last[source]>600),'Please wait before opening another container')
 busy[source]=true;last[source]=GetGameTimer()
 local ok,result=pcall(function()
  service.claim(source) -- a previous opening was left/closed; retry its delivery first
  local names=validType(payload.typeId);local outer=payload.outer==true
  local expected=outer and names.outer or names.inner
  local slot
  if payload.slot then slot=MetaComic.Inventory.getSlot(source,tonumber(payload.slot));assert(slot,'That inventory slot is no longer available')
  elseif MetaComic.Inventory.slotsOf then for _,entry in pairs(MetaComic.Inventory.slotsOf(source,expected)) do slot=entry;break end end
  local paid=slot~=nil
  assert(paid or (management and not Config.Items.RequireForOpen),'You need this sealed container in your inventory')
  local container
  local openingId=unique()
  if paid then
   assert(slot.name==expected,'That slot is not the selected container')
   local meta=slot.metadata or slot.info or {}
   if meta.containerSnapshot~=nil then
    assert(meta.collectableType==payload.typeId and meta.outer==outer and type(meta.containerSnapshot)=='table','Container metadata is invalid')
    container=copy(meta.containerSnapshot)
   else
    container=copy(assert(service.data.containers[payload.typeId],'Save this container before using plain inventory items'))
   end
  else container=copy(assert(service.data.containers[payload.typeId],'Save a container first')) end
  bounded(container.count,24);bounded(container.outer.count,100)
  local outputs,items={},{}
  if outer then
   for _=1,container.outer.count do local meta=containerMetadata(payload.typeId,container,false);outputs[#outputs+1]={name=names.inner,metadata=meta};items[#items+1]={instanceId=meta.instanceId,label=container.label,containerSnapshot=copy(container),collectableType=payload.typeId} end
  else
   local set=assert(find(service.data.sets,container.setId),'The container set no longer exists')
   assert(set.collectableType==payload.typeId,'Container set type does not match')
   local pool={}
   for _,id in ipairs(set.itemIds) do local item=find(service.data.definitions,id);if item then pool[#pool+1]=item end end
   assert(#pool>0,'This container set is empty')
   for _=1,container.count do
    local chosen=weightedPick(pool)
    local snapshot=MetaComic.Collectables.snapshot(payload.typeId,withPrint(chosen,weightedPick(printsOf(chosen))))
    snapshot.instanceId=unique();snapshot.acquiredAt=os.date('!%Y-%m-%dT%H:%M:%SZ');snapshot.snapshotVersion=2
    outputs[#outputs+1]={name=names.item,metadata=collectibleMetadata(payload.typeId,snapshot)};items[#items+1]=snapshot
   end
  end
  if paid then
   local consumed=copy(slot)
   local meta=slot.metadata or slot.info or {}
   local identity=meta.instanceId and {instanceId=meta.instanceId} or nil
   assert(MetaComic.Inventory.remove(source,expected,1,identity,slot.slot),'Could not consume this container')
   local staged,err=pcall(savePending,openingId,ownerOf(source),outputs)
   if not staged then
    assert(MetaComic.Inventory.add(source,consumed.name,1,consumed.metadata or consumed.info),'Could not return consumed container')
    error(err)
   end
  else
   savePending(openingId,ownerOf(source),outputs)
  end
  -- new prints get their inventory icon drawn during the reveal (by this player) and uploaded
  if not outer and service.onPulled then pcall(service.onPulled,source,items) end
  return {data=service.get(source),run={id=openingId,typeId=payload.typeId,container=container,outer=outer,items=items}}
 end)
 busy[source]=nil
 if not ok then error(result) end
 return result
end
AddEventHandler('playerDropped',function() busy[source]=nil;last[source]=nil end)
service.init()
