"""Verify the real getSets RPC loads persisted memberships before returning."""
from pathlib import Path
import sys
import unittest
if len(sys.argv)>1: sys.path.insert(0,sys.argv.pop(1))
from lupa.lua54 import LuaRuntime
ROOT=Path(__file__).resolve().parents[1]

class SetLoadingTests(unittest.TestCase):
    def setUp(self):
        self.lua=LuaRuntime(unpack_returned_tuples=True)
        self.lua.execute("""
            handlers={};reloads=0;loadedSets={}
            MetaComic={Persistence={},Cards={},Sets={}}
            function MetaComic.Persistence.reloadDefinitions() reloads=reloads+1;return not loadFails,'database unavailable' end
            function MetaComic.Cards.reloadCatalog() end
            function MetaComic.Cards.getCatalog() return {{id='hero'}} end
            function MetaComic.Sets.reload() loadedSets={{id='alpha',code='ALP',cardIds={'hero'}}} end
            function MetaComic.Sets.getAll() return loadedSets end
            function MetaComic.Sets.defaultId() return 'alpha' end
            function setsWithLogos() return loadedSets end
            function fail(err) return {ok=false,error=err} end
            function print() end
        """)
        text=(ROOT/'fivem/server/main.lua').read_text(encoding='utf-8')
        loader=text.split('local definitionsLoaded =',1)[1].split('CreateThread(function() Wait(0) loadDefinitions() end)',1)[0]
        rpc=text.split('handlers.getSets = function()',1)[1].split('handlers.saveSets =',1)[0]
        self.lua.execute('local definitionsLoaded ='+loader+'handlers.getSets = function()'+rpc)

    def test_get_sets_recovers_startup_cache_and_reuses_loaded_data(self):
        self.lua.execute('result=handlers.getSets()')
        self.assertTrue(self.lua.eval('result.ok'))
        self.assertEqual(self.lua.eval('result.sets[1].cardIds[1]'),'hero')
        self.lua.execute('handlers.getSets()')
        self.assertEqual(self.lua.eval('reloads'),1)

    def test_failed_load_reports_error_then_retries_instead_of_empty_success(self):
        self.lua.execute('loadFails=true;result=handlers.getSets()')
        self.assertFalse(self.lua.eval('result.ok'))
        self.assertIsNone(self.lua.eval('result.sets'))
        self.lua.execute('loadFails=false;result=handlers.getSets()')
        self.assertTrue(self.lua.eval('result.ok'))
        self.assertEqual(self.lua.eval('reloads'),2)

if __name__=='__main__': unittest.main()
