"""Exercise GPS movement and skimmer payment conservation against the real modules."""
from pathlib import Path
import sys
import unittest

if len(sys.argv) > 1:
    sys.path.insert(0, sys.argv.pop(1))
from lupa.lua54 import LuaRuntime

ROOT = Path(__file__).resolve().parents[1]


class SecurityTests(unittest.TestCase):
    def setUp(self):
        self.lua = LuaRuntime(unpack_returned_tuples=True)
        self.lua.execute('''
          now=1000;os.time=function() return now end
          local mt={__sub=function(a,b) return vector3(a.x-b.x,a.y-b.y,a.z-b.z) end,
            __len=function(a) return math.sqrt(a.x*a.x+a.y*a.y+a.z*a.z) end}
          function vector3(x,y,z) return setmetatable({x=x,y=y,z=z},mt) end
          Config={VendingMachines={GPS={Enabled=true},Skimmer={Enabled=true,Mode='record',Percent=15}}}
          record={serial='VM-1',status='placed',owner='owner',gpsOrigin={x=0,y=0,z=0}}
          records={serials={['VM-1']=record}}
          entry={serial='VM-1',id=1,x=0,y=0,z=0}
          threads={};messages={};alarms={};saveOK=true;removed=0;returned=0;paid=0
          MetaComic={Framework={getIdentifier=function(src) return src==11 and 'owner' or src==22 and 'hacker' or 'intruder' end,
            notify=function(src,message) messages[#messages+1]={src=src,message=message} end},
            Settings={get=function() return records end,set=function() return saveOK end},
            Vending={bySerial=function() return isItem and nil or entry end,canControl=function(src) return src==11 end,broadcast=function() end},
            Police={alert=function(_,data) alarms[#alarms+1]=data end},Inventory={},Money={}}
          function MetaComic.CopyTable(v) if type(v)~='table' then return v end;local t={};for k,x in pairs(v) do t[k]=MetaComic.CopyTable(x) end;return t end
          MetaComic.Inventory.remove=function() removed=removed+1;return true end
          MetaComic.Inventory.add=function() returned=returned+1;return true end
          MetaComic.Money.add=function(_,_,amount) if payFail then return false end;paid=paid+amount;return true end
          function GetPlayerName() return 'Player' end
          function GetPlayers() return {'11','22'} end
          function CreateThread(fn) threads[#threads+1]=coroutine.create(fn) end
          function Wait() coroutine.yield() end
          function tick(time) now=time;local ok,err=coroutine.resume(threads[2]);assert(ok,err) end
          function GetPlayerPed(src) return src end
          function DoesEntityExist(id) return id==100 or id==11 or id==22 end
          function GetEntityCoords() return movingCoords or vector3(0,0,0) end
        ''')
        self.lua.execute((ROOT / 'fivem/server/modules/vending_registry.lua').read_text(encoding='utf-8'))
        self.lua.execute((ROOT / 'fivem/server/modules/vending_security.lua').read_text(encoding='utf-8'))
        self.lua.execute('Security=MetaComic.VendingSecurity')

    def install(self):
        self.assertTrue(self.lua.execute('return Security.install(22,entry)'))

    def test_record_cut_divert_conserve_payment(self):
        self.install()
        for mode, retained in [('record', 0), ('cut', 75), ('divert', 500)]:
            self.lua.execute(f"Config.VendingMachines.Skimmer.Mode='{mode}'")
            before = self.lua.eval('record.skimmer.balance')
            remaining = self.lua.execute('return Security.cardSale(entry,99,500)')
            self.assertEqual(remaining + self.lua.eval('record.skimmer.balance') - before, 500)
            self.assertEqual(500 - remaining, retained)
        self.assertEqual(self.lua.eval('#record.skimmer.transactions'), 3)

    def test_installer_collects_once_and_others_cannot_collect(self):
        self.install()
        self.lua.execute("Config.VendingMachines.Skimmer.Mode='cut';Security.cardSale(entry,99,500)")
        self.assertFalse(self.lua.execute('return Security.collect(11,entry)'))
        self.assertTrue(self.lua.execute('return Security.collect(22,entry)'))
        self.assertTrue(self.lua.execute('return Security.collect(22,entry)'))
        self.assertEqual(self.lua.eval('paid'), 75)

    def test_failed_save_does_not_remove_sale_revenue(self):
        self.install()
        self.lua.execute("Config.VendingMachines.Skimmer.Mode='divert';saveOK=false")
        self.assertEqual(self.lua.execute('return Security.cardSale(entry,99,500)'), 500)
        self.assertEqual(self.lua.eval('record.skimmer.balance'), 0)

    def test_failed_install_refunds_item_and_removal_is_authorized(self):
        self.lua.execute('saveOK=false')
        self.assertFalse(self.lua.execute('return Security.install(22,entry)'))
        self.assertIsNone(self.lua.eval('record.skimmer'))
        self.assertEqual(self.lua.eval('returned'), 1)
        self.lua.execute('saveOK=true')
        self.install()
        self.assertFalse(self.lua.execute('return Security.remove(33,entry)'))
        self.assertTrue(self.lua.execute('return Security.remove(11,entry)'))

    def test_gps_threshold_disabled_state_and_rearm_baseline(self):
        self.lua.execute('tick(1000);entry.x=1;tick(1001)')
        self.assertEqual(self.lua.eval('#alarms'), 0)
        self.lua.execute('entry.x=5;tick(1002)')
        self.assertEqual(self.lua.eval('#alarms'), 1)
        self.assertEqual(self.lua.eval('messages[1].src'), 11)
        self.assertTrue(self.lua.execute('return Security.gps(22,entry,false)'))
        self.lua.execute('tick(1100)')
        self.assertEqual(self.lua.eval('#alarms'), 1)
        self.assertFalse(self.lua.execute('return Security.gps(22,entry,true)'))
        self.assertTrue(self.lua.execute('return Security.gps(11,entry,true)'))
        self.assertEqual(self.lua.eval('record.gpsOrigin.x'), 5)
        self.lua.execute('tick(1200)')
        self.assertEqual(self.lua.eval('#alarms'), 1)

    def test_gps_follows_towed_entity_and_current_chip_controller(self):
        self.lua.execute("record.tampered=true;record.routing={id='hacker'};record.routingUntil=1100;Security.track('VM-1',100);movingCoords=vector3(8,0,0);tick(1000);tick(1001)")
        self.assertEqual(self.lua.eval('messages[1].src'), 22)
        self.lua.execute('tick(1200)')
        self.assertEqual(self.lua.eval('messages[2].src'), 11)

    def test_gps_follows_inventory_holder(self):
        self.lua.execute("MetaComic.Vending.bySerial=function() return nil end;record.status='stolen';record.holder={id='hacker'};movingCoords=vector3(8,0,0);tick(1000);tick(1001)")
        self.assertEqual(self.lua.eval('#alarms'), 1)
        self.assertEqual(self.lua.eval('messages[1].src'), 11)

    def test_changed_lua_files_compile(self):
        for name in ['fivem/config.lua','fivem/client/vending_machines.lua','fivem/client/vending_crime.lua',
                     'fivem/server/modules/vending_crime.lua','fivem/server/modules/vending_machines.lua']:
            result = self.lua.eval('load')((ROOT/name).read_text(encoding='utf-8'))
            self.assertFalse(isinstance(result, tuple), str(result))


if __name__ == '__main__':
    unittest.main()
