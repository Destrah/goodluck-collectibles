import { isFiveM } from './runtime/env.js'

export const CARD_TYPES = [
  'civilian', 'police', 'medical', 'legal', 'farmer',
  'criminal', 'vehicle', 'structure', 'location'
]

export const LAYOUTS = [
  { value: 'classic', label: 'Classic Frame' },
  { value: 'full-art', label: 'Full Art' },
  { value: 'illustration', label: 'Illustration Rare' },
  { value: 'dark-borderless', label: 'Dark Borderless' },
]

export const RARITIES = [
  { value: 'common', label: 'Common' },
  { value: 'uncommon', label: 'Uncommon' },
  { value: 'rare', label: 'Rare' },
  { value: 'ultra_rare', label: 'Ultra Rare' },
  { value: 'legendary', label: 'Legendary' },
]

export const HOLOS = [
  { value: 'none', label: 'None' },
  { value: 'rainbow', label: 'Rainbow Foil' },
  { value: 'prism', label: 'Prism / Streak' },
  { value: 'cosmos', label: 'Cosmos Sparkle' },
  { value: 'reverse', label: 'Reverse Holo' },
  { value: 'etched', label: 'Etched Foil' },
  { value: 'aurora', label: 'Aurora Foil' },
  { value: 'oilslick', label: 'Oil Slick' },
]

export const SUBJECT_EFFECTS = [
  { value: 'outline-rainbow', label: 'Rainbow outline' },
  { value: 'outline-gold', label: 'Gold outline' },
  { value: 'outline-silver', label: 'Silver outline' },
  { value: 'foil-rainbow', label: 'Rainbow subject foil' },
  { value: 'foil-prism', label: 'Prism subject foil' },
  { value: 'foil-etched', label: 'Etched subject foil' },
  { value: 'foil-cosmos', label: 'Cosmos subject foil' },
  { value: 'foil-galaxy', label: 'Galaxy / diffraction foil' },
  { value: 'foil-flame', label: 'Flame foil (v1)' },
  { value: 'foil-flame-v2', label: 'Flame foil v2 — Smooth' },
  { value: 'foil-flame-hybrid', label: 'Flame foil v3 — Realistic layered' },
  { value: 'foil-flame-anime', label: 'Flame foil v4 — Stylized anime' },
  { value: 'foil-flame-smoky', label: 'Flame foil v5 — Smoky realistic' },
  { value: 'foil-electric', label: 'Electric foil' },
  { value: 'foil-water', label: 'Water shimmer foil' },
  { value: 'foil-smoke', label: 'Smoke / shadow foil' },
  { value: 'foil-frost', label: 'Frost / ice foil' },
]

export const MASK_SOURCES = [
  { value: 'alpha', label: 'Alpha mask (transparent PNG/WebP)' },
  { value: 'luminance', label: 'Luminance mask (white = visible)' },
  { value: 'luminance-invert', label: 'Inverted luminance (black = visible)' },
]

const uuid = () => crypto.randomUUID()

export function makeSubjectLayer(overrides = {}) {
  return {
    id: uuid(),
    name: 'Subject effect',
    image: '',
    mode: 'outline-rainbow',
    strength: 70,
    maskOnly: false,
    maskSource: 'alpha',
    foilA: '#ff4d8d',
    foilB: '#4df3ff',
    foilC: '#ffe66d',
    ...overrides,
  }
}

export function makeVariant(overrides = {}) {
  return {
    id: uuid(),
    name: 'Standard',
    rarity: 'Common',
    rarityKey: 'common',
    chanceWeight: 100,
    layout: 'classic',
    holo: 'none',
    holoStrength: 55,
    image: '',
    imagePositionX: 50,
    imagePositionY: 50,
    imageZoom: 100,
    accent: '',
    foilA: '',
    foilB: '',
    foilC: '',
    subjectLayers: [],
    ...overrides,
  }
}

