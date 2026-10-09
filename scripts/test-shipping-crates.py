"""Shipping crate admin grants: permission checks, identity metadata and rollback."""
from pathlib import Path
import sys
import unittest
if len(sys.argv)>1: sys.path.insert(0,sys.argv.pop(1))
from lupa.lua54 import LuaRuntime
ROOT=Path(__file__).resolve().parents[1]

class CrateTests(unittest.TestCase):
    def setUp(self):
        self.lua=LuaRuntime(unpack_returned_tuples=True)
        self.lua.execute('''
            Config={Items={},ShippingCrates={Default='mixed',GiveCommand='givecrate',Crates={mixed={label='Mixed crate',contents={{type='item',item='boosterbox',count=2}}},cards={label='Cards crate',contents={}}}}}
            MetaComic={Inventory={},Framework={},RpcHandlers={},Rewards={}}
            MetaComic.CanManageReal=function(source) return source==1 end
            MetaComic.CanManage=function() return true end -- a test-role impersonation must not grant items
            types={};commands={};events={};registered={};inventory={};added=0;removed=0;canCarry=true
            MetaComic.Rewards.register=function(kind,definition) types[kind]=definition end
            MetaComic.Rewards.label=function() return '2 booster boxes' end
            MetaComic.Rewards.give=function(source,result,amount) return types[result.type].give(source,result,amount) end
            MetaComic.Framework.notify=function(_,message) notice=message end
            MetaComic.Inventory.canCarry=function(_,name,count) checkedCount=count;return canCarry end
            MetaComic.Inventory.add=function(_,name,count,metadata)
                added=added+1;if failAt==added then return false end
                inventory[metadata.instanceId]=metadata;return true
            end
            MetaComic.Inventory.remove=function(_,name,count,identity)
                if not inventory[identity.instanceId] then return false end
                inventory[identity.instanceId]=nil;removed=removed+1;return true
            end
            function GetGameTimer() return 123 end
            function RegisterCommand(name,fn) commands[name]=fn end
            function RegisterNetEvent(name,fn) events[name]=fn end
            function AddEventHandler() end
            exports=function(name,fn) registered[name]=fn end
            function inventoryCount() local count=0;for _ in pairs(inventory) do count=count+1 end;return count end
        ''')
        self.lua.execute((ROOT/'fivem/server/modules/shipping_crates.lua').read_text())

    def test_real_admin_choices_and_no_test_role_impersonation(self):
        self.assertEqual(self.lua.eval('#MetaComic.RpcHandlers.getShippingCrates(1).crates'),2)
        self.assertFalse(self.lua.eval('MetaComic.RpcHandlers.createShippingCrate(2,{crate="mixed",amount=1}).ok'))
        self.assertEqual(self.lua.eval('added'),0)

    def test_grant_keeps_distinct_serial_identity_and_configured_contents(self):
        self.assertTrue(self.lua.eval('MetaComic.RpcHandlers.createShippingCrate(1,{crate="mixed",amount=2}).ok'))
        self.assertEqual(self.lua.eval('checkedCount'),2)
        self.assertEqual(self.lua.eval('inventoryCount()'),2)
        self.assertTrue(self.lua.eval('(function() local serial;for _,metadata in pairs(inventory) do if metadata.crate~="mixed" or metadata.description~="Contains 2 booster boxes" or metadata.serial==serial then return false end;serial=metadata.serial end;return true end)()'))

    def test_capacity_preflight_adds_nothing(self):
        self.lua.execute('canCarry=false')
        self.assertFalse(self.lua.eval('MetaComic.RpcHandlers.createShippingCrate(1,{crate="mixed",amount=2}).ok'))
        self.assertEqual(self.lua.eval('added'),0)

    def test_failed_batch_rolls_back_only_new_crates(self):
        self.lua.execute('inventory.original={instanceId="original",crate="mixed"};failAt=2')
        self.assertFalse(self.lua.eval('MetaComic.RpcHandlers.createShippingCrate(1,{crate="mixed",amount=3}).ok'))
        self.assertEqual(self.lua.eval('removed'),1)
        self.assertEqual(self.lua.eval('inventoryCount()'),1)
        self.assertEqual(self.lua.eval('inventory.original.instanceId'),'original')

    def test_invalid_crate_and_fractional_quantity(self):
        self.assertFalse(self.lua.eval('MetaComic.RpcHandlers.createShippingCrate(1,{crate="missing",amount=1}).ok'))
        self.assertFalse(self.lua.eval('(MetaComic.ShippingCrates.give(1,"mixed",1.5))'))
        self.assertEqual(self.lua.eval('added'),0)

    def test_command_uses_real_permission_and_export_uses_same_grant(self):
        self.lua.execute('commands.givecrate(2,{"mixed","1"})')
        self.assertEqual(self.lua.eval('added'),0)
        self.lua.execute('commands.givecrate(1,{"cards","2"})')
        self.assertEqual(self.lua.eval('inventoryCount()'),2)
        self.assertTrue(self.lua.eval('registered.GiveShippingCrate(1,"cards",1)'))
        self.assertEqual(self.lua.eval('inventoryCount()'),3)

