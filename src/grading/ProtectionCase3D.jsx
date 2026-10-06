import { SlabLabel } from './ProtectionShell.jsx'

// A real 3D case around a card in the rotating inspector: front and back panes plus clear side walls, sized past
// the card (the card floats inside), so turning a sleeved / toploadered / slabbed card shows plastic, not paper.
// Sizes are px at the inspector's card width (~390px); depth is the case's thickness.
export const CASE_SIZES = {
  sleeve: { x: 6, top: 12, bottom: 6, depth: 4, radius: 28 },
  toploader: { x: 15, top: 24, bottom: 15, depth: 14, radius: 16 },
  slab: { x: 20, top: 110, bottom: 20, depth: 34, radius: 18 },
}

export const caseKindOf = card => card?.graded ? 'slab' : (card?.protection && card.protection !== 'none' ? card.protection : null)

export default function ProtectionCase3D({ card }) {
  const kind = caseKindOf(card)
  const size = kind && CASE_SIZES[kind]
  if (!size) return null
  const style = { '--case-x': `${size.x}px`, '--case-t': `${size.top}px`, '--case-b': `${size.bottom}px`, '--case-z': `${size.depth}px`, '--case-r': `${size.radius}px`, '--shell-k': 1 }
  return <div className={`case3d case3d--${kind}`} style={style} aria-hidden="true">
    <div className="case3d-face case3d-front">
      {kind === 'slab' && <SlabLabel card={card} side="front" />}
      <i className="case3d-window" />
    </div>
    <div className="case3d-face case3d-back">
      {kind === 'slab' && <SlabLabel card={card} side="back" />}
      <i className="case3d-window" />
    </div>
    <i className="case3d-side case3d-left" /><i className="case3d-side case3d-right" />
    <i className="case3d-side case3d-top" /><i className="case3d-side case3d-bottom" />
  </div>
}
