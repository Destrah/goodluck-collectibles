"""Real Lua takeover isolation, delegation, remote map and recovery regression tests."""
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


class OSTests(unittest.TestCase):
    provide_issuer_key = fixtures.KeyTests.provide_issuer_key
    issue = fixtures.KeyTests.issue
    replace = fixtures.KeyTests.replace
    unlock = fixtures.KeyTests.unlock
    load_management_handlers = fixtures.KeyTests.load_management_handlers

    def setUp(self):
        fixtures.KeyTests.setUp(self)
        self.lua.execute('''
            MetaComic.Framework.getIdentifier=function(src)
                if src==11 then return 'owner' elseif src==22 then return 'hacker' else return 'person-'..src end
            end
            MetaComic.CanManage=function(src) return src==44 end
            MetaComic.Portal={ownerScope=function(src) if src==11 then return 'owner' end end}
            Registry=MetaComic.VendingRegistry
            record.status='placed';record.coords={x=10,y=20,z=30}
            record.history={{at=900,event='Original private business history',sensor=true}}
            record.sales={{at=900,total=123,secret='Original sale'}}
            order={1};cfg=Config.VendingMachines
            function clientProducts(e) return MetaComic.CopyTable(e.products) end
            MetaComic.VendingSecurity.gpsPosition=function() return gpsFix end
        ''')
        self.load_management_handlers()
        code = (ROOT / 'fivem/server/modules/vending_machines.lua').read_text(encoding='utf-8')
        section = code.split('-- Map of every machine', 1)[1].split('-- Restock', 1)[0]
        self.lua.execute('-- Map of every machine' + section)

    def take_over(self):
        self.lua.execute("Registry.update('VM-1',Registry.osStartFields(record,'hacker'),'Operating system taken over');MetaComic.Vending.sendAccessAll()")

    def test_new_os_does_not_receive_business_history_sales_or_existing_keys(self):
        self.issue()
        self.take_over()
        self.lua.execute("Registry.sensor('VM-1','New private OS event',22);Registry.logSale('VM-1',{at=1100,total=456})")
        self.assertEqual(self.lua.eval('Registry.viewFor(record,22,true).history[1].event'), 'New private OS event')
        self.assertEqual(self.lua.eval('#Registry.viewFor(record,22,true).sales'), 1)
        self.assertEqual(self.lua.eval('Registry.viewFor(record,22,true).sales[1].total'), 456)
        self.assertEqual(self.lua.eval('#Registry.viewFor(record,22,true).keyArchive.keys'), 0)
        self.assertEqual(self.lua.eval('#Registry.viewFor(record,22,true).keyArchive.cylinders'), 0)
        for actor in (11, 44, 55):
            self.assertEqual(self.lua.eval(f'Registry.viewFor(record,{actor},true).history[1].event'), 'Original private business history')
            self.assertEqual(self.lua.eval(f'Registry.viewFor(record,{actor},true).sales[1].total'), 123)
            self.assertIsNone(self.lua.eval(f'Registry.viewFor(record,{actor},true).coords'))
        self.assertEqual(self.lua.eval('#record.sales'), 1)
        self.assertEqual(self.lua.eval('#record.history'), 1)

    def test_remote_map_denies_business_owner_and_unassigned_but_supports_delegate(self):
        self.take_over()
        for actor in (11, 44):
            self.assertEqual(self.lua.eval(f'#MetaComic.RpcHandlers.getVendingMachines({actor}).machines'), 0)
        self.assertFalse(self.lua.eval('MetaComic.RpcHandlers.getVendingMachines(33).ok'))
        self.assertEqual(self.lua.eval('#MetaComic.RpcHandlers.getVendingMachines(22).machines'), 1)
        self.assertTrue(self.lua.execute("return Registry.setOSAccess(22,'VM-1',33,true)"))
        self.assertEqual(self.lua.eval('#MetaComic.RpcHandlers.getVendingMachines(33).machines'), 1)
        self.assertFalse(self.lua.eval("Registry.setOSAccess(33,'VM-1',66,true)")[0])
        self.assertFalse(self.lua.eval("Registry.setOSAccess(44,'VM-1',66,true)")[0])
        self.assertTrue(self.lua.execute("return Registry.setOSAccess(22,'VM-1',33,false)"))
        self.assertFalse(self.lua.eval('MetaComic.RpcHandlers.getVendingMachines(33).ok'))

    def test_moving_gps_fixes_do_not_leak_to_previous_owner_or_business(self):
        self.take_over()
        self.lua.execute("record.status='item';machines={};order={};gpsFix={x=100,y=200,z=5,at=now,how='towed'}")
        self.assertEqual(self.lua.eval('#MetaComic.RpcHandlers.getVendingMachines(11).machines'), 0)
        self.assertEqual(self.lua.eval('#MetaComic.RpcHandlers.getVendingMachines(44).machines'), 0)
        self.assertEqual(self.lua.eval('MetaComic.RpcHandlers.getVendingMachines(22).machines[1].x'), 100)

    def test_records_rpc_and_printing_partition_both_groups(self):
        self.issue(); self.take_over()
        self.lua.execute("Registry.sensor('VM-1','Private takeover log',22);Registry.logSale('VM-1',{at=1100,total=456})")
        self.assertEqual(self.lua.eval('MetaComic.RpcHandlers.getVendingRecords(22).scope'), 'os')
        self.assertEqual(self.lua.eval('MetaComic.RpcHandlers.getVendingRecords(22).machines[1].history[1].event'), 'Private takeover log')
        self.assertTrue(self.lua.eval('MetaComic.RpcHandlers.getVendingRecords(11).machines[1].remoteOffline'))
        self.assertIsNone(self.lua.eval('MetaComic.RpcHandlers.getVendingRecords(44).machines[1].cash'))
        self.assertTrue(self.lua.eval("MetaComic.RpcHandlers.saveVendingRecords(22,{action='osAccess',serial='VM-1',serverId=33,allowed=true}).ok"))
        self.assertTrue(self.lua.eval('MetaComic.RpcHandlers.getVendingRecords(33).machines[1].osView'))
        self.assertFalse(self.lua.eval("MetaComic.RpcHandlers.saveVendingRecords(33,{action='assign',serial='VM-1',owner='person-33'}).ok"))
        self.assertFalse(self.lua.eval("MetaComic.RpcHandlers.saveVendingRecords(33,{action='certificate',serial='VM-1'}).ok"))
        self.assertTrue(self.lua.eval("MetaComic.RpcHandlers.saveVendingRecords(33,{action='keyReport',serial='VM-1'}).ok"))
        self.lua.execute("source=33;handlers['meta_comic:server:useVendingRecord']('keyreport',1)")
        self.assertEqual(self.lua.eval('#viewed.printed.archive.keys'), 0)
        self.lua.execute("source=11;handlers['meta_comic:server:vendingKeyReport']('VM-1',false)")
        self.assertEqual(self.lua.eval('#viewed.printed.archive.keys'), 2)

    def test_delegates_have_operating_controls_but_no_key_or_ownership_bypass(self):
        self.take_over()
        self.assertTrue(self.lua.execute("return Registry.setOSAccess(22,'VM-1',33,true)"))
        self.assertTrue(self.lua.eval('CanMaintain(33,entry)'))
        self.assertTrue(self.lua.eval('CanOperate(33,entry)'))
        self.assertTrue(self.lua.eval('Keys.canRegister(33,record)'))
        self.assertFalse(self.lua.eval("CabinetAccess(33,entry,'full')"))
        self.assertFalse(self.lua.eval('Keys.canIssue(33,record)'))
        self.assertFalse(self.lua.eval("Registry.ownedBy(record,'person-33')"))
        self.lua.execute("cabinetOpen=false;source=33;handlers['meta_comic:server:vendingRekeyStart'](1)")
        self.assertIsNone(self.lua.eval('startData'))

    def test_recovery_revokes_remote_access_resumes_business_logging_without_backfill(self):
        self.issue(); self.take_over()
        self.assertTrue(self.lua.execute("return Registry.setOSAccess(22,'VM-1',33,true)"))
        self.lua.execute("Registry.update('VM-1',nil,'Private OS event');Registry.logSale('VM-1',{at=1100,total=456});source=11;handlers['meta_comic:server:crimeStart'](1,'replaceboard');timer=60000;handlers['meta_comic:server:crimeFinish'](startData.token,true)")
        self.assertIsNone(self.lua.eval('record.systemController'))
        self.assertIsNone(self.lua.eval('record.osDelegates'))
        self.assertFalse(self.lua.eval('Registry.hasOSAccess(33)'))
        self.assertFalse(self.lua.eval('MetaComic.RpcHandlers.getVendingRecords(33).ok'))
        self.assertEqual(self.lua.eval('#MetaComic.RpcHandlers.getVendingMachines(11).machines'), 1)
        self.assertEqual(self.lua.eval('#MetaComic.RpcHandlers.getVendingMachines(44).machines'), 1)
        self.assertEqual(self.lua.eval('#record.sales'), 1)
        self.assertEqual(self.lua.eval('record.sales[1].total'), 123)
        self.assertEqual(self.lua.eval('record.osArchives[1].sales[1].total'), 456)
        self.lua.execute("Registry.logSale('VM-1',{at=1200,total=789})")
        self.assertEqual(self.lua.eval('#record.sales'), 2)
        self.assertEqual(self.lua.eval('record.sales[1].total'), 789)
        self.assertFalse(self.lua.eval("(function() for _,event in ipairs(record.history) do if event.event=='Private OS event' then return true end end;return false end)()"))

    def test_failed_grant_save_preserves_old_acl_and_restart_keeps_successful_acl(self):
        self.take_over()
        self.lua.execute('saveOK=false')
        self.assertFalse(self.lua.eval("Registry.setOSAccess(22,'VM-1',33,true)")[0])
        self.assertFalse(self.lua.eval("Registry.osMember(record,'person-33')"))
        self.lua.execute("saveOK=true;assert(Registry.setOSAccess(22,'VM-1',33,true));assert(Registry.save())")
        self.lua.execute((ROOT / 'fivem/server/modules/vending_registry.lua').read_text(encoding='utf-8'))
        self.assertTrue(self.lua.eval("MetaComic.VendingRegistry.osMember(MetaComic.VendingRegistry.get('VM-1'),'person-33')"))

    def test_payment_diversion_alone_cannot_read_map_logs_or_receive_controller_telemetry(self):
        self.lua.execute("record.routing={id='hacker'};record.tampered=true")
        self.assertEqual(self.lua.eval('Registry.controller(record)'), 'owner')
        self.assertFalse(self.lua.eval('Registry.hasOSAccess(22)'))
        self.assertFalse(self.lua.eval('MetaComic.RpcHandlers.getVendingMachines(22).ok'))
        self.assertFalse(self.lua.eval('MetaComic.RpcHandlers.getVendingRecords(22).ok'))

    def test_existing_takeover_migration_preserves_existing_records_only_for_business(self):
        self.issue()
        self.lua.execute("record.systemController='hacker';Registry.ensureOS(record);Registry.sensor('VM-1','New deployment OS event',22)")
        self.assertEqual(self.lua.eval('Registry.viewFor(record,11,true).history[1].event'), 'Original private business history')
        self.assertEqual(self.lua.eval('#Registry.viewFor(record,22,true).history'), 1)
        self.assertEqual(self.lua.eval('Registry.viewFor(record,22,true).history[1].event'), 'New deployment OS event')
        self.assertEqual(self.lua.eval('#Registry.viewFor(record,22,true).sales'), 0)
        self.assertEqual(self.lua.eval('#Registry.viewFor(record,22,true).keyArchive.keys'), 0)

    def test_new_os_key_records_include_only_new_keys_and_working_key_is_still_required(self):
        self.issue(target=22)
        self.take_over()
        self.assertTrue(self.lua.execute("return Registry.setOSAccess(22,'VM-1',33,true)"))
        self.assertFalse(self.lua.execute("return Keys.issue(33,'VM-1',66,'full')")[0])
        self.assertTrue(self.lua.execute("return Keys.issue(22,'VM-1',33,'full')"))
        self.assertEqual(self.lua.eval('#Registry.viewFor(record,33,true).keyArchive.keys'), 1)
        self.assertEqual(self.lua.eval('Registry.viewFor(record,33,true).keyArchive.keys[1].issuedTo'), 'person-33')
        self.assertEqual(self.lua.eval('#Registry.viewFor(record,33,true).keyArchive.cylinders'), 1)
        self.assertIsNone(self.lua.eval('Registry.viewFor(record,33,true).keyArchive.cylinders[1].installedAt'))
        self.assertEqual(self.lua.eval('#Registry.viewFor(record,11,true).keyArchive.keys'), 2)

    def test_offline_delegate_revocation_uses_existing_identifier(self):
        self.take_over()
        self.assertTrue(self.lua.execute("return Registry.setOSAccess(22,'VM-1',33,true)"))
        self.lua.execute('function GetPlayerName() return nil end')
        self.assertTrue(self.lua.execute("return Registry.setOSAccess(22,'VM-1','person-33',false)"))
        self.assertFalse(self.lua.eval('Registry.hasOSAccess(33)'))

    def test_second_takeover_does_not_receive_previous_os_private_logs(self):
        self.take_over()
        self.lua.execute("Registry.update('VM-1',nil,'First OS private event');source=11;handlers['meta_comic:server:crimeStart'](1,'replaceboard');timer=60000;handlers['meta_comic:server:crimeFinish'](startData.token,true)")
        self.lua.execute("Registry.update('VM-1',Registry.osStartFields(record,'person-66'),'Second takeover')")
        self.assertEqual(self.lua.eval('#Registry.viewFor(record,66,true).history'), 0)
        self.assertEqual(self.lua.eval('record.osHistory[1].event'), 'Second takeover')
        self.assertEqual(self.lua.eval('record.osArchives[1].history[1].event'), 'First OS private event')

    def test_all_changed_lua_sources_parse(self):
        for path in ('server/main.lua', 'server/modules/police.lua', 'server/modules/vending_registry.lua',
                     'server/modules/vending_records.lua', 'server/modules/vending_machines.lua',
                     'server/modules/vending_keys.lua', 'server/modules/vending_security.lua',
                     'client/vending_machines.lua'):
            result = self.lua.eval('load')((ROOT / 'fivem' / path).read_text(encoding='utf-8'))
            self.assertFalse(isinstance(result, tuple), f'{path}: {result}')


if __name__ == '__main__':
    unittest.main()
