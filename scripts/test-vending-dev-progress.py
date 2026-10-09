"""Verify server-config dev caps and authoritative crime completion timing."""
from pathlib import Path
import importlib.util
import sys
import unittest

if len(sys.argv) > 1:
    sys.path.insert(0, sys.argv.pop(1))
ROOT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location('crime', ROOT / 'scripts/test-vending-crime.py')
crime = importlib.util.module_from_spec(spec)
spec.loader.exec_module(crime)


class DevProgressTests(unittest.TestCase):
    def setUp(self):
        crime.CrimeTests.setUp(self)
        self.lua.execute('''
            convars={}
            function GetConvarInt(name, default) return convars[name] or default end
        ''')
        self.lua.execute((ROOT / 'fivem/shared/utils.lua').read_text(encoding='utf-8'))

    def test_opt_in_cap_preserves_config_and_short_actions(self):
        self.assertEqual(self.lua.eval('MetaComic.VendingProgressDuration(300000)'), 300000)
        self.lua.execute("convars.metacomic_dev_testing=1")
        self.assertEqual(self.lua.eval('MetaComic.VendingProgressDuration(300000)'), 15000)
        self.assertEqual(self.lua.eval('MetaComic.VendingProgressDuration(3000)'), 3000)
        self.lua.execute('convars.metacomic_dev_progress_ms=10000')
        self.assertEqual(self.lua.eval('MetaComic.VendingProgressDuration(45000)'), 10000)
        self.assertEqual(self.lua.eval('Config.VendingMachines.Crime.BreakIn.Duration'), 45000)
        self.assertEqual(self.lua.eval('Config.VendingMachines.Crime.BreakIn.Loot.UnlockSeconds'), 600)
        self.lua.execute('convars.metacomic_dev_testing=0')
        self.assertEqual(self.lua.eval('MetaComic.VendingProgressDuration(45000)'), 45000)

    def start_breakin(self):
        self.lua.execute((ROOT / 'fivem/server/modules/vending_loot.lua').read_text(encoding='utf-8'))
        self.lua.execute("convars.metacomic_dev_testing=1;handlers['meta_comic:server:crimeStart'](1,'breakin')")
        self.assertEqual(self.lua.eval('startData.duration'), 15000)

    def test_early_completion_rejected(self):
        self.start_breakin()
        self.lua.execute("timer=1000;handlers['meta_comic:server:crimeFinish'](startData.token,true)")
        self.assertFalse(self.lua.eval('MetaComic.VendingLoot.isOpen(entry)'))

    def test_job_keeps_duration_when_dev_mode_changes(self):
        self.start_breakin()
        self.lua.execute("convars.metacomic_dev_testing=0;timer=15000;handlers['meta_comic:server:crimeFinish'](startData.token,true)")
        self.assertTrue(self.lua.eval('MetaComic.VendingLoot.isOpen(entry)'))


if __name__ == '__main__':
    unittest.main()
