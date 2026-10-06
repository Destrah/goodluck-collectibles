// Card condition: every pulled card copy carries small print imperfections (and later wear) in its metadata, and
// a grader finds them to give the card a grade. Mirrored on the server by fivem/server/modules/grading.lua —
// keep the numbers (thresholds, deductions, match radii) the same in both.
//
// condition = {
//   v: 1,
//   centering: { front: [cx, cy], back: [cx, cy] }  -1..1: left border = base * (1 + cx), right = base * (1 - cx)
//   art:  [dx, dy]        artwork printed off register, % of the card size
//   text: { title:[dx,dy], hp:[dx,dy], ... } independent sections; v1 arrays still supported
//   foil: [dx, dy, hue]   holo / foil layer offset (%) and colour drift (deg): every copy differs a little
//   mask: [dx, dy]        subject-mask effect layers offset, %
//   corners: { front: [tl, tr, br, bl], back: [...] }   0..1 whitening / softening
//   edges:   { front: [top, right, bottom, left], back: [...] } 0..1 chipping
//   marks: [{ id, type: 'scratch' | 'dent' | 'crease' | 'bend' | 'tear', side, x1, y1, x2, y2, s }]  points in % of the card
// }

export const CONDITION_VERSION = 2
// FiveM's JSON turns an empty Lua list into {}: read every list through this
export const asArray = value => Array.isArray(value) ? value : []

const r2 = n => Math.round(n * 100) / 100
const clamp = (n, min, max) => Math.min(Math.max(n, min), max)
const gauss = (random = Math.random) => {
  let u = 0, v = 0
  while (u === 0) u = random()
  while (v === 0) v = random()
  return Math.sqrt(-2 * Math.log(u)) * Math.cos(2 * Math.PI * v)
}

// ------------------------------------------------------------------ flaw types (what a grader can mark)

export const FLAW_TYPES = [
  { value: 'centering', label: 'Off-centre borders', hint: 'Opposing borders have different widths. Measure both borders; a 10 needs 55/45 or better on the front, 75/25 on the back. Mark artwork and text registration separately.' },
  { value: 'art', label: 'Artwork shifted', hint: 'The picture is printed off its window: compare where the art is cropped against the reference, or measure from the edge with the ruler.' },
  { value: 'text', label: 'Text shifted', hint: 'Click the specific shifted name, HP, type line, description, attack text or footer. Clicking the artwork does not confirm a text flaw.' },
  { value: 'foil', label: 'Foil / holo off', hint: 'Only the shiny holo pattern is off; the picture and text are fine. Turn on "Foil only" to see just the holo on both cards: if its stripes / colours sit higher, lower or sideways, or the colours are tinted differently (e.g. more pink than blue) compared with the reference, mark it.' },
  { value: 'mask', label: 'Mask effect off', hint: 'The subject effect is not lined up with the picture.' },
  { value: 'corner', label: 'Corner wear', hint: 'Whitened, soft or dinged corner' },
  { value: 'edge', label: 'Edge wear', hint: 'Chipped or whitened edge' },
  { value: 'scratch', label: 'Surface scratch', hint: 'Fine line in the gloss (try the raking light)' },
  { value: 'dent', label: 'Dent / dimple', hint: 'Small pressed-in spot' },
  { value: 'crease', label: 'Crease', hint: 'Fold line through the card' },
  { value: 'bend', label: 'Bend', hint: 'Soft warp across the card' },
  { value: 'tear', label: 'Tear', hint: 'Rip in the card stock' },
  // manufacturing defects (can come straight out of a pack)
  { value: 'roller', label: 'Roller marks', hint: 'The card got caught in the press rollers: a band of faint parallel pressed lines running across it. Best seen with the raking light; click on the band.' },
  { value: 'printline', label: 'Print line', hint: 'A thin, perfectly straight ink streak across the print, from a dirty print head. Click on the line.' },
  { value: 'inkspot', label: 'Ink spot / fisheye', hint: 'A tiny speck of stray ink, or a little ring where the ink failed to stick. Use the loupe; click on it.' },
  { value: 'stain', label: 'Stain', hint: 'A faint discoloured patch, like wax or gum residue from the pack. Click on it.' },
]
// what each marked flaw costs the grade (s: severity 0..1); mirrored in grading.lua markDeduction
const MARK_DEDUCTIONS = { tear: s => 3 + 2 * s, crease: s => 2 + 2 * s, bend: s => 1.5 + s, dent: () => 1, roller: s => 1 + s, stain: s => 0.5 + s * 0.5, inkspot: () => 0.5, printline: s => 0.5 + s * 0.5 }
const markDeduction = (type, s) => (MARK_DEDUCTIONS[type] || (v => 0.5 + v * 0.5))(s)
// how close (in % of the card) a grader's click must be to a marked flaw; point flaws measure to the point
const MARK_RADIUS = { bend: 12, roller: 12, dent: 8, inkspot: 6, stain: 10, printline: 6 }
const POINT_MARKS = new Set(['dent', 'inkspot', 'stain'])
export const flawLabel = type => FLAW_TYPES.find(entry => entry.value === type)?.label || type

