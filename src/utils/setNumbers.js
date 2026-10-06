// Collector numbers for the card footer and slab label: a card's place in its set's card list and the set's size
// ("BASE 007/120"). Pulled cards use the set they came from (card.setId); catalogue cards use the first set that
// lists them. Reordering a set's cards in Sets & containers renumbers them.
let lookup = { byId: new Map(), firstSet: new Map() }
let version = 0
const listeners = new Set()
export const subscribeSetNumbers = listener => { listeners.add(listener); return () => listeners.delete(listener) }
export const setNumbersVersion = () => version

export function setCardSets(sets) {
  const byId = new Map()
  const firstSet = new Map()
  for (const set of Array.isArray(sets) ? sets : []) {
    if (!set?.id) continue
    const ids = Array.isArray(set.cardIds) ? set.cardIds : []
    const positions = new Map(ids.map((id, index) => [id, index + 1]))
    byId.set(set.id, { set, positions, total: ids.length })
    for (const id of ids) if (!firstSet.has(id)) firstSet.set(id, set.id)
  }
  lookup = { byId, firstSet }
  version += 1
  listeners.forEach(listener => listener())
}

const setCode = set => String(set.code || set.id || '').trim().toUpperCase().slice(0, 12)

// { code, number: '007', total: '120', label: 'BASE 007/120' }, or null when no loaded set lists the card
export function collectorNumber(card) {
  const cardId = card?.baseCardId || card?.id
  if (!cardId) return null
  let entry = card.setId ? lookup.byId.get(card.setId) : null
  if (!entry?.positions.has(cardId)) entry = lookup.byId.get(lookup.firstSet.get(cardId))
  const position = entry?.positions.get(cardId)
  if (!position) return null
  const width = Math.max(3, String(entry.total).length)
  const number = String(position).padStart(width, '0')
  const total = String(entry.total).padStart(width, '0')
  const code = setCode(entry.set)
  return { code, number, total, label: `${code ? `${code} ` : ''}${number}/${total}` }
}
