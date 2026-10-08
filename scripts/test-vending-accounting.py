"""Exercise persisted OS accounting and server-side portal/admin disclosure."""
from pathlib import Path
import importlib.util
import sys
import unittest
if len(sys.argv) > 1:
    sys.path.insert(0, sys.argv.pop(1))
ROOT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location('fixtures', ROOT / 'scripts/test-vending-keys.py')
fixtures = importlib.util.module_from_spec(spec)
spec.loader.exec_module(fixtures)

def load_accounting(lua):
    code = (ROOT / 'fivem/server/modules/vending_machines.lua').read_text(encoding='utf-8')
    section = code.split('local function accounting(entry)', 1)[1].split('local function clientProducts', 1)[0]
    lua.execute('Registry=MetaComic.VendingRegistry\nfunction accounting(entry)' + section.replace('local function accountChange', 'function accountChange'))
    lua.execute('MetaComic.Vending.accounting=accounting')

class AccountingTests(unittest.TestCase):
    provide_issuer_key = fixtures.KeyTests.provide_issuer_key
    issue = fixtures.KeyTests.issue
    unlock = fixtures.KeyTests.unlock
    load_management_handlers = fixtures.KeyTests.load_management_handlers

    def setUp(self):
        fixtures.KeyTests.setUp(self)
        self.lua.execute("Registry=MetaComic.VendingRegistry;entry.cash=750;entry.products={{set='base',kind='pack',stock=10}};record.status='placed';MetaComic.CanManage=function(src) return src==44 end;MetaComic.Portal={ownerScope=function(src) if src==11 then return 'owner' end end}")
        load_accounting(self.lua)
        self.lua.execute('accounting(entry)')

    def test_theft_then_purchase_and_restock_do_not_reveal_missing_contents(self):
        self.lua.execute("entry.cash=250;entry.products[1].stock=4;accountChange(entry,entry.products[1],-1,100);accountChange(entry,entry.products[1],2,0)")
        self.assertEqual(self.lua.eval('accounting(entry).cash'), 850)
        self.assertEqual(self.lua.eval("accounting(entry).stock['base:pack']"), 11)
        self.assertEqual(self.lua.eval('entry.cash'), 250)

    def test_real_loot_batches_leave_recorded_cash_and_stock_unchanged(self):
        spec = importlib.util.spec_from_file_location('loot_fixtures', ROOT / 'scripts/test-vending-loot.py')
        loot = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(loot)
        for mode in ('cash', 'stock'):
            scenario = loot.LootTests()
            scenario.setUp()
            load_accounting(scenario.lua)
            scenario.lua.execute('accounting(entry)')
            scenario.start(mode)
            scenario.lua.execute('advance(5000)')
            self.assertEqual(scenario.lua.eval('accounting(entry).cash'), 300)
            self.assertEqual(scenario.lua.eval("accounting(entry).stock['test:pack']"), 3)
            if mode == 'cash':
                self.assertEqual(scenario.lua.eval('entry.cash'), 200)
            else:
                self.assertEqual(scenario.lua.eval('entry.products[1].stock'), 2)

    def test_portals_hide_crime_details_even_from_managers(self):
        self.lua.execute("Registry.update('VM-1',nil,'Card skimmer installed','Criminal');Registry.update('VM-1',nil,'Cabinet forced open','Criminal');Registry.update('VM-1',nil,'GPS disabled','Criminal');Registry.sensor('VM-1','Server cabinet opened',22)")
        self.assertEqual(self.lua.eval('#Registry.viewFor(record,44,true).history'), 3)
        self.assertIsNone(self.lua.eval('Registry.viewFor(record,44,true).history[1].by'))
        self.assertIsNone(self.lua.eval('Registry.viewFor(record,44,true).history[2].by'))
        self.assertEqual(self.lua.eval('Registry.viewFor(record,44,true).history[3].event'), 'Lock resistance / vibration detected')
        self.assertEqual(self.lua.eval('#Registry.view(record,true).history'), 4)

    def test_authenticated_owner_sensor_has_identity_and_forgery_preserves_admin_actor(self):
        self.lua.execute("Registry.sensor('VM-1','Main door opened',11);Registry.sensor('VM-1','Server cabinet opened',22);record.history[1].displayBy='Employee'")
        self.assertEqual(self.lua.eval('Registry.viewFor(record,44,true).history[1].by'), 'Employee')
        self.assertIsNotNone(self.lua.eval('Registry.viewFor(record,44,true).history[2].by'))
        self.assertNotEqual(self.lua.eval('Registry.view(record,true).history[1].by'), 'Employee')

    def test_records_rpc_requires_manager_for_forensic_data(self):
        self.lua.execute((ROOT / 'fivem/server/modules/vending_records.lua').read_text(encoding='utf-8'))
        self.lua.execute("entry.cash=100;Registry.update('VM-1',nil,'Card skimmer installed','Criminal')")
        self.assertEqual(self.lua.eval('MetaComic.RpcHandlers.getVendingRecords(44,{forensic=true}).machines[1].cash'), 100)
        self.assertEqual(self.lua.eval('MetaComic.RpcHandlers.getVendingRecords(44,{forensic=false}).machines[1].cash'), 750)
        self.assertEqual(self.lua.eval('#MetaComic.RpcHandlers.getVendingRecords(44,{forensic=false}).machines[1].history'), 0)
        self.assertEqual(self.lua.eval('#MetaComic.RpcHandlers.getVendingRecords(11,{forensic=true}).machines[1].history'), 0)

    def test_physical_collection_displays_actual_cash_and_zero_after_completion(self):
        self.load_management_handlers()
        self.issue()
        self.unlock()
        code = (ROOT / 'fivem/server/modules/vending_machines.lua').read_text(encoding='utf-8')
        section = 'local function manageInfo' + code.split('local function manageInfo', 1)[1].split('local function openManage', 1)[0]
        self.lua.execute('cfg=Config.VendingMachines\n' + section + '\nManageInfo=manageInfo')
        self.lua.execute("record.accounting.cash=5750;entry.cash=5350;record.owner=nil;function openManage(src,e) latestManage=ManageInfo(src,e) end")
        self.assertEqual(self.lua.eval('ManageInfo(11,entry).cash'), 5350)
        self.lua.execute("handlers['meta_comic:server:vendingOwner'](1,'collect')")
        self.assertEqual(self.lua.eval('entry.cash'), 0)
        self.assertEqual(self.lua.eval('latestManage.cash'), 0)
        self.assertEqual(self.lua.eval('record.accounting.cash'), 400)
        self.lua.execute((ROOT / 'fivem/server/modules/vending_records.lua').read_text(encoding='utf-8'))
        self.assertEqual(self.lua.eval('MetaComic.RpcHandlers.getVendingRecords(44,{forensic=false}).machines[1].cash'), 400)
        self.lua.execute("handlers['meta_comic:server:vendingOwner'](1,'collect')")
        self.assertEqual(self.lua.eval('latestManage.cash'), 0)

    def test_resync_requires_authorized_open_rack_and_preserves_totals_on_save_failure(self):
        self.load_management_handlers()
        self.issue()
        self.unlock()
        self.lua.execute("rackOpen=false;MetaComic.VendingCashbox.rackOpen=function() return rackOpen end;entry.cash=100;entry.products[1].stock=2;handlers['meta_comic:server:vendingOwner'](1,'resync')")
        self.assertEqual(self.lua.eval('accounting(entry).cash'), 750)
        self.lua.execute("rackOpen=true;saveOK=false;handlers['meta_comic:server:vendingOwner'](1,'resync')")
        self.assertEqual(self.lua.eval('accounting(entry).cash'), 750)
        self.lua.execute("saveOK=true;handlers['meta_comic:server:vendingOwner'](1,'resync')")
        self.assertEqual(self.lua.eval('accounting(entry).cash'), 100)
        self.assertEqual(self.lua.eval("accounting(entry).stock['base:pack']"), 2)

    def test_falsification_requires_open_rack_at_start_and_finish(self):
        self.lua.execute("Registry.register('employee','Registered Employee',0);Registry.sensor('VM-1','Server cabinet opened',22);source=22;rackOpen=false;MetaComic.VendingCashbox.rackOpen=function() return rackOpen end;handlers['meta_comic:server:crimeStart'](1,'falsifylogs',{employee='employee'})")
        self.assertIsNone(self.lua.eval('startData'))
        self.lua.execute("rackOpen=true;handlers['meta_comic:server:crimeStart'](1,'falsifylogs',{employee='employee'});rackOpen=false;timer=45000;handlers['meta_comic:server:crimeFinish'](startData.token,true)")
        self.assertIsNone(self.lua.eval('record.history[1].displayBy'))
        self.lua.execute("rackOpen=true;handlers['meta_comic:server:crimeStart'](1,'falsifylogs',{employee='employee'});timer=90000;handlers['meta_comic:server:crimeFinish'](startData.token,true)")
        self.assertEqual(self.lua.eval('Registry.viewFor(record,44,true).history[1].by'), 'Registered Employee')
        self.assertNotEqual(self.lua.eval('Registry.view(record,true).history[1].by'), 'Registered Employee')

    def test_all_changed_lua_parse(self):
        for relative in ('config.lua', 'client/vending_machines.lua', 'client/vending_crime.lua', 'server/modules/vending_machines.lua', 'server/modules/vending_registry.lua', 'server/modules/vending_records.lua', 'server/modules/vending_crime.lua', 'server/modules/vending_door.lua', 'server/modules/vending_security.lua'):
            code = (ROOT / 'fivem' / relative).read_text(encoding='utf-8')
            self.lua.execute('assert(load(...))', code)

if __name__ == '__main__':
    unittest.main()
