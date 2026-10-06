import { useEffect, useLayoutEffect, useRef, useState } from 'react'
import TradingCard from '../components/TradingCard'
import { CardBack } from '../collectables/tradingCards.jsx'
import { FLAW_TYPES, LIMITS, TEXT_SECTIONS, textOffset, asArray, flawLabel, gradeName, listFlaws, flawOptions, matchMark, gradeFromFound, gradeFromFlaws, certNumber, gradeChoices, allowedGrade, DEFAULT_GRADE_ADJUST } from './condition.js'
import './grading.css'

// Card width in real life: a standard trading card is 63.5 x 88.9 mm.
const CARD_MM = 63.5
const LENS = 190, LENS_ZOOM = 2.8
const WHOLE_FACE = new Set(['centering', 'art', 'foil', 'mask'])
const TEXT_TARGETS = [['subtitle','.card-kicker'],['title','.card-header h2'],['hp','.hp-block small'],['hp','.hp-value'],['info','.card-info-row span'],['description','.card-description'],['attack','.attack-copy strong'],['attack','.attack-copy small'],['attack','.attack > b'],['footer','.card-footer span']]
const FACE_FLAWS = FLAW_TYPES.filter(entry => WHOLE_FACE.has(entry.value))
const SPOT_FLAWS = FLAW_TYPES.filter(entry => !WHOLE_FACE.has(entry.value))
// what the measurement guides outline on the front (selector, label)
const GUIDE_PARTS = [['.card-art-wrap', 'artwork window'], ['.card-header h2', 'name'], ['.hp-block', 'HP'], ['.card-info-row', 'type / rarity line'], ['.card-body', 'text box'], ['.card-footer', 'footer']]

// one light shared by both cards: hovering either one lights the foil / holo on both at the same spot
function createLightDriver() {
  const listeners = new Set()
  return { effectFrames: new Map(), subscribe(fn) { listeners.add(fn); return () => listeners.delete(fn) }, emit(light) { listeners.forEach(fn => fn(light)) } }
}

function Face({ card, side, driver, comparison }) {
  return side === 'front'
    ? <TradingCard card={card} size="viewer" interactive={false} showProtection={false} driver={driver} comparison={comparison} />
    : <div className="grading-back"><CardBack item={card} showProtection={false} /></div>
}

// A grading session checked locally (standalone): the same rules the FiveM server applies.
export function localGradingSession(card, { maxWrong = 6, grader = 'You', gradeAdjust = DEFAULT_GRADE_ADJUST } = {}) {
  const flaws = listFlaws(card.condition, flawOptions(card))
  const found = [], calls = []
  let wrong = 0
  return {
    maxWrong, gradeAdjust,
    async mark(mark) {
      if (wrong >= maxWrong) throw new Error('Too many wrong calls: submit your grade or cancel.')
      const flaw = matchMark(flaws, mark, found)
      if (flaw) {
        found.push(flaw.id)
        calls.push({ type: flaw.type, side: flaw.side, label: flaw.label, deduction: flaw.deduction, x: Number(mark.x), y: Number(mark.y) })
        return { confirmed: true, flaw: { id: flaw.id, type: flaw.type, side: flaw.side, label: flaw.label, deduction: flaw.deduction }, found: found.length }
      }
      wrong += 1
      return { confirmed: false, wrong, maxWrong }
    },
    // grade: the grader's final pick (suggested ± gradeAdjust); returns the slabbed card and its grading record
    async submit({ grade: chosen } = {}) {
      const suggested = gradeFromFound(flaws, found)
      const grade = allowedGrade(chosen ?? suggested, suggested, gradeAdjust)
      const graded = { grade, name: gradeName(grade), cert: certNumber(), gradedAt: new Date().toISOString(), found: found.length, grader }
      const record = { ...graded, suggested, title: card.title, variantName: card.variantName, setName: card.setName || '',
        baseCardId: card.baseCardId || card.id, variantId: card.variantId, condition: card.condition, marks: calls }
      return { card: { ...card, graded, protection: 'slab' }, grade, record }
    },
    async cancel() {},
  }
}

const mm = value => `${value.toFixed(2)} mm`

// Measurement guides over a face: the card's border on each side and where every printed part sits, in mm from
// the cut edge. On the reference print they are the expected numbers to measure the graded card against.
// layout position of an element inside `root` (offsetLeft chain): unaffected by the table's zoom / pan / rotation
function layoutBox(element, root) {
  let x = 0, y = 0, node = element
  while (node && node !== root) {
    x += node.offsetLeft; y += node.offsetTop
    const parent = node.offsetParent
    if (parent && parent !== root && root.contains(parent)) { x += parent.clientLeft; y += parent.clientTop }
    node = parent && root.contains(parent) ? parent : null
  }
  return { x, y, w: element.offsetWidth, h: element.offsetHeight }
}