// thresholds: below these a variation is normal print tolerance, not a flaw
export const LIMITS = { centeringFront: 0.1, centeringBack: 0.5, art: 0.6, text: 0.5, foil: 1.5, foilHue: 18, mask: 0.8, wear: 0.15 }
export const TEXT_SECTIONS = ['subtitle','title','hp','info','description','attack','footer']
export function textOffset(condition, part) {
  return asArray(Array.isArray(condition?.text) ? condition.text : condition?.text?.[part])
}
export function textSectionStyle(condition, part) {
  const [x=0,y=0]=textOffset(condition,part)
  return Math.hypot(x,y)>LIMITS.text ? {transform:`translate(calc(var(--card-w) * ${x} / 100), calc(var(--card-h) * ${y} / 100))`} : {}
}

// Server validation bands; the bench additionally requires a hit on the actual
// rendered text element. Coordinates use the outer card face, in percent.
export function textRegions(condition, layout = 'classic') {
  const top=layout === 'classic' ? 58 : 49
  return Object.fromEntries(Object.entries({subtitle:[3,2,82,7],title:[3,5,82,15],hp:[72,2,98,15],info:[3,top,98,top+8],description:[3,top+5,98,94],attack:[3,top+9,98,94],footer:[3,93,98,100]}).map(([key,r])=>{const [dx=0,dy=0]=textOffset(condition,key);return [key,[r[0]+dx,r[1]+dy,r[2]+dx,r[3]+dy]]}))
}

const CORNER_POINTS = [[0, 0], [100, 0], [100, 100], [0, 100]] // tl tr br bl
const EDGE_NAMES = ['top', 'right', 'bottom', 'left']
const CORNER_NAMES = ['top left', 'top right', 'bottom right', 'bottom left']

const tieredWear = s => s > 0.7 ? 1.5 : s > 0.4 ? 1 : 0.5

