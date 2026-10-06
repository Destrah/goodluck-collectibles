import React, { memo, useCallback, useEffect, useRef, useState, useSyncExternalStore } from 'react'
import { resolveCardVariant } from '../cardData'
import ElementalMaskFX from './ElementalMaskFX'
import { useResolvedAsset } from '../runtime/assets'
import ConditionOverlay from '../grading/ConditionOverlay'
import ProtectionShell from '../grading/ProtectionShell'
import { conditionStyle, textSectionStyle } from '../grading/condition.js'
import '../grading/grading.css'
import { formatPacks, oddsVersion, starCount, starStyle, subscribeOdds, tierOf } from '../utils/printOdds.js'
import { collectorNumber, setNumbersVersion, subscribeSetNumbers } from '../utils/setNumbers.js'

// footer stars: how many = the print's rarity tier; colour = how rare it really is to pull (see utils/printOdds.js)
function RarityStars({ card }) {
  useSyncExternalStore(subscribeOdds, oddsVersion)
  const { colour, label, packs } = starStyle(card)
  const tip = `${card.rarity || tierOf(card)}${packs ? ` · about 1 in ${formatPacks(packs)} packs${label ? ` (${label})` : ''}` : ''}`
  // a CSS tooltip, not title=: FiveM's NUI browser never shows native tooltips
  return <span className="rarity-stars" style={{ '--star': colour }} data-tip={tip} aria-label={tip}>{'★'.repeat(starCount(card))}</span>
}

// footer left: set code and collector number ("BASE 007/120"), then the print
function CardNumber({ card }) {
  useSyncExternalStore(subscribeSetNumbers, setNumbersVersion)
  const numbered = collectorNumber(card)
  const tip = numbered ? `Card ${Number(numbered.number)} of ${Number(numbered.total)} in ${card.setName || numbered.code}` : undefined
  return <span data-tip={tip} aria-label={tip}>{numbered ? numbered.label : 'META COMICS'} • {card.variantName || 'PRINT'}</span>
}

const clamp = (n, min, max) => Math.min(Math.max(n, min), max)
const ELEMENTAL_CONTOUR_MODES = new Set(['foil-flame', 'foil-flame-v2', 'foil-flame-hybrid', 'foil-flame-anime', 'foil-flame-smoky', 'foil-electric', 'foil-water'])

const maskRefCache = new Map()
function buildMaskReference(layer) {
  const key = `${layer?.maskSource || 'alpha'}|${layer?.image || ''}`
  let hit = maskRefCache.get(key)
  if (!hit) {
    hit = buildMaskReferenceUncached(layer)
    if (maskRefCache.size > 80) maskRefCache.delete(maskRefCache.keys().next().value)
    maskRefCache.set(key, hit)
  }
  return hit
}

