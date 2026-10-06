import React, { useEffect, useMemo, useRef, useState } from 'react'
import FittedCard, { CARD_W, CARD_H, shellOf } from './FittedCard'
import CardViewer from './CardViewer'
import { bridge, isFiveM } from '../runtime'
import '../styles/binder.css'
import '../styles/cardCase.css'

const DRAG_PX = 6
const PAGE_HOVER_MS = 520
// a slab's outer size at scale 1 (every card in the case is drawn at the scale that fits a slab, so all match)
const SLAB_W = CARD_W + 2 * 18 * 0.68, SLAB_H = CARD_H + (104 + 18) * 0.68

// The three sample layouts (pick one in the header; Config.CardCase.Style sets the default in FiveM)
export const CASE_STYLES = [
  { id: 'compartments', label: 'Compartments', help: 'Cards stand upright in compartments. Hover one to lift it.' },
  { id: 'foam', label: 'Foam display', help: 'Cards lie flat in foam cut-outs. Use the arrows for more.' },
  { id: 'topdown', label: 'Top-down rows', help: 'Looking down on the slab tops. Hover one to see it on the right.' },
]
const styleIds = CASE_STYLES.map(style => style.id)

/**
 * Card case (slab case): an aluminium carry case, in one of three sample layouts.
 *   holder = { kind: 'case', style?, label, slots, pockets: [{ slot, card }], hand: [{ slot, card }] }
 * Slots are grouped (a compartment, a row, or a page of cut-outs). Click a card to see it large.
 * Drag: case -> group (move to a free spot, or onto a card to swap), hand -> group (put in), case -> hand (take
 * out). In FiveM the server makes every move (the same calls as the binder).
 */
