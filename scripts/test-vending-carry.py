"""Exercise server towing, snapping and drop/pickup with isolated FiveM stubs."""
from pathlib import Path
import sys
import unittest

if len(sys.argv) > 1:
    sys.path.insert(0, sys.argv.pop(1))
from lupa.lua54 import LuaRuntime

ROOT = Path(__file__).resolve().parents[1]


class VendingCarryTests(unittest.TestCase):
    def setUp(self):
        self.lua = LuaRuntime(unpack_returned_tuples=True)
        self.lua.execute('''
          local mt={}
          function vector3(x,y,z) return setmetatable({x=x,y=y,z=z},mt) end
          mt.__add=function(a,b) return vector3(a.x+b.x,a.y+b.y,a.z+b.z) end
          mt.__sub=function(a,b) return vector3(a.x-b.x,a.y-b.y,a.z-b.z) end
          mt.__mul=function(a,b) return vector3(a.x*b,a.y*b,a.z*b) end
          mt.__len=function(a) return math.sqrt(a.x*a.x+a.y*a.y+a.z*a.z) end
          Config={VendingMachines={},VendingCarry={VehicleEntry='block',Tow={Length=6,Snap={Enabled=true,Duration=600,GracePeriod=3000,MaxSpeedKmh=100}}}}
          handlers={};stopHandlers={};threads={};events={};states={};now=0;speed=0
          coords={[1]=vector3(0,0,0),[200]=vector3(0,0,0)}
          metadata={serial='VM-TEST',products={{stock=7}},cash=42}
          item=true;adds=0;removes=0;updates=0;writes=0
          MetaComic={Inventory={},Vending={},VendingRegistry={},Framework={}}
          local inv=MetaComic.Inventory
          inv.slotsOf=function() return item and {{slot=3,metadata=metadata}} or {} end
          inv.remove=function(_,_,_,identity,slot)
            assert(identity.serial=='VM-TEST' and slot==3)
            if not item then return false end
            item=false;removes=removes+1;return true
          end
          MetaComic.Vending.giveMachineItem=function(_,serial,products,cash)
            assert(serial=='VM-TEST' and products[1].stock==7 and cash==42)
            adds=adds+1;item=true;return true
          end
          local r=MetaComic.VendingRegistry
          r.get=function() return {status='stolen'} end
          r.nameOf=function() return 'Player' end
          r.identifierOf=function() return 'license:player' end
          r.update=function() updates=updates+1 end
          r.onlineSource=function() return nil end
          function RegisterNetEvent(name,fn) handlers[name]=fn end
          function AddEventHandler(name,fn) stopHandlers[name]=fn end
          function CreateThread(fn) threads[#threads+1]=coroutine.create(fn) end
          function Wait() coroutine.yield() end
          function step(time) now=time;local ok,err=coroutine.resume(threads[1]);assert(ok,err) end
          function SetTimeout(_,fn) pendingDelete=fn end
          function GetGameTimer() return now end
          function GetCurrentResourceName() return 'test' end
          function LoadResourceFile() return nil end
          function SaveResourceFile() writes=writes+1;return true end
          json={decode=function() return nil end,encode=function() return '{}' end}
          function joaat() return 123 end
          function NetworkGetEntityFromNetworkId(id) return coords[id] and id or 0 end
          function NetworkGetNetworkIdFromEntity(id) return id end
          function DoesEntityExist(id) return coords[id]~=nil end
          function GetEntityType(id) return id==200 and 2 or 3 end
          function GetPlayerPed() return 1 end
          function GetVehiclePedIsIn() return 0 end
          function GetEntityCoords(id) return coords[id] end
          function GetEntityHeading() return 0 end
          function SetEntityHeading() end
          function GetEntitySpeed() return speed end
          function FreezeEntityPosition() end
          function CreateObjectNoOffset(_,x,y,z) coords[100]=vector3(x,y,z);return 100 end
          function DeleteEntity(id) coords[id]=nil end
          function Entity(id)
            if not states[id] then states[id]={set=function(self,k,v) self[k]=v end} end
            return {state=states[id]}
          end
          function GetPlayerPing() return 100 end
          function TriggerClientEvent(name,_,...)
            events[#events+1]={name=name,args={...}}
          end
          function countEvent(name)
            local count=0;for _,e in ipairs(events) do if e.name==name then count=count+1 end end;return count
          end
          source=1
        ''')
        self.lua.execute((ROOT / 'fivem/server/modules/vending_carry.lua').read_text(encoding='utf-8'))

    def tow(self):
        self.lua.execute("handlers['meta_comic:server:vendingTow'](200);states[100].metaComicTowNeedsGround=false;step(0);step(0)")

    def test_snap_requires_grace_and_continuous_overload(self):
        self.tow()
        self.lua.execute('speed=40;step(1000);step(3000);step(3400);speed=0;step(3500);speed=40;step(3600);step(4199)')
        self.assertEqual(self.lua.eval("countEvent('meta_comic:client:vendingRopeSnapped')"), 0)
        self.lua.execute('step(4200);step(5000)')
        self.assertEqual(self.lua.eval("countEvent('meta_comic:client:vendingRopeSnapped')"), 1)
        self.assertEqual(self.lua.eval('adds'), 0)
        self.assertTrue(self.lua.eval('DoesEntityExist(100)'))

    def test_distance_snap_and_pickup_require_proximity_to_machine(self):
        self.tow()
        self.lua.execute("coords[100]=vector3(20,0,0);step(3000);step(3600);handlers['meta_comic:server:vendingUntow'](100)")
        self.assertEqual(self.lua.eval('adds'), 0)
        self.lua.execute("coords[1]=vector3(20,0,0);handlers['meta_comic:server:vendingUntow'](100);handlers['meta_comic:server:vendingUntow'](100)")
        self.assertEqual(self.lua.eval('adds'), 1)

    def test_speed_limit_can_be_disabled(self):
        self.lua.execute('Config.VendingCarry.Tow.Snap.MaxSpeedKmh=0')
        self.tow()
        self.lua.execute('speed=100;step(3000);step(10000)')
        self.assertEqual(self.lua.eval("countEvent('meta_comic:client:vendingRopeSnapped')"), 0)

    def test_snapping_can_be_disabled_entirely(self):
        self.lua.execute('Config.VendingCarry.Tow.Snap.Enabled=false')
        self.lua.execute("handlers['meta_comic:server:vendingTow'](200);states[100].metaComicTowNeedsGround=false;step(0)")
        self.assertEqual(self.lua.eval("coroutine.status(threads[1])"), 'dead')
        self.assertEqual(self.lua.eval("countEvent('meta_comic:client:vendingRopeSnapped')"), 0)

    def test_physics_mass_and_owner_migration(self):
        self.tow()
        self.lua.execute('''
          Config.VendingCarry.Tow.Physics={Mass=450,LinearDamping=0.2,AngularDamping=0.8}
          owned=true;physicsCalls=0
          function NetworkDoesNetworkIdExist(id) return coords[id]~=nil end
          function NetworkHasControlOfEntity() return owned end
          function SetObjectPhysicsParams(...) physicsCalls=physicsCalls+1;physicsArgs={...} end
          function SetEntityDynamic() end
          function SetEntityHasGravity() end
          function ActivatePhysics() end
          function SetEntityCollision() end
          function SetEntityLoadCollisionFlag() end
        ''')
        self.lua.execute((ROOT / 'fivem/client/vending_carry.lua').read_text(encoding='utf-8'))
        self.lua.execute("handlers['meta_comic:client:vendingRopeSnapped'](100);assert(coroutine.resume(threads[5]))")
        self.assertEqual(self.lua.eval('physicsArgs[2]'), 450)
        self.assertEqual(self.lua.eval('physicsArgs[5]'), 0.2)
        self.assertEqual(self.lua.eval('physicsArgs[8]'), 0.8)
        self.lua.execute('assert(coroutine.resume(threads[5]))')
        self.assertEqual(self.lua.eval('physicsCalls'), 1)
        self.lua.execute('owned=false;assert(coroutine.resume(threads[5]));owned=true;assert(coroutine.resume(threads[5]))')
        self.assertEqual(self.lua.eval('physicsCalls'), 2)
        self.lua.execute('Config.VendingCarry.Tow.Physics.Enabled=false;owned=false;assert(coroutine.resume(threads[5]));owned=true;assert(coroutine.resume(threads[5]))')
        self.assertEqual(self.lua.eval('physicsCalls'), 2)

    def test_drop_mode_preserves_stock_cash_and_prevents_duplicate_drop(self):
        self.lua.execute("Config.VendingCarry.VehicleEntry='drop';handlers['meta_comic:server:vendingCarryDrop']();handlers['meta_comic:server:vendingCarryDrop']()")
        self.assertEqual(self.lua.eval('removes'), 1)
        self.lua.execute("handlers['meta_comic:server:vendingUntow'](100)")
        self.assertEqual(self.lua.eval('adds'), 1)

    def test_block_mode_rejects_drop_event(self):
        self.lua.execute("handlers['meta_comic:server:vendingCarryDrop']()")
        self.assertEqual(self.lua.eval('removes'), 0)
        self.assertFalse(self.lua.eval('DoesEntityExist(100)'))

    def test_vehicle_entry_modes_block_control_and_only_drop_when_configured(self):
        self.lua.execute('''
          exports={ox_inventory={GetItemCount=function() return 1 end}}
          function GetResourceState() return 'started' end
          function PlayerPedId() return 1 end
          function PlayerId() return 1 end
          function DisableControlAction(_,control) if control==23 then entryBlocked=true end end
          function IsDisabledControlJustPressed() return true end
          function GetVehiclePedIsTryingToEnter() return 0 end
          function TriggerServerEvent(name) if name=='meta_comic:server:vendingCarryDrop' then requestedDrops=(requestedDrops or 0)+1 end end
          function TriggerEvent() end
          function IsPedInAnyVehicle() return false end
          function IsPedSwimming() return false end
          function IsPedRagdoll() return false end
          function IsEntityDead() return false end
          function IsPedClimbing() return false end
          function IsPedFalling() return false end
          function IsModelInCdimage() return false end
          function SetCurrentPedWeapon() end
          function DisablePlayerFiring() end
          function SetPedMaxMoveBlendRatio() end
          function SetPedMoveRateOverride() end
        ''')
        self.lua.execute((ROOT / 'fivem/client/vending_carry.lua').read_text(encoding='utf-8'))
        self.lua.execute('local ok,e=coroutine.resume(threads[4]);assert(ok,e);ok,e=coroutine.resume(threads[8]);assert(ok,e)')
        self.assertTrue(self.lua.eval('entryBlocked'))
        self.assertIsNone(self.lua.eval('requestedDrops'))
        self.lua.execute("Config.VendingCarry.VehicleEntry='drop';now=2000;local ok,e=coroutine.resume(threads[8]);assert(ok,e)")
        self.assertEqual(self.lua.eval('requestedDrops'), 1)

    def test_stop_does_not_start_inventory_or_registry_writes(self):
        self.tow()
        before = self.lua.eval('updates')
        self.lua.execute("stopHandlers.onResourceStop('test')")
        self.assertEqual(self.lua.eval('adds'), 0)
        self.assertEqual(self.lua.eval('updates'), before)
        self.assertTrue(self.lua.eval('DoesEntityExist(100)'))

    def test_client_and_config_compile(self):
        for name in ['fivem/client/vending_carry.lua', 'fivem/config.lua']:
            result = self.lua.eval('load')((ROOT / name).read_text(encoding='utf-8'))
            self.assertFalse(isinstance(result, tuple), str(result))


if __name__ == '__main__':
    unittest.main()
