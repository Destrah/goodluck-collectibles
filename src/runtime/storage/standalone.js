const STORAGE_KEY = 'rush-tradingcards-react-v3'
let memoryCatalog = []

const clone = value => typeof structuredClone === 'function' ? structuredClone(value) : JSON.parse(JSON.stringify(value))

export const standaloneStorage = {
  async loadCatalog(fallback) {
    try {
      const saved = localStorage.getItem(STORAGE_KEY)
      memoryCatalog = clone(saved ? JSON.parse(saved) : fallback)
      return clone(memoryCatalog)
    } catch {
      memoryCatalog = clone(fallback)
      return clone(memoryCatalog)
    }
  },
  async saveCard(card) {
    try {
      const cards = clone(memoryCatalog)
      const index = cards.findIndex(item => item?.id === card?.id)
      if (index >= 0) cards[index] = clone(card)
      else cards.push(clone(card))
      localStorage.setItem(STORAGE_KEY, JSON.stringify(cards))
      memoryCatalog = cards
      return { ok: true, cardId: card?.id }
    } catch (error) {
      console.warn('Could not persist card to localStorage.', error)
      return { ok: false, error: error?.message || String(error) }
    }
  },
  async deleteCard(cardId) {
    try {
      const cards = memoryCatalog.filter(card => card?.id !== cardId)
      localStorage.setItem(STORAGE_KEY, JSON.stringify(cards))
      memoryCatalog = clone(cards)
      return { ok: true, cardId }
    } catch (error) {
      console.warn('Could not delete card from localStorage.', error)
      return { ok: false, error: error?.message || String(error) }
    }
  },
  async saveCatalog(cards) {
    try {
      localStorage.setItem(STORAGE_KEY, JSON.stringify(cards))
      memoryCatalog = clone(cards)
      return { ok: true }
    } catch (error) {
      console.warn('Could not persist cards to localStorage.', error)
      return { ok: false, error: error?.message || String(error) }
    }
  },
}
