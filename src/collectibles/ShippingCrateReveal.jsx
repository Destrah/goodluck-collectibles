import { useEffect, useRef, useState } from 'react'
import { bridge } from '../runtime'
import './shippingCrate.css'

// FiveM shipping crate item: the crate breaks open in 3D and its contents come out one by one.
// crate = { crate, label, serial, contents: [{ label, type, kind, collectible, outer, count }], animation }
export default function ShippingCrateReveal({ crate, onClose }) {
  const canvasRef = useRef(null)
  const sceneRef = useRef(null)
  const [revealed, setRevealed] = useState(0)
  const [finished, setFinished] = useState(false)
  const [failed, setFailed] = useState(false)
  const contents = Array.isArray(crate?.contents) ? crate.contents : []
  // the server hands the contents over once the reveal has finished (or the page closes), not before
  const claimed = useRef(false)
  const claim = () => { if (!claimed.current) { claimed.current = true; bridge.claimCrate?.().catch?.(() => {}) } }
  useEffect(() => { if (finished) claim() }, [finished])
  useEffect(() => () => claim(), [])

  useEffect(() => {
    let cancelled = false
    import('./ShippingCrate3D.js')
      .then(({ createCrateScene }) => createCrateScene(canvasRef.current, {
        animation: crate?.animation, items: contents, serial: crate?.serial, label: crate?.label,
        onReveal: index => setRevealed(count => Math.max(count, index + 1)),
      }))
      .then(scene => {
        if (cancelled) return scene.dispose()
        sceneRef.current = scene
        return scene.play().then(() => { if (!cancelled) setFinished(true) })
      })
      .catch(error => { console.warn('Shipping crate 3D failed', error); if (!cancelled) { setFailed(true); setRevealed(contents.length); setFinished(true) } })
    return () => { cancelled = true; sceneRef.current?.dispose(); sceneRef.current = null }
  }, [crate]) // eslint-disable-line react-hooks/exhaustive-deps

  useEffect(() => {
    const onKey = event => { if (event.key === 'Escape') onClose?.(); else if (event.key === ' ' || event.key === 'Enter') sceneRef.current?.skip() }
    window.addEventListener('keydown', onKey)
    return () => window.removeEventListener('keydown', onKey)
  }, [onClose])

  return (
    <div className="crate-reveal" role="dialog" aria-label={crate?.label || 'Shipping crate'}>
      {!failed && <canvas ref={canvasRef} className="crate-reveal-canvas" onClick={() => sceneRef.current?.skip()} />}
      <header className="crate-reveal-head">
        <h2>{crate?.label || 'Shipping Crate'}</h2>
        {crate?.serial && <span className="crate-reveal-serial">{crate.serial}</span>}
      </header>
      <aside className="crate-reveal-list" aria-live="polite">
        <h3>Contents</h3>
        <ul>
          {contents.map((item, index) => (
            <li key={index} className={index < revealed ? 'is-in' : ''}>{index < revealed ? item.label : '?'}</li>
          ))}
          {!contents.length && <li className="is-in">Empty</li>}
        </ul>
      </aside>
      <footer className="crate-reveal-foot">
        {!finished && <button type="button" onClick={() => sceneRef.current?.skip()}>Skip</button>}
        <button type="button" className="primary" onClick={onClose}>{finished ? 'Done' : 'Close'}</button>
      </footer>
    </div>
  )
}
