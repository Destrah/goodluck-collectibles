import React, { useEffect, useState } from 'react'
import TradingCard from './TradingCard'

const VIEWER_W = 390
const VIEWER_H = 546

// bare: no backdrop at all (FiveM card item: only the card is drawn, the game stays visible around it)
export default function CardViewer({ card, originRect, onClose, title = 'Card detail', bare = false }) {
  const [active, setActive] = useState(false)

  useEffect(() => {
    const frame = requestAnimationFrame(() => requestAnimationFrame(() => setActive(true)))
    return () => cancelAnimationFrame(frame)
  }, [])

  const close = () => {
    setActive(false)
    window.setTimeout(onClose, 260)
  }

  const sourceCenterX = originRect ? originRect.left + originRect.width / 2 : window.innerWidth / 2
  const sourceCenterY = originRect ? originRect.top + originRect.height / 2 : window.innerHeight / 2
  const startX = sourceCenterX - window.innerWidth / 2
  const startY = sourceCenterY - window.innerHeight / 2
  const startScaleX = originRect ? originRect.width / VIEWER_W : 0.86
  const startScaleY = originRect ? originRect.height / VIEWER_H : 0.86

  return (
    <div className={`card-viewer ${active ? 'active' : ''} ${bare ? 'card-viewer--bare' : ''}`} onClick={close} role="dialog" aria-modal="true" aria-label={title}>
      {!bare && <div className="card-viewer-backdrop" />}
      <div
        className="card-viewer-shell"
        style={{
          '--viewer-start-x': `${startX}px`,
          '--viewer-start-y': `${startY}px`,
          '--viewer-start-scale-x': startScaleX,
          '--viewer-start-scale-y': startScaleY,
        }}
        onClick={event => event.stopPropagation()}
      >
        <button className="viewer-close" onClick={close} aria-label="Close large card">×</button>
        <TradingCard card={card} size="viewer" interactive />
      </div>
    </div>
  )
}
