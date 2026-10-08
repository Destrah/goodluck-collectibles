"""Exercise the real client cylinder interaction, work pose, minigames and cancellation."""
from pathlib import Path
import sys
import unittest
if len(sys.argv) > 1: sys.path.insert(0, sys.argv.pop(1))
from lupa.lua54 import LuaRuntime
ROOT = Path(__file__).resolve().parents[1]


class RekeyClientTests(unittest.TestCase):
    def setUp(self):
        self.lua = LuaRuntime(unpack_returned_tuples=True)
        self.lua.execute('''
            function vector3(x,y,z) return {x=x,y=y,z=z} end
            Config={VendingMachines={Keys={Enabled=true,ReplaceOffset=vector3(0.85,-0.15,0)}}}
            handlers={};threads={};server={};timer=0;animations=0;controls=0
            playerCoords=vector3(0,0,0)
            function RegisterNetEvent(name,fn) handlers[name]=fn end
            function exports() end
            function CreateThread(fn) threads[#threads+1]=coroutine.create(fn) end
            function Wait(ms) timer=timer+math.max(ms,100);if coroutine.isyieldable() then coroutine.yield() end end
            function GetGameTimer() return timer end
            function TriggerEvent() end
            function TriggerServerEvent(name,token) server[#server+1]={name=name,token=token} end
            function GetResourceState() return 'started' end
            function PlayerPedId() return 11 end
            function DoesEntityExist() return not missing end
            function IsPedInAnyVehicle() return inCar end
            function GetEntityCoords(entity) return entity==11 and playerCoords or vector3(0,0,0) end
            function GetOffsetFromEntityInWorldCoords(_,x,y,z) return vector3(x,y,z) end
            function GetHeadingFromVector_2d(x,y) faceX=x;faceY=y;return 90 end
            function TaskGoStraightToCoord(_,x,y,z) if not blocked then playerCoords=vector3(x,y,z) end end
            function IsEntityDead() return false end
            function ClearPedTasks() playing=false end
            function SetEntityHeading(_,heading) facing=heading end
            function RequestAnimDict() end
            function HasAnimDictLoaded() return true end
            function DisableControlAction() controls=controls+1 end
            function IsEntityPlayingAnim() return playing end
            function TaskPlayAnim(_,dict,clip,_,_,_,flag) animations=animations+1;playing=true;animFlag=flag end
            function stepPose() local ok,err=coroutine.resume(threads[#threads]);assert(ok,err) end
            MetaComic={VendingMachineById=function() return {entity=1} end,RunMinigames=function()
                stepPose();poseDuringGame=playing;return not gameFailed
            end}
            exports=setmetatable({ox_lib={progressBar=function(_,data)
                stepPose();progress=data;poseDuringProgress=playing;return not canceled
            end}}, {__call=function() end})
        ''')
        self.lua.execute((ROOT / 'fivem/client/vending_keys.lua').read_text(encoding='utf-8'))

    def run_rekey(self):
        self.lua.execute("handlers['meta_comic:client:vendingRekeyStart']({id=1,token='job',duration=180000,minigame={'lockpick_hard','wires_hard'}})")

    def test_right_side_and_looping_pose_continue_through_minigames_and_timer(self):
        self.run_rekey()
        self.assertEqual(self.lua.eval('playerCoords.x'), .85)
        self.assertLess(self.lua.eval('faceX'), 0)
        self.assertTrue(self.lua.eval('poseDuringGame and poseDuringProgress'))
        self.assertEqual(self.lua.eval('animFlag'), 1)
        self.assertEqual(self.lua.eval('progress.duration'), 180000)
        self.assertEqual(self.lua.eval('server[#server].name'), 'meta_comic:server:vendingRekeyFinish')
        self.assertFalse(self.lua.eval('playing'))

    def test_failed_minigame_cancels_without_finish(self):
        self.lua.execute('gameFailed=true')
        self.run_rekey()
        self.assertIsNone(self.lua.eval('progress'))
        self.assertEqual(self.lua.eval('server[#server].name'), 'meta_comic:server:vendingRekeyCancel')

    def test_blocked_side_and_vehicle_use_cancel(self):
        for flag in ('blocked', 'inCar'):
            self.setUp()
            self.lua.execute(flag + '=true')
            self.run_rekey()
            self.assertIsNone(self.lua.eval('progress'))
            self.assertEqual(self.lua.eval('server[#server].name'), 'meta_comic:server:vendingRekeyCancel')

    def test_canceled_progress_does_not_finish_and_releases_pose(self):
        self.lua.execute('canceled=true')
        self.run_rekey()
        self.assertFalse(self.lua.eval('playing'))
        self.assertEqual(self.lua.eval('server[#server].name'), 'meta_comic:server:vendingRekeyCancel')


if __name__ == '__main__': unittest.main()
