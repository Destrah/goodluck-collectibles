"""Exercise the real third-eye door predicates, including a stale break-in timer."""
from pathlib import Path
import re
import sys
import unittest
if len(sys.argv) > 1: sys.path.insert(0, sys.argv.pop(1))
from lupa.lua54 import LuaRuntime
ROOT = Path(__file__).resolve().parents[1]


class AvailabilityTests(unittest.TestCase):
    def setUp(self):
        self.lua = LuaRuntime()
        self.lua.execute('''
            doors={};lids={};racks={};breaking=false
            machine={id=1,unlockedUntil=999999}
            MetaComic={VendingMachineOf=function() return machine end}
        ''')
        text = (ROOT/'fivem/client/vending_door.lua').read_text(encoding='utf-8')
        self.lua.execute(next(line for line in text.splitlines() if line.startswith('MetaComic.VendingCabinetOpen =')))
        for name, function in [('cashbox','CashReady'), ('rack','RackReady')]:
            section = text.split(f"name = 'meta_comic_vending_{name}'", 1)[1]
            code = re.search(r'canInteract = (function\(entity\).*?\n\s*end),\n\s*onSelect', section, re.S).group(1)
            self.lua.execute(function+'='+code)
        keys = (ROOT/'fivem/client/vending_keys.lua').read_text(encoding='utf-8')
        function = re.search(r'MetaComic.VendingHasKeyAccess = (function\(id, full\).*?\nend)', keys, re.S).group(1)
        self.lua.execute('keySessions={};clock=100;function GetGameTimer() return clock end;MetaComic.VendingMachineById=function() return machine end')
        self.lua.execute('MetaComic.VendingHasKeyAccess='+function)

    def test_active_unlock_timer_does_not_show_locks_behind_closed_door(self):
        self.assertFalse(self.lua.eval('CashReady(1)'))
        self.assertFalse(self.lua.eval('RackReady(1)'))
        self.lua.execute('doors[1]={target=0,angle=90}')
        self.assertFalse(self.lua.eval('CashReady(1)'))
        self.assertFalse(self.lua.eval('RackReady(1)'))

    def test_open_door_shows_only_closed_accessible_lids(self):
        self.lua.execute('doors[1]={target=105};machine.unlockedUntil=0')
        self.assertTrue(self.lua.eval('CashReady(1)'))
        self.assertTrue(self.lua.eval('RackReady(1)'))
        self.lua.execute('lids[1]=0;racks[1]=true')
        self.assertFalse(self.lua.eval('CashReady(1)'))
        self.assertFalse(self.lua.eval('RackReady(1)'))

    def test_seals_padlocks_and_current_action_hide_locks(self):
        for condition in ('machine.securitySeal={}', 'machine.padlock=true', 'breaking=true'):
            self.lua.execute('doors[1]={target=105};machine.securitySeal=nil;machine.padlock=false;breaking=false;'+condition)
            self.assertFalse(self.lua.eval('CashReady(1)'))
            self.assertFalse(self.lua.eval('RackReady(1)'))

    def test_key_permissions_expire_and_follow_current_lock_revision(self):
        self.lua.execute("machine.serial='VM-1';machine.lockRevision=2;keySessions[1]={serial='VM-1',revision=2,expires=200,full=false}")
        self.assertTrue(self.lua.eval('MetaComic.VendingHasKeyAccess(1)'))
        self.assertFalse(self.lua.eval('MetaComic.VendingHasKeyAccess(1,true)'))
        self.lua.execute('machine.lockRevision=3')
        self.assertFalse(self.lua.eval('MetaComic.VendingHasKeyAccess(1)'))
        self.lua.execute('machine.lockRevision=2;clock=200')
        self.assertFalse(self.lua.eval('MetaComic.VendingHasKeyAccess(1)'))


if __name__ == '__main__': unittest.main()
