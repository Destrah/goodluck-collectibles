export const isFiveM = typeof window !== 'undefined' && typeof window.GetParentResourceName === 'function'

export function getResourceName() {
  return isFiveM ? window.GetParentResourceName() : 'rush-tradingcards'
}
