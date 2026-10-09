import assert from 'node:assert/strict'
import {sharePricingRequest} from '../src/runtime/pricingRequests.js'
let resolve, calls=0
const request=()=>{calls++;return new Promise(r=>{resolve=r})}
const a=sharePricingRequest('same',request),b=sharePricingRequest('same',request)
assert.equal(a,b)
await Promise.resolve()
assert.equal(calls,1)
resolve({ok:true})
assert.deepEqual(await a,{ok:true})
await sharePricingRequest('same',()=>{calls++;return 2})
assert.equal(calls,2)
await assert.rejects(sharePricingRequest('failure',()=>Promise.reject(new Error('failed'))))
assert.equal(await sharePricingRequest('failure',()=>3),3)
console.log('Pricing requests: duplicates coalesced; completed/failed requests cleared.')
