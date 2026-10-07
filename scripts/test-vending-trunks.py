"""Server-authoritative trunk hook checks, including reverse swaps."""
from pathlib import Path
import sys
import unittest
if len(sys.argv) > 1:
    sys.path.insert(0, sys.argv.pop(1))
from lupa.lua54 import LuaRuntime
ROOT = Path(__file__).resolve().parents[1]

class TrunkTests(unittest.TestCase):
    def setUp(self):
        self.lua = LuaRuntime(unpack_returned_tuples=True)
        self.lua.execute('''
            Config={VendingMachines={},VendingCarry={TrunkRestrictions={
                BlockedModels={'adder',-2},BlockedClasses={'sedan','sports'},BlockedTypes={'boat'},
                ModelClasses={sultan='sports',speedo='vans'},BlockUnknownClass=true}}}
            MetaComic={Framework={notify=function() notified=true end}}
            function joaat(name) return ({adder=1,sultan=2,speedo=3})[name] end
            vehicleModel=3;vehicleType='automobile'
            function GetEntityModel() return vehicleModel end
            function GetVehicleType() return vehicleType end
            function DoesEntityExist() return true end
            function GetEntityType() return 2 end
            function NetworkGetEntityFromNetworkId() return stale and 99 or 50 end
            function GetResourceState() return 'started' end
            function GetCurrentResourceName() return 'test' end
            function AddEventHandler() end
            function CreateThread(fn) fn() end
            exports={ox_inventory={
                GetInventory=function() return {entityId=50,netid=5} end,
                registerHook=function(_,event,fn) assert(event=='swapItems');Hook=fn;return 7 end}}
            payload={source=1,action='move',fromSlot={name='vending_machine'},toInventory='trunkABC',toType='trunk'}
        ''')
        self.lua.execute((ROOT/'fivem/server/modules/vending_trunks.lua').read_text(encoding='utf-8'))

    def test_allowed_van(self):
        self.assertIsNone(self.lua.eval('Hook(payload)'))

    def test_model_names_and_signed_hashes(self):
        for model in (1, 4294967294):
            self.lua.execute(f'vehicleModel={model}')
            self.assertFalse(self.lua.eval('Hook(payload)'))

    def test_class_type_and_unknown(self):
        for code in ('vehicleModel=2', "vehicleModel=3;vehicleType='boat'", "vehicleType='automobile';vehicleModel=4"):
            self.lua.execute(code)
            self.assertFalse(self.lua.eval('Hook(payload)'))

    def test_reverse_swap(self):
        self.lua.execute("vehicleModel=1;payload={source=1,action='swap',fromType='trunk',fromInventory='trunkABC',fromSlot={name='water'},toType='player',toSlot={name='vending_machine'}}")
        self.assertFalse(self.lua.eval('Hook(payload)'))

    def test_removing_machine_and_other_items_unaffected(self):
        self.lua.execute("vehicleModel=1;payload.toType='player';payload.fromType='trunk'")
        self.assertIsNone(self.lua.eval('Hook(payload)'))
        self.lua.execute("payload.toType='trunk';payload.fromSlot.name='water'")
        self.assertIsNone(self.lua.eval('Hook(payload)'))

    def test_stale_vehicle_rejected(self):
        self.lua.execute('stale=true')
        self.assertFalse(self.lua.eval('Hook(payload)'))

if __name__ == '__main__':
    unittest.main()
