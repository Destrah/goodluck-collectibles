// Used by generation and odds: preserve guaranteed slot tiers whenever the set has them or higher tiers.
export const PACK_TIER_CHAINS = {
  common: ['common', 'uncommon', 'rare', 'ultra_rare', 'legendary'],
  uncommon: ['uncommon', 'rare', 'ultra_rare', 'legendary', 'common'],
  rare: ['rare', 'ultra_rare', 'legendary', 'uncommon', 'common'],
  ultra_rare: ['ultra_rare', 'rare', 'legendary', 'uncommon', 'common'],
  legendary: ['legendary', 'ultra_rare', 'rare', 'uncommon', 'common'],
}
export const PACK_SLOTS = [[3, PACK_TIER_CHAINS.common], [1, PACK_TIER_CHAINS.uncommon],
  [0.75, PACK_TIER_CHAINS.rare], [0.2, PACK_TIER_CHAINS.ultra_rare], [0.05, PACK_TIER_CHAINS.legendary]]