function MeasureGuides({ host, side, deps, layers = { borders: true, parts: true, centre: true } }) {
  const [guides, setGuides] = useState(null)
  useLayoutEffect(() => {
    let frame = 0, timer = 0
    const measure = () => {
      const root = host.current
      const card = root?.querySelector(side === 'front' ? '.trading-card' : '.collectible-card-back-face')
      if (!root || !card) return
      const cardBox = layoutBox(card, root)
      const per = CARD_MM / (cardBox.w || 390)
      const next = { card: cardBox, per, parts: [], borders: null }
      if (side === 'front') {
        const style = getComputedStyle(card)
        const b = ['Top', 'Right', 'Bottom', 'Left'].map(edge => parseFloat(style[`border${edge}Width`]) || 0)
        next.borders = b
        for (const [selector, label] of GUIDE_PARTS) {
          const element = card.querySelector(selector)
          if (element) next.parts.push({ label, ...layoutBox(element, root) })
        }
      }
      setGuides(next)
    }
    frame = requestAnimationFrame(measure)
    timer = setTimeout(measure, 450) // artwork / fonts settle
    window.addEventListener('resize', measure)
    return () => { cancelAnimationFrame(frame); clearTimeout(timer); window.removeEventListener('resize', measure) }
  }, [side, ...deps])
  if (!guides) return null
  const { card: c, per, parts, borders } = guides
  const cx = c.x + c.w / 2, cy = c.y + c.h / 2
  return <svg className="grading-guides" aria-hidden="true">
    {layers.centre && <>
      <line className="centre" x1={cx} y1={c.y - 6} x2={cx} y2={c.y + c.h + 6} />
      <line className="centre" x1={c.x - 6} y1={cy} x2={c.x + c.w + 6} y2={cy} />
    </>}
    {layers.borders && borders && <g className="borders">
      <text x={cx} y={c.y + 11} textAnchor="middle">top border {mm(borders[0] * per)}</text>
      <text x={c.x + c.w - 5} y={cy - 6} textAnchor="end">right {mm(borders[1] * per)}</text>
      <text x={cx} y={c.y + c.h - 5} textAnchor="middle">bottom border {mm(borders[2] * per)}</text>
      <text x={c.x + 5} y={cy - 6}>left {mm(borders[3] * per)}</text>
      <text x={c.x + 5} y={cy + 8} className="sub">left/right {Math.round(borders[3] / (borders[1] + borders[3] || 1) * 100)}/{Math.round(borders[1] / (borders[1] + borders[3] || 1) * 100)} · top/bottom {Math.round(borders[0] / (borders[0] + borders[2] || 1) * 100)}/{Math.round(borders[2] / (borders[0] + borders[2] || 1) * 100)}</text>
    </g>}
    {layers.parts && parts.map(part => <g key={part.label} className="part">
      <rect x={part.x} y={part.y} width={part.w} height={part.h} />
      <text x={part.x + 3} y={part.y - 3}>{part.label}: ← {mm((part.x - c.x) * per)} · ↑ {mm((part.y - c.y) * per)}</text>
    </g>)}
  </svg>
}

// One bench surface: a card face you can measure (ruler), magnify (loupe) and, on the graded card, mark.
// Standalone debugger: where each real flaw is (whole-side ones as a frame, spot ones circled / traced)
function DebugLayer({ flaws, found, side }) {
  const list = flaws.filter(flaw => flaw.side === side)
  return <svg className="grading-debug" viewBox="0 0 100 100" preserveAspectRatio="none" aria-hidden="true">
    {list.map(flaw => {
      const cls = found.has(flaw.id) ? 'found' : 'missed'
      if (flaw.type === 'text') return <g key={flaw.id}>{Object.entries(flaw.regions || {}).map(([part,r])=><rect key={part} className={cls} x={r[0]} y={r[1]} width={r[2]-r[0]} height={r[3]-r[1]}/>)}</g>
      if (WHOLE_FACE.has(flaw.type)) return <rect key={flaw.id} className={cls} x="1" y="1" width="98" height="98" />
      if (flaw.type === 'corner') return <circle key={flaw.id} className={cls} cx={flaw.x} cy={flaw.y} r="9" />
      if (flaw.type === 'edge') { const [x1, y1, x2, y2] = [[0, 0, 100, 0], [100, 0, 100, 100], [0, 100, 100, 100], [0, 0, 0, 100]][flaw.index]; return <line key={flaw.id} className={cls} x1={x1} y1={y1} x2={x2} y2={y2} /> }
      const m = flaw.mark
      if (flaw.type === 'dent') return <circle key={flaw.id} className={cls} cx={m.x1} cy={m.y1} r="5" />
      return <line key={flaw.id} className={cls} x1={m.x1} y1={m.y1} x2={m.x2} y2={m.y2} />
    })}
  </svg>
}

