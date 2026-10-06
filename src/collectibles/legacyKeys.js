// Items saved before the "collectible" spelling fix (inventory metadata, server data, browser storage) name their
// type with the old misspelled key. Everything here reads `collectibleType`, so incoming data is renamed once.
const LEGACY_TYPE_KEY = 'collectableType'

export function withCollectibleKeys(value, depth = 0) {
  if (!value || typeof value !== 'object' || depth > 16) return value
  if (Array.isArray(value)) {
    for (const entry of value) withCollectibleKeys(entry, depth + 1)
    return value
  }
  if (Object.prototype.hasOwnProperty.call(value, LEGACY_TYPE_KEY)) {
    if (value.collectibleType === undefined) value.collectibleType = value[LEGACY_TYPE_KEY]
    delete value[LEGACY_TYPE_KEY]
  }
  for (const key in value) {
    const child = value[key]
    if (child && typeof child === 'object') withCollectibleKeys(child, depth + 1)
  }
  return value
}