// Every real flaw of a card (what the grade is made of). hasFoil / hasMask: the print has those layers at all.
export function listFlaws(condition, { hasFoil = false, hasMask = false, layout = 'classic' } = {}) {
  if (!condition) return []
  const flaws = []
  for (const side of ['front', 'back']) {
    const [cx = 0, cy = 0] = condition.centering?.[side] || []
    const c = Math.max(Math.abs(cx), Math.abs(cy))
    const limit = side === 'front' ? LIMITS.centeringFront : LIMITS.centeringBack
    if (c > limit) {
      const deduction = side === 'front' ? (c > 0.35 ? 3 : c > 0.2 ? 2 : 1) : (c > 0.7 ? 2 : 1)
      flaws.push({ id: `centering-${side}`, type: 'centering', side, deduction, label: `Off-centre (${side})` })
    }
  }
  const off = value => Math.hypot(value?.[0] || 0, value?.[1] || 0)
  const art = off(condition.art)
  if (art > LIMITS.art) flaws.push({ id: 'art', type: 'art', side: 'front', deduction: art > 1.5 ? 1.5 : 0.5, label: 'Artwork misaligned' })
  const regions=textRegions(condition,layout)
  if (Array.isArray(condition.text)) {
    const text=off(condition.text)
    if(text>LIMITS.text) flaws.push({id:'text',type:'text',side:'front',deduction:text>1.2?1:.5,label:'Text misaligned (legacy layer)',regions})
  } else for(const part of TEXT_SECTIONS) {
    const text=off(textOffset(condition,part))
    if(text>LIMITS.text) flaws.push({id:`text-${part}`,type:'text',side:'front',deduction:text>1.2?1:.5,label:`Text misaligned (${part})`,textPart:part,regions:{[part]:regions[part]}})
  }
  const foil = off(condition.foil)
  if (hasFoil && (foil > LIMITS.foil || Math.abs(condition.foil?.[2] || 0) > LIMITS.foilHue)) flaws.push({ id: 'foil', type: 'foil', side: 'front', deduction: foil > 3 ? 1 : 0.5, label: 'Foil / holo off' })
  if (hasMask && off(condition.mask) > LIMITS.mask) flaws.push({ id: 'mask', type: 'mask', side: 'front', deduction: 0.5, label: 'Mask effect off' })
  for (const side of ['front', 'back']) {
    asArray(condition.corners?.[side]).forEach((s, index) => {
      if (s > LIMITS.wear) flaws.push({ id: `corner-${side}-${index}`, type: 'corner', side, index, x: CORNER_POINTS[index][0], y: CORNER_POINTS[index][1], deduction: tieredWear(s), label: `Corner wear (${CORNER_NAMES[index]}, ${side})` })
    })
    asArray(condition.edges?.[side]).forEach((s, index) => {
      if (s > LIMITS.wear) flaws.push({ id: `edge-${side}-${index}`, type: 'edge', side, index, deduction: tieredWear(s), label: `Edge wear (${EDGE_NAMES[index]}, ${side})` })
    })
  }
  for (const mark of asArray(condition.marks)) {
    const s = clamp(Number(mark.s) || 0.3, 0, 1)
    const deduction = markDeduction(mark.type, s)
    flaws.push({ id: mark.id, type: mark.type, side: mark.side || 'front', mark, deduction: r2(deduction), label: `${flawLabel(mark.type)} (${mark.side || 'front'})` })
  }
  return flaws
}

// PSA-style scale from a list of flaws
export function gradeFromFlaws(flaws) {
  const total = flaws.reduce((sum, flaw) => sum + (flaw.deduction || 0), 0)
  return clamp(Math.floor((10 - total) * 2) / 2, 1, 10)
}
export const GRADE_NAMES = { 10: 'GEM MT', 9.5: 'MINT+', 9: 'MINT', 8.5: 'NM-MT+', 8: 'NM-MT', 7.5: 'NM+', 7: 'NM', 6.5: 'EX-MT+', 6: 'EX-MT', 5.5: 'EX+', 5: 'EX', 4.5: 'VG-EX+', 4: 'VG-EX', 3.5: 'VG+', 3: 'VG', 2.5: 'GOOD+', 2: 'GOOD', 1.5: 'FAIR', 1: 'POOR' }
export const gradeName = grade => GRADE_NAMES[grade] || ''
export const trueGrade = (condition, options) => gradeFromFlaws(listFlaws(condition, options))
export const printHasFoil = card => !!card && ((card.holo && card.holo !== 'none') || false)
export const printHasMask = card => Array.isArray(card?.subjectLayers) && card.subjectLayers.some(layer => layer?.image)
export const flawOptions = card => ({ hasFoil: printHasFoil(card), hasMask: printHasMask(card), layout:card?.layout })

