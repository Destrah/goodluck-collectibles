import { useEffect, useRef, useState } from 'react'
import ContainerOpening from './ContainerOpening'
import ContainerVisual from './ContainerVisual'
import { normalizeLook, innerLookKind } from './container3dOptions'
import { soundFx } from '../utils/soundFx'

// Each scene gets its own canvas: disposing a renderer loses its WebGL context, so a canvas is never reused.
const mountCanvas = (parent, className) => { const canvas = document.createElement('canvas'); canvas.className = className; parent.appendChild(canvas); return canvas }

const CAPTIONS = {
  bag: { loading: 'Getting the pouch ready…', charge: 'Something is rattling inside…', open: 'Loosening the drawstring…', emerge: 'Here they come…' },
  box: { loading: 'Getting the box ready…', charge: 'Something is moving inside…', open: 'Opening the box…', emerge: 'Here it comes…' },
  case: { loading: 'Getting the case ready…', charge: 'Something heavy is inside…', open: 'Opening the case…', emerge: 'Unpacking sealed containers…' },
}

const plural = (label, count) => count === 1 ? label : /(x|s|ch|sh)$/i.test(label) ? label + 'es' : label + 's'
// what a landing / revealed item sounds like
const itemKind = item => item?.containerSnapshot ? (item.containerSnapshot.kind === 'bag' ? 'bag' : 'box') : item?.collectibleType === 'challenge_coin' ? 'coin' : 'plush'
const sceneKind = run => run.outer ? 'case' : innerLookKind(run.container)
const caseInfo = run => ({ count: run.items.length || run.container.outer?.count, innerLabel: run.container.label })

