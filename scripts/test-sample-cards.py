"""Sample import integration tests; reuses the SQLite/Lua adapter test harness.
Run: python scripts/test-sample-cards.py .tmp-mysql-tests
"""
import importlib.util
import json
from pathlib import Path
import re
import sys
import unittest
if len(sys.argv)>1:
    sys.path.insert(0,sys.argv.pop(1))
ROOT=Path(__file__).resolve().parents[1]
spec=importlib.util.spec_from_file_location('persistence_harness',ROOT/'scripts/test-mysql-persistence.py')
module=importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)

class SampleTests(unittest.TestCase):
    def setUp(self):
        self.h=module.PersistenceTests('test_all_fivem_lua_files_compile')
        self.h.setUp()
        self.lua=self.h.lua
        self.h.files['data/sample-cards.json']=(ROOT/'fivem/data/sample-cards.json').read_text(encoding='utf-8')
        for asset in (ROOT/'public/img/sample').glob('*.png'):
            self.h.files['img/sample/'+asset.name]=asset.read_bytes()
        self.h.run_file('fivem/server/modules/sample_cards.lua')
        self.lua.execute('''
            Wait=function() end
            uploads=0;syncs=0
            sampleHooks={hasKey=function() return true end,report=function() end,freeze=function() end,
                sync=function() syncs=syncs+1 end,
                upload=function(data) assert(data:sub(1,22)=='data:image/png;base64,');uploads=uploads+1;return 'https://example.test/'..uploads..'.png' end}
        ''')

    def test_manifest_coverage_and_aligned_assets(self):
        seed=json.loads(self.h.files['data/sample-cards.json'])
        self.assertEqual(len(seed['cards']),100)
        self.assertEqual(sum(len(c['variants']) for c in seed['cards']),800)
        self.assertEqual(len(set(c['id'] for c in seed['cards'])),100)
        self.assertEqual(len(set(c['chanceWeight'] for c in seed['cards'])),5)
        holos=set();effects=set();mask_sources=set();layouts=set();tiers=set()
        source=(ROOT/'src/cardData.js').read_text(encoding='utf-8')
        allowed_effects=set(re.findall(r"value: '([^']+)'",source.split('export const SUBJECT_EFFECTS = [')[1].split(']')[0]))
        for card in seed['cards']:
            self.assertIn(card['image'][1:],self.h.files)
            for print_ in card['variants']:
                holos.add(print_['holo']);layouts.add(print_['layout']);tiers.add(print_['rarityKey'])
                for layer in print_['subjectLayers']:
                    effects.add(layer['mode']);mask_sources.add(layer['maskSource'])
                    self.assertIn(layer['image'][1:],self.h.files)
                    self.assertIn(layer['mode'],allowed_effects)
        self.assertEqual(len(holos),8);self.assertEqual(len(layouts),4);self.assertEqual(len(tiers),5)
        self.assertEqual(len(effects),len(allowed_effects))
        self.assertEqual(mask_sources,{'alpha','luminance','luminance-invert'})

    def test_uploads_and_atomic_import_preserve_existing_definitions(self):
        before=self.h.rows(module.CARDS)
        result=self.lua.execute('return MetaComic.SampleCards.generate(sampleHooks)')
        self.assertEqual(result['added'],100);self.assertEqual(result['prints'],800)
        self.assertEqual(self.lua.eval('uploads'),150)
        self.assertEqual(len(self.h.rows(module.CARDS)),102)
        self.assertEqual(len(self.h.rows(module.PRINTS)),803)
        for row in before:self.assertIn(row,self.h.rows(module.CARDS))
        catalog=self.h.to_python(self.lua.execute('return MetaComic.Cards.getCatalog()'))
        for card in catalog:
            if card['id'].startswith('sample-'):
                self.assertTrue(card['image'].startswith('https://'))
                for print_ in card['variants']:
                    for layer in print_.get('subjectLayers',[]):self.assertTrue(layer['image'].startswith('https://'))
        sample=[s for s in self.h.rows(module.SETS) if s['id']=='sample'][0]
        self.assertEqual(sample['name'],'Sample')
        self.assertEqual(len([r for r in self.h.rows(module.MEMBERS) if r['set_id']=='sample']),100)

    def test_reruns_are_idempotent_and_preserve_edited_sample_cards(self):
        self.lua.execute('MetaComic.SampleCards.generate(sampleHooks)')
        self.lua.execute("local card=MetaComic.Cards.getCatalog()[3];card.title='Edited Sample';MetaComic.Cards.saveCard(card)")
        uploads=self.lua.eval('uploads')
        result=self.lua.execute('return MetaComic.SampleCards.generate(sampleHooks)')
        self.assertEqual(result['added'],0);self.assertEqual(self.lua.eval('uploads'),uploads)
        self.assertEqual(len(self.h.rows(module.CARDS)),102)
        self.assertTrue(any(r['title']=='Edited Sample' for r in self.h.rows(module.CARDS)))

    def test_failed_upload_does_not_save_partial_catalog(self):
        self.lua.execute('sampleHooks.upload=function() return nil end')
        with self.assertRaisesRegex(Exception,'Sample upload failed'):
            self.lua.execute('MetaComic.SampleCards.generate(sampleHooks)')
        self.assertEqual(len(self.h.rows(module.CARDS)),2)
        self.assertFalse(any(r['id']=='sample' for r in self.h.rows(module.SETS)))
        self.assertEqual(self.lua.eval('syncs'),0)
        self.lua.execute("sampleHooks.upload=function() return 'https://example.test/retry.png' end")
        self.assertEqual(self.lua.execute('return MetaComic.SampleCards.generate(sampleHooks)').added,100)

    def test_artwork_refresh_preserves_all_other_definition_fields(self):
        self.lua.execute('MetaComic.SampleCards.generate(sampleHooks)')
        self.lua.execute("local card=MetaComic.Cards.getCatalog()[3];card.title='Edited Sample';card.variants[1].chanceWeight=777;MetaComic.Cards.saveCard(card)")
        before=self.h.to_python(self.lua.execute('return MetaComic.Cards.getCatalog()'))
        self.lua.execute('sampleHooks.refreshArt=true')
        result=self.lua.execute('return MetaComic.SampleCards.generate(sampleHooks)')
        after=self.h.to_python(self.lua.execute('return MetaComic.Cards.getCatalog()'))
        self.assertEqual(result['added'],0)
        self.assertEqual(self.lua.eval('uploads'),250)
        for old,new in zip(before,after):
            if old['id'].startswith('sample-'):
                self.assertNotEqual(old.pop('image'),new.pop('image'))
            self.assertEqual(old,new)

    def test_database_failure_rolls_back_cards_prints_and_memberships_together(self):
        self.h.fail_after=5
        with self.assertRaisesRegex(Exception,'Could not save sample'):
            self.lua.execute('MetaComic.SampleCards.generate(sampleHooks)')
        self.assertEqual(len(self.h.rows(module.CARDS)),2)
        self.assertEqual(len(self.h.rows(module.PRINTS)),3)
        self.assertFalse(any(r['id']=='sample' for r in self.h.rows(module.SETS)))

    def test_missing_key_and_id_collision_stop_before_uploading(self):
        self.lua.execute('sampleHooks.hasKey=function() return false end')
        with self.assertRaisesRegex(Exception,'metacomic_fivemanage_key'):
            self.lua.execute('MetaComic.SampleCards.generate(sampleHooks)')
        self.lua.execute("sampleHooks.hasKey=function() return true end;MetaComic.Cards.saveCard({id='sample-001',title='Existing custom card',variants={{id='custom'}}})")
        with self.assertRaisesRegex(Exception,'conflicts with an existing card'):
            self.lua.execute('MetaComic.SampleCards.generate(sampleHooks)')
        self.assertEqual(self.lua.eval('uploads'),0)

    def test_base64_and_lua_syntax(self):
        import base64
        encode=self.lua.eval('MetaComic.SampleCards.base64')
        for raw in [b'',b'a',b'ab',b'abc',bytes(range(256))]:
            self.assertEqual(encode(raw),base64.b64encode(raw).decode())
        self.h.test_all_fivem_lua_files_compile()

if __name__=='__main__':unittest.main()