// ------------------------------------------------------------------ factory condition of a newly pulled card

let markSerial = 0
const markId = type => `${type}-${Date.now().toString(36)}-${(markSerial++).toString(36)}`

function randomMark(type, random, side = random() < 0.7 ? 'front' : 'back') {
  const s = r2(0.2 + random() * 0.6)
  if (type === 'tear') { // starts at an edge
    const edge = Math.floor(random() * 4), along = 10 + random() * 80, depth = 2 + s * 6
    const [x1, y1, x2, y2] = edge === 0 ? [along, 0, along + 1, depth] : edge === 1 ? [100, along, 100 - depth, along + 1] : edge === 2 ? [along, 100, along - 1, 100 - depth] : [0, along, depth, along - 1]
    return { id: markId(type), type, side, x1: r2(x1), y1: r2(y1), x2: r2(x2), y2: r2(y2), s }
  }
  if (POINT_MARKS.has(type)) { const x = 15 + random() * 70, y = 15 + random() * 70; return { id: markId(type), type, side, x1: r2(x), y1: r2(y), x2: r2(x), y2: r2(y), s } }
  // a line: scratches are short; creases / bends / roller marks / print lines run across the card. Roller marks
  // follow the feed direction (nearly level); print lines are dead straight, level or upright.
  const across = type === 'crease' || type === 'bend' || type === 'roller' || type === 'printline'
  const angle = type === 'roller' ? (random() - 0.5) * 0.3
    : type === 'printline' ? (random() < 0.5 ? 0 : Math.PI / 2) + (random() - 0.5) * 0.06
    : across ? (random() < 0.5 ? 0 : Math.PI / 2) + (random() - 0.5) * 0.9 : random() * Math.PI
  const length = across ? 140 : 8 + random() * 22
  const cx = 20 + random() * 60, cy = 20 + random() * 60
  const dx = Math.cos(angle) * length / 2, dy = Math.sin(angle) * length / 2
  return { id: markId(type), type, side, x1: r2(clamp(cx - dx, 0, 100)), y1: r2(clamp(cy - dy, 0, 100)), x2: r2(clamp(cx + dx, 0, 100)), y2: r2(clamp(cy + dy, 0, 100)), s }
}

// A new card from a pack: print defects only (centering, art / text / foil / mask registration). No wear or
// damage: corners, edges, scratches, creases and tears only come from handling afterwards.
export function generateCondition(random = Math.random) {
  const perfect = random() < 0.04 // a true gem: every tolerance well inside the limits
  const g = scale => perfect ? r2(gauss(random) * scale * 0.25) : r2(gauss(random) * scale)
  const miscut = !perfect && random() < 0.08
  const misprint = !perfect && random() < 0.04
  // rare manufacturing defects (mirrored in grading.lua G.generate)
  const marks = []
  if (!perfect) for (const [type, chance] of FACTORY_MARKS) if (random() < chance) marks.push(randomMark(type, random))
  return {
    v: CONDITION_VERSION,
    centering: {
      front: [clamp(g(miscut ? 0.3 : 0.13), -0.8, 0.8), clamp(g(miscut ? 0.18 : 0.09), -0.8, 0.8)].map(r2),
      back: [clamp(g(0.36), -0.85, 0.85), clamp(g(0.28), -0.85, 0.85)].map(r2),
    },
    art: [g(misprint ? 1.8 : 0.48), g(misprint ? 1.4 : 0.38)],
    text: Object.fromEntries(TEXT_SECTIONS.map(part=>[part,random()<.28?[g(.36),g(.3)]:[0,0]])),
    foil: [g(1.3), g(1.3), r2(gauss(random) * (perfect ? 2 : 12))],
    mask: [g(0.45), g(0.45)],
    corners: { front: [0, 0, 0, 0], back: [0, 0, 0, 0] },
    edges: { front: [0, 0, 0, 0], back: [0, 0, 0, 0] },
    marks,
  }
}
const FACTORY_MARKS = [['roller', 0.02], ['printline', 0.03], ['inkspot', 0.04], ['stain', 0.015]]

