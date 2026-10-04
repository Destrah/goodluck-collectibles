import { getResourceName } from '../env'

const listeners = new Set()
let installed = false

function installMessageListener() {
  if (installed) return
  installed = true
  window.addEventListener('message', event => {
    const message = event.data
    if (!message || typeof message !== 'object') return
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
  const payload = await response.json().catch(() => ({}))
  if (payload?.ok === false) throw new Error(payload.error || `FiveM NUI request failed: ${endpoint}`)
  return payload
}

installMessageListener()

export const fivemBridge = {
  runtime: 'fivem',
  getInfo: () => nuiFetch('getRuntimeInfo'),
  close: () => nuiFetch('close'),
  openPack: payload => nuiFetch('openPack', { set: payload?.set || 'base' }),
  openBox: payload => nuiFetch('openBox', { set: payload?.set || 'base' }),
  getCollection: () => nuiFetch('getCollection'),
  getCatalog: () => nuiFetch('getCatalog'),
  getSets: () => nuiFetch('getSets'),
  saveSets: sets => nuiFetch('saveSets', { sets }),
  printCard: payload => nuiFetch('printCard', payload || {}),
  createSealed: payload => nuiFetch('createSealed', payload || {}),
  getPackPrefs: () => nuiFetch('getPackPrefs'),
  savePackPrefs: prefs => nuiFetch('savePackPrefs', { prefs }),
  packProp: state => nuiFetch('packProp', { state }), // 'start' | 'stop': character pack-opening animation
  cardIcon: (key, data) => nuiFetch('cardIcon', { key, data }),
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
