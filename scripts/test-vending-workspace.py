"""Nested vending workspace and partial reopening visuals using the real Lua code."""
from pathlib import Path
import sys
sys.path.insert(0,str(Path(__file__).resolve().parents[1]/'.tmp-mysql-tests'))
from lupa.lua54 import LuaRuntime
root=Path(__file__).resolve().parents[1]
lua=LuaRuntime()
lua.execute('''
Config={};cfg={Keys={Enabled=true}};MetaComic={};contexts={};shown={};threads={};events={};requests={};busy=false
local mt={__sub=function(a,b)return a end,__len=function()return far and 10 or 0 end}
GetEntityCoords=function()return setmetatable({},mt)end
GetResourceState=function()return 'started'end
DoesEntityExist=function()return true end
PlayerPedId=function()return 1 end
MetaComic.VendingMachineById=function()return {entity=10}end
MetaComic.VendingKeyWorkBusy=function()return busy end
CreateThread=function(f)threads[#threads+1]=coroutine.create(f)end
Wait=function()coroutine.yield()end
RegisterNetEvent=function(n,f)events[n]=f end
TriggerServerEvent=function(n,...)requests[#requests+1]={name=n,args={...}}end
lib={getOpenContextMenu=function() return visible end}
exports={ox_lib={registerContext=function(_,c)contexts[c.id]=c end,showContext=function(_,id)shown[#shown+1]=id;visible=id end,hideContext=function()hidden=true end}}
''')
source=(root/'fivem/client/vending_machines.lua').read_text(encoding='utf-8')
lua.execute(source[source.index('local workspace'):source.index('local function input(',source.index('local workspace'))])
lua.execute('''
MetaComic.OpenVendingManage(1)
assert(contexts.meta_comic_vending_manage_root.options[1].title=='Cabinet lock / keys')
assert(contexts.meta_comic_vending_manage_root.options[2].title=='Restock')
assert(contexts.meta_comic_vending_manage_root.options[3].title=='Machine management')
contexts.meta_comic_vending_manage_root.options[1].onSelect()
assert(requests[#requests].name=='meta_comic:server:vendingKeyMenu')
MetaComic.VendingContextMenu('meta_comic_vending_keys','Keys',{{title='Action',onSelect=function()actions=(actions or 0)+1 end}},'meta_comic_vending_manage_root')
assert(contexts.meta_comic_vending_keys.menu=='meta_comic_vending_manage_root')
contexts.meta_comic_vending_keys.options[1].onSelect()
assert(actions==1)
local actionThread=threads[#threads]
busy=true;assert(coroutine.resume(actionThread));busy=false;assert(coroutine.resume(actionThread))
assert(requests[#requests].name=='meta_comic:server:vendingKeyMenu')
-- No timer-based reopen; duplicate completion signals produce one snapshot request.
local before=#shown
visible=nil
requests={}
MetaComic.VendingContextMenu('meta_comic_vending_keys','Keys',{{title='Action',onSelect=function()end}},'meta_comic_vending_manage_root')
visible=nil
before=#shown
contexts.meta_comic_vending_keys.options[1].onSelect()
events['meta_comic:client:vendingMenuRefresh'](1)
assert(#shown==before and #requests==0)
assert(coroutine.resume(threads[#threads]))
assert(#requests==1 and #shown==before)
events['meta_comic:client:vendingMenuRefresh'](1)
assert(#requests==1)
MetaComic.VendingContextMenu('meta_comic_vending_keys','Updated keys',{{title='Close cabinet'}},'meta_comic_vending_manage_root')
assert(#shown==before+1)
-- An unsolicited duplicate snapshot updates registration without reopening a visible menu.
MetaComic.VendingContextMenu('meta_comic_vending_keys','Updated keys',{{title='Close cabinet'}},'meta_comic_vending_manage_root')
assert(#shown==before+1)
contexts.meta_comic_vending_keys.onBack()
events['meta_comic:client:vendingMenuRefresh'](1)
assert(shown[#shown]=='meta_comic_vending_manage_root')
contexts.meta_comic_vending_manage_root.onExit()
assert(MetaComic.VendingMenuActive==nil)
MetaComic.OpenVendingManage(1);far=true;assert(coroutine.resume(threads[#threads]));assert(hidden and MetaComic.VendingMenuActive==nil)
''')
# Actual restock option must wait across the request/animation latency gap.
lua.execute("far=false;needsOxLib=function()return true end;productTitle=function()return 'Base Pack'end;productIcon=function()return 'box'end;productImage=function()end;menu=MetaComic.VendingContextMenu;input=function()return dialogAnswer end;MAX_STOCK=100;MetaComic.OpenVendingManage(1)")
a=source.index('local function openRestock(');b=source.index('-- the server answers Buy / Restock',a)
lua.execute(source[a:b]+'\nTestOpenRestock=openRestock')
lua.execute("""
TestOpenRestock({id=1,products={{set='base',kind='pack',stock=0}}},100)
assert(contexts.meta_comic_vending_restock.options[1].waitForResponse)
requests={};dialogAnswer={5};visible=nil;local before=#shown
contexts.meta_comic_vending_restock.options[1].onSelect()
assert(#requests==1 and requests[1].name=='meta_comic:server:vendingRestock')
-- The server hasn't started the animation yet: do not fetch or reveal the old stock.
assert(coroutine.resume(threads[#threads]));assert(#requests==1 and #shown==before)
busy=true;assert(#requests==1)
-- Final server acknowledgement asks for a fresh snapshot, then displays that snapshot once.
busy=false;events['meta_comic:client:vendingMenuRefresh'](1)
assert(#requests==2 and requests[2].name=='meta_comic:server:vendingOpen' and #shown==before)
TestOpenRestock({id=1,products={{set='base',kind='pack',stock=5}}},100)
assert(#shown==before+1 and contexts.meta_comic_vending_restock.options[1].description=='Stock 5 / 100')
-- Dismissing the amount dialog must restore the menu without waiting for a nonexistent action.
dialogAnswer=nil;requests={};visible=nil;contexts.meta_comic_vending_restock.options[1].onSelect()
assert(coroutine.resume(threads[#threads]));assert(#requests==1 and requests[1].name=='meta_comic:server:vendingOpen')
""")
lua=LuaRuntime()
lua.execute('''
Config={VendingMachines={Door={CancelAjarFraction=.18,CancelReopenSpeed=.35}}};MetaComic={};handlers={};threads={}
vec3=function(x,y,z)return {x=x,y=y,z=z}end;vector3=vec3
joaat=function()return 1 end
GetResourceState=function()return 'missing'end
IsModelInCdimage=function()return true end
RegisterNetEvent=function(n,f)handlers[n]=f end
CreateThread=function(f)threads[#threads+1]=f end
AddEventHandler=function()end
''')
lua.execute((root/'fivem/client/vending_door.lua').read_text(encoding='utf-8')+'\nTestDoorState=function(id)return doors[id]end;TestDiscardDoor=function(id)doors[id]=nil end')
lua.execute('''
handlers['meta_comic:client:vendingDoor'](1,true)
handlers['meta_comic:client:vendingDoor'](1,false,nil,true)
assert(TestDoorState(1).serverOpen==true and TestDoorState(1).target==0)
handlers['meta_comic:client:vendingDoor'](1,true,nil,true)
handlers['meta_comic:client:vendingAjar'](1,{cabinet=true,cashbox=true})
assert(MetaComic.VendingIsAjar(1))
assert(math.abs(TestDoorState(1).target-105*.18)<.001)
assert(TestDoorState(1).reopenSpeed==.35)
assert(TestDoorState(1).ajar.cashbox and not TestDoorState(1).ajar.rack)
handlers['meta_comic:client:vendingAjar'](1,nil)
assert(not MetaComic.VendingIsAjar(1) and TestDoorState(1).target==105)
assert(TestDoorState(1).reopenSpeed==nil)
-- A fully closed preview removes its props; cancellation must still recreate an ajar cabinet.
handlers['meta_comic:client:vendingDoor'](1,false,nil,true)
TestDiscardDoor(1)
handlers['meta_comic:client:vendingDoor'](1,true)
handlers['meta_comic:client:vendingAjar'](1,{cabinet=true})
assert(math.abs(TestDoorState(1).target-105*.18)<.001)
handlers['meta_comic:client:vendingAjar'](1,nil)
-- Rack cancellation never changes the cabinet target, even if the visual state is incomplete.
TestDoorState(1).serverOpen=nil
handlers['meta_comic:client:vendingAjar'](1,{rack=true})
assert(TestDoorState(1).target==105 and TestDoorState(1).ajar.rack)
handlers['meta_comic:client:vendingAjar'](1,nil)
assert(TestDoorState(1).target==105)
''')
print('Vending workspace: nested root/back navigation, action restoration, refreshed keys, explicit exit/range cleanup; door preview, partial target and slow reopening passed.')

