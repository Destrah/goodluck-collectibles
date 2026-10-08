"""Run the real product handler to verify stock withdrawals and failed payouts."""
import importlib.util
from pathlib import Path
import sys
import unittest
if len(sys.argv) > 1: sys.path.insert(0, sys.argv.pop(1))
ROOT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location('fixtures', ROOT/'scripts/test-vending-security.py')
fixtures = importlib.util.module_from_spec(spec); spec.loader.exec_module(fixtures)

class StockTests(unittest.TestCase):
    def setUp(self):
        fixtures.SecurityTests.setUp(self)
        self.lua.execute('''
            Config.Items={BoosterPack='boosterpack',BoosterBox='boosterbox'}
            handlers={};source=11;ready=true;machines={[1]=entry};stockTransfers={};given=0;saveCount=0
            MAX_PRICE=10000000;MAX_PRODUCTS=30
            entry.products={{set='set-a',kind='pack',price=100,stock=8}}
            function RegisterNetEvent(name,fn) handlers[name]=fn end
            function notify() end
            function openManage() end
            function broadcast() end
            function canControl(src) return src==11 end
            function cabinetAccess(src,entry,level) return MetaComic.VendingKeys and MetaComic.VendingKeys.access(src,entry,level) or not MetaComic.VendingKeys and canControl(src) end
            function near() return not farAway end
            function interactReach() return 2 end
            function kindOf(kind) return kind=='box' and 'box' or 'pack' end
            function getSet(id) return {id=id} end
            function findProduct(e) return e.products[1],1 end
            function whole(value,min,max) local n=tonumber(value);return n and n>=min and n<=max and math.floor(n) or nil end
            function saveProducts() saveCount=saveCount+1;return not saveFail end
            MetaComic.Inventory.canCarry=function() return not fullInventory end
            MetaComic.GiveSealed=function(src,kind,set,amount)
                assert(src==11 and kind=='pack' and set=='set-a')
                if payoutFail then return false,'inventory refused' end
                given=given+amount;return true
            end
        ''')
        script = (ROOT/'fivem/server/modules/vending_machines.lua').read_text(encoding='utf-8')
        accounting = 'function accounting(entry)' + script.split('local function accounting(entry)', 1)[1].split('local function clientProducts', 1)[0]
        self.lua.execute('Registry=MetaComic.VendingRegistry')
        self.lua.execute(accounting.replace('local function accountChange', 'function accountChange'))
        self.lua.execute('accounting(entry)')
        actual = script.split('local function withdrawStock', 1)[1].split('-- Owner actions:', 1)[0]
        self.lua.execute('local function withdrawStock' + actual)

    def action(self, action, fields):
        self.lua.execute("handlers['meta_comic:server:vendingProduct'](1,'"+action+"',{"+fields+"})")

    def test_lower_stock_returns_difference_once(self):
        self.action('stock', "set='set-a',kind='pack',stock=3")
        self.assertEqual(self.lua.eval('given'), 5)
        self.assertEqual(self.lua.eval('entry.products[1].stock'), 3)
        self.action('stock', "set='set-a',kind='pack',stock=3")
        self.assertEqual(self.lua.eval('given'), 5)

    def test_explicit_withdraw_and_remove_return_stock(self):
        self.action('withdraw', "set='set-a',kind='pack',amount=2")
        self.assertEqual(self.lua.eval('given'), 2)
        self.action('remove', "set='set-a',kind='pack'")
        self.assertEqual(self.lua.eval('given'), 8)
        self.assertEqual(self.lua.eval('#entry.products'), 0)

    def test_full_inventory_failed_payout_and_failed_save_preserve_stock(self):
        for flag in ['fullInventory', 'payoutFail', 'saveFail']:
            self.lua.execute(flag+'=true')
            self.action('withdraw', "set='set-a',kind='pack',amount=2")
            self.assertEqual(self.lua.eval('entry.products[1].stock'), 8)
            self.assertEqual(self.lua.eval('given'), 0)
            self.lua.execute(flag+'=false')

    def test_permissions_and_invalid_counts(self):
        self.lua.execute('source=22')
        self.action('withdraw', "set='set-a',kind='pack',amount=2")
        self.lua.execute('source=11')
        self.action('stock', "set='set-a',kind='pack',stock=100")
        self.action('withdraw', "set='set-a',kind='pack',amount=100")
        self.assertEqual(self.lua.eval('given'), 0)
        self.assertEqual(self.lua.eval('entry.products[1].stock'), 8)

    def test_purchase_and_withdrawal_cannot_overlap_during_save(self):
        self.lua.execute('''
            shop={};MAX_CASH=0;cfg={SlotPacks={Enabled=false}};Registry=MetaComic.VendingRegistry
            function paymentMethods() return {cash=true,card=true} end
            function kindLabel() return 'pack' end
            MetaComic.Money.remove=function() return true end
            MetaComic.GiveSealed=function(_,_,_,amount) given=given+amount;return true,{name='Test'} end
            function saveEntry() coroutine.yield() end
        ''')
        script=(ROOT/'fivem/server/modules/vending_machines.lua').read_text(encoding='utf-8')
        actual=script.split('local buying = {}',1)[1].split("AddEventHandler('playerDropped'",1)[0]
        self.lua.execute('local buying = {}'+actual)
        self.lua.execute("buyThread=coroutine.create(function() handlers['meta_comic:server:vendingBuy'](1,'set-a','pack','cash') end);assert(coroutine.resume(buyThread))")
        self.action('withdraw', "set='set-a',kind='pack',amount=2")
        self.assertEqual(self.lua.eval('given'), 1)
        self.lua.execute('assert(coroutine.resume(buyThread))')
        self.action('withdraw', "set='set-a',kind='pack',amount=2")
        self.assertEqual(self.lua.eval('given'), 3)
        self.assertEqual(self.lua.eval('entry.products[1].stock'), 5)

    def load_buy_handler(self):
        self.lua.execute('''
            shop={};MAX_CASH=0;cfg={SlotPacks={Enabled=false}};charged=0;refunded=0;cabinetOpen=false
            function paymentMethods() return {cash=true,card=true} end
            function kindLabel() return 'pack' end
            MetaComic.VendingCashbox={cabinetOpen=function() return cabinetOpen end}
            MetaComic.Money.remove=function(_,_,amount) charged=charged+amount;return true end
            MetaComic.Money.add=function(_,_,amount) refunded=refunded+amount;return true end
            MetaComic.GiveSealed=function(_,_,_,amount) given=given+amount;return true,{name='Test'} end
            function saveEntry() return true end
        ''')
        code=(ROOT/'fivem/server/modules/vending_machines.lua').read_text(encoding='utf-8')
        actual=code.split('local buying = {}',1)[1].split("AddEventHandler('playerDropped'",1)[0]
        self.lua.execute('local buying = {}'+actual)

    def test_open_machine_rejects_stale_buy_menu_and_closed_machine_sells(self):
        self.load_buy_handler()
        self.lua.execute("cabinetOpen=true;handlers['meta_comic:server:vendingBuy'](1,'set-a','pack','cash')")
        self.assertEqual(self.lua.eval('charged'), 0)
        self.assertEqual(self.lua.eval('given'), 0)
        self.assertEqual(self.lua.eval('entry.products[1].stock'), 8)
        self.lua.execute("cabinetOpen=false;handlers['meta_comic:server:vendingBuy'](1,'set-a','pack','cash')")
        self.assertEqual(self.lua.eval('charged'), 100)
        self.assertEqual(self.lua.eval('given'), 1)

    def test_opening_during_dispensing_refunds_and_restores_stock(self):
        self.load_buy_handler()
        self.lua.execute("cfg.SlotPacks.Enabled=true;function Wait() cabinetOpen=true end;handlers['meta_comic:server:vendingBuy'](1,'set-a','pack','cash')")
        self.assertEqual(self.lua.eval('charged'), 100)
        self.assertEqual(self.lua.eval('refunded'), 100)
        self.assertEqual(self.lua.eval('given'), 0)
        self.assertEqual(self.lua.eval('entry.products[1].stock'), 8)
        self.assertEqual(self.lua.eval('accounting(entry).cash'), 0)

    def test_open_machine_cannot_open_buy_menu(self):
        self.load_buy_handler()
        self.lua.execute('function clientProducts() return {} end;menus=0;function TriggerLatentClientEvent() menus=menus+1 end')
        code=(ROOT/'fivem/server/modules/vending_machines.lua').read_text(encoding='utf-8')
        actual=code.split("RegisterNetEvent('meta_comic:server:vendingOpen'",1)[1].split('-- Manage',1)[0]
        self.lua.execute("RegisterNetEvent('meta_comic:server:vendingOpen'"+actual)
        self.lua.execute("cabinetOpen=true;handlers['meta_comic:server:vendingOpen'](1,'buy')")
        self.assertEqual(self.lua.eval('menus'), 0)
        self.lua.execute("cabinetOpen=false;handlers['meta_comic:server:vendingOpen'](1,'buy')")
        self.assertEqual(self.lua.eval('menus'), 1)

if __name__ == '__main__': unittest.main()
