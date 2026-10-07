"""Verify chance/glove filters, adapter isolation and injury/blood coupling."""
from pathlib import Path
import sys
import unittest
if len(sys.argv) > 1:
    sys.path.insert(0, sys.argv.pop(1))
from lupa.lua54 import LuaRuntime
ROOT = Path(__file__).resolve().parents[1]

class EvidenceTests(unittest.TestCase):
    def setUp(self):
        self.lua = LuaRuntime(unpack_returned_tuples=True)
        self.lua.execute('''
            events={};created={};health=200;handlers={};serverEvents={};source=22;now=1000;os.time=function() return now end
            Config={CrimeEvidence={Enabled=true,Fingerprints={Enabled=true,Chance=100,Actions={breakin=true}},
                Injury={Enabled=true,Actions={breakin={Chance=100,Damage=5}}},Blood={Enabled=true,Chance=100},
                Adapters={{Type='rush-evidence',Resource='rush-evidence'}, {Create=function(data) created[#created+1]=data end}}}}
            MetaComic={VendingRegistry={identifierOf=function() return 'player-id' end}}
            function vector3(x,y,z) return {x=x,y=y,z=z} end
            function RegisterNetEvent(name,fn) handlers[name]=fn end
            function AddEventHandler() end
            function GetEntityCoords() return playerCoords or vector3(10,18,30.9) end
            function TriggerEvent(name,data) serverEvents[#serverEvents+1]={name=name,data=data} end
            function GetResourceState() return resourceStopped and 'stopped' or 'started' end
            function TriggerClientEvent(name,src,data) events[#events+1]={name=name,src=src,data=data} end
            function GetPlayerPed() return 1 end
            function DoesEntityExist() return true end
            function GetEntityHealth() return health end
            entry={serial='VM-1',id=3,x=10,y=20,z=30}
        ''')
        self.lua.execute((ROOT/'fivem/server/modules/crime_evidence.lua').read_text())

    def test_prints_adapter_and_gloves(self):
        self.lua.execute("MetaComic.CrimeEvidence.start(22,entry,'breakin')")
        self.assertEqual(self.lua.eval('events[1].name'), 'evidence:client:CreateFingerprint')
        self.assertEqual(self.lua.eval('created[1].identifier'), 'player-id')
        self.lua.execute("Config.CrimeEvidence.Fingerprints.IsWearingGloves=function() return true end;MetaComic.CrimeEvidence.start(22,entry,'breakin')")
        self.assertEqual(self.lua.eval('#created'), 1)

    def test_injury_precedes_blood_and_disabled_injury_leaves_none(self):
        self.lua.execute("MetaComic.CrimeEvidence.failure(22,entry,'breakin')")
        self.assertEqual(self.lua.eval('events[1].name'), 'meta_comic:client:crimeInjury')
        self.assertEqual(self.lua.eval('events[2].name'), 'meta_comic:client:crimeBloodGround')
        self.assertEqual(self.lua.eval('created[1].kind'), 'blood')
        self.lua.execute("Config.CrimeEvidence.Injury.Enabled=false;MetaComic.CrimeEvidence.failure(22,entry,'breakin')")
        self.assertEqual(self.lua.eval('#events'), 2)

    def test_no_injury_for_other_actions_or_low_health(self):
        self.lua.execute("MetaComic.CrimeEvidence.failure(22,entry,'hack');health=101;MetaComic.CrimeEvidence.failure(22,entry,'breakin')")
        self.assertEqual(self.lua.eval('#events'), 0)

    def test_fingerprint_positions_stay_outside_and_vary_near_player(self):
        self.lua.execute("for i=1,20 do MetaComic.CrimeEvidence.start(22,entry,'breakin') end")
        self.assertAlmostEqual(self.lua.eval('created[1].coords.y'), 19.495)
        self.assertTrue(self.lua.eval('math.abs(created[1].coords.x-10)<=0.18'))
        self.assertNotEqual(self.lua.eval('created[1].coords.x'), self.lua.eval('created[2].coords.x'))
        self.lua.execute("playerCoords=vector3(12,20,30.9);MetaComic.CrimeEvidence.start(22,entry,'breakin')")
        self.assertAlmostEqual(self.lua.eval('created[21].coords.x'), 10.655)
        self.lua.execute("entry.h=90;playerCoords=vector3(12,20,30.9);MetaComic.CrimeEvidence.start(22,entry,'breakin')")
        self.assertAlmostEqual(self.lua.eval('created[22].coords.x'), 10.505)

    def test_blood_is_scattered_ground_checked_and_single_use(self):
        self.lua.execute("MetaComic.CrimeEvidence.failure(22,entry,'breakin')")
        self.assertTrue(self.lua.eval('(created[1].coords.x-10)^2+(created[1].coords.y-18)^2<=0.25^2'))
        self.lua.execute("token=events[2].data.token;source=33;handlers['meta_comic:server:crimeBloodGround'](token,30)")
        self.assertEqual(self.lua.eval('#serverEvents'), 0)
        self.lua.execute("source=22;handlers['meta_comic:server:crimeBloodGround'](token,30);handlers['meta_comic:server:crimeBloodGround'](token,30)")
        self.assertEqual(self.lua.eval('#serverEvents'), 1)
        self.assertEqual(self.lua.eval('serverEvents[1].name'), 'evidence:server:CreateBlood')
        self.assertEqual(self.lua.eval('serverEvents[1].data.src'), 22)
        self.assertAlmostEqual(self.lua.eval('serverEvents[1].data.coords.z'), 30.02)
        self.lua.execute("MetaComic.CrimeEvidence.failure(22,entry,'breakin');handlers['meta_comic:server:crimeBloodGround'](events[4].data.token,100)")
        self.assertEqual(self.lua.eval('#serverEvents'), 1)

    def test_blood_ground_request_expires_and_rejects_player_movement(self):
        self.lua.execute("MetaComic.CrimeEvidence.failure(22,entry,'breakin');now=1011;handlers['meta_comic:server:crimeBloodGround'](events[2].data.token,30)")
        self.assertEqual(self.lua.eval('#serverEvents'), 0)
        self.lua.execute("MetaComic.CrimeEvidence.failure(22,entry,'breakin');playerCoords=vector3(50,50,30.9);handlers['meta_comic:server:crimeBloodGround'](events[4].data.token,30)")
        self.assertEqual(self.lua.eval('#serverEvents'), 0)

    def test_failed_adapter_does_not_block_other_adapters(self):
        self.lua.execute("table.insert(Config.CrimeEvidence.Adapters,1,{Create=function() error('adapter test') end});resourceStopped=true;MetaComic.CrimeEvidence.start(22,entry,'breakin')")
        self.assertEqual(self.lua.eval('#created'), 1)
        self.assertEqual(self.lua.eval('#events'), 0)

if __name__ == '__main__':
    unittest.main()
