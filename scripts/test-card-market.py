"""Check exact pack expectations and read-only buyer projections in the actual Lua modules."""
import importlib.util
from pathlib import Path
import unittest
import json

spec=importlib.util.spec_from_file_location('report',Path(__file__).with_name('card-market-report.py'))
report=importlib.util.module_from_spec(spec);spec.loader.exec_module(report)

class MarketTests(unittest.TestCase):
    def fixture(self,tiers=None):
        tiers=tiers or ['common','uncommon','rare','ultra_rare','legendary']
        cards=[{'id':f'card{i}','title':tier,'variants':[{'id':'base','rarityKey':tier}]} for i,tier in enumerate(tiers)]
        lua=report.runtime(cards,[{'id':'test','name':'Test','cardIds':[c['id'] for c in cards]}])
        return lua

    def calculate(self,lua,n=100):
        return report.from_lua(lua.globals().MetaComic.CardMarketAnalysis.calculate(lua.globals().Config.CardBuyers.Peds[1],'test',n))

    def test_exact_guaranteed_slot_value(self):
        result=self.calculate(self.fixture())
        self.assertAlmostEqual(result['clean']['mean'],15.75)
        self.assertAlmostEqual(sum(p['expectedCopies'] for p in result['prints']),5)
        self.assertAlmostEqual(sum(s['mean'] for s in result['slots']),15.75)
        self.assertAlmostEqual(sum(g['chance'] for g in result['gradeDistribution']),1)

    def test_constant_common_price_and_minimum(self):
        result=self.calculate(self.fixture(['common']),1)
        for scenario in ['clean','fresh']:
            self.assertEqual(result[scenario]['mean'],5)
            self.assertEqual(result[scenario]['variance'],0)
            self.assertEqual(result[scenario]['median'],5)
        self.assertEqual(result['samples'],100)

    def test_integer_card_offers_and_pack_payouts_before_averaging(self):
        result=self.calculate(self.fixture(),300)
        for row in result['prints']:
            self.assertEqual(row['cleanPrice'],int(row['cleanPrice']))
            for grade in row['grades']:
                self.assertEqual(grade['price'],int(grade['price']))
        for scenario in ['clean','fresh','graded']:
            for bin in result[scenario]['histogram']:
                self.assertEqual(bin['value'],int(bin['value']))
        # Whole-dollar sales still produce a fractional weighted expectation.
        self.assertEqual(result['clean']['mean'],15.75)

    def test_deterministic_and_does_not_consume_gameplay_random(self):
        lua=self.fixture()
        lua.execute('math.randomseed(91); expected=math.random(); math.randomseed(91)')
        first=self.calculate(lua,300)
        self.assertEqual(lua.eval('math.random()'),lua.globals().expected)
        self.assertEqual(first,self.calculate(lua,300))
        self.assertLess(first['gradeScenarios'][0]['mean'],first['clean']['mean'])
        self.assertGreater(first['gradeScenarios'][-1]['mean'],first['clean']['mean'])

    def test_employee_permissions_and_duty(self):
        lua=self.fixture()
        lua.execute("admin=false;Config.CardBuyers.Peds[1].EmployeeJobs={cardshop=0};job={name='cardshop',grade=0,onDuty=true}")
        self.assertEqual(len(lua.globals().MetaComic.CardBuyers.analysisBuyers(1)),1)

    def test_report_cache_invalidation_and_disabled_buyer(self):
        lua=self.fixture()
        lua.globals().encodeJson=lambda value:json.dumps(report.from_lua(value),sort_keys=True)
        lua.execute('''json={encode=encodeJson};calls=0
            local calculate=MetaComic.CardMarketAnalysis.calculate
            MetaComic.CardMarketAnalysis.calculate=function(...) calls=calls+1;return calculate(...) end
            Config.CardBuyers.Analysis.SamplePacks=100''')
        service=lua.globals().MetaComic.CardMarketAnalysis
        payload=report.to_lua(lua,{'index':1,'setId':'test'})
        self.assertTrue(service.report(1,payload)['ok'])
        self.assertTrue(service.report(1,payload)['ok'])
        self.assertEqual(lua.globals().calls,1)
        lua.execute('MetaComic.CardBuyerStock.version=1')
        self.assertTrue(service.report(1,payload)['ok'])
        self.assertEqual(lua.globals().calls,2)
        lua.execute('MetaComic.CardBuyers=nil')
        self.assertFalse(service.report(1,payload)['ok'])
        self.assertFalse(service.options(1)['ok'])

    def test_set_payout_preview_save_permissions_and_reload(self):
        lua=self.fixture()
        lua.globals().encodeJson=lambda value:json.dumps(report.from_lua(value),sort_keys=True)
        lua.execute("function IsPlayerAceAllowed(_,ace) return aceAllowed==true and ace==Config.Management.Ace end;aceAllowed=true")
        lua.execute("settings={};MetaComic.Settings={get=function(k,d) return settings[k] or d end,set=function(k,v) if failSave then return false,'Database unavailable' end;settings[k]=v;return true end};json={encode=encodeJson};Config.CardBuyers.Analysis.SamplePacks=100")
        service=lua.globals().MetaComic.CardMarketAnalysis
        payload=report.to_lua(lua,{'index':1,'setId':'test'})
        original=service.report(1,payload)['report']['clean']['mean']
        preview=report.to_lua(lua,{'index':1,'setId':'test','previewMultiplier':2})
        self.assertGreater(service.report(1,preview)['report']['clean']['mean'],original)
        self.assertEqual(lua.globals().MetaComic.CardBuyers.setPayoutMultiplier('test'),1)
        save=lua.globals().MetaComic.RpcHandlers.saveCardSetPayout
        self.assertTrue(save(1,report.to_lua(lua,{'setId':'test','multiplier':2}))['ok'])
        self.assertGreater(service.report(1,payload)['report']['clean']['mean'],original)
        lua.execute((report.ROOT/'fivem/server/modules/card_buyers.lua').read_text(encoding='utf-8'))
        self.assertEqual(lua.globals().MetaComic.CardBuyers.setPayoutMultiplier('test'),2)
        self.assertEqual(lua.globals().MetaComic.CardBuyers.setPayoutMultiplier('other'),1)
        lua.execute('failSave=true')
        self.assertFalse(save(1,report.to_lua(lua,{'setId':'test','multiplier':0.5}))['ok'])
        self.assertEqual(lua.globals().MetaComic.CardBuyers.setPayoutMultiplier('test'),2)
        self.assertFalse(save(1,report.to_lua(lua,{'setId':'test','multiplier':float('inf')}))['ok'])
        lua.execute("admin=false;aceAllowed=false;Config.CardBuyers.Peds[1].EmployeeJobs={cardshop=0};job={name='cardshop',grade=0,onDuty=true}")
        self.assertFalse(save(1,report.to_lua(lua,{'setId':'test','multiplier':1}))['ok'])
        self.assertFalse(service.report(1,preview)['ok'])
        self.assertTrue(service.report(1,payload)['ok'])
        lua.execute('admin=true')
        self.assertFalse(service.options(1)['canAdjustPayouts'])
        self.assertFalse(save(1,report.to_lua(lua,{'setId':'test','multiplier':1}))['ok'])
        lua.execute('aceAllowed=true')
        self.assertTrue(service.options(1)['canAdjustPayouts'])

    def test_duplicate_reports_wait_for_one_calculation(self):
        lua=self.fixture()
        lua.globals().encodeJson=lambda value:json.dumps(report.from_lua(value),sort_keys=True)
        lua.execute("""json={encode=encodeJson};Config.CardBuyers.Analysis.SamplePacks=100
            local calculate=MetaComic.CardMarketAnalysis.calculate
            calls=0;MetaComic.CardMarketAnalysis.calculate=function(...) calls=calls+1;return calculate(...) end
            function Wait() coroutine.yield() end
            local payload={index=1,setId='test'}
            first=coroutine.create(function() result1=MetaComic.CardMarketAnalysis.report(1,payload) end)
            second=coroutine.create(function() result2=MetaComic.CardMarketAnalysis.report(1,payload) end)
            assert(coroutine.resume(first));assert(coroutine.resume(second))
            for i=1,20 do
                if coroutine.status(first)~='dead' then assert(coroutine.resume(first)) end
                if coroutine.status(second)~='dead' then assert(coroutine.resume(second)) end
            end
        """)
        self.assertTrue(lua.globals().result1['ok'])
        self.assertTrue(lua.globals().result2['ok'])
        self.assertEqual(lua.globals().calls,1)
        self.assertEqual(report.from_lua(lua.globals().result1['report']),report.from_lua(lua.globals().result2['report']))

    def test_adjustment_rounding_floor_cap_and_fixed_overrides(self):
        lua=self.fixture()
        lua.execute("buyer=Config.CardBuyers.Peds[1];buyer.Pricing='rarity';buyer.RarityMultipliers={common=3};buyer.MinPrice=1;buyer.MaxPrice=10;card={id='x',baseCardId='x',variantId='base',setId='test',rarityKey='common'}")
        price=lua.globals().MetaComic.CardBuyers.price
        buyer,card=lua.globals().buyer,lua.globals().card
        self.assertEqual(price(buyer,card,lua.table(),0.5),2)
        self.assertEqual(price(buyer,card,lua.table(),0.1),1)
        self.assertEqual(price(buyer,card,lua.table(),10),10)
        lua.execute("buyer.FixedPricesEnabled=true;buyer.FixedPrices={x=7}")
        self.assertEqual(price(buyer,card,lua.table(),0.1),7)

    def test_portal_grants_pricing_without_editor_access(self):
        lua=self.fixture()
        lua.execute("admin=false;canManage=MetaComic.CanManage;Config.CardBuyers.Peds[1].EmployeeJobs={cardshop=0};job={name='cardshop',grade=0,onDuty=true};function IsPlayerAceAllowed() return false end")
        source=(report.ROOT/'fivem/server/main.lua').read_text(encoding='utf-8')
        start=source.index('local PORTAL_TABS')
        end=source.index('local function requireEdit',start)
        lua.execute(source[start:end])
        access=report.from_lua(lua.globals().MetaComic.Portal.access(1))
        self.assertIn('pricing',access['tabs'])
        self.assertNotIn('editor',access['tabs'])
        lua.execute('job.onDuty=false')
        self.assertEqual(len(lua.globals().MetaComic.CardBuyers.analysisBuyers(1)),0)
        lua.execute("job={name='unrelated',grade=10,onDuty=true}")
        self.assertEqual(len(lua.globals().MetaComic.CardBuyers.analysisBuyers(1)),0)
        self.assertFalse(lua.globals().MetaComic.CardMarketAnalysis.report(1,report.to_lua(lua,{'index':1,'setId':'test'}))['ok'])
        lua.execute('admin=true')
        self.assertEqual(len(lua.globals().MetaComic.CardBuyers.analysisBuyers(1)),1)

if __name__=='__main__':unittest.main()
