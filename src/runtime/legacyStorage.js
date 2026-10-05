// Read old installations once, keeping historical names out of active storage paths.
const previousKeys = {
  'meta-comic-collectables-v3': 'rush-tradingcards-react-v3',
  'meta-comic-pack-prefs-v1': 'rush-tradingcards-pack-prefs-v1',
}

export function readMigratedStorage(key) {
  const current = localStorage.getItem(key)
  if (current !== null) return current
  const previous = previousKeys[key] && localStorage.getItem(previousKeys[key])
  if (previous != null) localStorage.setItem(key, previous)
  return previous ?? null
}