// ---------- the grading table: both cards lying on one mat you can pan, zoom (to the cursor) and rotate ----------
const CARD_W = 390, CARD_H = 546, CARD_GAP = 70
const lineUp = () => ({ graded: { x: 0, y: 0 }, reference: { x: CARD_W + CARD_GAP, y: 0 } }) // exactly side by side
const clampZoom = value => Math.min(6, Math.max(0.25, value))

function GradingTable({ cards, side, tool, raking, guides, pins, onMark, onHint, debug, light, foilOnly, comparison, controls }) {
  const viewport = useRef(null)
  const holders = useRef({})
  const [bounds, setBounds] = useState({ width: 900, height: 620 })
  const [view, setView] = useState(null) // { x, y, zoom, rot } screen = pan + rotate(rot) * zoom * world
  const [positions, setPositions] = useState(lineUp)
  const [lens, setLens] = useState(null)
  const [ruler, setRuler] = useState(null)
  const [panning, setPanning] = useState(false)
  const drag = useRef(null)

  // fit both cards (side by side) into the table, centred, no rotation
  const fit = (size = bounds) => {
    const width = CARD_W * 2 + CARD_GAP, height = CARD_H + 40
    const zoom = clampZoom(Math.min(1.4, (size.width - 60) / width, (size.height - 60) / height))
    return { zoom, rot: 0, x: (size.width - width * zoom) / 2, y: (size.height - CARD_H * zoom) / 2 + 12 * zoom }
  }
  useLayoutEffect(() => {
    const element = viewport.current
    const measure = () => {
      const size = { width: element.clientWidth, height: element.clientHeight }
      setBounds(size)
      setView(current => current || fit(size))
    }
    measure()
    const observer = new ResizeObserver(measure)
    observer.observe(element)
    return () => observer.disconnect()
  }, [])
  const v = view || fit()
  const rad = v.rot * Math.PI / 180, cos = Math.cos(rad), sin = Math.sin(rad)
  const toWorld = (px, py) => { const qx = px - v.x, qy = py - v.y; return { x: (qx * cos + qy * sin) / v.zoom, y: (-qx * sin + qy * cos) / v.zoom } }
  // zoom / rotate about a point on screen (that spot stays put)
  const transformAbout = (px, py, nextZoom, nextRot) => setView(current => {
    const base = current || fit()
    const r0 = base.rot * Math.PI / 180, qx = px - base.x, qy = py - base.y
    const world = { x: (qx * Math.cos(r0) + qy * Math.sin(r0)) / base.zoom, y: (-qx * Math.sin(r0) + qy * Math.cos(r0)) / base.zoom }
    const zoom = clampZoom(nextZoom(base.zoom)), rot = nextRot(base.rot), r1 = rot * Math.PI / 180
    return { zoom, rot, x: px - (world.x * Math.cos(r1) - world.y * Math.sin(r1)) * zoom, y: py - (world.x * Math.sin(r1) + world.y * Math.cos(r1)) * zoom }
  })
  useEffect(() => {
    const element = viewport.current
    const wheel = event => {
      event.preventDefault()
      const box = element.getBoundingClientRect(), px = event.clientX - box.left, py = event.clientY - box.top
      if (event.shiftKey) transformAbout(px, py, z => z, r => r + (event.deltaY > 0 ? 5 : -5))
      else transformAbout(px, py, z => z * Math.exp(-event.deltaY * 0.0015), r => r)
    }
    element.addEventListener('wheel', wheel, { passive: false })
    return () => element.removeEventListener('wheel', wheel)
  })
  // the toolbar's view buttons (zoom about / rotate around the centre of the table)
  controls.current = {
    zoom: factor => transformAbout(bounds.width / 2, bounds.height / 2, z => z * factor, r => r),
    rotate: degrees => transformAbout(bounds.width / 2, bounds.height / 2, z => z, r => r + degrees),
    reset: () => { setView(fit()); setPositions(lineUp()) },
    lineUp: () => setPositions(lineUp()),
  }

  // pointer on screen -> the card under it (card-local px and % of the card), whatever the zoom / pan / rotation
  const locate = event => {
    const box = viewport.current.getBoundingClientRect()
    const sx = event.clientX - box.left, sy = event.clientY - box.top
    const world = toWorld(sx, sy)
    const holder = event.target.closest?.('[data-card-holder]')?.dataset.cardHolder
      || Object.keys(positions).find(id => { const p = positions[id]; return world.x >= p.x && world.x <= p.x + CARD_W && world.y >= p.y && world.y <= p.y + CARD_H })
    const point = { sx, sy, world, holder }
    if (!holder) return point
    const p = positions[holder], lx = world.x - p.x, ly = world.y - p.y
    let textPart
    for (const element of document.elementsFromPoint(event.clientX, event.clientY)) {
      if (!holders.current[holder]?.contains(element)) continue
      const hit = TEXT_TARGETS.find(([, selector]) => element.closest(selector))
      if (hit) { textPart = hit[0]; break }
    }
    return { ...point, lx, ly, x: lx / CARD_W * 100, y: ly / CARD_H * 100, cardWidth: CARD_W, inside: lx >= 0 && lx <= CARD_W && ly >= 0 && ly <= CARD_H, textPart }
  }

  const down = event => {
    const point = locate(event)
    const capture = () => { try { viewport.current.setPointerCapture(event.pointerId) } catch { /* gone */ } }
    // pan: right / middle drag anywhere, the hand tool, or dragging the empty table
    if (event.button === 1 || event.button === 2 || tool === 'hand' || (!point.holder && event.button === 0)) {
      event.preventDefault(); capture(); setPanning(true)
      drag.current = { kind: 'pan', sx: point.sx, sy: point.sy, x: v.x, y: v.y }
      return
    }
    if (event.button !== 0) return
    if (tool === 'move') {
      capture()
      drag.current = { kind: 'card', id: point.holder, wx: point.world.x, wy: point.world.y, start: positions[point.holder] }
    } else if (tool === 'ruler') {
      capture()
      drag.current = { kind: 'ruler' }
      setRuler({ holder: point.holder, a: point, b: point })
    } else if (tool === 'mark') {
      if (point.holder === 'graded') onMark(point)
      else onHint('Mark flaws on the card you are grading. The reference is for comparing and measuring.')
    }
  }
  const move = event => {
    const point = locate(event)
    const active = drag.current
    if (active?.kind === 'pan') { setView(current => ({ ...(current || v), x: active.x + point.sx - active.sx, y: active.y + point.sy - active.sy })); return }
    if (active?.kind === 'card') {
      const id = active.id
      setPositions(current => ({ ...current, [id]: { x: active.start.x + point.world.x - active.wx, y: active.start.y + point.world.y - active.wy } }))
      return
    }
    if (point.holder && light) light.emit({ x: Math.min(100, Math.max(0, point.x)), y: Math.min(100, Math.max(0, point.y)), active: point.inside })
    if (tool === 'magnifier') setLens(point.holder ? point : null)
    if (active?.kind === 'ruler') setRuler(current => {
      if (!current) return current
      const p = positions[current.holder], lx = point.world.x - p.x, ly = point.world.y - p.y
      // nearly level / upright drags snap straight (in the card's own axes), so border widths measure cleanly
      const dx = lx - current.a.lx, dy = ly - current.a.ly
      const b = Math.abs(dy) < Math.abs(dx) * 0.12 ? { lx, ly: current.a.ly } : Math.abs(dx) < Math.abs(dy) * 0.12 ? { lx: current.a.lx, ly } : { lx, ly }
      return { ...current, b }
    })
  }
  const up = () => { drag.current = null; setPanning(false) }

  const rulerMm = ruler && (() => {
    const per = CARD_MM / CARD_W
    const dx = (ruler.b.lx - ruler.a.lx) * per, dy = (ruler.b.ly - ruler.a.ly) * per
    return { length: Math.hypot(dx, dy), dx: Math.abs(dx), dy: Math.abs(dy) }
  })()
  const faceClass = `grading-face ${raking ? 'is-raking' : ''} ${!light && !foilOnly ? 'foil-light-off' : ''} ${foilOnly && side === 'front' ? 'foil-only' : ''}`
  const lensCard = lens?.holder && cards.find(entry => entry.id === lens.holder)

  return <div ref={viewport} className={`grading-table tool-${tool} ${panning ? 'is-panning' : ''}`}
    onPointerDown={down} onPointerMove={move} onPointerUp={up} onPointerCancel={up} onContextMenu={event => event.preventDefault()}
    onPointerLeave={() => { setLens(null); light?.emit({ x: 50, y: 50, active: false }) }}>
    <div className="grading-world" style={{ transform: `translate(${v.x}px, ${v.y}px) rotate(${v.rot}deg) scale(${v.zoom})` }}>
      {cards.map(entry => {
        const p = positions[entry.id]
        return <div key={entry.id} className="grading-holder" data-card-holder={entry.id} style={{ left: p.x, top: p.y }}>
          <div className="grading-holder-label"><strong>{entry.title}</strong><small>{entry.subtitle}</small></div>
          <div ref={element => { holders.current[entry.id] = element }} className={faceClass}>
            <Face card={entry.card} side={side} driver={light} comparison={comparison} />
            {raking && <i className="grading-raking-light" aria-hidden="true" />}
            {entry.id === 'graded' && debug && <div className="grading-debug-host"><DebugLayer {...debug} side={side} /></div>}
            {entry.id === 'reference' && guides && <MeasureGuides host={{ get current() { return holders.current.reference } }} side={side} deps={[entry.card]} layers={guides} />}
            {entry.id === 'graded' && <div className="grading-pins">
              {pins.filter(mark => mark.side === side).map(mark => <span key={mark.id} className={`grading-pin is-${mark.status} ${WHOLE_FACE.has(mark.type) ? 'is-face' : ''}`} style={{ left: `${mark.x}%`, top: `${mark.y}%` }} title={mark.label || flawLabel(mark.type)} />)}
            </div>}
            {ruler?.holder === entry.id && <svg className="grading-ruler" aria-hidden="true">
              <line x1={ruler.a.lx} y1={ruler.a.ly} x2={ruler.b.lx} y2={ruler.b.ly} />
              <circle cx={ruler.a.lx} cy={ruler.a.ly} r="3" /><circle cx={ruler.b.lx} cy={ruler.b.ly} r="3" />
              <text x={ruler.b.lx + 8} y={ruler.b.ly - 8}>{mm(rulerMm.length)}</text>
              <text x={ruler.b.lx + 8} y={ruler.b.ly + 8} className="sub">↔ {rulerMm.dx.toFixed(2)} · ↕ {rulerMm.dy.toFixed(2)}</text>
            </svg>}
          </div>
        </div>
      })}
    </div>
    {lensCard && tool === 'magnifier' && <div className={`grading-lens ${faceClass}`} style={{ left: Math.max(0, Math.min(bounds.width - LENS, lens.sx - LENS / 2)), top: Math.max(0, Math.min(bounds.height - LENS, lens.sy - LENS / 2)), width: LENS, height: LENS }} aria-hidden="true">
      <div className="grading-lens-content" style={{ transform: `translate(${LENS / 2 - lens.lx * LENS_ZOOM}px, ${LENS / 2 - lens.ly * LENS_ZOOM}px) scale(${LENS_ZOOM})` }}>
        <Face card={lensCard.card} side={side} driver={light} comparison={comparison} />
        {raking && <i className="grading-raking-light" />}
      </div>
    </div>}
    <div className="grading-table-zoom" aria-hidden="true">{Math.round(v.zoom * 100)}% · {((v.rot % 360) + 360) % 360}°</div>
  </div>
}

