import { test } from 'node:test'
import assert from 'node:assert/strict'
import { inspectorInputs } from '../src/collectibles/inspectorRevision.js'
import { queueInspectorBuild } from '../src/collectibles/inspectorLifecycle.js'

test('plushie version edits invalidate the preview without switching items', () => {
  const item = { id:'bear', collectibleType:'plushie', stitchPattern:'running', stitchWidth:2.2, stitchColor:'#f3e6cf', tint:'#c98a5a', tintStrength:20 }
  for (const [field,value] of Object.entries({stitchPattern:'cross',stitchWidth:4,stitchColor:'#112233',tint:'#ffffff',tintStrength:80,imagePositionX:20,imagePositionY:70,imageZoom:150})) {
    assert.notDeepEqual(inspectorInputs({...item,[field]:value}),inspectorInputs(item),field)
  }
  assert.deepEqual(inspectorInputs({...item,chanceWeight:50}),inspectorInputs(item))
  assert.deepEqual(inspectorInputs(structuredClone(item)),inspectorInputs(item))
})

test('rapid edits finish and dispose the pending scene before building the latest one', async () => {
  let release, current=1
  const started=new Promise(resolve => {release=resolve})
  const events=[]
  const first=queueInspectorBuild(Promise.resolve(), {
    isCurrent:()=>current===1,
    build:async()=>{events.push('first build');await started;return {dispose:()=>events.push('first disposed')}},
    publish:()=>events.push('first published'), onError:assert.fail,
  })
  await new Promise(resolve=>setImmediate(resolve))
  current=2
  const second=queueInspectorBuild(first,{isCurrent:()=>current===2,build:()=>{assert.fail('obsolete edit built')},publish:assert.fail,onError:assert.fail})
  current=3
  const third=queueInspectorBuild(second,{isCurrent:()=>current===3,build:async()=>{events.push('latest build');return {}},publish:()=>events.push('latest published'),onError:assert.fail})
  assert.deepEqual(events,['first build'])
  release()
  await third
  assert.deepEqual(events,['first build','first disposed','latest build','latest published'])
})
