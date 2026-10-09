"""Authoritative cargo inventory state and safe, non-colliding local visuals."""
from pathlib import Path
import sys
import unittest
if len(sys.argv)>1: sys.path.insert(0,sys.argv.pop(1))
from lupa.lua54 import LuaRuntime
ROOT=Path(__file__).resolve().parents[1]

class CargoTests(unittest.TestCase):
    def setUp(self):
        self.lua=LuaRuntime(unpack_returned_tuples=True)
        self.lua.execute('''
            function vec3(x,y,z) return {x=x,y=y,z=z} end
            function joaat(v) return ({speedo4=4,rumpo=5,rumpo2=6,rumpo3=7,trflat=9,metacomics_vending_machine=20,speedo=11,speedo2=12,pony=13,pony2=14,burrito=15,burrito2=16,burrito3=17,burrito4=18,burrito5=19,mule=21,mule2=22,mule3=23,mule4=24,mule5=25,benson=26})[v] end
            Config={VendingMachines={},VendingCarry={TrunkCargo={Profiles={
                speedo4={Doors={2,3},Slots={{offset=vec3(0,-1,0),rotation=vec3(90,0,180)}},CrateSlots={{offset=vec3(0,-1,-0.5),rotation=vec3(0,0,0),alignBottom=true}}},
                trflat={Doors={},Slots={{offset=vec3(0,0,1),rotation=vec3(0,0,0)}}}}}}}
            Config.ShippingCrates={Models={Closed='crate'},Carry={}}
            MetaComic={Framework={notify=function(_,text) notice=text end}}
            inventories={trunkA={id='trunkA',type='trunk',entityId=50,netid=5,items={}}}
            entities={[50]={type=2,model=4,bucket=0,state={}},[51]={type=2,model=9,bucket=0,state={}}}
            status={[2]=7,[3]=7};spawned=0;nextObject=100;deleted=0;handlers={};timers={};registered={};threads={}
            function GetCurrentResourceName() return 'cards' end
            function GetGameTimer() return 0 end
            function GetEntityType(id) return entities[id] and entities[id].type end
            function GetEntityModel(id) return entities[id].model end
            function DoesEntityExist(id) return entities[id]~=nil end
            function NetworkGetEntityFromNetworkId(id) return id==5 and (stale and 51 or 50) or id==6 and 51 or 0 end
            function NetworkGetNetworkIdFromEntity(id) return id+1000 end
            function GetEntityCoords() return vec3(0,0,0) end
            function GetEntityRoutingBucket(id) return entities[id].bucket end
            function SetEntityRoutingBucket(id,bucket) entities[id].bucket=bucket end
            function GetVehicleDoorStatus(_,door) return status[door] or 0 end
            function CreateObjectNoOffset(model)
                spawned=spawned+1;nextObject=nextObject+1;entities[nextObject]={type=3,model=model,bucket=0};return nextObject
            end
            function FreezeEntityPosition() end;function SetEntityOrphanMode() end
            function DeleteEntity(id) entities[id]=nil;deleted=deleted+1 end
            function Entity(id)
                local state=entities[id].state or {};entities[id].state=state
                state.set=function(_,key,value) state[key]=value end
                return {state=state}
            end
            function RegisterNetEvent(name,fn) handlers[name]=fn end
            function AddEventHandler(name,fn) handlers[name]=fn end
            function CreateThread(fn) threads[#threads+1]=fn end
            function SetTimeout(_,fn) timers[#timers+1]=fn end
            function Wait() end
            exports=setmetatable({ox_inventory={GetInventory=function(_,id) return inventories[id] end}},
                {__call=function(_,name,fn) registered[name]=fn end})
            payload={source=1,action='move',fromInventory=1,fromSlot={name='vending_machine',count=1},fromType='player',toInventory='trunkA',toType='trunk',count=1}
        ''')
        self.lua.execute((ROOT/'fivem/server/modules/vending_trunk_cargo.lua').read_text())
        self.lua.execute('Cargo=MetaComic.VendingTrunkCargo')

    def test_server_door_gate_and_capacity(self):
        self.assertTrue(self.lua.eval('Cargo.check(payload)'))
        self.lua.execute('status[3]=0')
        self.assertFalse(self.lua.eval('(Cargo.check(payload))'))
        self.lua.execute("status[3]=7;inventories.trunkA.items={{name='vending_machine',count=1}}")
        self.assertFalse(self.lua.eval('(Cargo.check(payload))'))

    def test_trailer_without_doors_and_unknown_profile(self):
        self.lua.execute("inventories.trunkA.entityId=51;inventories.trunkA.netid=6;status={}")
        self.assertTrue(self.lua.eval('Cargo.check(payload)'))
        self.lua.execute('entities[51].model=999')
        self.assertFalse(self.lua.eval('(Cargo.check(payload))'))

    def test_reverse_swap_and_same_trunk_reorder(self):
        self.lua.execute("status={};payload={source=1,action='swap',fromInventory='trunkA',fromType='trunk',fromSlot={name='water'},toInventory=1,toType='player',toSlot={name='vending_machine',count=1}}")
        self.assertFalse(self.lua.eval('(Cargo.check(payload))'))
        self.lua.execute("payload.toInventory='trunkA';payload.toType='trunk'")
        self.assertTrue(self.lua.eval('Cargo.check(payload)'))

    def test_failed_move_publishes_nothing_and_success_publishes_placement_only(self):
        self.lua.execute('Cargo.changed(payload);timers[1]()')
        self.assertEqual(self.lua.eval('spawned'),0)
        self.lua.execute("Cargo.changed(payload);inventories.trunkA.items={{name='vending_machine',count=1}};timers[2]();Cargo.refresh('trunkA')")
        self.assertEqual(self.lua.eval('spawned'),0)
        self.assertEqual(self.lua.eval('#inventories.trunkA.items'),1)
        self.assertEqual(self.lua.eval('#entities[50].state.metaComicTrunkCargo.slots'),1)

    def test_removal_clears_replicated_state_without_physical_entities(self):
        self.lua.execute("inventories.trunkA.items={{name='vending_machine',count=1}};Cargo.refresh('trunkA');Cargo.refresh('trunkA')")
        self.assertEqual(self.lua.eval('spawned'),0)
        self.lua.execute("inventories.trunkA.items={};Cargo.refresh('trunkA')")
        self.assertIsNone(self.lua.eval('entities[50].state.metaComicTrunkCargo'))
        self.assertEqual(self.lua.eval('deleted'),0)

    def test_stale_vehicle_and_shutdown_preserve_inventory(self):
        self.lua.execute('stale=true')
        self.assertFalse(self.lua.eval('(Cargo.check(payload))'))
        self.lua.execute("stale=false;inventories.trunkA.items={{name='vending_machine',count=1}};Cargo.refresh('trunkA');handlers.onResourceStop('cards')")
        self.assertEqual(self.lua.eval('#inventories.trunkA.items'),1)
        self.assertIsNone(self.lua.eval('entities[101]'))

    def test_routing_bucket_uses_vehicle_state_without_separate_entities(self):
        self.lua.execute("inventories.trunkA.items={{name='vending_machine',count=1}};Cargo.refresh('trunkA');entities[50].bucket=12;Cargo.refresh('trunkA')")
        self.assertEqual(self.lua.eval('entities[50].bucket'),12)
        self.assertEqual(self.lua.eval('spawned'),0)
        self.assertEqual(self.lua.eval('entities[50].state.metaComicTrunkCargo.model'),'metacomics_vending_machine')

    def test_reconcile_does_not_republish_unchanged_state(self):
        self.lua.execute("writes=0;local original=Entity;function Entity(id) local entity=original(id);entity.state.set=function(_,key,value) writes=writes+1;entity.state[key]=value end;return entity end;inventories.trunkA.items={{name='vending_machine',count=1}};Cargo.refresh('trunkA');Cargo.refresh('trunkA')")
        self.assertEqual(self.lua.eval('writes'),1)

    def test_crate_capacity_mixed_load_rejection_and_type_swap(self):
        self.lua.execute("payload.fromSlot={name='shipping_crate',count=1}")
        self.assertTrue(self.lua.eval('Cargo.check(payload)'))
        self.lua.execute("inventories.trunkA.items={{name='vending_machine',count=1}}")
        self.assertFalse(self.lua.eval('(Cargo.check(payload))'))
        self.lua.execute("payload.action='swap';payload.toSlot={name='vending_machine',count=1}")
        self.assertTrue(self.lua.eval('Cargo.check(payload)'))
        self.lua.execute("inventories.trunkA.items={{name='shipping_crate',count=1}};payload.action='move';payload.toSlot=nil")
        self.assertFalse(self.lua.eval('(Cargo.check(payload))'))

    def test_crate_visual_model_and_floor_alignment_come_from_server_inventory(self):
        self.lua.execute("inventories.trunkA.items={{name='shipping_crate',count=1,metadata={crate='cards',instanceId='original'}}};Cargo.refresh('trunkA')")
        self.assertEqual(self.lua.eval('entities[50].state.metaComicTrunkCargo.model'),'crate')
        self.assertTrue(self.lua.eval('entities[50].state.metaComicTrunkCargo.slots[1].alignBottom'))
        self.assertEqual(self.lua.eval('inventories.trunkA.items[1].metadata.instanceId'),'original')
        self.assertEqual(self.lua.eval('spawned'),0)
        self.lua.execute("inventories.trunkA.items={};Cargo.refresh('trunkA')")
        self.assertIsNone(self.lua.eval('entities[50].state.metaComicTrunkCargo'))

    def test_crate_reverse_swap_unknown_profile_and_disable(self):
        self.lua.execute("payload={action='swap',fromInventory='trunkA',fromType='trunk',fromSlot={name='water'},toInventory=1,toType='player',toSlot={name='shipping_crate',count=1}};status={}")
        self.assertFalse(self.lua.eval('(Cargo.check(payload))'))
        self.lua.execute('status={[2]=7,[3]=7}')
        self.assertTrue(self.lua.eval('Cargo.check(payload)'))
        self.lua.execute('entities[50].model=999')
        self.assertFalse(self.lua.eval('(Cargo.check(payload))'))

    def test_all_default_vans_allow_closed_doors_and_side_rotation(self):
        for model in (4,5,6,7,11,12,13,14,15,16,17,18,19):
            with self.subTest(model=model):
                self.setUp()
                self.lua.execute('originalConfig=Config;vector3=vec3;function vec4(x,y,z,w) return {x=x,y=y,z=z,w=w} end')
                self.lua.execute((ROOT/'fivem/config.lua').read_text(encoding='utf-8'))
                self.lua.execute("profiles=Config.VendingCarry.TrunkCargo.Profiles;Config=originalConfig;Config.VendingCarry.TrunkCargo.Profiles={};for _,name in ipairs({'speedo4','rumpo','rumpo2','rumpo3','speedo','speedo2','pony','pony2','burrito','burrito2','burrito3','burrito4','burrito5'}) do Config.VendingCarry.TrunkCargo.Profiles[name]=profiles[name] end")
                self.lua.execute((ROOT/'fivem/server/modules/vending_trunk_cargo.lua').read_text())
                self.lua.execute(f'Cargo=MetaComic.VendingTrunkCargo;status={{}};entities[50].model={model}')
                self.assertTrue(self.lua.eval('Cargo.check(payload)'))
                self.lua.execute("inventories.trunkA.items={{name='vending_machine',count=1}};Cargo.refresh('trunkA')")
                self.assertEqual(self.lua.eval('#entities[50].state.metaComicTrunkCargo.doors'),0)
                self.assertEqual(self.lua.eval('entities[50].state.metaComicTrunkCargo.slots[1].rotation.x'),0)
                self.assertEqual(self.lua.eval('entities[50].state.metaComicTrunkCargo.slots[1].rotation.y'),90)
                self.assertEqual(self.lua.eval('entities[50].state.metaComicTrunkCargo.slots[1].rotation.z'),90)

    def test_truck_profiles_upright_grid_allowlist_and_capacity(self):
        for name, model, capacity in [('mule',21,6),('mule2',22,6),('mule3',23,6),('mule4',24,6),('mule5',25,6),('benson',26,9)]:
            with self.subTest(model=name):
                self.setUp()
                self.lua.execute('originalConfig=Config;vector3=vec3;function vec4(x,y,z,w) return {x=x,y=y,z=z,w=w} end')
                self.lua.execute((ROOT/'fivem/config.lua').read_text(encoding='utf-8'))
                self.assertTrue(self.lua.eval(f"(function() for _,name in ipairs(Config.VendingCarry.TrunkRestrictions.AllowedModels) do if name=='{name}' then return true end end return false end)()"))
                self.lua.execute("profiles=Config.VendingCarry.TrunkCargo.Profiles;Config=originalConfig;Config.VendingCarry.TrunkCargo.Profiles={};for _,name in ipairs({'mule','mule2','mule3','mule4','mule5','benson'}) do Config.VendingCarry.TrunkCargo.Profiles[name]=profiles[name] end")
                self.lua.execute((ROOT/'fivem/server/modules/vending_trunk_cargo.lua').read_text())
                self.lua.execute(f'Cargo=MetaComic.VendingTrunkCargo;entities[50].model={model};status={{}};payload.count={capacity}')
                self.assertTrue(self.lua.eval('Cargo.check(payload)'))
                self.lua.execute(f'payload.count={capacity+1}')
                self.assertFalse(self.lua.eval('(Cargo.check(payload))'))
                self.lua.execute(f"inventories.trunkA.items={{{{name='vending_machine',count={capacity}}}}};Cargo.refresh('trunkA');slots=entities[50].state.metaComicTrunkCargo.slots")
                self.assertEqual(self.lua.eval('#slots'),capacity)
                self.assertEqual(self.lua.eval('spawned'),0)
                self.assertTrue(self.lua.eval('''(function()
                    for i,a in ipairs(slots) do
                        if a.rotation.x~=0 or a.rotation.y~=0 or a.rotation.z~=(i==9 and 0 or 90) then return false end
                        for j,b in ipairs(slots) do
                            -- Sideways footprint: 0.8791 m across, 1.165 m deep.
                            local ax,ay=a.rotation.z==90 and 0.8791 or 1.165,a.rotation.z==90 and 1.165 or 0.8791
                            local bx,by=b.rotation.z==90 and 0.8791 or 1.165,b.rotation.z==90 and 1.165 or 0.8791
                            if i~=j and math.abs(a.offset.x-b.offset.x)<(ax+bx)/2 and math.abs(a.offset.y-b.offset.y)<(ay+by)/2 then return false end
                        end
                    end
                    return true
                end)()'''))
                self.lua.execute("inventories.trunkA.items={{name='vending_machine',count=1}};Cargo.refresh('trunkA')")
                self.assertEqual(self.lua.eval('#entities[50].state.metaComicTrunkCargo.slots'),1)

