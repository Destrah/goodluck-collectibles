import React, { useEffect, useMemo, useRef, useState } from 'react'
import TradingCard from './components/TradingCard'
import CardEditor from './components/CardEditor'
import PackSimulator from './components/PackSimulator'
import PackOptions from './components/PackOptions'
import ManagementPanel from './components/ManagementPanel'
import LazyMount from './components/LazyMount'
import CardViewer from './components/CardViewer'
import BinderView from './components/BinderView'
import { renderCardIcon } from './utils/cardIcon'
import { HOLOS, defaultCards, newCard, normalizeCard, normalizeCards, resolveCardVariant } from './cardData'
import { bridge, isFiveM, storage } from './runtime'

function mergeBuiltInDemoVariants(cards) {
  const demosByTitle = new Map(defaultCards
    .filter(card => card.title === 'Nate Gatto' || card.title === 'Holo Mask Lab')
    .map(card => [card.title, card]))

  const merged = cards.map(card => {
    const demo = demosByTitle.get(card.title)
    if (!demo) return card
    const existingNames = new Set(card.variants.map(variant => variant.name))
    const additions = demo.variants
      .filter(variant => !existingNames.has(variant.name))
      .map(variant => structuredClone(variant))
    return additions.length ? { ...card, variants: [...card.variants, ...additions] } : card
  })

  for (const [title, demo] of demosByTitle) {
    if (!merged.some(card => card.title === title)) merged.push(structuredClone(demo))
  }
  return merged
}

