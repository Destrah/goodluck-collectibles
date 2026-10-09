"""Set-specific odds must stay in the live icon cache, including cross-resource snapshots."""
import importlib.util
from pathlib import Path
import unittest
spec=importlib.util.spec_from_file_location('report',Path(__file__).with_name('card-market-report.py'))
report=importlib.util.module_from_spec(spec);spec.loader.exec_module(report)

class IconTests(unittest.TestCase):
    def test_set_icon_signatures_are_live_without_artwork_edits(self):
        tiers=['common','uncommon','rare','ultra_rare','legendary']
        cards=[{'id':f'card{i}','title':tier,'image':'https://example.com/card.png','variants':[{'id':'base','rarityKey':tier}]} for i,tier in enumerate(tiers)]
        sets=[{'id':'all','cardIds':[c['id'] for c in cards]},{'id':'small','cardIds':['card0','card2','card3']}]
        lua=report.runtime(cards,sets)
        main=(report.ROOT/'fivem/server/main.lua').read_text(encoding='utf-8')
        lua.execute('ICON_STYLE=1;function objectType() return nil end;function Wait() end')
        start=main.index('local CARD_ICON_FIELDS')
        end=main.index('-- File mode:',start)
        lua.execute(main[start:end]+'\ntestKey=printKey;testIcon=iconCard;testHash=hashText')
        lua.execute("yieldCount=0;function Wait() yieldCount=yieldCount+1 end;longArtwork=string.rep('image-data',20000);directHash=testHash(longArtwork);chunkHash=testHash(longArtwork,true)")
        self.assertEqual(lua.eval('directHash'),lua.eval('chunkHash'))
        self.assertGreater(lua.eval('yieldCount'),1)
        start=main.index('local function catalogPrints()')
        end=main.index('-- Fivemanage uploads waiting',start)
        lua.execute('printKey=testKey\n'+main[start:end]+'\ntestLive=liveIconKeys')
        lua.execute("global=MetaComic.Cards.resolve('card2','base');pulled=MetaComic.CopyTable(global);pulled.setId='small';live=testLive()")
        self.assertNotEqual(lua.eval('testKey(global)'),lua.eval('testKey(pulled)'))
        self.assertTrue(lua.eval('live[testKey(pulled)]'))
        self.assertTrue(lua.eval('live[testKey(global)]'))
        self.assertTrue(lua.eval('live[testKey(MetaComic.CopyTable(pulled))]'))
        self.assertNotEqual(lua.eval('testIcon(global).starColour'),lua.eval('testIcon(pulled).starColour'))
        self.assertEqual(lua.eval('global.image'),lua.eval('pulled.image'))

if __name__=='__main__':unittest.main()
