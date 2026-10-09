import { useEffect, useRef, useState } from 'react'
import { soundFx } from '../utils/soundFx'
import { bridge } from '../runtime'

const CAPTIONS = { loading: 'Getting the box ready…', sealed: 'Something is rattling inside…', tear: 'Tearing off the wrap…', open: 'Opening the box…', emerge: 'Here come the packs…', done: 'Packs ready on the table' }
// FiveM: the canvas covers the whole screen but the scene is framed like the centre stage, as in the container openings
const OVERLAY_FRAME = (w, h) => ({ width: Math.min(1400, w * 0.96), height: Math.max(240, Math.min(h * 0.7, 760)) })

// FiveM booster box item: the opening over the game world, like the coin bag / plushie box openings; the packs reach
// the inventory once it has played (or on close)
export function BoosterBoxOverlay({ box, onClose }) {
  const count = Number(box?.packs) || 12
  const packs = useRef(Promise.resolve(count)).current
  const [done, setDone] = useState(false)
  const claimed = useRef(false)
  const claim = () => { if (!claimed.current) { claimed.current = true; bridge.claimBox?.().catch?.(() => {}) } }
  useEffect(() => () => claim(), [])
  useEffect(() => {
    const onKey = event => { if (event.key === 'Escape') onClose?.() }
    window.addEventListener('keydown', onKey)
    return () => window.removeEventListener('keydown', onKey)
  }, [onClose])
  const name = box?.setName ? `${box.setName} booster pack` : 'booster pack'
  return <div className="pk-overlay collectible-opening-overlay bb-overlay" role="dialog" aria-label={box?.setName ? `${box.setName} Booster Box` : 'Booster Box'}>
    <div className="pk-overlay-stage">
      <BoosterBoxOpening3D packs={packs} frame={OVERLAY_FRAME} doneCaption={`+${count} ${name}${count === 1 ? '' : 's'} added to your inventory`} onDone={() => { claim(); setDone(true) }} />
    </div>
    <div className="pk-overlay-bar">
      <button type="button" className="primary" onClick={onClose}>{done ? 'Done' : 'Close'}</button>
    </div>
  </div>
}

// 3D opening of a booster box item (BoosterBox3D.js). packs: Promise of the pack count from the server; onDone(ok)
// runs when the packs have landed, or straight away (ok = false) when WebGL is unavailable so the 2D flow carries on.
export default function BoosterBoxOpening3D({ packs, onDone, frame, doneCaption }) {
  const host = useRef(null)
  const scene = useRef(null)
  const [phase, setPhase] = useState('loading')
  const done = useRef(onDone)
  done.current = onDone

  useEffect(() => {
    let dead = false, created = null
    const canvas = document.createElement('canvas') // a disposed renderer loses its context, so never reuse a canvas
    canvas.className = 'meta-opening3d-canvas'
    host.current.appendChild(canvas)
    import('../collectibles/BoosterBox3D.js')
      .then(({ createBoosterBoxScene }) => createBoosterBoxScene(canvas, {
        packs, frame,
        onPhase: (name, index, skipped) => {
          if (dead) return
          if (!skipped) soundFx.boosterBox?.(name)
          if (name !== 'land' && name !== 'drop') setPhase(name)
        },
      }))
      .then(result => {
        if (dead) { result.dispose(); return }
        created = result; scene.current = result
        setPhase(current => current === 'loading' ? 'sealed' : current)
        return result.play().then(ok => { if (!dead) done.current?.(ok !== false) })
      })
      .catch(error => {
        console.warn('[packs] 3D booster box opening unavailable', error)
        if (!dead) done.current?.(false)
      })
    return () => { dead = true; created?.dispose(); canvas.remove(); scene.current = null }
  }, [packs])

  return <section className="meta-opening3d bb-open3d" aria-live="polite" onClick={() => scene.current?.skip()}>
    <div className="meta-opening3d-stage"><div ref={host} className="meta-opening3d-host" /></div>
    {phase === 'done' && doneCaption ? <p className="bb-done">{doneCaption}</p> : <p>{CAPTIONS[phase] || CAPTIONS.loading}</p>}
  </section>
}
