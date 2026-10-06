import assert from 'node:assert/strict'
import test from 'node:test'
import { conditionStyle, listFlaws, matchMark, textSectionStyle, generateCondition, TEXT_SECTIONS } from '../src/grading/condition.js'
import { readFileSync } from 'node:fs'

test('foil and mask within tolerance render without drift or recoloring', () => {
  const condition = { foil:[.3,.1,10.14], mask:[.64,0] }
  assert.deepEqual(listFlaws(condition,{hasFoil:true,hasMask:true}),[])
  const style = conditionStyle(condition)
  for (const key of ['--foil-on','--foil-dx','--foil-dy','--foil-hue','--mask-dx','--mask-dy']) assert.equal(style[key],0,key)
})

test('real foil and mask flaws keep their visible offsets', () => {
  const condition = { foil:[1.51,0,19], mask:[.81,0] }
  assert.deepEqual(listFlaws(condition,{hasFoil:true,hasMask:true}).map(f=>f.type),['foil','mask'])
  const style=conditionStyle(condition)
  assert.equal(style['--foil-on'],1)
  assert.equal(style['--foil-dx'],1.51)
  assert.equal(style['--foil-hue'],19)
  assert.equal(style['--mask-dx'],.81)
})

test('corner and edge rendering use the same strict wear threshold as grading', () => {
  const source=readFileSync(new URL('../src/grading/ConditionOverlay.jsx',import.meta.url),'utf8')
  assert.match(source,/const VISIBLE = LIMITS\.wear/)
  const condition={corners:{front:[0,.15,.16,0]},edges:{front:[.15,.16,0,0]}}
  assert.deepEqual(listFlaws(condition).map(f=>f.id),['corner-front-2','edge-front-1'])
})

test('a mask-only flaw cannot expose a gap from artwork within tolerance', () => {
  const condition={art:[.3,-.2],mask:[1,0]}
  assert.deepEqual(listFlaws(condition,{hasMask:true}).map(f=>f.type),['mask'])
  const style=conditionStyle(condition)
  assert.equal(style['--art-dx'],0)
  assert.equal(style['--art-dy'],0)
  assert.equal(style['--mask-dx'],1)
  assert.equal(condition.art[0],.3) // historical metadata is unchanged
})

test('artwork past tolerance retains its actual displacement', () => {
  const style=conditionStyle({art:[.61,-.2]})
  assert.equal(style['--art-dx'],.61)
  assert.equal(style['--art-dy'],-.2)
})

test('normal centering cannot change border pixel widths on a mask-only flaw', () => {
  const condition={centering:{front:[.06,-.04],back:[.5,-.3]},mask:[1,0]}
  assert.deepEqual(listFlaws(condition,{hasMask:true}).map(f=>f.type),['mask'])
  for (const side of ['front','back']) {
    const style=conditionStyle(condition,side)
    assert.equal(style['--cx'],0)
    assert.equal(style['--cy'],0)
  }
  assert.equal(condition.centering.front[0],.06)
  assert.equal(conditionStyle({centering:{front:[.11,-.04]}})['--cx'],.11)
  assert.equal(conditionStyle({centering:{back:[.51,-.3]}},'back')['--cx'],.51)
})

test('text grading requires an identified text block at its shifted position', () => {
  const flaws=listFlaws({text:[1,0]},{layout:'illustration'})
  assert.equal(matchMark(flaws,{type:'text',x:50,y:40}),null)
  assert.equal(matchMark(flaws,{type:'text',textPart:'title',x:50,y:40}),null)
  assert.equal(matchMark(flaws,{type:'centering',x:50,y:40}),null)
  assert.equal(matchMark(flaws,{type:'text',textPart:'title',x:20,y:9}).id,'text')
  assert.equal(matchMark(flaws,{type:'text',textPart:'title',x:20,y:9},['text']),null)
})

test('independent text sections render and grade separately', () => {
  const condition={v:2,text:{title:[1,0],description:[0,.7],hp:[0,0]}}
  const flaws=listFlaws(condition,{layout:'illustration'})
  assert.deepEqual(flaws.map(f=>f.id),['text-title','text-description'])
  assert.deepEqual(textSectionStyle(condition,'hp'),{})
  assert.ok(textSectionStyle(condition,'title').transform)
  assert.equal(matchMark(flaws,{type:'text',textPart:'hp',x:90,y:8}),null)
  assert.equal(matchMark(flaws,{type:'text',textPart:'title',x:20,y:9}).id,'text-title')
  assert.equal(matchMark(flaws,{type:'text',textPart:'description',x:20,y:62},['text-title']).id,'text-description')
  assert.equal(matchMark(flaws,{type:'centering',textPart:'title',x:20,y:9}),null)
  const generated=generateCondition()
  assert.equal(generated.v,2)
  assert.deepEqual(Object.keys(generated.text),TEXT_SECTIONS)
})
