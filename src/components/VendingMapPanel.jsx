import React, { useCallback, useEffect, useLayoutEffect, useMemo, useRef, useState } from 'react'
import { bridge, isFiveM } from '../runtime'
import { getResourceName } from '../runtime/env'
import './vendingMap.css'

// Lines world coordinates up with the common 8192px GTA V map tiles (Config.VendingMachines.Map overrides it).
const DEFAULT_MAP = { CenterX: 117.3, CenterY: 172.8, ScaleX: 0.02072, ScaleY: 0.0205 }
const LOW_STOCK = 0.2 // share of the maximum stock under which a product counts as low
const MIN_ZOOM = 1
const MAX_ZOOM = 14

const kindLabel = kind => kind === 'box' ? 'Booster Box' : 'Booster Pack'
const money = value => `$${Math.floor(Number(value) || 0).toLocaleString()}`
const clamp = (value, min, max) => Math.min(max, Math.max(min, value))

function mapImageUrl(image) {
  if (!image) return ''
  if (/^(https?:|nui:|data:)/.test(image)) return image
  const path = String(image).replace(/^\/+/, '')
  return isFiveM ? `nui://${getResourceName()}/${path}` : `/${path}`
}

// world x / y -> 0..1 across the map picture
function toMap(machine, map) {
  const c = { ...DEFAULT_MAP, ...map }
  return {
    x: (Number(machine.x) * Number(c.ScaleX) + Number(c.CenterX)) / 256,
    y: (Number(c.CenterY) - Number(machine.y) * Number(c.ScaleY)) / 256,
  }
}

// GPS fixes of machines that aren't standing anywhere (server: tracked = how it was last seen)
const TRACKED_LABEL = { carried: 'Carried as an item', ground: 'Dropped on the ground', towed: 'Being towed' }
const ago = seconds => {
  if (!seconds) return ''
  const minutes = Math.max(0, Math.round((Date.now() / 1000 - seconds) / 60))
  return minutes < 1 ? 'just now' : `${minutes} min ago`
}

function machineStatus(machine, maxStock) {
  if (machine.tracked) return 'tracked'
  const products = machine.products || []
  if (!products.length) return 'empty'
  if (products.some(product => (product.stock || 0) < 1)) return 'soldout'
  if (products.some(product => (product.stock || 0) < maxStock * LOW_STOCK)) return 'low'
  return 'ok'
}
const STATUS_LABEL = { ok: 'Stocked', low: 'Running low', soldout: 'Something sold out', empty: 'Sells nothing', tracked: 'GPS: not placed' }
const machineName = machine => machine.tracked ? (machine.serial || 'Machine') : `Vending machine #${machine.id}`

function VendingIcon() {
  return <svg viewBox="0 0 24 32" aria-hidden="true"><rect x="2" y="1" width="20" height="28" rx="3" /><rect className="glass" x="5" y="4" width="10" height="16" rx="1.5" /><rect className="slot" x="17" y="6" width="3" height="6" rx="1" /><rect className="slot" x="5" y="23" width="14" height="3" rx="1" /></svg>
}

function SetLogo({ logo, name }) {
  const [failed, setFailed] = useState(false)
  useEffect(() => setFailed(false), [logo])
  if (logo && !failed) return <img className="vending-logo" src={logo} alt="" onError={() => setFailed(true)} />
  return <span className="vending-logo vending-logo--text">{String(name || '?').slice(0, 2).toUpperCase()}</span>
}

