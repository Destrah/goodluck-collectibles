"""Real client menu flow: visual keys, delayed requests, interruption and confirmed opening."""
from pathlib import Path
import sys
import unittest
if len(sys.argv) > 1:
    sys.path.insert(0, sys.argv.pop(1))
from lupa.lua54 import LuaRuntime
ROOT = Path(__file__).resolve().parents[1]


class KeyAnimationTests(unittest.TestCase):
    def setUp(self):
        self.lua = LuaRuntime(unpack_returned_tuples=True)
        self.lua.execute('''
            local mt={__sub=function(a,b) return vec3(a.x-b.x,a.y-b.y,a.z-b.z) end,
                __len=function(v) return math.sqrt(v.x*v.x+v.y*v.y+v.z*v.z) end}
            function vec3(x,y,z) return setmetatable({x=x,y=y,z=z},mt) end
            vector3=vec3
            function vec4(x,y,z,w) return {x=x,y=y,z=z,w=w} end
            Config={VendingMachines={Keys={Enabled=true}}};MetaComic={};handlers={};localEvents={};threads={}
            timer=0;player=vec3(0,-1,-.95);objects={[99]=true};server={};deleted=0;gestures=0
            function RegisterNetEvent(n,f) handlers[n]=f end
            function AddEventHandler(n,f) localEvents[n]=f end
            function GetCurrentResourceName() return 'meta-comic' end
            function GetResourceState() return 'started' end
            function GetGameTimer() return timer end
            function Wait(ms)
                timer=timer+math.max(100,ms);if interruptWalk then damaged=true end
                if coroutine.isyieldable() then coroutine.yield() end
            end
            function PlayerPedId() return 1 end
            function IsPedInAnyVehicle() return false end
            function IsEntityDead() return false end
            function IsPedRagdoll() return false end
            function IsPedBeingStunned() return false end
            function HasEntityBeenDamagedByAnyPed() return damaged==true end
            function ClearEntityLastDamageEntity() damaged=false end
            function DoesEntityExist(id) return objects[id]==true end
            function GetOffsetFromEntityInWorldCoords(_,x,y,z) return vec3(x,y,z) end
            function GetHeadingFromVector_2d(x,y) faceX=x;faceY=y;return 0 end
            function GetEntityCoords() return player end
            function ClearPedTasks() end
            function TaskGoStraightToCoord(_,x,y,z) walked=true;player=vec3(x,y,z) end
            function SetEntityCoordsNoOffset(_,x,y,z) snapAt=timer;player=vec3(x,y,z) end
            function SetEntityHeading() end
            function joaat(model) modelName=model;return 5 end
            function IsModelInCdimage() return true end
            function RequestModel() end
            function HasModelLoaded() return true end
            function SetModelAsNoLongerNeeded() end
            function CreateObject() objects[100]=true;return 100 end
            function DeleteEntity(id) objects[id]=nil;deleted=deleted+1 end
            function SetEntityCollision() end
            function GetPedBoneIndex(_,bone) return bone end
            function AttachEntityToEntity(_,_,bone,x,y,z,rx,ry,rz) attached=true;attachedBone=bone;keyRotation=vec3(rx,ry,rz) end
            function SetIkTarget(_,part,_,_,x,y,z,flags) ikPart=part;ikTarget=vec3(x,y,z);ikFlags=flags end
            function CreateThread(fn) threads[#threads+1]=coroutine.create(fn) end
            function TriggerServerEvent(name,id,mode)
                server[#server+1]={name=name,id=id,mode=mode,at=timer}
                if name=='meta_comic:server:vendingKeyCloseForLock' and not rejectClose then
                    source=65535;handlers['meta_comic:client:vendingKeyCloseForLock'](id);source=nil
                    doorClosingUntil=timer+1200
                    lidClosingUntil=timer+2600
                elseif mode==false and (name=='meta_comic:server:vendingCashboxKey' or name=='meta_comic:server:vendingRackKey') and not rejectClose then
                    local kind=name=='meta_comic:server:vendingCashboxKey' and 'cashbox' or 'rack'
                    source=65535;handlers['meta_comic:client:vendingKeyCloseForLock'](id,kind);source=nil
                    lidClosingUntil=timer+2600
                end
            end
            function TriggerEvent() end
            function RequestAnimDict() end
            function HasAnimDictLoaded() return true end
            function TaskPlayAnim() gestures=gestures+1 end
            MetaComic.VendingMachineById=function() return {entity=99} end
            MetaComic.VendingDoorOpen=function() return doorClosingUntil and timer<doorClosingUntil end
            MetaComic.VendingLockPartsOpen=function(_,kind)
                return lidClosingUntil and timer<lidClosingUntil or kind=='cylinder' and MetaComic.VendingDoorOpen()
            end
            exports=setmetatable({ox_lib={
                registerContext=function(_,data) menu=data end,showContext=function() end,
                progressBar=function(_,data)
                    progress=data;keyDuringProgress=objects[100]==true;requestsBefore=#server
                    timer=timer+data.duration*.5
                    if interruptProgress then damaged=true end
                    if moveDuringProgress then player=vec3(player.x+.8,player.y,player.z) end
                    if stopResource then localEvents.onResourceStop('meta-comic') end
                    local ok,err=coroutine.resume(threads[#threads]);assert(ok,err)
                    timer=timer+data.duration*.5
                    return not canceled
                end,
                progressActive=function() return true end,
                cancelProgress=function() canceled=true end}}, {__call=function() end})
        ''')
        self.lua.execute((ROOT / 'fivem/config.lua').read_text(encoding='utf-8'))
        self.lua.execute((ROOT / 'fivem/client/vending_keys.lua').read_text(encoding='utf-8'))

    def select(self, padlock=False):
        self.lua.execute("handlers['meta_comic:client:vendingKeyMenu']({id=1,serial='VM',lockId='C1',condition='intact',hasKey=true,padlock=" + ('true' if padlock else 'false') + "});menu.options[2].onSelect()")

    def test_key_is_held_until_animation_completes_before_unlock_request(self):
        self.select()
        self.assertTrue(self.lua.eval('keyDuringProgress and attached and walked'))
        self.assertEqual(self.lua.eval('modelName'), 'h4_prop_h4_key_desk_01')
        self.assertEqual(self.lua.eval('attachedBone'), 64096)
        self.assertEqual(self.lua.eval('progress.anim.clip'), 'action')
        self.assertIn('jailor_key_turn', self.lua.eval('progress.anim.dict'))
        self.assertAlmostEqual(self.lua.eval('ikTarget.z'), .24)
        self.assertEqual(self.lua.eval('requestsBefore'), 0)
        self.assertEqual(self.lua.eval('server[1].name'), 'meta_comic:server:vendingKeyUnlock')
        self.assertGreaterEqual(self.lua.eval('snapAt'), 1000)
        self.assertFalse(self.lua.eval('objects[100]==true'))
        self.assertFalse(self.lua.eval('MetaComic.VendingKeyWorkBusy()'))
        self.assertEqual(self.lua.eval('gestures'), 0)
        self.lua.execute("source=65535;handlers['meta_comic:client:vendingKeyUnlocked']({id=1,open=true})")
        self.assertEqual(self.lua.eval('gestures'), 1)

    def test_padlock_uses_its_spot_and_is_removed_only_after_animation(self):
        self.select(True)
        self.assertEqual(self.lua.eval('modelName'), 'tr_prop_tr_car_keys_01a')
        self.assertAlmostEqual(self.lua.eval('player.x'), .48)
        self.assertAlmostEqual(self.lua.eval('ikTarget.x'), .58)
        self.assertAlmostEqual(self.lua.eval('ikTarget.z'), .14)
        self.assertEqual(self.lua.eval('keyRotation.z'), -90)
        self.assertEqual(self.lua.eval('attachedBone'), 64096)
        self.assertEqual(self.lua.eval('server[1].name'), 'meta_comic:server:vendingPadlock')
        self.assertEqual(self.lua.eval('server[1].mode'), 'remove')
        self.assertEqual(self.lua.eval('requestsBefore'), 0)

    def test_canceled_or_interrupted_key_use_never_unlocks(self):
        for flag in ['canceled', 'interruptProgress', 'interruptWalk', 'stopResource', 'moveDuringProgress']:
            self.setUp()
            self.lua.execute(flag + '=true')
            self.select()
            self.assertEqual(self.lua.eval('#server'), 0, flag)
            self.assertFalse(self.lua.eval('objects[100]==true'), flag)
            self.assertFalse(self.lua.eval('MetaComic.VendingKeyWorkBusy()'), flag)

    def test_model_floor_height_does_not_cancel_settled_player(self):
        self.lua.execute('player=vec3(0,-1,10)')
        self.select(True)
        self.assertEqual(self.lua.eval('#server'), 1)
        self.assertEqual(self.lua.eval('player.z'), 10)
        self.assertFalse(self.lua.eval('canceled==true'))

    def test_interior_locks_use_car_key_prop_and_existing_server_actions(self):
        for index, event in [(2, 'meta_comic:server:vendingCashboxKey'), (3, 'meta_comic:server:vendingRackKey')]:
            self.setUp()
            self.lua.execute("handlers['meta_comic:client:vendingKeyMenu']({id=1,serial='VM',lockId='C1',condition='intact',session=true,cabinetOpen=true,fullSession=true,boxEnabled=true,rackEnabled=true});menu.options[" + str(index) + "].onSelect()")
            self.assertEqual(self.lua.eval('modelName'), 'tr_prop_tr_car_keys_01a')
            self.assertEqual(self.lua.eval('attachedBone'), 64096)
            self.assertTrue(self.lua.eval('keyDuringProgress'))
            self.assertEqual(self.lua.eval('server[1].name'), event)
            self.assertTrue(self.lua.eval('server[1].mode'))
            self.assertEqual(self.lua.eval('ikPart'), 4)
            self.assertEqual(self.lua.eval('ikFlags'), 16)
            if index == 2:
                self.assertEqual(self.lua.eval('progress.anim.clip'), 'machinic_loop_mechandplayer')
                self.assertAlmostEqual(self.lua.eval('player.y'), -.64)
                self.assertGreater(self.lua.eval('ikTarget.y'), 0)  # behind the front panel
                self.assertLess(self.lua.eval('ikTarget.z'), -.5)  # bottom of the cabinet
            else:
                self.assertEqual(self.lua.eval('progress.anim.clip'), 'unlock_loop_janitor')

    def test_unconfirmed_or_forged_opening_does_not_play_gesture(self):
        self.lua.execute("source=65535;handlers['meta_comic:client:vendingKeyUnlocked']({id=1,open=true})")
        self.assertEqual(self.lua.eval('gestures'), 0)
        self.select()
        self.lua.execute("source=1;handlers['meta_comic:client:vendingKeyUnlocked']({id=1,open=true})")
        self.assertEqual(self.lua.eval('gestures'), 0)
        self.lua.execute("source=65535;handlers['meta_comic:client:vendingKeyUnlocked']({id=1,open=false})")
        self.assertEqual(self.lua.eval('gestures'), 0)

    def test_padlock_install_holds_padlock_before_server_consumes_item(self):
        self.lua.execute("handlers['meta_comic:client:vendingKeyMenu']({id=1,serial='VM',lockId='C1',condition='intact',canPadlock=true,hasPadlockItem=true});menu.options[2].onSelect()")
        self.assertEqual(self.lua.eval('modelName'), 'prop_cs_padlock')
        self.assertTrue(self.lua.eval('keyDuringProgress'))
        self.assertEqual(self.lua.eval('requestsBefore'), 0)
        self.assertEqual(self.lua.eval('server[1].name'), 'meta_comic:server:vendingPadlock')
        self.assertEqual(self.lua.eval('server[1].mode'), 'install')
        self.assertFalse(self.lua.eval('objects[100]==true'))

    def test_lock_requests_wait_for_key_pose(self):
        for index, event, prop in [(2, 'meta_comic:server:vendingCashboxKey', 'tr_prop_tr_car_keys_01a'),
                                   (3, 'meta_comic:server:vendingRackKey', 'tr_prop_tr_car_keys_01a'),
                                   (4, 'meta_comic:server:vendingKeyLock', 'h4_prop_h4_key_desk_01')]:
            self.setUp()
            self.lua.execute("handlers['meta_comic:client:vendingKeyMenu']({id=1,serial='VM',lockId='C1',condition='intact',session=true,cabinetOpen=true,fullSession=true,boxEnabled=true,rackEnabled=true,boxOpen=true,rackOpen=true});menu.options[" + str(index) + "].onSelect()")
            self.assertEqual(self.lua.eval('modelName'), prop)
            self.assertEqual(self.lua.eval('requestsBefore'), 1)
            self.assertEqual(self.lua.eval('server[#server].name'), event)
            if index < 4:
                self.assertFalse(self.lua.eval('server[1].mode'))
                self.assertEqual(self.lua.eval('#server'), 1)  # no duplicate close after the pose
            else:
                self.assertEqual(self.lua.eval('server[1].name'), 'meta_comic:server:vendingKeyCloseForLock')
            self.assertGreaterEqual(self.lua.eval('snapAt'), 3600)  # waits for lids, not just the front door

    def test_unconfirmed_close_never_starts_cabinet_key_pose_or_locks(self):
        self.lua.execute("rejectClose=true;MetaComic.VendingUseKeyAtLock(1,'cylinder','lock')")
        self.assertIsNone(self.lua.eval('progress'))
        self.assertEqual(self.lua.eval('#server'), 1)
        self.assertFalse(self.lua.eval('objects[100]==true'))
        self.assertFalse(self.lua.eval('MetaComic.VendingKeyWorkBusy()'))

    def test_canceled_lock_pose_leaves_only_confirmed_close_request(self):
        self.lua.execute("canceled=true;MetaComic.VendingUseKeyAtLock(1,'cylinder','lock')")
        self.assertTrue(self.lua.eval('keyDuringProgress'))
        self.assertEqual(self.lua.eval('#server'), 1)
        self.assertFalse(self.lua.eval('objects[100]==true'))

    def test_canceled_padlock_install_never_requests_consumption(self):
        self.lua.execute("canceled=true;handlers['meta_comic:client:vendingKeyMenu']({id=1,serial='VM',lockId='C1',condition='intact',canPadlock=true,hasPadlockItem=true});menu.options[2].onSelect()")
        self.assertEqual(self.lua.eval('#server'), 0)
        self.assertFalse(self.lua.eval('objects[100]==true'))


if __name__ == '__main__':
    unittest.main()