class CrateSceneTests(unittest.TestCase):
    def test_same_sealed_lid_detaches_and_falls_without_replacing_base(self):
        lua=LuaRuntime(unpack_returned_tuples=True)
        lua.execute('''
            Config={ShippingCrates={Models={Closed='base',Open='base',Lid='lid',SeparateLid=true},Animation={},Reveal3D=false}}
            MetaComic={};events={};objects={};nextObject=100;now=0;detached=0;deleted=0
            function vector3(x,y,z) return {x=x,y=y,z=z} end
            function joaat(name) return name=='base' and 1 or 2 end
            function IsModelInCdimage() return true end;function RequestModel() end;function HasModelLoaded() return true end
            function SetModelAsNoLongerNeeded() end
            function GetGameTimer() return now end;function Wait(ms) now=now+(ms>0 and ms or 16) end
            function PlayerPedId() return 10 end
            function GetEntityHeading() return 0 end
            function GetOffsetFromEntityInWorldCoords(id,x,y,z)
                local p=objects[id] or {x=0,y=0,z=1};return vector3(p.x+x,p.y+y,p.z+z)
            end
            function GetGroundZFor_3dCoord() return true,0 end
            function GetModelDimensions(model)
                if model==1 then return vector3(-0.5,-0.5,-0.3),vector3(0.5,0.5,0.7) end
                return vector3(-0.4,-0.4,-0.05),vector3(0.4,0.4,0.05)
            end
            function CreateObjectNoOffset(model,x,y,z) nextObject=nextObject+1;objects[nextObject]={model=model,x=x,y=y,z=z};return nextObject end
            function SetEntityHeading() end;function FreezeEntityPosition() end;function SetEntityCollision() end
            function DoesEntityExist(id) return objects[id]~=nil end
            function DeleteEntity(id) objects[id]=nil;deleted=deleted+1 end
            function GetEntityCoords(id) return vector3(objects[id].x,objects[id].y,objects[id].z) end
            function PlaceObjectOnGroundProperly(id) groundPlaced=id end
            function AttachEntityToEntity(id,parent,_,x,y,z)
                local p=objects[parent];objects[id].x=p.x+x;objects[id].y=p.y+y;objects[id].z=p.z+z;objects[id].parent=parent
            end
            function DetachEntity(id) objects[id].parent=nil;detached=detached+1 end
            function SetEntityCoordsNoOffset(id,x,y,z) objects[id].x=x;objects[id].y=y;objects[id].z=z end
            function SetEntityRotation() end;function TaskTurnPedToFaceCoord() end;function PlaySoundFrontend() end
            function GetResourceState() return 'started' end
            exports=setmetatable({ox_lib={progressBar=function() return true end}},{__call=function() end})
            function RegisterNetEvent(name,fn) events[name]=fn end
            function AddEventHandler(name,fn) events[name]=fn end
            function TriggerEvent(name,value) if name=='meta_comic:client:crateCarryPause' then paused=value end end
            function TriggerServerEvent(name) lastServerEvent=name end
            function SetTimeout() end;function CreateThread(fn) fn() end
            function GetCurrentResourceName() return 'cards' end
        ''')
        lua.execute((ROOT/'fivem/shared/vending_cargo_geometry.lua').read_text())
        lua.execute((ROOT/'fivem/client/shipping_crates.lua').read_text())
        lua.execute("events['meta_comic:client:crateStart']({duration=100})")
        self.assertEqual(lua.eval('objects[102].parent'),101)
        self.assertAlmostEqual(lua.eval('objects[102].z'),1.05)
        self.assertTrue(lua.eval('paused'))
        self.assertEqual(lua.eval('lastServerEvent'),'meta_comic:server:crateFinish')
        lua.execute("events['meta_comic:client:crateOpened']({contents={}})")
        self.assertEqual(lua.eval('nextObject'),102)
        self.assertEqual(lua.eval('detached'),1)
        self.assertIsNone(lua.eval('objects[102].parent'))
        self.assertAlmostEqual(lua.eval('objects[102].z'),0.05)
        self.assertFalse(lua.eval('paused'))
        lua.execute("events.onResourceStop('cards')")
        self.assertEqual(lua.eval('deleted'),2)

if __name__=='__main__':unittest.main()
