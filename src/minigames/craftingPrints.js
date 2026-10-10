import { resolveCardVariant } from '../cardData'
import { bridge, isFiveM } from '../runtime'

const shuffled = values => {
  const result = [...values]
  for (let i = result.length - 1; i > 0; i--) {
    const j = Math.floor(Math.random() * (i + 1))
    ;[result[i], result[j]] = [result[j], result[i]]
  }
  return result
}

// Keep standalone draft artwork, while FiveM reads the authoritative saved set/catalogue.
export async function loadCraftingPrints(setId, sets, cards, options = {}) {
  if (isFiveM) {
    const result = await bridge.getCraftingPrints({ setId: setId || undefined, cols: options.cols, rows: options.rows })
    if (!result?.ok || !result.cards?.length) throw new Error(result?.error || 'This set has no printable cards.')
    return result
  }
  const set = sets.find(entry => entry.id === (setId || 'base')) || (!setId ? sets[0] : null)
  if (!set) throw new Error('Choose a valid card set.')
  const allowed = new Set(set.cardIds || [])
  const pool = shuffled(cards.filter(card => allowed.has(card.id)))
    .map(card => ({ card, variants: shuffled(card.variants || []) }))
  const prints = []
  for (let round = 0; pool.some(entry => entry.variants.length > round) && prints.length < 600; round++) {
    for (const { card, variants } of pool) {
      if (variants[round] && prints.length < 600) prints.push(resolveCardVariant(card, variants[round]))
    }
  }
  if (!prints.length) throw new Error('This set has no printable cards.')
  return { cards: prints, setId: set.id, setName: set.name || set.id }
}
