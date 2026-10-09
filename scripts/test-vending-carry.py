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
          function SetTimeout(ms,fn) if ms==30000 then initializationTimeout=fn else pendingDelete=fn end end
          function GetGameTimer() return now end
          function GetCurrentResourceName() return 'test' end
          function LoadResourceFile() return nil end
          function SaveResourceFile() writes=writes+1;return true end
          json={decode=function() return nil end,encode=function() return '{}' end}
          function joaat(name) lastHashedModel=name;return name=='metacomics_vending_body' and 124 or 123 end
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
          function FreezeEntityPosition(id,value) frozenEntities=frozenEntities or {};frozenEntities[id]=value end
          function CreateObjectNoOffset(model,x,y,z) spawnedModel=model;coords[100]=vector3(x,y,z);return 100 end
          function DeleteEntity(id) coords[id]=nil end
          function Entity(id)
            if not states[id] then states[id]={set=function(self,k,v) self[k]=v end} end
            return {state=states[id]}
          end
          function GetPlayerPing() return 100 end
          function NetworkGetEntityOwner() return 1 end
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

    def test_stolen_tow_uses_custom_body_collision(self):
        self.lua.execute("handlers['meta_comic:server:vendingTow'](200)")
        self.assertEqual(self.lua.eval('spawnedModel'), 124)

    def test_intact_tow_uses_complete_custom_machine(self):
        self.lua.execute("Config.VendingCarry.Tow.StolenOnly=false;MetaComic.VendingRegistry.get=function() return {status='owned'} end;handlers['meta_comic:server:vendingTow'](200)")
        self.assertEqual(self.lua.eval('spawnedModel'), 123)

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
          function NetworkHasControlOfEntity(id)
            if id==200 and carOwned~=nil then return carOwned end
            return owned
          end
          function NetworkRequestControlOfEntity(id) requestedControl=id end
          function SetObjectPhysicsParams(...) physicsCalls=physicsCalls+1;physicsArgs={...} end
          function SetEntityDynamic() end
          function SetEntityHasGravity() end
          function ActivatePhysics() end
          function SetActivateObjectPhysicsAsSoonAsItIsUnfrozen() end
          function TriggerServerEvent() end
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

    def setup_client_crate_carry(self, available=True):
        self.lua.execute('''
            Config.ShippingCrates={Models={Closed='crate'},Carry={Enabled=true,MoveRate=0.7}}
            Config.VendingCarry.VehicleEntry='drop'
            Config.VendingCarry.Dolly={model='dolly'}
            crateHeld=true;nextProp=300;spawnedCrates=0;spawnedDollies=0;collision={}
            exports={ox_inventory={GetItemCount=function(_,name) return name=='shipping_crate' and crateHeld and 1 or 0 end}}
            function GetResourceState() return 'started' end
            function PlayerPedId() return 1 end;function PlayerId() return 1 end
            function DisableControlAction(_,control) if control==23 then entryBlocked=true end end
            function IsDisabledControlJustPressed() return true end
            function GetVehiclePedIsTryingToEnter() return 0 end
            function TriggerServerEvent(name) if name=='meta_comic:server:vendingCarryDrop' then requestedDrops=(requestedDrops or 0)+1 end end
            function TriggerEvent() end
            function IsPedInAnyVehicle() return false end;function IsPedSwimming() return false end
            function IsPedRagdoll() return false end;function IsEntityDead() return false end
            function IsPedClimbing() return false end;function IsPedFalling() return false end
            function joaat(name) return name=='crate' and 27 or name=='dolly' and 28 or 123 end
            function IsModelInCdimage(model) return model~=27 or crateAvailable end;function RequestModel() end;function HasModelLoaded() return true end
            function SetModelAsNoLongerNeeded() end
            function CreateObject(model,x,y,z) assert(model==27 or model==28);if model==27 then spawnedCrates=spawnedCrates+1 else spawnedDollies=spawnedDollies+1 end;nextProp=nextProp+1;coords[nextProp]=vector3(x,y,z);return nextProp end
            function SetEntityCollision(id,value) collision[id]=value end
            function AttachEntityToEntity(id) assert(collision[id]==false) end
            function DetachEntity() end
            function GetModelDimensions() return vector3(-0.5,-0.5,-0.4),vector3(0.5,0.5,0.4) end
            function SetCurrentPedWeapon() end;function DisablePlayerFiring() end
            function SetPedMaxMoveBlendRatio() end;function SetPedMoveRateOverride(_,rate) moveRate=rate end
        ''')
        self.lua.execute('crateAvailable='+str(available).lower())
        self.lua.execute((ROOT/'fivem/client/vending_carry.lua').read_text())
        self.lua.execute('assert(coroutine.resume(threads[4]));assert(coroutine.resume(threads[8]))')

    def test_shipping_crate_carry_uses_crate_prop_pauses_for_opening_and_blocks_entry(self):
        self.setup_client_crate_carry()
        self.assertEqual(self.lua.eval('spawnedCrates'),1)
        self.assertEqual(self.lua.eval('moveRate'),0.7)
        self.assertTrue(self.lua.eval('entryBlocked'))
        self.assertIsNone(self.lua.eval('requestedDrops'))
        self.lua.execute("stopHandlers['meta_comic:client:crateCarryPause'](true);assert(coroutine.resume(threads[8]))")
        self.assertFalse(self.lua.eval('DoesEntityExist(301)'))
        self.assertEqual(self.lua.eval('spawnedCrates'),1)
        self.lua.execute("stopHandlers['meta_comic:client:crateCarryPause'](false);assert(coroutine.resume(threads[8]))")
        self.assertEqual(self.lua.eval('spawnedCrates'),2)
        self.lua.execute('crateHeld=false;assert(coroutine.resume(threads[4]));assert(coroutine.resume(threads[8]))')
        self.assertFalse(self.lua.eval('DoesEntityExist(304)'))

    def test_missing_crate_retries_without_duplicating_the_existing_dolly(self):
        self.setup_client_crate_carry(available=False)
        self.assertEqual(self.lua.eval('spawnedCrates'),0)
        self.assertEqual(self.lua.eval('spawnedDollies'),1)
        self.lua.execute('crateAvailable=true;now=6000;assert(coroutine.resume(threads[8]))')
        self.assertEqual(self.lua.eval('spawnedCrates'),1)
        self.assertEqual(self.lua.eval('spawnedDollies'),1)

    def test_vanished_cabinet_never_returns_inventory(self):
        self.tow()
        self.lua.execute('coords[100]=nil;assert(coroutine.resume(threads[2]));assert(coroutine.resume(threads[2]))')
        self.assertEqual(self.lua.eval('adds'), 0)

    def test_restart_adopts_cabinet_without_inventory_return(self):
        self.lua.execute("coords[100]=vector3(5,6,0);Entity(100).state:set('metaComicTowId','old',true)")
        self.lua.execute("json.decode=function() return {{serial='VM-TEST',objectNet=100,towId='old',products=metadata.products,cash=42,coords={x=5,y=6,z=0}}} end;threads={}")
        self.lua.execute((ROOT/'fivem/server/modules/vending_carry.lua').read_text(encoding='utf-8'))
        self.lua.execute('assert(coroutine.resume(threads[3]));assert(coroutine.resume(threads[3]))')
        self.assertEqual(self.lua.eval('adds'), 0)
        self.assertTrue(self.lua.eval('DoesEntityExist(100)'))
        self.assertEqual(self.lua.eval("countEvent('meta_comic:client:vendingRopeSnapped')"), 1)
        self.lua.execute("coords[1]=vector3(5,6,0);handlers['meta_comic:server:vendingUntow'](100)")
        self.assertEqual(self.lua.eval('adds'), 1)  # deliberate pickup still returns an item

    def test_client_and_config_compile(self):
        for name in ['fivem/client/vending_carry.lua', 'fivem/config.lua']:
            result = self.lua.eval('load')((ROOT / name).read_text(encoding='utf-8'))
            self.assertFalse(isinstance(result, tuple), str(result))

    def test_grounding_waits_for_both_model_and_world_collision(self):
        self.lua.execute('''
          frozen=false;gravity=true;modelReady=false;worldReady=true;foundGround=true;ground=12
          function SetEntityHasGravity(_,value) gravity=value end
          function FreezeEntityPosition(_,value) frozen=value end
          function SetEntityCollision() end
          function SetEntityLoadCollisionFlag() end
          function GetEntityModel() return 123 end
          function RequestCollisionForModel() end
          function RequestCollisionAtCoord() end
          function RequestModel() modelRequested=true end
          function HasModelLoaded() return modelReady end
          function SetModelAsNoLongerNeeded() end
          function HasCollisionLoadedAroundEntity() return worldReady end
          function GetGroundZFor_3dCoord() return foundGround,ground end
          function GetModelDimensions() return vector3(-1,-1,-0.95),vector3(1,1,1) end
          function SetEntityRotation() end
          function SetEntityCoordsNoOffset(id,x,y,z) coords[id]=vector3(x,y,z) end
          function PlaceObjectOnGroundProperly() return placementOK~=false end
          function SetEntityVelocity() velocityReset=true end
          coords[100]=vector3(0,0,1);Entity(100).state:set('metaComicTowNeedsGround',true,true)
        ''')
        client = (ROOT / 'fivem/client/vending_carry.lua').read_text(encoding='utf-8')
        section = client.split('local function groundMachine', 1)[1].split('local function makeRope', 1)[0]
        self.lua.execute('local function groundMachine' + section + '\nGround=groundMachine')
        self.assertFalse(self.lua.eval('Ground(100)'))
        self.assertTrue(self.lua.eval('frozen and not gravity and states[100].metaComicTowNeedsGround'))
        self.lua.execute('modelReady=true;worldReady=false')
        self.assertFalse(self.lua.eval('Ground(100)'))
        self.lua.execute('worldReady=true;foundGround=false')
        self.assertFalse(self.lua.eval('Ground(100)'))
        self.lua.execute('foundGround=true;placementOK=false')
        self.assertTrue(self.lua.eval('Ground(100)'))
        self.assertTrue(self.lua.eval('modelRequested and not states[100].metaComicTowNeedsGround'))
        self.lua.execute('placementOK=true')
        self.assertTrue(self.lua.eval('Ground(100)'))
        self.assertAlmostEqual(self.lua.eval('coords[100].z'), 13.10)
        self.assertTrue(self.lua.eval('velocityReset and not states[100].metaComicTowNeedsGround'))

    def test_only_network_owner_attaches_physical_rope(self):
        self.lua.execute('''
          stopping=false;ropes={[100]={}};tow={Length=6};owned=false
          function entityOf(id) return id end
          function rearOf() return vector3(0,0,1) end
          function SetEntityCollision() end
          function SetEntityLoadCollisionFlag() end
          function NetworkHasControlOfEntity(id)
            if id==200 and carOwned~=nil then return carOwned end
            return owned
          end
          function NetworkRequestControlOfEntity(id) requestedControl=id end
          function RopeLoadTextures() end
          function RopeAreTexturesLoaded() return true end
          function GetOffsetFromEntityInWorldCoords() return vector3(0,-5,1) end
          function AddRope() return 9 end
          function DoesRopeExist() return ropeFailed~=true end
          function AttachEntitiesToRope(...) physical=(physical or 0)+1;ropeArgs=table.pack(...) end
          function applyTowPhysics() physics=(physics or 0)+1 end
          function TriggerServerEvent() readySent=true end
          function PinRopeVertex() pins=(pins or 0)+1 end
          function GetRopeVertexCount() return 32 end
          coords[100]=vector3(0,-5,1);Entity(100).state:set('metaComicTowNeedsGround',false,true)
        ''')
        client = (ROOT / 'fivem/client/vending_carry.lua').read_text(encoding='utf-8')
        section = client.split('local function makeRope', 1)[1].split("RegisterNetEvent('meta_comic:client:vendingTow'", 1)[0]
        self.lua.execute('local function makeRope' + section + '\nMake=makeRope')
        self.assertTrue(self.lua.eval('Make(100,200)'))
        self.assertIsNone(self.lua.eval('physical'))
        self.assertIsNone(self.lua.eval('physics'))
        self.assertEqual(self.lua.eval('pins'), 2)
        self.lua.execute('carOwned=true;ropes[100]={}')
        self.assertTrue(self.lua.eval('Make(100,200)'))
        self.assertEqual(self.lua.eval('requestedControl'), 100)
        self.assertIsNone(self.lua.eval('physical'))
        self.lua.execute('owned=true;ropes[100]={}')
        self.assertTrue(self.lua.eval('Make(100,200)'))
        self.assertEqual(self.lua.eval('physical'), 1)
        self.assertEqual(self.lua.eval('physics'), 1)
        self.assertTrue(self.lua.eval('readySent'))
        self.assertEqual(self.lua.eval('ropeArgs[2]'), 200)
        self.assertEqual(self.lua.eval('ropeArgs[3]'), 100)
        self.assertTrue(self.lua.eval('ropeArgs[13]==nil and ropeArgs[14]==nil'))
        self.lua.execute('carOwned=false;ropes[100]={}')
        self.assertTrue(self.lua.eval('Make(100,200)'))
        self.assertEqual(self.lua.eval('physical'), 1)
        self.lua.execute('ropeFailed=true;ropes[100]={}')
        self.assertFalse(self.lua.eval('Make(100,200)'))
        self.assertEqual(self.lua.eval('physics'), 1)

    def test_failed_initialization_returns_same_machine_once(self):
        self.lua.execute("handlers['meta_comic:server:vendingTow'](200);initializationTimeout();initializationTimeout()")
        self.assertEqual(self.lua.eval('removes'), 1)
        self.assertEqual(self.lua.eval('adds'), 1)

    def test_ready_owner_cancels_rollback_but_other_player_cannot(self):
        self.lua.execute("handlers['meta_comic:server:vendingTow'](200);source=2;handlers['meta_comic:server:vendingTowReady'](100);initializationTimeout()")
        self.assertEqual(self.lua.eval('adds'), 1)
        self.setUp()
        self.lua.execute("handlers['meta_comic:server:vendingTow'](200);handlers['meta_comic:server:vendingTowReady'](100);initializationTimeout()")
        self.assertEqual(self.lua.eval('adds'), 0)
        self.assertFalse(self.lua.eval('frozenEntities[100]'))


if __name__ == '__main__':
    unittest.main()