export default function VendingMapPanel() {
  const [data, setData] = useState(null)
  const [error, setError] = useState('')
  const [loading, setLoading] = useState(false)
  const [selectedId, setSelectedId] = useState(null)
  const [filter, setFilter] = useState('all')
  const [imageFailed, setImageFailed] = useState(false)
  const [view, setView] = useState({ zoom: 1, x: 0, y: 0 })
  const [size, setSize] = useState({ width: 0, height: 0 })
  const [message, setMessage] = useState('')
  const viewport = useRef(null)
  const drag = useRef(null)

  const load = useCallback(async () => {
    setLoading(true); setError('')
    try {
      const result = await bridge.getVendingMachines()
      setData(result)
      setSelectedId(current => result.machines?.some(machine => machine.id === current) ? current : null)
    } catch (err) {
      setError(err?.message || String(err))
    } finally { setLoading(false) }
  }, [])
  useEffect(() => { load() }, [load])
  useEffect(() => {
    const refresh = event => { if (event.data?.type === 'metaComic:vendingRemoteAccessChanged') load() }
    window.addEventListener('message', refresh)
    return () => window.removeEventListener('message', refresh)
  }, [load])

  useLayoutEffect(() => {
    const element = viewport.current
    if (!element) return undefined
    const update = () => setSize({ width: element.clientWidth, height: element.clientHeight })
    update()
    const observer = new ResizeObserver(update)
    observer.observe(element)
    return () => observer.disconnect()
  }, [])

  const machines = data?.machines || []
  const maxStock = Number(data?.maxStock) || 100
  const logos = data?.logos || {}
  const map = data?.map || {}
  const image = mapImageUrl(map.Image)
  useEffect(() => setImageFailed(false), [image])

  // the map is a square that fits the viewport at zoom 1
  const side = Math.max(1, Math.min(size.width, size.height))
  const baseX = (size.width - side) / 2
  const baseY = (size.height - side) / 2
  // the map's edge may never move past the middle of the viewport, so it can't be dragged out of sight
  const clampView = useCallback(next => {
    const zoom = clamp(next.zoom, MIN_ZOOM, MAX_ZOOM)
    const cx = size.width / 2 - baseX
    const cy = size.height / 2 - baseY
    return { zoom, x: clamp(next.x, cx - side * zoom, cx), y: clamp(next.y, cy - side * zoom, cy) }
  }, [side, size.width, size.height, baseX, baseY])
  const zoomCenter = factor => setView(current => {
    const zoom = clamp(current.zoom * factor, MIN_ZOOM, MAX_ZOOM)
    const ratio = zoom / current.zoom
    const cx = size.width / 2 - baseX
    const cy = size.height / 2 - baseY
    return clampView({ zoom, x: cx - (cx - current.x) * ratio, y: cy - (cy - current.y) * ratio })
  })

  const zoomAt = (factor, clientX, clientY) => {
    const rect = viewport.current.getBoundingClientRect()
    const px = clientX - rect.left - baseX
    const py = clientY - rect.top - baseY
    setView(current => {
      const zoom = clamp(current.zoom * factor, MIN_ZOOM, MAX_ZOOM)
      const ratio = zoom / current.zoom
      return clampView({ zoom, x: px - (px - current.x) * ratio, y: py - (py - current.y) * ratio })
    })
  }

  const onWheel = event => { event.preventDefault(); zoomAt(event.deltaY < 0 ? 1.2 : 1 / 1.2, event.clientX, event.clientY) }
  useEffect(() => {
    const element = viewport.current
    if (!element) return undefined
    element.addEventListener('wheel', onWheel, { passive: false })
    return () => element.removeEventListener('wheel', onWheel)
  })

  const onPointerDown = event => {
    if (event.button !== 0) return
    drag.current = { id: event.pointerId, startX: event.clientX, startY: event.clientY, x: view.x, y: view.y, moved: false }
  }
  const onPointerMove = event => {
    const current = drag.current
    if (!current || current.id !== event.pointerId) return
    const dx = event.clientX - current.startX
    const dy = event.clientY - current.startY
    if (Math.abs(dx) + Math.abs(dy) > 4) current.moved = true
    if (current.moved) setView(previous => clampView({ ...previous, x: current.x + dx, y: current.y + dy }))
  }
  const onPointerUp = event => {
    const current = drag.current
    drag.current = null
    if (!current || current.moved) return
    // a click (not a drag): on a marker selects that machine, on the map itself clears the selection
    const marker = event.target.closest?.('.vending-marker')
    setSelectedId(marker ? Number(marker.dataset.id) : null)
  }

  const focusMachine = machine => {
    setSelectedId(machine.id)
    const point = toMap(machine, map)
    setView(current => {
      const zoom = Math.max(current.zoom, 4)
      return clampView({ zoom, x: size.width / 2 - baseX - point.x * side * zoom, y: size.height / 2 - baseY - point.y * side * zoom })
    })
  }

  const visible = useMemo(() => machines.filter(machine => filter === 'all' || (filter === 'attention' && ['low', 'soldout', 'empty'].includes(machineStatus(machine, maxStock)))), [machines, filter, maxStock])
  const selected = machines.find(machine => machine.id === selectedId) || null
  const counts = useMemo(() => {
    const result = { ok: 0, low: 0, soldout: 0, empty: 0, tracked: 0 }
    machines.forEach(machine => { result[machineStatus(machine, maxStock)] += 1 })
    return result
  }, [machines, maxStock])

  const waypoint = async machine => {
    setMessage('')
    try {
      await bridge.vendingWaypoint(machine.x, machine.y)
      setMessage(`Waypoint set to ${machine.tracked ? machine.serial : `vending machine #${machine.id}`}.`)
    } catch (err) { setMessage(err?.message || String(err)) }
  }

  return (
    <section className="management-page vending-page">
      <div className="management-heading">
        <div><span className="eyebrow">Restricted FiveM tools</span><h2>Vending machines</h2><p>Every placed machine and what it has left. Click a machine to see its stock; scroll to zoom and drag to move the map.</p></div>
        <button disabled={loading} onClick={load}>{loading ? 'Loading…' : 'Refresh'}</button>
      </div>
      {error && <div className="management-message" role="alert">{error}</div>}
      {message && <div className="management-message">{message}</div>}

      <div className="vending-layout">
        <div className="vending-map-card">
          <div className="vending-map-toolbar">
            <span className="vending-pill ok">{counts.ok} stocked</span>
            <span className="vending-pill low">{counts.low} low</span>
            <span className="vending-pill soldout">{counts.soldout} sold out</span>
            {counts.empty > 0 && <span className="vending-pill empty">{counts.empty} empty</span>}
            {counts.tracked > 0 && <span className="vending-pill tracked">{counts.tracked} on GPS</span>}
            <span className="vending-toolbar-gap" />
            <button className="ghost small-button" onClick={() => zoomCenter(1.4)}>+</button>
            <button className="ghost small-button" onClick={() => zoomCenter(1 / 1.4)}>−</button>
            <button className="ghost small-button" onClick={() => setView({ zoom: 1, x: 0, y: 0 })}>Reset</button>
          </div>
          <div ref={viewport} className="vending-map-viewport" onPointerDown={onPointerDown} onPointerMove={onPointerMove} onPointerUp={onPointerUp} onPointerCancel={() => { drag.current = null }} onPointerLeave={() => { drag.current = null }}>
            <div className={`vending-map ${!image || imageFailed ? 'vending-map--grid' : ''}`}
              style={{ width: side, height: side, left: baseX, top: baseY, transform: `translate(${view.x}px, ${view.y}px) scale(${view.zoom})` }}>
              {image && !imageFailed && <img className="vending-map-image" src={image} alt="" draggable="false" onError={() => setImageFailed(true)} />}
            </div>
            <div className="vending-marker-layer">
              {visible.map(machine => {
                const point = toMap(machine, map)
                const status = machineStatus(machine, maxStock)
                const left = baseX + view.x + point.x * side * view.zoom
                const top = baseY + view.y + point.y * side * view.zoom
                return <button key={machine.id} type="button" data-id={machine.id} title={`${machineName(machine)} · ${machine.tracked ? TRACKED_LABEL[machine.tracked] || STATUS_LABEL.tracked : STATUS_LABEL[status]}`}
                  className={`vending-marker ${status} ${machine.id === selectedId ? 'selected' : ''}`}
                  style={{ left, top }} onClick={event => { if (event.detail === 0) setSelectedId(machine.id) }}><VendingIcon /></button>
              })}
            </div>
            {(!image || imageFailed) && <div className="vending-map-note">No map picture found{map.Image ? ` at ${map.Image}` : ''}. Add one to show the GTA V map behind the machines (Config.VendingMachines.Map).</div>}
          </div>
        </div>

        <aside className="vending-side">
          {selected ? <div className="management-card vending-detail">
            <div className="management-panel-title">
              <div><strong>{machineName(selected)}</strong><span>{selected.tracked ? TRACKED_LABEL[selected.tracked] || STATUS_LABEL.tracked : STATUS_LABEL[machineStatus(selected, maxStock)]} · {Math.round(selected.x)}, {Math.round(selected.y)}</span></div>
              <button className="ghost small-button" onClick={() => setSelectedId(null)}>Close</button>
            </div>
            {selected.tracked && <p className="vending-empty">GPS fix {ago(selected.seenAt)}{selected.holderName ? ` · held by ${selected.holderName}` : ''}{selected.ownerName ? ` · owned by ${selected.ownerName}` : ''}. It shows here until it is placed again or its GPS is disabled.</p>}
            {!selected.tracked && (selected.products || []).length === 0 && <p className="vending-empty">This machine sells nothing yet. Add products with the Manage option on the machine.</p>}
            <div className="vending-products">
              {(selected.products || []).map(product => {
                const stock = product.stock || 0
                const share = clamp(stock / maxStock, 0, 1)
                const level = stock < 1 ? 'soldout' : share < LOW_STOCK ? 'low' : 'ok'
                return <div key={`${product.set}:${product.kind}`} className={`vending-product ${level}`}>
                  <SetLogo logo={logos[product.set]} name={product.setName} />
                  <div className="vending-product-info">
                    <strong>{product.setName}</strong>
                    <span>{kindLabel(product.kind)} · {money(product.price)}</span>
                    <div className="vending-stock-bar"><i style={{ width: `${share * 100}%` }} /></div>
                  </div>
                  <span className="vending-stock-count">{stock < 1 ? 'Sold out' : `${stock} / ${maxStock}`}</span>
                </div>
              })}
            </div>
            {isFiveM && <button className="primary" onClick={() => waypoint(selected)}>Set waypoint</button>}
          </div> : <div className="management-card vending-hint"><strong>Pick a machine</strong><span>Click a machine on the map or in the list to see its stock.</span></div>}

          <div className="management-card vending-list-card">
            <div className="management-panel-title">
              <div><strong>All machines</strong><span>{machines.filter(machine => !machine.tracked).length} placed{counts.tracked ? ` · ${counts.tracked} on GPS` : ''}</span></div>
              <select value={filter} onChange={event => setFilter(event.target.value)} aria-label="Show machines">
                <option value="all">All</option>
                <option value="attention">Needs restocking</option>
              </select>
            </div>
            <div className="vending-list">
              {visible.length === 0 && <p className="vending-empty">{machines.length ? 'Every machine is stocked.' : 'No vending machines placed yet. Use /placevending in game.'}</p>}
              {visible.map(machine => {
                const status = machineStatus(machine, maxStock)
                const total = (machine.products || []).reduce((sum, product) => sum + (product.stock || 0), 0)
                return <button key={machine.id} className={machine.id === selectedId ? 'active' : ''} onClick={() => focusMachine(machine)}>
                  <i className={`vending-dot ${status}`} />
                  <span><strong>{machine.tracked ? machine.serial : `#${machine.id}`}</strong><small>{machine.tracked ? `${TRACKED_LABEL[machine.tracked] || 'GPS'} · ${ago(machine.seenAt)}` : `${(machine.products || []).length} products · ${total} in stock`}</small></span>
                  <span className="vending-logos">{[...new Set((machine.products || []).map(product => product.set))].slice(0, 3).map(setId => {
                    const product = machine.products.find(entry => entry.set === setId)
                    return <SetLogo key={setId} logo={logos[setId]} name={product?.setName} />
                  })}</span>
                </button>
              })}
            </div>
          </div>
        </aside>
      </div>
    </section>
  )
}
