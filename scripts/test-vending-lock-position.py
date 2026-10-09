"""Exercise actual lock approach code: walking, facing, cancellation and reach."""
from pathlib import Path
import sys
import unittest

if len(sys.argv) > 1:
    sys.path.insert(0, sys.argv.pop(1))
from lupa.lua54 import LuaRuntime
ROOT = Path(__file__).resolve().parents[1]


class LockPositionTests(unittest.TestCase):
    def setUp(self):
        self.lua = LuaRuntime(unpack_returned_tuples=True)
        self.lua.execute('''
            local mt={__sub=function(a,b) return vec3(a.x-b.x,a.y-b.y,a.z-b.z) end,
                __len=function(v) return math.sqrt(v.x*v.x+v.y*v.y+v.z*v.z) end}
            function vec3(x,y,z) return setmetatable({x=x,y=y,z=z},mt) end
            vector3=vec3
            function vec4(x,y,z,w) return {x=x,y=y,z=z,w=w} end
            timer=0;active=true;snaps=0;walks=0;exists=true;player=vec3(0,-1,-.95)
            function PlayerPedId() return 1 end
            function GetGameTimer() return timer end
            function Wait(ms) timer=timer+(ms==0 and 500 or ms);if cancel then active=false end end
            function DoesEntityExist() return exists end
            function GetOffsetFromEntityInWorldCoords(_,x,y,z) return vec3(x+10,y+20,z) end
            function GetHeadingFromVector_2d(x,y) faceX=x;faceY=y;return 123 end
            function ClearPedTasks() end
            function TaskGoStraightToCoord(_,x,y,z)
                walks=walks+1;walkX=x;walkY=y;player=vec3(x,y,z)
                if far then player=vec3(x+5,y,z) end
            end
            function GetEntityCoords() return player end
            function SetEntityCoordsNoOffset(_,x,y,z) snaps=snaps+1;snapAt=timer;snapX=x;snapY=y end
            function SetEntityHeading(_,h) heading=h end
            function TaskTurnPedToFaceEntity() end
        ''')
        self.lua.execute((ROOT / 'fivem/config.lua').read_text(encoding='utf-8'))
        self.lua.execute('crime=Config.VendingMachines.Crime')
        script = (ROOT / 'fivem/client/vending_crime.lua').read_text(encoding='utf-8')
        code = 'local function approachLock' + script.split('local function approachLock', 1)[1].split("RegisterNetEvent('meta_comic:client:crimeStart'", 1)[0]
        self.lua.execute(code + '\nApproach=approachLock;function current() return active end')

    def test_separate_lock_spots_walk_then_face(self):
        for action, x, y in [('breakin', 10.49, 18.96), ('pickpadlock', 10.58, 18.98)]:
            self.lua.execute(f"timer=0;Approach({{entity=99}},'{action}',current)")
            self.assertAlmostEqual(self.lua.eval('snapX'), x)
            self.assertAlmostEqual(self.lua.eval('snapY'), y)
            self.assertGreaterEqual(self.lua.eval('snapAt'), 1000)
            self.assertEqual(self.lua.eval('heading'), 123)
            self.assertAlmostEqual(self.lua.eval('faceX'), 0)
            self.assertGreater(self.lua.eval('faceY'), 0)

    def test_interrupted_approach_never_snaps(self):
        self.lua.execute("cancel=true;result=Approach({entity=99},'breakin',current)")
        self.assertFalse(self.lua.eval('result'))
        self.assertEqual(self.lua.eval('snaps'), 0)

    def test_out_of_reach_never_teleports(self):
        self.lua.execute("far=true;result=Approach({entity=99},'pickpadlock',current)")
        self.assertFalse(self.lua.eval('result'))
        self.assertEqual(self.lua.eval('snaps'), 0)

    def test_missing_machine_does_not_start_walk(self):
        self.lua.execute("exists=false;result=Approach({entity=99},'breakin',current)")
        self.assertFalse(self.lua.eval('result'))
        self.assertEqual(self.lua.eval('walks'), 0)


if __name__ == '__main__':
    unittest.main()
