import { memo, useId } from 'react'
import { asArray, LIMITS } from './condition.js'

// Wear and damage drawn over one face of a card (front or back), from its condition. The SVG is stretched over the
// face (100 x 100 units), so strokes use non-scaling widths. Scratches are faint until the grading station's
// raking light (.is-raking) brings them out.
// The mathematical corner falls outside the rounded card's clipping path.
// Keep whitening on the visible stock, just inside the rounded edge.
const CORNERS = [[3.5, 3.5], [96.5, 3.5], [96.5, 96.5], [3.5, 96.5]]
const EDGE_LINES = [[0, 0, 100, 0], [100, 0, 100, 100], [100, 100, 0, 100], [0, 100, 0, 0]]

// cheap repeatable wobble so a crease isn't a ruler-straight line
const wobble = (mark, steps = 9) => {
  const points = []
  let seed = [...String(mark.id || '')].reduce((sum, char) => sum + char.charCodeAt(0), 7)
  const next = () => { seed = (seed * 9301 + 49297) % 233280; return seed / 233280 - 0.5 }
  const dx = mark.x2 - mark.x1, dy = mark.y2 - mark.y1, length = Math.hypot(dx, dy) || 1
  const nx = -dy / length, ny = dx / length
  for (let i = 0; i <= steps; i++) {
    const t = i / steps, w = i === 0 || i === steps ? 0 : next() * 1.1
    points.push(`${(mark.x1 + dx * t + nx * w).toFixed(2)},${(mark.y1 + dy * t + ny * w).toFixed(2)}`)
  }
  return points.join(' ')
}

function Mark({ mark, dentId }) {
  const s = Math.min(1, Math.max(0, Number(mark.s) || 0.3))
  if (mark.type === 'scratch') return <g className="cond-scratch">
    <line x1={mark.x1} y1={mark.y1} x2={mark.x2} y2={mark.y2} stroke="#fff" strokeOpacity={0.18 + s * 0.25} strokeWidth={0.6 + s * 0.6} vectorEffect="non-scaling-stroke" strokeLinecap="round" />
  </g>
  if (mark.type === 'dent') return <g className="cond-dent">
    <circle cx={mark.x1} cy={mark.y1} r={1.4 + s * 1.6} fill={`url(#${dentId})`} />
  </g>
  if (mark.type === 'crease') {
    const points = wobble(mark)
    return <g className="cond-crease">
      <polyline points={points} fill="none" stroke="#000" strokeOpacity={0.35 + s * 0.3} strokeWidth={1.6 + s * 1.4} vectorEffect="non-scaling-stroke" transform="translate(0.25 0.35)" />
      <polyline points={points} fill="none" stroke="#fff" strokeOpacity={0.45 + s * 0.35} strokeWidth={0.9 + s * 0.8} vectorEffect="non-scaling-stroke" />
      <polyline points={points} fill="none" stroke="#f4efe4" strokeOpacity={0.5} strokeWidth={0.6} strokeDasharray="1.2 2.6" vectorEffect="non-scaling-stroke" transform="translate(-0.2 -0.2)" />
    </g>
  }
  if (mark.type === 'bend') return <g className="cond-bend">
    <line x1={mark.x1} y1={mark.y1} x2={mark.x2} y2={mark.y2} stroke="#fff" strokeOpacity={0.1 + s * 0.12} strokeWidth={10 + s * 10} vectorEffect="non-scaling-stroke" />
    <line x1={mark.x1} y1={mark.y1} x2={mark.x2} y2={mark.y2} stroke="#000" strokeOpacity={0.12 + s * 0.12} strokeWidth={4 + s * 5} vectorEffect="non-scaling-stroke" transform="translate(0.8 1)" />
  </g>
  if (mark.type === 'tear') {
    const dx = mark.x2 - mark.x1, dy = mark.y2 - mark.y1, length = Math.hypot(dx, dy) || 1
    const nx = -dy / length * (1.6 + s * 2), ny = dx / length * (1.6 + s * 2)
    const tip = `${mark.x2},${mark.y2}`
    const path = `M${mark.x1 - nx},${mark.y1 - ny} L${(mark.x1 + mark.x2) / 2 - nx * 0.4},${(mark.y1 + mark.y2) / 2 - ny * 0.4 + 0.6} L${tip} L${(mark.x1 + mark.x2) / 2 + nx * 0.5},${(mark.y1 + mark.y2) / 2 + ny * 0.5 - 0.5} L${mark.x1 + nx},${mark.y1 + ny} Z`
    return <g className="cond-tear">
      <path d={path} fill="#efe7d7" stroke="#2a2420" strokeOpacity="0.7" strokeWidth="0.9" vectorEffect="non-scaling-stroke" />
      <path d={path} fill="none" stroke="#fff" strokeOpacity="0.5" strokeWidth="0.5" strokeDasharray="0.8 1.4" vectorEffect="non-scaling-stroke" />
    </g>
  }
  const seed = [...String(mark.id || '')].reduce((sum, char) => sum + char.charCodeAt(0), 0)
  // roller marks: a band of faint parallel pressed ridges along the feed direction (stronger under the raking light)
  if (mark.type === 'roller') {
    const dx = mark.x2 - mark.x1, dy = mark.y2 - mark.y1, length = Math.hypot(dx, dy) || 1
    const nx = -dy / length, ny = dx / length, count = 4 + (seed % 3)
    return <g className="cond-roller">
      {Array.from({ length: count }, (_, i) => {
        const o = (i - (count - 1) / 2) * (1.1 + s * 0.6)
        return <g key={i} transform={`translate(${nx * o} ${ny * o})`}>
          <line x1={mark.x1} y1={mark.y1} x2={mark.x2} y2={mark.y2} stroke="#000" strokeOpacity={0.1 + s * 0.12} strokeWidth="1.4" vectorEffect="non-scaling-stroke" transform="translate(0.15 0.25)" />
          <line x1={mark.x1} y1={mark.y1} x2={mark.x2} y2={mark.y2} stroke="#fff" strokeOpacity={0.08 + s * 0.1} strokeWidth="0.8" vectorEffect="non-scaling-stroke" />
        </g>
      })}
    </g>
  }
  // print line: one dead-straight streak of a single ink
  if (mark.type === 'printline') return <g className="cond-printline">
    <line x1={mark.x1} y1={mark.y1} x2={mark.x2} y2={mark.y2} stroke={['#00b7ff', '#ff2fa8', '#ffe34d', '#1a1a1a'][seed % 4]} strokeOpacity={0.35 + s * 0.3} strokeWidth={0.7 + s * 0.6} vectorEffect="non-scaling-stroke" />
  </g>
  // ink spot (a speck of ink) or fisheye (a little ring where ink didn't take); the face is 5:7, so ry is scaled to stay round
  if (mark.type === 'inkspot') {
    const r = 0.5 + s * 0.6, fisheye = seed % 2 === 0
    return <g className="cond-inkspot">
      {fisheye
        ? <ellipse cx={mark.x1} cy={mark.y1} rx={r} ry={r * 0.714} fill="#fffaf0" fillOpacity="0.55" stroke="#000" strokeOpacity="0.35" strokeWidth="0.6" vectorEffect="non-scaling-stroke" />
        : <ellipse cx={mark.x1} cy={mark.y1} rx={r} ry={r * 0.714} fill={['#1b1030', '#0d4f8a', '#8a0d4f'][seed % 3]} fillOpacity="0.8" />}
    </g>
  }
  // stain: a faint discoloured blotch
  if (mark.type === 'stain') {
    const r = 3 + s * 4
    return <g className="cond-stain" fill="#c9a14a" fillOpacity={0.1 + s * 0.08}>
      <ellipse cx={mark.x1} cy={mark.y1} rx={r} ry={r * 0.6} />
      <ellipse cx={mark.x1 + r * 0.4} cy={mark.y1 - r * 0.2} rx={r * 0.6} ry={r * 0.45} />
      <ellipse cx={mark.x1 - r * 0.35} cy={mark.y1 + r * 0.25} rx={r * 0.5} ry={r * 0.35} />
    </g>
  }
  return null
}

