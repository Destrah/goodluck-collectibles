// Standalone only: the card copies pulled from packs (with their condition, protection and grade), so they can be
// sleeved, handled and graded in the browser. Only ids + condition are stored; the print comes from the catalogue.
import { resolveCardVariant } from '../cardData.js'

const KEY = 'meta-comic-card-copies-v1'
const LIMIT = 120

export function loadCopies() {
  try {
    const list = JSON.parse(localStorage.getItem(KEY) || '[]')
    return Array.isArray(list) ? list : []
  } catch { return [] }
}
function saveCopies(list) {
  try { localStorage.setItem(KEY, JSON.stringify(list.slice(0, LIMIT))) } catch { /* storage full or blocked: copies just aren't kept */ }
  return list
}
// The print as it was pulled, for when its catalogue card is gone (the built-in demo catalogue gets new ids on
// every load until it is saved). Inline uploaded artwork is left out: it would fill the browser storage.
const snapshotOf = card => {
  const { condition, protection, graded, sleeved, snapshot, ...print } = card
  for (const [key, value] of Object.entries(print)) if (typeof value === 'string' && value.startsWith('data:') && value.length > 20000) delete print[key]
  return print
}
const toCopy = card => ({
  snapshot: snapshotOf(card),
  instanceId: card.instanceId || card.pullId || crypto.randomUUID(),
  baseCardId: card.baseCardId || card.id, variantId: card.variantId,
  setName: card.setName || '', condition: card.condition || null,
  protection: card.protection || 'none', graded: card.graded || null,
  acquiredAt: card.acquiredAt || new Date().toISOString(),
})
export const recordPulls = cards => saveCopies([...cards.filter(card => card?.condition).map(toCopy), ...loadCopies()])
export const addCopy = card => saveCopies([toCopy(card), ...loadCopies()])
export const updateCopy = (instanceId, patch) => saveCopies(loadCopies().map(copy => copy.instanceId === instanceId ? { ...copy, ...patch } : copy))
export const removeCopy = instanceId => saveCopies(loadCopies().filter(copy => copy.instanceId !== instanceId))

// Grading records by cert number (standalone's stand-in for the FiveM server's records)
const RECORDS_KEY = 'meta-comic-grading-records-v1'
const readRecords = () => { try { const value = JSON.parse(localStorage.getItem(RECORDS_KEY) || '{}'); return value && typeof value === 'object' ? value : {} } catch { return {} } }
export function saveRecord(record) {
  if (!record?.cert) return
  try { localStorage.setItem(RECORDS_KEY, JSON.stringify({ ...readRecords(), [record.cert]: record })) } catch { /* storage full: the slab still has its grade */ }
}
export const getRecord = cert => readRecords()[String(cert)] || null

// The full card for a stored copy (null when its card was deleted from the catalogue)
export function copyCard(copy, catalog) {
  const base = catalog.find(card => card.id === copy.baseCardId)
  const { snapshot, ...own } = copy
  if (base) return { ...resolveCardVariant(base, copy.variantId), ...own }
  return snapshot ? { ...snapshot, ...own } : null
}
