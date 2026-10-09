"""Physical slot props follow stock theft independently of persisted OS accounting."""
from pathlib import Path
import importlib.util
import sys
import unittest
if len(sys.argv) > 1:
    sys.path.insert(0, sys.argv.pop(1))
from lupa.lua54 import LuaRuntime
ROOT = Path(__file__).resolve().parents[1]


class DisplayStockTests(unittest.TestCase):
    def setUp(self):
        self.lua = LuaRuntime(unpack_returned_tuples=True)
        self.lua.execute('''
            function vec3(x,y,z) return {x=x,y=y,z=z} end
            vector3=vec3;function vec4() return {} end
            MetaComic={};entities={[99]=true,[98]=true};parents={};models={};nextProp=100
            function DoesEntityExist(id) return entities[id]==true end
            function DeleteEntity(id) entities[id]=nil end
            function joaat(model) return model end
            function loadModel(hash) return hash end
            function CreateObjectNoOffset(hash) nextProp=nextProp+1;entities[nextProp]=true;models[nextProp]=hash;return nextProp end
            function SetEntityCollision() end
            function SetModelAsNoLongerNeeded() end
            function AttachEntityToEntity(prop,parent) parents[prop]=parent end
            function SetTimeout() end
            machines={}
        ''')
        self.lua.execute((ROOT/'fivem/config.lua').read_text(encoding='utf-8'))
        code = (ROOT/'fivem/client/vending_machines.lua').read_text(encoding='utf-8')
        section = code.split('local slotPacks =',1)[1].split('local function spawn(machine)',1)[0]
        self.lua.execute('cfg=Config.VendingMachines;local MAX_STOCK=100;local slotPacks =' + section + '\nSync=syncPacks')

    def test_pack_props_decrease_to_empty_while_recorded_stock_stays_full(self):
        self.lua.execute("machine={id=1,entity=99,packParent=98,coords=vec3(0,0,0),products={{set='base',kind='pack',stock=100,maxStock=100}},displayStock={['base:pack']=100}};Sync(machine)")
        self.assertEqual(self.lua.eval('#machine.packProps'), 15)
        self.lua.execute("oldProps=machine.packProps;machine.displayStock['base:pack']=50;Sync(machine)")
        self.assertEqual(self.lua.eval('#machine.packProps'), 8)
        self.assertFalse(self.lua.eval('entities[oldProps[1]]==true'))
        self.assertEqual(self.lua.eval('parents[machine.packProps[1]]'), 98)
        self.lua.execute("machine.displayStock['base:pack']=0;Sync(machine)")
        self.assertEqual(self.lua.eval('#machine.packProps'), 0)
        self.assertEqual(self.lua.eval('machine.products[1].stock'), 100)

    def test_selected_boxes_empty_without_removing_other_packs_and_can_restock(self):
        self.lua.execute("machine={id=1,entity=99,coords=vec3(0,0,0),products={{set='base',kind='pack',stock=100,maxStock=100},{set='base',kind='box',stock=20,maxStock=20}},displayStock={['base:pack']=100,['base:box']=20}};Sync(machine)")
        self.assertEqual(self.lua.eval('#machine.packProps'), 14)
        self.lua.execute("machine.displayStock['base:box']=0;Sync(machine)")
        self.assertEqual(self.lua.eval('#machine.packProps'), 7)
        self.assertEqual(self.lua.eval('models[machine.packProps[7]]'), 'metacomics_slot_pack')
        self.lua.execute("machine.displayStock['base:box']=10;Sync(machine)")
        self.assertEqual(self.lua.eval('#machine.packProps'), 11)
        self.assertEqual(self.lua.eval('models[machine.packProps[11]]'), 'prop_boosterbox_01')

    def test_real_loot_broadcast_contains_physical_zero_but_preserves_recorded_stock(self):
        spec = importlib.util.spec_from_file_location('loot', ROOT/'scripts/test-vending-loot.py')
        fixture = importlib.util.module_from_spec(spec);spec.loader.exec_module(fixture)
        scenario = fixture.LootTests();scenario.setUp()
        code = (ROOT/'fivem/server/modules/vending_machines.lua').read_text(encoding='utf-8')
        products = code.split('local function accounting(entry)',1)[1].split('local function cleanProducts',1)[0]
        entry = code.split('local function clientEntry(entry)',1)[1].split('local function saveJson',1)[0]
        scenario.lua.execute('''
            Registry=MetaComic.VendingRegistry
            function getSet(id) return {id=id,name=id} end
            function maxStockOf(kind) return kind=='box' and 20 or 100 end
            function recordOf() return record end
        ''')
        scenario.lua.execute('local function accounting(entry)' + products + '\nfunction ClientEntry(entry)' + entry)
        scenario.lua.execute("entry.products={{set='test',kind='box',stock=1}};initial=ClientEntry(entry);MetaComic.Vending.broadcast=function(entry) latest=ClientEntry(entry) end")
        scenario.start('stock');scenario.lua.execute('advance(5000)')
        self.assertEqual(scenario.lua.eval("latest.displayStock['test:box']"), 0)
        self.assertEqual(scenario.lua.eval('latest.products[1].stock'), 1)


if __name__ == '__main__':
    unittest.main()