function buildMaskReferenceUncached(layer) {
  const maskSource = layer?.maskSource || 'alpha'
  if (!layer?.image) return { maskImage: 'none', maskMode: 'alpha' }
  if (maskSource === 'alpha') return { maskImage: `url("${layer.image}")`, maskMode: 'alpha' }

  const safeHref = String(layer.image)
    .replace(/&/g, '&amp;')
    .replace(/"/g, '&quot;')
  const invertFilter = maskSource === 'luminance-invert'
    ? '<filter id="inv"><feColorMatrix type="matrix" values="-1 0 0 0 1 0 -1 0 0 1 0 0 -1 0 1 0 0 0 1 0"/></filter>'
    : ''
  const filterAttr = maskSource === 'luminance-invert' ? ' filter="url(#inv)"' : ''
  const svg = `<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 100 100" preserveAspectRatio="none"><defs>${invertFilter}</defs><image href="${safeHref}" x="0" y="0" width="100" height="100" preserveAspectRatio="xMidYMid slice"${filterAttr}/></svg>`
  return {
    maskImage: `url("data:image/svg+xml;utf8,${encodeURIComponent(svg)}")`,
    maskMode: 'luminance',
  }
}

function SubjectLayer({ layer, active, framing, comparison }) {
  const resolved = useResolvedAsset(layer?.image)
  if (!layer?.image || resolved.status !== 'loaded' || !resolved.url) return null

  const strength = clamp(Number(layer.strength ?? 70), 0, 100) / 100
  const isOutline = layer.mode?.startsWith('outline-')
  const maskOnly = Boolean(layer.maskOnly)
  const contourFx = ELEMENTAL_CONTOUR_MODES.has(layer.mode)
  const positionX = clamp(Number(framing?.x ?? 50), 0, 100)
  const positionY = clamp(Number(framing?.y ?? 50), 0, 100)
  const zoom = clamp(Number(framing?.zoom ?? 100), 100, 220)
  const resolvedLayer = { ...layer, image: resolved.url }
  const { maskImage, maskMode } = buildMaskReference(resolvedLayer)
  // The layer is scaled by the art zoom, so its static fills would spill over the card frame: keep them to the
  // part that lines up with the artwork window (the contour FX canvas does its own limiting and may overflow).
  const hidden = 1 - 100 / zoom
  const clip = `inset(${positionY * hidden}% ${(100 - positionX) * hidden}% ${(100 - positionY) * hidden}% ${positionX * hidden}%)`

  return (
    <div
      className={`subject-effect-layer subject-${layer.mode} ${maskOnly ? 'is-mask-only' : ''} ${contourFx ? 'has-contour-fx' : ''}`}
      style={{
        '--subject-mask': maskImage,
        '--subject-mask-mode': maskMode,
        '--subject-strength': strength,
        '--subject-a': layer.foilA || '#ff4d8d',
        '--subject-b': layer.foilB || '#4df3ff',
        '--subject-c': layer.foilC || '#ffe66d',
        '--subject-position-x': `${positionX}%`,
        '--subject-position-y': `${positionY}%`,
        '--subject-art-scale': zoom / 100,
        '--subject-clip': clip,
      }}
      aria-hidden="true"
    >
      {isOutline && !maskOnly && <div className="subject-outline-glow" />}
      {!maskOnly && <img className={`subject-cutout ${isOutline ? 'subject-cutout-cover' : ''}`} src={resolved.url} alt="" draggable="false" decoding="async" />}
      <div className="subject-effect-paint" />
      <div className="subject-effect-spectrum" />
      <div className="subject-effect-grain" />
      <div className="subject-effect-glint" />
      {contourFx && <ElementalMaskFX layer={resolvedLayer} active={active} framing={{ x: positionX, y: positionY, zoom }} comparison={comparison} />}
    </div>
  )
}

// showProtection: draw the copy's sleeve / toploader / slab (off inside binder pockets, which are sleeves already)
function TradingCard({ card: inputCard, size = 'large', interactive = true, driver, showProtection = true, comparison }) {
  const card = inputCard?.variantId ? inputCard : resolveCardVariant(inputCard)
  const ref = useRef(null)
  const raf = useRef(0)
  const pending = useRef(null)
  const activeRef = useRef(false)
  const [active, setActive] = useState(false)
  const artwork = useResolvedAsset(card.image, { showOriginalWhileLoading: true })

  // Pointer position drives CSS variables directly (one write per frame, no React re-render).
  const applyVars = useCallback(() => {
    raf.current = 0
    const el = ref.current
    const p = pending.current
    if (!el || !p) return
    el.style.setProperty('--mx', `${p.x}%`)
    el.style.setProperty('--my', `${p.y}%`)
    el.style.setProperty('--rx', `${p.rx}deg`)
    el.style.setProperty('--ry', `${p.ry}deg`)
    el.style.setProperty('--tx', `${p.tx}px`)
    el.style.setProperty('--ty', `${p.ty}px`)
  }, [])

  const onMove = (event) => {
    if (!interactive || !ref.current) return
    const rect = ref.current.getBoundingClientRect()
    const x = clamp(((event.clientX - rect.left) / rect.width) * 100, 0, 100)
    const y = clamp(((event.clientY - rect.top) / rect.height) * 100, 0, 100)
    pending.current = { x, y, rx: ((50 - y) / 50) * 11, ry: ((x - 50) / 50) * 15, tx: ((x - 50) / 50) * 7, ty: ((y - 50) / 50) * 5 }
    if (!raf.current) raf.current = requestAnimationFrame(applyVars)
    if (!activeRef.current) { activeRef.current = true; setActive(true) }
  }

  const reset = () => {
    cancelAnimationFrame(raf.current)
    raf.current = 0
    pending.current = { x: 50, y: 50, rx: 0, ry: 0, tx: 0, ty: 0 }
    applyVars()
    activeRef.current = false
    setActive(false)
  }
  useEffect(() => () => cancelAnimationFrame(raf.current), [])
  // An enclosing inspector can drive the foil/mask light (already mapped to this face) while it owns the tilt.
  useEffect(() => {
    if (!driver) return
    return driver.subscribe(light => {
      pending.current = { x: light.x, y: light.y, rx: 0, ry: 0, tx: 0, ty: 0 }
      if (!raf.current) raf.current = requestAnimationFrame(applyVars)
      if (light.active !== activeRef.current) { activeRef.current = light.active; setActive(light.active) }
    })
  }, [driver, applyVars])
  const pointer = { active }
  const strength = clamp(Number(card.holoStrength ?? 55), 0, 100) / 100
  const hasSubjectEffects = Array.isArray(card.subjectLayers) && card.subjectLayers.some(layer => layer.image)
  const glareAlpha = pointer.active ? (0.18 * Math.max(0.25, strength)).toFixed(3) : 0
  const hoverScale = pointer.active ? 1.018 : 1
  // this copy's print imperfections (centering, offsets, foil drift) and wear; catalogue prints have none
  const condition = card.condition
  const copyStyle = conditionStyle(condition, 'front')
  const borderBase=size==='viewer'?7:size==='medium'?4:6
  const cx=copyStyle['--cx'] || 0,cy=copyStyle['--cy'] || 0
  const cutBorder=condition ? [1+cy,1-cx,1-cy,1+cx].map(ratio=>`${Math.round(borderBase*ratio)}px`).join(' ') : undefined
  const protection = showProtection ? (card.graded ? 'slab' : card.protection || 'none') : 'none'
  const artDx = Number(copyStyle['--art-dx']) || 0, artDy = Number(copyStyle['--art-dy']) || 0

  return (
    <div className={`card-stage card-stage--${size} ${protection !== 'none' ? `is-protected is-${protection}` : ''}`}>
      <article
        ref={ref}
        className={`trading-card layout-${card.layout} holo-${card.holo} ${pointer.active ? 'is-active' : ''} ${interactive ? 'is-interactive' : 'no-interaction'} ${condition ? 'has-condition' : ''} ${copyStyle['--foil-on'] ? 'has-foil-error' : ''}`}
        onPointerMove={interactive ? onMove : undefined}
        onPointerLeave={interactive ? reset : undefined}
        style={{
          '--mx': '50%',
          '--my': '50%',
          '--rx': '0deg',
          '--ry': '0deg',
          '--tx': '0px',
          '--ty': '0px',
          '--hover-scale': hoverScale,
          '--accent': card.accent,
          '--foil-a': card.foilA,
          '--foil-b': card.foilB,
          '--foil-c': card.foilC,
          '--foil-rainbow-alpha': (0.5 * strength).toFixed(3),
          '--foil-prism-alpha': (0.62 * strength).toFixed(3),
          '--foil-cosmos-alpha': (0.42 * strength).toFixed(3),
          '--foil-reverse-alpha': (0.58 * strength).toFixed(3),
          '--foil-etched-alpha': (0.5 * strength).toFixed(3),
          '--foil-aurora-alpha': (0.52 * strength).toFixed(3),
          '--foil-oilslick-alpha': (0.5 * strength).toFixed(3),
          '--sparkle-alpha': (0.78 * strength).toFixed(3),
          '--shine-alpha': (0.24 * strength).toFixed(3),
          '--noise-alpha': (0.16 * strength).toFixed(3),
          '--glare-alpha': glareAlpha,
          '--hover-active': pointer.active ? 1 : 0,
          ...copyStyle,
          borderWidth:cutBorder,
        }}
      >
        <div className="card-art-wrap" style={{ '--art-offset-x':`${artDx}%`, '--art-offset-y':`${artDy}%` }}>
          <img
            className="card-art"
            src={artwork.displayUrl || card.image}
            alt=""
            draggable="false"
            decoding="async"
            style={{
              objectPosition: `${clamp(Number(card.imagePositionX ?? 50), 0, 100)}% ${clamp(Number(card.imagePositionY ?? 50), 0, 100)}%`,
              transform: `${artDx || artDy ? `translate(${artDx}%, ${artDy}%) ` : ''}scale(${clamp(Number(card.imageZoom ?? 100), 100, 220) / 100})`,
              transformOrigin: `${clamp(Number(card.imagePositionX ?? 50), 0, 100)}% ${clamp(Number(card.imagePositionY ?? 50), 0, 100)}%`,
            }}
          />
          <div className="art-vignette" />
        </div>

        <div className="card-foil" aria-hidden="true" />
        <div className="card-shine" aria-hidden="true" />
        <div className="card-noise" aria-hidden="true" />
        <div className="card-sparkles" aria-hidden="true" />

        {hasSubjectEffects && (
          <div className="subject-layer-host">
            {card.subjectLayers.map(layer => <SubjectLayer key={layer.id} layer={layer} active={pointer.active} framing={{ x: card.imagePositionX, y: card.imagePositionY, zoom: card.imageZoom }} comparison={comparison} />)}
          </div>
        )}

        <div className="light-sweep" aria-hidden="true" />
        <ConditionOverlay condition={condition} side="front" />
        {card.manualPrint && <div className="manual-print-stamp" title={card.printedBy ? `Printed by ${card.printedBy}` : 'Manually printed card'}>MANUAL PRINT</div>}

        <header className="card-header">
          <div>
            <div className="card-kicker" style={textSectionStyle(condition,'subtitle')}>{card.subtitle}</div>
            <h2 style={textSectionStyle(condition,'title')}>{card.title}</h2>
          </div>
          <div className="hp-block" style={textSectionStyle(condition,'hp')}><small>HP</small><span className="hp-value">{card.hp}</span><img src={`/img/${card.type}.png`} alt={card.type} /></div>
        </header>

        <div className="card-info-row" style={textSectionStyle(condition,'info')}>
          <span>{card.type}</span>
          <span>{card.rarity}</span>
        </div>

        <section className="card-body">
          <p className="card-description" style={textSectionStyle(condition,'description')}>{card.description}</p>
          <div className="attacks" style={textSectionStyle(condition,'attack')}>
            {card.attacks.slice(0, 3).map((attack, index) => (
              <div className="attack" key={`${attack.name}-${index}`}>
                <div className="attack-cost" aria-label={`${attack.cost} cost`}>
                  {Array.from({ length: Math.min(Number(attack.cost) || 0, 4) }).map((_, i) => (
                    <span key={i} className="cost-pip" />
                  ))}
                </div>
                <div className="attack-copy">
                  <strong>{attack.name}</strong>
                  <small>{attack.text}</small>
                </div>
                <b>{attack.damage}</b>
              </div>
            ))}
          </div>
        </section>

        <footer className="card-footer" style={textSectionStyle(condition,'footer')}>
          <CardNumber card={card} />
          <RarityStars card={card} />
        </footer>
      </article>
      {protection !== 'none' && <ProtectionShell card={{ ...card, protection }} side="front" />}
    </div>
  )
}

export default memo(TradingCard)
