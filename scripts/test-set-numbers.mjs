import assert from 'node:assert/strict'
import { collectorNumber, setCardSets, subscribeSetNumbers, setNumbersVersion } from '../src/utils/setNumbers.js'

const card = { id: 'copy-id', baseCardId: 'hero', setId: 'alpha', graded: { cert: '123' } }
setCardSets([])
assert.equal(collectorNumber(card), null)
const before = setNumbersVersion()
let changes = 0
const unsubscribe = subscribeSetNumbers(() => { changes += 1 })
setCardSets([{ id: 'alpha', code: 'ALP', cardIds: ['first', 'hero', 'third'] }])
assert.equal(changes, 1)
assert.ok(setNumbersVersion() > before)
assert.equal(collectorNumber(card).label, 'ALP 002/003')
assert.equal(collectorNumber({ id: 'hero' }).label, 'ALP 002/003')
setCardSets([
  { id: 'alpha', code: 'ALP', cardIds: ['hero', 'first', 'third', 'fourth'] },
  { id: 'beta', code: 'BET', cardIds: ['first', 'third', 'hero'] },
])
assert.equal(collectorNumber(card).label, 'ALP 001/004')
assert.equal(collectorNumber({ ...card, setId: 'beta' }).label, 'BET 003/003')
assert.equal(changes, 2)
unsubscribe()
console.log('Collector numbers recover after late set loading and update after membership changes.')
