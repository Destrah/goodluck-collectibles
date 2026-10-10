"""Check dispatch export payloads and LB Phone delivery to the chip controller."""
from pathlib import Path
import sys
import unittest
import zipfile

if len(sys.argv) > 1:
    sys.path.insert(0, sys.argv.pop(1))
from lupa.lua54 import LuaRuntime

ROOT = Path(__file__).resolve().parents[1]


class PoliceIntegrationTests(unittest.TestCase):
    def setUp(self):
        self.lua = LuaRuntime(unpack_returned_tuples=True)
        self.lua.execute('''
          now=1000;os.time=function() return now end
          Config={VendingMachines={},Police={System='auto',RushDispatchJobs={'lspd','bcso','sasp'},
            Blip={time=90,sprite=52},Alerts={breakin={title='Machine break-in',message='Machine {serial}',chance={start=100,success=100}}},
            Phone={Enabled=true,Recipient='controller',Mode='notification',Stages={start=true,success=true},Cooldown=60}}}
          records={serials={['VM-1']={owner='owner',tampered=false}}}
          MetaComic={Framework={getIdentifier=function(src) return src==11 and 'owner' or 'hacker' end},
            Settings={get=function() return records end,set=function() return true end}}
          function CreateThread() end
          function GetPlayers() return {'11','22'} end
          function GetPlayerName() return 'Player' end
          function GetResourceState(name)
            if name=='rush-dispatch' then return 'started' end
            if name=='lb-phone' and not phoneStopped then return 'started' end
            return 'missing'
          end
          serverEvents={};clientHandlers={};notifications={};messages={};lookups={}
          function TriggerClientEvent(name,target,...) serverEvents[#serverEvents+1]={name=name,target=target,args={...}} end
          function RegisterNetEvent(name,fn) clientHandlers[name]=fn end
          function vector3(x,y,z) return {x=x,y=y,z=z} end
          local phone={}
          phone.GetEquippedPhoneNumber=function(_,target)
            lookups[#lookups+1]=target
            if missingPhone then return nil end
            return target==11 and '5550011' or target==22 and '5550022' or '5550099'
          end
          phone.SendNotification=function(_,target,data)
            if phoneError then error('Unavailable') end
            notifications[#notifications+1]={target=target,data=data};return 1
          end
          phone.SendMessage=function(_,from,to,message) messages[#messages+1]={from=from,to=to,message=message};return {messageId=1} end
          exports=setmetatable({['lb-phone']=phone,['rush-dispatch']={CustomAlert=function(_,data) custom=data end}},
            {__call=function() end})
          alert={action='breakin',stage='start',serial='VM-1',coords={x=1,y=2,z=3}}
        ''')
        self.lua.execute((ROOT / 'fivem/server/modules/vending_registry.lua').read_text(encoding='utf-8'))
        self.lua.execute((ROOT / 'fivem/server/modules/police.lua').read_text(encoding='utf-8'))
        self.lua.execute((ROOT / 'fivem/client/police.lua').read_text(encoding='utf-8'))

    def send(self):
        return self.lua.execute('return MetaComic.Police.alert(99,alert)')

    def test_witness_and_outcome_rules_deduplicate_without_suppressing_phone(self):
        self.lua.execute("""
          Config.Police.CrimeRules={default={witness=100,fail=100,success=100},pickpadlock={witness=100,fail=100,success=0},installskimmer={witness=100,fail=100,success=0}}
          job={action='pickpadlock'};entry={serial='VM-1',x=1,y=2,z=3}
          assert(not MetaComic.Police.attempt(99,job,entry,'breakin','start'))
          assert(not MetaComic.Police.attempt(99,job,entry,'breakin','success'))
          assert(MetaComic.Police.attempt(99,job,entry,'breakin','witness'))
          assert(not MetaComic.Police.attempt(99,job,entry,'breakin','fail'))
          assert(#serverEvents==1)
          job={action='installskimmer'}
          assert(not MetaComic.Police.attempt(99,job,entry,'installskimmer','success'))
          assert(MetaComic.Police.attempt(99,job,entry,'installskimmer','fail'))
          job={action='breakin'}
          assert(MetaComic.Police.attempt(99,job,entry,'breakin','success'))
          Config.Police.CrimeRules.default.fail=0
          assert(not MetaComic.Police.attempt(99,{},entry,'breakin','fail'))
        """)

    def test_rush_export_payload_matches_fork(self):
        self.assertTrue(self.send())
        self.lua.execute("local e=serverEvents[1];clientHandlers[e.name](e.args[1],e.args[2])")
        self.assertEqual(self.lua.eval('custom.dispatchCode'), '10-90')
        self.assertEqual(self.lua.eval('custom.description'), 'Machine VM-1')
        self.assertEqual(self.lua.eval('custom.job[1]'), 'lspd')
        self.assertEqual(self.lua.eval('custom.flash'), 'true')
        self.assertEqual(self.lua.eval('custom.offset'), 'false')
        self.assertAlmostEqual(self.lua.eval('custom.length*128'), 90)

    def test_phone_goes_to_owner_then_os_controller_then_owner_after_recovery(self):
        self.send()
        self.assertEqual(self.lua.eval('lookups[1]'), 11)
        self.lua.execute("records.serials['VM-1'].systemController='hacker'")
        self.send()
        self.assertEqual(self.lua.eval('lookups[2]'), 22)
        self.lua.execute("records.serials['VM-1'].systemController=nil;now=1200")
        self.send()
        self.assertEqual(self.lua.eval('lookups[3]'), 11)
        self.assertEqual(self.lua.eval('notifications[2].target'), '5550022')

    def test_owner_phone_recipient_cannot_bypass_os_telemetry_blackout(self):
        self.lua.execute("records.serials['VM-1'].systemController='hacker';Config.Police.Phone.Recipient='owner'")
        self.send()
        self.assertEqual(self.lua.eval('#notifications'), 0)

    def test_phone_independent_of_police_roll_and_cooldown_stages(self):
        self.lua.execute('Config.Police.Alerts.breakin.chance.start=0')
        self.assertFalse(self.send())
        self.send()
        self.assertEqual(self.lua.eval('#notifications'), 1)
        self.assertEqual(self.lua.eval('#serverEvents'), 0)
        self.lua.execute("alert.stage='success'")
        self.send()
        self.assertEqual(self.lua.eval('#notifications'), 2)

    def test_sms_export_and_sender(self):
        self.lua.execute("Config.Police.Phone.Mode='sms';Config.Police.Phone.FromNumber='5550100'")
        self.send()
        self.assertEqual(self.lua.eval('messages[1].from'), '5550100')
        self.assertEqual(self.lua.eval('messages[1].to'), '5550011')
        self.assertIn('VM-1', self.lua.eval('messages[1].message'))

    def test_police_dispatch_only_runs_at_selected_crime_stage(self):
        self.assertTrue(self.send())
        self.lua.execute("alert.stage='fail'")
        self.assertFalse(self.send())
        self.lua.execute("alert.stage='success'")
        self.assertFalse(self.send())
        self.assertEqual(self.lua.eval('#serverEvents'), 1)
        self.lua.execute("Config.Police.CrimeAlertStage='success'")
        self.assertTrue(self.send())
        self.assertEqual(self.lua.eval('#serverEvents'), 2)

    def test_failed_phone_export_does_not_block_dispatch_or_retry(self):
        self.lua.execute('phoneError=true')
        self.assertTrue(self.send())
        self.lua.execute('phoneError=false')
        self.send()
        self.assertEqual(self.lua.eval('#notifications'), 1)
        self.assertEqual(self.lua.eval('#serverEvents'), 2)

    def test_business_owned_machine_has_no_personal_recipient(self):
        self.lua.execute("records.serials['VM-1'].owner=nil")
        self.send()
        self.assertEqual(self.lua.eval('#lookups'), 0)

    def test_disabled_phone_and_missing_phone_preserve_dispatch(self):
        self.lua.execute('Config.Police.Phone.Enabled=false')
        self.assertTrue(self.send())
        self.assertEqual(self.lua.eval('#lookups'), 0)
        self.lua.execute('Config.Police.Phone.Enabled=true;missingPhone=true')
        self.assertTrue(self.send())
        self.assertEqual(self.lua.eval('#notifications'), 0)

    def test_provided_export_accepts_adapter_payload(self):
        archive = ROOT / '.tmp-rush-dispatch.zip'
        if not archive.exists():
            self.skipTest('Optional supplied dispatch ZIP is not present')
        with zipfile.ZipFile(archive) as z:
            source = z.read('rush-dispatch/client/calls.lua').decode('utf-8')
        start = source.index('local function CustomAlert(data)')
        end = source.index("exports('CustomAlert', CustomAlert)", start)
        self.lua.execute(source[start:end] + '\nProvidedCustomAlert=CustomAlert')
        self.lua.execute("function vec3(x,y,z) return vector3(x,y,z) end;function getStreetandZone() return 'Test Street' end;function TriggerServerEvent(name,data) providedName=name;providedData=data end")
        self.send()
        self.lua.execute("local e=serverEvents[1];clientHandlers[e.name](e.args[1],e.args[2]);ProvidedCustomAlert(custom)")
        self.assertEqual(self.lua.eval('providedName'), 'dispatch:server:notify')
        self.assertEqual(self.lua.eval('providedData.alert.blipflash'), 'true')
        self.assertEqual(self.lua.eval('providedData.alert.recipientList[1]'), 'lspd')
        self.assertEqual(self.lua.eval('providedData.origin.z'), 3)


if __name__ == '__main__':
    unittest.main()
