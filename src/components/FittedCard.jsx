import React from 'react'
import TradingCard from './TradingCard'

// A card at "medium" size, as the binder and the card case draw them
export const CARD_W = 230, CARD_H = 322

// How far each case reaches past a medium card (px left/right, top, bottom; grading.css .card-protection-- at
// --shell-k .68).
const SHELL = { none: [0, 0, 0], sleeve: [6, 12, 6], toploader: [13, 22, 13], slab: [18, 104, 18] }
export const shellOf = card => (card?.graded ? 'slab' : card?.protection) || 'none'
const shell = kind => (SHELL[kind] || SHELL.none).map(value => value * 0.68)

// The scale that fits a card in a `reserve` case (default: its own) inside width x height. Pass one reserve for
// every card of a view and they are all drawn the same size, each case simply reaching round its own card.
export function fitScale(width, height, reserve = 'none') {
  const [px, pt, pb] = shell(reserve)
  return Math.min(width / (CARD_W + px * 2), height / (CARD_H + pt + pb))
}

// A card drawn with its protection inside a width x height box.
//   reserve: the case the box has room for (all cards of a view use one, so they are the same size)
//   align 'top': the card's own case starts at the top of the box (upright cards in the card case)
//   align 'own': the card and its own case are centred in the box (cards lying in foam cut-outs)
export default function FittedCard({ card, width, height, align = 'center', reserve }) {
  const own = shellOf(card)
  const room = reserve || own
  const s = fitScale(width, height, room)
  const [, ptRoom, pbRoom] = shell(room)
  const [, ptOwn, pbOwn] = shell(own)
  const top = align === 'top' ? ptOwn * s
    : align === 'own' ? (height - (CARD_H + ptOwn + pbOwn) * s) / 2 + ptOwn * s
    : (height - (CARD_H + ptRoom + pbRoom) * s) / 2 + ptRoom * s
  return (
    <span className="bd-card-scale" style={{ left: (width - CARD_W * s) / 2, top, transform: `scale(${s})` }}>
      <TradingCard card={card} size="medium" interactive={false} />
    </span>
  )
}