export default function App() {
  const [cards, setCards] = useState(() => structuredClone(defaultCards))
  const [savedCards, setSavedCards] = useState(() => structuredClone(defaultCards))
  const [runtimeInfo, setRuntimeInfo] = useState({
    runtime: isFiveM ? 'fivem' : 'standalone',
    framework: isFiveM ? 'detecting' : 'none',
    persistence: isFiveM ? 'detecting' : 'localStorage',
    inventory: isFiveM ? 'detecting' : 'none',
    capabilities: { editor: !isFiveM, catalogWrite: !isFiveM, collection: isFiveM, management: false },
  })
  const [nuiVisible, setNuiVisible] = useState(!isFiveM)
  const [catalogReady, setCatalogReady] = useState(false)
  const [sets, setSets] = useState([])
  const [selectedId, setSelectedId] = useState(() => cards[0]?.id)
  const [selectedVariantId, setSelectedVariantId] = useState(() => cards[0]?.variants?.[0]?.id)
  const [tab, setTab] = useState('editor')
  // FiveM booster pack item: centre-screen opening only (0 = normal app). Bumped for every new pack.
  const [overlayRun, setOverlayRun] = useState(0)
  // FiveM trading card item used: show just that card, large, in the centre of the screen
  const [cardView, setCardView] = useState(null)
  // FiveM binder item "View Binder" / standalone binder preview
  const [binderView, setBinderView] = useState(null)
  // FiveM /cardoptions: compact player preference overlay
  const [packOptionsView, setPackOptionsView] = useState(false)
  const [binderPreview, setBinderPreview] = useState(null)
  const [saveState, setSaveState] = useState({ saving: false, error: '' })
  const [unsavedPrompt, setUnsavedPrompt] = useState(false)
  const pendingActionRef = useRef(null)
  const performCloseNui = () => bridge.close().catch(() => {}).finally(() => { setNuiVisible(false); setOverlayRun(0); setCardView(null); setBinderView(null); setPackOptionsView(false) })
  const [previewViewer, setPreviewViewer] = useState(null)
  const importRef = useRef(null)
  const previewRef = useRef(null)

  useEffect(() => {
    let cancelled = false
    Promise.all([
      storage.loadCatalog(defaultCards),
      bridge.getInfo().catch(() => null),
      bridge.getSets?.().catch(() => null),
    ]).then(([loaded, info, setResult]) => {
      if (cancelled) return
      const normalized = mergeBuiltInDemoVariants(normalizeCards(loaded))
      if (normalized.length) {
        setCards(normalized)
        setSavedCards(structuredClone(normalized))
        setSelectedId(normalized[0]?.id)
        setSelectedVariantId(normalized[0]?.variants?.[0]?.id)
      }
      if (info) {
        setRuntimeInfo(current => ({ ...current, ...info }))
        if (isFiveM && info.capabilities?.editor === false) setTab(current => current === 'editor' ? 'pack' : current)
      }
      if (Array.isArray(setResult?.sets)) setSets(setResult.sets)
      setCatalogReady(true)
    })

    const unsubscribe = bridge.subscribe(message => {
      // FiveM: the server asks for inventory icons of card prints it has no uploaded icon for yet.
      // Drawn here (works while the UI is hidden) and sent back; the server uploads them (Config.CardIcons.Mode = 'upload').
      if (message?.type === 'rushCards:renderIcons' && Array.isArray(message.items)) {
        ;(async () => {
          for (const item of message.items) {
            try {
              const data = await renderCardIcon(item.card, Number(message.size) || 100, message.format)
              await bridge.cardIcon?.(item.key, data || '') // '' = couldn't draw it, the server moves on
            } catch (error) {
              console.warn('Could not render card icon', item?.key, error)
              await bridge.cardIcon?.(item.key, '')
            }
          }
        })()
        return
      }
      if (message?.type === 'rushCards:open') {
        setNuiVisible(true)
        if (message.mode === 'admin') {
          setPackOptionsView(false)
          setOverlayRun(0)
          setCardView(null)
          setBinderView(null)
          if (message.runtimeInfo) setRuntimeInfo(current => ({ ...current, ...message.runtimeInfo }))
          const canEdit = message.runtimeInfo?.capabilities?.editor === true
          setTab(canEdit ? 'editor' : 'management')

          // /cardadmin is expected to reflect the server's current catalog, sets and
          // permissions every time it opens, not only what existed when the hidden
          // NUI page first booted.
          ;(async () => {
            const [info, catalogResult, setResult] = await Promise.all([
              bridge.getInfo().catch(() => null),
              bridge.getCatalog().catch(() => null),
              bridge.getSets?.().catch(() => null),
            ])
            if (info) setRuntimeInfo(current => ({ ...current, ...info }))
            if (Array.isArray(catalogResult?.cards) && catalogResult.cards.length) {
              const normalized = mergeBuiltInDemoVariants(normalizeCards(catalogResult.cards))
              setCards(normalized)
              setSavedCards(structuredClone(normalized))
              setSelectedId(current => normalized.some(card => card.id === current) ? current : normalized[0]?.id)
              setSelectedVariantId(current => normalized.some(card => card.variants.some(variant => variant.id === current)) ? current : normalized[0]?.variants?.[0]?.id)
            }
            if (Array.isArray(setResult?.sets)) setSets(setResult.sets)
          })()
        } else if (message.overlay && message.mode === 'options') {
          setOverlayRun(0)
          setCardView(null)
          setBinderView(null)
          setPackOptionsView(true)
        } else if (message.overlay && message.mode === 'management') {
          setPackOptionsView(false)
          setOverlayRun(0)
          setCardView(null)
          setBinderView(null)
          setTab('management')
        } else if (message.overlay && message.mode === 'binder' && message.binder) {
          setPackOptionsView(false)
          setOverlayRun(0)
          setCardView(null)
          setBinderView(message.binder)
        } else if (message.overlay && message.mode === 'card' && message.card) {
          setPackOptionsView(false)
          setOverlayRun(0)
          setBinderView(null)
          setCardView({ card: message.card, shownBy: message.shownBy || '' })
        } else if (message.overlay) {
          setPackOptionsView(false)
          setCardView(null)
          setBinderView(null)
          setOverlayRun(run => run + 1)
        } else {
          setPackOptionsView(false)
          setOverlayRun(0)
          setCardView(null)
          setBinderView(null)
          if (message.view) setTab(message.view)
        }
      }
      if (message?.type === 'rushCards:close') { setNuiVisible(false); setOverlayRun(0); setCardView(null); setBinderView(null); setPackOptionsView(false) }
    })
    bridge.uiReady?.().catch?.(() => {}) // FiveM only: listening now, so the server can send icon work
    return () => {
      cancelled = true
      unsubscribe?.()
    }
  }, [])


  useEffect(() => {
    if (!cards.some(card => card.id === selectedId)) {
      setSelectedId(cards[0]?.id)
      setSelectedVariantId(cards[0]?.variants?.[0]?.id)
      return
    }
    const selected = cards.find(card => card.id === selectedId)
    if (selected && !selected.variants.some(variant => variant.id === selectedVariantId)) {
      setSelectedVariantId(selected.variants[0]?.id)
    }
  }, [cards, selectedId, selectedVariantId])

  const editorAllowed = !isFiveM || runtimeInfo.capabilities?.editor === true
  const managementAllowed = isFiveM && runtimeInfo.capabilities?.management === true
  const selected = cards.find(card => card.id === selectedId) || cards[0]
  const savedSelected = selected ? savedCards.find(card => card.id === selected.id) : null
  const selectedDirty = Boolean(selected) && (!savedSelected || JSON.stringify(normalizeCard(selected)) !== JSON.stringify(normalizeCard(savedSelected)))
  const selectedIsNew = Boolean(selected) && !savedSelected
  const selectedPrint = selected ? resolveCardVariant(selected, selectedVariantId) : null
  const allPrints = useMemo(() => cards.flatMap(card => card.variants.map(variant => resolveCardVariant(card, variant))), [cards])

  const runPendingAction = () => {
    const action = pendingActionRef.current
    pendingActionRef.current = null
    if (typeof action === 'function') action()
  }

  const guardUnsaved = action => {
    if (!selectedDirty) { action(); return }
    pendingActionRef.current = action
    setUnsavedPrompt(true)
  }

  const saveSelected = async () => {
    if (!selected || !selectedDirty || saveState.saving) return !selectedDirty
    setSaveState({ saving: true, error: '' })
    const snapshot = normalizeCard(structuredClone(selected))
    const result = await storage.saveCard(snapshot)
    if (!result?.ok) {
      setSaveState({ saving: false, error: result?.error || 'Could not save card.' })
      return false
    }
    setCards(current => current.map(card => card.id === snapshot.id ? structuredClone(snapshot) : card))
    setSavedCards(current => {
      const exists = current.some(card => card.id === snapshot.id)
      return exists
        ? current.map(card => card.id === snapshot.id ? structuredClone(snapshot) : card)
        : [...current, structuredClone(snapshot)]
    })
    setSaveState({ saving: false, error: '' })
    return true
  }

  const revertSelected = () => {
    if (!selected) return
    if (savedSelected) {
      const restored = structuredClone(savedSelected)
      setCards(current => current.map(card => card.id === selected.id ? restored : card))
      setSelectedVariantId(current => restored.variants.some(variant => variant.id === current) ? current : restored.variants[0]?.id)
    } else {
      const remaining = cards.filter(card => card.id !== selected.id)
      const fallback = savedCards[0] || remaining[0]
      setCards(remaining)
      setSelectedId(fallback?.id)
      setSelectedVariantId(fallback?.variants?.[0]?.id)
    }
    setSaveState({ saving: false, error: '' })
  }

  const saveAndContinue = async () => {
    if (!await saveSelected()) return
    setUnsavedPrompt(false)
    runPendingAction()
  }

  const discardAndContinue = () => {
    revertSelected()
    setUnsavedPrompt(false)
    queueMicrotask(runPendingAction)
  }

  const requestCloseNui = () => guardUnsaved(performCloseNui)

  const chooseCardNow = id => {
    const card = cards.find(item => item.id === id)
    setSelectedId(id)
    setSelectedVariantId(card?.variants?.[0]?.id)
  }
  const chooseCard = id => {
    if (id === selectedId) return
    guardUnsaved(() => chooseCardNow(id))
  }

  const changeSelected = next => {
    setSaveState(current => current.error ? { ...current, error: '' } : current)
    setCards(current => current.map(card => card.id === next.id ? normalizeCard(next) : card))
  }

  const addNow = () => {
    const card = newCard()
    setCards(current => [...current, card])
    setSelectedId(card.id)
    setSelectedVariantId(card.variants[0].id)
    setTab('editor')
  }
  const add = () => guardUnsaved(addNow)

  const duplicateNow = () => {
    const source = savedCards.find(card => card.id === selected?.id) || selected
    if (!source) return
    const card = structuredClone(source)
    card.id = crypto.randomUUID()
    card.title = `${source.title} Copy`
    card.variants = card.variants.map(variant => ({
      ...variant,
      id: crypto.randomUUID(),
      subjectLayers: (variant.subjectLayers || []).map(layer => ({ ...layer, id: crypto.randomUUID() })),
    }))
    setCards(current => [...current, card])
    setSelectedId(card.id)
    setSelectedVariantId(card.variants[0].id)
    setTab('editor')
  }
  const duplicate = () => guardUnsaved(duplicateNow)

  const remove = async () => {
    if (!selected || cards.length === 1 || saveState.saving) return
    if (savedSelected && !window.confirm(`Delete ${selected.title}? This removes it from the saved catalog.`)) return
    if (savedSelected) {
      setSaveState({ saving: true, error: '' })
      const result = await storage.deleteCard(selected.id)
      if (!result?.ok) { setSaveState({ saving: false, error: result?.error || 'Could not delete card.' }); return }
    }
    const remaining = cards.filter(card => card.id !== selected.id)
    const remainingSaved = savedCards.filter(card => card.id !== selected.id)
    setCards(remaining)
    setSavedCards(remainingSaved)
    const fallback = remaining[0]
    setSelectedId(fallback?.id)
    setSelectedVariantId(fallback?.variants?.[0]?.id)
    setSaveState({ saving: false, error: '' })
  }

  const changeTab = nextTab => {
    if (nextTab === tab) return
    guardUnsaved(() => setTab(nextTab))
  }

  useEffect(() => {
    if (!nuiVisible && isFiveM) return undefined
    const onKeyDown = event => {
      if ((event.ctrlKey || event.metaKey) && event.key.toLowerCase() === 's' && tab === 'editor') {
        event.preventDefault()
        saveSelected()
        return
      }
      if (isFiveM && event.key === 'Escape') {
        event.preventDefault()
        requestCloseNui()
      }
    }
    window.addEventListener('keydown', onKeyDown)
    return () => window.removeEventListener('keydown', onKeyDown)
  }, [nuiVisible, tab, selectedDirty, selectedId, cards, savedCards, saveState.saving])

  useEffect(() => {
    if (!selectedDirty) return undefined
    const onBeforeUnload = event => { event.preventDefault(); event.returnValue = '' }
    window.addEventListener('beforeunload', onBeforeUnload)
    return () => window.removeEventListener('beforeunload', onBeforeUnload)
  }, [selectedDirty])

  const exportJson = () => {
    const blob = new Blob([JSON.stringify(cards, null, 2)], { type: 'application/json' })
    const url = URL.createObjectURL(blob)
    const a = document.createElement('a')
    a.href = url
    a.download = 'rush-trading-cards-v3.json'
    a.click()
    URL.revokeObjectURL(url)
  }

  const importJson = async (file) => {
    if (!file) return
    const parsed = JSON.parse(await file.text())
    if (!Array.isArray(parsed)) throw new Error('Expected an array of cards')
    const normalized = normalizeCards(parsed)
    if (!normalized.length) throw new Error('The card array is empty')
    const result = await storage.saveCatalog(normalized)
    if (!result?.ok) throw new Error(result?.error || 'Could not import catalog')
    setCards(normalized)
    setSavedCards(structuredClone(normalized))
    setSelectedId(normalized[0].id)
    setSelectedVariantId(normalized[0].variants[0]?.id)
  }

  const requestImport = () => guardUnsaved(() => importRef.current?.click())

  const reset = () => guardUnsaved(async () => {
    if (!window.confirm('Replace the saved catalog with the bundled demo cards?')) return
    const fresh = structuredClone(defaultCards)
    const result = await storage.saveCatalog(fresh)
    if (!result?.ok) { setSaveState({ saving: false, error: result?.error || 'Could not reset catalog.' }); return }
    setCards(fresh)
    setSavedCards(structuredClone(fresh))
    setSelectedId(fresh[0].id)
    setSelectedVariantId(fresh[0].variants[0].id)
  })

  if (isFiveM && !nuiVisible) return null

  // /cardoptions: only the compact preference panel, with the game visible around it
  if (isFiveM && packOptionsView) return <PackOptions onClose={performCloseNui} />
  // booster pack item used in FiveM: only the centre-screen opening, no app shell
  if (overlayRun) return <PackSimulator cards={cards} overlay overlayKey={overlayRun} onClose={performCloseNui} />
  // FiveM binder item: only the binder, the game stays visible around it
  if (isFiveM && binderView) return <BinderView binder={binderView} onClose={performCloseNui} />
  // trading card item used in FiveM: only that card, centred
  if (cardView) {
    const { card, shownBy } = cardView
    return (
      <>
        {shownBy && <div className="card-shown-by">{shownBy} is showing you a card</div>}
        <CardViewer bare card={card} onClose={performCloseNui} title={`${card.title || 'Card'} ${card.variantName || ''}`.trim()} />
      </>
    )
  }

  return (
    <main className={`app-shell ${isFiveM ? 'runtime-fivem' : 'runtime-standalone'}`}>
      <nav className="topbar">
        <div className="brand"><div className="brand-mark">R</div><div><strong>Rush Trading Cards</strong><span>{isFiveM ? `FiveM NUI · ${runtimeInfo.framework}` : 'Standalone React App'}</span></div></div>
        <div className="top-actions">
          {editorAllowed && <>
            <button className="ghost" onClick={requestImport}>Import JSON</button>
            <input ref={importRef} hidden type="file" accept="application/json" onChange={e => importJson(e.target.files?.[0]).catch(err => alert(err.message))} />
            <button className="ghost" onClick={exportJson}>Export JSON</button>
            <button className="primary" onClick={add}>+ New card</button>
          </>}
          {isFiveM && <button className="ghost" onClick={requestCloseNui}>Close</button>}
        </div>
      </nav>

      <section className="hero-copy">
        <div>
          <span className="eyebrow">{isFiveM ? 'FiveM NUI runtime' : 'Standalone runtime'}</span>
          <h1>Print variants, layered subject masks, and animated pack-opening tests.</h1>
          <p>Each character can now have multiple pullable prints, each with its own rarity, layout, artwork override, full-card foil strength, and any number of transparent subject-mask layers for outline or subject-only foil effects.</p>
        </div>
        <div className="hero-badges"><span>{cards.length} base cards</span><span>{allPrints.length} print variants</span><span>{runtimeInfo.framework || 'none'} / {runtimeInfo.persistence || 'none'}</span></div>
      </section>

      <div className="mode-tabs">
        {editorAllowed && <button className={tab === 'editor' ? 'active' : ''} onClick={() => changeTab('editor')}>Editor</button>}
        {managementAllowed && <button className={tab === 'management' ? 'active' : ''} onClick={() => changeTab('management')}>Sets & production</button>}
        <button className={tab === 'gallery' ? 'active' : ''} onClick={() => changeTab('gallery')}>Print collection</button>
        <button className={tab === 'effects' ? 'active' : ''} onClick={() => changeTab('effects')}>Effect sampler</button>
        <button className={tab === 'pack' ? 'active' : ''} onClick={() => changeTab('pack')}>Pack / box lab</button>
      </div>

      {tab === 'editor' && selected && selectedPrint && (
        <section className="workspace">
          <aside className="card-list">
            <div className="list-heading"><span>Base cards</span><small>{cards.length}</small></div>
            {cards.map(card => (
              <button key={card.id} className={`card-list-item ${card.id === selected.id ? 'selected' : ''}`} onClick={() => chooseCard(card.id)}>
                <img src={card.image} alt="" />
                <div><strong>{card.title}</strong><span>{card.variants.length} print{card.variants.length === 1 ? '' : 's'}</span></div>
              </button>
            ))}
            <button className="reset-link" onClick={reset}>Reset v3 demo cards</button>
          </aside>

          <section className="preview-column">
            <div className="preview-label"><span>Interactive preview</span><small>{selectedPrint.variantName} · holo {selectedPrint.holoStrength}% · click to enlarge</small></div>
            <div
              ref={previewRef}
              className="editor-preview-clickable"
              role="button"
              tabIndex={0}
              onClick={() => {
                const rect = previewRef.current?.querySelector('.trading-card')?.getBoundingClientRect()
                setPreviewViewer({ card: selectedPrint, originRect: rect })
              }}
              onKeyDown={event => {
                if (event.key === 'Enter' || event.key === ' ') {
                  event.preventDefault()
                  const rect = previewRef.current?.querySelector('.trading-card')?.getBoundingClientRect()
                  setPreviewViewer({ card: selectedPrint, originRect: rect })
                }
              }}
            >
              <TradingCard card={selectedPrint} />
            </div>
          </section>

          <CardEditor
            card={selected}
            selectedVariantId={selectedVariantId}
            onSelectVariant={setSelectedVariantId}
            onChange={changeSelected}
            onDelete={remove}
            onDuplicate={duplicate}
            dirty={selectedDirty}
            isNew={selectedIsNew}
            saving={saveState.saving}
            saveError={saveState.error}
            onSave={saveSelected}
            onRevert={revertSelected}
          />
        </section>
      )}

      {tab === 'management' && managementAllowed && <ManagementPanel cards={cards} sets={sets} onSetsChange={setSets} />}

      {tab === 'gallery' && (
        <div className="binder-preview-bar">
          <span>Binder preview: every print in collection order, 9 per sleeve page (in FiveM the order comes from the binder item's slots).</span>
          <button className="ghost" onClick={() => setBinderPreview({ label: 'Binder preview', slots: Math.max(18, Math.ceil(allPrints.length / 18) * 18), pockets: allPrints.map((card, i) => ({ slot: i + 1, card })) })}>View binder</button>
        </div>
      )}
      {binderPreview && <BinderView binder={binderPreview} onClose={() => setBinderPreview(null)} />}

      {tab === 'gallery' && (
        <section className="gallery-grid">
          {allPrints.map(print => (
            <div className="gallery-item" data-print-key={`${print.baseCardId}::${print.variantId}`} key={`${print.baseCardId}-${print.variantId}`} onClick={() => guardUnsaved(() => { setSelectedId(print.baseCardId); setSelectedVariantId(print.variantId); setTab('editor') })}>
              <LazyMount><TradingCard card={print} size="medium" /></LazyMount>
              <div><strong>{print.title} — {print.variantName}</strong><span>{print.rarity}</span></div>
            </div>
          ))}
        </section>
      )}

      {tab === 'effects' && selectedPrint && (
        <section className="effect-section">
          <div className="effect-intro">
            <span className="eyebrow">Same print, different surface</span>
            <h2>Full-card holographic sampler</h2>
            <p>These previews temporarily swap only the full-card finish. Your transparent subject layers remain stacked above it, which lets you test combinations such as a light rainbow card surface plus a gold character outline.</p>
          </div>
          <div className="effect-grid">
            {HOLOS.map(({ value, label }) => (
              <div className="effect-card" key={value}><LazyMount><TradingCard card={{ ...selectedPrint, holo: value }} size="medium" /></LazyMount><strong>{label}</strong></div>
            ))}
          </div>
        </section>
      )}

      {tab === 'pack' && <PackSimulator cards={cards} />}

      {previewViewer && (
        <CardViewer
          card={previewViewer.card}
          originRect={previewViewer.originRect}
          onClose={() => setPreviewViewer(null)}
          title={`${previewViewer.card.title} ${previewViewer.card.variantName}`}
        />
      )}

      {unsavedPrompt && (
        <div className="unsaved-overlay" role="presentation">
          <section className="unsaved-dialog" role="dialog" aria-modal="true" aria-labelledby="unsaved-title">
            <span className="eyebrow">Unsaved card changes</span>
            <h3 id="unsaved-title">Save changes to {selected?.title || 'this card'}?</h3>
            <p>Your current edits only exist in the local editor draft. Save them, discard them, or stay here and keep editing.</p>
            {saveState.error && <div className="editor-save-error">{saveState.error}</div>}
            <div className="unsaved-actions">
              <button className="ghost" disabled={saveState.saving} onClick={() => { pendingActionRef.current = null; setUnsavedPrompt(false) }}>Cancel</button>
              <button className="danger ghost" disabled={saveState.saving} onClick={discardAndContinue}>Discard</button>
              <button className="primary" disabled={saveState.saving} onClick={saveAndContinue}>{saveState.saving ? 'Saving…' : 'Save & continue'}</button>
            </div>
          </section>
        </div>
      )}

      <footer className="app-footer">{isFiveM ? `FiveM · framework ${runtimeInfo.framework} · inventory ${runtimeInfo.inventory} · persistence ${runtimeInfo.persistence}` : 'Standalone browser mode · edits persist locally until you export JSON.'}</footer>
    </main>
  )
}
