import assert from 'node:assert/strict'
import { shareRead } from '../src/runtime/sharedReads.js'
import { portalNeedsCatalog } from '../src/runtime/portalBoot.js'
assert.equal(portalNeedsCatalog(true, 'admin', ['vending', 'records', 'pricing', 'minigames'], ''), false)
assert.equal(portalNeedsCatalog(true, 'admin', ['vending', 'editor'], ''), true)
assert.equal(portalNeedsCatalog(true, 'admin', [], 'vending'), false)
assert.equal(portalNeedsCatalog(true, 'admin', [], ''), true)
assert.equal(portalNeedsCatalog(false, 'admin', ['vending'], ''), true)
assert.equal(portalNeedsCatalog(true, 'binder', [], ''), true)
let calls=0, resolve
const read=()=>{calls++;return new Promise(done=>{resolve=done})}
const a=shareRead('map',read), b=shareRead('map',read)
assert.equal(a,b)
await Promise.resolve();assert.equal(calls,1);resolve({machines:[]});await a
const c=shareRead('map',read);await Promise.resolve();assert.equal(calls,2);resolve({machines:[1]});assert.deepEqual(await c,{machines:[1]})
await assert.rejects(shareRead('failure',()=>Promise.reject(new Error('failed'))))
assert.equal(await shareRead('failure',()=>42),42)
console.log('Portal catalogue selection and coalesced fresh reads passed.')
