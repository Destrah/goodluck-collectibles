"""Actual queue and adapters: coalescing, memory reads, failures, yielding saves and shutdown recovery."""
from pathlib import Path
import sys
import unittest
if len(sys.argv)>1: sys.path.insert(0,sys.argv.pop(1))
from lupa.lua54 import LuaRuntime
ROOT=Path(__file__).resolve().parents[1]
QUEUE=(ROOT/'fivem/server/modules/runtime_saves.lua').read_text(encoding='utf-8')


class RuntimeSaveTests(unittest.TestCase):
    def setUp(self):
        self.lua=LuaRuntime(unpack_returned_tuples=True)
        self.lua.execute('''
            Config={RuntimeSaves={IntervalSeconds=30},Database={Resource='oxmysql'}}
            MetaComic={Persistence={name='mysql'}}
            function MetaComic.CopyTable(value)
                if type(value)~='table' then return value end
                local copy={};for k,v in pairs(value) do copy[k]=MetaComic.CopyTable(v) end;return copy
            end
            files={};encoded={};encodeId=0;threads={};handlers={};writes=0;dbwrites=0
            json={encode=function(value) encodeId=encodeId+1;local id='json'..encodeId;encoded[id]=MetaComic.CopyTable(value);return id end,
                decode=function(id) if not encoded[id] then error('missing') end;return MetaComic.CopyTable(encoded[id]) end}
            function GetCurrentResourceName() return 'cards' end
            function LoadResourceFile(_,file) return files[file] end
            function SaveResourceFile(_,file,value) files[file]=value;return true end
            function CreateThread(fn) threads[#threads+1]=coroutine.create(fn) end
            function AddEventHandler(name,fn) handlers[name]=fn end
            function Wait() if coroutine.isyieldable() then coroutine.yield() end end
            function print() end
            exports={oxmysql={query_async=function(_,sql,params)
                if sql:find('SELECT') then return {} end
                dbwrites=dbwrites+1;lastParams=params
                if dbYield then Wait(0) end
                if dbFail then return nil end
                return 1
            end}}
        ''')
        self.lua.execute(QUEUE)

    def test_many_updates_are_one_write_and_periodic_thread_flushes(self):
        self.lua.execute("MetaComic.RuntimeSaves.register('state',function(_,data) writes=writes+1;latest=data.amount;return true end);for n=1,20 do MetaComic.RuntimeSaves.mark('state',1,{amount=n}) end")
        self.assertEqual(self.lua.eval('writes'),0)
        self.lua.execute('assert(coroutine.resume(threads[1]));assert(coroutine.resume(threads[1]))')
        self.assertEqual(self.lua.eval('writes'),1)
        self.assertEqual(self.lua.eval('latest'),20)

    def test_change_during_yielding_write_stays_pending(self):
        self.lua.execute("MetaComic.RuntimeSaves.register('state',function(_,data) writes=writes+1;latest=data.amount;Wait(0);return true end);MetaComic.RuntimeSaves.mark('state',1,{amount=1});job=coroutine.create(MetaComic.RuntimeSaves.flush);assert(coroutine.resume(job));MetaComic.RuntimeSaves.mark('state',1,{amount=2});assert(coroutine.resume(job))")
        self.assertEqual(self.lua.eval("MetaComic.RuntimeSaves.pending('state')['1'].amount"),2)
        self.lua.execute('job=coroutine.create(MetaComic.RuntimeSaves.flush);assert(coroutine.resume(job));assert(coroutine.resume(job))')
        self.assertEqual(self.lua.eval('latest'),2)
        self.assertIsNone(self.lua.eval("next(MetaComic.RuntimeSaves.pending('state'))"))

    def test_failed_database_save_retries_latest_state(self):
        self.lua.execute("fail=true;MetaComic.RuntimeSaves.register('state',function() writes=writes+1;return not fail end);MetaComic.RuntimeSaves.mark('state',1,{amount=9});assert(not MetaComic.RuntimeSaves.flush());fail=false;assert(MetaComic.RuntimeSaves.flush())")
        self.assertEqual(self.lua.eval('writes'),2)
        self.assertIsNone(self.lua.eval("next(MetaComic.RuntimeSaves.pending('state'))"))

    def test_stop_checkpoints_without_database_callback_and_replays_on_restart(self):
        self.lua.execute("MetaComic.RuntimeSaves.register('state',function() error('No database calls during stop') end);MetaComic.RuntimeSaves.mark('state',1,{amount=9});handlers.onResourceStop('cards')")
        self.assertIsNotNone(self.lua.eval("files['data/runtime-pending.json']"))
        self.lua.execute(QUEUE)  # previous coroutine never completed: mimic host shutting down
        self.assertEqual(self.lua.eval("MetaComic.RuntimeSaves.pending('state')['1'].amount"),9)
        self.lua.execute("MetaComic.RuntimeSaves.discard('state',1)")
        self.lua.execute(QUEUE)
        self.assertIsNone(self.lua.eval("next(MetaComic.RuntimeSaves.pending('state'))"))

    def test_settings_stage_is_immediate_in_memory_and_writes_only_on_flush(self):
        self.lua.execute((ROOT/'fivem/server/modules/settings.lua').read_text(encoding='utf-8'))
        self.lua.execute("assert(MetaComic.Settings.stage('vending_registry',{cash=100}));assert(MetaComic.Settings.stage('vending_registry',{cash=50}))")
        self.assertEqual(self.lua.eval('dbwrites'),0)
        self.assertEqual(self.lua.eval("MetaComic.Settings.get('vending_registry').cash"),50)
        self.lua.execute('assert(MetaComic.RuntimeSaves.flush())')
        self.assertEqual(self.lua.eval('dbwrites'),1)
        self.lua.execute("assert(MetaComic.Settings.stage('recipes',{n=1}));assert(MetaComic.Settings.set('recipes',{n=2}));assert(MetaComic.RuntimeSaves.flush())")
        self.assertEqual(self.lua.eval("MetaComic.Settings.get('recipes').n"),2)
        self.assertEqual(self.lua.eval('dbwrites'),2)  # explicit save supersedes its older queued version

    def test_machine_save_updates_memory_without_per_batch_sql(self):
        code=(ROOT/'fivem/server/modules/vending_machines.lua').read_text(encoding='utf-8')
        section=code.split('local function saveEntry(entry)',1)[1].split('local function index(entry)',1)[0]
        self.lua.execute('''
            useMysql=true;tableName='machines';ready=true;machines={[1]={serial='VM'}}
            function accounting() end
            function metaOf(entry) return json.encode({serial=entry.serial,cash=entry.cash}) end
            function db() return exports.oxmysql end
        ''')
        self.lua.execute('local function saveEntry(entry)' + section + '\nSaveEntry=saveEntry')
        self.lua.execute("entry={id=1,serial='VM',products={{set='base',kind='pack',stock=3}},cash=100,x=1,y=2,z=3,h=4};assert(SaveEntry(entry));entry.products[1].stock=2;assert(SaveEntry(entry));entry.products[1].stock=0;assert(SaveEntry(entry))")
        self.assertEqual(self.lua.eval('dbwrites'),0)
        self.lua.execute('assert(MetaComic.RuntimeSaves.flush())')
        self.assertEqual(self.lua.eval('dbwrites'),1)
        self.assertEqual(self.lua.eval('json.decode(lastParams[1])[1].stock'),0)

    def test_settings_restart_recovers_pending_value_after_failed_shutdown_flush(self):
        settings=(ROOT/'fivem/server/modules/settings.lua').read_text(encoding='utf-8')
        self.lua.execute(settings)
        self.lua.execute("assert(MetaComic.Settings.stage('vending_registry',{cash=42}));dbFail=true;handlers.onResourceStop('cards')")
        self.lua.execute(QUEUE)
        self.lua.execute(settings)
        self.assertEqual(self.lua.eval("MetaComic.Settings.get('vending_registry').cash"),42)
        self.lua.execute('dbFail=false;assert(MetaComic.RuntimeSaves.flush())')
        self.assertEqual(self.lua.eval('json.decode(lastParams[2]).cash'),42)

    def test_stage_during_explicit_save_remains_latest_in_memory_and_pending(self):
        self.lua.execute((ROOT/'fivem/server/modules/settings.lua').read_text(encoding='utf-8'))
        self.lua.execute("assert(MetaComic.Settings.stage('state',{n=1}));dbYield=true;job=coroutine.create(function() assert(MetaComic.Settings.set('state',{n=2})) end);assert(coroutine.resume(job));assert(MetaComic.Settings.stage('state',{n=3}));assert(coroutine.resume(job))")
        self.assertEqual(self.lua.eval("MetaComic.Settings.get('state').n"),3)
        self.lua.execute('dbYield=false;assert(MetaComic.RuntimeSaves.flush())')
        self.assertEqual(self.lua.eval('json.decode(lastParams[2]).n'),3)


if __name__=='__main__': unittest.main()