# The damaged-cabinet menu must offer authentication again after a key is recovered.
lua=LuaRuntime()
lua.execute("""
MetaComic={VendingContextMenu=function(id,title,options) menuOptions=options end}
GetResourceState=function() return 'started' end
RegisterNetEvent=function(name,fn) menuHandler=fn end
useKeyAtLock=function(...) keyArgs={...} end
""")
source=(root/'fivem/client/vending_keys.lua').read_text(encoding='utf-8')
a=source.index("RegisterNetEvent('meta_comic:client:vendingKeyMenu'")
b=source.index("RegisterNetEvent('meta_comic:client:vendingRekeyStart'",a)
lua.execute(source[a:b])
lua.execute("""
local data={id=1,serial='VM-1',lockId='C1',condition='damaged',damagedUnsealed=true,hasKey=true,hasFull=true,boxEnabled=true,rackEnabled=true}
menuHandler(data)
local found
for _,option in ipairs(menuOptions) do
    if option.title=='Authenticate cabinet key' then found=option end
end
assert(found and not found.disabled)
found.onSelect()
assert(keyArgs[2]=='cylinder' and keyArgs[3]=='door' and keyArgs[4]==true)
data.cabinetOpen=true;data.session=true;data.fullSession=true
menuHandler(data)
local box,rack
for _,option in ipairs(menuOptions) do
    box=box or option.title=='Open cash box'
    rack=rack or option.title=='Open server rack'
    assert(option.title~='Close and lock cabinet')
end
assert(box and rack)
""")
print('Recovered-key damaged cabinet authentication and interior menu options passed.')
