import { readMigratedStorage } from '../legacyStorage.js'
import { withCollectibleKeys } from '../../collectibles/legacyKeys.js'

const STORAGE_KEY = 'meta-comic-collectibles-v3'
let memoryCatalog = []

const isQuotaError = error => error?.name === 'QuotaExceededError' || error?.name === 'NS_ERROR_DOM_QUOTA_REACHED' || error?.code === 22 || error?.code === 1014
const saveErrorMessage = (error, cards) => isQuotaError(error)
  ? `Not saved: cards need ${(JSON.stringify(cards).length / 1024 / 1024).toFixed(1)} MB but browser storage is full (about 5 MB, shared with coins and plushies). Use artwork URLs instead of uploaded files, or upload smaller images.`
  : error?.message || String(error)

const clone = value => typeof structuredClone === 'function' ? structuredClone(value) : JSON.parse(JSON.stringify(value))

export const standaloneStorage = {
  async loadCatalog(fallback) {
    try {
      const saved = readMigratedStorage(STORAGE_KEY)
      memoryCatalog = clone(saved ? withCollectibleKeys(JSON.parse(saved)) : fallback)
      return clone(memoryCatalog)
    } catch {
      memoryCatalog = clone(fallback)
      return clone(memoryCatalog)
    }
  },
  async saveCard(card) {
    let cards = memoryCatalog
    try {
      cards = clone(memoryCatalog)
      const index = cards.findIndex(item => item?.id === card?.id)
      if (index >= 0) cards[index] = clone(card)
      else cards.push(clone(card))
      localStorage.setItem(STORAGE_KEY, JSON.stringify(cards))
      memoryCatalog = cards
      return { ok: true, cardId: card?.id }
    } catch (error) {
      console.warn('Could not persist card to localStorage.', error)
      return { ok: false, error: saveErrorMessage(error, cards) }
    }
  },
  async deleteCard(cardId) {
    let cards = memoryCatalog
    try {
      cards = memoryCatalog.filter(card => card?.id !== cardId)
      localStorage.setItem(STORAGE_KEY, JSON.stringify(cards))
      memoryCatalog = clone(cards)
      return { ok: true, cardId }
    } catch (error) {
      console.warn('Could not delete card from localStorage.', error)
      return { ok: false, error: saveErrorMessage(error, cards) }
    }
  },
  async saveCatalog(cards) {
    try {
      localStorage.setItem(STORAGE_KEY, JSON.stringify(cards))
      memoryCatalog = clone(cards)
      return { ok: true }
    } catch (error) {
      console.warn('Could not persist cards to localStorage.', error)
      return { ok: false, error: saveErrorMessage(error, cards) }
    }
  },
}
