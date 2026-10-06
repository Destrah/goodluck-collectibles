import assert from 'node:assert/strict'
import { test } from 'node:test'
import { readMigratedStorage } from '../src/runtime/legacyStorage.js'
import { registerCollectibleType, getCollectibleType } from '../src/collectibles/registry.js'
import { openContainer, openOuterContainer, openSealedContainer, saveSet, saveDefinition, saveCollectibles, loadCollectibles } from '../src/collectibles/standaloneStore.js'

test('standalone branding migration retains saved catalogs and respects newer saves', () => {
  const data = new Map([['rush-tradingcards-react-v3', '[{"id":"existing-card"}]']])
  globalThis.localStorage = { getItem: key => data.get(key) ?? null, setItem: (key, value) => data.set(key, value) }
  assert.equal(readMigratedStorage('meta-comic-collectibles-v3'), '[{"id":"existing-card"}]')
  data.set('meta-comic-collectibles-v3', '[]')
  assert.equal(readMigratedStorage('meta-comic-collectibles-v3'), '[]')
  assert.equal(data.get('rush-tradingcards-react-v3'), '[{"id":"existing-card"}]')
})

test('opening modules uses saved definitions and preserves acquired snapshots after edits and deletes', () => {
  const definition = { id: 'bear', collectibleType: 'plushie', title: 'Original Bear', chanceWeight: 5, fabric: 'Fleece' }
  const data = { definitions: [definition], containers: { plushie: { id: 'plushie_box', itemIds: ['bear'], count: 2 } }, instances: [] }
  let sequence = 0
  const result = openContainer(data, 'plushie', () => 0, () => `instance-${++sequence}`, () => '2026-10-04')
  assert.equal(result.pulled.length, 2)
  assert.equal(data.instances.length, 0)
  assert.notEqual(result.pulled[0], result.data.instances[0])
  const edited = saveDefinition(result.data, { ...definition, title: 'Edited Bear', fabric: 'Cotton' })
  assert.equal(edited.instances[0].title, 'Original Bear')
  edited.definitions = []
  assert.equal(edited.instances[0].fabric, 'Fleece')
  const storageData = new Map()
  const storage = { getItem: key => storageData.get(key) ?? null, setItem: (key, value) => storageData.set(key, value) }
  saveCollectibles(edited, storage)
  assert.deepEqual(loadCollectibles(storage).instances, edited.instances)
})

test('containers isolate types and reject empty or unsaved contents', () => {
  const data = { definitions: [{ id:'coin', collectibleType:'challenge_coin',title:'Coin' }], containers: { plushie:{id:'plushie_box',itemIds:['coin'],count:1} }, instances: [] }
  assert.throws(() => openContainer(data,'plushie'), /at least one/)
  assert.throws(() => openContainer(data,'challenge_coin'), /Save a container/)
  assert.throws(() => saveDefinition(data, {id:'new',title:'   '}), /Enter a name/)
  assert.throws(() => loadCollectibles({getItem: () => '{"definitions":[]}' }), /invalid/)
})

test('collectible dispatch supports new types while legacy cards still resolve as cards', () => {
  const cardRenderer = () => null
  const plushieRenderer = () => null
  registerCollectibleType('trading_card', { render: cardRenderer })
  registerCollectibleType('plushie', { render: plushieRenderer })
  assert.equal(getCollectibleType({ title: 'Old physical card' }).render, cardRenderer)
  assert.equal(getCollectibleType({ collectibleType: 'plushie' }).render, plushieRenderer)
  assert.equal(getCollectibleType({ collectibleType: 'unknown' }), undefined)
  assert.throws(() => registerCollectibleType('plushie', { render: plushieRenderer }), /Duplicate/)
})

test('outer containers retain sealed counts and each inner container is consumed once', () => {
  for (const [typeId, count, outerCount] of [['plushie',1,18],['challenge_coin',3,10]]) {
    const data = { definitions:[{id:'item',title:'Original',collectibleType:typeId}], sets:[], instances:[], sealed:[], containers:{[typeId]:{id:'inner',label:'Inner',setId:'set',count,outer:{count:outerCount}}} }
    const saved = saveSet(data,{id:'set',name:'Set',collectibleType:typeId,itemIds:['item']})
    let sequence=0
    const ids=()=>String(++sequence)
    const outer=openOuterContainer(saved,typeId,ids)
    assert.equal(outer.sealed.length,outerCount)
    assert.equal(outer.data.instances.length,0)
    outer.data.containers[typeId].count=24
    const opened=openSealedContainer(outer.data,outer.sealed[0].instanceId,()=>0,ids)
    assert.equal(opened.pulled.length,count)
    assert.equal(opened.data.sealed.length,outerCount-1)
    assert.equal(opened.data.containers[typeId].count,24)
    assert.throws(()=>openSealedContainer(opened.data,outer.sealed[0].instanceId),/no longer available/)
    const edited=saveDefinition(opened.data,{...data.definitions[0],title:'Updated'})
    assert.equal(edited.instances[0].title,'Original')
    assert.throws(()=>saveSet(edited,{id:'bad',name:'Bad',collectibleType:'another',itemIds:['item']}),/their type/)
  }
})