// ------------------------------------------------------------------ wear from handling

// What protects a card: none | sleeve | toploader | slab (and a binder pocket, which counts as a sleeve)
export const PROTECTION = { none: 0, sleeve: 1, toploader: 2, slab: 3 }
export const PROTECTION_LABELS = { none: 'Raw (unprotected)', sleeve: 'Penny sleeve', toploader: 'Toploader', slab: 'Graded slab' }

// One handling event. rough: spun / flipped hard in the inspector. Returns a new condition (or the same one when
// nothing happened). Server-authoritative in FiveM: grading.lua does the same roll.
export function applyWear(condition, { protection = 'none', rough = false } = {}, random = Math.random) {
  const level = PROTECTION[protection] ?? 0
  if (!condition || level >= 2) return condition // toploaders and slabs keep the card safe
  const chance = rough ? (level === 1 ? 0.12 : 0.45) : (level === 1 ? 0.01 : 0.07)
  if (random() >= chance) return condition
  const next = structuredClone(condition)
  next.marks = asArray(next.marks)
  for (const key of ['corners', 'edges']) {
    next[key] = next[key] || {}
    for (const face of ['front', 'back']) next[key][face] = asArray(next[key][face]).length === 4 ? next[key][face] : [0, 0, 0, 0]
  }
  const side = random() < 0.6 ? 'front' : 'back'
  const roll = random()
  const bump = (list, index, amount) => { list[index] = r2(clamp((list[index] || 0) + amount, 0, 1)) }
  if (rough && level === 0 && roll < 0.22) next.marks.push(randomMark(random() < 0.6 ? 'crease' : 'bend', random, side))
  else if (rough && level === 0 && roll < 0.27) next.marks.push(randomMark('tear', random, side))
  else if (roll < 0.55) bump(next.corners[side], Math.floor(random() * 4), 0.08 + random() * 0.18)
  else if (roll < 0.85) bump(next.edges[side], Math.floor(random() * 4), 0.06 + random() * 0.15)
  else next.marks.push(randomMark(random() < 0.7 ? 'scratch' : 'dent', random, side))
  return next
}

// ------------------------------------------------------------------ grading: checking a grader's mark

// A grader marks { type, side, x, y } (x / y in % of the card face). It is confirmed only when a real flaw of that
// type is there; otherwise it is rejected (no grading something that isn't wrong). Returns the flaw or null.
export function matchMark(flaws, mark, foundIds = []) {
  const found = new Set(foundIds)
  const x = Number(mark?.x), y = Number(mark?.y)
  const near = flaw => {
    if (flaw.type === 'text') {
      const r=flaw.regions?.[mark?.textPart]
      return !!r && x>=r[0] && x<=r[2] && y>=r[1] && y<=r[3]
    }
    if (flaw.type === 'centering' || flaw.type === 'art' || flaw.type === 'foil' || flaw.type === 'mask') return true // whole-face faults
    if (flaw.type === 'corner') return Math.hypot(x - flaw.x, y - flaw.y) <= 18
    if (flaw.type === 'edge') return [y, 100 - x, 100 - y, x][flaw.index] <= 9
    const radius = MARK_RADIUS[flaw.type] ?? 7 // scratch, crease, tear: 7
    if (POINT_MARKS.has(flaw.type)) return Math.hypot(x - flaw.mark.x1, y - flaw.mark.y1) <= radius
    return segmentDistance(x, y, flaw.mark) <= radius
  }
  // "Off-centre" is how a shifted print looks to a grader, whether it's the borders, the art or the text block
  const accepts = [mark?.type]
  for (const type of accepts) {
    const hit = flaws.find(flaw => !found.has(flaw.id) && flaw.type === type && flaw.side === (mark?.side || 'front') && near(flaw))
    if (hit) return hit
  }
  return null
}
function segmentDistance(x, y, mark) {
  const ax = mark.x1, ay = mark.y1, bx = mark.x2, by = mark.y2
  const lx = bx - ax, ly = by - ay, length = lx * lx + ly * ly
  const t = length ? clamp(((x - ax) * lx + (y - ay) * ly) / length, 0, 1) : 0
  return Math.hypot(x - (ax + t * lx), y - (ay + t * ly))
}

