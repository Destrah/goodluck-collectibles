-- The bundled manifest is only imported by an explicit authorized command.
-- Uploads finish before definitions are committed; reruns preserve edited samples.
MetaComic.SampleCards = {}
local service=MetaComic.SampleCards
local resource=GetCurrentResourceName()
local alphabet='ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/'
local function base64(bytes)
 local result={}
 for index=1,#bytes,3 do
  local a,b,c=bytes:byte(index,index+2);local n=a*65536+(b or 0)*256+(c or 0)
  result[#result+1]=alphabet:sub(n//262144+1,n//262144+1)..alphabet:sub(n//4096%64+1,n//4096%64+1)
    ..(b and alphabet:sub(n//64%64+1,n//64%64+1) or '=')..(c and alphabet:sub(n%64+1,n%64+1) or '=')
 end
 return table.concat(result)
end
service.base64=base64

function service.merge(cards,sets,seed)
 local catalog=MetaComic.CopyTable(cards);local list=MetaComic.CopyTable(sets)
 local known={};for _,card in ipairs(catalog) do known[card.id]=card end
 local added,prints=0,0
 for _,card in ipairs(seed.cards) do
  local previous=known[card.id]
  assert(not previous or previous.sampleSeedVersion==seed.version,'Sample id conflicts with an existing card: '..tostring(card.id))
  if not previous then catalog[#catalog+1]=MetaComic.CopyTable(card);added=added+1 end
  prints=prints+#(previous and previous.variants or card.variants)
 end
 local target
 for _,set in ipairs(list) do if set.id==seed.set.id then target=set;break end end
 if not target then target=MetaComic.CopyTable(seed.set);target.cardIds={};list[#list+1]=target end
 local members={};for _,id in ipairs(target.cardIds) do members[id]=true end
 for _,card in ipairs(seed.cards) do if not members[card.id] then target.cardIds[#target.cardIds+1]=card.id;members[card.id]=true end end
 return catalog,list,added,prints
end

local running=false
function service.generate(hooks)
 assert(not running,'A Sample set generation is already in progress')
 running=true
 local ok,result=pcall(function()
  assert(hooks.hasKey(),'Set metacomic_fivemanage_key_artwork or metacomic_fivemanage_key before generating the Sample set')
  local raw=assert(LoadResourceFile(resource,'data/sample-cards.json'),'Missing data/sample-cards.json; copy the updated resource files')
  local seed=json.decode(raw);assert(type(seed)=='table' and type(seed.cards)=='table' and #seed.cards>=100,'Invalid sample manifest')
  local current=MetaComic.Cards.getCatalog()
  service.merge(current,MetaComic.Sets.getAll(),seed) -- detect conflicts before any uploads
  local known={};for _,card in ipairs(current) do known[card.id]=true end
  local assets={}
  local function collect(value)
   for _,entry in pairs(value) do
    if type(entry)=='table' then collect(entry)
    elseif type(entry)=='string' and entry:match('^/img/sample/[%w%-]+%.png$') then assets[entry]=true end
   end
  end
  for _,card in ipairs(seed.cards) do if not known[card.id] then collect(card) end end
  -- Explicit artwork refresh leaves print settings, masks and other edits intact.
  if hooks.refreshArt then
   for _,card in ipairs(seed.cards) do assets[card.image]=true end
  end
  local paths={};for path in pairs(assets) do paths[#paths+1]=path end;table.sort(paths)
  hooks.report(('Uploading %d sample artwork/mask assets; progress is also logged in the server console.'):format(#paths))
  local urls={}
  for index,path in ipairs(paths) do
   local bytes=assert(LoadResourceFile(resource,path:sub(2)),'Missing sample asset: '..path)
   local url=hooks.upload('data:image/png;base64,'..base64(bytes))
   assert(type(url)=='string' and url:match('^https://'),'Sample upload failed for '..path..'; rerun the command to resume cached uploads')
   urls[path]=url
   if index%10==0 or index==#paths then hooks.report(('Sample asset uploads: %d/%d'):format(index,#paths)) end
   Wait(0)
  end
  local function replace(value)
   for key,entry in pairs(value) do
    if type(entry)=='table' then replace(entry) elseif urls[entry] then value[key]=urls[entry] end
   end
  end
  for _,card in ipairs(seed.cards) do if not known[card.id] then replace(card) end end
  -- Merge against the latest cache after the uploads, preserving edits made while
  -- Fivemanage was processing assets. MySQL commits cards + memberships together.
  if MetaComic.Persistence.reloadDefinitions then local refreshed,err=MetaComic.Persistence.reloadDefinitions();assert(refreshed,err);MetaComic.Cards.reloadCatalog();MetaComic.Sets.reload() end
  local latest=MetaComic.Cards.getCatalog();local latestIds={};for _,card in ipairs(latest) do latestIds[card.id]=true end
  for _,card in ipairs(seed.cards) do
   assert(not known[card.id] or latestIds[card.id],'Sample cards changed during generation; rerun the command to upload newly missing assets')
  end
  local cards,sets,added,prints=service.merge(latest,MetaComic.Sets.getAll(),seed)
  if hooks.refreshArt then
   local images={};for _,card in ipairs(seed.cards) do images[card.id]=urls[card.image] or card.image end
   for _,card in ipairs(cards) do if images[card.id] then card.image=images[card.id] end end
  end
  hooks.freeze()
  if MetaComic.Persistence.saveSampleCatalog then
   local saved,err=MetaComic.Persistence.saveSampleCatalog(cards,sets);assert(saved,err)
   MetaComic.Cards.reloadCatalog();MetaComic.Sets.reload()
  else
   local saved,err=MetaComic.Cards.saveCatalog(cards);assert(saved,err)
   saved,err=MetaComic.Sets.save(sets);assert(saved,err)
  end
  hooks.sync()
  hooks.report(('Sample ready: %d base cards, %d prints; %d cards added. Open /collectablesadmin and select Sample in Sets & containers or the pack lab. Inventory icons upload in the background.'):format(#seed.cards,prints,added))
  return {added=added,cards=#seed.cards,prints=prints}
 end)
 running=false
 if not ok then error(result) end
 return result
end
