import assert from 'node:assert/strict'
import { computePrintOdds, setServerOdds, setPrintOdds, oddsFor } from '../src/utils/printOdds.js'
import { makePack } from '../src/runtime/packLogic.js'
const tiers=['common','uncommon','rare','ultra_rare','legendary']
const catalog=tiers.map((tier,i)=>({id:`card${i}`,title:tier,variants:[{id:'base',rarityKey:tier}]}))
const values=computePrintOdds(catalog)
assert.deepEqual([...values.values()],[3,1,0.75,0.2,0.05])
const missingUncommon=computePrintOdds(catalog.filter(card=>card.id!=='card1'))
assert.equal(missingUncommon.get('card2::base'),1.75)
const missingRare=computePrintOdds(catalog.filter(card=>card.id!=='card2'))
assert.equal(missingRare.get('card3::base'),0.95)
const onlyLegendary=computePrintOdds([catalog[4]])
assert.equal(onlyLegendary.get('card4::base'),5)
const weighted=computePrintOdds([{id:'one',chanceWeight:3,variants:[{id:'a',rarityKey:'common',chanceWeight:1},{id:'b',rarityKey:'common',chanceWeight:3}]},
  {id:'two',chanceWeight:1,variants:[{id:'a',rarityKey:'common'}]}])
assert.equal(weighted.get('one::b'),2.8125)
assert.equal([...weighted.values()].reduce((a,b)=>a+b,0),5)
setServerOdds({'card0::base':1},{set:{'card0::base':0.2}})
setPrintOdds(catalog,[])
assert.equal(oddsFor({baseCardId:'card0',variantId:'base',setId:'set'}),0.2)
setServerOdds(null)
let seed=123
Math.random=()=>{seed=(seed*1664525+1013904223)>>>0;return seed/2**32}
for (const cards of [catalog,catalog.filter(card=>card.id!=='card1'),catalog.filter(card=>card.id!=='card2')]) {
  for (let i=0;i<200;i++) {
    const pack=makePack(cards)
    assert.equal(pack.length,5)
    assert.ok(tiers.indexOf(pack[3].rarityKey)>=1)
    assert.ok(tiers.indexOf(pack[4].rarityKey)>=2)
  }
}
console.log('Pack odds and guarantees: passed (600 packs, weighted odds, set authority).')
