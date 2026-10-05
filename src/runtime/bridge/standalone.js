import { makePack } from '../packLogic'

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
    return { ok: true, cards: pulled.slice(0,count), source: 'standalone' }
  },
  async openBox() {
    return { ok: true, packs: Math.min(100,Math.max(1,Number(readContainers().outerCount) || 12)), source: 'standalone' }
  },
  async packProp() { return { ok: true } }, // no character in the browser
  async claimCards() { return { ok: true, given: 0 } }, // no inventory in the browser
  async claimCollectibles() { return { ok: true, given: 0 } },
  async getCollection() { return { ok: true, cards: [] } },
  async swapBinderCards() { return { ok: true } },
  async getCatalog() { return null },
  async getSets() { return { ok: true, sets: readSets() } },
  async saveSets(sets) { localStorage.setItem(SETS_KEY,JSON.stringify(sets));return {ok:true,sets} },
  async getCardContainers() {return readContainers()},
  async saveCardContainers(value) {localStorage.setItem(CONTAINERS_KEY,JSON.stringify(value));return {ok:true}},
  async printCard() { return { ok: false, error: 'Manual printing is only available in FiveM.' } },
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
