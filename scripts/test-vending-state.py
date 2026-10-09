"""Real normalized adapter with a transactional SQL fixture and real JSON round trips."""
from pathlib import Path
import copy
import json
import sys
import unittest
if len(sys.argv)>1: sys.path.insert(0,sys.argv.pop(1))
from lupa.lua54 import LuaRuntime,lua_type
ROOT=Path(__file__).resolve().parents[1]
QUEUE=(ROOT/'fivem/server/modules/runtime_saves.lua').read_text(encoding='utf-8')
STORE=(ROOT/'fivem/server/modules/vending_state.lua').read_text(encoding='utf-8')


class VendingStateTests(unittest.TestCase):
    def convert(self,value):
        if lua_type(value)!='table': return value
        items=dict(value.items())
        if items and set(items)==set(range(1,len(items)+1)):
            return [self.convert(items[i]) for i in range(1,len(items)+1)]
        return {str(k):self.convert(v) for k,v in items.items()}

    def query(self,sql,params):
        values=self.convert(params)
        if 'CREATE TABLE' in sql: return self.lua.table()
        if sql.startswith('DELETE FROM `goodluck_collectibles_settings`'):
            self.deleted_legacy=True;return 1
        if 'SELECT' in sql:
            bucket='entries' if 'vending_entries' in sql else 'state'
            rows=[]
            for identity,row in self.storage[bucket].items():
                if identity[0]==values[0]: rows.append(row)
            return self.lua.table_from(rows,recursive=True)
        raise AssertionError(sql)

    def transaction(self,statements):
        self.transactions+=1
        if self.fail: return False
        target=copy.deepcopy(self.storage)
        touched=[]
        for statement in self.convert(statements):
            sql,values=statement['query'],statement['values']
            bucket='entries' if 'vending_entries' in sql else 'state'
            insert=sql.startswith('INSERT')
            width=(6 if bucket=='entries' else 4) if insert else (5 if bucket=='entries' else 3)
            for index in range(0,len(values),width):
                row=values[index:index+width]
                if insert:
                    fields={'dataset':row[0],'section':row[1],'record_id':row[2],'data_json':row[-1]}
                    if bucket=='entries': fields.update(collection=row[3],position=row[4])
                    key=tuple(row[:-1]);target[bucket][key]=fields
                else:
                    key=tuple(row);target[bucket].pop(key,None)
                touched.append((bucket,key))
        self.storage=target;self.touched=touched
        return True

    def setUp(self):
        self.lua=LuaRuntime(unpack_returned_tuples=True)
        self.storage={'state':{},'entries':{}};self.transactions=0;self.fail=False;self.deleted_legacy=False;self.touched=[]
        self.lua.globals().encode=lambda value:json.dumps(self.convert(value),ensure_ascii=False,separators=(',',':'))
        self.lua.globals().decode=lambda raw:self.lua.table_from(json.loads(raw),recursive=True) if isinstance(json.loads(raw),(dict,list)) else json.loads(raw)
        self.lua.globals().sql_query=self.query;self.lua.globals().sql_transaction=self.transaction
        self.lua.execute('''
            Config={Database={Resource='oxmysql',AutoCreateSchema=true},RuntimeSaves={IntervalSeconds=30}}
            MetaComic={Persistence={name='mysql'},Settings={forget=function() forgotten=true end}}
            json={encode=encode,decode=decode};files={};handlers={}
            function GetCurrentResourceName() return 'cards' end
            function LoadResourceFile(_,file) return files[file] end
            function SaveResourceFile(_,file,data) files[file]=data;return true end
            function CreateThread() end
            function AddEventHandler(n,f) handlers[n]=f end
            function Wait() end
            function print() end
            exports={oxmysql={query_async=function(_,sql,params) return sql_query(sql,params) end,
                transaction_async=function(_,statements) return sql_transaction(statements) end}}
            legacy={people={owner={name='Owner',tax=10}},pending={owner=25},business={pending=100},serials={
                VM={serial='VM',owner='owner',history={{at=2,event='Open'},{at=1,event='Created'}},sales={{at=2,price=250}},
                    keyArchive={keys={{id='K1',access='full'}},cylinders={{id='C1',generation=1}}},
                    osBusinessSnapshot={history={{at=1,event='Created'}},keyArchive={keys={{id='K1'}},cylinders={{id='C1'}}}},
                    osArchives={{controller='other',history={{at=1,event='Old OS'}}}}}}}
        ''')
        self.lua.execute((ROOT/'fivem/shared/utils.lua').read_text(encoding='utf-8'))
        self.lua.execute(QUEUE);self.lua.execute(STORE)

    def test_scalar_balances_counters_and_collection_entries_survive_restart(self):
        self.lua.execute("legacy.serials.VM.tags={'pack',12,false,true};MetaComic.VendingState.load('vending_registry',legacy)")
        self.lua.execute(STORE)
        restored=self.convert(self.lua.eval("MetaComic.VendingState.load('vending_registry',nil)"))
        self.assertEqual(restored['pending']['owner'],25)
        self.assertEqual(restored['serials']['VM']['tags'],['pack',12,False,True])
        self.lua.execute("MetaComic.VendingState.load('vending_key_reports',{nextId=42,reports={}})")
        self.lua.execute(STORE)
        self.assertEqual(self.lua.eval("MetaComic.VendingState.load('vending_key_reports',nil).nextId"),42)

    def test_large_startup_load_yields_and_preserves_all_history(self):
        self.lua.execute("legacy.serials.VM.history={};for i=1,500 do legacy.serials.VM.history[i]={at=i,event='Event '..i} end;MetaComic.VendingState.load('vending_registry',legacy)")
        self.lua.execute(STORE)
        self.lua.execute("yieldCount=0;function Wait() yieldCount=yieldCount+1 end;restored=MetaComic.VendingState.load('vending_registry',nil)")
        self.assertGreaterEqual(self.lua.eval('yieldCount'),10)
        self.assertEqual(self.lua.eval('#restored.serials.VM.history'),500)
        self.assertEqual(self.lua.eval('restored.serials.VM.history[500].event'),'Event 500')

    def test_pending_runtime_values_accept_scalars_with_real_copy_helper(self):
        self.lua.execute("MetaComic.RuntimeSaves.mark('test','balance',25);MetaComic.RuntimeSaves.mark('test','enabled',false)")
        self.assertEqual(self.lua.eval("MetaComic.RuntimeSaves.pending('test').balance"),25)
        self.assertIs(self.lua.eval("MetaComic.RuntimeSaves.pending('test').enabled"),False)

    def test_migration_splits_nested_logs_and_archives_then_round_trips(self):
        original=self.convert(self.lua.eval('legacy'))
        self.lua.execute("data=MetaComic.VendingState.load('vending_registry',legacy)")
        self.assertTrue(self.deleted_legacy)
        self.assertIsNotNone(self.lua.eval("files['data/vending_registry-legacy-backup.json']"))
        machine=next(row for row in self.storage['state'].values() if row['section']=='machines')
        self.assertNotIn('Open',machine['data_json'])
        self.assertNotIn('Old OS',machine['data_json'])
        self.lua.execute(STORE)
        restored=self.convert(self.lua.eval("MetaComic.VendingState.load('vending_registry',nil)"))
        self.assertEqual(restored,original)

    def test_runtime_changes_coalesce_and_unchanged_rows_do_not_write(self):
        self.lua.execute("data=MetaComic.VendingState.load('vending_registry',legacy)")
        self.assertEqual(self.transactions,1)
        self.lua.execute("for n=1,10 do data.serials.VM.updatedAt=n;MetaComic.VendingState.stage('vending_registry',data) end")
        self.assertEqual(self.transactions,1)
        self.lua.execute('assert(MetaComic.RuntimeSaves.flush())')
        self.assertEqual(self.transactions,2)
        self.assertEqual(len(self.touched),1)
        self.lua.execute("MetaComic.VendingState.stage('vending_registry',data);assert(MetaComic.RuntimeSaves.flush())")
        self.assertEqual(self.transactions,2)

    def test_failed_migration_keeps_legacy_and_retry_succeeds(self):
        self.fail=True
        ok=self.lua.execute("return pcall(MetaComic.VendingState.load,'vending_registry',legacy)")[0]
        self.assertFalse(ok);self.assertFalse(self.deleted_legacy)
        self.assertEqual(len(self.storage['state']),0)
        self.fail=False
        self.lua.execute("assert(MetaComic.VendingState.load('vending_registry',legacy))")
        self.assertTrue(self.deleted_legacy)

    def test_report_snapshots_store_individually_with_separate_archive_entries(self):
        self.lua.execute("reports=MetaComic.VendingState.load('vending_key_reports',{nextId=1,reports={R1={serial='VM',archive={keys={{id='K1'}},cylinders={{id='C1'}}}}}});reports.nextId=2;reports.reports.R2={serial='VM',archive={keys={{id='K2'}},cylinders={{id='C2'}}}};assert(MetaComic.VendingState.saveNow('vending_key_reports',reports))")
        self.lua.execute(STORE)
        self.assertEqual(self.lua.eval("MetaComic.VendingState.load('vending_key_reports',nil).reports.R1.archive.keys[1].id"),'K1')
        self.assertEqual(self.lua.eval("MetaComic.VendingState.load('vending_key_reports',nil).reports.R2.archive.keys[1].id"),'K2')

    def test_shutdown_recovers_pending_normalized_state_without_old_blob(self):
        self.lua.execute("data=MetaComic.VendingState.load('vending_registry',legacy);data.business.pending=17;MetaComic.VendingState.stage('vending_registry',data)")
        self.fail=True;self.lua.execute("handlers.onResourceStop('cards')")
        self.lua.execute(QUEUE);self.lua.execute(STORE)
        self.assertEqual(self.lua.eval("MetaComic.VendingState.load('vending_registry',nil).business.pending"),17)
        self.fail=False;self.lua.execute('assert(MetaComic.RuntimeSaves.flush())')
        self.lua.execute(STORE)
        self.assertEqual(self.lua.eval("MetaComic.VendingState.load('vending_registry',nil).business.pending"),17)

    def test_real_registry_logs_use_queue_and_normalized_rows(self):
        self.lua.execute('MetaComic.Settings.get=function() return legacy end')
        self.lua.execute((ROOT/'fivem/server/modules/vending_registry.lua').read_text(encoding='utf-8'))
        self.lua.execute("assert(MetaComic.VendingRegistry.get('VM'));MetaComic.VendingRegistry.update('VM',{lockCondition='damaged'},'New sensor event','Owner')")
        self.assertEqual(self.transactions,1)  # migration only; runtime mutation remains in memory
        self.lua.execute('assert(MetaComic.RuntimeSaves.flush())')
        self.assertEqual(self.transactions,2)
        self.lua.execute(STORE)
        self.assertEqual(self.lua.eval("MetaComic.VendingState.load('vending_registry',nil).serials.VM.history[1].event"),'New sensor event')


if __name__=='__main__': unittest.main()
