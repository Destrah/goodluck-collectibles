import { useEffect, useRef, useState } from 'react'
import { bridge } from '../runtime'
import CardViewer from '../components/CardViewer'
import ContainerOpening3D from './ContainerOpening3D'
import './collectibles.css'
import { loadPackPrefs } from '../runtime/packPrefs'
import { openingLook } from './containerPrefs.js'

export default function CollectibleOpeningOverlay({ request, onClose }) {
  const [run, setRun] = useState(null)
  const [error, setError] = useState('')
  const [settled, setSettled] = useState(false)
  const [flipAllKey, setFlipAllKey] = useState(0)
  const [viewer, setViewer] = useState(null)
  const [claiming, setClaiming] = useState(false)
  const claimRequest = useRef(null)
  const pending = useRef(null)
  useEffect(() => {
    let alive = true
    // Reuse the request during StrictMode effect replay: consuming an inventory
    // container must never be repeated by a presentation lifecycle.
    if (!pending.current) pending.current = Promise.all([
      bridge.openCollectibleContainer({ typeId: request.typeId, slot: request.slot, outer: request.outer }),loadPackPrefs(),
    ]).then(([response,prefs]) => ({...response,run:{...response.run,playbackLook:openingLook(response.run,prefs)}}))
    pending.current.then(response => { if (alive) setRun(response.run) })
      .catch(err => { if (alive) setError(err.message) })
    return () => { alive = false }
  }, [])
  const claim = () => {
    if (!claimRequest.current) {
      setClaiming(true)
      claimRequest.current = pending.current.catch(() => null).then(() => bridge.claimCollectibles())
        .catch(err => {claimRequest.current=null;setError(err.message);throw err})
        .finally(() => setClaiming(false))
    }
    return claimRequest.current
  }
  const close = () => {if(claiming)return;claim().then(onClose).catch(() => {})}
  const canFlip = settled && !run?.outer && !viewer
  useEffect(() => {
    const onKeyDown = event => {
      if (event.repeat || /^(INPUT|TEXTAREA|SELECT)$/.test(event.target?.tagName)) return
      if (event.key === 'Escape') {
        event.preventDefault()
        if (viewer) setViewer(null)
        else close()
      } else if (event.key.toLowerCase() === 'f' && canFlip) {
        event.preventDefault()
        setFlipAllKey(current => current + 1)
      }
    }
    window.addEventListener('keydown', onKeyDown)
    return () => window.removeEventListener('keydown', onKeyDown)
  }, [canFlip, viewer, onClose,claiming])
  return <div className="pk-overlay collectible-opening-overlay" role="dialog" aria-label="Opening a collectible container">
    <div className="pk-overlay-stage">
      {run && <ContainerOpening3D key={run.id} run={run} look={run.playbackLook}
        compact flipAllKey={flipAllKey} onInspect={setViewer} onComplete={() => setSettled(true)} onAllRevealed={() => claim().catch(() => {})} />}
      {!run && !error && <p className="collectible-opening-status" role="status">Opening container…</p>}
    </div>
    <div className="pk-overlay-bar">
      {error && <div className="runtime-error" role="alert">{error}</div>}
      {run && !run.outer && <button className="ghost pk-flip-all" disabled={!canFlip} onClick={() => setFlipAllKey(current => current + 1)}>Reveal all <kbd className="pk-keycap">F</kbd></button>}
      <button className="primary" disabled={claiming} onClick={close}>{claiming ? 'Receiving items…' : 'Close'}</button>
    </div>
    {viewer && <CardViewer card={viewer} title={viewer.title} onClose={() => setViewer(null)} />}
  </div>
}