function legacyVariant(card) {
  const legacySubjectMode = card.holo === 'subject-outline'
    ? 'outline-rainbow'
    : card.holo === 'subject-foil'
      ? 'foil-rainbow'
      : null

  return makeVariant({
    name: 'Imported print',
    rarity: card.rarity || 'Common',
    rarityKey: card.rarityKey || 'common',
    chanceWeight: card.chanceWeight || 100,
    layout: card.layout || 'classic',
    holo: legacySubjectMode ? 'none' : (card.holo || 'none'),
    holoStrength: card.holoStrength ?? 55,
    image: '',
    subjectLayers: legacySubjectMode && card.subjectImage
      ? [makeSubjectLayer({
          name: 'Imported subject effect',
          image: card.subjectImage,
          mode: legacySubjectMode,
          strength: card.holoStrength ?? 70,
          foilA: card.foilA,
          foilB: card.foilB,
          foilC: card.foilC,
        })]
      : [],
  })
}

function repairHoloMaskLab(normalized) {
  if (normalized.title !== 'Holo Mask Lab') return normalized

  const fixedLayer = (existing, patch) => ({
    ...makeSubjectLayer(),
    ...(existing || {}),
    ...patch,
    id: existing?.id || uuid(),
  })

  const repairedVariants = normalized.variants.map(variant => {
    const current = Array.isArray(variant.subjectLayers) ? variant.subjectLayers : []

    // One-time repair for the accidental flame contamination that could be saved in v3/v4 localStorage.
    // Once the reference is back to a non-flame mode, normal editor changes are left alone.
    if (variant.name === 'Subject Prism Mask' && (!current[0] || String(current[0].mode || '').startsWith('foil-flame'))) {
      return {
        ...variant,
        holo: 'none',
        subjectLayers: [fixedLayer(current[0], {
          name: 'Subject fill mask',
          image: '/img/holo_sample_subject_mask.png',
          mode: 'foil-prism',
          maskOnly: true,
          maskSource: 'alpha',
          strength: 78,
          foilA: '#ff3cac', foilB: '#27e5ff', foilC: '#ffe86a',
        })],
      }
    }

    if (variant.name === 'Dedicated Outline Mask' && (!current[0] || String(current[0].mode || '').startsWith('foil-flame'))) {
      return {
        ...variant,
        holo: 'none',
        subjectLayers: [fixedLayer(current[0], {
          name: 'True outline ring mask',
          image: '/img/holo_sample_outline_mask.png',
          mode: 'foil-galaxy',
          maskOnly: true,
          maskSource: 'alpha',
          strength: 92,
          foilA: '#ff4dc8', foilB: '#38e8ff', foilC: '#fff27a',
        })],
      }
    }

    if (variant.name === 'Triple Mask Chase' && (current.length < 3 || current.some(layer => String(layer?.mode || '').startsWith('foil-flame')))) {
      return {
        ...variant,
        holo: 'aurora',
        holoStrength: 16,
        subjectLayers: [
          fixedLayer(current[0], {
            name: 'Subject prism',
            image: '/img/holo_sample_subject_mask.png',
            mode: 'foil-prism',
            maskOnly: true,
            maskSource: 'alpha',
            strength: 62,
            foilA: '#ff3cac', foilB: '#27e5ff', foilC: '#ffe86a',
          }),
          fixedLayer(current[1], {
            name: 'Outline diffraction',
            image: '/img/holo_sample_outline_mask.png',
            mode: 'foil-galaxy',
            maskOnly: true,
            maskSource: 'alpha',
            strength: 96,
            foilA: '#ff5bca', foilB: '#4af4ff', foilC: '#ffffff',
          }),
          fixedLayer(current[2], {
            name: 'Neon accent mask',
            image: '/img/holo_sample_accent_mask.png',
            mode: 'foil-cosmos',
            maskOnly: true,
            maskSource: 'alpha',
            strength: 82,
            foilA: '#9b5cff', foilB: '#27e5ff', foilC: '#ff58bd',
          }),
        ],
      }
    }

    // The first flame demo used the tiny accent mask. Migrate only that old demo setup to the
    // filled person+car mask so the flame front can follow the full silhouette, then leave edits alone.
    if (variant.name === 'Flame Accent Demo' && (
      !current[0] ||
      current[0].image === '/img/holo_sample_accent_mask.png' ||
      current[0].mode !== 'foil-flame'
    )) {
      return {
        ...variant,
        holo: 'none',
        subjectLayers: [fixedLayer(current[0], {
          name: 'Flame contour v1',
          image: '/img/holo_sample_subject_mask.png',
          mode: 'foil-flame',
          maskOnly: true,
          maskSource: 'alpha',
          strength: current[0]?.strength ?? 84,
          foilA: '#f97316', foilB: '#fb7185', foilC: '#fde047',
        })],
      }
    }

    return variant
  })

  const hasVariant = (name) => repairedVariants.some(variant => variant.name === name)
  const addDemo = (name, rarity, mode, strength, colors) => makeVariant({
    name,
    rarity,
    rarityKey: 'legendary',
    chanceWeight: 1,
    layout: 'classic',
    holo: 'none',
    subjectLayers: [makeSubjectLayer({
      name: rarity,
      image: '/img/holo_sample_subject_mask.png',
      mode,
      maskOnly: true,
      maskSource: 'alpha',
      strength,
      foilA: colors[0], foilB: colors[1], foilC: colors[2],
    })],
  })

  if (!hasVariant('Flame Smooth Demo')) repairedVariants.push(addDemo('Flame Smooth Demo', 'Reference Flame v2', 'foil-flame-v2', 82, ['#ff4b18', '#ff9f2d', '#ffe36b']))
  if (!hasVariant('Flame Hybrid Demo')) repairedVariants.push(addDemo('Flame Hybrid Demo', 'Reference Flame v3', 'foil-flame-hybrid', 84, ['#ff5418', '#ffad33', '#fff08a']))
  if (!hasVariant('Flame Anime Demo')) repairedVariants.push(addDemo('Flame Anime Demo', 'Reference Flame v4', 'foil-flame-anime', 88, ['#ef2b12', '#ff7a12', '#ffd62e']))
  if (!hasVariant('Flame Smoky Demo')) repairedVariants.push(addDemo('Flame Smoky Demo', 'Reference Flame v5', 'foil-flame-smoky', 78, ['#f04a18', '#ff9a28', '#ffe077']))
  if (!hasVariant('Flame Hybrid 50% Demo')) repairedVariants.push(addDemo('Flame Hybrid 50% Demo', 'Reference Flame 50%', 'foil-flame-hybrid', 50, ['#ff5418', '#ffad33', '#fff08a']))

  return { ...normalized, variants: repairedVariants }
}

