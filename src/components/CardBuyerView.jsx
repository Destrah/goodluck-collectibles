import React, { useEffect, useMemo, useRef, useState } from 'react'
import FittedCard from './FittedCard'
import CardViewer from './CardViewer'
import { bridge } from '../runtime'
import '../styles/binder.css'
import './cardBuyer.css'

const money = value => `$${Number(value || 0).toLocaleString()}`
const valuationNote = value => value ? `Base ${money(value.basePrice)} · ${value.conditionNote}${value.populationFactor !== 1 && value.populationFactor != null ? ` · ${value.gradedPopulation} recorded at this grade (${value.populationFactor.toFixed(2)}×)` : ''}` : ''
function SaleBinder({ available, page, tile }) {
  const ref = useRef(null)
  const [size, setSize] = useState({ width: 70, height: 90 })
  useEffect(() => {
    const observer = new ResizeObserver(([entry]) => {
      const { width, height } = entry.contentRect
      setSize({ width: Math.max(24, (width - 48) / 6 - 10), height: Math.max(24, (height - 16) / 3 - 26) })
    })
    observer.observe(ref.current)
    return () => observer.disconnect()
  }, [])
  const renderPage = side => <div className={`bd-page bd-page--${side ? 'right' : 'left'} cb-binder-page`}>
    <div className="bd-grid cb-binder-grid">{Array.from({ length: 9 }, (_, i) => {
      const slot = page * 18 + side * 9 + i + 1
      const offer = available.find(entry => entry.slot === slot)
      return <div className="bd-pocket cb-binder-pocket" key={slot}>{tile(offer, false, size)}
        {!offer && <span className="cb-slot-number">{slot}</span>}<span className="bd-sleeve" /></div>
    })}</div>
  </div>
  return <div className="bd-binder cb-sale-binder"><div ref={ref} className="bd-spread cb-binder-spread">
    {renderPage(0)}<div className="bd-spine cb-binder-spine">{[18, 50, 82].map(top => <i key={top} className="bd-ring" style={{ top: `${top}%` }} />)}</div>{renderPage(1)}
  </div></div>
}
export function cardBuyerDemo(cards) {
  const holders = [{ id: 'demo-binder', kind: 'binder', label: 'My binder', slots: 36 }, { id: 'demo-case', kind: 'case', label: 'Collector case', slots: 24 }]
  return { index: 1, token: 'preview', label: 'Collector’s counter', maxCards: 60, balance: 15000, holders,
    offers: cards.slice(0, 30).map((card, i) => ({ ref: `demo:${i}`, location: i < 8 ? 'hand' : i < 21 ? 'demo-binder' : 'demo-case',
      slot: i < 8 ? i + 1 : i < 21 ? i - 7 : i - 20, card, label: card.title, price: [1, 2, 5, 15, 50][i % 5] })) }
}

