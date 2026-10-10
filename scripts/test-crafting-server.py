"""Exercise real crafting transactions, bonus boundaries and ACE-restricted settings."""
from pathlib import Path
import sys
sys.path.insert(0,str(Path(__file__).resolve().parents[1]/'.tmp-mysql-tests'))
from lupa.lua54 import LuaRuntime
lua=LuaRuntime()
lua.execute('''
now=0; source=1; ace=true; enough=true; room=true; events={}; messages={}; grants={}; removed=0; saved=nil
GetGameTimer=function()return now end
IsPlayerAceAllowed=function()return ace end
RegisterNetEvent=function(n,f)events[n]=f end
AddEventHandler=function()end;RegisterCommand=function()end
CreateThread=function(f)f()end;Wait=function()end
TriggerClientEvent=function()end;TriggerLatentClientEvent=function(...)lastEvent={...}end
GetPlayerPed=function()return 0 end
exports=function()end
Config={Crafting={Recipes={{id='pack',label='Pack',time=4000,ingredients={{item='paper',count=2}},
 result={type='sealed',kind='pack',count=1},minigame={enabled=true,cols=5,rows=3,rewardPacks=3,bonusPacks=1,bonusSeconds=180}}}},Management={Ace='metacomic.manage'}}
local function copy(v)if type(v)~='table'then return v end local t={}for k,x in pairs(v)do t[k]=copy(x)end return t end
MetaComic={CopyTable=copy,CanManage=function()return true end,RpcHandlers={},
 Framework={notify=function(_,m)messages[#messages+1]=m end},Inventory={count=function()return enough and 99 or 0 end,
 remove=function(_,_,n)removed=removed+n;return true end,add=function()return true end},Money={remove=function()return true end,add=function()end},
 Settings={get=function()return saved end,set=function(_,v)saved=v;return true end},
 Sets={get=function(id)if id=='base' then return {id='base',name='Base',cardIds={'c'}} elseif id=='other' then return {id='other',name='Other',cardIds={'d'}} elseif id=='empty' then return {id='empty',cardIds={}} end end,defaultId=function()return 'base'end,getAll=function()return {{id='base',name='Base'},{id='other',name='Other'}}end},
 Cards={getCatalog=function()return {{id='c',variants={{id='v'},{id='holo'}}},{id='d',variants={{id='v'},{id='foil'}}}}end,resolve=function(id,v)return {id=id,variantId=v,title='Card',accent='#22d3ee'}end},
 Rewards={types={sealed={validate=function()return true end,label=function()return 'Pack'end,
 canGive=function(_,r)checked=r.count;return room end,give=function(_,r)grants[#grants+1]=r.count;grantSet=r.set;return true end}}}}
MetaComic.Rewards.register=function()end
start=function()events['meta_comic:server:craftingStart'](0,'pack',3)end
finish=function(errors)events['meta_comic:server:craftingFinish']({errors=errors,printed=true,inspected=true,packs=3,folds=3,seals=3,cuts=14,rewardPacks=999,seconds=1})end
''')
lua.execute((Path(__file__).resolve().parents[1]/'fivem/server/modules/crafting.lua').read_text(encoding='utf-8'))
for name in ['fivem/client/crafting.lua','fivem/client/minigames.lua','fivem/client/main.lua','fivem/config.lua']:
    code=(Path(__file__).resolve().parents[1]/name).read_text(encoding='utf-8')
    lua.globals().syntax_source=code
    lua.execute('assert(load(syntax_source))')
