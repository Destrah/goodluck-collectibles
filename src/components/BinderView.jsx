import React, { useEffect, useMemo, useRef, useState } from 'react'
import TradingCard from './TradingCard'
import CardViewer from './CardViewer'
import { bridge, isFiveM } from '../runtime'
import '../styles/binder.css'

const CARD_W = 230, CARD_H = 322
const TURN_MS = 620
const HOLD_MS = 190
const EXTRACT_MS = 300
const DROP_MS = 680
const EDGE_HOVER_MS = 520
const EDGE_REARM_MS = 180

const delay = ms => new Promise(resolve => window.setTimeout(resolve, ms))

/**
 * Trading card binder: an open binder with clear 9-pocket sleeve pages.
 *   binder = { label, slots, pockets: [{ slot, card }] }
 *
 * Click = inspect. Hold + drag = reorder. A drag can land on another card (swap) or an empty pocket (move).
 */
export default function BinderView({ binder, onClose, perPage = 9 }) {
  const [size, setSize] = useState(() => ({ w: window.innerWidth, h: window.innerHeight }))
  const [spread, setSpread] = useState(0)
  const [turn, setTurn] = useState(null)
  const [viewer, setViewer] = useState(null)
  const [pockets, setPockets] = useState(() => binder?.pockets || [])
  const [drag, setDrag] = useState(null)
  const [dropping, setDropping] = useState(null)
  const [dragMessage, setDragMessage] = useState('')
  const [edgeHover, setEdgeHover] = useState(null)

  const binderRef = useRef(null)
  const cardRefs = useRef(new Map())
  const pocketRefs = useRef(new Map())
  const pointerSession = useRef(null)
  const dragRef = useRef(null)
  const extractTimer = useRef(null)
  const edgeTimer = useRef(null)
  const edgeHoverRef = useRef(null)
  const spreadRef = useRef(0)
  const turnRef = useRef(null)
  const suppressClickUntil = useRef(0)

  const setDragState = next => {
    dragRef.current = typeof next === 'function' ? next(dragRef.current) : next
    setDrag(dragRef.current)
  }

  const clearEdgeHover = () => {
    if (edgeTimer.current) window.clearTimeout(edgeTimer.current)
    edgeTimer.current = null
    edgeHoverRef.current = null
    setEdgeHover(null)
  }

  const clearPointerSession = () => {
    const session = pointerSession.current
    if (session?.holdTimer) window.clearTimeout(session.holdTimer)
    pointerSession.current = null
  }

  const cancelDrag = () => {
    if (extractTimer.current) window.clearTimeout(extractTimer.current)
    extractTimer.current = null
    clearPointerSession()
    clearEdgeHover()
    setDragState(null)
    setDragMessage('')
  }

  useEffect(() => {
    setPockets(binder?.pockets || [])
    cancelDrag()
    setDropping(null)
    setDragMessage('')
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [binder])

  useEffect(() => {
    const onResize = () => setSize({ w: window.innerWidth, h: window.innerHeight })
    window.addEventListener('resize', onResize)
    return () => window.removeEventListener('resize', onResize)
  }, [])

  useEffect(() => () => {
    if (extractTimer.current) window.clearTimeout(extractTimer.current)
    if (edgeTimer.current) window.clearTimeout(edgeTimer.current)
    clearPointerSession()
  }, [])

  const bySlot = useMemo(() => {
    const map = new Map()
    for (const pocket of pockets || []) if (pocket?.card) map.set(Number(pocket.slot), pocket.card)
    return map
  }, [pockets])

  const filled = bySlot.size
  const slots = Math.max(Number(binder?.slots) || 0, ...[...bySlot.keys()], perPage)
  const single = size.w / size.h < 1.25
  const pageCount = Math.max(single ? 1 : 2, Math.ceil(slots / perPage))
  const pagesPerView = single ? 1 : 2
  const spreads = Math.ceil(pageCount / pagesPerView)
  const pageSlots = page => Array.from({ length: perPage }, (_, i) => page * perPage + i + 1)

  const pageRatio = 0.78
  const spineW = single ? 0 : 0.08
  const H = Math.floor(Math.min(size.h * 0.84, (size.w * 0.94) / (pagesPerView * pageRatio + spineW)))
  const pageW = Math.floor(H * pageRatio), spine = Math.floor(H * spineW)
  const pad = Math.round(H * 0.035), gap = Math.round(H * 0.012)
  const pocketW = (pageW - pad * 2 - gap * 2) / 3, pocketH = (H - pad * 2 - gap * 2) / 3
  const scale = Math.min((pocketW * 0.9) / CARD_W, (pocketH * 0.9) / CARD_H)
  const busy = !!drag || !!dropping
  spreadRef.current = spread
  turnRef.current = turn

  const go = dir => {
    if (turn || busy) return
    const to = spread + dir
    if (to < 0 || to >= spreads) return
    if (single) { setSpread(to); return }
    setTurn({ dir, to })
    window.setTimeout(() => { setSpread(to); setTurn(null) }, TURN_MS)
  }

  const promoteDragToFloating = () => {
    const active = dragRef.current
    const session = pointerSession.current
    if (!active || active.phase !== 'dragging' || active.floating || !session) return active
    const button = cardRefs.current.get(active.slot)
    if (!button) return active
    const rect = button.getBoundingClientRect()
    const next = {
      ...active,
      floating: true,
      sourceSpread: active.sourceSpread ?? spreadRef.current,
      floatLeft: rect.left,
      floatTop: rect.top,
      floatWidth: rect.width,
      floatHeight: rect.height,
      floatPointerX: session.lastX,
      floatPointerY: session.lastY,
      targetSlot: null,
    }
    setDragState(next)
    return next
  }

  const edgeAtPoint = (x, y) => {
    const root = binderRef.current
    if (!root) return null
    const rect = root.getBoundingClientRect()
    const verticalPad = Math.max(36, H * 0.08)
    if (y < rect.top - verticalPad || y > rect.bottom + verticalPad) return null
    const zone = Math.max(52, Math.min(92, rect.width * 0.085))
    const outsideAllowance = Math.max(30, zone * 0.55)
    const current = spreadRef.current
    if (x >= rect.left - outsideAllowance && x <= rect.left + zone && current > 0) return 'left'
    if (x <= rect.right + outsideAllowance && x >= rect.right - zone && current < spreads - 1) return 'right'
    return null
  }

  const updateFloatingPosition = (x, y) => {
    setDragState(current => {
      if (!current?.floating) return current
      return {
        ...current,
        floatLeft: current.floatLeft + (x - current.floatPointerX),
        floatTop: current.floatTop + (y - current.floatPointerY),
        floatPointerX: x,
        floatPointerY: y,
        targetSlot: slotAtPoint(x, y),
      }
    })
  }

  const turnDuringDrag = dir => {
    const active = dragRef.current
    if (!active || active.phase !== 'dragging' || dropping || turnRef.current) return
    const current = spreadRef.current
    const to = current + dir
    if (to < 0 || to >= spreads) { clearEdgeHover(); return }

    promoteDragToFloating()
    clearEdgeHover()
    setDragMessage(`Turning ${dir < 0 ? 'back' : 'forward'} while holding card…`)
    setDragState(value => value ? { ...value, targetSlot: null, crossedPages: true } : value)

    const finishTurn = () => {
      spreadRef.current = to
      setSpread(to)
      setTurn(null)
      turnRef.current = null
      setDragMessage('Drop on an empty pocket to move, or another card to swap.')
      window.setTimeout(() => {
        const session = pointerSession.current
        if (session && dragRef.current?.phase === 'dragging') updateEdgeHover(session.lastX, session.lastY)
      }, EDGE_REARM_MS)
    }

    if (single) {
      spreadRef.current = to
      setSpread(to)
      window.setTimeout(() => {
        setDragMessage('Drop on an empty pocket to move, or another card to swap.')
        const session = pointerSession.current
        if (session && dragRef.current?.phase === 'dragging') updateEdgeHover(session.lastX, session.lastY)
      }, EDGE_REARM_MS)
      return
    }

    const nextTurn = { dir, to, dragTurn: true }
    turnRef.current = nextTurn
    setTurn(nextTurn)
    window.setTimeout(finishTurn, TURN_MS)
  }

  const updateEdgeHover = (x, y) => {
    const active = dragRef.current
    if (!active || active.phase !== 'dragging' || dropping || turnRef.current) {
      clearEdgeHover()
      return
    }
    const edge = edgeAtPoint(x, y)
    if (!edge) {
      clearEdgeHover()
      return
    }
    if (edgeHoverRef.current === edge && edgeTimer.current) return
    if (edgeTimer.current) window.clearTimeout(edgeTimer.current)
    edgeHoverRef.current = edge
    setEdgeHover(edge)
    edgeTimer.current = window.setTimeout(() => {
      edgeTimer.current = null
      if (edgeHoverRef.current === edge && dragRef.current?.phase === 'dragging') {
        turnDuringDrag(edge === 'left' ? -1 : 1)
      }
    }, EDGE_HOVER_MS)
  }

  useEffect(() => {
    const onKey = event => {
      if (viewer) return
      if (event.key === 'ArrowRight') go(1)
      if (event.key === 'ArrowLeft') go(-1)
      if (event.key === 'Escape') {
        if (drag && !dropping) cancelDrag()
        else if (!dropping) onClose?.()
      }
    }
    window.addEventListener('keydown', onKey)
    return () => window.removeEventListener('keydown', onKey)
  })

  const openCard = (card, event) => {
    if (busy || Date.now() < suppressClickUntil.current) {
      event?.preventDefault?.()
      return
    }
    setViewer({ card, originRect: event.currentTarget.getBoundingClientRect() })
  }

  const slotAtPoint = (x, y) => {
    const element = document.elementFromPoint(x, y)
    const pocket = element?.closest?.('.bd-pocket[data-binder-slot]')
    if (!pocket || !pocket.closest('.bd-overlay')) return null
    const slot = Number(pocket.dataset.binderSlot)
    return slot >= 1 && slot <= slots ? slot : null
  }

  const beginDrag = session => {
    if (!session || pointerSession.current !== session || dropping || viewer) return
    const button = cardRefs.current.get(session.slot)
    if (!button) return
    const rect = button.getBoundingClientRect()
    const extract = Math.max(rect.height + 18, 96)
    session.dragStarted = true
    suppressClickUntil.current = Date.now() + 900
    setDragMessage('Pulling card from sleeve…')
    setDragState({
      slot: session.slot,
      card: session.card,
      phase: 'extracting',
      dx: 0,
      dy: 0,
      targetSlot: null,
      extract,
      sourceSpread: spreadRef.current,
      floating: false,
    })

    extractTimer.current = window.setTimeout(() => {
      const active = pointerSession.current
      if (!active || active !== session) return
      const dx = active.lastX - active.startX
      const dy = active.lastY - active.startY
      const targetSlot = slotAtPoint(active.lastX, active.lastY)
      setDragState(current => current && current.slot === session.slot
        ? { ...current, phase: 'dragging', dx, dy, targetSlot }
        : current)
      setDragMessage('Drop on an empty pocket to move, or another card to swap.')
      window.setTimeout(() => {
        if (pointerSession.current === session && dragRef.current?.phase === 'dragging') {
          updateEdgeHover(active.lastX, active.lastY)
        }
      }, 0)
    }, EXTRACT_MS)
  }

  const onCardPointerDown = (slot, card, event) => {
    if (busy || viewer || event.button !== 0) return
    clearPointerSession()
    const session = {
      pointerId: event.pointerId,
      slot,
      card,
      startX: event.clientX,
      startY: event.clientY,
      lastX: event.clientX,
      lastY: event.clientY,
      dragStarted: false,
      holdTimer: null,
    }
    session.holdTimer = window.setTimeout(() => beginDrag(session), HOLD_MS)
    pointerSession.current = session
  }

  const applyLocalReorder = (fromSlot, toSlot) => {
    setPockets(current => {
      const from = current.find(pocket => Number(pocket.slot) === fromSlot)
      if (!from) return current
      const to = current.find(pocket => Number(pocket.slot) === toSlot)
      if (!to) return current.map(pocket => Number(pocket.slot) === fromSlot ? { ...pocket, slot: toSlot } : pocket)
      return current.map(pocket => {
        if (Number(pocket.slot) === fromSlot) return { ...pocket, slot: toSlot }
        if (Number(pocket.slot) === toSlot) return { ...pocket, slot: fromSlot }
        return pocket
      })
    })
  }

  const finishReorder = async (fromSlot, toSlot, dragSnapshot) => {
    const targetPocket = pocketRefs.current.get(toSlot)
    if (!targetPocket) {
      cancelDrag()
      setDragMessage('That destination pocket is not currently visible.')
      return
    }

    const targetRect = targetPocket.getBoundingClientRect()
    const targetCard = cardRefs.current.get(toSlot)
    const targetCardRect = targetCard?.getBoundingClientRect()
    const targetExtract = targetCardRect ? Math.max(targetCardRect.height + 18, 96) : dragSnapshot.extract

    if (dragSnapshot.floating) {
      const cardWidth = dragSnapshot.floatWidth || CARD_W * scale
      const cardHeight = dragSnapshot.floatHeight || CARD_H * scale
      const restLeft = targetCardRect?.left ?? (targetRect.left + (targetRect.width - cardWidth) / 2)
      const restTop = targetCardRect?.top ?? (targetRect.top + (targetRect.height - cardHeight) / 2)
      setDropping({
        crossPage: true,
        fromSlot,
        toSlot,
        sourceCard: dragSnapshot.card,
        floatLeft: dragSnapshot.floatLeft,
        floatTop: dragSnapshot.floatTop,
        floatWidth: cardWidth,
        floatHeight: cardHeight,
        floatEndX: restLeft - dragSnapshot.floatLeft,
        floatEndY: (restTop - dragSnapshot.extract) - dragSnapshot.floatTop,
        sourceExtract: dragSnapshot.extract,
        targetOccupied: !!targetCard,
        targetExtract,
        returnX: (toSlot > fromSlot ? -1 : 1) * Math.max(pageW * 0.78, 240),
      })
    } else {
      const sourcePocket = pocketRefs.current.get(fromSlot)
      if (!sourcePocket) {
        cancelDrag()
        setDragMessage('The source pocket is no longer visible.')
        return
      }
      const sourceRect = sourcePocket.getBoundingClientRect()
      const dx = targetRect.left - sourceRect.left
      const dy = targetRect.top - sourceRect.top
      setDropping({
        crossPage: false,
        fromSlot,
        toSlot,
        sourceStartX: dragSnapshot.dx,
        sourceStartY: dragSnapshot.dy,
        sourceEndX: dx,
        sourceEndY: dy,
        sourceExtract: dragSnapshot.extract,
        targetOccupied: !!targetCard,
        targetEndX: -dx,
        targetEndY: -dy,
        targetExtract,
      })
    }

    clearEdgeHover()
    setDragState(null)
    setDragMessage(targetCard ? 'Swapping binder positions…' : 'Placing card in empty pocket…')

    try {
      if (isFiveM) {
        const [response] = await Promise.all([
          bridge.swapBinderCards({ fromSlot, toSlot }),
          delay(DROP_MS),
        ])
        if (response?.binder?.pockets) setPockets(response.binder.pockets)
        else applyLocalReorder(fromSlot, toSlot)
      } else {
        await delay(DROP_MS)
        applyLocalReorder(fromSlot, toSlot)
      }
      setDragMessage('')
    } catch (error) {
      setDragMessage(error?.message || 'Could not move that card.')
    } finally {
      setDropping(null)
    }
  }

  useEffect(() => {
    const onMove = event => {
      const session = pointerSession.current
      if (!session || event.pointerId !== session.pointerId) return
      session.lastX = event.clientX
      session.lastY = event.clientY
      const active = dragRef.current
      if (!active || !session.dragStarted || active.phase !== 'dragging') return
      event.preventDefault()

      if (active.floating) {
        updateFloatingPosition(event.clientX, event.clientY)
      } else {
        const targetSlot = slotAtPoint(event.clientX, event.clientY)
        setDragState(current => current && current.slot === session.slot ? {
          ...current,
          dx: event.clientX - session.startX,
          dy: event.clientY - session.startY,
          targetSlot,
        } : current)
      }
      updateEdgeHover(event.clientX, event.clientY)
    }

    const finishPointerDrop = (session, active, x, y) => {
      let snapshot = active
      if (active.floating) {
        snapshot = {
          ...active,
          floatLeft: active.floatLeft + (x - active.floatPointerX),
          floatTop: active.floatTop + (y - active.floatPointerY),
          floatPointerX: x,
          floatPointerY: y,
        }
      } else {
        snapshot = {
          ...active,
          dx: x - session.startX,
          dy: y - session.startY,
        }
      }
      const targetSlot = slotAtPoint(x, y) || snapshot.targetSlot
      if (!targetSlot || targetSlot === snapshot.slot) {
        setDragState(null)
        setDragMessage('')
        return
      }
      finishReorder(snapshot.slot, targetSlot, snapshot)
    }

    const onUp = event => {
      const session = pointerSession.current
      if (!session || event.pointerId !== session.pointerId) return
      if (session.holdTimer) window.clearTimeout(session.holdTimer)
      const active = dragRef.current
      if (!session.dragStarted || !active) {
        pointerSession.current = null
        return
      }

      event.preventDefault()
      suppressClickUntil.current = Date.now() + 700
      if (extractTimer.current) window.clearTimeout(extractTimer.current)
      extractTimer.current = null
      if (edgeTimer.current) window.clearTimeout(edgeTimer.current)
      edgeTimer.current = null
      edgeHoverRef.current = null
      setEdgeHover(null)
      session.lastX = event.clientX
      session.lastY = event.clientY
      pointerSession.current = null

      if (turnRef.current) {
        const x = event.clientX, y = event.clientY
        window.setTimeout(() => {
          const latest = dragRef.current
          if (latest) finishPointerDrop(session, latest, x, y)
        }, TURN_MS + 30)
        return
      }
      finishPointerDrop(session, active, event.clientX, event.clientY)
    }

    const onCancel = event => {
      const session = pointerSession.current
      if (!session || event.pointerId !== session.pointerId) return
      suppressClickUntil.current = session.dragStarted ? Date.now() + 500 : suppressClickUntil.current
      cancelDrag()
    }

    window.addEventListener('pointermove', onMove, { passive: false })
    window.addEventListener('pointerup', onUp, { passive: false })
    window.addEventListener('pointercancel', onCancel)
    return () => {
      window.removeEventListener('pointermove', onMove)
      window.removeEventListener('pointerup', onUp)
      window.removeEventListener('pointercancel', onCancel)
    }
  })

  const cardMotion = slot => {
    if (drag?.slot === slot) {
      if (drag.floating) return undefined
      if (drag.phase === 'extracting') return {
        '--bd-drag-extract-y': `-${drag.extract}px`,
        animationDuration: `${EXTRACT_MS}ms`,
      }
      return {
        '--bd-drag-x': `${drag.dx}px`,
        '--bd-drag-y': `${drag.dy}px`,
        '--bd-drag-extract-y': `-${drag.extract}px`,
      }
    }
    if (!dropping) return undefined
    if (dropping.crossPage) {
      if (dropping.targetOccupied && slot === dropping.toSlot) return {
        '--bd-cross-return-x': `${dropping.returnX}px`,
        '--bd-cross-return-extract-y': `-${dropping.targetExtract}px`,
        animationDuration: `${DROP_MS}ms`,
      }
      return undefined
    }
    if (slot === dropping.fromSlot) return {
      '--bd-drop-start-x': `${dropping.sourceStartX}px`,
      '--bd-drop-start-y': `${dropping.sourceStartY}px`,
      '--bd-drop-end-x': `${dropping.sourceEndX}px`,
      '--bd-drop-end-y': `${dropping.sourceEndY}px`,
      '--bd-drop-extract-y': `-${dropping.sourceExtract}px`,
      animationDuration: `${DROP_MS}ms`,
    }
    if (dropping.targetOccupied && slot === dropping.toSlot) return {
      '--bd-return-x': `${dropping.targetEndX}px`,
      '--bd-return-y': `${dropping.targetEndY}px`,
      '--bd-return-extract-y': `-${dropping.targetExtract}px`,
      animationDuration: `${DROP_MS}ms`,
    }
    return undefined
  }

  const renderFloatingCard = () => {
    const active = drag?.floating ? drag : (dropping?.crossPage ? dropping : null)
    if (!active) return null
    const isDrop = !!dropping?.crossPage
    const card = isDrop ? dropping.sourceCard : drag.card
    const width = isDrop ? dropping.floatWidth : drag.floatWidth
    const height = isDrop ? dropping.floatHeight : drag.floatHeight
    const left = isDrop ? dropping.floatLeft : drag.floatLeft
    const top = isDrop ? dropping.floatTop : drag.floatTop
    const floatingScale = width / CARD_W
    return (
      <div className={`bd-drag-float ${isDrop ? 'is-dropping' : ''}`}
        style={{
          left, top, width, height,
          '--bd-float-drop-x': isDrop ? `${dropping.floatEndX}px` : '0px',
          '--bd-float-drop-y': isDrop ? `${dropping.floatEndY}px` : '0px',
          animationDuration: isDrop ? `${DROP_MS}ms` : undefined,
        }}>
        <span className="bd-card-scale" style={{ transform: `scale(${floatingScale})` }}>
          <TradingCard card={card} size="medium" interactive={false} />
        </span>
      </div>
    )
  }

  const renderPage = (page, side, captureRefs = true) => (
    <div className={`bd-page bd-page--${side}`} style={{ width: pageW, height: H, padding: pad }}>
      <div className="bd-grid" style={{ gridTemplateColumns: `repeat(3, ${pocketW}px)`, gridTemplateRows: `repeat(3, ${pocketH}px)`, gap }}>
        {page < pageCount && pageSlots(page).map(slot => {
          const card = bySlot.get(slot)
          const isDragSource = drag?.slot === slot
          const isTarget = drag?.targetSlot === slot && drag.slot !== slot
          const isDropSource = dropping?.fromSlot === slot
          const isDropTarget = dropping?.toSlot === slot
          const crossPageReturn = !!(dropping?.crossPage && dropping.targetOccupied && isDropTarget)
          const sourceHidden = !!(drag?.floating && isDragSource)
          return (
            <div
              ref={captureRefs ? (node => { if (node) pocketRefs.current.set(slot, node); else pocketRefs.current.delete(slot) }) : undefined}
              data-binder-slot={slot}
              className={`bd-pocket ${card ? 'has-card' : ''} ${slot > slots ? 'is-off' : ''} ${isTarget ? 'is-drag-target' : ''} ${isDragSource ? 'is-drag-source' : ''} ${isDropSource ? 'is-drop-source' : ''} ${isDropTarget ? 'is-drop-target' : ''}`}
              key={slot}>
              {card && (
                <button type="button"
                  ref={captureRefs ? (node => { if (node) cardRefs.current.set(slot, node); else cardRefs.current.delete(slot) }) : undefined}
                  className={`bd-card ${isDragSource && !drag?.floating ? `is-${drag.phase}` : ''} ${sourceHidden ? 'is-float-source-hidden' : ''} ${isDropSource && !dropping?.crossPage ? 'is-drop-source' : ''} ${dropping?.targetOccupied && isDropTarget && !dropping?.crossPage ? 'is-drop-return' : ''} ${crossPageReturn ? 'is-crosspage-return' : ''}`}
                  onPointerDown={captureRefs ? (event => onCardPointerDown(slot, card, event)) : undefined}
                  onClick={captureRefs ? (event => openCard(card, event)) : undefined}
                  onDragStart={event => event.preventDefault()}
                  aria-label={`${card.title || 'Card'} ${card.variantName || ''}. Click to inspect; hold and drag to move.`}
                  data-binder-drag-native="true"
                  style={{ width: CARD_W * scale, height: CARD_H * scale, ...cardMotion(slot) }}>
                  <span className="bd-card-scale" style={{ transform: `scale(${scale})` }}>
                    <TradingCard card={card} size="medium" interactive={false} />
                  </span>
                </button>
              )}
              {dropping?.crossPage && isDropTarget && (
                <div className="bd-crosspage-insert"
                  style={{
                    width: dropping.floatWidth,
                    height: dropping.floatHeight,
                    '--bd-cross-insert-extract-y': `-${dropping.sourceExtract}px`,
                    animationDuration: `${DROP_MS}ms`,
                  }}>
                  <span className="bd-card-scale" style={{ transform: `scale(${dropping.floatWidth / CARD_W})` }}>
                    <TradingCard card={dropping.sourceCard} size="medium" interactive={false} />
                  </span>
                </div>
              )}
              <span className="bd-sleeve" aria-hidden="true" />
            </div>
          )
        })}
      </div>
      {page < pageCount && <span className="bd-page-no">{page + 1}</span>}
    </div>
  )

  const leftOf = s => s * 2, rightOf = s => s * 2 + 1
  const leftPage = turn && turn.dir < 0 ? leftOf(turn.to) : leftOf(spread)
  const rightPage = turn && turn.dir > 0 ? rightOf(turn.to) : rightOf(spread)

  return (
    <div className="bd-overlay" role="dialog" aria-label={binder?.label || 'Trading card binder'} data-binder-drag-reorder="native">
      <div className="bd-head" style={{ width: single ? pageW + 40 : pageW * 2 + spine + 40 }}>
        <div>
          <strong>{binder?.label || 'Trading Card Binder'}</strong>
          <span>{filled} card{filled === 1 ? '' : 's'} · {slots} pockets</span>
          <span className={`bd-swap-help ${dragMessage ? 'has-message' : ''}`}>
            {dragMessage || 'Click to inspect · Hold and drag to move/swap · Hover a binder edge to turn pages'}
          </span>
        </div>
        <button type="button" className="bd-close" onClick={onClose} disabled={busy} aria-label="Close binder">×</button>
      </div>

      <div ref={binderRef} className={`bd-binder ${busy ? 'is-reordering' : ''}`} style={{ padding: 20 }}>
        {drag?.phase === 'dragging' && (
          <>
            <div className={`bd-drag-page-edge bd-drag-page-edge--left ${edgeHover === 'left' ? 'is-hot' : ''} ${spread === 0 ? 'is-disabled' : ''}`} aria-hidden="true">
              <strong>‹</strong><span>{spread === 0 ? 'First pages' : 'Hold to turn'}</span>
            </div>
            <div className={`bd-drag-page-edge bd-drag-page-edge--right ${edgeHover === 'right' ? 'is-hot' : ''} ${spread >= spreads - 1 ? 'is-disabled' : ''}`} aria-hidden="true">
              <strong>›</strong><span>{spread >= spreads - 1 ? 'Last pages' : 'Hold to turn'}</span>
            </div>
          </>
        )}
        {single ? (
          <div className="bd-spread">{renderPage(spread, 'right')}</div>
        ) : (
          <div className="bd-spread" style={{ width: pageW * 2 + spine, height: H }}>
            {renderPage(leftPage, 'left')}
            <div className="bd-spine" style={{ width: spine, height: H }}>
              {[0.18, 0.5, 0.82].map(y => <span className="bd-ring" key={y} style={{ top: `${y * 100}%` }} />)}
            </div>
            {renderPage(rightPage, 'right')}

            {turn && (
              <div className={`bd-leaf bd-leaf--${turn.dir > 0 ? 'next' : 'prev'}`}
                style={{ width: pageW, height: H, left: turn.dir > 0 ? pageW + spine : 0, animationDuration: `${TURN_MS}ms` }}>
                <div className="bd-leaf-face bd-leaf-front">{renderPage(turn.dir > 0 ? rightOf(spread) : leftOf(spread), turn.dir > 0 ? 'right' : 'left', false)}</div>
                <div className="bd-leaf-face bd-leaf-back">{renderPage(turn.dir > 0 ? leftOf(turn.to) : rightOf(turn.to), turn.dir > 0 ? 'left' : 'right', false)}</div>
              </div>
            )}
          </div>
        )}
      </div>

      {renderFloatingCard()}

      <div className="bd-nav">
        <button type="button" onClick={() => go(-1)} disabled={spread === 0 || !!turn || busy} aria-label="Previous pages">‹</button>
        <span>{single ? `Page ${spread + 1} of ${pageCount}` : `Pages ${spread * 2 + 1}–${Math.min(spread * 2 + 2, pageCount)} of ${pageCount}`}</span>
        <button type="button" onClick={() => go(1)} disabled={spread >= spreads - 1 || !!turn || busy} aria-label="Next pages">›</button>
      </div>

      {viewer && <CardViewer card={viewer.card} originRect={viewer.originRect} onClose={() => setViewer(null)} title={`${viewer.card.title || 'Card'} ${viewer.card.variantName || ''}`.trim()} />}
    </div>
  )
}
