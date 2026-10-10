"""Check legacy drilling migration, builtin routing and timeout/result handling."""
from pathlib import Path
import sys
sys.path.insert(0, str(Path(__file__).resolve().parents[1]/'.tmp-mysql-tests'))
from lupa.lua54 import LuaRuntime
lua=LuaRuntime()
lua.execute('''
Config={Minigames={drill_hard={type='builtin',game='sequence',level='hard'},
pick={type='qb-minigames',game='Lockpick'},cut={type='builtin',game='grinder',time=60},wiring={type='builtin',game='skimmer'}}}
MetaComic={CopyTable=function(t)local o={} for k,v in pairs(t)do o[k]=v end return o end}
callbacks={} messages={} timers={} focus={}
RegisterNUICallback=function(name,fn)callbacks[name]=fn end
AddEventHandler=function()end
GetGameTimer=function()return 100 end
GetResourceState=function()return 'missing' end
SetTimeout=function(ms,fn)timers[#timers+1]={ms=ms,fn=fn} end
SetNuiFocus=function(a,b)focus[#focus+1]=a end
exports=function()end
promise={new=function()return {resolve=function(self,value)self.value=value end}end}
Citizen={Await=function(p)return p.value end}
SendNUIMessage=function(m)
 messages[#messages+1]=m
 if m.mode=='minigame' then
  callbacks.minigameResult({id='wrong',success=true},function()end)
  callbacks.minigameResult({id=m.minigame.id,success=true},function()end)
 end
end
''')
lua.execute((Path(__file__).resolve().parents[1]/'fivem/client/minigames.lua').read_text(encoding='utf-8'))
lua.execute('''
assert(MetaComic.RunMinigames('drill_hard'))
assert(messages[1].minigame.game=='drill' and messages[1].minigame.theme=='camlock')
assert(Config.Minigames.drill_hard.game=='sequence') -- preserve caller's config
assert(timers[1].ms==85000)
assert(focus[1]==true and focus[2]==false)
assert(MetaComic.RunMinigames('pick'))
assert(messages[3].minigame.game=='lockpick')
assert(MetaComic.RunMinigames('cut'))
assert(messages[5].minigame.game=='grinder' and timers[3].ms==75000)
assert(MetaComic.RunMinigames('wiring'))
assert(messages[7].minigame.game=='skimmer' and timers[4].ms==135000)
local list
callbacks.getMinigames({},function(r)list=r.presets end)
for _,p in ipairs(list)do assert(p.type=='builtin' and p.available)end
assert(MetaComic.RunMinigames('wiring', {solderMode='trace',drift=true}))
assert(messages[#messages-1].minigame.solderMode=='trace' and messages[#messages-1].minigame.drift==true)
assert(Config.Minigames.wiring.solderMode==nil and Config.Minigames.wiring.drift==nil)
assert(MetaComic.RunMinigames({game='skimmer',solderMode='steady'}, {drift=false}))
assert(messages[#messages-1].minigame.solderMode=='steady' and messages[#messages-1].minigame.drift==false)
assert(MetaComic.RunMinigames({'wiring','wiring'}, {solderMode='steady'}))
assert(messages[#messages-1].minigame.solderMode=='steady')
-- A foreign/stale result cannot finish a game; its safety timeout returns false.
SendNUIMessage=function(m)if m.mode=='minigame' then
 callbacks.minigameResult({id='foreign',success=true},function()end)
 timers[#timers].fn()
end end
assert(not MetaComic.RunMinigames('cut'))
''')
print('Shear routing: legacy drill, external lockpick, grinder, config preservation, matching result, timeout and admin listings passed.')
