import assert from 'node:assert/strict'
import { readFile } from 'node:fs/promises'
import { test } from 'node:test'

globalThis.window = { GetParentResourceName: () => 'meta-comic' }
const { normalizeCatalogForRuntime } = await import('../src/runtime/catalog.js')
const { normalizeCard } = await import('../src/cardData.js')
globalThis.catalogTestBridge = {}
const source = (await readFile(new URL('../src/runtime/storage/fivem.js', import.meta.url), 'utf8'))
  .replace("import { bridge } from '../bridge'", 'const bridge = globalThis.catalogTestBridge')
const { fivemStorage } = await import(`data:text/javascript;base64,${Buffer.from(source).toString('base64')}`)

test('FiveM empty catalog remains empty instead of loading bundled demo cards', async () => {
  catalogTestBridge.getCatalog = async () => ({ ok: true, cards: [] })
  assert.deepEqual(await fivemStorage.loadCatalog([{ id: 'fake-demo' }]), [])
  assert.deepEqual(normalizeCatalogForRuntime([]), [])
})

test('FiveM uses only persisted cards and keeps IDs stable on reopen', () => {
  const input = [{ id: 'saved-card', title: 'Only persisted card', variants: [{ id: 'saved-print' }] }]
  const first = normalizeCatalogForRuntime(input)
  const reopened = normalizeCatalogForRuntime(input)
  assert.deepEqual(first, reopened)
  assert.equal(first.length, 1)
  assert.equal(first[0].id, 'saved-card')
  assert.equal(first[0].variants[0].id, 'saved-print')
})

test('FiveM never resurrects demo prints or rewrites saved mask effects', () => {
  const card = normalizeCard({ id: 'lab', title: 'Holo Mask Lab', variants: [{
    id: 'print', name: 'Subject Prism Mask', subjectLayers: [{
      id: 'mask', image: 'https://example.com/mask.png', mode: 'foil-flame',
    }],
  }] })
  assert.equal(card.variants.length, 1)
  assert.equal(card.variants[0].subjectLayers[0].mode, 'foil-flame')
  assert.equal(card.variants[0].subjectLayers[0].image, 'https://example.com/mask.png')
})

test('FiveM load errors and invalid responses are surfaced without a demo fallback', async () => {
  catalogTestBridge.getCatalog = async () => { throw new Error('Database unavailable') }
  await assert.rejects(fivemStorage.loadCatalog([{ id: 'fake-demo' }]), /Database unavailable/)
  catalogTestBridge.getCatalog = async () => ({ ok: true })
  await assert.rejects(fivemStorage.loadCatalog(), /invalid card catalog/)
})
