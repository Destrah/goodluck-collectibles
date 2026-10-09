// How rare a print really is: the expected number of copies of it per booster pack, from the same pull rules as
// packLogic.js / cards.lua (3 common slots, 1 uncommon slot, 1 rare slot: rare 75% / ultra rare 20% / legendary 5%,
// preserving minimum tier guarantees when qualifying prints exist; base cards and prints picked by chance weights).
// The footer stars on a card show its tier (how many) and these odds (their colour).

const TIER_STARS = { common: 1, uncommon: 2, rare: 3, ultra_rare: 4, legendary: 5 }
const LABEL_TO_TIER = { Common: 'common', Uncommon: 'uncommon', Rare: 'rare', 'Ultra Rare': 'ultra_rare', Legendary: 'legendary' }
// [chance per pack, tiers tried in order]
import { PACK_SLOTS } from '../runtime/packRules.js'
const weight = value => Math.max(1, Number(value) || 1)

export const tierOf = card => card?.rarityKey || LABEL_TO_TIER[card?.rarity] || 'common'
export const starCount = card => TIER_STARS[tierOf(card)] || 1
export const printKey = card => `${card?.baseCardId || card?.id}::${card?.variantId}`

// catalog: normalised cards (with variants). Returns Map(printKey -> expected copies per pack).
export function computePrintOdds(catalog) {
  const odds = new Map()
  const cards = Array.isArray(catalog) ? catalog : []
  const pools = {}
  for (const card of cards) {
    for (const variant of card.variants || []) {
      const tier = variant.rarityKey || 'common'
      ;(pools[tier] ||= new Map()).set(card.id, [...((pools[tier].get(card.id)) || []), variant])
    }
  }
  const tierShare = {} // chance per pack that a slot draws from each tier
  for (const [chance, tiers] of PACK_SLOTS) {
    const tier = tiers.find(name => pools[name]?.size)
    if (tier) tierShare[tier] = (tierShare[tier] || 0) + chance
  }
  for (const [tier, bases] of Object.entries(pools)) {
    const draws = tierShare[tier] || 0
    if (!draws) continue
    const baseTotal = [...bases.keys()].reduce((sum, id) => sum + weight(cards.find(card => card.id === id)?.chanceWeight), 0)
    for (const [id, variants] of bases) {
      const baseChance = weight(cards.find(card => card.id === id)?.chanceWeight) / baseTotal
      const variantTotal = variants.reduce((sum, variant) => sum + weight(variant.chanceWeight), 0)
      for (const variant of variants) odds.set(`${id}::${variant.id}`, draws * baseChance * weight(variant.chanceWeight) / variantTotal)
    }
  }
  return odds
}

// The odds the cards on screen use: the whole catalogue, plus per set (a set's packs only hold its own cards)
let current = { all: new Map(), bySet: {} }
// FiveM: the server works the odds out from its own catalogue (the NUI only loads the catalogue for the editor)
let serverOdds = null
let serverBySet = {}
// cards already on screen redraw their stars when the odds arrive
let version = 0
const listeners = new Set()
export const subscribeOdds = listener => { listeners.add(listener); return () => listeners.delete(listener) }
export const oddsVersion = () => version
export function setServerOdds(odds, bySet = {}) {
  serverOdds = odds && typeof odds === 'object' ? new Map(Object.entries(odds).map(([key, value]) => [key, Number(value) || 0])) : null
  serverBySet = Object.fromEntries(Object.entries(bySet).map(([id, entries]) => [id, new Map(Object.entries(entries).map(([key, value]) => [key, Number(value) || 0]))]))
  if (serverOdds) current = { all: serverOdds, bySet: serverBySet }
  version += 1
  listeners.forEach(listener => listener())
}
export function setPrintOdds(catalog, sets = []) {
  const bySet = {}
  for (const set of sets || []) {
    const ids = new Set(set.cardIds || [])
    if (ids.size) bySet[set.id] = computePrintOdds((catalog || []).filter(card => ids.has(card.id)))
  }
  const all = computePrintOdds(catalog)
  current = { all: serverOdds || all, bySet: { ...bySet, ...serverBySet } }
}
// expected copies per pack (0 when unknown)
export function oddsFor(card) {
  const key = printKey(card)
  return current.bySet[card?.setId]?.get(key) ?? current.all.get(key) ?? 0
}
export const packsPerCopy = card => { const odds = oddsFor(card); return odds > 0 ? 1 / odds : 0 }

// Star colour: how many times rarer than the catalogue's commonest print this one is to pull (a big catalogue
// makes every single print rare in absolute terms, so the bands are relative). The tooltip shows the real odds.
// Mirrored in cards.lua (ODDS_COLOURS / starColour).
export const ODDS_COLOURS = [
  [2, '#d6dde8', 'everyday'], [6, '#4ade80', 'uncommon find'], [20, '#38bdf8', 'scarce'],
  [80, '#a78bfa', 'rare pull'], [300, '#fbbf24', 'chase'], [Infinity, '#ff4d6d', 'grail'],
]
const commonest = map => { let best = 0; for (const value of map.values()) if (value > best) best = value; return best }
export function oddsBand(odds, best) {
  if (!(odds > 0) || !(best > 0)) return null
  return ODDS_COLOURS.find(([limit]) => best / odds <= limit)
}
export function starStyle(card) {
  const map = current.bySet[card?.setId]?.has(printKey(card)) ? current.bySet[card.setId] : current.all
  const odds = map.get(printKey(card)) || 0
  const band = oddsBand(odds, commonest(map))
  if (!band) return { colour: '#d6dde8', label: '' }
  return { colour: band[1], label: band[2], packs: 1 / odds }
}

// "1 in 4.2" / "1 in 380" packs
export const formatPacks = packs => packs < 10 ? packs.toFixed(1) : String(Math.round(packs))
