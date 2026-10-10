"""Run actual restock batches: preflight, timing, partial completion, rechecks and cancellation."""
from pathlib import Path
import sys
import unittest
if len(sys.argv) > 1:
    sys.path.insert(0, sys.argv.pop(1))
else:
    sys.path.insert(0, str(Path(__file__).resolve().parents[1] / '.tmp-mysql-tests'))
from lupa.lua54 import LuaRuntime
ROOT=Path(__file__).resolve().parents[1]

class RestockTests(unittest.TestCase):
    def setUp(self):
        self.lua=LuaRuntime(unpack_returned_tuples=True)
        self.lua.execute('''
            cfg={Work={Enabled=true,Restock={PackBatch=2,BoxBatch=1,BaseMs=2000,PerUnitMs=1500,MaxMs=45000,FullStockMs=0}}}
            Config={Items={BoosterPack='pack',BoosterBox='box'}}
            source=1;timer=1000;ready=true;held=10;room=100;notices={};messages={};clientEvents={};handlers={};events={};saves=0;broadcasts=0;accounted=0
            entry={id=1,serial='serial',products={{set='base',kind='pack',stock=0}}};machines={[1]=entry};stockTransfers={}
            MetaComic={Inventory={slotsOf=function(_,item) return {{slot=4,count=held,metadata={setId=inventorySet or 'base'}}} end,
                remove=function(_,_,count) if failRemove then return false end;held=held-count;return true end},
                Sets={defaultId=function() return 'base' end},
                GiveSealed=function(_,_,_,count) held=held+count;return true end}
            Registry={sensor=function() end}
            function RegisterNetEvent(n,f) handlers[n]=f end;function AddEventHandler(n,f) events[n]=f end
            function TriggerClientEvent(name,_,data) clientEvents[#clientEvents+1]={name=name,data=data,stock=entry.products[1].stock};if name=='meta_comic:client:vendingWork' then messages[#messages+1]=data end end
            function TriggerEvent() end;function GetGameTimer() return timer end
            function notify(_,message) notices[#notices+1]=message end
            function canRestock() return not closed and not expiredAccess end
            function near() return not far end;function interactReach() return 2 end
            function sealedText() return sealed and 'sealed' end
            function findProduct(e,set,kind) if e.products[1].set==set and e.products[1].kind==kind then return e.products[1] end end
            function kindOf(v) return v=='box' and 'box' or 'pack' end
            function kindLabel(v) return v=='box' and 'box' or 'pack' end
            function getSet(id) return {name=id} end
            function maxStockOf() return room end
            function whole(value,min,max) local n=tonumber(value);return n and n%1==0 and n>=min and n<=max and n or nil end
            function saveProducts() saves=saves+1;return not failSave end
            function accountChange(_,_,count) accounted=accounted+count end
            function broadcast() broadcasts=broadcasts+1 end
            function ownerAction() cashFinished=true end
            function GetConvarInt(_,fallback) return fallback end
        ''')
        self.lua.execute((ROOT/'fivem/shared/utils.lua').read_text())
        code=(ROOT/'fivem/server/modules/vending_machines.lua').read_text()
        declarations=code[code.index('local startWork --'):code.index('-- Owner actions:',code.index('local startWork --'))]
        section=code[code.index('-- The player\'s inventory slots holding sealed'):code.index('-- Buying ---')]
        self.lua.execute(declarations+section+'\nworkIsBusy=workBusy')

    def start(self,count=5,kind='pack'):
        self.lua.execute(f"handlers['meta_comic:server:vendingRestock'](1,'base','{kind}',{count})")

    def finish(self):
        self.lua.execute("local data=messages[#messages];timer=timer+data.duration;handlers['meta_comic:server:vendingWorkFinish'](data.token)")

    def test_rejects_full_requested_amount_before_any_animation(self):
        self.lua.execute('held=4');self.start(5)
        self.assertEqual(len(self.lua.globals().messages),0)
        self.assertIn('you have 4',self.lua.globals().notices[1])
        self.assertEqual(self.lua.globals().held,4)

    def test_pack_batches_commit_live_stock_and_final_remainder(self):
        self.start(5)
        self.assertEqual(self.lua.globals().messages[1].duration,5000)
        self.assertEqual(self.lua.eval('entry.products[1].stock'),0)
        self.finish();self.assertEqual(self.lua.eval('entry.products[1].stock'),2)
        self.finish();self.assertEqual(self.lua.eval('entry.products[1].stock'),4)
        self.assertEqual(self.lua.globals().messages[3].duration,3500)
        self.finish();self.assertEqual(self.lua.eval('entry.products[1].stock'),5)
        self.assertEqual(self.lua.globals().held,5)
        self.assertEqual(self.lua.globals().accounted,5)
        self.assertEqual(self.lua.globals().broadcasts,3)
        self.assertFalse(self.lua.eval('workIsBusy(entry)'))

    def test_menu_refresh_waits_for_full_run_and_uses_final_stock(self):
        self.start(5)
        self.assertEqual(self.lua.eval("#clientEvents"), 1)
        self.finish();self.finish()
        self.assertEqual(self.lua.eval("#clientEvents"), 3)
        self.finish()
        self.assertEqual(self.lua.eval("clientEvents[#clientEvents-1].name"), 'meta_comic:client:vendingWorkStop')
        self.assertEqual(self.lua.eval("clientEvents[#clientEvents].name"), 'meta_comic:client:vendingMenuRefresh')
        self.assertEqual(self.lua.eval("clientEvents[#clientEvents].stock"), 5)

    def test_rejection_cancellation_and_untimed_completion_refresh_menu(self):
        self.lua.execute('held=1');self.start(5)
        self.assertEqual(self.lua.eval("clientEvents[#clientEvents].name"), 'meta_comic:client:vendingMenuRefresh')
        self.lua.execute('held=10;clientEvents={}');self.start(5);self.finish()
        self.lua.execute("handlers['meta_comic:server:vendingWorkCancel'](messages[#messages].token)")
        self.assertEqual(self.lua.eval("clientEvents[#clientEvents].name"), 'meta_comic:client:vendingMenuRefresh')
        self.assertEqual(self.lua.eval("clientEvents[#clientEvents].stock"), 2)
        self.lua.execute('cfg.Work.Enabled=false;clientEvents={}');self.start(3)
        self.assertEqual(self.lua.eval("clientEvents[#clientEvents].name"), 'meta_comic:client:vendingMenuRefresh')
        self.assertEqual(self.lua.eval("clientEvents[#clientEvents].stock"), 5)

    def test_configurable_box_batches(self):
        self.lua.execute("entry.products[1].kind='box';cfg.Work.Restock.BoxBatch=2")
        self.start(3,'box');self.finish()
        self.assertEqual(self.lua.eval('entry.products[1].stock'),2)
        self.finish();self.assertEqual(self.lua.eval('entry.products[1].stock'),3)
        self.assertEqual(len(self.lua.globals().messages),2)

    def test_full_capacity_total_time_cap_for_packs_and_boxes(self):
        for kind,capacity in [('pack',100),('box',20)]:
            for cap in (30000,15000):
                self.setUp()
                self.lua.execute(f"room={capacity};held={capacity};entry.products[1].kind='{kind}';cfg.Work.Restock.FullStockMs={cap}")
                self.start(capacity,kind)
                while self.lua.eval('workIsBusy(entry)'):
                    self.finish()
                self.assertLessEqual(sum(d.duration for d in self.lua.globals().messages.values()),cap)
                self.assertEqual(self.lua.eval('entry.products[1].stock'),capacity)

    def test_cancel_keeps_completed_batches_and_ignores_stale_tokens(self):
        self.start();self.finish()
        self.lua.execute("handlers['meta_comic:server:vendingWorkCancel'](messages[1].token)")
        self.assertTrue(self.lua.eval('workIsBusy(entry)'))
        self.lua.execute("handlers['meta_comic:server:vendingWorkCancel'](messages[2].token);timer=timer+5000;handlers['meta_comic:server:vendingWorkFinish'](messages[2].token)")
        self.assertEqual(self.lua.eval('entry.products[1].stock'),2)
        self.assertEqual(self.lua.globals().held,8)
        self.assertFalse(self.lua.eval('workIsBusy(entry)'))

    def test_expired_batch_cannot_commit(self):
        self.start()
        self.lua.execute("local data=messages[1];timer=timer+data.duration+10000;handlers['meta_comic:server:vendingWorkFinish'](data.token)")
        self.assertEqual(self.lua.eval('entry.products[1].stock'), 0)
        self.assertEqual(self.lua.eval('held'), 10)

    def test_cannot_complete_early_or_replay(self):
        self.start()
        self.lua.execute("handlers['meta_comic:server:vendingWorkFinish']('wrong')")
        self.assertTrue(self.lua.eval('workIsBusy(entry)'))
        self.lua.execute("timer=timer+4999;handlers['meta_comic:server:vendingWorkFinish'](messages[1].token)")
        self.assertEqual(self.lua.globals().held,10)
        self.assertEqual(self.lua.eval('entry.products[1].stock'),0)

    def test_rechecks_inventory_access_and_capacity_before_commit(self):
        for change in ['held=1','closed=true','expiredAccess=true','room=1','failRemove=true','failSave=true']:
            with self.subTest(change=change):
                self.setUp();self.start();self.lua.execute(change);before=self.lua.globals().held;self.finish()
                self.assertEqual(self.lua.eval('entry.products[1].stock'),0)
                self.assertEqual(self.lua.globals().held,before)
                self.assertEqual(len(self.lua.globals().messages),1)

    def test_wrong_set_and_other_restockers_blocked(self):
        self.lua.execute("inventorySet='other'");self.start()
        self.assertEqual(len(self.lua.globals().messages),0)
        self.lua.execute('inventorySet=nil');self.start()
        self.lua.execute("source=2;handlers['meta_comic:server:vendingRestock'](1,'base','pack',2)")
        self.assertEqual(len(self.lua.globals().messages),1)

    def test_disabled_work_loads_immediately_after_preflight(self):
        self.lua.execute('cfg.Work.Enabled=false');self.start()
        self.assertEqual(len(self.lua.globals().messages),0)
        self.assertEqual(self.lua.eval('entry.products[1].stock'),5)

if __name__=='__main__':unittest.main()
