import React, { memo, useEffect, useMemo, useRef, useState } from 'react'
import { createPortal } from 'react-dom'
import { defaultCards } from '../cardData'
import { loadCraftingPrints } from './craftingPrints'
import FittedCard from '../components/FittedCard'
import { mountCraftWorkbench } from './craftWorkbench'
import './craftWorkbench.css'
import './craftingMinigame.css'
import { bridge, storage } from '../runtime'
import { isFiveM } from '../runtime/env'

const Face = memo(function Face({ card, target }) {
  const [size, setSize] = useState({ width: target.clientWidth, height: target.clientHeight })
  useEffect(() => {
    let frame = 0
    const observer = new ResizeObserver(() => {
      cancelAnimationFrame(frame)
      frame = requestAnimationFrame(() => {
        const width = target.clientWidth, height = target.clientHeight
        if (width > 0 && height > 0) setSize(previous => previous.width === width && previous.height === height ? previous : { width, height })
      })
    })
    observer.observe(target)
    return () => { observer.disconnect(); cancelAnimationFrame(frame) }
  }, [target])
  return createPortal(<FittedCard card={card} width={size.width} height={size.height} reserve="none" />, target)
})

// Reuse TradingCard, including its remote artwork/masks, without screenshots or baked inventory icons.
export default function CraftingMinigame({ config, done }) {
  const root = useRef(null), doneRef = useRef(done)
  doneRef.current = done
  const [faces, setFaces] = useState([])
  const [liveCards, setLiveCards] = useState(null)
  const cards = useMemo(() => Array.isArray(config.cards) ? config.cards : liveCards?.cards || [], [config.cards, liveCards])
  useEffect(() => {
    if (Array.isArray(config.cards)) return
    let cancelled = false
    const load = async () => {
      if (isFiveM) return bridge.getCraftingPrints({ setId: config.setId, cols: config.cols, rows: config.rows })
      const [catalog, result] = await Promise.all([storage.loadCatalog(defaultCards), bridge.getSets()])
      const sets = result.sets?.length ? result.sets : [{ id: 'base', name: 'Base Set', cardIds: catalog.map(card => card.id) }]
      return { ok: true, ...await loadCraftingPrints(config.setId, sets, catalog) }
    }
    load().then(result => {
      if (cancelled) return
      if (!result?.ok || !result.cards?.length) doneRef.current(false, { error: 'No printable cards in this set.' })
      else setLiveCards(result)
    }).catch(error => { if (!cancelled) doneRef.current(false, { error: error.message }) })
    return () => { cancelled = true }
  }, [config.cards, config.setId])
  useEffect(() => {
    const node = root.current
    if (!cards.length && !Array.isArray(config.cards)) { node.textContent = 'Preparing the print sheet…'; return }
    node.innerHTML = '<div class="shop"></div>'
    const cols = Math.max(1, Math.min(10, Math.floor(Number(config.cols) || 5)))
    const rows = Math.max(1, Math.min(10, Math.floor(Number(config.rows) || 3)))
    if (cols * rows > 60 || cols * rows % 5 !== 0) { doneRef.current(false, { error: 'Sheet total must be divisible by five (maximum 60).' }); return }
    const cleanup = mountCraftWorkbench(node, { ...config, setName: config.setName || liveCards?.setName, cols, rows, cards }, (success, detail) => doneRef.current(success, detail))
    // Physical cards retain their portal container through sheet/strip/card/pack transitions.
    // Moving an existing host does not remount TradingCard or restart its mask/foil layers.
    const hosts = new Map()
    let queued = false, disposed = false
    const update = () => {
      queued = false
      if (disposed || !node.isConnected) return
      let changed = false
      for (const slot of node.querySelectorAll('[data-print]')) {
        const key = slot.dataset.face
        const card = cards[Number(slot.dataset.print)]
        if (!key || !card) continue
        let entry = hosts.get(key)
        if (!entry) {
          const target = document.createElement('span')
          target.className = 'cw-face-host'
          entry = { key, target, card }
          hosts.set(key, entry); changed = true
        } else if (entry.card !== card) { entry.card = card; changed = true }
        if (entry.target.parentElement !== slot) slot.append(entry.target)
      }
      if (changed) setFaces([...hosts.values()].map(entry => ({ ...entry })))
    }
    const isSlot = element => element.nodeType === 1 && (element.matches('[data-print]') || element.querySelector('[data-print]'))
    const observer = new MutationObserver(records => {
      if (!queued && records.some(record => !record.target.closest?.('.cw-face') && [...record.addedNodes, ...record.removedNodes].some(isSlot))) {
        queued = true; queueMicrotask(update)
      }
    })
    observer.observe(node, { childList: true, subtree: true })
    update()
    return () => { disposed = true; observer.disconnect(); cleanup(); hosts.clear(); setFaces([]) }

  }, [config, cards, liveCards])
  return <><div id="craft-batch" ref={root} className="cw-runtime" />{faces.filter(face => face.card).map(face => <Face key={face.key} {...face} />)}</>
}