// The grade on the slab: made of the flaws the grader actually found. Missed flaws make it look better than it is.
export function gradeFromFound(flaws, foundIds) {
  const found = new Set(foundIds)
  return gradeFromFlaws(flaws.filter(flaw => found.has(flaw.id)))
}

export const certNumber = (random = Math.random) => String(Math.floor(10000000 + random() * 89999999))

// The grader picks the final grade on the slab: their confirmed calls suggest one, and they may go up to `adjust`
// either side of it (a generous or harsh grader). Mirrored in grading.lua (G.allowedGrade).
export const DEFAULT_GRADE_ADJUST = 1
export function gradeChoices(suggested, adjust = DEFAULT_GRADE_ADJUST) {
  const list = []
  for (let grade = Math.max(1, suggested - adjust); grade <= Math.min(10, suggested + adjust) + 1e-9; grade += 0.5) list.push(Math.round(grade * 2) / 2)
  return list
}
export const allowedGrade = (chosen, suggested, adjust = DEFAULT_GRADE_ADJUST) => {
  const grade = Number(chosen)
  return gradeChoices(suggested, adjust).includes(grade) ? grade : suggested
}

// ------------------------------------------------------------------ rendering helpers

// CSS variables for a card face from its condition (TradingCard / CardBack)
export function conditionStyle(condition, side = 'front') {
  if (!condition) return {}
  const [cx = 0, cy = 0] = condition.centering?.[side] || []
  const centeringLimit = side === 'front' ? LIMITS.centeringFront : LIMITS.centeringBack
  const centeringOff = Math.max(Math.abs(cx), Math.abs(cy)) > centeringLimit
  // Fractional border widths are rounded down by Chromium. Even tiny normal
  // variations otherwise create an ungradeable one-pixel border discrepancy.
  const style = { '--cx': centeringOff ? clamp(cx, -0.9, 0.9) : 0, '--cy': centeringOff ? clamp(cy, -0.9, 0.9) : 0 }
  if (side === 'front') {
    const artOff = Math.hypot(condition.art?.[0] || 0, condition.art?.[1] || 0) > LIMITS.art
    style['--art-dx'] = artOff ? condition.art?.[0] || 0 : 0
    style['--art-dy'] = artOff ? condition.art?.[1] || 0 : 0
    // the foil is drawn shifted only when it's out of tolerance; within it, it matches the reference exactly
    const foilOff = Math.hypot(condition.foil?.[0] || 0, condition.foil?.[1] || 0) > LIMITS.foil || Math.abs(condition.foil?.[2] || 0) > LIMITS.foilHue
    style['--foil-on'] = foilOff ? 1 : 0
    style['--text-dx'] = condition.text?.[0] || 0
    style['--text-dy'] = condition.text?.[1] || 0
    style['--foil-dx'] = foilOff ? condition.foil?.[0] || 0 : 0
    style['--foil-dy'] = foilOff ? condition.foil?.[1] || 0 : 0
    style['--foil-hue'] = foilOff ? condition.foil?.[2] || 0 : 0
    const maskOff = Math.hypot(condition.mask?.[0] || 0, condition.mask?.[1] || 0) > LIMITS.mask
    style['--mask-dx'] = maskOff ? condition.mask?.[0] || 0 : 0
    style['--mask-dy'] = maskOff ? condition.mask?.[1] || 0 : 0
  }
  return style
}

// The condition a copy has once it is known (old items made before conditions existed get one when first used).
export const ensureCondition = card => card?.condition ? card : { ...card, condition: generateCondition() }