export function normalizeCard(card) {
  // Migrate legacy base framing once; prints with separate artwork used centered defaults.
  const framing = variant => {
    const separateArt = String(variant.image || '').trim() && String(variant.image).trim() !== String(card.image || '').trim()
    const value = (key, fallback) => {
      const raw = variant[key] ?? (separateArt ? fallback : card[key]) ?? fallback
      return Number.isFinite(Number(raw)) ? Number(raw) : fallback
    }
    return { imagePositionX: value('imagePositionX', 50), imagePositionY: value('imagePositionY', 50), imageZoom: value('imageZoom', 100) }
  }
  const variants = Array.isArray(card.variants) && card.variants.length
    ? card.variants.map(variant => ({
        ...makeVariant(),
        ...variant,
        ...framing(variant),
        id: variant.id || uuid(),
        holoStrength: variant.holoStrength ?? 55,
        subjectLayers: Array.isArray(variant.subjectLayers)
          ? variant.subjectLayers.map(layer => ({ ...makeSubjectLayer(), ...layer, id: layer.id || uuid() }))
          : [],
      }))
    : [{ ...legacyVariant(card), ...framing({}) }]

  const normalized = {
    id: card.id || uuid(),
    title: card.title || 'Untitled Card',
    subtitle: card.subtitle || '',
    hp: Number(card.hp) || 100,
    type: card.type || 'civilian',
    chanceWeight: Number(card.baseChanceWeight ?? card.chanceWeight) || 100,
    image: card.image || '/img/template.jpg',
    description: card.description || '',
    accent: card.accent || '#f59e0b',
    foilA: card.foilA || '#ff4d8d',
    foilB: card.foilB || '#4df3ff',
    foilC: card.foilC || '#ffe66d',
    attacks: Array.isArray(card.attacks) ? card.attacks : [],
    variants,
  }

  return isFiveM ? normalized : repairHoloMaskLab(normalized)
}

export function normalizeCards(cards) {
  return (Array.isArray(cards) ? cards : []).map(normalizeCard)
}

