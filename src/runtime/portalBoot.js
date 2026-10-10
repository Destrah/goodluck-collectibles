const independentTabs = new Set(['vending', 'records', 'pricing', 'minigames'])
export function portalNeedsCatalog(embedded, view, tabs, tab) {
  if (!embedded || view !== 'admin') return true
  const requested = tabs.length ? tabs : tab ? [tab] : []
  return !requested.length || requested.some(value => !independentTabs.has(value))
}
