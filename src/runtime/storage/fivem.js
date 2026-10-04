import { bridge } from '../bridge'

let queuedCatalog = null
let saveInFlight = null

async function sendCatalog(cards) {
  try {
    return await bridge.saveCatalog(cards)
  } catch (error) {
    // Catalog writes are intentionally optional in FiveM.
    if (!String(error?.message || '').toLowerCase().includes('disabled')) console.warn(error)
    return { ok: false, error: error?.message || String(error) }
  }
}

async function flushCatalogQueue() {
  if (saveInFlight || !queuedCatalog) return { ok: true, queued: true }

  const snapshot = queuedCatalog
  queuedCatalog = null
  saveInFlight = sendCatalog(snapshot)

  let result
  try {
    result = await saveInFlight
  } finally {
    saveInFlight = null
  }

  // If edits arrived while the previous (possibly latent) catalog was travelling, save
  // one newest snapshot next. Intermediate slider frames are intentionally discarded.
  if (queuedCatalog) queueMicrotask(() => { flushCatalogQueue() })
  return result
}

export const fivemStorage = {
  async loadCatalog(fallback) {
    try {
      const result = await bridge.getCatalog()
      return Array.isArray(result?.cards) && result.cards.length ? result.cards : fallback
    } catch (error) {
      console.warn('Could not load FiveM catalog, using bundled cards.', error)
      return fallback
    }
  },

  async saveCard(card) {
    try {
      return await bridge.saveCard(card)
    } catch (error) {
      if (!String(error?.message || '').toLowerCase().includes('disabled')) console.warn(error)
      return { ok: false, error: error?.message || String(error) }
    }
  },
  async deleteCard(cardId) {
    try {
      return await bridge.deleteCard(cardId)
    } catch (error) {
      if (!String(error?.message || '').toLowerCase().includes('disabled')) console.warn(error)
      return { ok: false, error: error?.message || String(error) }
    }
  },
  async saveCatalog(cards) {
    // React state is updated immutably, so keeping the latest reference is safe. The
    // queue prevents several full catalogs from being in flight at once.
    queuedCatalog = cards
    if (saveInFlight) return { ok: true, queued: true }
    return flushCatalogQueue()
  },
}
