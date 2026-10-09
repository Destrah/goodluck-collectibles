"""Verify the configured theft duration and prerequisites at start and completion."""
from pathlib import Path
import sys
import unittest
import importlib.util

if len(sys.argv) > 1:
    sys.path.insert(0, sys.argv.pop(1))
# Import the existing isolated FiveM/registry fixtures without duplicating their stubs.
ROOT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location('security_fixtures', ROOT/'scripts/test-vending-security.py')
fixtures = importlib.util.module_from_spec(spec)
spec.loader.exec_module(fixtures)


class CrimeTests(unittest.TestCase):
    def setUp(self):
        fixtures.SecurityTests.setUp(self)
        self.lua.execute('vec3=vector3')
        self.lua.execute((ROOT/'fivem/config.lua').read_text(encoding='utf-8'))
        self.lua.execute('''
          handlers={};timer=0;source=22;pickups=0
          entry.openedBy={id='hacker',at=now}
          function GetGameTimer() return timer end
          function RegisterNetEvent(name,fn) handlers[name]=fn end
          function AddEventHandler() end
          doorOpen=false
          function TriggerEvent(name,_,_,reason,action) if name=='meta_comic:server:vendingDoorSuccess' and reason=='crime' and action=='breakin' then doorOpen=true end end
          MetaComic.VendingCashbox={cabinetOpen=function() return doorOpen end,allows=function() return true end}
          function TriggerClientEvent(name,_,data) if name=='meta_comic:client:crimeStart' then startData=data elseif name=='meta_comic:client:lootInspect' then inspectData=data end end
          MetaComic.Inventory.count=function() return 100 end
          MetaComic.Police.count=function() return 0 end
          MetaComic.Vending.canManage=function() return false end
          MetaComic.Vending.sendAccessAll=function() end
          MetaComic.Vending.get=function() return entry end
          MetaComic.Vending.near=function() return true end
          MetaComic.Vending.reach=function() return 2 end
          MetaComic.Vending.pickUp=function() pickups=pickups+1;return true end
        ''')
        self.lua.execute((ROOT/'fivem/server/modules/vending_crime.lua').read_text(encoding='utf-8'))

    def test_missing_loot_module_never_falls_back_to_immediate_cash(self):
        self.lua.execute("entry.cash=500;entry.products={};handlers['meta_comic:server:crimeStart'](1,'breakin')")
        self.assertIsNone(self.lua.eval('startData'))
        self.assertEqual(self.lua.eval('entry.cash'), 500)
        self.assertEqual(self.lua.eval('paid'), 0)
        self.lua.execute("Config.VendingMachines.Crime.BreakIn.Loot=nil;handlers['meta_comic:server:crimeStart'](1,'breakin')")
        self.assertIsNone(self.lua.eval('startData'))
        self.assertEqual(self.lua.eval('paid'), 0)

    def test_missing_loot_module_at_completion_preserves_contents(self):
        self.lua.execute("""
            entry.cash=500;entry.products={}
            MetaComic.VendingLoot={busy=function() return false end,isOpen=function() return false end}
            handlers['meta_comic:server:crimeStart'](1,'breakin')
            MetaComic.VendingLoot=nil;timer=45000
            handlers['meta_comic:server:crimeFinish'](startData.token,true)
        """)
        self.assertEqual(self.lua.eval('entry.cash'), 500)
        self.assertEqual(self.lua.eval('paid'), 0)

    def test_successful_breakin_opens_inspection_without_paying_cash(self):
        self.lua.execute("entry.cash=300;entry.products={{set='test',kind='pack',stock=3}};MetaComic.Vending.save=function() return true end")
        self.lua.execute((ROOT/'fivem/server/modules/vending_loot.lua').read_text(encoding='utf-8'))
        self.lua.execute("handlers['meta_comic:server:crimeStart'](1,'breakin');timer=45000;handlers['meta_comic:server:crimeFinish'](startData.token,true)")
        self.assertEqual(self.lua.eval('inspectData.cash'), 'low')
        self.assertEqual(self.lua.eval('inspectData.stock'), 'low')
        self.assertEqual(self.lua.eval('inspectData.cashMs'), 12000)
        self.assertEqual(self.lua.eval('inspectData.stockMs'), 15000)
        self.assertEqual(self.lua.eval('entry.cash'), 300)
        self.assertEqual(self.lua.eval('entry.products[1].stock'), 3)
        self.assertEqual(self.lua.eval('paid'), 0)
        self.assertTrue(self.lua.eval('MetaComic.VendingLoot.isOpen(entry)'))

    def test_immediate_cash_requires_explicit_disabled_loot(self):
        self.lua.execute("""
            entry.cash=500;entry.products={};MetaComic.Vending.save=function() return true end;Config.VendingMachines.Crime.BreakIn.Loot.Enabled=false
            handlers['meta_comic:server:crimeStart'](1,'breakin');timer=45000
            handlers['meta_comic:server:crimeFinish'](startData.token,true)
        """)
        self.assertEqual(self.lua.eval('paid'), 500)
        self.assertEqual(self.lua.eval('entry.cash'), 0)

    def start(self):
        # Exercise the optional GPS/open-cabinet prerequisites independently of the user's current defaults.
        self.lua.execute('Config.VendingMachines.Crime.Steal.Duration=180000')
        self.lua.execute('''
            Config.VendingMachines.Crime.Steal.NeedsGPSDisabled=true
            record.unlockedUntil=record.unlockedUntil or 1600
            MetaComic.VendingLoot=MetaComic.VendingLoot or {busy=function() return false end,
                isOpen=function() return record.unlockedUntil>now end}
        ''')
        self.lua.execute("handlers['meta_comic:server:crimeStart'](1,'steal')")

    def test_loose_machine_theft_needs_no_drill_or_open_cabinet(self):
        self.lua.execute("record.unbolted=true;MetaComic.Inventory.count=function() return 0 end;handlers['meta_comic:server:crimeStart'](1,'takemachine')")
        self.assertEqual(self.lua.eval('startData.duration'), 5000)
        self.lua.execute("timer=5000;handlers['meta_comic:server:crimeFinish'](startData.token,true)")
        self.assertEqual(self.lua.eval('pickups'), 1)

    def test_loose_theft_rechecks_bolts_and_rejects_bolted_start(self):
        self.lua.execute("handlers['meta_comic:server:crimeStart'](1,'takemachine')")
        self.assertIsNone(self.lua.eval('startData'))
        self.lua.execute("record.unbolted=true;handlers['meta_comic:server:crimeStart'](1,'takemachine');record.unbolted=nil;timer=5000;handlers['meta_comic:server:crimeFinish'](startData.token,true)")
        self.assertEqual(self.lua.eval('pickups'), 0)

    def test_only_installer_or_authorized_staff_can_bolt_after_full_duration(self):
        self.lua.execute("record.unbolted=true;record.installedById='owner';handlers['meta_comic:server:crimeStart'](1,'bolt')")
        self.assertIsNone(self.lua.eval('startData'))
        self.lua.execute("source=11;handlers['meta_comic:server:crimeStart'](1,'bolt');handlers['meta_comic:server:crimeFinish'](startData.token,true)")
        self.assertTrue(self.lua.eval('record.unbolted'))
        self.lua.execute("handlers['meta_comic:server:crimeStart'](1,'bolt');timer=10000;handlers['meta_comic:server:crimeFinish'](startData.token,true)")
        self.assertIsNone(self.lua.eval('record.unbolted'))

    def test_bolt_save_failure_leaves_machine_loose(self):
        self.lua.execute("record.unbolted=true;record.installedById='hacker';handlers['meta_comic:server:crimeStart'](1,'bolt');saveOK=false;timer=10000;handlers['meta_comic:server:crimeFinish'](startData.token,true)")
        self.assertTrue(self.lua.eval('record.unbolted'))

    def test_full_hack_is_hardest_and_preserves_owner(self):
        self.lua.execute("MetaComic.Vending.sendAccessAll=function() end;handlers['meta_comic:server:crimeStart'](1,'fullhack')")
        self.assertEqual(self.lua.eval('startData.duration'), 300000)
        self.assertEqual(self.lua.eval('#startData.minigame'), 6)
        self.lua.execute("timer=300000;handlers['meta_comic:server:crimeFinish'](startData.token,true)")
        self.assertEqual(self.lua.eval('record.owner'), 'owner')
        self.assertEqual(self.lua.eval('MetaComic.VendingRegistry.systemController(record)'), 'hacker')
        self.assertEqual(self.lua.eval('MetaComic.VendingRegistry.routing(record).id'), 'owner')
        self.assertFalse(self.lua.eval('record.gpsDisabled == true'))
        self.lua.execute("MetaComic.VendingRegistry.resetRouting('VM-1')")
        self.assertEqual(self.lua.eval('MetaComic.VendingRegistry.systemController(record)'), 'hacker')
        self.assertEqual(self.lua.eval('MetaComic.VendingRegistry.controller(record)'), 'hacker')

    def test_payment_hacker_can_upgrade_to_full_hack(self):
        self.lua.execute("record.tampered=true;record.routing={id='hacker'};handlers['meta_comic:server:crimeStart'](1,'fullhack')")
        self.assertEqual(self.lua.eval('startData.action'), 'fullhack')

    def test_full_hack_does_not_expire_without_board_replacement(self):
        self.lua.execute("record.systemController='hacker';record.systemUntil=1001")
        self.assertEqual(self.lua.eval('MetaComic.VendingRegistry.controller(record)'), 'hacker')
        self.lua.execute('now=1002')
        self.assertEqual(self.lua.eval('MetaComic.VendingRegistry.controller(record)'), 'hacker')

    def test_failed_takeover_save_keeps_original_control_and_tools(self):
        self.lua.execute("handlers['meta_comic:server:crimeStart'](1,'fullhack');saveOK=false;timer=300000;handlers['meta_comic:server:crimeFinish'](startData.token,true)")
        self.assertIsNone(self.lua.eval('record.systemController'))
        self.assertIsNone(self.lua.eval('record.routing'))
        self.assertEqual(self.lua.eval('removed'), 0)

    def test_management_gps_switch_requires_owner_manager_or_full_takeover(self):
        script = (ROOT/'fivem/server/modules/vending_machines.lua').read_text(encoding='utf-8')
        handler = script.split('local function ownerAction', 1)[1].split('-- Map of every machine', 1)[0]
        self.lua.execute('''
            ready=true;machines={[1]=entry};Registry=MetaComic.VendingRegistry;stockTransfers={}
            function near() return true end
            function interactReach() return 2 end
            function recordOf() return record end
            function canManage() return false end
            function playerName() return 'Player' end
            function playerId(src) return Registry.identifierOf(src) end
            function canControl(src) return record.owner==playerId(src) or Registry.controller(record)==playerId(src) end
            function cabinetAccess(src,entry,level) return MetaComic.VendingKeys and MetaComic.VendingKeys.access(src,entry,level) or not MetaComic.VendingKeys and canControl(src,entry) end
            function notify() end
            function openManage() end
        ''')
        policy = 'local function canOperateSystem' + script.split('local function canOperateSystem', 1)[1].split('local function canRestock', 1)[0]
        self.lua.execute(policy + '\ncanOperateSystemTest=canOperateSystem')
        self.lua.execute('canOperateSystem=canOperateSystemTest;MetaComic.Vending.canOperateSystem=canOperateSystemTest')
        self.lua.execute('local function ownerAction' + handler)
        self.lua.execute("record.tampered=true;record.routing={id='hacker'};handlers['meta_comic:server:vendingOwner'](1,'gps')")
        self.assertFalse(self.lua.eval('record.gpsDisabled == true'))
        self.lua.execute("record.systemController='hacker';handlers['meta_comic:server:vendingOwner'](1,'gps')")
        self.assertTrue(self.lua.eval('record.gpsDisabled'))
        self.lua.execute("source=11;handlers['meta_comic:server:vendingOwner'](1,'gps')")
        self.assertTrue(self.lua.eval('record.gpsDisabled'))  # compromised owner cannot switch GPS before board repair

    def test_full_controller_can_route_to_another_player_without_granting_control(self):
        self.test_management_gps_switch_requires_owner_manager_or_full_takeover()
        self.lua.execute("source=22;function sendAccessAll() end;function GetPlayerPing() return 100 end;record.systemController='hacker';handlers['meta_comic:server:vendingOwner'](1,'payments',{mode='player',value='33'})")
        self.assertEqual(self.lua.eval('record.routing.id'), 'intruder')
        self.assertEqual(self.lua.eval('MetaComic.VendingRegistry.controller(record)'), 'hacker')
        self.lua.execute("source=11;handlers['meta_comic:server:vendingOwner'](1,'payments',{mode='player',value='11'})")
        self.assertEqual(self.lua.eval('record.routing.id'), 'intruder')
        self.lua.execute("source=22;handlers['meta_comic:server:vendingOwner'](1,'payments',{mode='routing',value='invalid'})")
        self.assertEqual(self.lua.eval('record.routing.id'), 'intruder')
        self.lua.execute("MetaComic.VendingRegistry.register('offline-payee','Payee');local person=MetaComic.VendingRegistry.person('offline-payee');handlers['meta_comic:server:vendingOwner'](1,'payments',{mode='routing',value=person.routing})")
        self.assertEqual(self.lua.eval('record.routing.id'), 'offline-payee')
        self.assertEqual(self.lua.eval('MetaComic.VendingRegistry.controller(record)'), 'hacker')

    def test_control_board_requires_owner_and_full_duration(self):
        self.lua.execute("record.systemController='hacker';source=22;handlers['meta_comic:server:crimeStart'](1,'replaceboard')")
        self.assertIsNone(self.lua.eval('startData'))
        self.lua.execute("source=11;handlers['meta_comic:server:crimeStart'](1,'replaceboard')")
        self.assertEqual(self.lua.eval('startData.duration'), 60000)
        self.lua.execute("timer=60000;handlers['meta_comic:server:crimeFinish'](startData.token,true)")
        self.assertIsNone(self.lua.eval('record.systemController'))
        self.assertEqual(self.lua.eval('MetaComic.VendingRegistry.controller(record)'), 'owner')
        self.assertEqual(self.lua.eval('removed'), 1)

    def test_failed_board_save_refunds_board_and_preserves_takeover(self):
        self.lua.execute("record.systemController='hacker';source=11;handlers['meta_comic:server:crimeStart'](1,'replaceboard');timer=60000;saveOK=false;handlers['meta_comic:server:crimeFinish'](startData.token,true)")
        self.assertEqual(self.lua.eval('record.systemController'), 'hacker')
        self.assertEqual(self.lua.eval('removed'), 1)
        self.assertEqual(self.lua.eval('returned'), 1)

    def test_evidence_only_follows_validated_attempt_and_failure(self):
        self.lua.execute('prints=0;injuries=0;MetaComic.CrimeEvidence={start=function() prints=prints+1 end,failure=function() injuries=injuries+1 end}')
        self.start()  # active GPS prevents theft and evidence
        self.assertEqual(self.lua.eval('prints'), 0)
        self.lua.execute('record.gpsDisabled=true')
        self.start()
        self.assertEqual(self.lua.eval('prints'), 1)
        self.lua.execute("handlers['meta_comic:server:crimeFinish']('invalid',false)")
        self.assertEqual(self.lua.eval('injuries'), 0)
        # Invalid finish clears its pending attempt; start another legitimate attempt.
        self.start()
        self.lua.execute("handlers['meta_comic:server:crimeFinish'](startData.token,false)")
        self.assertEqual(self.lua.eval('injuries'), 1)

    def test_theft_needs_disabled_gps_before_start(self):
        self.start()
        self.assertIsNone(self.lua.eval('startData'))
        self.lua.execute('record.gpsDisabled=true')
        self.start()
        self.assertEqual(self.lua.eval('startData.duration'), 180000)
        self.assertEqual(self.lua.eval('#startData.minigame'), 3)

    def test_early_completion_does_not_grant_machine(self):
        self.lua.execute('record.gpsDisabled=true')
        self.start()
        self.lua.execute("timer=1000;handlers['meta_comic:server:crimeFinish'](startData.token,true)")
        self.assertEqual(self.lua.eval('pickups'), 0)

    def test_gps_is_rechecked_at_completion(self):
        self.lua.execute('record.gpsDisabled=true')
        self.start()
        self.lua.execute("record.gpsDisabled=false;timer=180000;handlers['meta_comic:server:crimeFinish'](startData.token,true)")
        self.assertEqual(self.lua.eval('pickups'), 0)

    def test_breakin_window_is_rechecked_at_completion(self):
        self.lua.execute('record.gpsDisabled=true')
        self.start()
        self.lua.execute("now=1601;timer=180000;handlers['meta_comic:server:crimeFinish'](startData.token,true)")
        self.assertEqual(self.lua.eval('pickups'), 0)

    def test_full_duration_and_valid_prerequisites_allow_theft(self):
        self.lua.execute('record.gpsDisabled=true')
        self.start()
        self.lua.execute("timer=180000;handlers['meta_comic:server:crimeFinish'](startData.token,true)")
        self.assertEqual(self.lua.eval('pickups'), 1)


if __name__ == '__main__':
    unittest.main(defaultTest='CrimeTests')