class CargoClientTests(unittest.TestCase):
    def setUp(self):
        self.lua=LuaRuntime(unpack_returned_tuples=True)
        self.lua.execute('''
            Config={VendingCarry={TrunkCargo={Profiles={speedo4={}}}}};timer=0;owner=false;objectOwner=false;attached=false
            opens=0;attaches=0;requests=0;releases=0;controls=0;handlers={};registered={}
            objects={};spawned=0;deleted=0;loaded=true;visible=false;collision=true;frozen=false;operations={};inAttach=false
            cargo={doors={2,3},slots={{net=101,offset={x=0,y=-1,z=0},rotation={x=90,y=0,z=180}}}}
            function joaat() return 4 end
            function GetGameTimer() return timer end
            function PlayerPedId() return 10 end
            function GetGamePool() return {50} end
            function DoesEntityExist(id) return id==50 and not unloaded or objects[id]~=nil end
            function GetEntityModel() return 4 end
            function GetEntityBoneIndexByName() return -1 end
            function GetEntityCoords() return setmetatable({x=0,y=0,z=0}, {__sub=function() return setmetatable({}, {__len=function() return 0 end}) end}) end
            function Entity() return {state={metaComicTrunkCargo=cargo}} end
            function NetworkHasControlOfEntity(id) return id==50 and owner or id==101 and objectOwner end
            function NetworkRequestControlOfEntity() requests=requests+1 end
            function NetworkDoesEntityExistWithNetworkId() return true end
            function NetToObj(id) return id end
            function SetVehicleDoorOpen() opens=opens+1 end
            angle=1
            function GetVehicleDoorAngleRatio() return angle end
            function SetVehicleDoorControl(_,_,_,target) if target==0 then releases=releases+1 end;controls=controls+1;angle=target end
            function IsModelInCdimage() return true end;function IsModelValid() return true end
            function RequestModel() requests=requests+1 end;function HasModelLoaded() return loaded end
            function SetModelAsNoLongerNeeded() end
            function CreateObjectNoOffset(_,x,y,z,networked,mission,dynamic)
                assert(not networked and not mission and not dynamic);assert(z==-10)
                spawned=spawned+1;objects[100+spawned]=true;attached=false;collision=true;visible=true
                operations[#operations+1]='create';return 100+spawned
            end
            function DeleteEntity(id) objects[id]=nil;deleted=deleted+1 end
            function SetEntityVisible(_,value) visible=value;operations[#operations+1]=value and 'show' or 'hide' end
            function SetEntityCollision(_,value) collision=value;operations[#operations+1]='collision' end
            function FreezeEntityPosition(_,value) frozen=value;operations[#operations+1]=value and 'freeze' or 'unfreeze' end
            function SetEntityInvincible() end
            function IsEntityAttachedToEntity() return attached end
            function AttachEntityToEntity() assert(not collision and not visible and frozen);attaches=attaches+1;attached=not failAttach;operations[#operations+1]='attach' end
            function VehToNet() return 5 end
            function TriggerServerEvent() end
            function GetCurrentResourceName() return 'cards' end
            function CreateThread(fn) loop=coroutine.create(fn) end
            function Wait(ms) timer=timer+ms;coroutine.yield() end
            function AddEventHandler(name,fn) handlers[name]=fn end
            exports=function(name,fn) registered[name]=fn end
            function tick() local ok,err=coroutine.resume(loop);assert(ok,err) end
        ''')
        self.lua.execute('MetaComic={}')
        self.lua.execute((ROOT/'fivem/shared/vending_cargo_geometry.lua').read_text())
        self.lua.execute((ROOT/'fivem/client/vending_trunk_cargo.lua').read_text())

    def test_local_attachment_does_not_need_ownership_but_doors_do(self):
        self.lua.execute('tick()')
        self.assertEqual(self.lua.eval('opens'),0)
        self.assertEqual(self.lua.eval('attaches'),1)
        self.lua.execute('owner=true;tick()')
        self.assertEqual(self.lua.eval('requests'),1)
        self.assertEqual(self.lua.eval('attaches'),1)
        self.lua.execute('objectOwner=true;tick();tick()')
        self.assertEqual(self.lua.eval('attaches'),1)
        self.assertEqual(self.lua.eval('opens'),0)
        self.assertEqual(self.lua.eval('controls'),0)
        self.assertFalse(self.lua.eval("registered.CanCloseVendingCargoDoor(50,2)"))
        self.assertTrue(self.lua.eval("registered.CanCloseVendingCargoDoor(50,0)"))

    def test_cargo_removal_does_not_move_doors(self):
        self.lua.execute('owner=true;objectOwner=true;tick();cargo=nil;tick()')
        self.assertEqual(self.lua.eval('controls'),0)
        self.assertTrue(self.lua.eval('registered.CanCloseVendingCargoDoor(50,2)'))
        self.assertEqual(self.lua.eval('deleted'),1)

    def test_spawn_lifecycle_is_collision_free_before_attach_and_show(self):
        self.lua.execute('tick()')
        self.assertEqual(self.lua.eval("table.concat(operations,',')"),
                         'create,hide,freeze,collision,hide,freeze,collision,attach,unfreeze,show')
        self.assertFalse(self.lua.eval('collision'))
        self.assertTrue(self.lua.eval('visible'))
        self.lua.execute('owner=true;tick();owner=false;tick()')
        self.assertEqual(self.lua.eval('spawned'),1)
        self.assertEqual(self.lua.eval('attaches'),1)
        self.assertFalse(self.lua.eval('collision'))

    def test_failed_attachment_stays_hidden_frozen_and_non_colliding(self):
        self.lua.execute('failAttach=true;tick();tick()')
        self.assertFalse(self.lua.eval('visible'))
        self.assertFalse(self.lua.eval('collision'))
        self.assertTrue(self.lua.eval('frozen'))
        self.assertEqual(self.lua.eval('spawned'),1)
        self.lua.execute('failAttach=false;tick()')
        self.assertTrue(self.lua.eval('visible'))
        self.assertFalse(self.lua.eval('collision'))

    def test_model_load_can_be_cancelled_without_spawning(self):
        self.lua.execute('loaded=false;tick();cargo=nil;loaded=true;tick()')
        self.assertEqual(self.lua.eval('spawned'),0)

    def test_streaming_cleanup_missing_object_recovery_and_stop(self):
        self.lua.execute('tick();objects[101]=nil;timer=500;tick()')
        self.assertEqual(self.lua.eval('spawned'),2)
        self.lua.execute('unloaded=true;tick()')
        self.assertEqual(self.lua.eval('deleted'),1)
        self.lua.execute('unloaded=false;tick()')
        self.assertEqual(self.lua.eval('spawned'),3)
        self.lua.execute("handlers.onResourceStop('cards')")
        self.assertEqual(self.lua.eval('deleted'),2)

    def test_changed_placement_replaces_visual(self):
        self.lua.execute('tick();cargo.slots[1].rotation.y=90;timer=500;tick()')
        self.assertEqual(self.lua.eval('spawned'),2)
        self.assertEqual(self.lua.eval('deleted'),1)

    def test_steady_attached_visual_does_not_repeat_native_mutations(self):
        self.lua.execute('tick();operationCount=#operations;tick();tick();tick()')
        self.assertEqual(self.lua.eval('#operations'),self.lua.eval('operationCount'))

    def test_large_cargo_creation_is_staggered(self):
        self.lua.execute('cargo.slots={};for i=1,9 do cargo.slots[i]={offset={x=i,y=-1,z=0},rotation={x=0,y=0,z=0}} end;tick()')
        self.assertEqual(self.lua.eval('spawned'),2)
        self.lua.execute('timer=500;tick()')
        self.assertEqual(self.lua.eval('spawned'),4)
        self.lua.execute('timer=1000;tick();timer=1500;tick();timer=2000;tick()')
        self.assertEqual(self.lua.eval('spawned'),9)

    def test_crate_model_origin_aligns_to_cargo_floor(self):
        self.lua.execute('''
            cargo.slots[1].alignBottom=true;cargo.slots[1].rotation={x=0,y=0,z=0};cargo.slots[1].offset.z=0.1
            function GetModelDimensions() return {x=-0.5,y=-0.5,z=-0.4},{x=0.5,y=0.5,z=0.4} end
            function AttachEntityToEntity(_,_,_,x,y,z) assert(not collision);attachedZ=z;attaches=attaches+1;attached=true end
            tick()
        ''')
        self.assertAlmostEqual(self.lua.eval('attachedZ'),0.5)

    def test_crate_lid_attaches_to_base_and_cleans_up_with_cargo(self):
        self.lua.execute('''
            cargo.lid='lid';attachLog={}
            function GetModelDimensions() return {x=-0.5,y=-0.5,z=-0.4},{x=0.5,y=0.5,z=0.4} end
            function AttachEntityToEntity(object,parent,_,x,y,z)
                assert(not collision and not visible and frozen);attached=true;attaches=attaches+1
                attachLog[#attachLog+1]={object=object,parent=parent,z=z}
            end
            tick()
        ''')
        self.assertEqual(self.lua.eval('spawned'),2)
        self.assertEqual(self.lua.eval('attachLog[2].parent'),101)
        self.assertAlmostEqual(self.lua.eval('attachLog[2].z'),0.8)
        self.lua.execute('cargo=nil;tick()')
        self.assertEqual(self.lua.eval('deleted'),2)

    def test_obstructed_door_only_corrects_at_minimum_angle(self):
        self.lua.execute('owner=true;angle=0.8;tick();tick()')
        self.assertEqual(self.lua.eval('controls'),0)
        self.lua.execute('angle=0.1;tick();tick();tick()')
        self.assertEqual(self.lua.eval('controls'),1)
        self.assertEqual(self.lua.eval('angle'),0.25)
        self.assertEqual(self.lua.eval('opens'),0)
        self.lua.execute('angle=0.9;tick()')
        self.assertEqual(self.lua.eval('controls'),1)

    def test_unobstructed_vehicle_allows_closed_doors(self):
        self.lua.execute('owner=true;cargo.doors={};angle=0;tick();tick()')
        self.assertEqual(self.lua.eval('controls'),0)
        self.assertTrue(self.lua.eval('registered.CanCloseVendingCargoDoor(50,2)'))

    def test_geometry_clears_fitting_cargo_and_stops_protruding_cargo(self):
        self.lua.execute('''
            owner=true;objectOwner=true;attached=true;angle=0;cargoY=-1
            cargo.collisionDoors={2,3}
            function GetEntityModel(id) return id>=101 and 20 or 4 end
            function GetEntityBoneIndexByName(_,name) return name=='door_dside_r' and 10 or 11 end
            function GetWorldPositionOfEntityBone(_,bone) return {x=bone==10 and -0.9 or 0.9,y=-2,z=0} end
            function GetOffsetFromEntityGivenWorldCoords(_,x,y,z) return {x=x,y=y,z=z} end
            function GetOffsetFromEntityInWorldCoords(_,x,y,z) return {x=x,y=y+cargoY,z=z} end
            function GetModelDimensions(model)
                if model==20 then return {x=-0.5,y=-0.5,z=-0.5},{x=0.5,y=0.5,z=0.5} end
                return {x=-1,y=-3,z=-1},{x=1,y=3,z=1.4}
            end
            geometryCalls=0;local originalLimit=MetaComic.VendingCargoGeometry.limit
            MetaComic.VendingCargoGeometry.limit=function(...) geometryCalls=geometryCalls+1;return originalLimit(...) end
            tick()
        ''')
        self.assertEqual(self.lua.eval('controls'),0)
        self.assertTrue(self.lua.eval('registered.CanCloseVendingCargoDoor(50,2)'))
        self.assertEqual(self.lua.eval('geometryCalls'),2)
        self.lua.execute('timer=2000;tick()')
        self.assertEqual(self.lua.eval('geometryCalls'),2)
        self.lua.execute('cargoY=-2;cargo.slots[1].offset.y=-2;timer=2500;tick()')
        self.assertEqual(self.lua.eval('geometryCalls'),4)
        self.assertGreater(self.lua.eval('controls'),0)
        self.assertFalse(self.lua.eval('registered.CanCloseVendingCargoDoor(50,2)'))
        self.assertEqual(self.lua.eval('opens'),0)

    def test_sliding_door_does_not_use_rear_swing_or_hold_fitting_load_open(self):
        self.lua.execute('''
            owner=true;angle=0;cargoX=0;cargo.collisionClearance=-0.015
            cargo.collisionDoors={2,3};cargo.slidingDoors={
                [2]={center={x=-1.1,y=-0.75,z=0},halfSize={x=0.025,y=0.7,z=0.8},travel={x=-0.12,y=-1.1,z=0}},
                [3]={center={x=1.1,y=-0.75,z=0},halfSize={x=0.025,y=0.7,z=0.8},travel={x=0.12,y=-1.1,z=0}}}
            function GetModelDimensions() return {x=-1.08,y=-0.5,z=-0.5},{x=1.08,y=0.5,z=0.5} end
            function GetOffsetFromEntityGivenWorldCoords(_,x,y,z) return {x=x,y=y,z=z} end
            function GetOffsetFromEntityInWorldCoords(_,x,y,z) return {x=x+cargoX,y=y-0.75,z=z} end
            tick()
        ''')
        self.assertEqual(self.lua.eval('controls'),0)
        self.assertTrue(self.lua.eval('registered.CanCloseVendingCargoDoor(50,3)'))
        self.lua.execute('cargoX=0.1;cargo.slots[1].offset.x=0.1;timer=2000;tick()')
        self.assertGreater(self.lua.eval('controls'),0)
        self.assertFalse(self.lua.eval('registered.CanCloseVendingCargoDoor(50,3)'))

