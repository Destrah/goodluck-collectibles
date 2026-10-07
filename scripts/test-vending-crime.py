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
          function TriggerClientEvent(name,_,data) if name=='meta_comic:client:crimeStart' then startData=data end end
          MetaComic.Inventory.count=function() return 100 end
          MetaComic.Police.count=function() return 0 end
          MetaComic.Vending.get=function() return entry end
          MetaComic.Vending.near=function() return true end
          MetaComic.Vending.reach=function() return 2 end
          MetaComic.Vending.pickUp=function() pickups=pickups+1;return true end
        ''')
        self.lua.execute((ROOT/'fivem/server/modules/vending_crime.lua').read_text(encoding='utf-8'))

    def start(self):
        self.lua.execute("handlers['meta_comic:server:crimeStart'](1,'steal')")

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