// The grading bench: the raw card next to a perfect reference print. Both can be measured (ruler, mm guides) and
// magnified; flaws are marked on the raw card and only confirmed when they are really there.
// FiveM supplies the server's actual session flaws when Config.Grading.Debug is enabled.
export default function GradingStation({ card, reference: referenceCard, session, onDone, onCancel, debug = false, debugFlaws }) {
  const [debugOn, setDebugOn] = useState(false)
  const realFlaws = debug ? (debugFlaws !== undefined ? asArray(debugFlaws) : listFlaws(card.condition, flawOptions(card))) : []
  const reference = cleanReference(referenceCard || card)
  const maxWrong = session.maxWrong ?? 6
  const [side, setSide] = useState('front')
  const [tool, setTool] = useState('mark')
  const [flawType, setFlawType] = useState('')
  const [raking, setRaking] = useState(false)
  const tableControls = useRef(null) // zoom / rotate / reset the table view (GradingTable fills it in)
  const [foilLight, setFoilLight] = useState(true)
  const [light] = useState(createLightDriver)
  // measurement layers on the reference print (expected numbers): each can be turned off so comparing stays clear
  const [guideLayers, setGuideLayers] = useState({ borders: false, parts: false, centre: false })
  const guides = guideLayers.borders || guideLayers.parts || guideLayers.centre ? guideLayers : null
  const [foilOnly, setFoilOnly] = useState(false)
  const hasFoil = flawOptions(card).hasFoil
  const [marks, setMarks] = useState([])
  const [wrong, setWrong] = useState(0)
  const [message, setMessage] = useState('')
  const [busy, setBusy] = useState(false)
  const [result, setResult] = useState(null)
  const found = marks.filter(mark => mark.status === 'confirmed')
  const foundIds = new Set(found.map(mark => mark.flawId))
  const outOfCalls = wrong >= maxWrong

  const placeMark = async point => {
    if (busy) return
    if (!flawType) { setMessage('First pick what is wrong in the list on the left, then click the card.'); return }
    if (outOfCalls) { setMessage('Too many wrong calls: submit your grade or cancel.'); return }
    if (!point.inside && !WHOLE_FACE.has(flawType)) { setMessage('Click the spot on the card itself.'); return }
    if (flawType === 'text' && !point.textPart) { setMessage('Click the specific text that is shifted, such as the name, HP or attack text.'); return }
    const id = crypto.randomUUID()
    setMarks(current => [...current, { id, side, type: flawType, x: Math.min(100, Math.max(0, point.x)), y: Math.min(100, Math.max(0, point.y)), status: 'checking' }])
    setBusy(true); setMessage('')
    try {
      const response = await session.mark({ type: flawType, side, textPart:point.textPart, x: Math.round(point.x * 10) / 10, y: Math.round(point.y * 10) / 10 })
      if (response.confirmed) {
        setMarks(current => current.map(mark => mark.id === id ? { ...mark, status: 'confirmed', flawId: response.flaw?.id, deduction: Number(response.flaw?.deduction) || 0, label: response.flaw?.label || flawLabel(flawType) } : mark))
        setMessage(`Confirmed: ${response.flaw?.label || flawLabel(flawType)}`)
      } else {
        setWrong(response.wrong ?? wrong + 1)
        setMarks(current => current.map(mark => mark.id === id ? { ...mark, status: 'rejected', label: `No ${flawLabel(flawType).toLowerCase()} (${side})` } : mark))
        setMessage(WHOLE_FACE.has(flawType) ? `The ${side} is within tolerance for "${flawLabel(flawType)}".` : `Nothing like "${flawLabel(flawType)}" there.`)
      }
    } catch (error) {
      setMarks(current => current.filter(mark => mark.id !== id))
      setMessage(error?.message || String(error))
    } finally { setBusy(false) }
  }

  // Submitting: the confirmed calls suggest a grade; the grader picks the final one within ±gradeAdjust of it
  const gradeAdjust = Number(session.gradeAdjust ?? DEFAULT_GRADE_ADJUST)
  const suggested = gradeFromFlaws(found)
  const [finalizing, setFinalizing] = useState(false)
  const [chosenGrade, setChosenGrade] = useState(null)
  const submit = async () => {
    setBusy(true); setMessage('')
    try { setResult(await session.submit({ grade: allowedGrade(chosenGrade ?? suggested, suggested, gradeAdjust) })) }
    catch (error) { setMessage(error?.message || String(error)); setFinalizing(false) }
    finally { setBusy(false) }
  }
  const cancel = async () => { try { await session.cancel() } catch { /* ended anyway */ } onCancel() }
  const active = FLAW_TYPES.find(entry => entry.value === flawType)
  const status = message || (tool === 'hand' ? 'Drag to move around the table. Wheel to zoom, Shift + wheel to rotate.'
    : tool === 'move' ? 'Drag a card to move it on the table. "Line up cards" puts them back side by side.'
    : tool === 'ruler' ?'Drag across a border or between a printed part and the edge. Level / upright drags snap straight. Compare with the reference numbers.'
    : tool === 'magnifier' ? 'Move the loupe over corners, edges and the surface (try it with the raking light).'
    : active ? `Marking "${active.label}" — ${WHOLE_FACE.has(active.value) ? `click anywhere on the ${side} of the card` : 'click exactly where it is'}.` : 'Pick what is wrong in the list on the left, then click the card.')

  if (result) return <div className="grading-station grading-result" role="dialog" aria-label="Grading result">
    <div className="grading-result-card"><TradingCard card={result.card} size="viewer" interactive={false} /></div>
    <div className="grading-result-copy">
      <span className="eyebrow">Graded and slabbed</span>
      <h2>{result.grade} · {gradeName(result.grade)}</h2>
      <p>You marked {found.length} issue{found.length === 1 ? '' : 's'}{result.grade !== suggested ? `, which suggested ${suggested}` : ''}. Anyone can look up cert #{result.card?.graded?.cert} to see your calls.</p>
      <p className="muted">Cert #{result.card?.graded?.cert}</p>
      <button className="primary" onClick={() => onDone(result.card, result.record)}>Done</button>
    </div>
  </div>

  const flawButton = entry => <button key={entry.value} className={flawType === entry.value ? 'active' : ''} title={entry.hint} onClick={() => { setFlawType(entry.value); setTool('mark'); setMessage('') }}>{entry.label}</button>

  return <div className="grading-station" role="dialog" aria-label="Card grading">
    <header className="grading-head">
      <div><span className="eyebrow">Grading bench</span><h2>{card.title} <small>{card.variantName}</small></h2></div>
      <div className="grading-counters">
        <span className="ok">{found.length} confirmed</span>
        <span className={outOfCalls ? 'bad' : ''}>{wrong}/{maxWrong} wrong calls</span>
      </div>
      <div className="grading-head-actions">
        <button className="ghost" onClick={cancel} disabled={busy}>Cancel</button>
        <button className="primary" onClick={() => { setChosenGrade(suggested); setFinalizing(true) }} disabled={busy}>Submit grade</button>
      </div>
    </header>

    {finalizing && <div className="grading-finalize" role="dialog" aria-label="Choose the final grade">
      <div className="grading-finalize-box">
        <strong>Final grade</strong>
        <p>Your {found.length} confirmed call{found.length === 1 ? '' : 's'} suggest <b>{suggested} {gradeName(suggested)}</b>. You can put a different grade on the slab, up to {gradeAdjust} either way; the record keeps your calls, so others can check it.</p>
        <div className="grading-grade-choices">
          {gradeChoices(suggested, gradeAdjust).map(grade => <button key={grade} className={grade === chosenGrade ? 'active' : ''} onClick={() => setChosenGrade(grade)}>
            <b>{grade}</b><small>{gradeName(grade)}</small>{grade === suggested && <em>suggested</em>}
          </button>)}
        </div>
        <div className="grading-head-actions">
          <button className="ghost" onClick={() => setFinalizing(false)} disabled={busy}>Keep grading</button>
          <button className="primary" onClick={submit} disabled={busy}>{busy ? 'Slabbing…' : `Slab it at ${chosenGrade ?? suggested}`}</button>
        </div>
      </div>
    </div>}

    <div className="grading-layout">
      <aside className="grading-tools">
        <div className="grading-tool-group">
          <strong>Tools</strong>
          <div className="grading-tool-row">
            {[['mark', 'Mark flaw'], ['magnifier', 'Loupe'], ['ruler', 'Ruler']].map(([value, label]) => <button key={value} className={tool === value ? 'active' : ''} onClick={() => setTool(value)}>{label}</button>)}
          </div>
          <div className="grading-tool-row">
            {[['hand', 'Pan view'], ['move', 'Move cards']].map(([value, label]) => <button key={value} className={tool === value ? 'active' : ''} onClick={() => setTool(value)}>{label}</button>)}
          </div>
          <div className="grading-tool-row">
            <button className={raking ? 'active' : ''} onClick={() => setRaking(!raking)}>Raking light</button>
            <button onClick={() => setSide(side === 'front' ? 'back' : 'front')}>Flip both to {side === 'front' ? 'back' : 'front'}</button>
          </div>
          <div className="grading-tool-row">
            <button className={foilLight ? 'active' : ''} onClick={() => { setFoilLight(!foilLight); light.emit({ x: 50, y: 50, active: false }) }} title="Enable foil and mask lighting on both cards; turn off to inspect the plain print and wear">Foil light (hover)</button>
            <button className={foilOnly ? 'active' : ''} disabled={!hasFoil} onClick={() => setFoilOnly(!foilOnly)}
              title={hasFoil ? 'Hide the print on both cards and show only the holo pattern, so a shifted or recoloured foil stands out' : 'This print has no foil / holo layer'}>Foil only</button>
          </div>
          <small className="muted">Reference measurements (mm)</small>
          <div className="grading-tool-row">
            {[['borders', 'Borders'], ['parts', 'Print layout'], ['centre', 'Centre lines']].map(([key, label]) =>
              <button key={key} className={guideLayers[key] ? 'active' : ''} onClick={() => setGuideLayers(current => ({ ...current, [key]: !current[key] }))}>{label}</button>)}
          </div>
          <small className="muted">View · wheel zooms to the cursor, Shift + wheel rotates, drag the table (or right-drag) to pan</small>
          <div className="grading-tool-row">
            <button onClick={() => tableControls.current?.zoom(1 / 1.25)} title="Zoom out">−</button>
            <button onClick={() => tableControls.current?.zoom(1.25)} title="Zoom in">+</button>
            <button onClick={() => tableControls.current?.rotate(-15)} title="Rotate the view left">⟲</button>
            <button onClick={() => tableControls.current?.rotate(15)} title="Rotate the view right">⟳</button>
          </div>
          <div className="grading-tool-row">
            <button onClick={() => tableControls.current?.lineUp()} title="Put both cards back side by side">Line up cards</button>
            <button onClick={() => tableControls.current?.reset()}>Reset view</button>
          </div>
        </div>
        <div className="grading-tool-group">
          <strong>What's wrong?</strong>
          <small className="muted">The whole side — click anywhere on it</small>
          <div className="grading-flaw-list">{FACE_FLAWS.map(flawButton)}</div>
          <small className="muted">At a spot — click right on it</small>
          <div className="grading-flaw-list">{SPOT_FLAWS.map(flawButton)}</div>
          {active && <small className="grading-hint">{active.hint}</small>}
        </div>
        <div className="grading-tool-group grading-marks">
          <strong>Your calls</strong>
          {!marks.length && <small className="muted">Nothing marked yet. Check the borders (off-centre), where the art and text sit against the reference, then corners, edges and the surface on both sides.</small>}
          {marks.map(mark => <div key={mark.id} className={`grading-call is-${mark.status}`}>{mark.status === 'confirmed' ? '✓' : mark.status === 'rejected' ? '✕' : '…'} {mark.label || flawLabel(mark.type)} <small>{mark.side}</small></div>)}
        </div>
        {debug && <div className="grading-tool-group grading-debug-panel">
          <strong>Grading debugger</strong>
          <button className={debugOn ? 'active' : ''} onClick={() => setDebugOn(!debugOn)}>{debugOn ? 'Hide' : 'Show'} where the flaws are</button>
          <small className="muted">{realFlaws.length} real flaw{realFlaws.length === 1 ? '' : 's'} · true grade {gradeFromFound(realFlaws, realFlaws.map(f => f.id))} {gradeName(gradeFromFound(realFlaws, realFlaws.map(f => f.id)))}</small>
          {debugOn && <>
            <small className="muted">Visible shifts inside tolerance do not count as print errors. Values must exceed the limit.</small>
            <table className="grading-tolerances"><thead><tr><th>Print layer</th><th>Offset</th><th>Limit</th></tr></thead><tbody>
              {[
                ['Front centering', Math.max(...[0, 1].map(i => Math.abs(card.condition?.centering?.front?.[i] || 0))), LIMITS.centeringFront],
                ['Back centering', Math.max(...[0, 1].map(i => Math.abs(card.condition?.centering?.back?.[i] || 0))), LIMITS.centeringBack],
                ...['art', 'foil', 'mask'].filter(key => key !== 'foil' && key !== 'mask' || flawOptions(card)[key === 'foil' ? 'hasFoil' : 'hasMask']).map(key => [flawLabel(key), Math.hypot(...[0, 1].map(i => card.condition?.[key]?.[i] || 0)), LIMITS[key]]),
                ...(Array.isArray(card.condition?.text) ? ['legacy layer'] : TEXT_SECTIONS).map(part=>[`Text (${part})`,Math.hypot(...textOffset(card.condition,part)),LIMITS.text]),
                ...(hasFoil ? [['Foil hue (°)', Math.abs(card.condition?.foil?.[2] || 0), LIMITS.foilHue]] : []),
              ].map(([label, value, limit]) => <tr key={label}><td>{label}</td><td>{value.toFixed(3)}</td><td>{limit} · {value > limit ? 'Error' : 'Within'}</td></tr>)}
            </tbody></table>
            <small className="muted">Centering uses border imbalance; layer offsets are percentages; foil hue is degrees.</small>
            <details><summary>Raw copy condition</summary><pre>{JSON.stringify(card.condition, null, 2)}</pre></details>
          </>}
          {debugOn && realFlaws.map(flaw => {
            const done = foundIds.has(flaw.id)
            return <button key={flaw.id} className={`grading-debug-item ${done ? 'found' : ''}`} title={FLAW_TYPES.find(t => t.value === flaw.type)?.hint}
              onClick={() => { setSide(flaw.side); setFlawType(flaw.type); setTool('mark'); setMessage(`Hint: ${flaw.label} — −${flaw.deduction}. ${WHOLE_FACE.has(flaw.type) ? 'Click anywhere on that side.' : 'Click inside the highlighted spot.'}`) }}>
              {done ? '✓' : '○'} {flaw.label} <small>−{flaw.deduction}</small>
            </button>
          })}
        </div>}
      </aside>

      <section className="grading-bench">
        <GradingTable controls={tableControls} side={side} tool={tool} raking={raking} guides={guides} pins={marks} onMark={placeMark} onHint={setMessage}
          debug={debug && debugOn ? { flaws: realFlaws, found: foundIds } : null} light={foilLight ? light : null} comparison={light.effectFrames} foilOnly={foilOnly}
          cards={[
            { id: 'graded', title: 'Card being graded', subtitle: `${side} · mark flaws here`, card },
            { id: 'reference', title: 'Reference print', subtitle: 'how it should look · measure it too', card: reference },
          ]} />
        <div className="grading-status" role="status">{status}</div>
      </section>
    </div>
  </div>
}

// the perfect print to compare against: no copy data at all, whatever it was built from
export const cleanReference = card => card ? { ...card, condition: null, protection: 'none', graded: null, manualPrint: false } : null
