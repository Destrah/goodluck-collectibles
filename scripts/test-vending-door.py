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

    def test_lock_wait_includes_each_lid_actual_angle_after_close_request(self):
        source = (ROOT / 'fivem/client/vending_door.lua').read_text(encoding='utf-8')
        section = source.split('MetaComic.VendingDoorOpen =', 1)[1].split('-- the hacks need', 1)[0]
        self.lua.execute('MetaComic={};doors={[1]={target=0,angle=0,lidAngle=0,rackAngle=30}};lids={};racks={};MetaComic.VendingDoorOpen =' + section)
        self.assertTrue(self.lua.eval("MetaComic.VendingLockPartsOpen(1,'cylinder')"))
        self.assertTrue(self.lua.eval("MetaComic.VendingLockPartsOpen(1,'rack')"))
        self.assertFalse(bool(self.lua.eval("MetaComic.VendingLockPartsOpen(1,'cashbox')")))
        self.lua.execute('doors[1].rackAngle=0;doors[1].lidAngle=20')
        self.assertTrue(self.lua.eval("MetaComic.VendingLockPartsOpen(1,'cylinder')"))
        self.assertTrue(self.lua.eval("MetaComic.VendingLockPartsOpen(1,'cashbox')"))
        self.lua.execute('doors[1].lidAngle=0')
        self.assertFalse(bool(self.lua.eval("MetaComic.VendingLockPartsOpen(1,'cylinder')")))
        self.lua.execute('lids[1]=0')  # an open, empty cashbox still needs closing
        self.assertTrue(self.lua.eval("MetaComic.VendingLockPartsOpen(1,'cylinder')"))

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

    def test_tow_body_is_used_directly_without_hiding_or_deleting_it(self):
        self.lua.execute('function GetEntityModel() return BODY end;state=Build(100)')
        self.assertEqual(self.lua.eval('state.body'), 100)
        self.assertFalse(self.lua.eval('state.ownsBody'))
        self.assertEqual(self.lua.eval('count'), 1)
        self.assertTrue(self.lua.eval('visible[100]==nil and alpha[100]==nil'))
        self.lua.execute('Drop(100,state)')
        self.assertTrue(self.lua.eval('entities[100] and not entities[1]'))

    def test_turn_response_opposes_acceleration_for_both_hinge_directions(self):
        source = (ROOT / 'fivem/client/vending_door.lua').read_text(encoding='utf-8')
        equation = next(line.strip() for line in source.splitlines() if 'local torque =' in line)
        for direction in (-1, 1):
            for sideways in (-1, 1):
                self.lua.execute(f'SIGN={direction};side={sideways};forward=0;rad=0;PUSH=260;{equation};response=SIGN*torque')
                self.assertLess(self.lua.eval('response') * sideways, 0)


if __name__ == '__main__':
    unittest.main()
