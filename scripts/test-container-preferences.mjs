import test from 'node:test'
import assert from 'node:assert/strict'
import { openingLook, sanitizeContainerAnimations } from '../src/collectables/containerPrefs.js'

test('legacy and invalid preferences default every container to random', () => {
  assert.deepEqual(sanitizeContainerAnimations({bag:'invalid',box:'pour'}),{bag:'random',box:'random',case:'random'})
})
test('random openings select each supported animation and preserve the sealed design', () => {
  const run={outer:false,container:{kind:'bag',look:{style:'leather',animation:'pop'}}}
  assert.deepEqual([0,.4,.9].map(value=>openingLook(run,{},()=>value).animation),['float','pour','pop'])
  assert.equal(openingLook(run,{},()=>.4).style,'leather')
  assert.equal(run.container.look.animation,'pop')
})
test('fixed player choices apply separately to bags, plushie boxes and outer cases', () => {
  const prefs={containerAnimations:{bag:'pour',box:'burst',case:'unfold'}}
  assert.equal(openingLook({container:{kind:'bag'}},prefs).animation,'pour')
  assert.equal(openingLook({container:{kind:'box'}},prefs).animation,'burst')
  assert.equal(openingLook({outer:true,container:{kind:'bag',outer:{look:{style:'crate'}}}},prefs).animation,'unfold')
})
