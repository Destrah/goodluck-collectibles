import { useEffect, useLayoutEffect, useRef, useState } from 'react'
import ContainerVisual from './ContainerVisual'
import CollectibleView from './CollectibleView'
import { soundFx } from '../utils/soundFx'

const STAGGER = 140
const FLIGHT = 1000
const REVEAL = 650

// closed -> charge (container wobbles) -> opening (pouch loosens / lid lifts) -> emerging (items fly out) -> settled
export default function ContainerOpening({ run, onInspect, onComplete, onAllRevealed, flipAllKey = 0, compact = false }) {
  const [phase,setPhase] = useState('closed')
  const [revealed,setRevealed] = useState([])
  const [revealing,setRevealing] = useState([])
  const stage = useRef(null)
  const timers = useRef([])
  const later = (fn, ms) => timers.current.push(setTimeout(fn, ms))

  useEffect(() => {
    setPhase('closed'); setRevealed([]); setRevealing([])
    const emergeAt = 1900
    const settleAt = emergeAt + FLIGHT + STAGGER * Math.max(0, run.items.length - 1)
    const sound = { kind: run.outer ? 'case' : run.container.kind === 'bag' ? 'bag' : 'box', style: run.outer ? 'display' : run.container.kind === 'bag' ? 'velvet' : 'window', innerKind: run.container.kind === 'bag' ? 'bag' : 'box' }
    const landing = item => item.containerSnapshot ? (item.containerSnapshot.kind === 'bag' ? 'bag' : 'box') : item.collectibleType === 'challenge_coin' ? 'coin' : 'plush'
    later(() => {setPhase('charge'); soundFx.container({ ...sound, event: 'charge' })},200)
    later(() => {setPhase('opening'); soundFx.container({ ...sound, event: 'open' })},1000)
    later(() => {setPhase('emerging'); run.items.forEach((item,index) => later(() => soundFx.container({ ...sound, event: 'land', itemKind: landing(item) }),index * STAGGER + 900))},emergeAt)
    later(() => {setPhase('settled'); onComplete?.()},settleAt)
    return () => {timers.current.forEach(clearTimeout); timers.current = []}
  }, [run.id])

  // Each item starts its flight at the container's mouth, wherever the grid places it.
  useLayoutEffect(() => {
    if (phase !== 'emerging' || !stage.current) return
    const source = stage.current.querySelector(':scope > .meta-container')?.getBoundingClientRect()
    if (!source) return
    const mouthX = source.left + source.width / 2
    const mouthY = source.top + source.height * (run.container.kind === 'bag' && !run.outer ? .14 : .3)
    stage.current.querySelectorAll('.meta-opening-item').forEach(node => {
      const rect = node.getBoundingClientRect()
      node.style.setProperty('--from-x', `${mouthX - (rect.left + rect.width / 2)}px`)
      node.style.setProperty('--from-y', `${mouthY - (rect.top + rect.height / 2)}px`)
    })
  }, [phase, run.id])

  const reveal = index => {
    if (revealed.includes(index) || revealing.includes(index)) return
    setRevealing(current => current.includes(index) ? current : [...current,index])
    soundFx.container({ event: 'reveal', itemKind: run.items[index]?.collectibleType === 'challenge_coin' ? 'coin' : 'plush' })
    later(() => {setRevealed(current => current.includes(index) ? current : [...current,index]); setRevealing(current => current.filter(entry => entry !== index))},REVEAL)
  }
  const bag = run.container.kind === 'bag' && !run.outer
  useEffect(() => {
    if (flipAllKey && phase === 'settled' && !run.outer) run.items.forEach((_, index) => later(() => reveal(index), index * 180))
  }, [flipAllKey])
  const allRevealed = phase === 'settled' && (run.outer || revealed.length === run.items.length)
  useEffect(() => {if(allRevealed) onAllRevealed?.()}, [allRevealed])
  const caption = {
    closed:'Ready…',
    charge:bag ? 'Something is rattling inside…' : 'Something is moving inside…',
    opening:bag ? 'Loosening the drawstring…' : 'Lifting the box lid…',
    emerging:run.outer ? 'Unpacking sealed containers…' : bag ? 'Coins tumbling out…' : 'Here it comes…',
    settled:run.outer ? 'Sealed containers ready to open' : 'Click each silhouette to reveal, then click again to inspect',
  }[phase]
  const open = phase === 'opening' || phase === 'emerging' || phase === 'settled'

  return <section ref={stage} className={`meta-opening meta-opening--${phase} ${bag ? 'meta-opening--bag' : 'meta-opening--box'} ${run.typeId === 'challenge_coin' ? 'meta-opening--coins' : 'meta-opening--plush'}`} aria-live="polite">
    <div className="meta-opening-burst" aria-hidden="true" />
    <ContainerVisual typeId={run.typeId} container={run.container} outer={run.outer} opening={open} />
    <p>{caption}</p>
    <div className="meta-opening-contents">{run.items.map((item,index) => {
      const state = revealed.includes(index) ? 'is-revealed' : revealing.includes(index) ? 'is-revealing' : 'is-hidden'
      return <div key={item.instanceId} className="meta-opening-item" style={{'--reveal-delay':`${index*STAGGER}ms`,'--object-accent':item.accent || '#c9a34d'}}>
        {run.outer ? <><ContainerVisual typeId={run.typeId} container={item.containerSnapshot} /><small>{item.label}</small></> : <button className={`collectible-reveal-button ${state}`} disabled={phase !== 'settled' || state === 'is-revealing'} aria-label={state === 'is-revealed' ? `Inspect ${item.title}` : 'Reveal collectible'} onClick={() => {if (state === 'is-revealed') onInspect(item); else reveal(index)}}>
          <span className="collectible-reveal-spin"><CollectibleView item={item} /></span>
          <span className="collectible-reveal-flash" aria-hidden="true" />
        </button>}
      </div>
    })}</div>
    {!compact && !run.outer && phase === 'settled' && revealed.length < run.items.length && <button onClick={() => run.items.forEach((_,index) => later(() => reveal(index),index * 180))}>Reveal all</button>}
  </section>
}
