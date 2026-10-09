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
            doorOpen=true;cashboxOpen=true
            MetaComic.VendingCashbox={
                cabinetOpen=function() return doorOpen and not record.securitySeal and (keyOpened or record.displacedOpen or (tonumber(record.unlockedUntil) or 0)>now) end,
                allows=function(_,mode) return doorOpen and (mode=='stock' or cashboxOpen) end,
            }
            function RegisterNetEvent(name,fn) handlers[name]=fn end
            function AddEventHandler() end
            function GetCurrentResourceName() return 'test' end
            function GetGameTimer() return timer end
            function TriggerClientEvent(name,src,data) events[#events+1]={name=name,src=src,data=data} end
            function TriggerLatentClientEvent(name,src,rate,data) TriggerClientEvent(name,src,data) end
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

    def test_closed_damaged_or_relocated_cabinet_rejects_inspect_and_loot(self):
        self.lua.execute("doorOpen=false;record.displacedOpen=true;handlers['meta_comic:server:lootInspect'](1);handlers['meta_comic:server:lootStart'](1,'both')")
        self.assertTrue(self.lua.eval('MetaComic.VendingLoot.isOpen(entry)'))
        self.assertFalse(self.lua.eval('MetaComic.VendingLoot.lootable(entry)'))
        self.assertEqual(self.lua.eval('#events'), 0)
        self.assertFalse(self.lua.eval('MetaComic.VendingLoot.busy(entry)'))

    def test_closing_door_during_cash_or_stock_batch_stops_payout(self):
        for mode in ('cash', 'stock'):
            self.setUp(); self.start(mode)
            self.lua.execute('doorOpen=false;advance(5000)')
            self.assertEqual(self.lua.eval('paid'), 0)
            self.assertEqual(self.lua.eval('packs'), 0)
            self.assertEqual(self.lua.eval('entry.cash'), 300)
            self.assertEqual(self.lua.eval('entry.products[1].stock'), 3)

    def test_door_closing_during_save_rolls_back_cash_and_stock(self):
        for mode in ('cash', 'stock'):
            self.setUp()
            self.lua.execute('MetaComic.Vending.save=function() doorOpen=false;return true end')
            self.start(mode); self.lua.execute('advance(5000)')
            self.assertEqual(self.lua.eval('paid'), 0)
            self.assertEqual(self.lua.eval('packs'), 0)
            self.assertEqual(self.lua.eval('entry.cash'), 300)
            self.assertEqual(self.lua.eval('entry.products[1].stock'), 3)

    def test_cashbox_closing_stops_cash_but_stock_still_allowed(self):
        self.start('cash'); self.lua.execute('cashboxOpen=false;advance(4000)')
        self.assertEqual(self.lua.eval('paid'), 0)
        self.lua.execute("handlers['meta_comic:server:lootStart'](1,'stock');advance(4000);advance(9000)")
        self.assertEqual(self.lua.eval('packs'), 1)

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

    def test_selected_box_uses_box_visual_and_leaves_other_stock(self):
        self.lua.execute("entry.products={{set='test',kind='pack',stock=3},{set='test',kind='box',stock=1}};handlers['meta_comic:server:lootStart'](1,'stock',{set='test',kind='box'});advance(0)")
        self.assertEqual(self.lua.eval('events[#events].data.productKind'), 'box')
        self.lua.execute('advance(5000)')
        self.assertEqual(self.lua.eval('entry.products[1].stock'), 3)
        self.assertEqual(self.lua.eval('entry.products[2].stock'), 0)
        self.assertEqual(self.lua.eval('packs'), 1)
        self.assertFalse(self.lua.eval('MetaComic.VendingLoot.busy(entry)'))

    def test_invalid_or_stale_selection_never_starts(self):
        for selection in ["'box'", "{}", "{set='missing',kind='pack'}", "{set='test',kind='invalid'}", "{set='test',kind='box'}"]:
            self.setUp()
            self.lua.execute("handlers['meta_comic:server:lootStart'](1,'stock'," + selection + ")")
            self.assertFalse(self.lua.eval('MetaComic.VendingLoot.busy(entry)'))
            self.assertEqual(self.lua.eval('#events'), 0)

    def test_selection_removed_mid_batch_does_not_switch_product(self):
        self.lua.execute("entry.products={{set='test',kind='pack',stock=3},{set='other',kind='box',stock=1}};handlers['meta_comic:server:lootStart'](1,'stock',{set='other',kind='box'});advance(0);entry.products[2].stock=0;advance(5000)")
        self.assertEqual(self.lua.eval('entry.products[1].stock'), 3)
        self.assertEqual(self.lua.eval('packs'), 0)

    def test_stock_selection_payload_names_sets_and_kind_without_exact_counts(self):
        self.lua.execute("MetaComic.Sets={get=function(id) return {name='Named set'} end};entry.products={{set='test',kind='box',stock=2}};handlers['meta_comic:server:lootInspect'](1)")
        self.assertEqual(self.lua.eval('events[1].data.products[1].setName'), 'Named set')
        self.assertEqual(self.lua.eval('events[1].data.products[1].kind'), 'box')
        self.assertIsNone(self.lua.eval('events[1].data.products[1].stock'))
        self.assertEqual(self.lua.eval('events[1].data.products[1].stockMs'), 10000)

    def test_client_stock_choice_sends_selected_set_and_box_kind(self):
        self.lua.execute('''
            menus={};exports={ox_lib={registerContext=function(_,data) menus[data.id]=data end,showContext=function(id) shown=id end}}
            function GetResourceState() return 'started' end
            function TriggerServerEvent(name,id,mode,selection) request={name=name,id=id,mode=mode,selection=selection} end
        ''')
        script = (ROOT / 'fivem/client/vending_crime.lua').read_text(encoding='utf-8')
        section = script.split("RegisterNetEvent('meta_comic:client:lootInspect'", 1)[1].split("RegisterNetEvent('meta_comic:client:lootStarted'", 1)[0]
        self.lua.execute("RegisterNetEvent('meta_comic:client:lootInspect'" + section)
        self.lua.execute("handlers['meta_comic:client:lootInspect']({id=1,cash='low',stock='low',cashMs=4000,stockMs=10000,products={{set='test',setName='Test set',kind='pack',level='low',stockMs=5000},{set='test',setName='Test set',kind='box',level='low',stockMs=5000}}});menus.meta_comic_vending_loot.options[3].onSelect()")
        self.assertIsNone(self.lua.eval('request'))  # choosing stock first opens product selection
        self.assertEqual(self.lua.eval('menus.meta_comic_vending_loot_stock.options[3].title'), 'Test set — Booster boxes')
        self.lua.execute('menus.meta_comic_vending_loot_stock.options[3].onSelect()')
        self.assertEqual(self.lua.eval('request.selection.kind'), 'box')
        self.assertEqual(self.lua.eval('request.selection.set'), 'test')
        self.assertEqual(self.lua.eval('request.mode'), 'stock')
        self.lua.execute('menus.meta_comic_vending_loot.options[4].onSelect();menus.meta_comic_vending_loot_stock.options[2].onSelect()')
        self.assertEqual(self.lua.eval('request.mode'), 'both')
        self.assertEqual(self.lua.eval('request.selection.kind'), 'pack')

if __name__ == '__main__': unittest.main()
