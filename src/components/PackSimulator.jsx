import React, { useEffect, useMemo, useRef, useState } from 'react'
import TradingCard from './TradingCard'
import PropVisual from './PropVisual'
import BoosterBoxOpening3D from './BoosterBoxOpening3D'
import CardViewer from './CardViewer'
import PackOpenScene, { PackStage, PackTable, TEAR_INFO, TEAR_KEYS, FAN_INFO, RANDOM_INFO, BASE_SECONDS, resolveTear, resolveFan, fanVars } from './PackOpenScene'
import { soundFx } from '../utils/soundFx'
import { bridge, isFiveM } from '../runtime'
import { variantsForTier } from '../runtime/packLogic'
import { rarityFx, rarityVars, sparkLayout } from '../utils/rarityFx'
import { DEFAULT_MAX_SPEED, DEFAULT_FLIP_ALL_KEY, MIN_SPEED, TEARS, FANS, clampSpeed, defaultPackPrefs, loadPackLimits, loadPackPrefs, savePackPrefs } from '../runtime/packPrefs'

const PACK_IMAGE = '/img/meta_pack.png'
const PACK_BACK_IMAGE = '/img/meta_pack_back.svg'
const BOX_IMAGE = '/img/meta_box_sheet.png'
const CARD_BACK_IMAGE = '/img/Cards_Back.jpg'

const sleep = ms => new Promise(resolve => setTimeout(resolve, ms))

/**
 * Pack / box lab, or (overlay) the centre-screen pack opening used when a FiveM player uses a booster pack item.
 *   overlay     render only the opening stage + Flip all / Done, centred on screen
 *   overlayKey  bump to open another pack in the overlay
 *   onClose     overlay "Done"
 */