export default function CardCaseView({ binder: holder, onClose }) {
  const [size, setSize] = useState(() => ({ w: window.innerWidth, h: window.innerHeight }))
  const [pockets, setPockets] = useState(() => holder?.pockets || [])
  const [hand, setHand] = useState(() => holder?.hand || [])
  const [showHand, setShowHand] = useState(() => { try { return localStorage.getItem('meta-comic-case-hand') !== '0' } catch { return true } })
  const [style, setStyle] = useState(() => {
    try { const saved = localStorage.getItem('meta-comic-case-style'); if (styleIds.includes(saved)) return saved } catch { /* private window */ }
    return styleIds.includes(holder?.style) ? holder.style : 'compartments'
  })
  const [page, setPage] = useState(0)
  const [preview, setPreview] = useState(null) // top-down: the hovered card
  const [viewer, setViewer] = useState(null)
  const [drag, setDrag] = useState(null) // { from: 'case' | 'hand', slot, card, x, y, target }
  const [message, setMessage] = useState('')
  const [moving, setMoving] = useState(false)
  const session = useRef(null)
  const handRef = useRef(null)
  const pageTimer = useRef({ dir: 0, timer: 0 })

  useEffect(() => { setPockets(holder?.pockets || []); setHand(holder?.hand || []) }, [holder])
  useEffect(() => {
    const onResize = () => setSize({ w: window.innerWidth, h: window.innerHeight })
    window.addEventListener('resize', onResize)
    return () => window.removeEventListener('resize', onResize)
  }, [])
  useEffect(() => () => window.clearTimeout(pageTimer.current.timer), [])

  const bySlot = useMemo(() => {
    const map = new Map()
    for (const pocket of pockets) if (pocket?.card) map.set(Number(pocket.slot), pocket.card)
    return map
  }, [pockets])

  const handAvailable = Array.isArray(holder?.hand)
  const handShown = handAvailable && showHand
  const slots = Math.max(Number(holder?.slots) || 0, ...bySlot.keys(), 8)
  const busy = moving

  // ---- shared sizes
  const handCardH = Math.round(Math.min(size.h * 0.26, 220))
  const handCardW = Math.round(handCardH * CARD_W / CARD_H)
  const handH = handShown ? Math.round(handCardH * 0.68) : 0
  const caseW = Math.min(size.w * 0.94, 1500)
  const areaH = Math.max(300, size.h - handH - 100) // the case, lid included

  // ---- layout per style: groups of slots (drop targets) and their geometry
  const layout = useMemo(() => {
    if (style === 'foam') {
      // flat-open briefcase: lid strip on top, the base with 2 rows of slab-sized cut-outs, paged
      const lidH = Math.round(areaH * 0.13)
      const baseH = areaH - lidH - 40
      const pad = 22, gap = 18, rows = 2
      let cutH = (baseH - pad * 2 - gap) / rows
      let cutW = cutH * SLAB_W / SLAB_H
      const cols = Math.max(3, Math.min(8, Math.floor((caseW - pad * 2 + gap) / (cutW + gap))))
      cutW = Math.min(cutW, (caseW - pad * 2 - gap * (cols - 1)) / cols)
      cutH = cutW * SLAB_H / SLAB_W
      const perPage = cols * rows
      const pages = Math.max(1, Math.ceil(slots / perPage))
      const groups = Array.from({ length: pages }, (_, p) => Array.from({ length: perPage }, (_, i) => p * perPage + i + 1).filter(slot => slot <= slots))
      return { lidH, pad, gap, rows, cols, cutW, cutH, pages, groups }
    }
    const COLS = 4, ROWS = 2
    const per = Math.ceil(slots / (COLS * ROWS))
    const groups = Array.from({ length: COLS * ROWS }, (_, c) => Array.from({ length: per }, (_, i) => c * per + i + 1).filter(slot => slot <= slots))
    if (style === 'topdown') {
      // straight down on the case: thin lid strip, 2 x 4 rows of slab tops, and a preview panel on the right
      const previewW = Math.min(caseW * 0.3, 380)
      const bodyW = caseW - previewW - 20
      const lidH = 26
      const pad = 16, gap = 12
      const cw = (bodyW - pad * 2 - gap * (COLS - 1)) / COLS
      const ch = (areaH - lidH - 40 - pad * 2 - gap * (ROWS - 1)) / ROWS
      return { COLS, ROWS, per, groups, previewW, bodyW, lidH, pad, gap, cw, ch, edge: ch / per }
    }
    // compartments: foam lid strip with hinges, the body below, cards upright showing their tops
    const lidH = Math.round(Math.min(areaH * 0.1, 96))
    const frontH = 30 // room for the handle under the body
    const pad = 18, gap = 14
    const cw = (caseW - pad * 2 - gap * (COLS - 1)) / COLS
    const ch = (areaH - lidH - frontH - pad * 2 - gap * (ROWS - 1)) / ROWS
    const FRONT = 0.42 // how much of the front card shows above the compartment's front wall
    const s = Math.min((cw * 0.88) / SLAB_W, ch / ((0.15 * Math.max(0, per - 1) + FRONT) * SLAB_H))
    const boxW = SLAB_W * s, boxH = SLAB_H * s
    const strip = per > 1 ? Math.min(boxH * 0.3, (ch - boxH * FRONT) / (per - 1)) : 0
    return { COLS, ROWS, per, groups, lidH, frontH, pad, gap, cw, ch, boxW, boxH, strip }
  }, [style, slots, caseW, areaH])

  const groups = layout.groups
  const visiblePage = Math.min(page, (layout.pages || 1) - 1)
  // the size a dragged card is drawn at (as it would sit in the case)
  const dragW = style === 'foam' ? layout.cutW : style === 'topdown' ? Math.min(layout.previewW * 0.7, 220) : layout.boxW
  const dragH = dragW * SLAB_H / SLAB_W

  const pickStyle = id => {
    setStyle(id)
    setPage(0)
    try { localStorage.setItem('meta-comic-case-style', id) } catch { /* private window */ }
  }
  const toggleHand = () => setShowHand(value => {
    try { localStorage.setItem('meta-comic-case-hand', value ? '0' : '1') } catch { /* private window */ }
    return !value
  })

  const overHand = (x, y) => {
    const rect = handShown && handRef.current?.getBoundingClientRect()
    return !!rect && y >= rect.top - 12
  }
  const firstFree = group => (groups[group] || []).find(slot => !bySlot.has(slot)) || null

  // where a drag would land: { type: 'hand' } | { type: 'case', group, slot (exact spot), place (final slot) }
  const targetAt = (x, y, from) => {
    if (from.from === 'case' && overHand(x, y)) return { type: 'hand' }
    const element = document.elementFromPoint(x, y)
    const box = element?.closest?.('[data-case-group]')
    if (!box) return null
    const group = Number(box.dataset.caseGroup)
    const spot = element.closest('[data-case-slot]')
    const slot = spot ? Number(spot.dataset.caseSlot) : null
    let place = null
    if (from.from === 'case') place = slot && slot !== from.slot ? slot : (slot === from.slot ? null : firstFree(group))
    else place = slot && !bySlot.has(slot) ? slot : firstFree(group)
    return { type: 'case', group, slot, place }
  }

  // The card moves on screen at once; the server's answer (FiveM) then replaces both lists, or puts them back.
  const moveCard = async (note, optimistic, request) => {
    const before = { hand, pockets }
    setMoving(true)
    setMessage(note)
    optimistic()
    try {
      const response = isFiveM ? await request() : null
      if (response?.binder) {
        setPockets(response.binder.pockets || [])
        if (Array.isArray(response.binder.hand)) setHand(response.binder.hand)
      }
      setMessage('')
    } catch (error) {
      setHand(before.hand)
      setPockets(before.pockets)
      setMessage(error?.message || 'Could not move that card.')
    } finally {
      setMoving(false)
    }
  }

  const putIn = (entry, toSlot) => moveCard('Putting the card in the case…', () => {
    setHand(current => current.filter(item => item.slot !== entry.slot))
    setPockets(current => [...current, { slot: toSlot, card: entry.card }])
  }, () => bridge.binderStoreCard({ invSlot: entry.slot, toSlot }))

  const takeOut = slot => {
    const card = bySlot.get(slot)
    if (!card) return
    return moveCard('Taking the card out of the case…', () => {
      setPockets(current => current.filter(item => Number(item.slot) !== slot))
      setHand(current => [...current, { slot: isFiveM ? -Date.now() : Math.max(0, ...current.map(item => item.slot)) + 1, card }])
    }, () => bridge.binderTakeCard({ fromSlot: slot }))
  }

  const rearrange = (fromSlot, toSlot) => moveCard(bySlot.has(toSlot) ? 'Swapping cards…' : 'Moving the card…', () => {
    setPockets(current => current.map(item => {
      if (Number(item.slot) === fromSlot) return { ...item, slot: toSlot }
      if (Number(item.slot) === toSlot) return { ...item, slot: fromSlot }
      return item
    }))
  }, () => bridge.swapBinderCards({ fromSlot, toSlot }))

  const onPointerDown = (from, slot, card, event) => {
    if (busy || viewer || event.button !== 0) return
    event.preventDefault()
    session.current = { pointerId: event.pointerId, from, slot, card, startX: event.clientX, startY: event.clientY, started: false, originRect: event.currentTarget.getBoundingClientRect() }
  }

  const turnPage = dir => setPage(current => Math.max(0, Math.min((layout.pages || 1) - 1, Math.min(current, (layout.pages || 1) - 1) + dir)))
  const clearPageTimer = () => { window.clearTimeout(pageTimer.current.timer); pageTimer.current = { dir: 0, timer: 0 } }

  useEffect(() => {
    const onMove = event => {
      const active = session.current
      if (!active || event.pointerId !== active.pointerId) return
      if (!active.started && Math.hypot(event.clientX - active.startX, event.clientY - active.startY) < DRAG_PX) return
      active.started = true
      event.preventDefault()
      setDrag({ from: active.from, slot: active.slot, card: active.card, x: event.clientX, y: event.clientY, target: targetAt(event.clientX, event.clientY, active) })
      // foam display: hold a dragged card over a page arrow to turn the page
      const pager = document.elementFromPoint(event.clientX, event.clientY)?.closest?.('[data-case-pager]')
      const dir = pager ? Number(pager.dataset.casePager) : 0
      if (dir !== pageTimer.current.dir) {
        clearPageTimer()
        if (dir) pageTimer.current = { dir, timer: window.setTimeout(() => { pageTimer.current = { dir: 0, timer: 0 }; turnPage(dir) }, PAGE_HOVER_MS) }
      }
    }
    const onUp = event => {
      const active = session.current
      if (!active || event.pointerId !== active.pointerId) return
      session.current = null
      clearPageTimer()
      setDrag(null)
      if (!active.started) { setViewer({ card: active.card, originRect: active.originRect }); return }
      const target = targetAt(event.clientX, event.clientY, active)
      if (!target) return
      if (target.type === 'hand') { takeOut(active.slot); return }
      if (!target.place) { if (target.slot !== active.slot) setMessage(style === 'foam' ? 'This page of the case is full.' : 'That compartment is full.'); return }
      if (active.from === 'hand') putIn({ slot: active.slot, card: active.card }, target.place)
      else rearrange(active.slot, target.place)
    }
    const onCancel = event => {
      if (session.current?.pointerId !== event.pointerId) return
      session.current = null
      clearPageTimer()
      setDrag(null)
    }
    const onKey = event => {
      if (viewer) return
      if (event.key === 'ArrowRight' && style === 'foam') turnPage(1)
      if (event.key === 'ArrowLeft' && style === 'foam') turnPage(-1)
      if (event.key !== 'Escape') return
      if (session.current) { session.current = null; setDrag(null) } else if (!busy) onClose?.()
    }
    window.addEventListener('pointermove', onMove, { passive: false })
    window.addEventListener('pointerup', onUp)
    window.addEventListener('pointercancel', onCancel)
    window.addEventListener('keydown', onKey)
    return () => {
      window.removeEventListener('pointermove', onMove)
      window.removeEventListener('pointerup', onUp)
      window.removeEventListener('pointercancel', onCancel)
      window.removeEventListener('keydown', onKey)
    }
  })

  const target = drag?.target
  const filled = bySlot.size
  const groupClass = group => target?.type === 'case' && target.group === group ? (target.place ? 'is-target' : 'is-full') : ''
  const isPlace = slot => target?.type === 'case' && target.place === slot
  const lifted = slot => drag?.from === 'case' && drag.slot === slot
  const cardProps = (slot, card) => ({
    onPointerDown: event => onPointerDown('case', slot, card, event),
    onDragStart: event => event.preventDefault(),
    'aria-label': `${card.title || 'Card'} ${card.variantName || ''}. Click to inspect; drag to move.`,
  })

  // ---- style: compartments (lid strip, 2 x 4 compartments, cards upright)
  const renderCompartments = () => {
    const { COLS, ROWS, lidH, pad, gap, cw, ch, boxW, boxH, strip } = layout
    return (
      <div className="cc-case cc-case--compartments" style={{ width: caseW }}>
        <div className="cc-lid" style={{ height: lidH }} aria-hidden="true"><span className="cc-hinge cc-hinge--l" /><span className="cc-hinge cc-hinge--r" /></div>
        <div className={`cc-body ${drag ? 'is-dragging' : ''}`} style={{ padding: pad, gap, gridTemplateColumns: `repeat(${COLS}, ${cw}px)`, gridTemplateRows: `repeat(${ROWS}, ${ch}px)` }}>
          {groups.map((list, group) => (
            <div key={group} data-case-group={group} className={`cc-compartment ${groupClass(group)}`}>
              {list.map((slot, i) => {
                const card = bySlot.get(slot)
                return (
                  <div key={slot} data-case-slot={slot} className={`cc-slot ${card ? 'has-card' : ''} ${isPlace(slot) ? 'is-place' : ''}`}
                    style={{ top: i * strip, height: i === list.length - 1 ? Math.max(strip, ch - i * strip) : strip, zIndex: i + 1 }}>
                    {card && (
                      <button type="button" className={`cc-card ${lifted(slot) ? 'is-lifted' : ''}`} {...cardProps(slot, card)}
                        style={{ left: (cw - boxW) / 2, width: boxW, height: boxH, '--cc-lift': `${-Math.min(boxH * 0.46, Math.max(strip * 2, boxH * 0.3))}px` }}>
                        <span className="cc-card-visual"><FittedCard card={card} width={boxW} height={boxH} align="top" reserve="slab" /></span>
                      </button>
                    )}
                  </div>
                )
              })}
              <span className="cc-front-wall" aria-hidden="true" />
            </div>
          ))}
        </div>
      </div>
    )
  }

  // ---- style: foam display (briefcase opened flat, cards lying in slab-sized cut-outs)
  const renderFoam = () => {
    const { lidH, pad, gap, cols, cutW, cutH, pages } = layout
    const list = groups[visiblePage] || []
    return (
      <div className="cc-case cc-case--foam" style={{ width: caseW }}>
        <div className="cf-lid" style={{ height: lidH }} aria-hidden="true"><span className="cf-lid-foam" /><span className="cf-clasp" /></div>
        <div className="cf-hinge" aria-hidden="true" />
        <div className="cf-base">
          <div className={`cf-foam ${groupClass(visiblePage)}`} data-case-group={visiblePage}
            style={{ padding: pad, gap, gridTemplateColumns: `repeat(${cols}, ${cutW}px)`, gridAutoRows: `${cutH}px` }}>
            {list.map(slot => {
              const card = bySlot.get(slot)
              return (
                <div key={slot} data-case-slot={slot} className={`cf-cutout ${card ? 'has-card' : ''} ${isPlace(slot) ? 'is-place' : ''}`}>
                  {card && (
                    <button type="button" className={`cf-card ${lifted(slot) ? 'is-lifted' : ''}`} {...cardProps(slot, card)}>
                      <FittedCard card={card} width={cutW} height={cutH} reserve="slab" align="own" />
                    </button>
                  )}
                </div>
              )
            })}
          </div>
          {pages > 1 && (
            <div className="cf-pager">
              <button type="button" data-case-pager="-1" onClick={() => turnPage(-1)} disabled={visiblePage === 0} aria-label="Previous tray">‹</button>
              <span>Tray {visiblePage + 1} of {pages}</span>
              <button type="button" data-case-pager="1" onClick={() => turnPage(1)} disabled={visiblePage >= pages - 1} aria-label="Next tray">›</button>
            </div>
          )}
        </div>
      </div>
    )
  }

  // ---- style: top-down rows (slab tops seen from above, preview on the right)
  const renderTopDown = () => {
    const { COLS, ROWS, previewW, bodyW, lidH, pad, gap, cw, ch, edge } = layout
    const shown = drag?.card || preview
    return (
      <div className="cc-topdown" style={{ width: caseW }}>
        <div className="cc-case cc-case--topdown" style={{ width: bodyW }}>
          <div className="ct-lid" style={{ height: lidH }} aria-hidden="true" />
          <div className="ct-body" style={{ padding: pad, gap, gridTemplateColumns: `repeat(${COLS}, ${cw}px)`, gridTemplateRows: `repeat(${ROWS}, ${ch}px)` }}>
            {groups.map((list, group) => (
              <div key={group} data-case-group={group} className={`ct-row ${groupClass(group)}`}>
                {list.map(slot => {
                  const card = bySlot.get(slot)
                  const kind = card ? shellOf(card) : ''
                  return (
                    <div key={slot} data-case-slot={slot} className={`ct-slot ${isPlace(slot) ? 'is-place' : ''}`} style={{ height: edge }}>
                      {card && (
                        <button type="button" className={`ct-edge ct-edge--${kind} ${lifted(slot) ? 'is-lifted' : ''}`} {...cardProps(slot, card)}
                          style={{ '--edge-accent': card.accent || '#64748b' }}
                          onPointerEnter={() => setPreview(card)}>
                          <span className="ct-edge-title">{card.title || 'Card'}</span>
                          <span className="ct-edge-sub">{card.variantName || card.rarity || ''}</span>
                          {card.graded && <b className="ct-edge-grade">{card.graded.grade}</b>}
                        </button>
                      )}
                    </div>
                  )
                })}
              </div>
            ))}
          </div>
        </div>
        <aside className="ct-preview" style={{ width: previewW }}>
          {shown
            ? <><div className="ct-preview-card" style={{ width: previewW * 0.8, height: previewW * 0.8 * SLAB_H / SLAB_W }}><FittedCard card={shown} width={previewW * 0.8} height={previewW * 0.8 * SLAB_H / SLAB_W} reserve="slab" /></div>
              <strong>{shown.title}</strong><span>{[shown.variantName, shown.graded ? `Graded ${shown.graded.grade} ${shown.graded.name || ''}` : shellOf(shown) !== 'none' ? `In a ${shellOf(shown)}` : 'Raw card'].filter(Boolean).join(' · ')}</span></>
            : <span className="ct-preview-empty">Hover a card to see it here</span>}
        </aside>
      </div>
    )
  }

  const styleInfo = CASE_STYLES.find(entry => entry.id === style)

  return (
    <div className="bd-overlay cc-overlay" role="dialog" aria-label={holder?.label || 'Card case'} style={handShown ? { paddingBottom: handH } : undefined}>
      <div className="bd-head" style={{ width: caseW }}>
        <div>
          <strong>{holder?.label || 'Card Case'}</strong>
          <span>{filled} card{filled === 1 ? '' : 's'} · {slots} spaces</span>
          <span className={`bd-swap-help ${message ? 'has-message' : ''}`}>
            {message || (handShown ? 'Drag a card from your hand into the case · Drag a case card onto your hand to take it out · Click to inspect' : styleInfo?.help)}
          </span>
        </div>
        <div className="bd-head-actions">
          <div className="cc-style-pick" role="group" aria-label="Case style">
            {CASE_STYLES.map(entry => (
              <button key={entry.id} type="button" className={entry.id === style ? 'is-on' : ''} onClick={() => pickStyle(entry.id)} disabled={busy || !!drag} title={entry.help}>{entry.label}</button>
            ))}
          </div>
          {handAvailable && (
            <button type="button" className={`bd-hand-toggle ${handShown ? 'is-on' : ''}`} onClick={toggleHand} disabled={busy} aria-pressed={handShown}>
              {handShown ? 'Hide' : 'Show'} card hand ({hand.length})
            </button>
          )}
          <button type="button" className="bd-close" onClick={onClose} disabled={busy} aria-label="Close card case">×</button>
        </div>
      </div>

      {style === 'foam' ? renderFoam() : style === 'topdown' ? renderTopDown() : renderCompartments()}

      {drag && (
        <div className="bd-drag-float cc-drag-float" style={{ left: drag.x - dragW / 2, top: drag.y - dragH * 0.3, width: dragW, height: dragH }}>
          <FittedCard card={drag.card} width={dragW} height={dragH} reserve="slab" />
        </div>
      )}

      {handShown && (
        <div ref={handRef} className={`bd-hand ${drag?.from === 'case' ? 'is-receiving' : ''} ${target?.type === 'hand' ? 'is-hot' : ''}`} style={{ height: handH }}>
          {drag?.from === 'case' && <span className="bd-hand-hint">Drop here to put it back in your inventory</span>}
          {!drag && !hand.length && <span className="bd-hand-hint">No trading cards in your inventory</span>}
          {hand.map((entry, i) => {
            const mid = (hand.length - 1) / 2
            const spacing = Math.min(handCardW * 0.62, (size.w * 0.86 - handCardW) / Math.max(1, hand.length - 1))
            const angle = (i - mid) * Math.min(6, 64 / Math.max(1, hand.length))
            return (
              <button type="button" key={entry.slot}
                className={`bd-hand-card ${drag?.from === 'hand' && drag.slot === entry.slot ? 'is-lifted' : ''}`}
                style={{ width: handCardW, height: handCardH, zIndex: i + 1, '--hand-x': `${(i - mid) * spacing}px`, '--hand-r': `${angle}deg`, '--hand-y': `${Math.abs(angle) * Math.abs(i - mid) * 0.5}px` }}
                onPointerDown={event => onPointerDown('hand', entry.slot, entry.card, event)}
                onPointerEnter={() => setPreview(entry.card)}
                onDragStart={event => event.preventDefault()}
                aria-label={`${entry.card.title || 'Card'} ${entry.card.variantName || ''}. Drag into the case to put it in; click to inspect.`}>
                <FittedCard card={entry.card} width={handCardW} height={handCardH} reserve="slab" />
              </button>
            )
          })}
        </div>
      )}

      {viewer && <CardViewer card={viewer.card} originRect={viewer.originRect} onClose={() => setViewer(null)} title={`${viewer.card.title || 'Card'} ${viewer.card.variantName || ''}`.trim()} />}
    </div>
  )
}
