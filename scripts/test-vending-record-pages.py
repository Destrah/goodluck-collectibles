"""Verify server paging, log retention and portal/OS evidence boundaries against real Lua modules."""
from pathlib import Path
import importlib.util
import sys
import unittest

if len(sys.argv) > 1:
    sys.path.insert(0, sys.argv.pop(1))
ROOT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location('key_fixtures', ROOT / 'scripts/test-vending-keys.py')
fixtures = importlib.util.module_from_spec(spec)
spec.loader.exec_module(fixtures)


class PageTests(unittest.TestCase):
    def setUp(self):
        fixtures.KeyTests.setUp(self)
        self.lua.execute('''
            Registry=MetaComic.VendingRegistry
            MetaComic.CanManage=function(src) return src==44 end
            MetaComic.Portal={ownerScope=function(src) if src==11 then return 'owner' end end}
            MetaComic.Vending.accounting=function(e) return {cash=e.cash or 0} end
            record.history={};record.sales={}
            for i=1,130 do
                record.history[i]={at=2000-i,event='Main door opened',sensor=true,by='Secret criminal',authenticated=false}
                record.sales[i]={at=2000-i,item='Pack '..i,method='cash',price=i}
            end
            function page(src,kind,n,size,forensic)
                return MetaComic.RpcHandlers.getVendingRecordPage(src,{serial='VM-1',kind=kind,page=n,pageSize=size,forensic=forensic})
            end
        ''')

    def test_only_requested_rows_return_and_last_page_is_bounded(self):
        self.assertEqual(self.lua.eval("#page(11,'sales',2,50).items"), 50)
        self.assertEqual(self.lua.eval("page(11,'sales',2,50).items[1].item"), 'Pack 51')
        self.assertEqual(self.lua.eval("page(11,'sales',2,50).total"), 130)
        self.assertEqual(self.lua.eval("page(11,'sales',2,50).amount"), 8515)
        self.assertEqual(self.lua.eval("#page(11,'sales',999,50).items"), 30)
        self.assertEqual(self.lua.eval("page(11,'sales',999,50).page"), 3)
        self.assertEqual(self.lua.eval("page(11,'sales',-5,100000).pageSize"), 100)

    def test_filtered_events_do_not_leak_actor_names_or_hidden_row_counts(self):
        self.lua.execute("record.history[1].event='Card skimmer installed';record.history[1].sensor=nil;record.history[2].displayBy='Registered employee'")
        self.assertEqual(self.lua.eval("page(11,'history',1,50,true).total"), 129)
        self.assertEqual(self.lua.eval("page(11,'history',1,50,true).items[1].by"), 'Registered employee')
        self.assertIsNone(self.lua.eval("page(11,'history',1,50).items[2].by"))
        self.assertEqual(self.lua.eval("page(44,'history',1,50,true).total"), 130)
        self.assertEqual(self.lua.eval("page(44,'history',1,50,true).items[1].by"), 'Secret criminal')
        self.assertEqual(self.lua.eval("page(44,'history',1,50,false).total"), 129)

    def test_arbitrary_serials_and_unassigned_players_are_denied(self):
        self.assertFalse(self.lua.eval("page(66,'sales',1,50,true).ok"))
        self.assertFalse(self.lua.eval("MetaComic.RpcHandlers.getVendingRecordPage(11,{serial='missing',kind='history'}).ok"))
        self.assertFalse(self.lua.eval("page(11,'keyArchive',1,50).ok"))
        self.assertFalse(self.lua.eval('MetaComic.RpcHandlers.getVendingRecordPage(44,nil).ok'))

    def test_summary_contains_counts_and_keys_without_log_arrays(self):
        self.lua.execute("summary=MetaComic.RpcHandlers.getVendingRecords(44,{summary=true,forensic=true}).machines[1]")
        self.assertIsNone(self.lua.eval('summary.history'))
        self.assertIsNone(self.lua.eval('summary.sales'))
        self.assertIsNotNone(self.lua.eval('summary.keyArchive'))
        self.assertEqual(self.lua.eval('summary.historyCount'), 130)
        self.assertEqual(self.lua.eval('summary.salesCount'), 130)
        self.assertEqual(self.lua.eval('summary.salesAmount'), 8515)

    def test_os_takeover_separates_live_logs_frozen_logs_and_admin_archives(self):
        self.lua.execute("Registry.update('VM-1',Registry.osStartFields(record,'hacker'),'Operating system taken over');Registry.sensor('VM-1','New OS observation',22);Registry.logSale('VM-1',{at=3000,item='OS pack',price=9})")
        self.assertEqual(self.lua.eval("page(22,'sales',1,50,true).total"), 1)
        self.assertEqual(self.lua.eval("page(22,'sales',1,50,true).items[1].item"), 'OS pack')
        self.assertEqual(self.lua.eval("page(11,'sales',1,50).total"), 130)
        self.assertEqual(self.lua.eval("page(44,'sales',1,50,true).total"), 131)
        self.lua.execute("record.osArchives={{sales={{at=4000,item='Archived OS pack',price=20}},history={{at=4000,event='Archived crime'}}}}")
        self.assertEqual(self.lua.eval("page(44,'sales',1,50,true).items[1].item"), 'Archived OS pack')
        self.assertEqual(self.lua.eval("page(44,'history',1,50,true).items[1].event"), 'Archived crime')
        self.assertTrue(self.lua.execute("return Registry.setOSAccess(22,'VM-1',33,true)"))
        self.assertTrue(self.lua.eval("page(33,'sales',1,50).ok"))
        self.assertTrue(self.lua.execute("return Registry.setOSAccess(22,'VM-1',33,false)"))
        self.assertFalse(self.lua.eval("page(33,'sales',1,50).ok"))

    def test_future_logs_retain_500_rows_with_older_configuration_preserved(self):
        # The inherited fixture boots the registry before loading config.lua; production loads config first.
        self.lua.execute((ROOT / 'fivem/server/modules/vending_registry.lua').read_text(encoding='utf-8'))
        self.lua.execute('Registry=MetaComic.VendingRegistry')
        self.lua.execute("record.history={};record.sales={};for i=1,610 do Registry.sensor('VM-1','Main door opened',11);Registry.logSale('VM-1',{at=i,price=i}) end")
        self.assertEqual(self.lua.eval('#record.history'), 500)
        self.assertEqual(self.lua.eval('#record.sales'), 500)
        self.assertEqual(self.lua.eval('record.sales[500].price'), 111)
        self.assertEqual(self.lua.eval('Config.VendingMachines.Ownership.HistoryLength'), 25)
        self.assertEqual(self.lua.eval('Config.VendingMachines.Ownership.SalesLog'), 50)


if __name__ == '__main__':
    unittest.main()
