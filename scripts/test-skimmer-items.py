"""Removed skimmers retain data, transfer it once, and preserve it on failed delivery."""
from pathlib import Path
import importlib.util
import sys
import unittest
if len(sys.argv) > 1: sys.path.insert(0, sys.argv.pop(1))
ROOT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location('fixtures', ROOT/'scripts/test-vending-security.py')
fixtures = importlib.util.module_from_spec(spec)
spec.loader.exec_module(fixtures)


class SkimmerItemTests(unittest.TestCase):
    def setUp(self):
        fixtures.SecurityTests.setUp(self)
        self.lua.execute('''
            handlers={};bags={[22]={[1]={slot=1,name='card_skimmer',count=1,metadata={}}}};nextSlot=1;failAdd={}
            function RegisterNetEvent(name,fn) handlers[name]=fn end
            function findItem(src,name)
                for slot,item in pairs(bags[src] or {}) do if item.name==name then return item end end
            end
            function countItems(src,name)
                local count=0;for _,item in pairs(bags[src] or {}) do if item.name==name then count=count+item.count end end;return count
            end
            MetaComic.Inventory.getSlot=function(src,slot) return (bags[src] or {})[slot] end
            MetaComic.Inventory.add=function(src,name,count,metadata)
                if failAdd[name] then return false end
                nextSlot=nextSlot+1;bags[src]=bags[src] or {}
                bags[src][nextSlot]={slot=nextSlot,name=name,count=count,metadata=MetaComic.CopyTable(metadata or {})}
                return true
            end
            MetaComic.Inventory.remove=function(src,name,count,metadata,requiredSlot)
                for slot,item in pairs(bags[src] or {}) do
                    if item.name==name and item.count>=count and (not requiredSlot or requiredSlot==slot)
                        and (not metadata or not metadata.dataId or metadata.dataId==item.metadata.dataId) then
                        item.count=item.count-count;if item.count==0 then bags[src][slot]=nil end;return true
                    end
                end
                return false
            end
        ''')
        self.lua.execute((ROOT/'fivem/server/modules/vending_security.lua').read_text(encoding='utf-8'))
        self.lua.execute('''
            Security=MetaComic.VendingSecurity;assert(Security.install(22,entry))
            Security.cardSale(entry,33,500);Security.cardSale(entry,33,500)
        ''')

    def assert_loaded(self, actor):
        self.assertEqual(self.lua.eval(f"findItem({actor},'card_skimmer').metadata.cards"), 2)
        self.assertEqual(self.lua.eval(f"findItem({actor},'card_skimmer').metadata.total"), 1000)
        self.assertEqual(self.lua.eval(f"findItem({actor},'card_skimmer').metadata.skimmed"), 150)
        self.assertEqual(self.lua.eval(f"findItem({actor},'card_skimmer').metadata.serial"), 'VM-1')

    def read(self, actor):
        self.lua.execute(f"source={actor};handlers['meta_comic:server:useSkimmerItem']('skimmer',findItem({actor},'card_skimmer').slot)")

    def test_installer_removal_stores_data_and_use_returns_card_data_once(self):
        self.assertTrue(self.lua.eval('Security.remove(22,entry)'))
        self.assert_loaded(22)
        self.read(22)
        self.assertEqual(self.lua.eval("findItem(22,'skimmer_card_data').metadata.skimmed"), 150)
        self.assertEqual(self.lua.eval("countItems(22,'card_skimmer')"), 1)
        self.read(22)
        self.assertEqual(self.lua.eval("countItems(22,'skimmer_card_data')"), 1)

    def test_inspection_removal_also_preserves_data_and_can_be_read(self):
        self.assertTrue(self.lua.eval('Security.inspect(11,entry)'))
        self.assertIsNone(self.lua.eval('record.skimmer'))
        self.assert_loaded(11)
        self.read(11)
        self.assertEqual(self.lua.eval("findItem(11,'skimmer_card_data').metadata.cards"), 2)
        self.assertEqual(self.lua.eval("findItem(11,'skimmer_card_data').metadata.skimmed"), 150)

    def test_full_inventory_keeps_inspected_skimmer_installed_with_its_data(self):
        self.lua.execute("failAdd.card_skimmer=true")
        self.assertFalse(self.lua.eval('Security.inspect(11,entry)'))
        self.assertEqual(self.lua.eval('record.skimmer.cards'), 2)
        self.assertEqual(self.lua.eval('record.skimmer.skimmed'), 150)

    def test_failed_inspection_save_returns_no_item_and_preserves_data(self):
        self.lua.execute('saveOK=false')
        self.assertFalse(self.lua.eval('Security.inspect(11,entry)'))
        self.assertEqual(self.lua.eval('record.skimmer.skimmed'), 150)
        self.assertEqual(self.lua.eval("countItems(11,'card_skimmer')"), 0)

    def test_failed_card_data_delivery_restores_loaded_skimmer(self):
        self.assertTrue(self.lua.eval('Security.remove(22,entry)'))
        self.lua.execute('failAdd.skimmer_card_data=true')
        self.read(22)
        self.assert_loaded(22)
        self.assertEqual(self.lua.eval("countItems(22,'skimmer_card_data')"), 0)


if __name__ == '__main__': unittest.main()
