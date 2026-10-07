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
            self.assertEqual(self.lua.eval('lastClip'),'givetake1_a')
            self.lua.execute('step(2200)')
            self.assertEqual(self.lua.eval('lastClip'),'grab')
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

if __name__=='__main__': unittest.main()
