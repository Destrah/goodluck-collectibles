import assert from 'node:assert/strict'
import { packStats, priceComparison, previewPackPricing } from '../src/runtime/packPricing.js'
const stats=packStats([10,20,30,40],25,125)
assert.equal(stats.mean,25)
assert.equal(stats.median,20)
assert.equal(stats.exact,true)
const comparison=priceComparison(stats,{packPrice:30,supplyCost:5,fee:10,margin:20,gradingCost:5})
assert.equal(comparison.playerProfit,-10)
assert.equal(comparison.breakEvenChance,.25)
assert.equal(comparison.retailMargin,22)
assert.equal(comparison.buybackMargin,-3)
assert.equal(comparison.targetPrice,43)
assert.equal(priceComparison(stats,{fee:80,margin:20}).targetPrice,null)
const cards=[{id:'common',title:'Common',variants:[{id:'base',rarityKey:'common'}]}]
const preview=previewPackPricing(cards,{id:'test',name:'Test',cardIds:['common']},100)
assert.equal(preview.clean.mean,5)
assert.equal(preview.fresh.mean,5)
assert.equal(preview.clean.variance,0)
console.log('Pricing comparison and standalone projections passed.')