lua.execute('start();now=1000;finish(0);assert(#grants==0 and removed==0)')
lua.execute('now=2000;start();now=42000;finish(0);assert(grants[1]==4 and checked==4 and removed==2)')
lua.execute('finish(0);assert(#grants==1)')
lua.execute('start();now=82000;finish(1);assert(grants[2]==3)')
lua.execute('start();now=400000;finish(0);assert(grants[3]==3)')
lua.execute('start();now=440000;room=false;finish(0);assert(#grants==3 and removed==6);room=true')
lua.execute("start();events['meta_comic:server:craftingFinish']({errors=0,printed=true,inspected=true,packs=999,folds=3,seals=3,cuts=14});assert(#grants==3)")
lua.execute('start();now=480000;enough=false;finish(0);assert(#grants==3);enough=true')
lua.execute('start();events["meta_comic:server:craftingCancel"]();now=520000;finish(0);assert(#grants==3)')
lua.execute("local r=MetaComic.RpcHandlers.getCraftingPrints(1,{setId='other'});assert(r.ok and r.setId=='other' and #r.cards==1);for _,c in ipairs(r.cards)do assert(c.id=='d')end;local all=MetaComic.Crafting.prints('other');assert(#all==2 and all[1].variantId~=all[2].variantId);assert(not MetaComic.RpcHandlers.getCraftingPrints(1,{setId='missing'}).ok)")
lua.execute("events['meta_comic:server:craftingStart'](0,'pack',7,'other');assert(lastEvent[4].setId=='other');now=now+40000;finish(1);assert(grants[4]==3 and grantSet=='other' and lastEvent[4].requestedPacks==4);now=now+40000;finish(1);assert(grants[5]==4 and lastEvent[4].requestedPacks==1);now=now+40000;finish(1);assert(grants[6]==1 and grantSet=='other');finish(1);assert(#grants==6)")
lua.execute("events['meta_comic:server:craftingStart'](0,'pack',3,'empty');now=now+40000;finish(0);assert(#grants==6);events['meta_comic:server:craftingStart'](0,'pack',3,'missing');finish(0);assert(#grants==6)")
lua.execute("events['meta_comic:server:craftingStart'](0,'pack',7,'other');now=now+40000;finish(1);assert(#grants==7);events['meta_comic:server:craftingCancel']();now=now+40000;finish(1);assert(#grants==7)")
lua.execute("local old=MetaComic.Cards.getCatalog;local get=MetaComic.Sets.get;MetaComic.Cards.getCatalog=function()local t={}for i=1,100 do t[i]={id='large'..i,variants={{id='standard'},{id='foil'},{id='holo'}}}end return t end;MetaComic.Sets.get=function(id)if id~='large'then return get(id)end local ids={}for i=1,100 do ids[i]='large'..i end return {id='large',cardIds=ids}end;local cards=MetaComic.Crafting.prints('large');assert(#cards==300);local ids,prints={},{};for _,c in ipairs(cards)do ids[c.id]=true;prints[c.variantId]=true end;local n=0;for _ in pairs(ids)do n=n+1 end;assert(n==100 and prints.standard and prints.foil and prints.holo);local compact=MetaComic.Crafting.prints('large',15);assert(#compact==15);local unique={}for _,c in ipairs(compact)do assert(not unique[c.id]);unique[c.id]=true end;MetaComic.Cards.getCatalog=old;MetaComic.Sets.get=get")
lua.execute("room=false;local previous=lastEvent;start();assert(lastEvent==previous and messages[#messages]:find('before starting'));now=now+40000;finish(0);assert(#grants==7);room=true")
lua.execute('ace=false;local r=MetaComic.Crafting.all();r[1].minigame.rewardPacks=90;assert(MetaComic.RpcHandlers.saveCrafting(1,{recipes=r}).ok==false);assert(saved==nil)')
lua.execute('ace=true;local r=MetaComic.Crafting.all();r[1].minigame.rows=4;r[1].minigame.cols=4;assert(MetaComic.RpcHandlers.saveCrafting(1,{recipes=r}).ok==false)')
lua.execute('local r=MetaComic.Crafting.all();r[1].minigame.rewardPacks=7;assert(MetaComic.RpcHandlers.saveCrafting(1,{recipes=r}).ok);assert(MetaComic.Crafting.all()[1].minigame.rewardPacks==7)')
lua.execute("local r=MetaComic.Crafting.all();r[1].minigame.rewardPacks=3;assert(MetaComic.RpcHandlers.saveCrafting(1,{recipes=r}).ok);local before=#grants;events['meta_comic:server:craftingStart'](0,'pack',10,'other');assert(checked==16);for i=1,4 do now=now+40000;finish(1)end;assert(grants[before+1]==3 and grants[before+2]==4 and grants[before+3]==3 and grants[before+4]==2)")
lua.execute("local before=#grants;events['meta_comic:server:craftingStart'](0,'pack',10,'other');now=now+40000;finish(1);now=now+40000;finish(1);assert(grants[before+2]==4);events['meta_comic:server:craftingCancel']();now=now+40000;finish(1);assert(#grants==before+2)")
lua.execute("local r=MetaComic.Crafting.all();r[1].minigame.rows=6;assert(MetaComic.RpcHandlers.saveCrafting(1,{recipes=r}).ok);start();assert(lastEvent[4].bonusSeconds==360);now=now+240000;events['meta_comic:server:craftingFinish']({errors=0,printed=true,inspected=true,packs=6,folds=6,seals=6,cuts=29});assert(grants[#grants]==4)")
lua.execute("local r=MetaComic.Crafting.all();r[1].minigame.scaleBonusTime=false;r[1].minigame.bulkBonusPacks=0;assert(MetaComic.RpcHandlers.saveCrafting(1,{recipes=r}).ok);start();assert(lastEvent[4].bonusSeconds==180);now=now+240000;events['meta_comic:server:craftingFinish']({errors=0,printed=true,inspected=true,packs=6,folds=6,seals=6,cuts=29});assert(grants[#grants]==3)")
lua.execute("ace=false;local r=MetaComic.Crafting.all();r[1].minigame.bulkBonusPacks=10;assert(not MetaComic.RpcHandlers.saveCrafting(1,{recipes=r}).ok);ace=true")
print('Bulk crafting: milestone extras survive cancellation, mistakes retain guaranteed extras, partial batches pay exact counts, capacity includes all bonuses, larger sheets scale perfect time, disabling and ACE checks passed.')
print('Crafting server: early/replayed/invalid/cancelled results rejected; server timed bonus; ingredient/capacity rechecks; reward quantity bounded by saved recipe; ACE and invalid grid checks passed.')

