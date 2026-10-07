"""Exercise incremental loot, expiry, secure, cancellation and payout rollback."""
from pathlib import Path
import importlib.util
import sys
import unittest
if len(sys.argv) > 1: sys.path.insert(0, sys.argv.pop(1))
ROOT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location('fixtures', ROOT/'scripts/test-vending-security.py')
fixtures = importlib.util.module_from_spec(spec); spec.loader.exec_module(fixtures)

class LootTests(unittest.TestCase):
    def setUp(self):
        fixtures.SecurityTests.setUp(self)
        self.lua.execute('vec3=vector3')
        self.lua.execute((ROOT/'fivem/config.lua').read_text(encoding='utf-8'))
        self.lua.execute('''
            handlers={};events={};source=22;timer=0;packs=0;saves=0
            entry.cash=300;entry.products={{set='test',kind='pack',stock=3}}
            record.unlockedUntil=1600
            function RegisterNetEvent(name,fn) handlers[name]=fn end
            function AddEventHandler() end
            function GetCurrentResourceName() return 'test' end
            function GetGameTimer() return timer end
            function TriggerClientEvent(name,src,data) events[#events+1]={name=name,src=src,data=data} end
            MetaComic.Vending.get=function() return entry end
            MetaComic.Vending.near=function() return not farAway end
            MetaComic.Vending.reach=function() return 2 end
            MetaComic.Vending.save=function() saves=saves+1;return not debitFail end
            MetaComic.Vending.giveSealed=function(_,_,_,amount) if fullInventory then return false end;packs=packs+amount;return true end
            function advance(t) timer=t;local ok,err=coroutine.resume(threads[#threads]);assert(ok,err) end
        ''')
        self.lua.execute((ROOT/'fivem/server/modules/vending_loot.lua').read_text(encoding='utf-8'))

    def start(self, mode='both'):
        self.lua.execute(f"handlers['meta_comic:server:lootStart'](1,'{mode}');advance(0)")

    def test_completed_batches_only_and_cancel_retains_remainder(self):
        self.start()
        self.lua.execute('advance(3999)')
        self.assertEqual(self.lua.eval('paid'), 0)
        self.lua.execute('advance(4000)')
        self.assertEqual(self.lua.eval('paid'), 100)
        self.assertEqual(self.lua.eval('entry.cash'), 200)
        self.lua.execute("handlers['meta_comic:server:lootCancel']();advance(10000)")
        self.assertEqual(self.lua.eval('packs'), 0)
        self.assertEqual(self.lua.eval('entry.products[1].stock'), 3)
        self.assertTrue(self.lua.eval('MetaComic.VendingLoot.isOpen(entry)'))

    def test_stock_only_and_full_inventory_rollback(self):
        self.start('stock')
        self.lua.execute('fullInventory=true;advance(5000)')
        self.assertEqual(self.lua.eval('packs'), 0)
        self.assertEqual(self.lua.eval('entry.products[1].stock'), 3)
        self.assertEqual(self.lua.eval('paid'), 0)

    def test_cash_only_does_not_take_stock(self):
        self.start('cash')
        self.lua.execute('advance(4000);advance(8000);advance(12000)')
        self.assertEqual(self.lua.eval('paid'), 300)
        self.assertEqual(self.lua.eval('packs'), 0)

    def test_expiry_or_leaving_range_prevents_next_payout(self):
        self.start()
        self.lua.execute('now=1601;advance(4000)')
        self.assertEqual(self.lua.eval('paid'), 0)
        self.assertEqual(self.lua.eval('entry.cash'), 300)

    def test_securing_stops_loot_and_closes_cabinet(self):
        self.start()
        self.lua.execute('source=11;assert(MetaComic.VendingLoot.secure(source,entry));advance(10000)')
        self.assertEqual(self.lua.eval('paid'), 0)
        self.assertFalse(self.lua.eval('MetaComic.VendingLoot.isOpen(entry)'))

    def test_concurrent_looters_cannot_double_take(self):
        self.start('cash')
        before = self.lua.eval('#threads')
        self.lua.execute("source=33;handlers['meta_comic:server:lootStart'](1,'cash')")
        self.assertEqual(self.lua.eval('#threads'), before)
        self.lua.execute('advance(4000)')
        self.assertEqual(self.lua.eval('paid'), 100)

    def test_cancel_during_save_does_not_pay(self):
        self.lua.execute('MetaComic.Vending.save=function() saves=saves+1;if saves==1 then Wait(0) end;return true end')
        self.start('cash')
        self.lua.execute("advance(4000);handlers['meta_comic:server:lootCancel']();advance(4000)")
        self.assertEqual(self.lua.eval('paid'), 0)
        self.assertEqual(self.lua.eval('entry.cash'), 300)

    def test_failed_save_does_not_award_or_remove_cash(self):
        self.start('cash')
        self.lua.execute('debitFail=true;advance(4000)')
        self.assertEqual(self.lua.eval('paid'), 0)
        self.assertEqual(self.lua.eval('entry.cash'), 300)

    def test_visual_metadata_matches_current_stock_product(self):
        self.lua.execute("entry.products={{set='test',kind='box',stock=1},{set='test',kind='pack',stock=1}}")
        self.start('stock')
        self.assertEqual(self.lua.eval('events[#events].data.productKind'), 'box')
        self.lua.execute('advance(5000)')
        self.assertEqual(self.lua.eval('events[#events].data.productKind'), 'pack')
        self.assertEqual(self.lua.eval('packs'), 1)

    def test_inspection_uses_levels_and_quantity_based_time(self):
        self.lua.execute("handlers['meta_comic:server:lootInspect'](1)")
        self.assertEqual(self.lua.eval('events[1].data.cash'), 'low')
        self.assertEqual(self.lua.eval('events[1].data.stock'), 'low')
        self.assertEqual(self.lua.eval('events[1].data.cashMs'), 12000)
        self.assertEqual(self.lua.eval('events[1].data.stockMs'), 15000)

if __name__ == '__main__': unittest.main()
