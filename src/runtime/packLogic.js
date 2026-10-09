import { resolveCardVariant } from '../cardData.js'
import { generateCondition } from '../grading/condition.js'
import { PACK_TIER_CHAINS } from './packRules.js'

export const weightedPick = (pool, getWeight = item => item.chanceWeight) => {
  if (!pool?.length) return null
  const total = pool.reduce((sum, item) => sum + Math.max(1, Number(getWeight(item)) || 1), 0)
  let roll = Math.random() * total
  for (const item of pool) {
    roll -= Math.max(1, Number(getWeight(item)) || 1)
    if (roll <= 0) return item
  }
  return pool[pool.length - 1]
}

export const variantsForTier = (card, tier) => (card.variants || []).filter(variant => variant.rarityKey === tier)

export function pullFromTier(cards, tier, fallbackTiers = []) {
  for (const candidateTier of [tier, ...fallbackTiers]) {
    const basePool = cards.filter(card => variantsForTier(card, candidateTier).length > 0)
    if (!basePool.length) continue
    const baseCard = weightedPick(basePool, card => card.chanceWeight)
    const variant = weightedPick(variantsForTier(baseCard, candidateTier), item => item.chanceWeight)
    return resolveCardVariant(baseCard, variant)
  }

  const baseCard = weightedPick(cards, card => card.chanceWeight)
  return baseCard ? resolveCardVariant(baseCard) : null
}

export function makePack(cards) {
  const rareRoll = Math.random() * 100
  const rareTier = rareRoll > 95 ? 'legendary' : rareRoll > 75 ? 'ultra_rare' : 'rare'
  const pull = tier => pullFromTier(cards, tier, PACK_TIER_CHAINS[tier].slice(1))
  return [
    pull('common'), pull('common'), pull('common'), pull('uncommon'), pull(rareTier),
  ].filter(Boolean).map(card => {
    const pullId = crypto.randomUUID()
    // every copy comes out of the pack with its own small print imperfections (src/grading/condition.js)
    return { ...card, pullId, instanceId: pullId, condition: generateCondition() }
  })
}
