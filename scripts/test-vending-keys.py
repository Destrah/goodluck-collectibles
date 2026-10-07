"""Run real Lua modules: keys, cylinder rotation, permanent evidence, seals and stale actions.
Usage: python scripts/test-vending-keys.py [directory containing lupa]
"""
from pathlib import Path
import importlib.util
import sys
import unittest

if len(sys.argv) > 1:
    sys.path.insert(0, sys.argv.pop(1))
ROOT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location('fixtures', ROOT / 'scripts/test-vending-security.py')
fixtures = importlib.util.module_from_spec(spec)
spec.loader.exec_module(fixtures)


class KeyTests(unittest.TestCase):
    def setUp(self):
        fixtures.SecurityTests.setUp(self)
        self.lua.execute('vec3=vector3')
        self.lua.execute((ROOT / 'fivem/config.lua').read_text(encoding='utf-8'))
        self.lua.execute('''
            handlers={};commands={};events={};bags={};timer=0;source=11;opened=0;cylinders=10
            entry.products={{set='test',kind='pack',stock=3}};entry.cash=300
            function RegisterNetEvent(name,fn) handlers[name]=fn end
            function RegisterCommand(name,fn) commands[name]=fn end
            function AddEventHandler() end
            function GetGameTimer() return timer end
            function GetEntityHealth() return 200 end
            function TriggerClientEvent(name,src,data)
                events[#events+1]={name=name,src=src,data=MetaComic.CopyTable(data)}
                if name=='meta_comic:client:crimeStart' or name=='meta_comic:client:vendingRekeyStart' then startData=data end
                if name=='meta_comic:client:vendingRecord' then viewed=data end
            end
            latent=0
            function TriggerLatentClientEvent(name,src,bps,data) latent=latent+1;TriggerClientEvent(name,src,data) end
            MetaComic.Vending.get=function(id) return tonumber(id)==1 and entry or nil end
            MetaComic.Vending.near=function() return not farAway end
            MetaComic.Vending.reach=function() return 2 end
            MetaComic.Vending.canManage=function(src) return src==44 end
            MetaComic.Vending.sendAccessAll=function() end
            MetaComic.Vending.isTransferringStock=function() return transferring==true end
            MetaComic.Vending.openManage=function() opened=opened+1 end
            MetaComic.Vending.save=function() return true end
            MetaComic.Vending.giveSealed=function() return true end
            MetaComic.Police.isPolice=function(src) return src==55 end
            MetaComic.Police.count=function() return 0 end
            MetaComic.RpcHandlers={}
            MetaComic.Settings.get=function(key) if key=='vending_key_reports' then return savedReports end;return records end
            MetaComic.Settings.set=function(key,value) if not saveOK then return false end;if key=='vending_key_reports' then savedReports=MetaComic.CopyTable(value) end;return true end
            MetaComic.Inventory.slotsOf=function(src,name)
                local found={};for _,item in pairs(bags[src] or {}) do if item.name==name then found[#found+1]=item end end;return found
            end
            MetaComic.Inventory.getSlot=function(src,slot) return (bags[src] or {})[slot] end
            MetaComic.Inventory.count=function(src,name) if name=='vending_lock_cylinder' then return cylinders end;return 100 end
            MetaComic.Inventory.remove=function(src,name)
                if name=='vending_lock_cylinder' then if cylinders<=0 then return false end;cylinders=cylinders-1 end;return true
            end
            MetaComic.Inventory.add=function(src,name,count,metadata)
                if addFail then return false end
                if name=='vending_lock_cylinder' then cylinders=cylinders+count;return true end
                bags[src]=bags[src] or {};local slot=#bags[src]+1
                bags[src][slot]={slot=slot,name=name,count=count,metadata=MetaComic.CopyTable(metadata)};return true
            end
        ''')
        for name in ('vending_keys', 'vending_records', 'vending_loot', 'vending_crime'):
            self.lua.execute((ROOT / f'fivem/server/modules/{name}.lua').read_text(encoding='utf-8'))
        self.lua.execute('Keys=MetaComic.VendingKeys;assert(Keys.ensure(record))')

    def issue(self, target=11, access='full'):
        self.assertTrue(self.lua.execute(f"return Keys.issue(44,'VM-1',{target},'{access}')"))

    def unlock(self, target=11):
        self.lua.execute(f'Keys.unlock({target},entry)')

    def replace(self, target=11):
        self.lua.execute(f"source={target};handlers['meta_comic:server:vendingRekeyStart'](1);timer=timer+60000;handlers['meta_comic:server:vendingRekeyFinish'](startData.token)")

    def load_management_handlers(self):
        self.lua.execute('''
            Registry=MetaComic.VendingRegistry;ready=true;machines={[1]=entry};stockTransfers={};given=0;pickups=0
            MAX_PRICE=10000000;MAX_PRODUCTS=30;own={};shop={}
            function notify() end
            function near() return not farAway end
            function interactReach() return 2 end
            function canManage(src) return src==44 end
            function canControl(src) return src==11 or src==44 end
            function controls(src) return src==11 end
            function cabinetAccess(src,e,level) return Keys.access(src,e,level) end
            function recordOf() return record end
            function playerName(src) return Registry.nameOf(src) end
            function playerId(src) return Registry.identifierOf(src) end
            function kindOf(kind) return kind=='box' and 'box' or 'pack' end
            function getSet(id) return {id=id} end
            function findProduct(e) return e.products[1],1 end
            function whole(value,min,max) local n=tonumber(value);return n and n>=min and n<=max and math.floor(n) or nil end
            function saveProducts() if revokeOnSave then bags[source]={} end;return true end
            saveEntry=saveProducts
            function broadcast() end
            function openManage() end
            function sendAccessAll() end
            function pickUp() pickups=pickups+1;return true end
            MetaComic.GiveSealed=function(_,_,_,amount) given=given+amount;return true end
        ''')
        code = (ROOT / 'fivem/server/modules/vending_machines.lua').read_text(encoding='utf-8')
        product = 'local function withdrawStock' + code.split('local function withdrawStock', 1)[1].split('-- Owner actions:', 1)[0]
        owner = "RegisterNetEvent('meta_comic:server:vendingOwner'" + code.split("RegisterNetEvent('meta_comic:server:vendingOwner'", 1)[1].split('-- Map of every machine', 1)[0]
        self.lua.execute(product)
        self.lua.execute(owner)

    def test_direct_management_events_reject_no_key_and_service_cash_or_stock(self):
        self.load_management_handlers()
        self.lua.execute("handlers['meta_comic:server:vendingProduct'](1,'price',{set='test',price=123})")
        self.assertIsNone(self.lua.eval('entry.products[1].price'))
        self.issue(access='service'); self.unlock()
        self.lua.execute("handlers['meta_comic:server:vendingProduct'](1,'price',{set='test',price=123});handlers['meta_comic:server:vendingProduct'](1,'withdraw',{set='test',amount=1});handlers['meta_comic:server:vendingOwner'](1,'collect')")
        self.assertEqual(self.lua.eval('entry.products[1].price'), 123)
        self.assertEqual(self.lua.eval('given'), 0)
        self.assertEqual(self.lua.eval('paid'), 0)
        self.assertEqual(self.lua.eval('entry.cash'), 300)

    def test_full_key_allows_cash_and_stock_but_does_not_change_owner(self):
        self.load_management_handlers()
        self.issue(target=22); self.unlock(22)
        self.lua.execute("source=22;handlers['meta_comic:server:vendingOwner'](1,'collect');handlers['meta_comic:server:vendingProduct'](1,'withdraw',{set='test',amount=1});handlers['meta_comic:server:vendingOwner'](1,'pickup')")
        self.assertEqual(self.lua.eval('paid'), 300)
        self.assertEqual(self.lua.eval('given'), 1)
        self.assertEqual(self.lua.eval('pickups'), 1)
        self.assertEqual(self.lua.eval('record.owner'), 'owner')

    def test_key_removed_during_cash_or_stock_save_rolls_back(self):
        self.load_management_handlers()
        self.issue(); self.unlock()
        self.lua.execute("revokeOnSave=true;handlers['meta_comic:server:vendingOwner'](1,'collect')")
        self.assertEqual(self.lua.eval('paid'), 0)
        self.assertEqual(self.lua.eval('entry.cash'), 300)
        self.issue(); self.unlock()
        self.lua.execute("handlers['meta_comic:server:vendingProduct'](1,'withdraw',{set='test',amount=1})")
        self.assertEqual(self.lua.eval('given'), 0)
        self.assertEqual(self.lua.eval('entry.products[1].stock'), 3)

    def test_full_key_cannot_reset_routing_or_assign_owner(self):
        self.load_management_handlers()
        self.issue(target=22); self.unlock(22)
        self.lua.execute("source=22;record.tampered=true;record.routing={id='hacker'};handlers['meta_comic:server:vendingOwner'](1,'resetRouting');handlers['meta_comic:server:vendingOwner'](1,'assign',{owner='business'})")
        self.assertTrue(self.lua.eval('record.tampered'))
        self.assertEqual(self.lua.eval('record.owner'), 'owner')

    def test_old_key_and_malformed_archive_cannot_unlock_or_erase_evidence(self):
        self.issue(); self.replace()
        self.lua.execute('record.lockId=nil')
        self.assertFalse(self.lua.eval('Keys.ensure(record)'))
        self.assertEqual(self.lua.eval('#record.keyArchive.cylinders'), 2)

    def test_new_lua_files_compile(self):
        for path in ('server/modules/vending_keys.lua', 'client/vending_keys.lua', 'server/modules/vending_records.lua', 'server/modules/vending_loot.lua', 'server/modules/vending_crime.lua'):
            result = self.lua.eval('load')((ROOT / 'fivem' / path).read_text(encoding='utf-8'))
            self.assertFalse(isinstance(result, tuple), f'{path}: {result}')

    def test_service_full_and_current_inventory_are_checked(self):
        self.issue(access='service')
        self.unlock()
        self.assertTrue(self.lua.eval("Keys.access(11,entry,'service')"))
        self.assertFalse(self.lua.eval("Keys.access(11,entry,'full')"))
        self.lua.execute('bags[11]={}')
        self.assertFalse(self.lua.eval("Keys.access(11,entry,'service')"))
        self.issue(access='full')
        self.unlock()
        self.assertTrue(self.lua.eval("Keys.access(11,entry,'full')"))

    def test_key_ownership_is_physical_but_does_not_grant_rekey_authority(self):
        self.issue()
        self.lua.execute('bags[22]=bags[11];bags[11]={}')
        self.unlock(22)
        self.assertTrue(self.lua.eval("Keys.access(22,entry,'full')"))
        self.assertFalse(self.lua.eval('Keys.authority(22,record)'))
        self.lua.execute("source=22;handlers['meta_comic:server:vendingRekeyStart'](1)")
        self.assertIsNone(self.lua.eval('startData'))

    def test_only_business_issues_general_keys(self):
        self.assertFalse(self.lua.execute("return Keys.issue(11,'VM-1',11,'full')")[0])
        self.assertFalse(self.lua.execute("return Keys.issue(44,'VM-1',11,'master')")[0])

    def test_expiry_distance_and_manual_lock_revoke_sessions(self):
        self.issue(); self.unlock()
        self.lua.execute('farAway=true')
        self.assertFalse(self.lua.eval("Keys.access(11,entry,'full')"))
        self.lua.execute('farAway=false;now=1301')
        self.assertFalse(self.lua.eval("Keys.access(11,entry,'full')"))
        self.unlock()
        self.lua.execute("source=11;handlers['meta_comic:server:vendingKeyLock'](1)")
        self.assertFalse(self.lua.eval("Keys.access(11,entry,'full')"))

    def test_rekey_retains_old_ids_and_metadata_and_issues_new_owner_key(self):
        self.issue(); self.unlock()
        old = self.lua.eval('bags[11][1].metadata.lockId')
        self.replace()
        self.assertEqual(self.lua.eval('#record.keyArchive.cylinders'), 2)
        self.assertEqual(self.lua.eval('#record.keyArchive.keys'), 2)
        self.assertEqual(self.lua.eval('record.keyArchive.keys[1].lockId'), old)
        self.assertEqual(self.lua.eval('bags[11][1].metadata.lockId'), old)
        self.assertEqual(self.lua.eval('record.keyArchive.cylinders[1].retiredAt'), 1000)
        self.assertFalse(self.lua.eval("Keys.access(11,entry,'full')"))
        self.lua.execute('Keys.unlock(11,entry,1)')
        self.assertFalse(self.lua.eval("Keys.access(11,entry,'full')"))
        self.unlock()
        self.assertTrue(self.lua.eval("Keys.access(11,entry,'full')"))
        self.lua.execute("source=11;handlers['meta_comic:server:useVendingKey'](1)")
        self.assertEqual(self.lua.eval('viewed.printed.lockId'), old)
        self.assertNotEqual(self.lua.eval('viewed.currentLockId'), old)

    def test_many_rotations_survive_capped_history_and_reload(self):
        self.issue()
        self.lua.execute('cylinders=100')
        for _ in range(28): self.replace()
        self.lua.execute("for i=1,30 do MetaComic.VendingRegistry.update('VM-1',nil,'Event '..i) end")
        self.assertEqual(self.lua.eval('#record.history'), 25)
        self.assertEqual(self.lua.eval('#record.keyArchive.cylinders'), 29)
        self.assertEqual(self.lua.eval('#record.keyArchive.keys'), 29)
        self.lua.execute('records=MetaComic.CopyTable(records)')
        self.lua.execute((ROOT / 'fivem/server/modules/vending_registry.lua').read_text(encoding='utf-8'))
        self.assertEqual(self.lua.eval("#MetaComic.VendingRegistry.get('VM-1').keyArchive.keys"), 29)

    def test_failed_replacement_preserves_lock_archive_and_returns_material(self):
        self.issue()
        self.lua.execute('saveOK=false')
        self.replace()
        self.assertEqual(self.lua.eval('record.lockId'), 'VM-1-C0001')
        self.assertEqual(self.lua.eval('#record.keyArchive.cylinders'), 1)
        self.assertIsNone(self.lua.eval('record.keyArchive.cylinders[1].retiredAt'))
        self.assertEqual(self.lua.eval('cylinders'), 10)

    def test_early_or_changed_replacement_cannot_rotate(self):
        self.lua.execute("source=11;handlers['meta_comic:server:vendingRekeyStart'](1);handlers['meta_comic:server:vendingRekeyFinish'](startData.token)")
        self.assertEqual(self.lua.eval('record.lockId'), 'VM-1-C0001')
        self.lua.execute("handlers['meta_comic:server:vendingRekeyStart'](1);Keys.invalidate(record);timer=60000;handlers['meta_comic:server:vendingRekeyFinish'](startData.token)")
        self.assertEqual(self.lua.eval('cylinders'), 10)

    def test_failed_key_delivery_reserves_id_and_never_creates_valid_key(self):
        self.lua.execute('addFail=true')
        self.assertFalse(self.lua.execute("return Keys.issue(44,'VM-1',11,'full')")[0])
        self.lua.execute('addFail=false')
        self.issue()
        self.assertTrue(self.lua.eval('record.keyArchive.keys[1].deliveryFailed'))
        self.assertEqual(self.lua.eval('bags[11][1].metadata.keyId'), 'VM-1-K000002')

    def test_forged_or_promoted_metadata_does_not_grant_access(self):
        self.issue(access='service')
        self.lua.execute("bags[11][1].metadata.access='full'")
        self.unlock()
        self.assertFalse(self.lua.eval("Keys.access(11,entry,'full')"))

    def test_police_seal_stops_loot_keeps_damage_and_owner_repairs(self):
        self.issue()
        self.lua.execute('assert(MetaComic.VendingLoot.unlock(22,entry))')
        self.assertFalse(self.lua.eval('MetaComic.VendingLoot.canSecure(22,entry)'))
        self.lua.execute('assert(MetaComic.VendingLoot.secure(55,entry))')
        self.assertEqual(self.lua.eval('record.lockCondition'), 'damaged')
        self.assertIsNotNone(self.lua.eval('record.securitySeal'))
        self.unlock()
        self.assertFalse(self.lua.eval("Keys.access(11,entry,'full')"))
        self.replace()
        self.assertEqual(self.lua.eval('record.lockCondition'), 'intact')
        self.assertIsNone(self.lua.eval('record.securitySeal'))

    def test_automatic_expiry_fits_seal_and_failed_save_can_retry(self):
        self.lua.execute('assert(MetaComic.VendingLoot.unlock(22,entry));now=1601;saveOK=false')
        self.lua.execute('local ok,err=coroutine.resume(threads[#threads]);assert(ok,err);ok,err=coroutine.resume(threads[#threads]);assert(ok,err)')
        self.assertIsNone(self.lua.eval('record.securitySeal'))
        self.lua.execute('saveOK=true;local ok,err=coroutine.resume(threads[#threads]);assert(ok,err)')
        self.assertEqual(self.lua.eval('record.lockCondition'), 'damaged')
        self.assertEqual(self.lua.eval('record.securitySeal.by'), 'Automatic security timer')

    def test_seal_adds_time_and_minigame_and_old_attempt_cannot_reopen(self):
        self.lua.execute("record.lockCondition='damaged';record.securitySeal={at=now};source=22;handlers['meta_comic:server:crimeStart'](1,'breakin')")
        self.assertEqual(self.lua.eval('startData.duration'), 65000)
        self.assertEqual(self.lua.eval('#startData.minigame'), 3)
        self.lua.execute("Keys.invalidate(record);timer=65000;handlers['meta_comic:server:crimeFinish'](startData.token,true)")
        self.assertFalse(self.lua.eval('MetaComic.VendingLoot.isOpen(entry)'))

    def test_key_reports_are_authorized_latent_and_immutable_after_rotation(self):
        self.issue(); self.replace()
        self.lua.execute("source=22;handlers['meta_comic:server:vendingKeyReport']('VM-1',false)")
        self.assertIsNone(self.lua.eval('viewed'))
        self.lua.execute("source=55;commands.vendingkeys(55,{'VM-1','print'});handlers['meta_comic:server:useVendingRecord']('keyreport',1)")
        self.assertEqual(self.lua.eval('#viewed.printed.archive.cylinders'), 2)
        self.assertEqual(self.lua.eval('viewed.printed.archive.keys[1].id'), 'VM-1-K000001')
        self.assertEqual(self.lua.eval('latent'), 1)
        self.replace()
        self.lua.execute("source=55;handlers['meta_comic:server:useVendingRecord']('keyreport',1)")
        self.assertEqual(self.lua.eval('#viewed.printed.archive.cylinders'), 2)
        self.lua.execute("commands.vendingkeys(55,{'VM-1','print'})")
        self.lua.execute("handlers['meta_comic:server:useVendingRecord']('keyreport',2)")
        self.assertEqual(self.lua.eval('#viewed.printed.archive.cylinders'), 3)
        self.assertIsNone(self.lua.eval('bags[55][2].metadata.archive'))

    def test_report_save_failure_gives_no_paper_and_report_survives_reload(self):
        self.issue()
        self.lua.execute("source=55;saveOK=false;commands.vendingkeys(55,{'VM-1','print'})")
        self.assertIsNone(self.lua.eval('bags[55]'))
        self.lua.execute("saveOK=true;commands.vendingkeys(55,{'VM-1','print'})")
        self.lua.execute((ROOT / 'fivem/server/modules/vending_records.lua').read_text(encoding='utf-8'))
        self.lua.execute("handlers['meta_comic:server:useVendingRecord']('keyreport',1)")
        self.assertEqual(self.lua.eval('viewed.printed.archive.keys[1].id'), 'VM-1-K000001')

    def test_legacy_immediate_loot_still_damages_and_seals_cylinder(self):
        self.lua.execute('Config.VendingMachines.Crime.BreakIn.Loot.Enabled=false')
        self.lua.execute((ROOT / 'fivem/server/modules/vending_loot.lua').read_text(encoding='utf-8'))
        self.lua.execute("source=22;handlers['meta_comic:server:crimeStart'](1,'breakin');timer=45000;handlers['meta_comic:server:crimeFinish'](startData.token,true)")
        self.assertEqual(self.lua.eval('record.lockCondition'), 'damaged')
        self.assertEqual(self.lua.eval('paid'), 300)
        self.lua.execute('assert(MetaComic.VendingLoot.secure(55,entry))')
        self.assertIsNotNone(self.lua.eval('record.securitySeal'))


if __name__ == '__main__':
    unittest.main()
