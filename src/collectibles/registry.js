const types = new Map()

export function registerCollectibleType(id, definition) {
  if (!id || typeof definition?.render !== 'function') throw new Error('Collectible types require an id and renderer')
  if (types.has(id)) throw new Error(`Duplicate collectible type: ${id}`)
  types.set(id, Object.freeze({ ...definition }))
}

export function getCollectibleType(item) {
  // Existing physical cards predate the type discriminator.
  return types.get(item?.collectibleType || 'trading_card')
}

export function listCollectibleTypes() {
  return [...types.entries()].map(([id, definition]) => ({ id, ...definition }))
}
