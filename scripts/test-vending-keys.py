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
            -- Existing archive tests operate on an already-open cabinet. Closed-door cases override this below.
            cabinetOpen=true
            MetaComic.VendingCashbox={cabinetOpen=function() return cabinetOpen end,isOpen=function() return false end,allows=function() return true end}
            MetaComic.Vending.save=function() return true end
            MetaComic.Vending.giveSealed=function() return true end
            MetaComic.Police.isPolice=function(src) return src==55 end
            MetaComic.Police.count=function() return 0 end
            MetaComic.RpcHandlers={}
            MetaComic.Settings.get=function(key) if key=='vending_key_reports' then return savedReports end;return records end
            MetaComic.Settings.set=function(key,value) if not saveOK then return false end;if key=='vending_key_reports' then savedReports=MetaComic.CopyTable(value) end;if revokeIssuerOnSave then bags[44]={} end;return true end
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
        self.provide_issuer_key()
        self.assertTrue(self.lua.execute(f"return Keys.issue(44,'VM-1',{target},'{access}')"))

    def provide_issuer_key(self):
        self.lua.execute('''
            if not Keys.canIssue(44,record) then
                if #record.keyArchive.keys==0 then
                    local status,installer=record.status,record.installedById
                    record.status='placed';record.installedById=MetaComic.VendingRegistry.identifierOf(44)
                    assert(Keys.initialKey(44,record))
                    record.status,record.installedById=status,installer
                else
                    -- An owner lends the current physical full key to the manager for duplication.
                    for _,bag in pairs(bags) do for _,item in pairs(bag) do
                        if item.name=='vending_key' and item.metadata.lockId==record.lockId and item.metadata.access=='full' then
                            bags[44]={MetaComic.CopyTable(item)}
                        end
                    end end
                end
            end
        ''')

    def unlock(self, target=11):
        self.lua.execute(f'Keys.unlock({target},entry)')

    def replace(self, target=11):
        if self.lua.eval('record.securitySeal ~= nil'):
            self.assertTrue(self.lua.eval(f'Keys.unseal({target},entry)'))
        self.lua.execute(f"source={target};handlers['meta_comic:server:vendingRekeyStart'](1);timer=timer+startData.duration;handlers['meta_comic:server:vendingRekeyFinish'](startData.token)")

    def test_closed_cabinet_blocks_owner_manager_employee_and_stolen_installer(self):
        self.lua.execute("cabinetOpen=false;record.stolenAt=now;record.installedById='hacker';MetaComic.Vending.businessStaff=function(src) return src==33 end")
        for actor in (11, 44, 33, 22):
            self.lua.execute(f"source={actor};handlers['meta_comic:server:vendingRekeyStart'](1)")
            self.assertIsNone(self.lua.eval('startData'))
        self.assertEqual(self.lua.eval('cylinders'), 10)
        self.assertEqual(self.lua.eval('record.lockId'), 'VM-1-C0001')

    def test_closing_cabinet_during_replacement_cannot_rotate_or_consume(self):
        self.lua.execute("handlers['meta_comic:server:vendingRekeyStart'](1);cabinetOpen=false;timer=60000;handlers['meta_comic:server:vendingRekeyFinish'](startData.token)")
        self.assertEqual(self.lua.eval('cylinders'), 10)
        self.assertEqual(self.lua.eval('record.lockId'), 'VM-1-C0001')

    def test_matching_damaged_key_or_staff_can_remove_seal_but_retired_keys_cannot(self):
        self.issue(target=22, access='service')
        self.lua.execute("assert(MetaComic.VendingLoot.unlock(33,entry));assert(MetaComic.VendingLoot.secure(55,entry));MetaComic.Vending.businessStaff=function(src) return src==33 end")
        self.assertFalse(self.lua.eval('Keys.unseal(66,entry)'))
        self.assertTrue(self.lua.eval('Keys.canUnseal(11,record)'))
        self.assertTrue(self.lua.eval('Keys.canUnseal(44,record)'))
        self.assertTrue(self.lua.eval('Keys.canUnseal(33,record)'))
        self.assertTrue(self.lua.eval('Keys.unseal(22,entry)'))
        self.assertIsNone(self.lua.eval('record.securitySeal'))
        self.assertEqual(self.lua.eval('record.lockCondition'), 'damaged')
        self.assertTrue(self.lua.eval('Keys.replacementReady(22,entry,record)'))
        self.replace(22)
        self.assertEqual(self.lua.eval('bags[22][2].metadata.access'), 'full')
        self.assertEqual(self.lua.eval('record.registeredLockId'), 'VM-1-C0001')
        self.lua.execute('bags[22][2]=nil;assert(MetaComic.VendingLoot.unlock(33,entry));assert(MetaComic.VendingLoot.secure(55,entry))')
        self.assertFalse(self.lua.eval('Keys.unseal(22,entry)'))
        self.assertIsNotNone(self.lua.eval('record.securitySeal'))

    def test_seal_removal_requires_proximity_and_persists_before_opening(self):
        self.load_server_door()
        self.lua.execute("record.lockCondition='damaged';record.securitySeal={at=now};source=11;farAway=true;handlers['meta_comic:server:vendingDamagedDoor'](1,true)")
        self.assertFalse(self.lua.eval('Keys.cabinetOpen(entry)'))
        self.lua.execute("farAway=false;saveOK=false;handlers['meta_comic:server:vendingDamagedDoor'](1,true)")
        self.assertFalse(self.lua.eval('Keys.cabinetOpen(entry)'))
        self.assertIsNotNone(self.lua.eval('record.securitySeal'))
        self.lua.execute("saveOK=true;handlers['meta_comic:server:vendingDamagedDoor'](1,true)")
        self.assertTrue(self.lua.eval('Keys.cabinetOpen(entry)'))

    def test_owner_can_break_into_machine_to_recover_cylinder_without_robbery_enabled(self):
        self.lua.execute("Config.VendingMachines.Crime.OwnersCanRob=false;cabinetOpen=false;handlers['meta_comic:server:crimeStart'](1,'breakin')")
        self.assertEqual(self.lua.eval('startData.action'), 'breakin')

    def load_server_door(self):
        self.lua.execute('''
            function exports() end
            local listeners={}
            function AddEventHandler(name,fn) listeners[name]=listeners[name] or {};table.insert(listeners[name],fn) end
            function TriggerEvent(name,...) for _,fn in ipairs(listeners[name] or {}) do fn(...) end end
            function RegisterNetEvent(name,fn)
                local previous=handlers[name]
                handlers[name]=function(...) if previous then previous(...) end;fn(...) end
            end
        ''')
        self.lua.execute((ROOT / 'fivem/server/modules/vending_door.lua').read_text(encoding='utf-8'))

    def test_damaged_door_is_public_but_sealed_or_repaired_door_is_not(self):
        self.load_server_door()
        self.lua.execute("record.lockCondition='damaged';record.unlockedUntil=now+600;source=66;handlers['meta_comic:server:vendingDamagedDoor'](1,true)")
        self.assertTrue(self.lua.eval('Keys.cabinetOpen(entry)'))
        self.lua.execute("handlers['meta_comic:server:vendingDamagedDoor'](1,false)")
        self.assertFalse(self.lua.eval('Keys.cabinetOpen(entry)'))
        self.lua.execute('local ok,err=coroutine.resume(threads[#threads]);assert(ok,err);for i=1,6 do ok,err=coroutine.resume(threads[#threads]);assert(ok,err) end')
        self.assertFalse(self.lua.eval('Keys.cabinetOpen(entry)'))
        self.lua.execute("assert(MetaComic.VendingLoot.secure(55,entry));handlers['meta_comic:server:vendingDamagedDoor'](1,true)")
        self.assertFalse(self.lua.eval('Keys.cabinetOpen(entry)'))
        self.assertIsNotNone(self.lua.eval('record.securitySeal'))
        self.lua.execute("source=11;handlers['meta_comic:server:vendingDamagedDoor'](1,true)")
        self.assertTrue(self.lua.eval('Keys.cabinetOpen(entry)'))
        self.assertIsNone(self.lua.eval('record.securitySeal'))
        self.lua.execute("handlers['meta_comic:server:vendingDamagedDoor'](1,false);record.lockCondition='intact';source=66;handlers['meta_comic:server:vendingDamagedDoor'](1,true)")
        self.assertFalse(self.lua.eval('Keys.cabinetOpen(entry)'))

    def test_active_replacement_holds_real_door_beyond_max_seconds(self):
        self.load_server_door()
        self.lua.execute("record.lockCondition='damaged';record.unlockedUntil=now+600;source=22;handlers['meta_comic:server:vendingDamagedDoor'](1,true);handlers['meta_comic:server:vendingRekeyStart'](1);now=1700")
        self.lua.execute('local ok,err=coroutine.resume(threads[#threads]);assert(ok,err);ok,err=coroutine.resume(threads[#threads]);assert(ok,err)')
        self.assertTrue(self.lua.eval('Keys.cabinetOpen(entry)'))
        self.lua.execute("source=66;handlers['meta_comic:server:vendingDamagedDoor'](1,false)")
        self.assertTrue(self.lua.eval('Keys.cabinetOpen(entry)'))
        self.lua.execute("source=22;timer=180000;handlers['meta_comic:server:vendingRekeyFinish'](startData.token)")
        self.assertEqual(self.lua.eval('record.lockId'), 'VM-1-C0002')

    def load_management_handlers(self):
        self.lua.execute('''
            Registry=MetaComic.VendingRegistry;ready=true;machines={[1]=entry};stockTransfers={};given=0;pickups=0
            MAX_PRICE=10000000;MAX_PRODUCTS=30;own={};shop={}
            function notify() end
            function near() return not farAway end
            function interactReach() return 2 end
            function canManage(src) return src==44 end
            function isEmployee(src) return src==33 end
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
        access = 'local function recordOf' + code.split('local function recordOf', 1)[1].split('-- Products', 1)[0]
        self.lua.execute(access + '\nCabinetAccess=cabinetAccess;BusinessStaff=businessStaff;CanMaintain=canControl;CanOperate=canOperateSystem;CanRestock=canRestock;RegisteredControls=controls;RegisteredBy=controlledBy')
        self.lua.execute('cabinetAccess=CabinetAccess;businessStaff=BusinessStaff;canControl=CanMaintain;canOperateSystem=CanOperate;controls=RegisteredControls;controlledBy=RegisteredBy;MetaComic.Vending.businessStaff=BusinessStaff;MetaComic.Vending.canControl=CanMaintain;MetaComic.Vending.canOperateSystem=CanOperate')
        product = 'local function withdrawStock' + code.split('local function withdrawStock', 1)[1].split('-- Owner actions:', 1)[0]
        owner = 'local function ownerAction' + code.split('local function ownerAction', 1)[1].split('-- Map of every machine', 1)[0]
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

    def test_closed_cabinet_blocks_owner_cash_stock_and_broken_open_override(self):
        self.load_management_handlers(); self.issue(); self.unlock()
        self.lua.execute("cabinetOpen=false;record.displacedOpen=true;record.lockCondition='damaged';handlers['meta_comic:server:vendingOwner'](1,'collect');handlers['meta_comic:server:vendingProduct'](1,'withdraw',{set='test',amount=1})")
        self.assertEqual(self.lua.eval('paid'), 0)
        self.assertEqual(self.lua.eval('given'), 0)
        self.assertEqual(self.lua.eval('entry.cash'), 300)
        self.assertEqual(self.lua.eval('entry.products[1].stock'), 3)

    def test_closed_cashbox_blocks_collection_but_not_stock_with_open_cabinet(self):
        self.load_management_handlers(); self.issue(); self.unlock()
        self.lua.execute("MetaComic.VendingCashbox.allows=function(_,mode) return mode=='stock' end;handlers['meta_comic:server:vendingOwner'](1,'collect');handlers['meta_comic:server:vendingProduct'](1,'withdraw',{set='test',amount=1})")
        self.assertEqual(self.lua.eval('paid'), 0)
        self.assertEqual(self.lua.eval('entry.cash'), 300)
        self.assertEqual(self.lua.eval('given'), 1)

    def test_cashbox_closing_during_owner_collection_save_restores_cash(self):
        self.load_management_handlers(); self.issue(); self.unlock()
        self.lua.execute("cashboxOpen=true;MetaComic.VendingCashbox.allows=function() return cashboxOpen end;function saveEntry() cashboxOpen=false;return true end;handlers['meta_comic:server:vendingOwner'](1,'collect')")
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
        for path in ('server/modules/vending_keys.lua', 'client/vending_keys.lua', 'server/modules/vending_door.lua', 'client/vending_crime.lua', 'server/modules/vending_records.lua', 'server/modules/vending_loot.lua', 'server/modules/vending_crime.lua', 'server/modules/vending_registry.lua', 'server/modules/vending_machines.lua', 'client/vending_machines.lua'):
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

    def test_manager_needs_a_current_full_key_to_duplicate(self):
        self.assertFalse(self.lua.execute("return Keys.issue(44,'VM-1',11,'full')")[0])
        self.assertEqual(self.lua.eval('#record.keyArchive.keys'), 0)
        self.issue()
        self.lua.execute('bags[44]={};bags[44][1]=MetaComic.CopyTable(bags[11][1]);bags[44][1].metadata.access="service"')
        self.assertFalse(self.lua.eval('Keys.canIssue(44,record)'))
        self.assertFalse(self.lua.execute("return Keys.issue(44,'VM-1',11,'full')")[0])

    def test_service_key_cannot_be_used_to_create_full_access_keys(self):
        self.issue(target=44, access='service')
        self.lua.execute('bags[44]={bags[44][2]}')
        self.assertFalse(self.lua.execute("return Keys.issue(44,'VM-1',11,'full')")[0])
        self.assertFalse(self.lua.execute("return Keys.issue(44,'VM-1',11,'service')")[0])

    def test_old_key_and_business_authority_cannot_duplicate_hidden_new_cylinder(self):
        self.issue()
        self.lua.execute('assert(MetaComic.VendingLoot.unlock(22,entry))')
        self.replace(22)
        self.assertFalse(self.lua.eval('Keys.canIssue(44,record)'))
        count = self.lua.eval('#record.keyArchive.keys')
        self.assertFalse(self.lua.execute("return Keys.issue(44,'VM-1',11,'full')")[0])
        self.assertEqual(self.lua.eval('#record.keyArchive.keys'), count)
        self.lua.execute('bags[44]={MetaComic.CopyTable(bags[22][1])}')
        self.assertTrue(self.lua.execute("return Keys.issue(44,'VM-1',11,'full')"))
        self.assertEqual(self.lua.eval('bags[11][2].metadata.lockId'), 'VM-1-C0002')
        self.assertEqual(self.lua.eval('record.registeredLockId'), 'VM-1-C0001')
        self.assertEqual(self.lua.eval('#record.registeredKeyArchive.keys'), 2)

    def test_removing_issuer_key_during_persistence_cannot_deliver_duplicate(self):
        self.provide_issuer_key()
        self.lua.execute('revokeIssuerOnSave=true')
        self.assertFalse(self.lua.execute("return Keys.issue(44,'VM-1',11,'full')")[0])
        self.assertIsNone(self.lua.eval('bags[11]'))
        self.assertTrue(self.lua.eval('record.keyArchive.keys[2].deliveryFailed'))

    def test_factory_install_includes_one_key_and_reinstall_cannot_generate_another(self):
        self.load_placement_transitions()
        self.lua.execute("recordPlaced(entry,'Installed','Owner',11)")
        self.assertEqual(self.lua.eval('bags[11][1].metadata.access'), 'full')
        self.assertEqual(self.lua.eval('#record.keyArchive.keys'), 1)
        self.lua.execute("recordPlaced(entry,'Moved','Owner',11)")
        self.assertEqual(self.lua.eval('#record.keyArchive.keys'), 1)

    def test_factory_key_delivery_failure_can_retry_and_stolen_factory_gets_no_free_key(self):
        self.load_placement_transitions()
        self.lua.execute("addFail=true;recordPlaced(entry,'Installed','Owner',11)")
        self.assertIsNotNone(self.lua.eval('record.replacementKeyDue'))
        self.lua.execute("addFail=false;source=11;handlers['meta_comic:server:vendingReplacementKey'](1)")
        self.assertEqual(self.lua.eval('#bags[11]'), 1)
        self.setUp(); self.load_placement_transitions()
        self.lua.execute("record.status='stolen';recordPlaced(entry,'Installed stolen machine','Thief',22)")
        self.assertIsNone(self.lua.eval('bags[22]'))
        self.assertIsNone(self.lua.eval('record.replacementKeyDue'))

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
        self.assertEqual(self.lua.eval('#record.keyArchive.keys'), 3)
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
        self.assertEqual(self.lua.eval('#record.keyArchive.keys'), 30)
        self.lua.execute('records=MetaComic.CopyTable(records)')
        self.lua.execute((ROOT / 'fivem/server/modules/vending_registry.lua').read_text(encoding='utf-8'))
        self.assertEqual(self.lua.eval("#MetaComic.VendingRegistry.get('VM-1').keyArchive.keys"), 30)

    def test_stolen_machine_installer_gets_full_key_without_business_issuance(self):
        self.issue()
        self.lua.execute("record.stolenAt=now;record.installedById='hacker';record.displacedOpen=true;record.lockCondition='damaged'")
        self.replace(22)
        self.assertEqual(self.lua.eval('bags[22][1].metadata.access'), 'full')
        self.assertEqual(self.lua.eval('bags[22][1].metadata.lockId'), 'VM-1-C0002')
        self.assertEqual(self.lua.eval('record.owner'), 'owner')
        self.assertIsNone(self.lua.eval('record.displacedOpen'))
        self.assertEqual(self.lua.eval('record.keyArchive.keys[1].lockId'), 'VM-1-C0001')
        self.unlock(22)
        self.assertTrue(self.lua.eval("Keys.access(22,entry,'full')"))
        self.assertFalse(self.lua.execute("return Keys.issue(22,'VM-1',22,'full')")[0])

    def test_stolen_marker_alone_cannot_grant_replacement(self):
        self.lua.execute("record.stolenAt=now;record.installedById='owner';source=22;handlers['meta_comic:server:vendingRekeyStart'](1)")
        self.assertIsNone(self.lua.eval('startData'))

    def test_unregistered_replacement_does_not_leak_into_views_or_police_reports(self):
        self.issue()
        self.lua.execute("assert(MetaComic.VendingLoot.unlock(22,entry))")
        self.replace(22)
        self.lua.execute("view=MetaComic.VendingRegistry.view(record,true);source=55;commands.vendingkeys(55,{'VM-1','print'});handlers['meta_comic:server:useVendingRecord']('keyreport',1)")
        self.assertEqual(self.lua.eval('view.lockId'), 'VM-1-C0001')
        self.assertEqual(self.lua.eval('#view.keyArchive.cylinders'), 1)
        self.assertIsNone(self.lua.eval('view.keyArchive.cylinders[1].retiredAt'))
        self.assertEqual(self.lua.eval('#view.keyArchive.keys'), 2)
        self.assertEqual(self.lua.eval('viewed.printed.lockId'), 'VM-1-C0001')
        self.assertIsNone(self.lua.eval('viewed.printed.archive.cylinders[1].retiredAt'))
        self.assertEqual(self.lua.eval('record.lockId'), 'VM-1-C0002')
        self.unlock(22)
        self.assertTrue(self.lua.eval("Keys.access(22,entry,'full')"))
        self.lua.execute("source=11;handlers['meta_comic:server:useVendingKey'](1)")
        self.assertEqual(self.lua.eval('viewed.currentLockId'), 'VM-1-C0001')
        self.lua.execute('records=MetaComic.CopyTable(records)')
        self.lua.execute((ROOT / 'fivem/server/modules/vending_registry.lua').read_text(encoding='utf-8'))
        self.assertEqual(self.lua.eval("MetaComic.VendingRegistry.view(MetaComic.VendingRegistry.get('VM-1'),true).lockId"), 'VM-1-C0001')

    def test_authorized_replacement_registers_only_known_cylinders_after_hidden_change(self):
        self.issue()
        self.lua.execute("assert(MetaComic.VendingLoot.unlock(22,entry))")
        self.replace(22)
        self.lua.execute('now=2000')
        self.replace(11)
        self.lua.execute('view=MetaComic.VendingRegistry.view(record,true)')
        self.assertEqual(self.lua.eval('view.lockId'), 'VM-1-C0003')
        self.assertEqual(self.lua.eval('#view.keyArchive.cylinders'), 2)
        self.assertEqual(self.lua.eval('view.keyArchive.cylinders[1].retiredAt'), 2000)
        self.assertEqual(self.lua.eval('view.keyArchive.cylinders[2].id'), 'VM-1-C0003')
        self.assertEqual(self.lua.eval('#view.keyArchive.keys'), 3)
        self.assertEqual(self.lua.eval('view.keyArchive.keys[3].lockId'), 'VM-1-C0003')
        self.assertEqual(self.lua.eval('#record.keyArchive.cylinders'), 3)

    def test_authorized_employee_replacement_updates_registered_records(self):
        self.lua.execute("record.owner=nil;MetaComic.Vending.businessStaff=function(src) return src==33 end")
        self.replace(33)
        self.assertEqual(self.lua.eval('startData.duration'), 60000)
        self.assertEqual(self.lua.eval('MetaComic.VendingRegistry.view(record,true).lockId'), 'VM-1-C0002')

    def test_service_key_session_can_inspect_skimmer_but_revoked_session_cannot_finish(self):
        self.issue(target=33, access='service')
        self.unlock(33)
        self.lua.execute("inspected=0;MetaComic.VendingSecurity.inspect=function() inspected=inspected+1;return true end;source=33;handlers['meta_comic:server:crimeStart'](1,'inspectpanel')")
        self.assertEqual(self.lua.eval('startData.action'), 'inspectpanel')
        self.lua.execute("timer=startData.duration;handlers['meta_comic:server:crimeFinish'](startData.token,true)")
        self.assertEqual(self.lua.eval('inspected'), 1)
        self.lua.execute("handlers['meta_comic:server:crimeStart'](1,'inspectpanel');bags[33]={};timer=timer+startData.duration;handlers['meta_comic:server:crimeFinish'](startData.token,true)")
        self.assertEqual(self.lua.eval('inspected'), 1)

    def test_key_without_an_unlocked_session_cannot_inspect(self):
        self.issue(target=33)
        self.lua.execute("source=33;handlers['meta_comic:server:crimeStart'](1,'inspectpanel')")
        self.assertIsNone(self.lua.eval('startData'))

    def test_police_reads_physical_serial_without_key_or_cabinet_session(self):
        self.lua.execute("source=55;handlers['meta_comic:server:vendingInspectSerial'](1)")
        self.assertEqual(self.lua.eval('events[#events].name'), 'meta_comic:client:vendingSerial')
        self.assertEqual(self.lua.eval('events[#events].src'), 55)
        self.assertEqual(self.lua.eval('events[#events].data.serial'), 'VM-1')
        self.assertIsNone(self.lua.eval('events[#events].data.lockId'))
        self.assertIsNone(self.lua.eval('events[#events].data.archive'))
        self.assertIsNone(self.lua.eval('bags[55]'))

    def test_serial_inspection_rejects_civilians_remote_police_and_missing_machine(self):
        self.lua.execute("before=#events;source=22;handlers['meta_comic:server:vendingInspectSerial'](1);source=55;farAway=true;handlers['meta_comic:server:vendingInspectSerial'](1);farAway=false;handlers['meta_comic:server:vendingInspectSerial'](999)")
        self.assertEqual(self.lua.eval('#events'), self.lua.eval('before'))

    def test_serial_matches_owner_registration_after_unregistered_cylinder_change(self):
        self.lua.execute("assert(MetaComic.VendingRecords.giveCertificate(11,'VM-1'));assert(MetaComic.VendingLoot.unlock(22,entry))")
        self.replace(22)
        self.lua.execute("source=55;handlers['meta_comic:server:vendingInspectSerial'](1)")
        self.assertEqual(self.lua.eval('events[#events].data.serial'), self.lua.eval('bags[11][1].metadata.serial'))
        self.assertIsNone(self.lua.eval('events[#events].data.lockId'))

    def test_failed_unregistered_replacement_does_not_create_record_snapshot(self):
        self.lua.execute("assert(MetaComic.VendingLoot.unlock(22,entry));saveOK=false")
        self.replace(22)
        self.assertEqual(self.lua.eval('record.lockId'), 'VM-1-C0001')
        self.assertIsNone(self.lua.eval('record.registeredKeyArchive'))
        self.assertEqual(self.lua.eval('cylinders'), 10)

    def test_manage_menu_reports_inspection_permission_for_service_key(self):
        self.load_management_handlers()
        self.lua.execute('cfg=Config.VendingMachines;function controlledBy(r,id) return r.owner==id end')
        code = (ROOT / 'fivem/server/modules/vending_machines.lua').read_text(encoding='utf-8')
        section = 'local function manageInfo' + code.split('local function manageInfo', 1)[1].split('local function openManage', 1)[0]
        self.lua.execute(section + '\nManageInfo=manageInfo')
        self.assertFalse(self.lua.eval('ManageInfo(33,entry).canInspectPanel'))
        self.issue(target=33, access='service')
        self.unlock(33)
        self.assertTrue(self.lua.eval('ManageInfo(33,entry).canInspectPanel'))
        self.lua.execute('bags[33]={}')
        self.assertFalse(self.lua.eval('ManageInfo(33,entry).canInspectPanel'))

    def test_unmoved_broken_machine_can_receive_difficult_cylinder_and_full_key(self):
        self.lua.execute("assert(MetaComic.VendingLoot.unlock(22,entry));source=22;handlers['meta_comic:server:vendingRekeyStart'](1)")
        self.assertEqual(self.lua.eval('startData.duration'), 180000)
        self.assertEqual(self.lua.eval('#startData.minigame'), 2)
        self.lua.execute("now=1700;local ok,err=coroutine.resume(threads[#threads]);assert(ok,err);ok,err=coroutine.resume(threads[#threads]);assert(ok,err)")
        self.assertIsNone(self.lua.eval('record.securitySeal'))
        self.lua.execute("timer=180000;handlers['meta_comic:server:vendingRekeyFinish'](startData.token)")
        self.assertEqual(self.lua.eval('bags[22][1].metadata.access'), 'full')
        self.assertEqual(self.lua.eval('record.lockInstallerId'), 'hacker')
        self.assertEqual(self.lua.eval('record.owner'), 'owner')

    def test_replacement_key_delivery_can_be_retried_without_duplicate_keys(self):
        self.lua.execute('addFail=true')
        self.replace()
        self.assertIsNotNone(self.lua.eval('record.replacementKeyDue'))
        self.lua.execute("addFail=false;source=22;handlers['meta_comic:server:vendingReplacementKey'](1)")
        self.assertIsNone(self.lua.eval('bags[22]'))
        self.lua.execute("source=11;handlers['meta_comic:server:vendingReplacementKey'](1);handlers['meta_comic:server:vendingReplacementKey'](1)")
        self.assertEqual(self.lua.eval('#bags[11]'), 1)
        self.assertEqual(self.lua.eval('bags[11][1].metadata.access'), 'full')
        self.assertIsNone(self.lua.eval('record.replacementKeyDue'))

    def test_displaced_open_survives_timer_and_reload_until_secure_or_rekey(self):
        self.lua.execute("assert(MetaComic.VendingLoot.unlock(22,entry));record.displacedOpen=true;assert(MetaComic.VendingRegistry.save());now=1700")
        self.lua.execute('local ok,err=coroutine.resume(threads[#threads]);assert(ok,err);ok,err=coroutine.resume(threads[#threads]);assert(ok,err)')
        self.assertTrue(self.lua.eval('MetaComic.VendingLoot.isOpen(entry)'))
        self.assertIsNone(self.lua.eval('record.securitySeal'))
        self.lua.execute((ROOT / 'fivem/server/modules/vending_registry.lua').read_text(encoding='utf-8'))
        self.assertTrue(self.lua.eval("MetaComic.VendingRegistry.get('VM-1').displacedOpen"))
        self.lua.execute('assert(MetaComic.VendingLoot.secure(55,entry))')
        self.assertFalse(self.lua.eval('MetaComic.VendingLoot.isOpen(entry)'))
        self.assertIsNone(self.lua.eval('record.displacedOpen'))

    def test_employee_can_secure_business_machine(self):
        self.load_management_handlers()
        self.lua.execute("record.owner=nil;assert(MetaComic.VendingLoot.unlock(22,entry))")
        self.assertTrue(self.lua.eval('MetaComic.VendingLoot.canSecure(33,entry)'))
        self.assertFalse(self.lua.eval('MetaComic.VendingLoot.canSecure(22,entry)'))
        self.lua.execute('assert(MetaComic.VendingLoot.secure(33,entry))')
        self.assertIsNotNone(self.lua.eval('record.securitySeal'))

    def test_payment_hack_preserves_staff_and_os_takeover_grants_operating_authority(self):
        self.load_management_handlers()
        self.lua.execute("record.owner=nil;record.routing={id='hacker'};record.tampered=true")
        self.assertTrue(self.lua.eval('BusinessStaff(33,entry)'))
        self.assertTrue(self.lua.eval('Keys.canRegister(33,record)'))
        self.assertFalse(self.lua.eval('CanMaintain(22,entry)'))
        self.assertFalse(self.lua.eval('Keys.canRegister(22,record)'))
        self.lua.execute("record.systemController='hacker'")
        self.assertTrue(self.lua.eval('CanMaintain(22,entry)'))
        self.assertTrue(self.lua.eval('Keys.canRegister(22,record)'))
        self.assertTrue(self.lua.eval('CanOperate(22,entry)'))
        self.assertFalse(self.lua.eval('CanOperate(33,entry)'))
        self.assertFalse(self.lua.eval('CanRestock(33,entry)'))
        self.assertFalse(self.lua.eval("CabinetAccess(22,entry,'full')"))
        self.lua.execute("record.lockCondition='damaged';record.displacedOpen=true")
        self.assertTrue(self.lua.eval('CanRestock(33,entry)'))
        self.assertTrue(self.lua.eval("CabinetAccess(33,entry,'service')"))
        self.assertFalse(self.lua.eval("CabinetAccess(33,entry,'full')"))
        self.assertTrue(self.lua.eval("CabinetAccess(22,entry,'full')"))
        self.assertTrue(self.lua.eval('MetaComic.VendingLoot.canSecure(33,entry)'))
        self.assertTrue(self.lua.eval('MetaComic.VendingLoot.canSecure(22,entry)'))
        self.lua.execute("source=33;handlers['meta_comic:server:vendingRekeyStart'](1)")
        self.assertEqual(self.lua.eval('startData.duration'), 60000)
        self.assertIsNone(self.lua.eval('startData.minigame'))

    def test_unrelated_employee_has_no_private_machine_authority_but_valid_key_still_works(self):
        self.load_management_handlers()
        self.issue(target=33, access='service')
        self.lua.execute("record.systemController='hacker';record.lockCondition='damaged';record.displacedOpen=true")
        self.assertFalse(self.lua.eval('BusinessStaff(33,entry)'))
        self.assertFalse(self.lua.eval('Keys.canRegister(33,record)'))
        self.assertFalse(self.lua.eval('MetaComic.VendingLoot.canSecure(33,entry)'))
        self.assertTrue(self.lua.eval('CanMaintain(11,entry)'))
        self.assertFalse(self.lua.eval('CanOperate(11,entry)'))
        self.lua.execute("record.lockCondition='intact';record.displacedOpen=nil")
        self.unlock(33)
        self.assertTrue(self.lua.eval('CanRestock(33,entry)'))
        self.assertFalse(self.lua.eval("CabinetAccess(33,entry,'full')"))
        self.assertFalse(self.lua.eval('Keys.canRegister(33,record)'))
        self.lua.execute("source=33;handlers['meta_comic:server:vendingKeyReport']('VM-1',false)")
        self.assertIsNone(self.lua.eval('viewed'))

    def test_employee_can_recover_business_board_but_must_access_open_cashbox(self):
        self.load_management_handlers()
        self.lua.execute("record.owner=nil;record.systemController='hacker';boardOpen=false;MetaComic.VendingCashbox.hackReady=function() return boardOpen end;source=33;handlers['meta_comic:server:crimeStart'](1,'replaceboard')")
        self.assertIsNone(self.lua.eval('startData'))
        self.lua.execute("boardOpen=true;handlers['meta_comic:server:crimeStart'](1,'replaceboard')")
        self.assertEqual(self.lua.eval('startData.duration'), 60000)
        self.lua.execute("boardOpen=false;timer=60000;handlers['meta_comic:server:crimeFinish'](startData.token,true)")
        self.assertEqual(self.lua.eval('record.systemController'), 'hacker')
        self.lua.execute("boardOpen=true;handlers['meta_comic:server:crimeStart'](1,'replaceboard');timer=120000;handlers['meta_comic:server:crimeFinish'](startData.token,true)")
        self.assertIsNone(self.lua.eval('record.systemController'))
        self.assertTrue(self.lua.eval('MetaComic.VendingRegistry.businessOwned(record)'))

    def test_business_staff_targets_survive_takeover_without_labeling_hacker_owner(self):
        self.load_management_handlers()
        code = (ROOT / 'fivem/server/modules/vending_machines.lua').read_text(encoding='utf-8')
        section = 'local function access(player)' + code.split('local function access(player)', 1)[1].split('local function sendAccess', 1)[0]
        self.lua.execute("order={1};cfg=Config.VendingMachines;skimmers={};function IsPlayerAceAllowed() return false end")
        self.lua.execute(section + '\nAccessFor=access')
        self.lua.execute("record.owner=nil;record.systemController='hacker'")
        self.assertEqual(self.lua.eval('AccessFor(33).staffed[1]'), 1)
        self.assertEqual(self.lua.eval('AccessFor(33).replaceBoard[1]'), 1)
        self.assertEqual(self.lua.eval('#AccessFor(22).controls'), 1)
        self.assertEqual(self.lua.eval('AccessFor(22).systemControls[1]'), 1)

    def test_business_employee_can_repair_without_gaining_record_or_duplication_permission(self):
        self.load_management_handlers()
        self.lua.execute("record.owner=nil;record.systemController='hacker';record.lockCondition='damaged';source=33;handlers['meta_comic:server:vendingKeyMenu'](1)")
        self.assertTrue(self.lua.eval('events[#events].data.canRepair'))
        self.assertFalse(self.lua.eval('events[#events].data.canRead'))
        self.assertFalse(self.lua.eval('events[#events].data.canIssue'))

    def test_canceling_replacement_resumes_expired_security_timer(self):
        self.lua.execute("assert(MetaComic.VendingLoot.unlock(22,entry));source=22;handlers['meta_comic:server:vendingRekeyStart'](1);now=1700;handlers['meta_comic:server:vendingRekeyCancel']()")
        self.lua.execute('local ok,err=coroutine.resume(threads[#threads]);assert(ok,err);ok,err=coroutine.resume(threads[#threads]);assert(ok,err)')
        self.assertIsNotNone(self.lua.eval('record.securitySeal'))
        self.assertEqual(self.lua.eval('cylinders'), 10)

    def load_placement_transitions(self):
        self.lua.execute('''
            Registry=MetaComic.VendingRegistry;stockTransfers={};ITEM='vending_machine';broadcasts=0
            function recordOf() return record end
            function playerId(src) return Registry.identifierOf(src) end
            function playerName(src) return Registry.nameOf(src) end
            function deleteMachine() return true end
            function giveMachineItem() return not inventoryRefused end
            function createMachine() return entry end
            function broadcast() broadcasts=broadcasts+1 end
            function sendAccessAll() end
        ''')
        code = (ROOT / 'fivem/server/modules/vending_machines.lua').read_text(encoding='utf-8')
        self.lua.execute('function recordPlaced' + code.split('local function recordPlaced', 1)[1].split('CreateThread(function()', 1)[0])
        self.lua.execute('function pickUp' + code.split('local function pickUp', 1)[1].split('-- Buy / Restock menus:', 1)[0])

    def test_installation_is_loose_and_legacy_placement_keeps_bolts(self):
        self.load_placement_transitions()
        self.lua.execute("recordPlaced(entry,'Legacy migration','Business')")
        self.assertIsNone(self.lua.eval('record.unbolted'))
        self.lua.execute("recordPlaced(entry,'Installed','Player',22)")
        self.assertTrue(self.lua.eval('record.unbolted'))
        self.assertEqual(self.lua.eval('record.installedById'), 'hacker')
        self.assertEqual(self.lua.eval('records.serials["VM-1"].unbolted'), True)

    def test_unbolt_pickup_and_replacement_preserve_open_and_inventory_failure_does_not(self):
        self.load_placement_transitions()
        self.lua.execute("inventoryRefused=true;assert(not pickUp(22,entry,'stolen','Stolen'))")
        self.assertIsNone(self.lua.eval('record.displacedOpen'))
        self.lua.execute("inventoryRefused=false;assert(pickUp(22,entry,'stolen','Stolen'));now=9999;recordPlaced(entry,'Relocated','Player',22)")
        self.assertTrue(self.lua.eval('record.displacedOpen'))
        self.assertTrue(self.lua.eval('MetaComic.VendingLoot.isOpen(entry)'))
        self.assertEqual(self.lua.eval('record.lockCondition'), 'damaged')
        self.assertTrue(self.lua.eval('Keys.canReplace(22,record)'))

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
        self.provide_issuer_key()
        self.lua.execute('addFail=true')
        self.assertFalse(self.lua.execute("return Keys.issue(44,'VM-1',11,'full')")[0])
        self.lua.execute('addFail=false')
        self.issue()
        self.assertTrue(self.lua.eval('record.keyArchive.keys[2].deliveryFailed'))
        self.assertEqual(self.lua.eval('bags[11][1].metadata.keyId'), 'VM-1-K000003')

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
        self.lua.execute('Config.VendingMachines.Crime.BreakIn.Loot.Enabled=false;cabinetOpen=false')
        self.lua.execute((ROOT / 'fivem/server/modules/vending_loot.lua').read_text(encoding='utf-8'))
        self.lua.execute("source=22;handlers['meta_comic:server:crimeStart'](1,'breakin');timer=45000;handlers['meta_comic:server:crimeFinish'](startData.token,true)")
        self.assertEqual(self.lua.eval('record.lockCondition'), 'damaged')
        self.assertEqual(self.lua.eval('paid'), 300)
        self.lua.execute('assert(MetaComic.VendingLoot.secure(55,entry))')
        self.assertIsNotNone(self.lua.eval('record.securitySeal'))


if __name__ == '__main__':
    unittest.main()
