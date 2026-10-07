import { DEMO_PRESETS } from '../../minigames/presets.js'
import { makePack } from '../packLogic'
import { recordPulls } from '../../grading/standaloneCopies.js'

// demo data so the Crafting tab can be tried outside FiveM (nothing is saved)
const demoCrafting = () => {
    return { ok: true, custom: false, resultTypes: ['container', 'crate', 'item', 'sealed', 'vending'], collectibles: ['challenge_coin', 'plushie'],
      stations: [{ id: 'shop_bench', label: 'Collectibles workbench' }], crates: [{ id: 'mixed', label: 'Mixed shipment' }],
      recipes: [
        { id: 'booster_pack', label: 'Booster Pack', category: 'Cards', time: 4000, money: 0, account: 'cash', enabled: true, jobs: {}, result: { type: 'sealed', kind: 'pack', count: 1 }, ingredients: [{ item: 'paper', count: 2 }, { item: 'plastic', count: 1 }] },
        { id: 'card_sleeve', label: 'Card Sleeves (10)', category: 'Supplies', time: 3000, money: 0, account: 'cash', enabled: true, jobs: {}, result: { type: 'item', item: 'card_sleeve', count: 10 }, ingredients: [{ item: 'plastic', count: 1 }] },
        { id: 'shipping_crate', label: 'Shipping Crate', category: 'Shipping', time: 20000, money: 500, account: 'bank', enabled: true, jobs: { cardshop: 1 }, result: { type: 'crate', crate: 'mixed', count: 1 }, ingredients: [{ item: 'wood', count: 10 }, { item: 'boosterbox', count: 2 }] },
      ] }
  }

// demo machine records for the Machine records tab outside FiveM (kept in memory only)
const demoRecords = {
  ok: true, keysEnabled: true, business: 'Collectibles Co.', businessRouting: '000000001', businessPending: 1250, defaultTax: 10, online: [{ serverId: 3, id: 'ABC12345', name: 'Sam Rivera' }],
  people: [{ id: 'XYZ98765', name: 'Jordan Lee', routing: '483920175', tax: 15, machines: 1, pending: 400, registeredAt: 1790000000 }],
  machines: [
    { serial: 'VM-7F3K-2Q9D', owner: 'business', ownerName: 'Collectibles Co.', routing: '000000001', routingName: 'Collectibles Co.', ownerRouting: '000000001', tax: 0, tampered: false, status: 'placed', coords: { x: 195, y: -933, z: 30 }, cash: 750, history: [{ at: 1790000000, event: 'Placed by the business', by: 'Alex' }] },
    { serial: 'VM-M4XP-8RTA', owner: 'XYZ98765', ownerName: 'Jordan Lee', routing: '771204983', routingName: 'Unknown account', ownerRouting: '483920175', tax: 15, tampered: true, status: 'stolen', holder: { name: 'Unknown' }, history: [{ at: 1790003600, event: 'Stolen' }, { at: 1790003000, event: 'Payment routing changed' }, { at: 1790000000, event: 'Assigned to Jordan Lee', by: 'Alex' }] },
  ],
}
// Include a retired cylinder/key so evidence records can be inspected in standalone mode.
for (const machine of demoRecords.machines) {
  machine.lockId = `${machine.serial}-C0002`
  machine.lockCondition = 'intact'
  machine.keyArchive = {
    cylinders: [
      { id: `${machine.serial}-C0001`, generation: 1, installedAt: 1790000000, installedBy: 'Alex', retiredAt: 1790003600, retiredBy: 'Alex' },
      { id: machine.lockId, generation: 2, installedAt: 1790003600, installedBy: 'Alex' },
    ],
    keys: [{ id: `${machine.serial}-K000001`, lockId: `${machine.serial}-C0001`, access: 'full', issuedAt: 1790000000, issuedTo: 'XYZ98765', issuedToName: 'Jordan Lee', issuedBy: 'DEMO-STAFF', issuedByName: 'Alex' }],
  }
}

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
  async getCrafting() { return demoCrafting() },
  async saveCrafting(payload) { const current = demoCrafting(); return payload?.reset ? current : { ...current, custom: true, recipes: payload.recipes } },
  async getVendingRecords() { return structuredClone(demoRecords) },
  async getMinigames() { return { ok: true, presets: DEMO_PRESETS } }, // built-in games play in the page
  async testMinigame() { return { ok: false, error: 'Only in game.' } },
  async saveVendingRecords(payload) {
    if (payload?.action === 'issueKey') {
      const machine = demoRecords.machines.find(m => m.serial === payload.serial)
      const recipient = demoRecords.online.find(player => player.serverId === Number(payload.serverId))
      if (!machine || !recipient || !['full', 'service'].includes(payload.access)) throw new Error('Choose a machine, online recipient and key access.')
      const archive = machine.keyArchive
      archive.keys.push({ id: `${machine.serial}-K${String(archive.keys.length + 1).padStart(6, '0')}`, lockId: machine.lockId, access: payload.access,
        issuedAt: Math.floor(Date.now() / 1000), issuedTo: recipient.id, issuedToName: recipient.name, issuedBy: 'DEMO-STAFF', issuedByName: 'Alex' })
    }
    if (payload?.action === 'keyReport') {
      const machine = demoRecords.machines.find(m => m.serial === payload.serial)
      if (!machine) throw new Error('Unknown machine serial.')
      return { ...structuredClone(demoRecords), keyReportPreview: { kind: 'keyreport', business: demoRecords.business, printed: {
        serial: machine.serial, ownerName: machine.ownerName, lockId: machine.lockId, archive: structuredClone(machine.keyArchive), printedAt: Math.floor(Date.now() / 1000),
      } } }
    }
    if (payload?.action === 'tax') for (const person of demoRecords.people) if (payload.taxes?.[person.id] != null) person.tax = payload.taxes[person.id]
    if (payload?.action === 'assign') { const machine = demoRecords.machines.find(m => m.serial === payload.serial); const person = demoRecords.people.find(p => p.id === payload.owner); if (machine) Object.assign(machine, { owner: payload.owner, ownerName: person?.name || demoRecords.business, tampered: false }) }
    if (payload?.action === 'resetRouting') { const machine = demoRecords.machines.find(m => m.serial === payload.serial); if (machine) machine.tampered = false }
    return structuredClone(demoRecords)
  },
  async minigameResult() { return { ok: true } },
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
