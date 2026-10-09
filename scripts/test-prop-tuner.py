"""Run the real reusable calibration tool: admin gating, frozen pose, edits and cleanup."""
from pathlib import Path
import sys
import unittest
if len(sys.argv) > 1:
    sys.path.insert(0, sys.argv.pop(1))
from lupa.lua54 import LuaRuntime
ROOT = Path(__file__).resolve().parents[1]


class PropTunerTests(unittest.TestCase):
    def setUp(self):
        self.lua = LuaRuntime(unpack_returned_tuples=True)
        self.lua.execute('''
            MetaComic={};handlers={};events={};commands={};exported={};source=65535
            function RegisterNetEvent(n,f) handlers[n]=f end
            function AddEventHandler(n,f) events[n]=f end
            function RegisterCommand(n,f) commands[n]=f end
            function exports(n,f) exported[n]=f end
            function GetCurrentResourceName() return 'cards' end
            function vec3(x,y,z) return setmetatable({x=x,y=y,z=z},{__sub=function(a,b) return vec3(a.x-b.x,a.y-b.y,a.z-b.z) end,__len=function(a) return math.sqrt(a.x*a.x+a.y*a.y+a.z*a.z) end}) end
            vector3=vec3;function vec4() return {} end
            function PlayerPedId() return 1 end
            function DoesEntityExist(id) return id~=0 and (id~=2 or not deleted) end
            function GetEntityCoords() return vec3(0,0,0) end
            function IsEntityDead() return dead==true end
            function IsPedRagdoll() return false end
            function IsPedInAnyVehicle() return false end
            function HasEntityBeenDamagedByAnyPed() return damaged==true end
            function ClearEntityLastDamageEntity() damaged=false end
            function IsEntityPositionFrozen() return frozen==true end
            function FreezeEntityPosition(_,value) frozen=value end
            function ClearPedTasks() cleared=true end
            function GetPedBoneIndex(_,bone) return bone end
            function joaat(model) usedModel=model;return 10 end
            function IsModelInCdimage() return true end
            function IsModelValid() return true end
            function RequestModel() end
            function RequestAnimDict() end
            function HasModelLoaded() return true end
            function HasAnimDictLoaded() return true end
            function SetModelAsNoLongerNeeded() end
            function CreateObject(_,_,_,_,networked) privateProp=not networked;deleted=false;return 2 end
            function DeleteEntity() deleted=true end
            function SetEntityCollision() end
            function AttachEntityToEntity(_,_,bone,x,y,z,rx,ry,rz) attachment={bone=bone,x=x,y=y,z=z,rx=rx,ry=ry,rz=rz} end
            function TaskPlayAnim(_,dict,clip) usedDict=dict;usedClip=clip end
            function IsEntityPlayingAnim() return not missingClip end
            function SetEntityAnimSpeed(_,_,_,value) speed=value end
            function SetEntityAnimCurrentTime(_,_,_,value) phase=value end
            function SetIkTarget(_,_,_,_,x,y,z) ik=vec3(x,y,z) end
            function GetOffsetFromEntityInWorldCoords(_,x,y,z) return vec3(x,y,z) end
            function GetHeadingFromVector_2d() return 0 end
            function SetEntityCoordsNoOffset() end
            function SetEntityHeading() end
            function GetGameTimer() return 0 end
            function Wait() if coroutine.isyieldable() then coroutine.yield() end end
            function CreateThread(fn) thread=coroutine.create(fn) end
            function DisableControlAction() end
            function IsDisabledControlJustPressed(_,id) if pressed==id then pressed=nil;return true end;return false end
            function IsDisabledControlPressed() return false end
            function SetTextFont() end;function SetTextScale() end;function SetTextColour() end;function SetTextOutline() end
            function BeginTextCommandDisplayText() end;function AddTextComponentSubstringPlayerName() end;function EndTextCommandDisplayText() end
            function TriggerEvent(_,message) notice=message end
            output={};function print(line) output[#output+1]=line end
            machine={id=1,entity=99};MetaComic.VendingNearestMachine=function() return machine end
            MetaComic.VendingMachineById=function() return machine end
        ''')
        self.lua.execute((ROOT / 'fivem/config.lua').read_text(encoding='utf-8'))
        self.lua.execute((ROOT / 'fivem/client/prop_tuner.lua').read_text(encoding='utf-8'))

    def command(self, *args, vending=False):
        data = self.lua.table_from({'args': self.lua.table_from(args), 'vending': vending})
        self.lua.globals().handlers['meta_comic:client:propTune'](data)

    def frame(self):
        self.lua.execute('assert(coroutine.resume(thread))')

    def test_generic_frozen_pose_edits_print_and_cleanup(self):
        self.command('start', 'prop_cs_padlock', 'dict', 'clip', '64096')
        self.frame()
        self.assertTrue(self.lua.eval('frozen and privateProp and MetaComic.PropTuneBusy()'))
        self.assertEqual(self.lua.eval('speed'), 0)
        self.command('move', '.01', '-.02', '.03')
        self.command('rotate', '0', '180', '90')
        self.assertAlmostEqual(self.lua.eval('attachment.x'), .01)
        self.assertEqual(self.lua.eval('attachment.ry'), 180)
        self.command('phase', '.7'); self.frame()
        self.assertEqual(self.lua.eval('phase'), .7)
        self.command('print')
        self.assertIn('Offset = vec3(0.0100, -0.0200, 0.0300)', self.lua.eval('output[2]'))
        self.command('stop')
        self.assertTrue(self.lua.eval('deleted and not frozen and not MetaComic.PropTuneBusy()'))

    def test_vending_profiles_use_real_props_clips_and_ik(self):
        for profile, model in [('padlock','tr_prop_tr_car_keys_01a'),('cabinet','h4_prop_h4_key_desk_01'),('cashbox','tr_prop_tr_car_keys_01a'),('rack','tr_prop_tr_car_keys_01a'),('install','prop_cs_padlock')]:
            self.setUp(); self.command(profile, vending=True); self.frame()
            self.assertEqual(self.lua.eval('usedModel'), model)
            self.assertEqual(self.lua.eval('attachment.bone'), 64096)
            self.assertIsNotNone(self.lua.eval('ik'))

    def test_keyboard_edits_and_interruption_restore_original_freeze(self):
        self.lua.execute('frozen=true')
        self.command('start','prop','dict','clip')
        self.lua.execute('pressed=175'); self.frame()
        self.assertAlmostEqual(self.lua.eval('attachment.x'), .005)
        self.lua.execute('pressed=45'); self.frame()
        self.lua.execute('pressed=10'); self.frame()
        self.assertEqual(self.lua.eval('attachment.rz'), 2)
        self.lua.execute('damaged=true'); self.frame()
        self.assertTrue(self.lua.eval('deleted and frozen and not MetaComic.PropTuneBusy()'))

    def test_untrusted_event_and_missing_clip_do_not_leave_props(self):
        self.lua.execute('source=1')
        self.command('start','prop','dict','clip')
        self.assertFalse(self.lua.eval('MetaComic.PropTuneBusy()'))
        self.lua.execute('source=65535;missingClip=true')
        self.command('start','prop','dict','clip')
        self.assertTrue(self.lua.eval('deleted and not frozen and not MetaComic.PropTuneBusy()'))

    def test_server_commands_and_export_require_real_admin(self):
        self.lua.execute('''
            MetaComic.CanManage=function() return true end
            MetaComic.CanManageReal=function(src) return src==11 end
            MetaComic.Framework={notify=function() rejected=true end}
            function TriggerClientEvent(_,src,data) sent=src;payload=data end
        ''')
        self.lua.execute((ROOT / 'fivem/server/modules/prop_tuner.lua').read_text(encoding='utf-8'))
        self.lua.execute("commands.proptune(22,{'start','prop','dict','clip'})")
        self.assertIsNone(self.lua.eval('sent'))
        self.lua.execute("commands.vendingkeytune(11,{'cashbox'})")
        self.assertEqual(self.lua.eval('sent'), 11)
        self.assertTrue(self.lua.eval('payload.vending'))
        self.assertFalse(self.lua.eval('exported.StartPropTune(22,{model="prop"})'))


if __name__ == '__main__':
    unittest.main()
