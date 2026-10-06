import { makePack } from '../packLogic'
import { recordPulls } from '../../grading/standaloneCopies.js'

const listeners = new Set()
const SETS_KEY = 'meta-comic-card-sets-v1'
const CONTAINERS_KEY = 'meta-comic-card-containers-v1'
const readSets = () => JSON.parse(localStorage.getItem(SETS_KEY) || '[]')
const readContainers = () => JSON.parse(localStorage.getItem(CONTAINERS_KEY) || '{"count":5,"outerCount":12}')

export const standaloneBridge = {
  runtime: 'standalone',
  async getInfo() {
    return {
      runtime: 'standalone',
      framework: 'none',
      persistence: 'localStorage',
      inventory: 'none',
      capabilities: { editor: true, catalogWrite: true, collection: false },
      packAnimation: { maxSpeed: 3, flipAllKey: 'F' },
    }
  },
  async close() { return true },
  async openPack({ cards, set }) {
    const selected = readSets().find(item => item.id === set)
    const pool = selected ? cards.filter(card => selected.cardIds.includes(card.id)) : cards
    if (!pool.length) throw new Error('This card set has no eligible cards.')
    const count = Math.min(24,Math.max(1,Number(readContainers().count) || 5))
    const pulled = []
    while (pulled.length < count) pulled.push(...makePack(pool))
    const pulls = pulled.slice(0,count)
    recordPulls(pulls) // kept so they can be sleeved and graded in the Grading tab
    return { ok: true, cards: pulls, source: 'standalone' }
  },
  async openBox() {
    return { ok: true, packs: Math.min(100,Math.max(1,Number(readContainers().outerCount) || 12)), source: 'standalone' }
  },
  async packProp() { return { ok: true } }, // no character in the browser
  async holdCollectibles() { return { ok: true } },
  async roughHandling() { return { ok: true } }, // standalone wear happens in the Grading tab's copies
  async claimCards() { return { ok: true, given: 0 } }, // no inventory in the browser
  async claimCollectibles() { return { ok: true, given: 0 } },
  async getCollection() { return { ok: true, cards: [] } },
  async swapBinderCards() { return { ok: true } },
  async binderStoreCard() { return { ok: true } }, // the binder preview moves its cards itself
  async binderTakeCard() { return { ok: true } },
  async getPrintOdds() { return null }, // worked out from the local catalogue
  async getCatalog() { return null },
  async getSets() { return { ok: true, sets: readSets() } },
  async saveSets(sets) { localStorage.setItem(SETS_KEY,JSON.stringify(sets));return {ok:true,sets} },
  // vending machines only exist in FiveM; a few demo machines let the map page be checked in the browser
  async getVendingMachines() {
    const sets = readSets()
    const logos = Object.fromEntries(sets.filter(set => set.logo).map(set => [set.id, set.logo]))
    const set = sets[0] || { id: 'base', name: 'Base' }
    const demo = [[1, 195, -933], [2, 1960, 3740], [3, -150, 6350], [4, -1200, -1500]]
    return { ok: true, maxStock: 100, logos, map: {}, machines: demo.map(([id, x, y], i) => ({ id, x, y, z: 30,
      products: [{ set: set.id, setName: set.name, kind: 'pack', price: 250, stock: [42, 0, 7, 100][i] },
        { set: set.id, setName: set.name, kind: 'box', price: 2500, stock: [3, 0, 0, 12][i] }] })) }
  },
  async vendingWaypoint() { return { ok: true } },
  async getCardContainers() {return readContainers()},
  async saveCardContainers(value) {localStorage.setItem(CONTAINERS_KEY,JSON.stringify(value));return {ok:true}},
  async printCard() { return { ok: false, error: 'Manual printing is only available in FiveM.' } },
  async printCollectible() { return { ok: false, error: 'Manual printing is only available in FiveM.' } },
  async createSealed() { return { ok: false, error: 'Sealed item creation is only available in FiveM.' } },
  async saveCatalog() { return { ok: true } },
  subscribe(listener) {
    listeners.add(listener)
    return () => listeners.delete(listener)
  },
  emit(message) {
    listeners.forEach(listener => listener(message))
  },
}
