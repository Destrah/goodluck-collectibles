"""Exercise the real batch visual lifecycle with streamed-model/native stubs."""
from pathlib import Path
import sys
import unittest
if len(sys.argv)>1: sys.path.insert(0,sys.argv.pop(1))
from lupa.lua54 import LuaRuntime
ROOT=Path(__file__).resolve().parents[1]

class VisualTests(unittest.TestCase):
    def setUp(self):
        self.lua=LuaRuntime(unpack_returned_tuples=True)
        self.lua.execute("""
            Config={Props={Pack={model='custom_pack'},Box={model='custom_box'}}};crime={BreakIn={Loot={Visuals={}}}}
            looting=true;lootGeneration=1;timer=0;threads={};objects={};models={};nextObject=0;attachments={};deleted=0
            function vec3(x,y,z) return {x=x,y=y,z=z} end
            function PlayerPedId() return 10 end
            function IsEntityDead() return dead==true end
            function GetGameTimer() return timer end
            function CreateThread(fn) threads[#threads+1]=coroutine.create(fn) end
            function Wait() coroutine.yield() end
            function loadModel(model) models[#models+1]=model;if loading then Wait() end;return model end
            function loadDict() return true end
            function GetEntityCoords() return vec3(0,0,0) end
            function TaskPlayAnim(_,dict,clip) lastClip=clip end
            function StopAnimTask() end
            function HasAnimDictLoaded() return true end
            function IsEntityPlayingAnim(_,_,clip) return lastClip==clip end
            function RegisterNetEvent() end
            MetaComic={}
            function SetModelAsNoLongerNeeded() end
            function CreateObject() nextObject=nextObject+1;objects[nextObject]=true;return nextObject end
            function DeleteEntity(id) objects[id]=nil;deleted=deleted+1 end
            function DoesEntityExist(id) return objects[id]==true end
            function SetEntityCollision() end
            function SetEntityAlpha() end
            function GetPedBoneIndex(_,bone) return bone end
            function AttachEntityToEntity(_,_,bone) attachments[#attachments+1]=bone end
            function step(t) timer=t;local ok,err=coroutine.resume(threads[#threads]);assert(ok,err) end
        """)
        script=(ROOT/'fivem/client/vending_crime.lua').read_text(encoding='utf-8')
        actual=script.split('local lootProp, lootAnim, visualToken',1)[1].split("RegisterNetEvent('meta_comic:client:lootInspect'",1)[0]
        self.lua.execute('local lootProp, lootAnim, visualToken'+actual+' Animate=animateLootBatch;Stop=stopLootVisual')

    def test_correct_props_and_reach_stash_cleanup(self):
        for kind,product,model in [('cash',None,'prop_anim_cash_note'),('stock','pack','custom_pack'),('stock','box','custom_box')]:
            product_lua='nil' if product is None else "'"+product+"'"
            self.lua.execute(f"timer=0;Animate({{kind='{kind}',productKind={product_lua},duration=4000}},4000,1);step(0);step(1000)")
            self.assertEqual(self.lua.eval('models[#models]'),model)
            self.assertEqual(self.lua.eval('lastClip'),'idle_a' if kind=='cash' else 'givetake1_a')
            self.lua.execute('step(2200)')
            self.assertEqual(self.lua.eval('lastClip'),'idle_a' if kind=='cash' else 'grab')
            self.lua.execute('step(3520)')
            self.assertEqual(self.lua.eval('attachments[#attachments]'),11816)
            self.lua.execute('step(4000)')
            self.assertTrue(self.lua.eval('next(objects)==nil'))

    def test_cancel_cleans_prop_and_canceled_loading_cannot_respawn(self):
        self.lua.execute("Animate({kind='cash',duration=4000},4000,1);step(1000);looting=false;Stop();step(2000)")
        self.assertTrue(self.lua.eval('next(objects)==nil'))
        self.lua.execute("looting=true;loading=true;timer=0;Animate({kind='cash',duration=4000},4000,1);step(0);looting=false;Stop();step(1000)")
        self.assertTrue(self.lua.eval('next(objects)==nil'))
        self.assertEqual(self.lua.eval('nextObject'),1)

    def test_superseded_streaming_batch_cannot_create_old_prop(self):
        self.lua.execute("loading=true;Animate({kind='cash',duration=4000},4000,1);step(0);old=threads[1];Stop();lootGeneration=2")
        self.lua.execute("local ok,err=coroutine.resume(old);assert(ok,err)")
        self.assertEqual(self.lua.eval('nextObject'),0)

    def test_disabled_visuals_start_no_thread(self):
        self.lua.execute("crime.BreakIn.Loot.Visuals.Enabled=false;Animate({kind='cash',duration=4000},4000,1)")
        self.assertEqual(self.lua.eval('#threads'),0)

