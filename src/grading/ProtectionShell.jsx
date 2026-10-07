import { memo, useSyncExternalStore } from 'react'
import { gradeName } from './condition.js'
import { collectorNumber, setNumbersVersion, subscribeSetNumbers } from '../utils/setNumbers.js'

// Clear plastic around a card: a penny sleeve, a rigid toploader, or a graded slab with its label (front only).
// Drawn as a sibling over the card inside .card-stage (see grading.css), so it never clips the card itself.
function Barcode({ value }) {
  const bars = []
  let x = 0
  for (const digit of String(value || '0').padEnd(8, '0')) {
    const n = Number(digit) || 0
    for (const width of [1 + (n % 3), 1 + ((n + 1) % 2), 1 + ((n + 2) % 3)]) { bars.push(<rect key={bars.length} x={x} y="0" width={width} height="10" />); x += width + 1 }
  }
  return <svg className="slab-barcode" viewBox={`0 0 ${x} 10`} preserveAspectRatio="none" aria-hidden="true">{bars}</svg>
}

// The slab's label: grade, card and cert on the front; grader on the back (also used by the 3D case)
export function SlabLabel({ card, side = 'front' }) {
  useSyncExternalStore(subscribeSetNumbers, setNumbersVersion)
  const graded = card?.graded
  if (side === 'back') return <div className="slab-label slab-label--back"><span>META COMICS GRADING</span><span>{graded?.grader ? `Graded by ${graded.grader}` : ''}</span><span>{graded?.cert}</span></div>
  if (!graded) return null
  const numbered = collectorNumber(card)
  return <div className="slab-label">
      <div className="slab-label-left">
        <strong>{(card.setName || 'META COMICS').toUpperCase().slice(0, 22)}</strong>
        <span>{(card.title || '').toUpperCase().slice(0, 24)}</span>
        <span>{(card.variantName || '').toUpperCase().slice(0, 24)}</span>
        <Barcode value={graded.cert} />
      </div>
      <div className="slab-label-right">
        <span>{numbered ? `#${numbered.number}` : ''}</span>
        <strong>{gradeName(graded.grade)}</strong>
        <b>{graded.grade}</b>
        <span>{graded.cert}</span>
      </div>
    </div>
}

function ProtectionShell({ card, side = 'front' }) {
  const graded = card?.graded
  const kind = graded ? 'slab' : card?.protection
  if (!kind || kind === 'none') return null
  if (kind !== 'slab') return <div className={`card-protection card-protection--${kind}`} aria-hidden="true"><i /></div>
  return <div className="card-protection card-protection--slab" aria-label={graded ? `Graded ${graded.grade}` : 'Slab'}>
    <SlabLabel card={card} side={side} />
    <i className="slab-window" />
  </div>
}

export default memo(ProtectionShell)
