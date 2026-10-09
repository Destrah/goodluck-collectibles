"""Run camera placement, same-frame edits/export, cancellation and real admin gating."""
from pathlib import Path
import sys
import unittest
sys.path.insert(0,str(Path(__file__).resolve().parents[1]/'.tmp-mysql-tests'))
from lupa.lua54 import LuaRuntime
ROOT=Path(__file__).resolve().parents[1]

class ZoneTests(unittest.TestCase):
    def setUp(self):
        self.lua=LuaRuntime(unpack_returned_tuples=True)
        self.lua.execute('''
        Config={CardBuyers={}};MetaComic={};handlers={};commands={};exported={};frame=0;pressed={}
        local mt={};mt.__add=function(a,b) return vec3(a.x+b.x,a.y+b.y,a.z+b.z) end
        mt.__mul=function(a,b) return vec3(a.x*b,a.y*b,a.z*b) end
        function vec3(x,y,z) return setmetatable({x=x,y=y,z=z},mt) end;vector3=vec3
        function MetaComic.CopyTable(t) local r={} for k,v in pairs(t) do r[k]=type(v)=='table' and MetaComic.CopyTable(v) or v end return r end
        function RegisterNetEvent(n,f) handlers[n]=f end;function AddEventHandler(n,f) handlers[n]=f end
        function RegisterCommand(n,f) commands[n]=f end;function exports(n,f) exported[n]=f end
        function TriggerEvent(_,msg) notice=msg end;function TriggerClientEvent(_,source) sent=source end
        function GetCurrentResourceName() return 'cards' end
        function GetResourceState() return 'missing' end;function IsNuiFocused() return focused==true end
        function PlayerPedId() return 1 end;function GetEntityHeading() return 0 end
        function GetGameplayCamCoord() return vec3(0,0,1) end
        function GetGameplayCamRot() return vec3(0,0,0) end
        function StartExpensiveSynchronousShapeTestLosProbe(...) probe={...};return 1 end
        function GetShapeTestResult() return 2,noHit and 0 or 1,vec3(10,20,0) end
        function GetEntityCoords() return vec3(9,19,0) end
        function GetGameTimer() return frame*100 end
        function IsEntityDead() return dead==true end;function IsPedInAnyVehicle() return vehicle==true end
        function DisableControlAction() end;function IsControlPressed() return false end
        function IsControlJustPressed(_,key) return pressed[key]==true end;IsDisabledControlJustPressed=IsControlJustPressed
        function DrawLine() lines=(lines or 0)+1 end
        function SetTextFont() end;function SetTextScale() end;function SetTextColour() end;function SetTextOutline() end
        function BeginTextCommandDisplayText() end;function AddTextComponentSubstringPlayerName(t) hud=t end
        function EndTextCommandDisplayText() end
        function CreateThread(f) thread=coroutine.create(f) end;function Wait() coroutine.yield() end
        function step(keys) pressed=keys or {};frame=frame+1;local ok,err=coroutine.resume(thread);if not ok then error(err) end end
        ''')
        self.lua.execute((ROOT/'fivem/client/box_zone_tool.lua').read_text())

    def test_camera_pin_adjust_export_and_defensive_copy(self):
        self.lua.execute("handlers['meta_comic:client:boxZoneTool']({name='counter'});step({[24]=true});step({[175]=true});step({[241]=true});step({[175]=true});step({[241]=true,[191]=true,[47]=true})")
        result=self.lua.globals().exported.GetLastBoxZone()
        self.assertAlmostEqual(result.coords.z,1.55)
        self.assertAlmostEqual(result.size.y,4.1)
        self.assertAlmostEqual(result.size.z,3.1)
        self.assertEqual(result.spot.x,9)
        self.assertEqual(self.lua.globals().probe[5],30)
        result.size.x=99
        self.assertEqual(self.lua.globals().exported.GetLastBoxZone().size.x,4)

    def test_no_hit_instructions_and_cancel_without_export(self):
        self.lua.execute("noHit=true;handlers['meta_comic:client:boxZoneTool']({});step({[191]=true});step({[177]=true})")
        self.assertIn('collision surface',self.lua.globals().hud)
        self.assertIsNone(self.lua.globals().exported.GetLastBoxZone())
        self.assertIsNone(self.lua.globals().lines)

    def test_arrows_cycle_size_and_rotation_without_tab(self):
        self.lua.execute("handlers['meta_comic:client:boxZoneTool']({});step({[24]=true});step({[37]=true});step({[241]=true});step({[175]=true});step({[175]=true});step({[175]=true});step({[241]=true});step({[174]=true});step({[241]=true,[191]=true})")
        result=self.lua.globals().exported.GetLastBoxZone()
        self.assertAlmostEqual(result.size.x,4.1)
        self.assertAlmostEqual(result.size.y,4)
        self.assertAlmostEqual(result.size.z,3.1)
        self.assertEqual(result.heading,5)

    def test_focus_and_vehicle_safely_cancel(self):
        self.lua.execute("focused=true;handlers['meta_comic:client:boxZoneTool']({})")
        self.assertIsNone(self.lua.globals().thread)
        self.lua.execute("focused=false;handlers['meta_comic:client:boxZoneTool']({});vehicle=true;step()")
        self.assertIsNone(self.lua.globals().exported.GetLastBoxZone())

    def test_opening_inventory_during_preview_cancels_with_reason(self):
        self.lua.execute("handlers['meta_comic:client:boxZoneTool']({});step();focused=true;step()")
        self.assertIn('menu opened',self.lua.globals().notice)
        self.assertIsNone(self.lua.globals().exported.GetLastBoxZone())

    def test_server_uses_real_permission(self):
        self.lua.execute("MetaComic.Framework={notify=function() end};MetaComic.CanManage=function() return true end;MetaComic.CanManageReal=function() return real==true end")
        self.lua.execute((ROOT/'fivem/server/modules/box_zone_tool.lua').read_text())
        self.lua.execute('commands.cardzone(1,{})')
        self.assertIsNone(self.lua.globals().sent)
        self.lua.execute('real=true;commands.cardzone(1,{})')
        self.assertEqual(self.lua.globals().sent,1)

if __name__=='__main__':unittest.main()

