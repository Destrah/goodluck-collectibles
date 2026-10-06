// Prints (versions) of a coin or plushie: each has its own rarity, pull weight and look. Mirrors
// fivem/server/modules/objects.lua so standalone pulls behave like the server's.
import { RARITIES } from '../cardData'

export { RARITIES }
const LABELS = Object.fromEntries(RARITIES.map(entry => [entry.value, entry.label]))

export const rarityKeyOf = value => {
  const key = String(value || '').toLowerCase().replace(/[\s-]+/g, '_')
  return LABELS[key] ? key : 'common'
}
export const rarityLabel = key => LABELS[rarityKeyOf(key)]

const weightOf = entry => Math.max(1, Number(entry?.chanceWeight) || 1)
export function weightedPick(list, random = Math.random) {
  const total = list.reduce((sum, entry) => sum + weightOf(entry), 0)
  let roll = random() * total
  return list.find(entry => (roll -= weightOf(entry)) <= 0) || list[list.length - 1]
}

// Definitions saved before prints existed behave as one "Standard" print of themselves.
export const printsOf = item => Array.isArray(item?.prints) && item.prints.length
  ? item.prints
  : [{ id: 'base', name: 'Standard', chanceWeight: 1, rarityKey: rarityKeyOf(item?.rarityKey || item?.rarity) }]

// The definition with one print's fields laid over it; an empty print field inherits the definition's value.
export function withPrint(item, print) {
  const merged = structuredClone(item)
  delete merged.prints
  for (const [key, value] of Object.entries(print || {})) {
    if (key === 'id' || key === 'name' || value === undefined || value === null || value === '') continue
    merged[key] = structuredClone(value)
  }
  merged.definitionId = item.id
  merged.printId = print?.id || 'base'
  merged.printName = print?.name || 'Standard'
  merged.rarityKey = rarityKeyOf(print?.rarityKey || item.rarityKey || item.rarity)
  merged.rarity = LABELS[merged.rarityKey]
  merged.chanceWeight = item.chanceWeight
  return merged
}

export const makePrint = (patch = {}) => ({ id: crypto.randomUUID(), name: 'Standard', rarityKey: 'common', chanceWeight: 100, ...patch })

// Every definition + print, e.g. for galleries.
export const allPrints = definitions => definitions.flatMap(item => printsOf(item).map(print => withPrint(item, print)))

// Stitch patterns for plushie seams.
export const STITCH_PATTERNS = [
  { value: 'running', label: 'Running stitch' },
  { value: 'cross', label: 'Cross stitch' },
  { value: 'zigzag', label: 'Zigzag' },
  { value: 'blanket', label: 'Blanket stitch' },
  { value: 'double', label: 'Double row' },
  { value: 'none', label: 'Hidden seam' },
]
// Back of a coin / plushie that has no back artwork of its own.
export const backStyles = defaultLabel => [
  { value: '', label: defaultLabel },
  { value: 'mirror', label: 'Mirror of the front' },
  { value: 'same', label: 'Same as the front' },
]
export const EDGE_STYLES = [
  { value: 'reeded', label: 'Reeded' },
  { value: 'smooth', label: 'Smooth' },
  { value: 'rope', label: 'Rope' },
  { value: 'studded', label: 'Studded' },
  { value: 'lettered', label: 'Lettered' },
]
export const FINISHES = [
  { value: 'none', label: 'None' },
  { value: 'rainbow', label: 'Rainbow (iridescent)' },
  { value: 'metallic', label: 'Metallic (polished)' },
  { value: 'glitter', label: 'Glitter (sparkle)' },
]
