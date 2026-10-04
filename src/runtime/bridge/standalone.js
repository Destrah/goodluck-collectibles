import { makePack } from '../packLogic'

const listeners = new Set()

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
  async openPack({ cards }) {
    return { ok: true, cards: makePack(cards), source: 'standalone' }
  },
  async openBox() {
    return { ok: true, packs: 12, source: 'standalone' }
  },
  async packProp() { return { ok: true } }, // no character in the browser
  async claimCards() { return { ok: true, given: 0 } }, // no inventory in the browser
  async getCollection() { return { ok: true, cards: [] } },
  async swapBinderCards() { return { ok: true } },
  async getCatalog() { return null },
  async getSets() { return { ok: true, sets: [] } },
  async saveSets(sets) { return { ok: true, sets } },
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
