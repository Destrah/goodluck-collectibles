/**
 * Reveal effects for the flip stage, keyed by card.rarityKey.
 *   color   rarity colour used for glow, rays, ring and sparkle tint
 *   glow    resting glow opacity once the card is face-up
 *   rays    resting opacity of the spinning light rays behind the card (0 = none)
 *   ring    shock ring on reveal
 *   sparks  number of sparkles that burst around the card edges
 *   charge  ms the card charges up (glow + rays + shake) before it flips; 0 = flips straight away
 *   flash   full-stage white flash on reveal
 */
export const RARITY_FX = {
  common: { color: '#e8edf6', glow: 0.15, rays: 0, ring: false, sparks: 5, charge: 0, flash: false },
  uncommon: { color: '#5fe3a0', glow: 0.3, rays: 0, ring: true, sparks: 6, charge: 0, flash: false },
  rare: { color: '#5aa9ff', glow: 0.6, rays: 0.4, ring: true, sparks: 10, charge: 450, flash: false },
  ultra_rare: { color: '#c77dff', glow: 0.75, rays: 0.55, ring: true, sparks: 12, charge: 600, flash: false },
  legendary: { color: '#ffc94d', glow: 0.9, rays: 0.75, ring: true, sparks: 15, charge: 750, flash: true },
}

export const rarityFx = key => RARITY_FX[key] || RARITY_FX.common

// '#rrggbb' + alpha -> 'rgba(...)'. Pre-computed here because FiveM's embedded Chromium is older than color-mix().
const rgba = (hex, a) => {
  const n = parseInt(hex.slice(1), 16)
  return `rgba(${(n >> 16) & 255},${(n >> 8) & 255},${n & 255},${a})`
}

/** CSS custom properties for a pull-slot. */
export const rarityVars = key => {
  const fx = rarityFx(key)
  return {
    '--rc': fx.color,
    '--rc-55': rgba(fx.color, 0.55),
    '--rc-70': rgba(fx.color, 0.7),
    '--rfx-glow': fx.glow,
    '--rfx-rays': fx.rays,
    '--rfx-charge': `${fx.charge || 300}ms`,
  }
}

// deterministic sparkle layout (seeded by slot index), biased to the card edges like the reference
const rand = seed => () => { seed = (seed * 16807) % 2147483647; return (seed - 1) / 2147483646 }
export function sparkLayout(count, seed = 1) {
  const r = rand(seed * 7919 + 13)
  return Array.from({ length: count }, () => {
    const onSide = r() < 0.5
    const x = onSide ? (r() < 0.5 ? -4 : 104) + (r() - 0.5) * 8 : r() * 100
    const y = onSide ? r() * 100 : (r() < 0.5 ? -3 : 103) + (r() - 0.5) * 8
    return { x, y, size: 16 + r() * 22, delay: Math.round(40 + r() * 650), dur: Math.round(520 + r() * 300) }
  })
}
