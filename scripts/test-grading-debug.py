"""Exercise FiveM grading handlers with isolated inventory/session stubs."""
from pathlib import Path
import sys
import unittest
if len(sys.argv) > 1:
    sys.path.insert(0, sys.argv.pop(1))
from lupa import LuaRuntime
ROOT = Path(__file__).resolve().parents[1]

class GradingDebugTests(unittest.TestCase):
    def setUp(self):
        self.lua = LuaRuntime(unpack_returned_tuples=True)
        self.lua.execute('''
          MetaComic={Inventory={has=function() return true end}}
          function MetaComic.CopyTable(value)
            if type(value)~='table' then return value end
            local out={};for k,v in pairs(value) do out[k]=MetaComic.CopyTable(v) end;return out
          end
          handlers={};gradingSessions={};gradingConfig={}
          gradingAllowed=function() return true end
          cardItemAt=function() return {metadata={}} end
          testCard={id='historical',image='https://example.test/original.png',variantId='old',holo='none',condition={centering={front={0.09,0.06}},art={0.3,0.2},text={0.2,0.1}}}
          handleCardItem=function() return testCard end
          maxWrongMarks=function() return 6 end
          fail=function(message) return {ok=false,error=message} end
        ''')
        self.lua.execute((ROOT/'fivem/server/modules/grading.lua').read_text(encoding='utf-8'))
        self.lua.execute('Grading=MetaComic.Grading')
        source=(ROOT/'fivem/server/main.lua').read_text(encoding='utf-8')
        start=source.index('handlers.startGrading = function')
        end=source.index('handlers.gradingSubmit = function',start)
        self.lua.execute(source[start:end])

    def test_debug_off_by_default_and_reference_uses_copy_snapshot(self):
        response=self.lua.execute('return handlers.startGrading(1,{slot=2})')
        self.assertFalse(response.debug)
        self.assertIsNone(response.debugFlaws)
        self.assertEqual(response.reference.image,response.card.image)
        self.assertIsNone(response.reference.condition)
        self.assertIsNotNone(response.card.condition)

    def test_debug_shows_server_flaws_without_changing_mark_rules(self):
        self.lua.execute('gradingConfig.Debug=true')
        response=self.lua.execute('return handlers.startGrading(1,{slot=2})')
        self.assertTrue(response.debug)
        self.assertEqual(len(response.debugFlaws),0)
        mark=self.lua.execute("return handlers.gradingMark(1,{sessionId=gradingSessions[1].id,mark={type='art',side='front',x=50,y=50}})")
        self.assertFalse(mark.confirmed)
        self.assertEqual(mark.wrong,1)
        self.lua.execute('testCard.condition.art={0.61,0}')
        response=self.lua.execute('return handlers.startGrading(1,{slot=2})')
        self.assertEqual(response.debugFlaws[1].id,'art')
        mark=self.lua.execute("return handlers.gradingMark(1,{sessionId=gradingSessions[1].id,mark={type='art',side='front',x=50,y=50}})")
        self.assertTrue(mark.confirmed)

    def test_text_marks_require_text_part_and_matching_position(self):
        self.lua.execute('testCard.condition.text={1,0};handlers.startGrading(1,{slot=2})')
        for mark in ["{type='text',x=50,y=40}","{type='text',textPart='title',x=50,y=40}","{type='centering',x=50,y=40}"]:
            result=self.lua.execute('return handlers.gradingMark(1,{sessionId=gradingSessions[1].id,mark='+mark+'})')
            self.assertFalse(result.confirmed)
        result=self.lua.execute("return handlers.gradingMark(1,{sessionId=gradingSessions[1].id,mark={type='text',textPart='title',x=20,y=9}})")
        self.assertTrue(result.confirmed)

    def test_independent_text_sections_have_separate_server_findings(self):
        self.lua.execute("testCard.layout='illustration';testCard.condition.text={title={1,0},description={0,0.7},hp={0,0}};handlers.startGrading(1,{slot=2})")
        for part,x,y,expected in [('hp',90,8,False),('title',20,9,True),('title',20,9,False),('description',20,62,True)]:
            result=self.lua.execute("return handlers.gradingMark(1,{sessionId=gradingSessions[1].id,mark={type='text',textPart='%s',x=%d,y=%d}})"%(part,x,y))
            self.assertEqual(result.confirmed,expected)
        self.assertEqual(self.lua.eval('gradingSessions[1].foundCount'),2)
        generated=self.lua.execute('return MetaComic.Grading.generate()')
        self.assertEqual(generated.v,2)
        self.assertIsNotNone(generated.text.title)

if __name__=='__main__':unittest.main()