class InterruptionTests(unittest.TestCase):
    def setUp(self):
        VisualTests.setUp(self)
        self.lua.execute('''
            Config.VendingMachines={Crime=crime};events={};resourceEvents={};serverEvents={};threads={}
            progressCancels=0;hardClears=0;secondaryClears=0
            function RegisterNetEvent(name,fn) events[name]=fn end
            function AddEventHandler(name,fn) resourceEvents[name]=fn end
            function TriggerServerEvent(name) serverEvents[#serverEvents+1]=name end
            function TriggerEvent() end
            function GetResourceState(name) return name=='ox_lib' and 'started' or 'missing' end
            function GetCurrentResourceName() return 'test' end
            function joaat(model) return model end
            function IsModelInCdimage() return true end
            function IsModelValid() return true end
            function RequestModel() end
            function HasModelLoaded() return true end
            function RequestAnimDict() end
            function HasAnimDictLoaded() return true end
            function ClearPedTasks() lastClip=nil end
            function ClearPedTasksImmediately() hardClears=hardClears+1;lastClip=nil end
            function ClearPedSecondaryTask() secondaryClears=secondaryClears+1 end
            function ClearEntityLastDamageEntity() end
            function HasEntityBeenDamagedByAnyPed() return damaged==true end
            function IsPedRagdoll() return ragdoll==true end
            function IsPedBeingStunned() return stunned==true end
            function DisableControlAction() end
            function IsControlJustPressed() return escape==true end
            function BeginTextCommandDisplayHelp() end
            function AddTextComponentSubstringPlayerName() end
            function EndTextCommandDisplayHelp() end
            exports={ox_lib={
                progressActive=function() return progressRunning==true end,
                cancelProgress=function() progressCancels=progressCancels+1;progressRunning=false end,
                progressBar=function() progressRunning=true;coroutine.yield();progressRunning=false;return progressResult==true end,
            }}
            function resume(co) local ok,err=coroutine.resume(co);assert(ok,err) end
        ''')
        self.lua.execute((ROOT/'fivem/client/vending_crime.lua').read_text(encoding='utf-8'))

    # Run the actual event handlers, rather than the isolated visual helper tested above.
    def start_loot(self):
        self.lua.execute("events['meta_comic:client:lootStarted']({id=1});monitor=threads[2];batch=coroutine.create(function() events['meta_comic:client:lootBatch']({kind='stock',duration=4000}) end);resume(batch);visual=threads[3];timer=1000;resume(visual)")

    def test_shove_cancels_progress_pose_props_and_delayed_batch(self):
        self.start_loot()
        self.assertEqual(self.lua.eval('nextObject'),1)
        self.lua.execute('ragdoll=true;resume(monitor)')
        self.assertEqual(self.lua.eval('progressCancels'),1)
        self.assertGreater(self.lua.eval('hardClears'),0)
        self.assertGreater(self.lua.eval('secondaryClears'),0)
        self.assertIsNone(self.lua.eval('lastClip'))
        self.assertTrue(self.lua.eval('next(objects)==nil'))
        self.lua.execute('progressResult=true;resume(batch);resume(visual)')
        self.assertEqual(self.lua.eval('nextObject'),1)
        self.assertEqual(self.lua.eval('serverEvents[#serverEvents]'),'meta_comic:server:lootCancel')

    def test_server_stop_and_escape_cleanup(self):
        for server_stop in (True,False):
            self.setUp();self.start_loot()
            if server_stop:
                self.lua.execute("events['meta_comic:client:lootStopped']('Interrupted')")
            else:
                self.lua.execute('escape=true;timer=0;resume(monitor)')
            self.assertTrue(self.lua.eval('next(objects)==nil'))
            self.assertEqual(self.lua.eval('progressCancels'),1)
            self.assertIsNone(self.lua.eval('lastClip'))

    def test_interrupted_service_work_cannot_finish_after_progress_resumes(self):
        self.lua.execute("work=coroutine.create(function() events['meta_comic:client:vendingWork']({id=1,kind='cash',duration=4000,token='work'}) end);resume(work);damaged=true;resume(threads[2]);progressResult=true;resume(work)")
        self.assertEqual(self.lua.eval('serverEvents[#serverEvents]'),'meta_comic:server:vendingWorkCancel')
        self.assertEqual(self.lua.eval('#serverEvents'),1)
        self.assertEqual(self.lua.eval('progressCancels'),1)
        clears=self.lua.eval('hardClears')
        self.lua.execute("events['meta_comic:client:lootStopped']('Old acknowledgement')")
        self.assertEqual(self.lua.eval('hardClears'),clears)

    def test_interrupted_crime_cannot_report_success_after_progress_resumes(self):
        self.lua.execute("action=coroutine.create(function() events['meta_comic:client:crimeStart']({id=1,duration=4000,token='crime',animation={dict='test',clip='test'}}) end);resume(action);stunned=true;resume(threads[2]);progressResult=true;resume(action)")
        self.assertEqual(self.lua.eval('#serverEvents'),1)
        self.assertEqual(self.lua.eval('serverEvents[1]'),'meta_comic:server:crimeCancel')
        self.assertIsNone(self.lua.eval('lastClip'))

    def test_interrupted_animation_loading_cannot_restart_pose_or_minigame(self):
        self.lua.execute('''
            loaded=false;games=0
            function HasAnimDictLoaded() return loaded end
            MetaComic.RunMinigames=function() games=games+1;return true end
            action=coroutine.create(function()
                events['meta_comic:client:crimeStart']({id=1,duration=4000,token='crime',
                    animation={dict='test',clip='test'},minigame='test'})
            end)
            resume(action);ragdoll=true;resume(threads[2]);loaded=true;resume(action)
        ''')
        self.assertEqual(self.lua.eval('games'),0)
        self.assertIsNone(self.lua.eval('lastClip'))
        self.assertEqual(self.lua.eval('#serverEvents'),1)

    def test_resource_stop_clears_active_pose_and_props(self):
        self.start_loot()
        self.lua.execute("resourceEvents.onResourceStop('test');resume(visual)")
        self.assertTrue(self.lua.eval('next(objects)==nil'))
        self.assertEqual(self.lua.eval('progressCancels'),1)
        self.assertIsNone(self.lua.eval('lastClip'))

    def test_canceled_walk_cannot_snap_player_back_to_machine(self):
        self.lua.execute('''
            local mt={__index=function(v,key) if key=='xy' then return v end end,
                __sub=function(a,b) return vec3(a.x-b.x,a.y-b.y,a.z-b.z) end,
                __len=function(v) return math.sqrt(v.x*v.x+v.y*v.y+v.z*v.z) end}
            function vec3(x,y,z) return setmetatable({x=x,y=y,z=z},mt) end
            objects[99]=true;snaps=0
            MetaComic.VendingMachineById=function() return {entity=99} end
            function TaskTurnPedToFaceEntity() end
            function GetOffsetFromEntityInWorldCoords() return vec3(4,0,0) end
            function GetEntityHeading() return 0 end
            function TaskGoStraightToCoord() end
            function SetEntityCoordsNoOffset() snaps=snaps+1 end
            function SetEntityHeading() end
        ''')
        self.start_loot()
        self.lua.execute("events['meta_comic:client:lootStopped']('Interrupted');resume(visual)")
        self.assertEqual(self.lua.eval('snaps'),0)
        self.assertEqual(self.lua.eval('nextObject'),0)
        self.assertIsNone(self.lua.eval('lastClip'))

    def movement_machine(self):
        self.lua.execute('''
            local mt={__index=function(v,key) if key=='xy' then return v end end,
                __sub=function(a,b) return vec3(a.x-b.x,a.y-b.y,a.z-b.z) end,
                __len=function(v) return math.sqrt(v.x*v.x+v.y*v.y+v.z*v.z) end}
            function vec3(x,y,z) return setmetatable({x=x,y=y,z=z},mt) end
            player=vec3(-1,0,0);objects[99]=true;snaps=0;walks=0
            Config.VendingMachines.Crime.BreakIn.Loot.Visuals.Spots={Stock=vec3(0,0,0),Cash=vec3(1,0,0)}
            MetaComic.VendingMachineById=function() return {entity=99} end
            function GetEntityCoords(id) return id==99 and vec3(0,0,0) or player end
            function TaskTurnPedToFaceEntity() end
            function GetOffsetFromEntityInWorldCoords(_,x,y,z) return vec3(x,y,z) end
            function GetEntityHeading() return 0 end
            function TaskGoStraightToCoord(_,x,y,z)
                walks=walks+1;player=vec3((player.x+x)/2,(player.y+y)/2,player.z)
            end
            function SetEntityCoordsNoOffset(_,x,y,z) snaps=snaps+1;player=vec3(x,y,z) end
            function SetEntityHeading() end
        ''')

    def test_cash_stock_switch_walks_before_snap_without_self_canceling(self):
        self.movement_machine()
        self.lua.execute("events['meta_comic:client:lootStarted']({id=1});monitor=threads[2];batch=coroutine.create(function() events['meta_comic:client:lootBatch']({kind='stock',duration=4000}) end);resume(batch);visual=threads[3];resume(visual)")
        self.assertEqual(self.lua.eval('walks'),1)
        self.assertEqual(self.lua.eval('snaps'),0)
        self.lua.execute('timer=500;resume(monitor);resume(visual)')
        self.assertEqual(self.lua.eval('snaps'),0)
        self.lua.execute('timer=1000;resume(visual);resume(monitor);resume(visual)')
        self.assertEqual(self.lua.eval('snaps'),1)
        self.lua.execute("timer=4000;resume(visual);progressResult=true;resume(batch);batch=coroutine.create(function() events['meta_comic:client:lootBatch']({kind='cash',duration=4000}) end);resume(batch);visual=threads[4];resume(visual)")
        self.assertEqual(self.lua.eval('walks'),2)
        self.assertEqual(self.lua.eval('snaps'),1)
        self.lua.execute('timer=4500;resume(monitor);resume(visual);timer=5000;resume(visual);resume(monitor);resume(visual);resume(monitor)')
        self.assertEqual(self.lua.eval('snaps'),2)
        self.assertEqual(self.lua.eval('#serverEvents'),0)
        self.assertEqual(self.lua.eval('progressCancels'),0)
        # Displacement after settling still interrupts the theft.
        self.lua.execute('player=vec3(1.8,0,0);resume(monitor)')
        self.assertEqual(self.lua.eval('serverEvents[#serverEvents]'),'meta_comic:server:lootCancel')
        self.assertEqual(self.lua.eval('progressCancels'),1)

    def test_shove_during_scripted_transition_still_cancels(self):
        self.movement_machine()
        self.start_loot()
        self.lua.execute('ragdoll=true;resume(monitor);resume(visual)')
        self.assertEqual(self.lua.eval('serverEvents[#serverEvents]'),'meta_comic:server:lootCancel')
        self.assertEqual(self.lua.eval('snaps'),0)
        self.assertEqual(self.lua.eval('progressCancels'),1)

if __name__=='__main__': unittest.main()
