"""Execute real Lua buyer handlers against server inventory, money and position fixtures."""
from pathlib import Path
import sys
import unittest
if len(sys.argv)>1: sys.path.insert(0,sys.argv.pop(1))
from lupa.lua54 import LuaRuntime
ROOT=Path(__file__).resolve().parents[1]


class CardBuyerTests(unittest.TestCase):
    def setUp(self):
        self.lua=LuaRuntime(unpack_returned_tuples=True)
        self.lua.execute('''
            local mt={};mt.__sub=function(a,b) return setmetatable({x=a.x-b.x,y=a.y-b.y,z=a.z-b.z},mt) end
            mt.__len=function(a) return math.sqrt(a.x*a.x+a.y*a.y+a.z*a.z) end
            function vector3(x,y,z) return setmetatable({x=x,y=y,z=z},mt) end
            buyer={id='shop',coords=vector3(0,0,0),EmployeeJobs={cardshop=0},Store={coords=vector3(0,0,0),radius=10},HideWhenEmployeesPresent=true}
            Config={Items={TradingCard='tradingcard'},CardBuyers={Enabled=true,Peds={buyer},MinPrice=10,MaxPrice=1000,Pricing='combined',
                RarityScores={common=0,rare=0.5,legendary=1},OddsMaxRatio=100,RequireBusinessFunds=false,FixedPricesEnabled=false}}
            source=1;players={};jobs={};positions={[1]=vector3(0,0,0)};events={};commands={};notices={};stored={shop=1000}
            card={baseCardId='one',variantId='base',rarityKey='common',title='One'}
            meta={instanceId='i1',label='One',cardSnapshot=card}
            item={name='tradingcard',slot=4,count=1,metadata=meta};removed=0;returned=0;paid=0;deposited=0;saves=0
            MetaComic={Framework={getJob=function(s) return jobs[s] end,notify=function(s,message) notices[#notices+1]=message end},
                Cards={printOdds=function() return {['one::base']=1,['rare::foil']=0.01} end,resolve=function() return card end},
                Settings={get=function() return stored end,set=function(_,v) saves=saves+1;if failSave then return false end;stored=v;return true end,
                    stage=function(_,v) stored=v;return true end},
                Inventory={getSlot=function(_,slot) if item and item.slot==slot then return item end end,
                    slotsOf=function() return item and {item} or {} end,
                    remove=function() if failRemove or not item then return false end;removed=removed+1;item=nil;return true end,
                    add=function(_,_,_,m) returned=returned+1;item={name='tradingcard',slot=4,count=1,metadata=m};return true end},
                Money={add=function(_,_,amount) if throwPay then error('payment error') end;if failPay then return false end;paid=paid+amount;return true end,
                    remove=function(_,_,amount) if failDeposit then return false end;deposited=deposited+amount;return true end}}
            function GetPlayers() return players end
            function GetPlayerPed(s) return positions[s] and s or 0 end
            function GetEntityCoords(s) return positions[s] end
            function RegisterNetEvent(name,cb) events[name]=cb end
            function RegisterCommand(name,cb) commands[name]=cb end
            function AddEventHandler() end
            function CreateThread() end
            function GetGameTimer() return 10000 end
            function TriggerClientEvent() end
            function TriggerLatentClientEvent(_,_,_,index,offers,balance) menu=offers;menuBalance=balance end
            function print() end
        ''')
        self.lua.execute((ROOT/'fivem/server/modules/card_buyers.lua').read_text(encoding='utf-8'))
        self.lua.execute((ROOT/'fivem/shared/utils.lua').read_text(encoding='utf-8'))

    def run_lua(self,code): self.lua.execute(code)
    def sale(self,price=10,instance='i1'):
        self.lua.execute(f"events['meta_comic:server:sellTradingCard'](1,4,{price},'{instance}')")
    def price(self): return self.lua.eval('MetaComic.CardBuyers.price(buyer,card,meta)')

    def baseline(self):
        self.run_lua("Config.CardBuyers.MinPrice=1;Config.CardBuyers.RarityMultipliers={common=1,uncommon=2,rare=5,ultra_rare=15,legendary=50}")
        self.lua.execute((ROOT/'fivem/server/modules/grading.lua').read_text(encoding='utf-8'))

    def test_one_dollar_baseline_and_rarity_scaling(self):
        self.baseline()
        self.run_lua("Config.CardBuyers.Pricing='rarity'")
        for tier, price in [('common',1),('uncommon',2),('rare',5),('ultra_rare',15),('legendary',50)]:
            self.run_lua(f"card.rarityKey='{tier}'")
            self.assertEqual(self.price(),price)

    def test_real_server_pack_guarantees_and_set_odds(self):
        self.run_lua('''
            Config.Catalog={File='catalog.json'};MetaComic.Persistence={name='mysql',loadCatalog=function() return catalogFixture end}
            function GetCurrentResourceName() return 'test' end
            catalogFixture={};for i,tier in ipairs({'common','uncommon','rare','ultra_rare','legendary'}) do
                catalogFixture[i]={id='card'..i,title=tier,variants={{id='base',rarityKey=tier}}}
            end
            selectedSet={id='set',name='Set',cardIds={'card1','card2','card3','card4','card5'}}
            MetaComic.Sets={get=function(id) if id=='set' then return selectedSet end end}
        ''')
        self.lua.execute((ROOT/'fivem/server/cards.lua').read_text(encoding='utf-8'))
        for index,expected in enumerate([3,1,.75,.2,.05],1):
            self.assertAlmostEqual(self.lua.eval(f"MetaComic.Cards.printOdds('set')['card{index}::base']"),expected)
        self.run_lua("selectedSet.cardIds={'card1','card4'}")
        self.assertAlmostEqual(self.lua.eval("MetaComic.Cards.printOdds('set')['card4::base']"),2)
        self.run_lua("for i=1,200 do local p=MetaComic.Cards.openPack('owner','set');assert(#p==5);assert(p[4].rarityKey=='ultra_rare');assert(p[5].rarityKey=='ultra_rare') end")

    def test_odds_use_card_set_and_one_dollar_relative_baseline(self):
        self.baseline()
        self.run_lua("card.setId='set';MetaComic.Cards.printOdds=function(id) assert(id=='set');return {['one::base']=0.25,['other::base']=3} end")
        self.assertEqual(self.price(),12)

    def test_small_raw_defects_do_not_change_price(self):
        self.baseline()
        self.run_lua("card.rarityKey='legendary';card.condition={art={0.9,0},centering={front={0.15,0}},marks={{type='scratch',s=0.3,x1=0,y1=0,x2=20,y2=0}}}")
        self.assertEqual(self.price(),50)

    def test_obvious_raw_defects_discount_but_respect_minimum(self):
        self.baseline()
        self.run_lua("card.rarityKey='legendary';card.condition={art={2,0}}")
        self.assertEqual(self.price(),44)
        self.run_lua("card.rarityKey='common'")
        self.assertEqual(self.price(),1)

    def test_short_scratch_is_not_obvious_but_large_scratch_is(self):
        self.baseline()
        self.run_lua("card.rarityKey='legendary';card.condition={marks={{type='scratch',s=0.8,x1=0,y1=0,x2=2,y2=0}}}")
        self.assertEqual(self.price(),50)
        self.run_lua('card.condition.marks[1].x2=30')
        self.assertLess(self.price(),50)

    def test_graded_cards_use_grade_without_double_condition_discount(self):
        self.baseline()
        self.run_lua("card.rarityKey='legendary';card.condition={art={5,0}};card.graded={grade=9}")
        self.assertEqual(self.price(),70)
        self.run_lua('card.graded.grade=10')
        self.assertEqual(self.price(),125)
        self.run_lua('card.graded.grade=2')
        self.assertEqual(self.price(),13)

    def test_grade_premium_caps_unless_fixed_override_authorizes_it(self):
        self.baseline()
        self.run_lua("Config.CardBuyers.FixedPricesEnabled=true;Config.CardBuyers.FixedPrices={one=900};card.graded={grade=10}")
        self.assertEqual(self.price(),1000)
        self.run_lua('Config.CardBuyers.FixedPricesIgnoreMaximum=true')
        self.assertEqual(self.price(),2250)

    def test_sparse_custom_grade_map_never_makes_integer_grade_zero(self):
        self.baseline()
        self.run_lua("card.rarityKey='legendary';card.graded={grade=8};Config.CardBuyers.ConditionPricing={GradeMultipliers={[10]=3}}")
        self.assertEqual(self.price(),50)

    def stock(self):
        self.run_lua('''
            Config.CardBuyers.Stock={Enabled=true};MetaComic.Persistence={name='json'}
            kvp={};encoded={};nextEncoded=0
            json={encode=function(value) nextEncoded=nextEncoded+1;local key=tostring(nextEncoded);encoded[key]=MetaComic.CopyTable(value);return key end,
                decode=function(value) return MetaComic.CopyTable(encoded[value]) end}
            function GetCurrentResourceName() return 'rush-tradingcards' end
            function SetResourceKvp(key,value) if failStock then error('storage failed') end;kvp[key]=value end
            function GetResourceKvpString(key) return kvp[key] end
            function StartFindKvp() kvpKeys={};for key in pairs(kvp) do kvpKeys[#kvpKeys+1]=key end;kvpPosition=0;return 1 end
            function FindKvp() kvpPosition=kvpPosition+1;return kvpKeys[kvpPosition] end
            function EndFindKvp() end
        ''')
        self.lua.execute((ROOT/'fivem/server/modules/card_buyer_stock.lua').read_text(encoding='utf-8'))

    def test_sales_retain_original_metadata_and_stock_retrieves_once(self):
        self.stock();self.sale()
        self.run_lua("rows,total=MetaComic.CardBuyerStock.page('shop',1,20)")
        self.assertEqual(self.lua.eval('total'),1)
        self.assertTrue(self.lua.eval("MetaComic.CardBuyerStock.retrieve(1,'shop',rows[1].id)" )[0])
        self.assertFalse(self.lua.eval("MetaComic.CardBuyerStock.retrieve(1,'shop',rows[1].id)" )[0])
        self.assertEqual(self.lua.eval('item.metadata.instanceId'),'i1')
        self.assertEqual(self.lua.eval('returned'),1)

    def test_failed_payment_has_no_stock_and_failed_stock_save_refunds(self):
        self.stock();self.run_lua('failPay=true');self.sale()
        self.assertEqual(self.lua.eval("select(2,MetaComic.CardBuyerStock.page('shop',1,20))"),0)
        self.run_lua('failPay=false;failStock=true');self.sale()
        self.assertEqual(self.lua.eval('paid'),0)
        self.assertEqual(self.lua.eval('returned'),2)

    def test_stock_survives_reload_and_cross_business_retrieval_is_rejected(self):
        self.stock();self.sale()
        self.lua.execute((ROOT/'fivem/server/modules/card_buyer_stock.lua').read_text(encoding='utf-8'))
        self.run_lua("rows,total=MetaComic.CardBuyerStock.page('shop',1,20)")
        self.assertEqual(self.lua.eval('total'),1)
        self.assertFalse(self.lua.eval("MetaComic.CardBuyerStock.retrieve(1,'other',rows[1].id)")[0])

    def test_cart_purchase_retains_cards_and_failed_add_keeps_stock(self):
        self.stock();self.quote()
        self.assertTrue(self.lua.eval('MetaComic.CardBuyers.sellCart(1,cartPayload).ok'))
        self.run_lua("rows,total=MetaComic.CardBuyerStock.page('shop',1,20);MetaComic.Inventory.add=function() return false end")
        self.assertEqual(self.lua.eval('total'),1)
        self.assertFalse(self.lua.eval("MetaComic.CardBuyerStock.retrieve(1,'shop',rows[1].id)")[0])
        self.assertEqual(self.lua.eval("select(2,MetaComic.CardBuyerStock.page('shop',1,20))"),1)

    def test_cart_failed_payment_cancels_retained_receipts(self):
        self.stock();self.run_lua('failPay=true');self.quote()
        self.assertFalse(self.lua.eval('MetaComic.CardBuyers.sellCart(1,cartPayload).ok'))
        self.assertEqual(self.lua.eval("select(2,MetaComic.CardBuyerStock.page('shop',1,20))"),0)
        self.assertEqual(self.lua.eval('returned'),1)

    def test_mysql_stock_uses_individual_rows_and_cached_browsing(self):
        self.stock()
        self.run_lua('''
            MetaComic.Persistence.name='mysql';Config.Database={Resource='oxmysql',AutoCreateSchema=true};sqlRows={};sqlCalls=0
            exports={oxmysql={query_async=function(_,sql,args)
                sqlCalls=sqlCalls+1
                if sql:find('SELECT') then local rows={};for _,value in pairs(sqlRows) do rows[#rows+1]={data_json=value} end;return rows end
                if sql:find('INSERT') then sqlRows[args[1]]=args[5] end
                return {}
            end}}
        ''')
        module=(ROOT/'fivem/server/modules/card_buyer_stock.lua').read_text(encoding='utf-8')
        self.lua.execute(module);self.sale()
        before=self.lua.eval('sqlCalls')
        self.assertEqual(self.lua.eval("select(2,MetaComic.CardBuyerStock.page('shop',1,20))"),1)
        self.assertEqual(self.lua.eval('sqlCalls'),before)
        self.lua.execute(module)
        self.assertEqual(self.lua.eval("select(2,MetaComic.CardBuyerStock.page('shop',1,20))"),1)

    def test_graded_population_changes_offers_and_deduplicates_resold_copy(self):
        self.baseline();self.stock()
        self.run_lua("card.rarityKey='legendary';card.graded={grade=9};Config.CardBuyers.GradedPopulation={Enabled=true};copies={}")
        self.assertEqual(self.price(),88)
        self.run_lua("batch=MetaComic.CardBuyerStock.prepare('shop',{{meta=meta,price=88}},1);MetaComic.CardBuyerStock.finish(batch,true)")
        self.assertEqual(self.lua.eval('MetaComic.CardBuyerStock.population(card,meta)'),1)
        self.run_lua("batch=MetaComic.CardBuyerStock.prepare('shop',{{meta=meta,price=88}},1);MetaComic.CardBuyerStock.finish(batch,true)")
        self.assertEqual(self.lua.eval('MetaComic.CardBuyerStock.population(card,meta)'),1)
        self.run_lua("for i=2,16 do local m=MetaComic.CopyTable(meta);m.instanceId='copy'..i;local b=MetaComic.CardBuyerStock.prepare('shop',{{meta=m,price=70}},1);MetaComic.CardBuyerStock.finish(b,true) end")
        self.assertEqual(self.lua.eval('MetaComic.CardBuyerStock.population(card,meta)'),16)
        self.assertEqual(self.price(),53)

    def test_manager_permission_distance_and_duty_are_required(self):
        self.stock();self.sale()
        self.run_lua("rows=MetaComic.CardBuyerStock.page('shop',1,20)")
        self.run_lua("events['meta_comic:server:retrieveBuyerCard'](1,rows[1].id,1)")
        self.assertEqual(self.lua.eval('returned'),0)
        self.run_lua("jobs[1]={name='cardshop',grade=2,onDuty=true};events['meta_comic:server:retrieveBuyerCard'](1,rows[1].id,1)")
        self.assertEqual(self.lua.eval('returned'),1)

    def test_rarity_and_odds_pricing_respect_bounds(self):
        self.assertEqual(self.price(),10)
        self.run_lua("card.rarityKey='legendary'")
        self.assertEqual(self.price(),1000)
        self.run_lua("card.rarityKey='rare';Config.CardBuyers.Pricing='rarity'")
        self.assertEqual(self.price(),505)
        self.run_lua("card.baseCardId='rare';card.variantId='foil';card.rarityKey='common';Config.CardBuyers.Pricing='odds'")
        self.assertEqual(self.price(),1000)

    def test_fixed_card_and_print_overrides_can_ignore_maximum(self):
        self.run_lua("Config.CardBuyers.FixedPricesEnabled=true;Config.CardBuyers.FixedPrices={one=1200,['one::base']=1500}")
        self.assertEqual(self.price(),1000)
        self.run_lua('Config.CardBuyers.FixedPricesIgnoreMaximum=true')
        self.assertEqual(self.price(),1500)
        self.run_lua('Config.CardBuyers.FixedPricesEnabled=false')
        self.assertEqual(self.price(),10)

    def test_manual_prints_rejected_unless_enabled(self):
        self.run_lua('meta.manualPrint=true')
        self.assertIsNone(self.price())
        self.run_lua('Config.CardBuyers.AcceptManualPrints=true')
        self.assertEqual(self.price(),10)

    def test_sale_consumes_exact_card_once(self):
        self.sale();self.sale()
        self.assertEqual(self.lua.eval('paid'),10)
        self.assertEqual(self.lua.eval('removed'),1)

    def test_distance_and_changed_card_or_price_reject(self):
        self.sale(1000);self.sale(instance='other')
        self.run_lua('positions[1]=vector3(100,0,0)');self.sale()
        self.assertEqual(self.lua.eval('removed'),0)

    def test_funded_sale_and_insufficient_funds(self):
        self.run_lua('Config.CardBuyers.RequireBusinessFunds=true;stored.shop=5')
        self.sale();self.assertEqual(self.lua.eval('removed'),0)
        self.run_lua('stored.shop=20');self.sale()
        self.assertEqual(self.lua.eval('stored.shop'),10)
        self.assertEqual(self.lua.eval('paid'),10)
        self.assertEqual(self.lua.eval('saves'),1)

    def test_failed_fund_save_returns_card_without_payment(self):
        self.run_lua('Config.CardBuyers.RequireBusinessFunds=true;failSave=true')
        self.sale()
        self.assertEqual(self.lua.eval('returned'),1)
        self.assertEqual(self.lua.eval('stored.shop'),1000)
        self.assertEqual(self.lua.eval('paid'),0)

    def test_failed_or_throwing_payment_refunds_card_and_business(self):
        for flag in ('failPay','throwPay'):
            with self.subTest(flag=flag):
                self.setUp();self.run_lua(f'Config.CardBuyers.RequireBusinessFunds=true;{flag}=true');self.sale()
                self.assertEqual(self.lua.eval('returned'),1)
                self.assertEqual(self.lua.eval('stored.shop'),1000)
                self.assertEqual(self.lua.eval('paid'),0)

    def test_failed_inventory_removal_never_charges_pool(self):
        self.run_lua('Config.CardBuyers.RequireBusinessFunds=true;failRemove=true');self.sale()
        self.assertEqual(self.lua.eval('stored.shop'),1000)
        self.assertEqual(self.lua.eval('saves'),0)

    def staff(self):
        self.run_lua("players={'2'};positions[2]=vector3(0,0,0);jobs[2]={name='cardshop',grade=0,onDuty=true}")

    def test_on_duty_employee_hides_ped_and_rejects_sale(self):
        self.staff();self.assertFalse(self.lua.eval('MetaComic.CardBuyers.available(buyer)'));self.sale()
        self.assertEqual(self.lua.eval('removed'),0)
        self.run_lua('jobs[2].onDuty=false');self.assertTrue(self.lua.eval('MetaComic.CardBuyers.available(buyer)'))
        self.run_lua('jobs[2].onDuty=true;positions[2]=vector3(30,0,0)')
        self.assertTrue(self.lua.eval('MetaComic.CardBuyers.available(buyer)'))

    def test_rotated_box_and_any_all_presence(self):
        self.staff()
        self.run_lua("buyer.Bounds={coords=vector3(20,0,0),size=vector3(8,2,4),heading=90};positions[2]=vector3(20,3,0)")
        self.assertFalse(self.lua.eval('MetaComic.CardBuyers.available(buyer)'))
        self.run_lua("buyer.PresenceMode='all'")
        self.assertTrue(self.lua.eval('MetaComic.CardBuyers.available(buyer)'))
        self.run_lua("buyer.Store=nil;positions[2]=vector3(23,0,0)")
        self.assertTrue(self.lua.eval('MetaComic.CardBuyers.available(buyer)'))

    def test_deposit_requires_employee_and_refunds_failed_save(self):
        self.run_lua("commands.fundcardbuyer(1,{'1','100'})")
        self.assertEqual(self.lua.eval('deposited'),0)
        self.run_lua("jobs[1]={name='cardshop',grade=0,onDuty=true};commands.fundcardbuyer(1,{'1','100'})")
        self.assertEqual(self.lua.eval('stored.shop'),1100)
        self.run_lua("failSave=true;commands.fundcardbuyer(1,{'1','100'})")
        self.assertEqual(self.lua.eval('stored.shop'),1100)
        self.assertEqual(self.lua.eval('paid'),100)

    def test_menu_uses_real_inventory_quotes(self):
        self.run_lua("events['meta_comic:server:cardBuyerMenu'](1)")
        self.assertEqual(self.lua.eval('menu[1].instanceId'),'i1')
        self.assertEqual(self.lua.eval('menu[1].price'),10)
        self.assertEqual(self.lua.eval('menu[1].slot'),4)

    def test_reentrant_sale_blocked_during_money_adapter(self):
        self.run_lua("MetaComic.Money.add=function(_,_,amount) events['meta_comic:server:sellTradingCard'](1,4,10,'i1');paid=paid+amount;return true end")
        self.sale()
        self.assertEqual(self.lua.eval('paid'),10)
        self.assertEqual(self.lua.eval('removed'),1)

    def test_client_lua_compiles(self):
        code=(ROOT/'fivem/client/card_buyers.lua').read_text(encoding='utf-8')
        self.assertIsNotNone(self.lua.eval('load')(code))

    def quote(self):
        self.run_lua("q=MetaComic.CardBuyers.ui(1,{index=1});cartPayload={token=q.token,refs={'hand:4'}}")

    def real_ox_adapter(self):
        # Exports return fresh nested tables across resource boundaries. Partial
        # matching compares nested table identities; strict matching compares values.
        self.run_lua('''
            MetaComic.InventoryAdapters={}
            function deepMatch(a,b)
                if type(a)~=type(b) then return false end
                if type(a)~='table' then return a==b end
                for k,v in pairs(a) do if not deepMatch(v,b[k]) then return false end end
                for k in pairs(b) do if a[k]==nil then return false end end
                return true
            end
            exports={ox_inventory={
                GetSlot=function(_,_,slot) return item and item.slot==slot and MetaComic.CopyTable(item) or nil end,
                Search=function(_,_,_,name) return name=='tradingcard' and item and {MetaComic.CopyTable(item)} or {} end,
                RemoveItem=function(_,_,name,count,m,slot,ignore,strict)
                    lastStrict=strict
                    if not item or item.slot~=slot or item.name~=name then return false end
                    if strict then if not deepMatch(item.metadata,m) then return false end
                    else for _,v in pairs(m) do if type(v)=='table' then return false end end end
                    removed=removed+1;item=nil;return true
                end,
            }}
        ''')
        self.lua.execute((ROOT/'fivem/server/adapters/inventory_ox.lua').read_text())
        self.run_lua('MetaComic.Inventory=MetaComic.InventoryAdapters.ox_inventory()')

    def test_real_ox_nested_metadata_sale_custom_and_fallback_icons(self):
        for picture in ['metacard_common','https://example.com/card.webp']:
            with self.subTest(picture=picture):
                self.setUp();self.real_ox_adapter()
                self.run_lua(f"meta.imageurl='{picture}';meta.cardSnapshot.condition={{corners={{front={{0.1,0,0,0}}}}}}")
                self.assertFalse(self.lua.eval('MetaComic.Inventory.remove(1,"tradingcard",1,MetaComic.CopyTable(meta),4)'))
                self.quote()
                self.assertTrue(self.lua.eval('MetaComic.CardBuyers.sellCart(1,cartPayload).ok'))
                self.assertTrue(self.lua.globals().lastStrict)
                self.assertEqual(self.lua.globals().paid,10)
                self.assertEqual(self.lua.globals().removed,1)

    def test_real_ox_single_card_menu_uses_exact_snapshot(self):
        self.real_ox_adapter();self.sale()
        self.assertEqual(self.lua.globals().paid,10)
        self.assertTrue(self.lua.globals().lastStrict)

    def test_exact_removal_rejects_wrong_slot_or_nested_identity(self):
        self.real_ox_adapter()
        self.assertFalse(self.lua.eval('MetaComic.Inventory.removeExact(1,"tradingcard",1,meta,5)'))
        self.run_lua('wrong=MetaComic.CopyTable(meta);wrong.cardSnapshot.title="Wrong"')
        self.assertFalse(self.lua.eval('MetaComic.Inventory.removeExact(1,"tradingcard",1,wrong,4)'))
        self.assertEqual(self.lua.globals().removed,0)

    def test_cart_quote_and_sale_are_single_use(self):
        self.quote()
        self.assertTrue(self.lua.eval('q.ok'))
        self.assertEqual(self.lua.eval('q.offers[1].price'),10)
        self.assertTrue(self.lua.eval('MetaComic.CardBuyers.sellCart(1,cartPayload).ok'))
        self.assertFalse(self.lua.eval('MetaComic.CardBuyers.sellCart(1,cartPayload).ok'))
        self.assertEqual(self.lua.eval('paid'),10)

    def test_cart_rejects_duplicates_changed_metadata_and_expired_quotes(self):
        self.quote();self.run_lua("cartPayload.refs={'hand:4','hand:4'}")
        self.assertFalse(self.lua.eval('MetaComic.CardBuyers.checkCart(1,cartPayload).ok'))
        self.run_lua("cartPayload.refs={'hand:4'};meta.protection='slab'")
        self.assertFalse(self.lua.eval('MetaComic.CardBuyers.sellCart(1,cartPayload).ok'))
        self.assertEqual(self.lua.eval('removed'),0)
        self.quote();self.run_lua("cartPayload.token='old'")
        self.assertFalse(self.lua.eval('MetaComic.CardBuyers.sellCart(1,cartPayload).ok'))

    def test_cart_rolls_back_partial_removal(self):
        self.quote()
        self.run_lua('''
            second={name='tradingcard',slot=5,metadata={instanceId='i2',cardSnapshot=card}}
            MetaComic.Inventory.slotsOf=function(_,name) if name=='tradingcard' then return {item,second} end;return {} end
            MetaComic.Inventory.getSlot=function(_,slot) return slot==4 and item or slot==5 and second end
            MetaComic.Inventory.remove=function(_,_,_,_,slot) if slot==5 then return false end;removed=removed+1;item=nil;return true end
            q=MetaComic.CardBuyers.ui(1,{index=1});cartPayload={token=q.token,refs={'hand:4','hand:5'}}
        ''')
        self.assertFalse(self.lua.eval('MetaComic.CardBuyers.sellCart(1,cartPayload).ok'))
        self.assertEqual(self.lua.eval('returned'),1)
        self.assertEqual(self.lua.eval('paid'),0)

    def test_cart_requires_budget_for_entire_batch_and_refunds_payment_failure(self):
        self.run_lua('Config.CardBuyers.RequireBusinessFunds=true;stored.shop=5');self.quote()
        self.assertFalse(self.lua.eval('MetaComic.CardBuyers.sellCart(1,cartPayload).ok'))
        self.run_lua('stored.shop=100;failPay=true');self.quote()
        self.assertFalse(self.lua.eval('MetaComic.CardBuyers.sellCart(1,cartPayload).ok'))
        self.assertEqual(self.lua.eval('stored.shop'),100)
        self.assertEqual(self.lua.eval('returned'),1)

    def test_cart_holder_ownership_and_container_slot_validation(self):
        self.run_lua('''
            Config.Items.Binder={'binder'};Config.Items.CardCase={'case'}
            holder={slot=6,name='binder',metadata={label='My binder'}}
            container={id='owned',slots=18,items={[4]=item}}
            MetaComic.Inventory.slotsOf=function(_,name) if name=='binder' then return {holder} end;return {} end
            MetaComic.Inventory.getContainer=function(_,slot) if holder and slot==6 then return container end end
            MetaComic.Inventory.getSlot=function(inv,slot) if inv=='owned' and slot==4 then return item end end
            q=MetaComic.CardBuyers.ui(1,{index=1});cartPayload={token=q.token,refs={'holder:6:4'}}
        ''')
        self.assertEqual(self.lua.eval('q.holders[1].kind'),'binder')
        self.assertTrue(self.lua.eval('MetaComic.CardBuyers.checkCart(1,cartPayload).ok'))
        self.run_lua('holder=nil')
        self.assertFalse(self.lua.eval('MetaComic.CardBuyers.sellCart(1,cartPayload).ok'))
        self.assertEqual(self.lua.eval('removed'),0)

    def test_cart_counter_bounds_reject_outside_and_employee_arrival(self):
        self.run_lua('buyer.SellArea={Bounds={coords=vector3(2,0,0),size=vector3(1,1,3)}}');self.quote()
        self.assertFalse(self.lua.eval('MetaComic.CardBuyers.checkCart(1,cartPayload).ok'))
        self.run_lua('positions[1]=vector3(2,0,0)')
        self.assertTrue(self.lua.eval('MetaComic.CardBuyers.checkCart(1,cartPayload).ok'))
        self.staff()
        self.assertFalse(self.lua.eval('MetaComic.CardBuyers.sellCart(1,cartPayload).ok'))

    def test_zone_adapters_can_register_switch_and_fail_closed(self):
        self.run_lua('exports=setmetatable({}, {__call=function(_,name,cb) exports[name]=cb end})')
        self.lua.execute((ROOT/'fivem/shared/card_buyer_zones.lua').read_text(encoding='utf-8'))
        self.run_lua("box={coords=vector3(0,0,0),size=vector3(2,2,2)}")
        self.assertTrue(self.lua.eval('MetaComic.CardBuyerZones.contains(vector3(0,0,0),box)'))
        self.run_lua("exports.RegisterCardBuyerZoneAdapter('custom',{contains=function() return false end});exports.UseCardBuyerZoneAdapter('custom')")
        self.assertFalse(self.lua.eval('MetaComic.CardBuyerZones.contains(vector3(0,0,0),box)'))
        self.run_lua("exports.RegisterCardBuyerZoneAdapter('custom',function() error('stopped') end)")
        self.assertFalse(self.lua.eval('MetaComic.CardBuyerZones.contains(vector3(0,0,0),box)'))

    def animation(self):
        self.run_lua('''
            clock=0;gestures=0;cleaned=0;deleted=0
            function GetGameTimer() return clock end
            function Wait() clock=clock+50 end
            function PlayerPedId() return 1 end
            function IsEntityDead() return false end
            function IsPedRagdoll() return interrupt and clock>100 or false end
            function IsPedInAnyVehicle() return false end
            function RequestAnimDict() end
            function HasAnimDictLoaded() return true end
            function GetAnimDuration() return 1 end
            function TaskPlayAnim() gestures=gestures+1 end
            function IsEntityPlayingAnim() return not stopAnimation end
            function DisableControlAction() end
            function IsControlJustPressed() return cancel and clock>100 or false end
            function SendNUIMessage() end
            function ClearPedTasks() cleaned=cleaned+1 end
            function joaat() return 1 end
            function RequestModel() end
            function HasModelLoaded() return true end
            function CreateObject() return 77 end
            function SetModelAsNoLongerNeeded() end
            function GetPedBoneIndex() return 1 end
            function AttachEntityToEntity() end
            function DoesEntityExist() return true end
            function DeleteEntity() deleted=deleted+1 end
            vec3=vector3
            area={Animation={dict='mp_common',clip='givetake1_a',Duration=850,
                Prop={model='custom-card',offset=vector3(0,0,0),rotation=vector3(0,0,0)}}}
        ''')
        self.lua.execute((ROOT/'fivem/client/card_buyers.lua').read_text(encoding='utf-8'))

    def test_counter_handover_deals_once_per_card_and_cleans_prop(self):
        self.animation()
        self.assertTrue(self.lua.eval('MetaComic.CardBuyerDeal(area,3)'))
        self.assertEqual(self.lua.eval('gestures'),3)
        self.assertEqual(self.lua.eval('deleted'),1)
        self.assertEqual(self.lua.eval('cleaned'),1)

    def test_counter_interruptions_cancel_without_inventory_changes(self):
        for flag in ('interrupt','cancel','stopAnimation'):
            with self.subTest(flag=flag):
                self.setUp();self.animation();self.run_lua(f'{flag}=true')
                self.assertFalse(self.lua.eval('MetaComic.CardBuyerDeal(area,3)'))
                self.assertEqual(self.lua.eval('gestures'),1)
                self.assertEqual(self.lua.eval('deleted'),1)
                self.assertEqual(self.lua.eval('removed'),0)
                self.assertEqual(self.lua.eval('paid'),0)
if __name__=='__main__': unittest.main()