# Exercise actual sealed metadata capacity/give helpers, including same-set stacking.
capacity=LuaRuntime()
capacity.execute("Config={Items={BoosterPack='pack',BoosterBox='box'}};MetaComic={Sets={get=function()return {id='other',name='Other',code='OTH'}end},Inventory={name='ox_inventory',canCarry=function(_,item,count,metadata)lastMetadata=metadata;return metadata and metadata.setId=='other' and count<=4 end,add=function(_,item,count,metadata)addedMetadata=metadata;return true end}};setById=function()return MetaComic.Sets.get()end")
main=(Path(__file__).resolve().parents[1]/'fivem/server/main.lua').read_text(encoding='utf-8')
capacity.execute(main[main.index('local function sealedMetadata'):main.index('local function metadataSetId')])
capacity.execute((Path(__file__).resolve().parents[1]/'fivem/server/modules/rewards.lua').read_text(encoding='utf-8'))
capacity.execute("assert(MetaComic.Rewards.types.sealed.canGive(1,{kind='pack',set='other',count=4},1));assert(not MetaComic.Rewards.types.sealed.canGive(1,{kind='pack',set='other',count=5},1));assert(MetaComic.GiveSealed(1,'pack','other',4));assert(lastMetadata.setId==addedMetadata.setId and lastMetadata.label==addedMetadata.label)")
print('Sealed capacity: set metadata matches the reward transaction; full order plus possible bonuses checked before start.')
