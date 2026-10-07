"""Verify server/shared forbidden zones and placement geometry with native stubs."""
from pathlib import Path
import sys
import unittest
if len(sys.argv) > 1: sys.path.insert(0, sys.argv.pop(1))
from lupa.lua54 import LuaRuntime
ROOT = Path(__file__).resolve().parents[1]

class PlacementTests(unittest.TestCase):
    def setUp(self):
        self.lua=LuaRuntime(unpack_returned_tuples=True)
        self.lua.execute('''
            MetaComic={};Config={VendingMachines={Placement={Enabled=true,ForbiddenZones={}}}}
            cfg=Config.VendingMachines;access={};onRoad=false;obstacle=false;rearWall=true;wallHeight=2;wallY=0.4;blockingY=nil;wallHalfWidth=100;groundZ=0;roadGroundZ=-0.15
            function vec3(x,y,z) return {x=x,y=y,z=z} end
            function GetModelDimensions() return vec3(-0.5,-0.4,0),vec3(0.5,0.4,2) end
            function GetOffsetFromEntityInWorldCoords(_,x,y,z) return vec3(x,y,z) end
            function IsPointOnRoad() return onRoad end
            function StartExpensiveSynchronousShapeTestLosProbe(x1,y1,z1,x2,y2,z2,flags)
                probeCoords=nil;probeNormal=nil
                if flags==1 then
                    local roadProbe=z1-z2>3
                    local ground=roadProbe and roadGroundZ or groundZ
                    if not roadProbe and curbY and y1<curbY then ground=roadGroundZ end
                    probeHit=not missingGround
                    probeCoords=vec3(x1,y1,ground);probeNormal=vec3(0,0,1)
                    return 1
                end
                rearProbe=y2>0.4
                local crossesWall=math.min(y1,y2)<=wallY and math.max(y1,y2)>=wallY
                local crossesBlock=blockingY and math.min(y1,y2)<=blockingY and math.max(y1,y2)>=blockingY
                probeHit=(rearWall and crossesWall and math.abs(x1)<=wallHalfWidth and z1<=wallHeight) or crossesBlock or (not rearProbe and obstacle)
                return 1
            end
            function GetShapeTestResult() return 2,probeHit and 1 or 0,probeCoords,probeNormal end
        ''')
        self.lua.execute((ROOT/'fivem/shared/utils.lua').read_text(encoding='utf-8'))
        script=(ROOT/'fivem/client/vending_machines.lua').read_text(encoding='utf-8')
        actual=script.split('local function placementClear',1)[1].split('local function outline',1)[0]
        self.lua.execute('function placementClear'+actual)
        server=(ROOT/'fivem/server/modules/vending_machines.lua').read_text(encoding='utf-8')
        spot=server.split('local function spotOk',1)[1].split('-- managers:',1)[0]
        self.lua.execute('function finite(value) return type(value)=="number" and value==value end;function near() return not farAway end;function IsPlayerAceAllowed() return aceGranted==true end')
        self.lua.execute('function spotOk'+spot)

    def check(self):
        return self.lua.execute('return placementClear(1,123,vec3(0,0,0),vec3(0,0,1))')

    def test_missing_helper_rejects_without_crashing_or_bypassing_zones(self):
        self.lua.execute('MetaComic.VendingPlacementZone=nil')
        self.assertFalse(self.check()[0])
        self.assertFalse(self.lua.execute('return spotOk(22,0,0,0,0)')[0])
        self.lua.execute('cfg.Placement.Enabled=false')
        self.assertTrue(self.lua.execute('return spotOk(22,0,0,0,0)')[0])

    def test_compatibility_entry_preserves_helper(self):
        self.lua.execute((ROOT/'fivem/shared/vending_placement.lua').read_text(encoding='utf-8'))
        self.assertTrue(self.check())

    def test_clear_wall_location_allowed(self):
        self.assertTrue(self.check())

    def test_road_obstruction_and_path_middle_rejected(self):
        for setting in ['onRoad=true','obstacle=true','rearWall=false']:
            self.lua.execute('onRoad=false;obstacle=false;rearWall=true;wallHeight=2;wallY=0.4;blockingY=nil;wallHalfWidth=100;groundZ=0;roadGroundZ=-0.15;'+setting)
            self.assertFalse(self.check()[0])

    def test_low_rear_wall_and_rear_contact_allowed(self):
        # The rear wall touches the bounding-box edge but does not enter the cabinet.
        self.lua.execute('wallHeight=0.65')
        self.assertTrue(self.check())
        self.lua.execute('cfg.Placement.RearWallProbeHeights={1.0}')
        self.assertFalse(self.check()[0])
        self.lua.execute('cfg.Placement.RearWallProbeHeights={0.6}')
        self.assertTrue(self.check())

    def test_wall_intrusion_and_front_passage_obstruction_rejected(self):
        self.lua.execute('wallY=0.2')
        self.assertFalse(self.check()[0])
        self.lua.execute('wallY=0.4;blockingY=-1.0')
        self.assertFalse(self.check()[0])

    def test_broad_road_region_allows_sidewalk_but_blocks_driving_lanes(self):
        self.lua.execute("""
            onRoad=true;roadY=8;roadZ=0;roadGap=0
            function GetClosestRoad() return true,vec3(-20,roadY,roadZ),vec3(20,roadY,roadZ),2,2,roadGap end
        """)
        self.assertTrue(self.check())  # GTA region includes the plaza; footprint is outside driving lanes.
        self.lua.execute('roadY=0')
        self.assertFalse(self.check()[0])
        self.lua.execute('roadY=7.5')
        self.assertFalse(self.check()[0])  # Centre is clear, but expanded footprint overlaps a lane.
        self.lua.execute('roadY=8;roadGap=2')
        self.assertFalse(self.check()[0])  # Median width is included.
        self.lua.execute('roadY=0;roadZ=-6')
        self.assertTrue(self.check())  # Road runs underneath this plaza.
        self.lua.execute("roadY=8;roadZ=0;roadGap=0;cfg.Placement.RoadCheckMode='native'")
        self.assertFalse(self.check()[0])  # Optional strict compatibility mode.

    def test_lane_estimate_cannot_allow_road_or_straddling_curb(self):
        self.lua.execute("""
            onRoad=true;roadGroundZ=0
            function GetClosestRoad() return true,vec3(-20,8,0),vec3(20,8,0),2,2,0 end
        """)
        self.assertFalse(self.check()[0])  # Same-level road outside an inaccurate lane estimate.
        self.lua.execute('roadGroundZ=-0.15;curbY=0')
        self.assertFalse(self.check()[0])  # Part of the expanded footprint is over the road.
        self.lua.execute('curbY=nil;missingGround=true')
        self.assertFalse(self.check()[0])

    def test_signpost_cannot_supply_rear_support(self):
        self.lua.execute('wallHalfWidth=0.03')
        self.assertFalse(self.check()[0])
        self.lua.execute("""
            onRoad=true;cfg.Placement.RequireRearWall=false
            function GetClosestRoad() return true,vec3(-20,8,0),vec3(20,8,0),2,2,0 end
        """)
        self.assertFalse(self.check()[0])  # Sidewalk exemption still requires broad support.
        self.lua.execute('wallHalfWidth=100')
        self.assertTrue(self.check())

    def test_missing_or_invalid_road_data_keeps_native_restriction(self):
        self.lua.execute('onRoad=true;function GetClosestRoad() return false end')
        self.assertFalse(self.check()[0])
        self.lua.execute('function GetClosestRoad() return true,vec3(0,0,0),vec3(0,0,0),2,2,0 end')
        self.assertFalse(self.check()[0])
        self.lua.execute('function GetClosestRoad() return true,vec3(-20,8,0),vec3(20,8,0),0,0,0 end')
        self.assertFalse(self.check()[0])

    def test_zone_radius_and_rotated_box(self):
        self.lua.execute("cfg.Placement.ForbiddenZones={{Center=vec3(0,0,0),Radius=3,MinZ=-1,MaxZ=2}}")
        self.assertFalse(self.lua.execute('return MetaComic.VendingPlacementZone(3.5,0,0)')[0])
        self.assertTrue(self.lua.execute('return MetaComic.VendingPlacementZone(0,0,10)'))
        self.lua.execute("cfg.Placement.ForbiddenZones={{Center=vec3(0,0,0),Size=vec3(2,10,4),Heading=90}}")
        self.assertFalse(self.lua.execute('return MetaComic.VendingPlacementZone(4,0,0)')[0])
        self.assertTrue(self.lua.execute('return MetaComic.VendingPlacementZone(0,4,0)'))

    def test_ace_preview_bypass_and_disabled_policy(self):
        self.lua.execute('onRoad=true;access.placementBypass=true')
        self.assertTrue(self.check())

    def test_server_rechecks_zones_and_validates_ace(self):
        self.lua.execute("cfg.Placement.BypassAce='placement.bypass';cfg.Placement.ForbiddenZones={{Center=vec3(0,0,0),Radius=3}}")
        self.assertFalse(self.lua.execute('return spotOk(22,0,0,0,0)')[0])
        self.lua.execute('aceGranted=true')
        self.assertTrue(self.lua.execute('return spotOk(22,0,0,0,0)')[0])
        self.lua.execute('farAway=true')
        self.assertFalse(self.lua.execute('return spotOk(22,0,0,0,0)')[0])
        self.lua.execute('access.placementBypass=false;cfg.Placement.Enabled=false')
        self.assertTrue(self.check())

if __name__ == '__main__': unittest.main()
