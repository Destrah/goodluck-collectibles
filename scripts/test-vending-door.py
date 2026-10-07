"""Moving cabinet assembly visibility and failed-spawn cleanup."""
from pathlib import Path
import sys
import unittest

if len(sys.argv) > 1:
    sys.path.insert(0, sys.argv.pop(1))
from lupa.lua54 import LuaRuntime

ROOT = Path(__file__).resolve().parents[1]


class MovingDoorTests(unittest.TestCase):
    def setUp(self):
        self.lua = LuaRuntime(unpack_returned_tuples=True)
        self.lua.execute('''
            BODY=10;DOOR=20;HINGE={x=1,y=2,z=3};SIGN=-1;REST=35
            loose={};entities={[100]=true};visible={};alpha={};parents={};count=0
            cfg={Model='full'};broken=true
            function Entity() return {state={metaComicDoorLoose=broken}} end
            function joaat() return 30 end
            function vector3(x,y,z) return {x=x,y=y,z=z} end
            function GetEntityModel() return 40 end
            function GetModelDimensions(model) return {z=model==40 and -0.5 or -0.95} end
            function load() return true end
            function GetEntityCoords() return {x=0,y=0,z=0} end
            function GetEntityVelocity() return {x=0,y=0,z=0} end
            function CreateObjectNoOffset(model)
                count=count+1
                if failModel==model then return 0 end
                entities[count]=true;return count
            end
            function DoesEntityExist(id) return entities[id]==true end
            function DeleteEntity(id) entities[id]=nil end
            function SetEntityCollision() end
            function AttachEntityToEntity(child,parent) parents[child]=parent end
            function SetModelAsNoLongerNeeded() end
            function SetEntityVisible(id,value) visible[id]=value end
            function SetEntityAlpha(id,value) alpha[id]=value end
            function ResetEntityAlpha(id) alpha[id]=255 end
        ''')
        source = (ROOT / 'fivem/client/vending_door.lua').read_text(encoding='utf-8')
        section = source.split('local function dropLoose', 1)[1].split('if LOOSE.Enabled', 1)[0]
        self.lua.execute('local function dropLoose' + section + '\nBuild=buildLoose;Drop=dropLoose')

    def test_body_and_door_share_visible_attachment_parent(self):
        self.lua.execute('state=Build(100)')
        self.assertTrue(self.lua.eval('visible[100]'))
        self.assertEqual(self.lua.eval('alpha[100]'), 0)
        self.assertEqual(self.lua.eval('parents[state.body]'), 100)
        self.assertEqual(self.lua.eval('parents[state.door]'), self.lua.eval('state.body'))

    def test_cleanup_restores_original_and_removes_both_parts(self):
        self.lua.execute('state=Build(100);loose[100]=state;Drop(100,state)')
        self.assertEqual(self.lua.eval('alpha[100]'), 255)
        self.assertTrue(self.lua.eval('entities[100] and not entities[1] and not entities[2]'))
        self.assertTrue(self.lua.eval('loose[100]==nil'))

    def test_partial_spawn_keeps_original_and_removes_orphans(self):
        for model in (10, 20):
            self.setUp()
            self.lua.execute(f'failModel={model};state=Build(100)')
            self.assertTrue(self.lua.eval('state==nil and entities[100]'))
            self.assertTrue(self.lua.eval('not entities[1] and not entities[2]'))
            self.assertTrue(self.lua.eval('visible[100]==nil and alpha[100]==nil'))

    def test_intact_world_machine_uses_complete_custom_mesh(self):
        self.lua.execute('broken=false;state=Build(100)')
        self.assertTrue(self.lua.eval('state.body~=nil and state.door==nil and not state.broken'))
        self.assertEqual(self.lua.eval('count'), 1)
        self.assertTrue(self.lua.eval('visible[100] and alpha[100]==0'))


if __name__ == '__main__':
    unittest.main()