export default function PackSimulator({ cards, sets = [], overlay = false, overlayKey = 0, onClose }) {
  const [setId,setSetId] = useState(sets[0]?.id || 'base')
  const [opened, setOpened] = useState([])
  const [revealed, setRevealed] = useState([])
  const [opening, setOpening] = useState(null)
  const [packsRemaining, setPacksRemaining] = useState(0)
  const [boxOpened, setBoxOpened] = useState(false)
  const [boxRun, setBoxRun] = useState(null) // the 3D box opening while it plays: { key, packs: Promise, onDone }
  const [viewer, setViewer] = useState(null)
  const [error, setError] = useState('')
  const [prefs, setPrefs] = useState(defaultPackPrefs)
  const [maxSpeed, setMaxSpeed] = useState(DEFAULT_MAX_SPEED)
  const [flipAllKey, setFlipAllKey] = useState(DEFAULT_FLIP_ALL_KEY)
  const [lastRun, setLastRun] = useState({ tear: 'peel', fan: 'line', speed: 1 })
  const [charging, setCharging] = useState([])
  const [settled, setSettled] = useState([]) // flip finished: rendered flat (no 3D layers) so the text is sharp
  const [flashKey, setFlashKey] = useState(0)
  const [flippingAll, setFlippingAll] = useState(false)
  const [prefsReady, setPrefsReady] = useState(false)
  const revealTimers = useRef([])
  const revealedRef = useRef([])
  const chargingRef = useRef([])
  const openedRef = useRef([])
  openedRef.current = opened
  const clearRevealTimers = () => { revealTimers.current.forEach(clearTimeout); revealTimers.current = [] }
  // clears every face-up / charging card (used whenever the table changes)
  const resetFlips = () => {
    clearRevealTimers()
    revealedRef.current = []; chargingRef.current = []
    setRevealed([]); setCharging([]); setSettled([]); setFlippingAll(false)
  }
  const prefsRef = useRef(defaultPackPrefs())
  const maxSpeedRef = useRef(DEFAULT_MAX_SPEED)
  const saveTimer = useRef(null)
  const [packPhase, setPackPhase] = useState('idle')
  const openingRef = useRef(false)

  const counts = useMemo(() => {
    const result = {}
    for (const tier of ['common', 'uncommon', 'rare', 'ultra_rare', 'legendary']) {
      const subjects = cards.filter(card => variantsForTier(card, tier).length > 0).length
      const prints = cards.reduce((sum, card) => sum + variantsForTier(card, tier).length, 0)
      result[tier] = { subjects, prints }
    }
    return result
  }, [cards])

  // Load the player's saved options once (speed limit comes from the server / config in FiveM).
  useEffect(() => {
    let alive = true
    ;(async () => {
      const limits = await loadPackLimits()
      const saved = await loadPackPrefs(limits.maxSpeed)
      if (!alive) return
      maxSpeedRef.current = limits.maxSpeed
      setFlipAllKey(limits.flipAllKey || DEFAULT_FLIP_ALL_KEY)
      prefsRef.current = saved
      setMaxSpeed(limits.maxSpeed)
      setPrefs(saved)
      setPrefsReady(true)
    })()
    return () => { alive = false; clearTimeout(saveTimer.current) }
  }, [])

  const updatePrefs = patch => {
    const next = { ...prefsRef.current, ...patch }
    next.speed = clampSpeed(next.speed, maxSpeedRef.current)
    prefsRef.current = next
    setPrefs(next)
    clearTimeout(saveTimer.current)
    saveTimer.current = setTimeout(() => savePackPrefs(next, maxSpeedRef.current), 250)
  }

  const playPhaseSound = phase => {
    if (phase === 'tilt' || phase === 'front-hold') soundFx.packHandle?.()
    if (phase === 'flip-start' || phase === 'flip-half') soundFx.packFlip?.()
    if (phase === 'seam-tension') soundFx.packCrinkle?.()
    if (phase === 'tear-start' || phase === 'tear-mid') soundFx.packTear?.(phase === 'tear-start' ? 'start' : 'mid')
    if (phase === 'tear-open') soundFx.packPeel?.()
    if (phase === 'cards-pull') soundFx.cardsSlide?.()
    if (phase === 'fan') soundFx.cardsFan?.()
  }

  // closing / leaving: stop the character animation and hand over any card items not yet claimed
  useEffect(() => () => {
    bridge.packProp?.('stop').catch(() => {})
    bridge.claimCards?.().catch(() => {})
  }, [])

  const sceneDone = useRef(null)
  const idleTimer = useRef(null)
  const [runId, setRunId] = useState(0)

  // PackOpenScene runs its own timeline and calls onDone when the cards are in their final line.
  const runPackScene = () => new Promise(resolve => {
    clearTimeout(idleTimer.current)
    sceneDone.current = resolve
    setPackPhase('front')
    setRunId(id => id + 1)
  })

  const openPack = async () => {
    if (openingRef.current) return
    openingRef.current = true
    setError('')
    setOpened([])
    resetFlips()
    setOpening('pack')
    // Resolve "random" once per pack so the animation and the final card layout agree.
    const current = prefsRef.current
    setLastRun({ tear: resolveTear(current.tear), fan: resolveFan(current.fan), speed: clampSpeed(current.speed, maxSpeedRef.current) })

    try {
      const responsePromise = bridge.openPack({ cards, set: setId })
      // Handle a fast server rejection while the existing scene is still running.
      responsePromise.catch(() => {})
      // overlay (item use): make sure the server accepted the open before ripping anything on screen
      if (overlay) await responsePromise
      // FiveM: the character holds the pack prop from the rip until the cards have fanned out
      bridge.packProp?.('start').catch(() => {})
      await runPackScene()
      bridge.packProp?.('stop').catch(() => {})
      const response = await responsePromise
      const result = Array.isArray(response?.cards) ? response.cards : []
      setOpened(result)
      // FiveM: the character holds the pulled cards while they're on screen (until the UI closes)
      if (result.length) bridge.holdCollectibles?.({ kind: 'card', count: result.length }).catch(() => {})
      resetFlips()
      if (packsRemaining > 0) setPacksRemaining(value => Math.max(0, value - 1))
      result.forEach((_, index) => setTimeout(() => soundFx.deal(), index * 80))
    } catch (err) {
      bridge.packProp?.('stop').catch(() => {})
      setError(err?.message || String(err))
    } finally {
      setOpening(null)
      // keep the animation layer mounted just long enough to cross-fade into the real cards
      idleTimer.current = setTimeout(() => setPackPhase('idle'), 550)
      openingRef.current = false
    }
  }

  const openBox = async () => {
    if (openingRef.current) return
    openingRef.current = true
    setError('')
    setOpened([])
    resetFlips()
    setOpening('box')
    const started = performance.now()
    // the 3D box drops in straight away and stays sealed until the server answers; then the packs come out
    const request = bridge.openBox({ cards, set: setId })
    let shown3d
    const played = new Promise(resolve => { shown3d = resolve })
    setBoxRun({ key: Date.now(), packs: request.then(response => Number(response?.packs) || 12), onDone: shown3d })
    try {
      const response = await request
      const played3d = await played
      if (!played3d) soundFx.boxOpen() // the 3D opening has its own wrap / lid sounds
      const wait = played3d ? 0 : Math.max(0, 1550 - (performance.now() - started))
      if (wait) await sleep(wait)
      setPacksRemaining(Number(response?.packs) || 12)
      setBoxOpened(true)
      if (!played3d) soundFx.boxReveal()
    } catch (err) {
      setError(err?.message || String(err))
    } finally {
      setBoxRun(null)
      setOpening(null)
      openingRef.current = false
    }
  }

  useEffect(() => bridge.subscribe(message => {
    // the centre-screen overlay starts its own opening; the lab must not also spend that pack
    if (overlay || message?.type !== 'metaComic:open' || message.overlay) return
    if (message.action === 'openPack') setTimeout(openPack, 0)
    if (message.action === 'openBox') setTimeout(openBox, 0)
  }), [cards, packsRemaining, overlay])

  // overlay: open a pack as soon as the player's tear / fan / speed preferences are loaded, and again whenever overlayKey changes
  const startedKey = useRef(0)
  useEffect(() => {
    if (!overlay || !prefsReady || !overlayKey || startedKey.current === overlayKey) return
    startedKey.current = overlayKey
    openPack()
  }, [overlay, overlayKey, prefsReady])

  // Flip a face-down card. Rare and better charge up first (glow, rays, shake), then flip with their rarity effects.
  // Returns how long until the card actually turns (ms).
  const flipCard = index => {
    if (revealedRef.current.includes(index) || chargingRef.current.includes(index)) return 0
    const tier = openedRef.current[index]?.rarityKey
    const fx = rarityFx(tier)
    const flip = () => {
      chargingRef.current = chargingRef.current.filter(i => i !== index)
      revealedRef.current = [...revealedRef.current, index]
      setCharging(chargingRef.current)
      setRevealed(revealedRef.current)
      revealTimers.current.push(setTimeout(() => setSettled(current => (current.includes(index) ? current : [...current, index])), 850))
      soundFx.flip()
      if (tier === 'rare' || tier === 'ultra_rare' || tier === 'legendary') {
        revealTimers.current.push(setTimeout(() => soundFx.rare(tier), 160))
      }
      if (fx.flash) revealTimers.current.push(setTimeout(() => setFlashKey(key => key + 1), 180))
    }
    if (fx.charge) {
      chargingRef.current = [...chargingRef.current, index]
      setCharging(chargingRef.current)
      revealTimers.current.push(setTimeout(flip, fx.charge))
    } else {
      flip()
    }
    return fx.charge || 0
  }

  // Flip every face-down card, left to right, each one waiting for the previous one (and its charge-up).
  const flipAll = () => {
    const queue = openedRef.current.map((_, i) => i).filter(i => !revealedRef.current.includes(i) && !chargingRef.current.includes(i))
    if (!queue.length) return
    setFlippingAll(true)
    let at = 0
    queue.forEach(i => {
      revealTimers.current.push(setTimeout(() => flipCard(i), at))
      at += (rarityFx(openedRef.current[i]?.rarityKey).charge || 0) + 420
    })
    revealTimers.current.push(setTimeout(() => setFlippingAll(false), at))
  }

  const toggleReveal = (index, event) => {
    if (charging.includes(index)) return
    if (!revealed.includes(index)) { flipCard(index); return }
    const rect = event.currentTarget.querySelector('.pull-inner')?.getBoundingClientRect() || event.currentTarget.getBoundingClientRect()
    setViewer({ card: opened[index], originRect: rect })
    soundFx.zoom()
  }

  const allRevealed = opened.length > 0 && revealed.length >= opened.length
  // every card flipped: the card items go into the player's inventory now (FiveM)
  useEffect(() => { if (allRevealed) bridge.claimCards?.().catch(() => {}) }, [allRevealed])
  const canFlipAll = opened.length > 0 && opening !== 'pack' && !allRevealed && !flippingAll

  // FiveM/standalone keyboard shortcut shown beside the button. NUI has keyboard focus while a pack is open.
  useEffect(() => {
    if (!canFlipAll || viewer) return undefined
    const expected = String(flipAllKey || DEFAULT_FLIP_ALL_KEY).toLowerCase()
    const onKeyDown = event => {
      const target = event.target
      if (target && ['INPUT', 'TEXTAREA', 'SELECT'].includes(target.tagName)) return
      if (String(event.key || '').toLowerCase() !== expected) return
      event.preventDefault()
      flipAll()
    }
    window.addEventListener('keydown', onKeyDown)
    return () => window.removeEventListener('keydown', onKeyDown)
  }, [canFlipAll, viewer, flipAllKey, opened, revealed, charging])

  const flipAllLabel = <>Flip all <kbd className="pk-keycap">{String(flipAllKey || DEFAULT_FLIP_ALL_KEY).toUpperCase()}</kbd></>

  const resetTable = () => {
    setOpened([])
    resetFlips()
    setOpening(null)
    setPacksRemaining(0)
    setBoxOpened(false)
    setViewer(null)
    clearTimeout(idleTimer.current)
    setPackPhase('idle')
  }

  const stage = (
    <PackStage>
      {packPhase !== 'idle' && (
        <PackOpenScene
          key={runId}
          tear={lastRun.tear}
          fan={lastRun.fan}
          speed={lastRun.speed}
          handoff={opened.length > 0}
          onPhase={playPhaseSound}
          onDone={() => { sceneDone.current?.(); sceneDone.current = null }}
        />
      )}
      {opened.length > 0 && (
        <PackTable>
          <div className={`pack-results pack-results--${lastRun.fan}`}>
            {opened.map((card, index) => {
              const isRevealed = revealed.includes(index)
              const isCharging = charging.includes(index)
              const isSelected = viewer?.card?.pullId === card.pullId
              const fx = rarityFx(card.rarityKey)
              return (
                <button className={`pull-slot ${isRevealed ? 'revealed can-zoom' : ''} ${isRevealed && settled.includes(index) ? 'settled' : ''} ${isCharging ? 'charging' : ''} ${fx.ring ? 'has-ring' : ''} ${isSelected ? 'viewer-selected' : ''}`} key={card.pullId} onClick={(event) => toggleReveal(index, event)} style={{ '--slot-index': index, ...fanVars(lastRun.fan, index, opened.length), ...rarityVars(card.rarityKey) }}>
                  <div className="rfx" aria-hidden="true">
                    <div className="rfx-rays-anchor"><div className="rfx-rays" /></div>
                    <div className="rfx-glow" />
                    <div className="rfx-ring" />
                    {sparkLayout(fx.sparks, index + 1).map((sp, k) => (
                      <i key={k} className="rfx-spark" style={{ left: `${sp.x}%`, top: `${sp.y}%`, '--sz': `${sp.size}px`, '--d': `${sp.delay}ms`, '--t': `${sp.dur}ms` }} />
                    ))}
                  </div>
                  <div className="pull-inner">
                    <div className="pull-back"><img src={CARD_BACK_IMAGE} alt="Card back" /><span>Click to reveal</span></div>
                    <div className="pull-front"><TradingCard card={card} size="large" interactive={isRevealed && !isSelected} /></div>
                  </div>
                  <div className="pull-caption"><strong>{isRevealed ? card.title : 'Hidden card'}</strong><span>{isRevealed ? `${card.variantName} · ${card.rarity}` : `Card ${index + 1}`}</span></div>
                </button>
              )
            })}
          </div>
        </PackTable>
      )}
      {flashKey > 0 && <div className="pk-flash" key={flashKey} aria-hidden="true" />}
    </PackStage>
  )

  const viewerEl = viewer && (
    <CardViewer
      card={viewer.card}
      originRect={viewer.originRect}
      onClose={() => setViewer(null)}
      title={`${viewer.card.title} ${viewer.card.variantName}`}
    />
  )

  // ---------- centre-screen overlay (FiveM booster pack item) ----------
  if (overlay) {
    return (
      <div className="pk-overlay" role="dialog" aria-label="Opening a booster pack">
        <div className="pk-overlay-stage">{stage}</div>
        <div className="pk-overlay-bar">
          {error && <div className="runtime-error">{error}</div>}
          {opened.length > 0 && opening !== 'pack' && (
            <>
              <button className="ghost pk-flip-all" onClick={flipAll} disabled={!canFlipAll}>{flipAllLabel}</button>
              <button className="primary" onClick={onClose}>{allRevealed ? 'Done' : 'Close'}</button>
            </>
          )}
          {error && <button className="primary" onClick={onClose}>Close</button>}
        </div>
        {viewerEl}
      </div>
    )
  }

  return (
    <section className="pack-lab">
      <div className="pack-heading">
        <div>
          <span className="eyebrow">FiveM pull logic + print variants</span>
          <h2>Pack & box opening lab</h2>
          <p>
            The pack animation is shared by standalone and FiveM NUI, so the visual sequence is the same in both. FiveM still receives the authoritative card pull from the server; only the presentation runs in React.
          </p>
        </div>
        <div className="pack-heading-actions">
          <button className="ghost" onClick={resetTable}>Reset table</button>
          <button className="primary pack-button" disabled={!!opening} onClick={openPack}>Rip booster pack</button>
          <button className="primary pack-button" disabled={!!opening} onClick={openBox}>Open booster box</button>
        </div>
      </div>

      {error && <div className="runtime-error">{error}</div>}
      {!!sets.length && <label className="field"><span>Card set</span><select value={setId} disabled={!!opening} onChange={event => setSetId(event.target.value)}>{sets.map(set => <option key={set.id} value={set.id}>{set.name}</option>)}</select></label>}

      <div className="rarity-pills">
        {Object.entries(counts).map(([tier, info]) => (
          <span key={tier}>{tier.replace('_', ' ')} <b>{info.subjects} cards / {info.prints} prints</b></span>
        ))}
      </div>

      <div className="pk-settings">
        <div className="pk-set-group">
          <span className="pk-set-title">Tear style</span>
          <div className="pk-set-row">
            {TEARS.map(key => {
              const info = key === 'random' ? RANDOM_INFO : TEAR_INFO[key]
              return <button key={key} type="button" className={`pk-opt ${prefs.tear === key ? 'selected' : ''}`} onClick={() => updatePrefs({ tear: key })} disabled={!!opening} title={info.short}>{info.label}</button>
            })}
          </div>
          <small className="pk-set-desc">{(prefs.tear === 'random' ? RANDOM_INFO : TEAR_INFO[prefs.tear]).short}</small>
        </div>
        <div className="pk-set-group">
          <span className="pk-set-title">Card fan-out</span>
          <div className="pk-set-row">
            {FANS.map(key => {
              const info = key === 'random' ? RANDOM_INFO : FAN_INFO[key]
              return <button key={key} type="button" className={`pk-opt ${prefs.fan === key ? 'selected' : ''}`} onClick={() => updatePrefs({ fan: key })} disabled={!!opening} title={info.short}>{info.label}</button>
            })}
          </div>
          <small className="pk-set-desc">{(prefs.fan === 'random' ? RANDOM_INFO : FAN_INFO[prefs.fan]).short}</small>
        </div>
        <div className="pk-set-group pk-set-speed">
          <span className="pk-set-title">Opening speed <b>{Number(prefs.speed.toFixed(2))}×</b></span>
          <input
            type="range"
            min={MIN_SPEED}
            max={maxSpeed}
            step={0.25}
            value={prefs.speed}
            onChange={event => updatePrefs({ speed: Number(event.target.value) })}
            disabled={!!opening || maxSpeed <= MIN_SPEED}
            aria-label="Pack opening speed"
          />
          <small className="pk-set-desc">1× is the original pace (slowest) · up to {maxSpeed}× · about {((prefs.tear === 'random' ? TEAR_KEYS.reduce((sum, key) => sum + BASE_SECONDS[key], 0) / TEAR_KEYS.length : BASE_SECONDS[prefs.tear] || BASE_SECONDS.seam) / prefs.speed).toFixed(1)} s per pack</small>
        </div>
      </div>

      {(opening === 'pack' || packPhase !== 'idle' || opened.length > 0) && (
        <section className={`pack-opening-scene pk-box ${opening === 'pack' ? 'is-active' : ''}`}>
          <div className="pk-head">
            <div className="pack-opening-copy">
              {opened.length > 0 && opening !== 'pack' ? (
                <>
                  <span className="eyebrow">Current pull</span>
                  <h3>{TEAR_INFO[lastRun.tear].label} · {FAN_INFO[lastRun.fan].label}</h3>
                  <p>All cards start face-down. Click once to reveal; click again to inspect larger.</p>
                </>
              ) : (
                <>
                  <span className="eyebrow">Opening pack</span>
                  <h3>{TEAR_INFO[lastRun.tear].label} · {FAN_INFO[lastRun.fan].label}</h3>
                  <p>{TEAR_INFO[lastRun.tear].detail}</p>
                </>
              )}
            </div>
            {opened.length > 0 && opening !== 'pack' && (
              <div className="pk-head-actions">
                {packsRemaining > 0 && <span className="packs-left">{packsRemaining} packs left in box</span>}
                <button className="ghost pk-flip-all" onClick={flipAll} disabled={!canFlipAll}>{flipAllLabel}</button>
                <button className="ghost" onClick={openPack} disabled={!!opening}>Open another pack</button>
              </div>
            )}
          </div>

          {stage}
        </section>
      )}

      {boxRun && <BoosterBoxOpening3D key={boxRun.key} packs={boxRun.packs} onDone={boxRun.onDone} />}

      {!boxRun && !boxOpened && !opened.length && opening !== 'pack' && (
        <div className="sealed-options">
          <button className="sealed-product" onClick={openPack} disabled={!!opening}>
            <div className="product-stage pack-product-stage">
              <div className="pack-shell-swap">
                <img className="pack-shell-front" src={PACK_IMAGE} alt="Booster pack front" />
                <img className="pack-shell-back" src={PACK_BACK_IMAGE} alt="Booster pack back" />
              </div>
            </div>
            <div>
              <strong>BOOSTER PACK</strong>
              <span>{(TEAR_INFO[prefs.tear] || RANDOM_INFO).label} • {(FAN_INFO[prefs.fan] || RANDOM_INFO).label} • {Number(prefs.speed.toFixed(2))}×</span>
              <small>Cards remain face-down through the opening, then settle in the reveal row where each card can be flipped individually.</small>
            </div>
          </button>

          <button className={`sealed-product ${opening === 'box' ? 'is-opening-box' : ''}`} onClick={openBox} disabled={!!opening}>
            <div className="product-stage box-product-stage">
              <div className="box-cellophane" />
              <div className="cellophane-strip" />
              <div className="box-lid" />
              <div className="box-pack-peek"><img src={PACK_IMAGE} alt="Pack preview" /></div>
              <PropVisual modelUrl="/models/prop_boosterbox_01.glb" imageUrl={BOX_IMAGE} alt="Booster box" />
            </div>
            <div>
              <strong>BOOSTER BOX</strong>
              <span>12 packs • unwrap + open</span>
              <small>After opening a box, each pack uses your selected tear style, fan-out and speed.</small>
            </div>
          </button>
        </div>
      )}

      {boxOpened && !opened.length && opening !== 'pack' && (
        <div className="box-table">
          <div className="opened-box-visual">
            <PropVisual modelUrl="/models/prop_boosterbox_01.glb" imageUrl={BOX_IMAGE} alt="Opened booster box" />
            <div className="pack-stack" aria-hidden="true">
              {Array.from({ length: Math.min(5, packsRemaining || 5) }).map((_, index) => (
                <img key={index} src={PACK_IMAGE} alt="" style={{ '--stack-index': index }} />
              ))}
            </div>
          </div>
          <div className="box-table-copy">
            <span className="eyebrow">Box opened</span>
            <h3>Packs ready on the table</h3>
            <p>Open a pack to run the selected opening sequence. The cards emerge as one face-down stack, then fan into place ready to flip.</p>
          </div>
        </div>
      )}

      <div className="stream-prop-note">
        <strong>Standalone / FiveM:</strong> the tear styles, fan-outs and speed setting are the same shared React animation in both environments. FiveM will not use a different pack-opening look unless you intentionally swap in a separate native animation later.
      </div>

      {viewerEl}
    </section>
  )
}