export function resolveCardVariant(card, variantOrId) {
  const normalized = normalizeCard(card)
  const variant = typeof variantOrId === 'object'
    ? normalized.variants.find(item => item.id === variantOrId?.id) || variantOrId
    : normalized.variants.find(item => item.id === variantOrId) || normalized.variants[0]

  const variantImage = String(variant.image || '').trim()
  const baseImage = String(normalized.image || '').trim()
  const usesVariantImage = Boolean(variantImage) && variantImage !== baseImage

  return {
    ...normalized,
    ...variant,
    id: normalized.id,
    baseCardId: normalized.id,
    variantId: variant.id,
    variantName: variant.name,
    image: usesVariantImage ? variant.image : normalized.image,
    imagePositionX: variant.imagePositionX ?? 50,
    imagePositionY: variant.imagePositionY ?? 50,
    imageZoom: variant.imageZoom ?? 100,
    accent: variant.accent || normalized.accent,
    foilA: variant.foilA || normalized.foilA,
    foilB: variant.foilB || normalized.foilB,
    foilC: variant.foilC || normalized.foilC,
    subjectLayers: Array.isArray(variant.subjectLayers) ? variant.subjectLayers : [],
  }
}

const baseCards = [
  {
    title: 'Nate Gatto',
    subtitle: 'City Civilian',
    hp: 100,
    type: 'civilian',
    chanceWeight: 50,
    image: '/img/nate_gatto.jpg',
    description: 'A local face with a knack for being in the middle of whatever is happening downtown.',
    accent: '#f59e0b',
    foilA: '#ff4d8d',
    foilB: '#4df3ff',
    foilC: '#ffe66d',
    attacks: [
      { name: 'Fast Talk', cost: 1, damage: 20, text: 'Distract the other player and draw one card.' },
      { name: 'Street Smarts', cost: 2, damage: 50, text: 'Gets stronger when played in a city location.' },
    ],
    variants: [
      makeVariant({ name: 'Base', rarity: 'Common', rarityKey: 'common', chanceWeight: 65, layout: 'classic', holo: 'none' }),
      makeVariant({ name: 'Reverse Holo', rarity: 'Common Reverse', rarityKey: 'common', chanceWeight: 25, layout: 'classic', holo: 'reverse', holoStrength: 46 }),
      makeVariant({ name: 'Rainbow Chase', rarity: 'Common Holo', rarityKey: 'common', chanceWeight: 10, layout: 'classic', holo: 'rainbow', holoStrength: 32 }),
      makeVariant({
        name: 'Character Outline',
        rarity: 'Rare Outline',
        rarityKey: 'rare',
        chanceWeight: 18,
        layout: 'classic',
        holo: 'none',
        subjectLayers: [makeSubjectLayer({
          name: 'Nate character outline',
          image: '/img/nate_gatto_character.png',
          mode: 'outline-rainbow',
          strength: 86,
          foilA: '#ff3d81',
          foilB: '#46e8ff',
          foilC: '#ffe95f',
        })],
      }),
      makeVariant({
        name: 'Character + Car Outline',
        rarity: 'Ultra Rare Outline',
        rarityKey: 'ultra_rare',
        chanceWeight: 10,
        layout: 'classic',
        holo: 'prism',
        holoStrength: 18,
        subjectLayers: [makeSubjectLayer({
          name: 'Nate and sheriff car outline',
          image: '/img/nate_gatto_character_car.png',
          mode: 'outline-gold',
          strength: 88,
          foilA: '#f59e0b',
          foilB: '#fff7c2',
          foilC: '#ffffff',
        })],
      }),
    ],
  },
  {
    title: 'Holo Mask Lab',
    subtitle: 'Reference Demo',
    hp: 120,
    type: 'vehicle',
    chanceWeight: 1,
    image: '/img/holo_sample_art.png',
    description: 'A clean sample card made specifically to demonstrate proper region masks, outline masks, and stacked foil layers.',
    accent: '#41dcff',
    foilA: '#ff3cac',
    foilB: '#27e5ff',
    foilC: '#ffe86a',
    attacks: [
      { name: 'Diffraction', cost: 1, damage: 30, text: 'A mask-clipped spectrum that follows the pointer.' },
      { name: 'Layer Stack', cost: 2, damage: 70, text: 'Stacks subject, outline, and accent masks independently.' },
    ],
    variants: [
      makeVariant({ name: 'Reference Base', rarity: 'Reference', rarityKey: 'rare', chanceWeight: 1, layout: 'classic', holo: 'none' }),
      makeVariant({
        name: 'Subject Prism Mask',
        rarity: 'Reference Holo',
        rarityKey: 'ultra_rare',
        chanceWeight: 1,
        layout: 'classic',
        holo: 'none',
        subjectLayers: [makeSubjectLayer({
          name: 'Subject fill mask',
          image: '/img/holo_sample_subject_mask.png',
          mode: 'foil-prism',
          maskOnly: true,
          strength: 78,
          foilA: '#ff3cac',
          foilB: '#27e5ff',
          foilC: '#ffe86a',
        })],
      }),
      makeVariant({
        name: 'Dedicated Outline Mask',
        rarity: 'Reference Outline',
        rarityKey: 'ultra_rare',
        chanceWeight: 1,
        layout: 'classic',
        holo: 'none',
        subjectLayers: [makeSubjectLayer({
          name: 'True outline ring mask',
          image: '/img/holo_sample_outline_mask.png',
          mode: 'foil-galaxy',
          maskOnly: true,
          strength: 92,
          foilA: '#ff4dc8',
          foilB: '#38e8ff',
          foilC: '#fff27a',
        })],
      }),
      makeVariant({
        name: 'Triple Mask Chase',
        rarity: 'Reference Chase',
        rarityKey: 'legendary',
        chanceWeight: 1,
        layout: 'classic',
        holo: 'aurora',
        holoStrength: 16,
        subjectLayers: [
          makeSubjectLayer({
            name: 'Subject prism',
            image: '/img/holo_sample_subject_mask.png',
            mode: 'foil-prism',
            maskOnly: true,
            strength: 62,
            foilA: '#ff3cac',
            foilB: '#27e5ff',
            foilC: '#ffe86a',
          }),
          makeSubjectLayer({
            name: 'Outline diffraction',
            image: '/img/holo_sample_outline_mask.png',
            mode: 'foil-galaxy',
            maskOnly: true,
            strength: 96,
            foilA: '#ff5bca',
            foilB: '#4af4ff',
            foilC: '#ffffff',
          }),
          makeSubjectLayer({
            name: 'Neon accent mask',
            image: '/img/holo_sample_accent_mask.png',
            mode: 'foil-cosmos',
            maskOnly: true,
            strength: 82,
            foilA: '#9b5cff',
            foilB: '#27e5ff',
            foilC: '#ff58bd',
          }),
        ],
      }),
      makeVariant({
        name: 'Electric Outline Demo',
        rarity: 'Reference Electric',
        rarityKey: 'ultra_rare',
        chanceWeight: 1,
        layout: 'classic',
        holo: 'none',
        subjectLayers: [
          makeSubjectLayer({
            name: 'Electric outline ring',
            image: '/img/holo_sample_outline_mask.png',
            mode: 'foil-electric',
            maskOnly: true,
            strength: 88,
            foilA: '#3b82f6',
            foilB: '#67e8f9',
            foilC: '#f8fafc',
          }),
        ],
      }),
      makeVariant({
        name: 'Water Subject Demo',
        rarity: 'Reference Water',
        rarityKey: 'ultra_rare',
        chanceWeight: 1,
        layout: 'classic',
        holo: 'none',
        subjectLayers: [
          makeSubjectLayer({
            name: 'Water subject fill',
            image: '/img/holo_sample_subject_mask.png',
            mode: 'foil-water',
            maskOnly: true,
            strength: 78,
            foilA: '#0ea5e9',
            foilB: '#67e8f9',
            foilC: '#dbeafe',
          }),
        ],
      }),
      makeVariant({
        name: 'Flame Accent Demo',
        rarity: 'Reference Flame v1',
        rarityKey: 'legendary',
        chanceWeight: 1,
        layout: 'classic',
        holo: 'none',
        subjectLayers: [
          makeSubjectLayer({
            name: 'Flame contour v1',
            image: '/img/holo_sample_subject_mask.png',
            mode: 'foil-flame',
            maskOnly: true,
            strength: 84,
            foilA: '#f97316',
            foilB: '#fb7185',
            foilC: '#fde047',
          }),
        ],
      }),
      makeVariant({
        name: 'Flame Smooth Demo',
        rarity: 'Reference Flame v2',
        rarityKey: 'legendary',
        chanceWeight: 1,
        layout: 'classic',
        holo: 'none',
        subjectLayers: [makeSubjectLayer({
          name: 'Continuous smooth flame',
          image: '/img/holo_sample_subject_mask.png',
          mode: 'foil-flame-v2',
          maskOnly: true,
          strength: 82,
          foilA: '#ff4b18', foilB: '#ff9f2d', foilC: '#ffe36b',
        })],
      }),
      makeVariant({
        name: 'Flame Hybrid Demo',
        rarity: 'Reference Flame v3',
        rarityKey: 'legendary',
        chanceWeight: 1,
        layout: 'classic',
        holo: 'none',
        subjectLayers: [makeSubjectLayer({
          name: 'Realistic layered fire',
          image: '/img/holo_sample_subject_mask.png',
          mode: 'foil-flame-hybrid',
          maskOnly: true,
          strength: 84,
          foilA: '#ff5418', foilB: '#ffad33', foilC: '#fff08a',
        })],
      }),
      makeVariant({
        name: 'Flame Anime Demo',
        rarity: 'Reference Flame v4',
        rarityKey: 'legendary',
        chanceWeight: 1,
        layout: 'classic',
        holo: 'none',
        subjectLayers: [makeSubjectLayer({
          name: 'Stylized anime flame',
          image: '/img/holo_sample_subject_mask.png',
          mode: 'foil-flame-anime',
          maskOnly: true,
          strength: 88,
          foilA: '#ef2b12', foilB: '#ff7a12', foilC: '#ffd62e',
        })],
      }),
      makeVariant({
        name: 'Flame Smoky Demo',
        rarity: 'Reference Flame v5',
        rarityKey: 'legendary',
        chanceWeight: 1,
        layout: 'classic',
        holo: 'none',
        subjectLayers: [makeSubjectLayer({
          name: 'Smoky realistic flame',
          image: '/img/holo_sample_subject_mask.png',
          mode: 'foil-flame-smoky',
          maskOnly: true,
          strength: 78,
          foilA: '#f04a18', foilB: '#ff9a28', foilC: '#ffe077',
        })],
      }),
      makeVariant({
        name: 'Flame Hybrid 50% Demo',
        rarity: 'Reference Flame 50%',
        rarityKey: 'legendary',
        chanceWeight: 1,
        layout: 'classic',
        holo: 'none',
        subjectLayers: [makeSubjectLayer({
          name: 'Realistic layered fire at 50%',
          image: '/img/holo_sample_subject_mask.png',
          mode: 'foil-flame-hybrid',
          maskOnly: true,
          strength: 50,
          foilA: '#ff5418', foilB: '#ffad33', foilC: '#fff08a',
        })],
      }),
    ],
  },
  {
    title: 'Peggy Moto',
    subtitle: 'Local Rider',
    hp: 95,
    type: 'civilian',
    chanceWeight: 42,
    image: '/img/peggy_moto.jpg',
    description: 'A street-level character card with multiple finishes in the same common pool.',
    accent: '#fb923c',
    foilA: '#fb7185',
    foilB: '#67e8f9',
    foilC: '#fde68a',
    attacks: [
      { name: 'Quick Turn', cost: 1, damage: 20, text: 'Move before the opponent on the next turn.' },
      { name: 'Side Street', cost: 2, damage: 40, text: 'Gets a bonus while a city location is active.' },
    ],
    variants: [
      makeVariant({ name: 'Base', rarity: 'Common', rarityKey: 'common', chanceWeight: 72, layout: 'classic', holo: 'none' }),
      makeVariant({ name: 'Etched', rarity: 'Common Etched', rarityKey: 'common', chanceWeight: 18, layout: 'classic', holo: 'etched', holoStrength: 42 }),
      makeVariant({ name: 'Prism', rarity: 'Common Prism', rarityKey: 'common', chanceWeight: 10, layout: 'classic', holo: 'prism', holoStrength: 34 }),
    ],
  },
  {
    title: 'Business Fudge',
    subtitle: 'Downtown Regular',
    hp: 105,
    type: 'civilian',
    chanceWeight: 38,
    image: '/img/business_fudge.jpg',
    description: 'Another common-pool subject so repeated packs do not collapse to a single character.',
    accent: '#eab308',
    foilA: '#facc15',
    foilB: '#22d3ee',
    foilC: '#f472b6',
    attacks: [
      { name: 'Pitch', cost: 1, damage: 25, text: 'Draw one card if this attack lands.' },
      { name: 'Close Deal', cost: 2, damage: 45, text: 'Extra damage against a weakened card.' },
    ],
    variants: [
      makeVariant({ name: 'Base', rarity: 'Common', rarityKey: 'common', chanceWeight: 75, layout: 'classic', holo: 'none' }),
      makeVariant({ name: 'Reverse Holo', rarity: 'Common Reverse', rarityKey: 'common', chanceWeight: 25, layout: 'classic', holo: 'reverse', holoStrength: 40 }),
    ],
  },
  {
    title: 'BCSO Moto',
    subtitle: 'Traffic Unit',
    hp: 130,
    type: 'police',
    chanceWeight: 45,
    image: '/img/moto_bcso.jpg',
    description: 'Built for pursuit, traffic control, and rapid response.',
    accent: '#4d8dff',
    foilA: '#38bdf8',
    foilB: '#a78bfa',
    foilC: '#f8fafc',
    attacks: [
      { name: 'Rapid Response', cost: 2, damage: 60, text: 'May act first on the next turn.' },
      { name: 'Intercept', cost: 3, damage: 90, text: 'Extra damage against vehicle cards.' },
    ],
    variants: [
      makeVariant({ name: 'Standard', rarity: 'Uncommon', rarityKey: 'uncommon', chanceWeight: 58, layout: 'classic', holo: 'none' }),
      makeVariant({ name: 'Reverse', rarity: 'Uncommon Reverse', rarityKey: 'uncommon', chanceWeight: 27, layout: 'classic', holo: 'reverse', holoStrength: 48 }),
      makeVariant({ name: 'Full Art Prism', rarity: 'Ultra Rare', rarityKey: 'ultra_rare', chanceWeight: 15, layout: 'full-art', holo: 'prism', holoStrength: 42 }),
    ],
  },
  {
    title: 'Sunset Run',
    subtitle: 'Location',
    hp: 110,
    type: 'location',
    chanceWeight: 32,
    image: '/img/sunset.jpg',
    description: 'A location print used to make the uncommon pool more varied.',
    accent: '#f97316',
    foilA: '#fb7185',
    foilB: '#fbbf24',
    foilC: '#60a5fa',
    attacks: [
      { name: 'Golden Hour', cost: 1, damage: 30, text: 'Boost a civilian card until the next turn.' },
      { name: 'Long Road', cost: 2, damage: 55, text: 'Location cards remain active one extra turn.' },
    ],
    variants: [
      makeVariant({ name: 'Standard', rarity: 'Uncommon', rarityKey: 'uncommon', chanceWeight: 70, layout: 'classic', holo: 'none' }),
      makeVariant({ name: 'Aurora', rarity: 'Uncommon Holo', rarityKey: 'uncommon', chanceWeight: 30, layout: 'classic', holo: 'aurora', holoStrength: 38 }),
    ],
  },
  {
    title: 'Dark Sky',
    subtitle: 'Criminal',
    hp: 120,
    type: 'criminal',
    chanceWeight: 35,
    image: '/img/dark_sky_woman.jpg',
    description: 'An illustration-style card where the artwork owns nearly the entire surface.',
    accent: '#a855f7',
    foilA: '#f0abfc',
    foilB: '#60a5fa',
    foilC: '#fb7185',
    attacks: [
      { name: 'Disappear', cost: 1, damage: 30, text: 'Reduce incoming damage on the next turn.' },
      { name: 'Night Move', cost: 3, damage: 80, text: 'Deals bonus damage under a location card.' },
    ],
    variants: [
      makeVariant({ name: 'Rare', rarity: 'Rare', rarityKey: 'rare', chanceWeight: 55, layout: 'classic', holo: 'cosmos', holoStrength: 35 }),
      makeVariant({ name: 'Illustration Rare', rarity: 'Illustration Rare', rarityKey: 'rare', chanceWeight: 30, layout: 'illustration', holo: 'oilslick', holoStrength: 32 }),
      makeVariant({ name: 'Full Art', rarity: 'Ultra Rare', rarityKey: 'ultra_rare', chanceWeight: 15, layout: 'full-art', holo: 'rainbow', holoStrength: 28 }),
    ],
  },
  {
    title: 'County Heat Gauntlet',
    subtitle: 'Event',
    hp: 145,
    type: 'police',
    chanceWeight: 28,
    image: '/img/county_heat_gauntlet.jpg',
    description: 'A second rare-pool subject with standard and premium treatments.',
    accent: '#ef4444',
    foilA: '#fb7185',
    foilB: '#facc15',
    foilC: '#38bdf8',
    attacks: [
      { name: 'Heat Check', cost: 2, damage: 65, text: 'Adds pressure to the opposing card.' },
      { name: 'Gauntlet', cost: 3, damage: 95, text: 'Heavy damage after surviving a turn.' },
    ],
    variants: [
      makeVariant({ name: 'Rare', rarity: 'Rare', rarityKey: 'rare', chanceWeight: 65, layout: 'classic', holo: 'etched', holoStrength: 38 }),
      makeVariant({ name: 'Prism Full Art', rarity: 'Ultra Rare', rarityKey: 'ultra_rare', chanceWeight: 25, layout: 'full-art', holo: 'prism', holoStrength: 38 }),
      makeVariant({ name: 'Gold Chase', rarity: 'Legendary', rarityKey: 'legendary', chanceWeight: 10, layout: 'dark-borderless', holo: 'aurora', holoStrength: 34, foilA: '#f59e0b', foilB: '#fde68a', foilC: '#ffffff' }),
    ],
  },
  {
    title: 'Air Juanito',
    subtitle: 'Special Vehicle',
    hp: 160,
    type: 'vehicle',
    chanceWeight: 24,
    image: '/img/air_juanito.jpg',
    description: 'A vehicle chase card with multiple high-rarity print treatments.',
    accent: '#22d3ee',
    foilA: '#67e8f9',
    foilB: '#818cf8',
    foilC: '#fef08a',
    attacks: [
      { name: 'Flyover', cost: 2, damage: 70, text: 'Ignores one ground-based effect.' },
      { name: 'Hard Landing', cost: 3, damage: 100, text: 'High damage with a recovery turn.' },
    ],
    variants: [
      makeVariant({ name: 'Ultra Rare', rarity: 'Ultra Rare', rarityKey: 'ultra_rare', chanceWeight: 70, layout: 'full-art', holo: 'prism', holoStrength: 36 }),
      makeVariant({ name: 'Oil Slick', rarity: 'Ultra Rare Alt', rarityKey: 'ultra_rare', chanceWeight: 30, layout: 'dark-borderless', holo: 'oilslick', holoStrength: 42 }),
    ],
  },
  {
    title: 'Pier Park Man',
    subtitle: 'Legendary Civilian',
    hp: 180,
    type: 'civilian',
    chanceWeight: 20,
    image: '/img/pier_park_man.jpg',
    description: 'A full-art legendary-style test card built to make foil and lighting easy to inspect.',
    accent: '#fbbf24',
    foilA: '#fb7185',
    foilB: '#22d3ee',
    foilC: '#fde047',
    attacks: [
      { name: 'Boardwalk Legend', cost: 2, damage: 90, text: 'Gain a bonus when a location card is active.' },
      { name: 'Last Call', cost: 4, damage: 130, text: 'A heavy finisher for pack testing.' },
    ],
    variants: [
      makeVariant({ name: 'Legendary Rainbow', rarity: 'Legendary', rarityKey: 'legendary', chanceWeight: 55, layout: 'full-art', holo: 'rainbow', holoStrength: 28 }),
      makeVariant({ name: 'Legendary Etched', rarity: 'Legendary Etched', rarityKey: 'legendary', chanceWeight: 30, layout: 'illustration', holo: 'etched', holoStrength: 45 }),
      makeVariant({ name: 'Legendary Aurora', rarity: 'Legendary Aurora', rarityKey: 'legendary', chanceWeight: 15, layout: 'dark-borderless', holo: 'aurora', holoStrength: 38 }),
    ],
  },
]

export const defaultCards = baseCards.map(card => normalizeCard({ id: uuid(), ...card }))

export function newCard() {
  return normalizeCard({
    id: uuid(),
    title: 'New Card',
    subtitle: 'Custom Print',
    hp: 100,
    type: 'civilian',
    chanceWeight: 100,
    image: '/img/pier_park_man.jpg',
    description: 'Describe the card here.',
    accent: '#f59e0b',
    foilA: '#ff4d8d',
    foilB: '#4df3ff',
    foilC: '#ffe66d',
    attacks: [{ name: 'Move', cost: 1, damage: 20, text: 'Describe the move here.' }],
    variants: [makeVariant()],
  })
}