export default function CardBuyerView({ buyer, onClose, demo = false }) {
  const [data, setData] = useState(buyer)
  const [location, setLocation] = useState('hand')
  const [page, setPage] = useState(0)
  const [selected, setSelected] = useState([])
  const [review, setReview] = useState(false)
  const [busy, setBusy] = useState(false)
  const [message, setMessage] = useState('')
  const [inspect, setInspect] = useState(null)
  const [dealing, setDealing] = useState(null)
  const [drag, setDrag] = useState(null)
  const [over, setOver] = useState(false)
  const offers = data.offers || []
  const chosen = useMemo(() => offers.filter(offer => selected.includes(offer.ref)), [offers, selected])
  const total = chosen.reduce((sum, offer) => sum + offer.price, 0)
  const unaffordable = data.balance !== false && total > data.balance
  const holder = data.holders?.find(entry => entry.id === location)
  const available = offers.filter(entry => entry.location === location)
  const hand = offers.filter(entry => entry.location === 'hand')
  const pages = Math.max(1, Math.ceil(Number(holder?.slots || 18) / 18))
  const add = ref => {
    const offer = offers.find(entry => entry.ref === ref)
    if (busy || review || !offer || offer.price === false || selected.includes(ref)) return
    if (selected.length >= (data.maxCards || 60)) { setMessage('The sale pile is full.'); return }
    setSelected(current => [...current, ref]); setMessage('')
  }
  const remove = ref => { if (!busy) { setSelected(current => current.filter(entry => entry !== ref)); setReview(false) } }
  useEffect(() => {
    const key = event => {
      if (event.key !== 'Escape') return
      event.preventDefault(); event.stopImmediatePropagation()
      if (inspect) setInspect(null)
      else if (!busy) { if (review) setReview(false); else onClose() }
    }
    const progress = event => {
      if (event.data?.type === 'metaComic:cardBuyerDealing') setDealing(event.data.done ? null : event.data)
    }
    window.addEventListener('keydown', key, true); window.addEventListener('message', progress)
    return () => { window.removeEventListener('keydown', key, true); window.removeEventListener('message', progress) }
  }, [busy, review, inspect, onClose])
  // Pointer dragging works in FiveM's Chromium as well as the browser; click + Add is the accessible alternative.
  useEffect(() => {
    if (!drag) return undefined
    const move = event => {
      const target = document.elementFromPoint(event.clientX, event.clientY)
      setOver(Boolean(target?.closest('[data-sale-pile]')))
      setDrag(current => current && { ...current, x: event.clientX, y: event.clientY, moved: current.moved || Math.hypot(event.clientX-current.startX,event.clientY-current.startY)>6 })
    }
    const up = event => {
      if (drag.moved && document.elementFromPoint(event.clientX, event.clientY)?.closest('[data-sale-pile]')) add(drag.ref)
      else if (!drag.moved) setInspect(offers.find(entry => entry.ref === drag.ref))
      setDrag(null); setOver(false)
    }
    const cancel = () => { setDrag(null); setOver(false) }
    window.addEventListener('pointermove', move); window.addEventListener('pointerup', up); window.addEventListener('pointercancel', cancel)
    return () => { window.removeEventListener('pointermove', move); window.removeEventListener('pointerup', up); window.removeEventListener('pointercancel', cancel) }
  }, [drag, selected, review, busy, offers])
  const refresh = async () => {
    setBusy(true); setMessage('')
    try { if (!demo) setData(await bridge.getCardBuyerUI({ index: data.index })); setSelected([]); setReview(false) }
    catch (error) { setMessage(error.message) }
    finally { setBusy(false) }
  }
  const sell = async () => {
    setBusy(true); setMessage('')
    try {
      const result = demo ? { total, count: chosen.length } : await bridge.sellCardBuyerCart({ token: data.token, refs: selected })
      setData(current => ({ ...current, offers: current.offers.filter(entry => !selected.includes(entry.ref)),
        balance: current.balance === false ? false : current.balance - result.total }))
      setSelected([]); setReview(false)
      setMessage(`${demo ? 'Preview: ' : ''}Sold ${result.count} cards for ${money(result.total)}.`)
      // A completed quote is single-use. Obtain fresh server inventory before another selection.
      if (!demo) {
        try { setData(await bridge.getCardBuyerUI({ index: data.index })) }
        catch (error) { setMessage(`Sold ${result.count} cards for ${money(result.total)}. ${error.message}`) }
      }
    } catch (error) { setMessage(error.message); setReview(false) }
    finally { setBusy(false); setDealing(null) }
  }
  const tile = (offer, compact = false, dimensions = null) => offer && (
    <div key={offer.ref} className={`cb-card ${selected.includes(offer.ref) ? 'is-selected' : ''} ${compact ? 'is-hand' : ''}`}
      style={dimensions ? { width: dimensions.width } : compact ? { '--cb-tilt': `${Math.max(-6,Math.min(6,(hand.indexOf(offer)-(hand.length-1)/2)*1.5))}deg` } : undefined}>
      <button type="button" className="cb-art" style={dimensions || undefined} disabled={busy || review} aria-label={`Inspect or drag ${offer.label}`}
        onPointerDown={event => { if (event.button !== 0 || selected.includes(offer.ref)) return; event.preventDefault(); setDrag({ ref: offer.ref, x: event.clientX, y: event.clientY, startX: event.clientX, startY: event.clientY, moved: false }) }}
        onKeyDown={event => { if (event.key === 'Enter') setInspect(offer) }}>
        <FittedCard card={offer.card} width={dimensions?.width || (compact ? 100 : 83)} height={dimensions?.height || (compact ? 142 : 115)} reserve={dimensions && !offer.card.graded ? 'toploader' : 'slab'} />
        {selected.includes(offer.ref) && <span className="cb-picked">In sale pile</span>}
      </button>
      <button type="button" className="cb-price" title={valuationNote(offer.valuation)} disabled={busy || review || offer.price === false} onClick={() => selected.includes(offer.ref) ? remove(offer.ref) : add(offer.ref)}>
        {selected.includes(offer.ref) ? '− Remove' : offer.price === false ? 'Not accepted' : `+ ${money(offer.price)}`}
      </button>
    </div>
  )
  return (
    <div className={`cb-overlay ${dealing ? 'is-dealing' : ''}`} role="dialog" aria-modal="true" aria-label="Sell trading cards">
      <section className="cb-counter">
        <header className="cb-header"><div><span className="cb-eyebrow">COLLECTOR BUYBACK {demo && '· PREVIEW'}</span><h1>{data.label}</h1><p>Drag cards into the sale pile. Review your selection before handing them over.</p></div>
          <div><button disabled={busy} onClick={refresh}>Refresh inventory</button><button disabled={busy} onClick={onClose} aria-label="Close selling screen">×</button></div></header>
        <div className="cb-body">
          <section className="cb-inventory">
            <div className="cb-source-heading"><h2>{holder?.label || 'Cards in your hand'}</h2><span>{available.length} cards</span></div>
            {location === 'hand' ? <div className="cb-hand-intro"><span>✦</span><h2>Your hand is below</h2><p>Pick a card to inspect it, or drag it onto the counter’s sale pile.</p><p>Switch to a binder or case using the tabs along the bottom.</p></div>
              : holder.kind === 'binder' ? <SaleBinder available={available} page={page} tile={tile} /> : <div className={`cb-holder cb-holder--${holder.kind}`}>
                {holder.kind === 'binder' && <div className="cb-rings"><i /><i /><i /></div>}
                {[0, 1].map(side => <div className="cb-page" key={side}>{Array.from({ length: 9 }, (_, i) => {
                  const slot = page * 18 + side * 9 + i + 1
                  const offer = available.find(entry => entry.slot === slot)
                  return <div className="cb-pocket" key={slot}>{tile(offer)}{!offer && <span>{slot}</span>}</div>
                })}</div>)}
              </div>}
            {holder && <div className="cb-pages"><button disabled={page === 0 || busy} onClick={() => setPage(page-1)}>‹ Previous</button><span>{page+1} / {pages}</span><button disabled={page+1 >= pages || busy} onClick={() => setPage(page+1)}>Next ›</button></div>}
          </section>
          <aside className={`cb-pile ${over ? 'is-over' : ''}`} data-sale-pile>
            <div className="cb-source-heading"><h2>{review ? 'Review your sale' : 'Sale pile'}</h2><span>{chosen.length} cards</span></div>
            <div className="cb-pile-list">{!chosen.length ? <div className="cb-empty"><span>↓</span><strong>Drop your cards here</strong><p>Cards stay in your inventory until you confirm the sale.</p></div> : chosen.map(offer => (
              <div className="cb-line" key={offer.ref}><button className="cb-mini" onClick={() => setInspect(offer)}><FittedCard card={offer.card} width={42} height={60} /></button><div><strong>{offer.label}</strong><small>{money(offer.price)}</small>{offer.valuation && <small className="cb-condition">{valuationNote(offer.valuation)}</small>}</div><button disabled={busy} onClick={() => remove(offer.ref)} aria-label={`Remove ${offer.label}`}>×</button></div>
            ))}</div>
            <div className="cb-total"><span>You receive</span><strong>{money(total)}</strong></div>
            {data.balance !== false && <p className={unaffordable ? 'cb-error' : 'cb-balance'}>{unaffordable ? 'The buyer cannot afford this whole pile.' : `Buyer funds: ${money(data.balance)}`}</p>}
            <button className="cb-confirm" disabled={!chosen.length || busy || unaffordable} onClick={() => review ? sell() : setReview(true)}>{busy ? 'Handing over cards…' : review ? `Confirm sale · ${money(total)}` : 'Review selected cards'}</button>
            {review && <button disabled={busy} onClick={() => setReview(false)}>Back to selecting</button>}
          </aside>
        </div>
        <footer className="cb-bottom"><nav aria-label="Inventory sources"><button className={location === 'hand' ? 'active' : ''} disabled={busy || review} onClick={() => { setLocation('hand'); setPage(0) }}>Hand · {hand.length}</button>{data.holders?.map(entry => <button key={entry.id} className={location === entry.id ? 'active' : ''} disabled={busy || review} onClick={() => { setLocation(entry.id); setPage(0) }}>{entry.kind === 'binder' ? '▤' : '▣'} {entry.label}</button>)}</nav>
          <div className="cb-hand">{hand.map(entry => tile(entry, true))}{!hand.length && <p>No loose cards. Choose a binder or case above.</p>}</div></footer>
        <div className="cb-status" role="status">{message || (review ? 'Check each selected card. Confirming sells the entire pile.' : 'Click a card to inspect · Drag to sell · Use + to select')}</div>
      </section>
      {drag?.moved && <div className="cb-drag" style={{ left: drag.x-50, top: drag.y-65 }}><FittedCard card={offers.find(entry => entry.ref === drag.ref)?.card} width={100} height={142} /></div>}
      {inspect && <><CardViewer card={inspect.card} title={`${inspect.label} · ${inspect.price === false ? 'Not accepted' : money(inspect.price)}`} onClose={() => setInspect(null)} /><div className="cb-inspect-action"><button disabled={busy || inspect.price === false} onClick={() => { selected.includes(inspect.ref) ? remove(inspect.ref) : add(inspect.ref); setInspect(null) }}>{selected.includes(inspect.ref) ? 'Remove from sale' : `Add to sale · ${money(inspect.price)}`}</button></div></>}
      {dealing && <div className="cb-dealing-status">Handing over card {dealing.index} of {dealing.count} · X to cancel</div>}
    </div>
  )
}
