// Read old installations once, keeping historical names out of active storage paths.
// newest first; the old 'collectables' spelling is kept only here so saved catalogues carry over
const previousKeys = {
  'meta-comic-collectibles-v3': ['meta-comic-collectables-v3', 'rush-tradingcards-react-v3'],
  'meta-comic-pack-prefs-v1': ['rush-tradingcards-pack-prefs-v1'],
}

export function readMigratedStorage(key) {
  const current = localStorage.getItem(key)
  if (current !== null) return current
  for (const oldKey of previousKeys[key] || []) {
    const previous = localStorage.getItem(oldKey)
    if (previous != null) {
      localStorage.setItem(key, previous)
      return previous
    }
  }
  return null
}