// Opening of a coin bag / plushie box / outer case rendered by Container3D.js. Falls back to the 2D CSS
// version when WebGL is unavailable. `look` is the container's saved design and animation.
// pendingItems (optional Promise of run.items): start the scene before the server has answered; run is then
// a provisional run (same id, no items) that the parent swaps for the real one when it arrives.
export default function ContainerOpening3D({ run, pendingItems, look, onInspect, onComplete, onAllRevealed, flipAllKey = 0, compact = false, frame }) {
  const host = useRef(null)
  const scene = useRef(null)
  const [failed, setFailed] = useState(false)
  const [phase, setPhase] = useState('loading')
  const [revealed, setRevealed] = useState([])
  const [labels, setLabels] = useState([])
  const kind = sceneKind(run)
  const chosen = normalizeLook(kind, look)
  const handlers = useRef({})
  handlers.current = { onInspect, onComplete }
  const runRef = useRef(run)
  runRef.current = run

  useEffect(() => {
    let dead = false, created = null
    setPhase('loading'); setRevealed([]); setLabels([]); setFailed(false)
    const canvas = mountCanvas(host.current, 'meta-opening3d-canvas')
    const soundBase = { kind, style: chosen.style, animation: chosen.animation, innerKind: innerLookKind(run.container) }
    import('./Container3D.js')
      .then(({ createContainerScene }) => createContainerScene(canvas, {
        kind, style: chosen.style, animation: chosen.animation, items: pendingItems || run.items, caseInfo: caseInfo(run), frame,
        onPhase: (name, index) => {
          if (dead) return
          if (name === 'charge' || name === 'open' || name === 'emerge') soundFx.container({ ...soundBase, event: name })
          if (name === 'land') soundFx.container({ ...soundBase, event: 'land', itemKind: itemKind(runRef.current.items[index]) })
          if (name === 'charge' || name === 'open' || name === 'emerge') setPhase(name)
          if (name === 'settled') { setPhase('settled'); handlers.current.onComplete?.() }
        },
        onReveal: index => { if (!dead) setRevealed(current => current.includes(index) ? current : [...current, index]) },
        onLayout: positions => { if (!dead) setLabels(positions) },
        onPick: (index, isRevealed) => {
          const { outer, items } = runRef.current
          if (outer) return
          if (isRevealed) handlers.current.onInspect(items[index])
          else { soundFx.container({ ...soundBase, event: 'reveal', itemKind: itemKind(items[index]) }); created?.reveal(index) }
        },
      }))
      .then(result => {
        if (dead) { result.dispose(); return }
        created = result; scene.current = result
        setPhase('charge')
        result.play()
      })
      .catch(error => {
        console.warn('[collectibles] 3D opening unavailable, using 2D fallback', error)
        if (!dead) setFailed(true)
      })
    return () => { dead = true; created?.dispose(); canvas.remove(); scene.current = null }
  }, [run.id, chosen.style, chosen.animation])

  const revealAll = () => {
    run.items.forEach((item, index) => !revealed.includes(index) && setTimeout(() => soundFx.container({ kind, event: 'reveal', itemKind: itemKind(item) }), index * 160))
    scene.current?.revealAll()
  }
  useEffect(() => {
    if (flipAllKey && phase === 'settled' && !failed && !run.outer) revealAll()
  }, [flipAllKey])
  const allRevealed = phase === 'settled' && (run.outer || revealed.length === run.items.length)
  useEffect(() => {if (allRevealed && !failed) onAllRevealed?.()}, [allRevealed,failed])

  if (failed) return <ContainerOpening run={run} onInspect={onInspect} onComplete={onComplete} onAllRevealed={onAllRevealed} flipAllKey={flipAllKey} compact={compact} />
  const caption = phase !== 'settled' ? CAPTIONS[kind][phase] || CAPTIONS[kind].loading
    : run.outer ? `${run.items.length} sealed ${plural(run.container.label.toLowerCase(), run.items.length)} unpacked${run.items.length > 24 ? ' (24 shown)' : ''}`
    : revealed.length < run.items.length ? 'Click each silhouette to reveal it, then click again to inspect' : 'Click a collectible to inspect it'

  return <section className="meta-opening3d" aria-live="polite">
    <div className="meta-opening3d-stage">
      <div ref={host} className="meta-opening3d-host" />
      {phase === 'settled' && !run.outer && labels.map((label, index) => revealed.includes(index) && <div key={run.items[index].instanceId} className="meta-opening3d-label" style={{ left: label.x, top: label.y }}>
        <strong>{run.items[index].title}</strong><span>{run.items[index].rarity}</span>
      </div>)}
    </div>
    <p>{caption}</p>
    {!compact && phase === 'settled' && !run.outer && <div className="meta-opening3d-actions">
      {revealed.length < run.items.length && <button onClick={revealAll}>Reveal all</button>}
      {/* keyboard access to the same reveal / inspect actions the canvas offers */}
      <div className="meta-opening3d-keys">{run.items.map((item, index) => <button key={item.instanceId} onClick={() => { if (revealed.includes(index)) onInspect(item); else { soundFx.container({ kind, event: 'reveal', itemKind: itemKind(item) }); scene.current?.reveal(index) } }}>{revealed.includes(index) ? `Inspect ${item.title}` : `Reveal #${index + 1}`}</button>)}</div>
    </div>}
  </section>
}

// Idle, slowly turning sealed container (or outer case) for the lab's opening tab.
export function ContainerPreview3D({ typeId, container, outer = false, look }) {
  const host = useRef(null)
  const [failed, setFailed] = useState(false)
  const kind = outer ? 'case' : innerLookKind(container)
  const chosen = normalizeLook(kind, look)
  const innerStyle = normalizeLook(innerLookKind(container), container.look).style
  useEffect(() => {
    let dead = false, created = null
    setFailed(false)
    const canvas = mountCanvas(host.current, 'meta-preview3d-canvas')
    canvas.setAttribute('aria-label', outer ? container.outer?.label || 'Outer case' : container.label)
    import('./Container3D.js')
      .then(({ createContainerScene }) => createContainerScene(canvas, { kind, style: chosen.style, animation: chosen.animation, preview: true, caseInfo: { count: container.outer?.count, innerLabel: container.label } }))
      .then(result => { if (dead) result.dispose(); else created = result })
      .catch(() => { if (!dead) setFailed(true) })
    return () => { dead = true; created?.dispose(); canvas.remove() }
  }, [kind, chosen.style, chosen.animation, innerStyle, container.outer?.count, container.label])
  if (failed) return <ContainerVisual typeId={typeId} container={container} outer={outer} />
  return <div ref={host} className="meta-preview3d-host" />
}
