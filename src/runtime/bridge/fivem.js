import { getResourceName, isEmbedded } from '../env'
import { withCollectibleKeys } from '../../collectibles/legacyKeys.js'

const listeners = new Set()
let installed = false

function installMessageListener() {
  if (installed) return
  installed = true
  window.addEventListener('message', event => {
    const message = event.data
    if (!message || typeof message !== 'object') return
    withCollectibleKeys(message)
    listeners.forEach(listener => listener(message))
  })
}

async function nuiFetch(endpoint, body = {}) {
  const response = await fetch(`https://${getResourceName()}/${endpoint}`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json; charset=UTF-8' },
    body: JSON.stringify(body),
  })
  if (!response.ok) throw new Error(`FiveM NUI request failed: ${endpoint} (${response.status})`)
  const payload = withCollectibleKeys(await response.json().catch(() => ({})))
  if (payload?.ok === false) throw new Error(payload.error || `FiveM NUI request failed: ${endpoint}`)
  return payload
}

installMessageListener()

// The server sends each uploaded image of an opening once (run.images); items point at it as '@img:N'.
function unpackRunImages(response) {
  const images = Array.isArray(response?.run?.images) ? response.run.images : []
  if (!images.length) return response
  const expand = value => typeof value === 'string' && value.startsWith('@img:') ? images[Number(value.slice(5)) - 1] ?? '' : value
  const items = (response.run.items || []).map(item => Object.fromEntries(Object.entries(item).map(([key, value]) => [key, expand(value)])))
  return { ...response, run: { ...response.run, items, images: undefined } }
}

export const fivemBridge = {
  runtime: 'fivem',
  getInfo: () => nuiFetch('getRuntimeInfo'),
  close: () => nuiFetch('close'),
  openPack: payload => nuiFetch('openPack', { set: payload?.set || 'base' }),
  openBox: payload => nuiFetch('openBox', { set: payload?.set || 'base' }),
  getCollection: () => nuiFetch('getCollection'),
  getCollectibles: () => nuiFetch('getCollectibles'),
  saveCollectible: payload => nuiFetch('saveCollectible', payload),
  openCollectibleContainer: payload => nuiFetch('openCollectibleContainer', payload).then(unpackRunImages),
  claimCollectibles: () => nuiFetch('claimCollectibles'),
  createCollectibleContainer: payload => nuiFetch('createCollectibleContainer', payload),
  swapBinderCards: payload => nuiFetch('swapBinderCards', payload || {}),
  binderStoreCard: payload => nuiFetch('binderStoreCard', payload || {}), // card hand -> binder pocket (server moves the item)
  binderTakeCard: payload => nuiFetch('binderTakeCard', payload || {}), // binder pocket -> inventory, if there is room
  getPrintOdds: () => nuiFetch('getPrintOdds'),
  getCatalog: () => nuiFetch('getCatalog'),
  getSets: () => nuiFetch('getSets'),
  saveSets: sets => nuiFetch('saveSets', { sets }),
  getVendingMachines: () => nuiFetch('getVendingMachines', { forensic: !isEmbedded }),
  getCrafting: () => nuiFetch('getCrafting'), // managers: recipes and what they can make
  saveCrafting: payload => nuiFetch('saveCrafting', payload),
  getVendingRecords: () => nuiFetch('getVendingRecords', { forensic: !isEmbedded, summary: true }),
  getVendingRecordPage: payload => nuiFetch('getVendingRecordPage', { ...payload, forensic: !isEmbedded }),
  saveVendingRecords: payload => nuiFetch('saveVendingRecords', { ...payload, forensic: !isEmbedded, summary: true }),
  minigameResult: payload => nuiFetch('minigameResult', payload), // built-in skill check finished
  getMinigames: () => nuiFetch('getMinigames'), // admin Minigames tab: Config.Minigames + last in-game test
  testMinigame: payload => nuiFetch('testMinigame', payload), // { name, speed }: run a preset in game
  vendingWaypoint: (x, y) => nuiFetch('vendingWaypoint', { x, y }),
  printCard: payload => nuiFetch('printCard', payload || {}),
  printCollectible: payload => nuiFetch('printCollectible', payload || {}),
  // card grading (server checks every mark against the card's real condition)
  gradingMark: payload => nuiFetch('gradingMark', payload || {}),
  gradingSubmit: payload => nuiFetch('gradingSubmit', payload || {}),
  gradingCancel: payload => nuiFetch('gradingCancel', payload || {}),
  gradingRecord: cert => nuiFetch('gradingRecord', { cert }), // cert lookup: { record, card }
  roughHandling: () => nuiFetch('roughHandling', {}), // own card spun hard in the viewer: the server may wear it
  createSealed: payload => nuiFetch('createSealed', payload || {}),
  getPackPrefs: () => nuiFetch('getPackPrefs'),
  savePackPrefs: prefs => nuiFetch('savePackPrefs', { prefs }),
  packProp: (state, kind) => nuiFetch('packProp', { state, kind }), // 'start' | 'stop': character opening animation; kind: undefined = booster pack, 'bag' | 'box' | 'case'
  holdCollectibles: payload => nuiFetch('holdCollectibles', payload || {}), // { kind | typeId, count }: the character holds the pulls
  cardIcon: (key, data) => nuiFetch('cardIcon', { key, data }),
  optimizedArtwork: (id, data) => nuiFetch('optimizedArtwork', { id, data }), // legacy artwork command: downscaled image -> server upload
  uiReady: () => nuiFetch('uiReady', {}), // NUI loaded -> server may ask it to draw missing card icons // rendered inventory icon -> server upload
  claimCards: () => nuiFetch('claimCards'), // give the pulled card items once they've been revealed / the opening closes
  saveCatalog: cards => nuiFetch('saveCatalog', { cards }),
  saveCard: card => nuiFetch('saveCard', { card }),
  deleteCard: cardId => nuiFetch('deleteCard', { cardId }),
  subscribe(listener) {
    listeners.add(listener)
    return () => listeners.delete(listener)
  },
}