function ConditionOverlay({ condition, side = 'front' }) {
  const id = useId().replace(/:/g, '')
  const cornerId = `cond-corner-${id}`, dentId = `cond-dent-${id}`
  if (!condition) return null
  const corners = asArray(condition.corners?.[side])
  const edges = asArray(condition.edges?.[side])
  const marks = asArray(condition.marks).filter(mark => (mark.side || 'front') === side)
  // wear below this is invisible handling noise: drawing it only speckles the edges of near-perfect cards
  const VISIBLE = LIMITS.wear
  if (!marks.length && !corners.some(v => v > VISIBLE) && !edges.some(v => v > VISIBLE)) return null
  return <svg className={`card-condition card-condition--${side}`} viewBox="0 0 100 100" preserveAspectRatio="none" aria-hidden="true">
    <defs>
      <radialGradient id={cornerId}><stop offset="0" stopColor="#fffaf0" stopOpacity="1" /><stop offset="0.55" stopColor="#fffaf0" stopOpacity="0.65" /><stop offset="1" stopColor="#fffaf0" stopOpacity="0" /></radialGradient>
      <radialGradient id={dentId}><stop offset="0" stopColor="#000" stopOpacity="0.35" /><stop offset="0.6" stopColor="#000" stopOpacity="0.12" /><stop offset="0.85" stopColor="#fff" stopOpacity="0.28" /><stop offset="1" stopColor="#fff" stopOpacity="0" /></radialGradient>
    </defs>
    {corners.map((v, index) => v > VISIBLE && <ellipse key={`c${index}`} cx={CORNERS[index][0]} cy={CORNERS[index][1]} rx={2 + v * 7} ry={(2 + v * 7) * 0.72} fill={`url(#${cornerId})`} opacity={0.55 + v * 0.45} />)}
    {edges.map((v, index) => v > VISIBLE && <line key={`e${index}`} x1={EDGE_LINES[index][0]} y1={EDGE_LINES[index][1]} x2={EDGE_LINES[index][2]} y2={EDGE_LINES[index][3]}
      stroke="#fffaf0" strokeOpacity={0.25 + v * 0.7} strokeWidth={1 + v * 3} strokeDasharray={`${0.6 + v * 3} ${4 - v * 2.5} ${0.4 + v} ${6 - v * 3}`} vectorEffect="non-scaling-stroke" />)}
    {marks.map(mark => <Mark key={mark.id} mark={mark} dentId={dentId} />)}
  </svg>
}

export default memo(ConditionOverlay)
