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
 MetaComic.Collectibles.registerType(id,{label=id,itemName=defaults.item,snapshotVersion=1})
end
service.types = types
local resource = GetCurrentResourceName()
local function query(sql,params) return exports[Config.Database.Resource or 'oxmysql']:query_async(sql,params or {}) end
local function transaction(statements)
 if not exports[Config.Database.Resource or 'oxmysql']:transaction_async(statements) then error('Collectible database write rolled back') end
end
local function statement(sql,values) return {query=sql,values=values or {}} end
local function copy(value) return MetaComic.CopyTable(value) end
local function decode(raw) if type(raw)=='table' then return MetaComic.Collectibles.normalize(copy(raw)) end;local value=json.decode(raw); assert(type(value)=='table','Invalid collectible JSON');return MetaComic.Collectibles.normalize(value) end
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
  if types[item.collectibleType] then
   for _,print in ipairs(printsOf(item)) do local snap=withPrint(item,print);snap.collectibleType=item.collectibleType;list[#list+1]=snap end
  end
 end
 return list
end

-- metadata stored on a coin / plushie inventory item: the snapshot is what the game UI renders
local function collectibleMetadata(typeId,snapshot)
 local imageurl,image
 if service.icon then imageurl,image=service.icon(snapshot) end
 local printPart=snapshot.printName and snapshot.printName~='Standard' and (' ('..snapshot.printName..')') or ''
 local manual=snapshot.manualPrint==true
 return {instanceId=snapshot.instanceId,collectibleType=typeId,label=(snapshot.title or 'Collectible')..printPart..(manual and ' [Manual Print]' or ''),
  description=(manual and 'MANUAL PRINT · ' or '')..('%s · %s'):format(snapshot.rarity or 'Common',snapshot.printName or 'Standard')..(snapshot.description and snapshot.description~='' and ('\n'..snapshot.description) or ''),
  rarity=snapshot.rarity,rarityKey=snapshot.rarityKey,printName=snapshot.printName,imageurl=imageurl,image=image,collectibleSnapshot=copy(snapshot),
  acquisitionSource=snapshot.acquisitionSource,manualPrint=manual or nil,printType=manual and 'MANUAL PRINT' or nil,printedBy=snapshot.printedBy,printedAt=snapshot.printedAt}
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
  -- tables made before the spelling fix: collectable_type -> collectible_type (keeps data, keys and the primary key)
  for _,tableName in ipairs({'goodluck_collectibles_items','goodluck_collectibles_sets','goodluck_collectibles_containers'}) do
   local old=query('SELECT 1 FROM information_schema.COLUMNS WHERE TABLE_SCHEMA=DATABASE() AND TABLE_NAME=? AND COLUMN_NAME=?',{tableName,'collectable_type'})
   if old and old[1] then query(('ALTER TABLE `%s` CHANGE `collectable_type` `collectible_type` VARCHAR(32) NOT NULL'):format(tableName)) end
  end
  for _,row in ipairs(query('SELECT item_json FROM goodluck_collectibles_items ORDER BY id')) do next.definitions[#next.definitions+1]=decode(row.item_json) end
  local byId={}
  for _,row in ipairs(query('SELECT id,collectible_type,name FROM goodluck_collectibles_sets ORDER BY id')) do local set={id=row.id,collectibleType=row.collectible_type,name=row.name,itemIds={}};byId[set.id]=set;next.sets[#next.sets+1]=set end
  for _,row in ipairs(query('SELECT set_id,item_id FROM goodluck_collectibles_set_items ORDER BY position')) do if byId[row.set_id] then table.insert(byId[row.set_id].itemIds,row.item_id) end end
  for _,row in ipairs(query('SELECT collectible_type,container_json FROM goodluck_collectibles_containers')) do next.containers[row.collectible_type]=decode(row.container_json) end
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
  local item=copy(payload.value or {});validType(item.collectibleType);validId(item.id)
  assert(type(item.title)=='string' and item.title:match('%S') and #item.title<=255,'Give the collectible a name')
  local previous=find(next.definitions,item.id);assert(not previous or previous.collectibleType==item.collectibleType,'Cannot change a collectible type')
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
  statements[1]=statement('INSERT INTO goodluck_collectibles_items (id,collectible_type,title,item_json) VALUES (?,?,?,?) ON DUPLICATE KEY UPDATE title=VALUES(title),item_json=VALUES(item_json)',{item.id,item.collectibleType,item.title,json.encode(item)})
 elseif payload.kind=='delete' then
  validId(payload.id);local item=assert(find(next.definitions,payload.id),'Unknown collectible')
  local kept={};for _,entry in ipairs(next.definitions) do if entry.id~=item.id then kept[#kept+1]=entry end end;next.definitions=kept
  for _,set in ipairs(next.sets) do local members={};for _,id in ipairs(set.itemIds) do if id~=item.id then members[#members+1]=id end end;set.itemIds=members end
  statements[1]=statement('DELETE FROM goodluck_collectibles_items WHERE id=?',{item.id})
 elseif payload.kind=='set' then
  local set=copy(payload.value or {});validType(set.collectibleType);validId(set.id);set.itemIds=set.itemIds or {}
  assert(type(set.name)=='string' and set.name:match('%S') and #set.name<=255,'Give the set a name')
  local previous=find(next.sets,set.id);assert(not previous or previous.collectibleType==set.collectibleType,'Cannot change a set type')
  local seen={};for _,id in ipairs(set.itemIds or {}) do local item=assert(find(next.definitions,id),'Unknown set member');assert(item.collectibleType==set.collectibleType and not seen[id],'Invalid or duplicate set member');seen[id]=true end
  next.sets=replace(next.sets,set)
  statements[#statements+1]=statement('INSERT INTO goodluck_collectibles_sets (id,collectible_type,name) VALUES (?,?,?) ON DUPLICATE KEY UPDATE name=VALUES(name)',{set.id,set.collectibleType,set.name})
  statements[#statements+1]=statement('DELETE FROM goodluck_collectibles_set_items WHERE set_id=?',{set.id})
  for index,id in ipairs(set.itemIds or {}) do statements[#statements+1]=statement('INSERT INTO goodluck_collectibles_set_items (set_id,item_id,position) VALUES (?,?,?)',{set.id,id,index}) end
 elseif payload.kind=='container' then
  local container=copy(payload.value or {});validType(payload.typeId);local set=assert(find(next.sets,container.setId),'Unknown set');assert(set.collectibleType==payload.typeId and #set.itemIds>0,'Choose a non-empty set of the same type')
  assert(type(container.label)=='string' and container.label:match('%S'),'Give the container a name')
  container.count=bounded(container.count,24);container.outer=container.outer or {};container.outer.count=bounded(container.outer.count,100)
  assert(type(container.outer.label)=='string' and container.outer.label:match('%S'),'Give the outer box a name')
  container.kind=payload.typeId=='challenge_coin' and 'bag' or 'box'
  next.containers[payload.typeId]=container
  statements[1]=statement('INSERT INTO goodluck_collectibles_containers (collectible_type,set_id,container_json) VALUES (?,?,?) ON DUPLICATE KEY UPDATE set_id=VALUES(set_id),container_json=VALUES(container_json)',{payload.typeId,container.setId,json.encode(container)})
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
   for _,slot in pairs(MetaComic.Inventory.slotsOf(source,names.item)) do local meta=slot.metadata or slot.info or {};if type(meta.collectibleSnapshot)=='table' then data.instances[#data.instances+1]=MetaComic.Collectibles.normalize(copy(meta.collectibleSnapshot)) end end
   for _,slot in pairs(MetaComic.Inventory.slotsOf(source,names.inner)) do local meta=slot.metadata or slot.info or {};if type(meta.containerSnapshot)=='table' then data.sealed[#data.sealed+1]={instanceId=meta.instanceId,collectibleType=typeId,containerSnapshot=copy(meta.containerSnapshot),label=meta.label,slot=slot.slot} end end
  end
 end
 return data
end

-- Copies of the pulled snapshots with each inline data: image (several hundred KB) replaced by a shared reference.
local function packImages(items)
 local images,index,packed={},{},{}
 for i,item in ipairs(items) do
  local entry=copy(item)
  for key,value in pairs(entry) do
   if type(value)=='string' and #value>4096 and value:sub(1,5)=='data:' then
    if not index[value] then images[#images+1]=value;index[value]='@img:'..#images end
    entry[key]=index[value]
   end
  end
  packed[i]=entry
 end
 return packed,images
end

local serial=0
local function unique() serial=serial+1;return ('%s-%s-%s'):format(os.time(),GetGameTimer(),serial) end
-- Container designs (src/collectibles/container3dOptions.js); the first one is the default.
local CONTAINER_STYLES={bag={'velvet','satin','leather'},box={'window','cube','gift'},case={'display','chest','crate'}}
local function styleOf(kind,look)
 for _,id in ipairs(CONTAINER_STYLES[kind]) do if type(look)=='table' and look.style==id then return id end end
 return CONTAINER_STYLES[kind][1]
end
-- Each design has its own inventory picture: ox_inventory/web/images/<item name>_<design>.png (fivem/img/containers).
-- Config.Collectibles.ContainerImages = false keeps the item's own picture for every design.
local function containerMetadata(typeId,container,outer)
 local names=types[typeId]
 local style=outer and styleOf('case',container.outer and container.outer.look) or styleOf(container.kind=='bag' and 'bag' or 'box',container.look)
 local image=Config.Collectibles.ContainerImages~=false and ((outer and names.outer or names.inner)..'_'..style) or nil
 return {instanceId=unique(),collectibleType=typeId,containerSnapshot=copy(container),outer=outer==true,label=outer and container.outer.label or container.label,image=image,
  description='Meta Comics · '..(outer and (container.outer.count..' sealed containers') or (container.count..' collectibles'))}
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
-- MySQL: each owner's undelivered openings are read once, then kept in memory next to the table (only this
-- resource writes it), so opening and claiming don't query the database every time.
local pendingCache={}
local function ownerOf(source) return assert(MetaComic.Framework.getIdentifier(source),'Player identity is unavailable') end
local function pendingFor(owner)
 if MetaComic.Persistence.name=='mysql' then
  if not pendingCache[owner] then
   local list={};for _,row in ipairs(query('SELECT id,outputs_json FROM goodluck_collectibles_openings WHERE owner=?',{owner})) do list[#list+1]={id=row.id,outputs=decode(row.outputs_json)} end
   pendingCache[owner]=list
  end
  return copy(pendingCache[owner])
 end
 if not pendingJson then local raw=LoadResourceFile(resource,'data/collectible_openings.json');pendingJson=raw and raw~='' and decode(raw) or {} end
 local list={};for id,entry in pairs(pendingJson) do if entry.owner==owner then list[#list+1]={id=id,outputs=copy(entry.outputs)} end end;return list
end
-- Receipt writes run in order on their own thread, so an opening doesn't wait for the database: the in-memory
-- copy above is updated first and is what openings / claims read.
local writeQueue,writing={},false
local function queueWrite(sql,params)
 writeQueue[#writeQueue+1]={sql=sql,params=params}
 if writing then return end
 writing=true
 CreateThread(function()
  while #writeQueue>0 do
   local write=table.remove(writeQueue,1)
   local ok,err=pcall(query,write.sql,write.params)
   if not ok then print('[meta-comic] could not save a collectible delivery receipt: '..tostring(err)) end
  end
  writing=false
 end)
end
local function savePending(id,owner,outputs)
 if MetaComic.Persistence.name=='mysql' then
  if not pendingCache[owner] then pendingFor(owner) end
  if outputs then queueWrite('INSERT INTO goodluck_collectibles_openings (id,owner,outputs_json) VALUES (?,?,?)',{id,owner,json.encode(outputs)})
  else queueWrite('DELETE FROM goodluck_collectibles_openings WHERE id=? AND owner=?',{id,owner}) end
  local cached=pendingCache[owner]
  if cached then
   local kept={};for _,entry in ipairs(cached) do if entry.id~=id then kept[#kept+1]=entry end end
   if outputs then kept[#kept+1]={id=id,outputs=copy(outputs)} end
   pendingCache[owner]=kept
  end
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
 local names=validType(payload.typeId);local container=copy(assert(service.data.containers[payload.typeId],'Save this container first'));local outer=payload.outer==true
 -- the version chosen when creating them; the sealed items keep it, and so do the containers inside an outer case
 local innerKind=container.kind=='bag' and 'bag' or 'box'
 container.look=container.look or {};container.look.style=styleOf(innerKind,{style=payload.style or container.look.style})
 container.outer=container.outer or {};container.outer.look=container.outer.look or {};container.outer.look.style=styleOf('case',{style=payload.outerStyle or container.outer.look.style})
 local outputs={};for _=1,bounded(payload.amount or 1,100) do outputs[#outputs+1]={name=outer and names.outer or names.inner,metadata=containerMetadata(payload.typeId,container,outer)} end
 deliver(source,outputs)
 return service.get(source)
end

-- Manual print from the editor: one item of a saved print, marked MANUAL PRINT (like printCard for trading cards).
-- Built from the saved catalogue, never from the editor's draft.
function service.printManual(source,payload,printer)
 local names=validType(payload.typeId);validId(payload.definitionId)
 local item=assert(find(service.data.definitions,payload.definitionId),'Save this collectible before printing it')
 assert(item.collectibleType==payload.typeId,'Collectible type does not match')
 local chosen;for _,print in ipairs(printsOf(item)) do if print.id==payload.printId then chosen=print end end
 assert(chosen,'Save this print before printing it')
 local snapshot=MetaComic.Collectibles.snapshot(payload.typeId,withPrint(item,chosen))
 local now=os.date('!%Y-%m-%dT%H:%M:%SZ')
 snapshot.instanceId='manual-'..unique();snapshot.acquiredAt=now;snapshot.snapshotVersion=2
 snapshot.acquisitionSource='manual_print';snapshot.manualPrint=true
 snapshot.printedBy=printer.name;snapshot.printedByIdentifier=printer.identifier;snapshot.printedAt=now
 deliver(source,{{name=names.item,metadata=collectibleMetadata(payload.typeId,snapshot)}})
 if service.onPulled then SetTimeout(0,function() pcall(service.onPulled,source,{withPrint(item,chosen)}) end) end -- shared icon, no stamp
 return snapshot
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
    assert(MetaComic.Collectibles.typeOf(meta)==payload.typeId and meta.outer==outer and type(meta.containerSnapshot)=='table','Container metadata is invalid')
    container=copy(meta.containerSnapshot)
   else
    container=copy(assert(service.data.containers[payload.typeId],'Save this container before using plain inventory items'))
   end
  else container=copy(assert(service.data.containers[payload.typeId],'Save a container first')) end
  bounded(container.count,24);bounded(container.outer.count,100)
  local outputs,items={},{}
  if outer then
   for _=1,container.outer.count do local meta=containerMetadata(payload.typeId,container,false);outputs[#outputs+1]={name=names.inner,metadata=meta};items[#items+1]={instanceId=meta.instanceId,label=container.label,containerSnapshot=copy(container),collectibleType=payload.typeId} end
  else
   local set=assert(find(service.data.sets,container.setId),'The container set no longer exists')
   assert(set.collectibleType==payload.typeId,'Container set type does not match')
   local pool={}
   for _,id in ipairs(set.itemIds) do local item=find(service.data.definitions,id);if item then pool[#pool+1]=item end end
   assert(#pool>0,'This container set is empty')
   for _=1,container.count do
    local chosen=weightedPick(pool)
    local snapshot=MetaComic.Collectibles.snapshot(payload.typeId,withPrint(chosen,weightedPick(printsOf(chosen))))
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
  -- (next tick: its latent icon request must queue behind this reply, not delay the opening animation)
  if not outer and service.onPulled then SetTimeout(0,function() pcall(service.onPulled,source,items) end) end
  -- Lean reply so the opening starts quickly: no full catalogue/inventory echo (the UI refreshes after the claim),
  -- and an uploaded image shared by several pulls is sent once (items reference it as '@img:N').
  local runItems,images=packImages(items)
  return {run={id=openingId,typeId=payload.typeId,container=container,outer=outer,items=runItems,images=images}}
 end)
 busy[source]=nil
 if not ok then error(result) end
 return result
end
AddEventHandler('playerDropped',function() busy[source]=nil;last[source]=nil end)
service.init()
