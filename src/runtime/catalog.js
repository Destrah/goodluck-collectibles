import { defaultCards, normalizeCards } from '../cardData.js'
import { isFiveM } from './env.js'

export function normalizeCatalogForRuntime(input) {
  const cards = normalizeCards(input)
  if (isFiveM) return cards
  const demosByTitle = new Map(defaultCards
    .filter(card => card.title === 'Nate Gatto' || card.title === 'Holo Mask Lab')
    .map(card => [card.title, card]))

  const merged = cards.map(card => {
    const demo = demosByTitle.get(card.title)
    if (!demo) return card
    const existingNames = new Set(card.variants.map(variant => variant.name))
    const additions = demo.variants
      .filter(variant => !existingNames.has(variant.name))
      .map(variant => structuredClone(variant))
    return additions.length ? { ...card, variants: [...card.variants, ...additions] } : card
  })

  for (const [title, demo] of demosByTitle) {
    if (!merged.some(card => card.title === title)) merged.push(structuredClone(demo))
  }
  return merged
}