class GeometryTests(unittest.TestCase):
    def setUp(self):
        self.lua=LuaRuntime(unpack_returned_tuples=True)
        self.lua.execute('MetaComic={}')
        self.lua.execute((ROOT/'fivem/shared/vending_cargo_geometry.lua').read_text())
        self.lua.execute('G=MetaComic.VendingCargoGeometry')

    def test_rotated_boxes_do_not_use_world_axis_overlap_as_collision(self):
        self.lua.execute('''
            function box(shift)
                return G.bounds({x=-2,y=-0.1,z=-0.1},{x=2,y=0.1,z=0.1},function(x,y,z)
                    local c=math.sqrt(0.5);return {x=x*c-y*c-shift*c,y=x*c+y*c+shift*c,z=z}
                end)
            end
        ''')
        self.assertFalse(self.lua.eval('G.intersects(box(0),box(0.3),0)'))
        self.assertTrue(self.lua.eval('G.intersects(box(0),box(0.1),0)'))

    def test_door_sweep_detects_contact_between_open_and_closed(self):
        self.lua.execute('''
            hinge={x=-0.9,y=-2,z=0}
            b=G.bounds({x=-0.76,y=-2.46,z=-0.1},{x=-0.64,y=-2.34,z=0.1},function(x,y,z) return {x=x,y=y,z=z} end)
            closed=G.door(hinge,1,0.9,-0.65,1.35,0,110)
        ''')
        self.assertFalse(self.lua.eval('G.intersects(closed,b,0)'))
        self.assertGreater(self.lua.eval('G.limit({b},hinge,1,0.9,-0.65,1.35,110)'),0)

if __name__=='__main__':unittest.main()
