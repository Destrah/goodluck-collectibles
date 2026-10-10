"""Ambient witness filters and token-authorized, deduplicated dispatch."""
from pathlib import Path
import sys
sys.path.insert(0,str(Path(__file__).resolve().parents[1]/'.tmp-mysql-tests'))
from lupa.lua54 import LuaRuntime
root=Path(__file__).resolve().parents[1]
for rejected in ['none','mission','player','dead','animal','script','blocked','away','far']:
 lua=LuaRuntime()
 lua.execute('''
 Config={Police={Witness={}}};MetaComic={};events={};reported=0;running=true
 exports=function() end
 RegisterNetEvent=function(n,f)events[n]=f end
 TriggerServerEvent=function()reported=reported+1 end
 CreateThread=function(f)thread=f end
 Wait=function()running=false end
 PlayerPedId=function()return 1 end
 GetGamePool=function()return {1,2} end
 local mt={__sub=function(a,b)return setmetatable({x=a.x-b.x,y=a.y-b.y,z=a.z-b.z},getmetatable(a))end,__len=function(a)return math.sqrt(a.x*a.x+a.y*a.y+a.z*a.z)end}
 GetEntityCoords=function(p)return setmetatable({x=p==1 and 0 or 5,y=0,z=0},mt)end
 GetEntityPopulationType=function()return 5 end
 IsPedAPlayer=function(p)return p==1 end
 IsPedHuman=function()return true end
 IsEntityDead=function()return false end
 IsEntityAMissionEntity=function()return false end
 GetEntityForwardVector=function()return {x=-1,y=0,z=0}end
 HasEntityClearLosToEntity=function()return true end
 ''')
 overrides={'mission':'IsEntityAMissionEntity=function()return true end','player':'IsPedAPlayer=function()return true end','dead':'IsEntityDead=function()return true end','animal':'IsPedHuman=function()return false end','script':'GetEntityPopulationType=function()return 7 end','blocked':'HasEntityClearLosToEntity=function()return false end','away':'GetEntityForwardVector=function()return {x=1,y=0,z=0}end','far':'Config.Police.Witness.Radius=1'}
 if rejected in overrides:lua.execute(overrides[rejected])
 lua.execute((root/'fivem/client/police.lua').read_text(encoding='utf-8'))
 lua.execute("MetaComic.WatchCrimeWitness('token',function()return running end);thread()")
 assert lua.eval('reported')==(1 if rejected=='none' else 0),rejected
lua=LuaRuntime()
lua.execute('''
Config={Police={System='custom',CrimeRules={default={witness=100,fail=100,success=100}},Custom=function()dispatches=dispatches+1 end}}
MetaComic={Vending={near=function()return nearby end,reach=function()return 2 end}}
nearby=true;active=true;dispatches=0;now=0;source=9;events={}
GetGameTimer=function()return now end
GetResourceState=function()return 'started' end
RegisterNetEvent=function(n,f)events[n]=f end
exports=function()end
''')
lua.execute((root/'fivem/server/modules/police.lua').read_text(encoding='utf-8'))
lua.execute('''
job={token='token',action='breakin',duration=10000};entry={serial='vm',x=0,y=0,z=0}
MetaComic.Police.watch(9,job,entry,'breakin',function()return active end)
events['meta_comic:server:crimeWitness']('wrong');assert(dispatches==0)
nearby=false;events['meta_comic:server:crimeWitness']('token');assert(dispatches==0)
nearby=true;active=false;events['meta_comic:server:crimeWitness']('token');assert(dispatches==0)
active=true;events['meta_comic:server:crimeWitness']('token');assert(dispatches==1)
events['meta_comic:server:crimeWitness']('token');assert(dispatches==1)
MetaComic.Police.attempt(9,job,entry,'breakin','success');assert(dispatches==1)
job={token='next'};MetaComic.Police.watch(9,job,entry,'breakin',function()return true end)
now=400000;events['meta_comic:server:crimeWitness']('next');assert(dispatches==1)
''')
print('Witness checks: ambient/player/mission/dead/animal/population/sight/facing/range filters, token, active job, expiry and dispatch deduplication passed.')
