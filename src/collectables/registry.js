const types = new Map()

export function registerCollectableType(id, definition) {
  if (!id || typeof definition?.render !== 'function') throw new Error('Collectable types require an id and renderer')
  if (types.has(id)) throw new Error(`Duplicate collectable type: ${id}`)
  types.set(id, Object.freeze({ ...definition }))
}

export function getCollectableType(item) {
  // Existing physical cards predate the type discriminator.
  return types.get(item?.collectableType || 'trading_card')
}

export function listCollectableTypes() {
  return [...types.entries()].map(([id, definition]) => ({ id, ...definition }))
}
