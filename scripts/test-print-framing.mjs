import assert from 'node:assert/strict'
import { test } from 'node:test'
import { normalizeCard, resolveCardVariant } from '../src/cardData.js'

const legacy = () => ({
  id: 'base', title: 'Framing test', image: 'https://example.com/art.png',
  imagePositionX: 22, imagePositionY: 35, imageZoom: 160,
  variants: [
    { id: 'regular', image: '', layout: 'classic' },
    { id: 'full', image: '', layout: 'full-art' },
    { id: 'other', image: 'https://example.com/other.png' },
  ],
})

test('legacy base framing migrates to shared-art prints and remains stable', () => {
  const input = legacy()
  const card = normalizeCard(input)
  assert.equal('imagePositionX' in card, false)
  assert.deepEqual(card.variants.map(v => [v.imagePositionX, v.imagePositionY, v.imageZoom]), [
    [22, 35, 160], [22, 35, 160], [50, 50, 100],
  ])
  assert.deepEqual(normalizeCard(card), card)
  assert.equal(resolveCardVariant(input, input.variants[0]).imagePositionX, 22)
})

test('shared artwork and explicit identical URLs retain independent print crops', () => {
  const card = normalizeCard(legacy())
  Object.assign(card.variants[1], { image: card.image, imagePositionX: 80, imagePositionY: 10, imageZoom: 200 })
  const regular = resolveCardVariant(card, 'regular')
  const full = resolveCardVariant(card, 'full')
  assert.equal(regular.image, full.image)
  assert.deepEqual([regular.imagePositionX, regular.imagePositionY, regular.imageZoom], [22, 35, 160])
  assert.deepEqual([full.imagePositionX, full.imagePositionY, full.imageZoom], [80, 10, 200])
})

test('separate artwork preserves explicit print framing and legacy single prints migrate', () => {
  const input = legacy()
  Object.assign(input.variants[2], { imagePositionX: 0, imagePositionY: 100, imageZoom: 180 })
  const other = resolveCardVariant(input, 'other')
  assert.deepEqual([other.imagePositionX, other.imagePositionY, other.imageZoom], [0, 100, 180])
  delete input.variants
  assert.deepEqual(normalizeCard(input).variants.map(v => [v.imagePositionX, v.imagePositionY, v.imageZoom]), [[22, 35, 160]])
})
