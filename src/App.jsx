import React, { useEffect, useMemo, useRef, useState } from 'react'
import TradingCard from './components/TradingCard'
import CardEditor from './components/CardEditor'
import PackSimulator from './components/PackSimulator'
import CollectiblesLab from './collectibles/CollectiblesLab'
import CollectibleOpeningOverlay from './collectibles/CollectibleOpeningOverlay'
import { listCollectibleTypes } from './collectibles/registry'
import PackOptions from './components/PackOptions'
import ManagementPanel from './components/ManagementPanel'
import VendingMapPanel from './components/VendingMapPanel'
import CraftingPanel from './components/CraftingPanel'
import ShippingCrateReveal from './collectibles/ShippingCrateReveal'
import VendingRecordsPanel from './components/VendingRecordsPanel'
import VendingRecordView from './components/VendingRecordView'
import Minigame from './minigames/Minigame'
import MinigameTestPanel from './minigames/MinigameTestPanel'
import LazyMount from './components/LazyMount'
import useConfirm from './components/useConfirm'
import CardViewer from './components/CardViewer'
import BinderView from './components/BinderView'
import CardCaseView from './components/CardCaseView'
import { renderCardIcon } from './utils/cardIcon'
import { downscaleImageUrl } from './utils/compressImage'
import GradingStation from './grading/GradingStation.jsx'
import GradeRecordLookup from './grading/GradeRecord.jsx'
import { setPrintOdds, setServerOdds } from './utils/printOdds.js'
import { setCardSets } from './utils/setNumbers.js'
import GradingLab from './grading/GradingLab.jsx'
import { copyCard, loadCopies } from './grading/standaloneCopies.js'
import { resolveAsset } from './runtime/assets'
import { HOLOS, defaultCards, newCard, normalizeCard, normalizeCards, resolveCardVariant } from './cardData'
import { bridge, isFiveM, storage } from './runtime'
import { embedTab, embedView, isEmbedded, notifyEmbedHost } from './runtime/env'
import { loadPackPrefs } from './runtime/packPrefs'
import { normalizeCatalogForRuntime } from './runtime/catalog'


export default function App() {
  const { confirm, dialog: confirmationDialog } = useConfirm()
  const [cards, setCards] = useState(() => isFiveM ? [] : structuredClone(defaultCards))
  const [savedCards, setSavedCards] = useState(() => isFiveM ? [] : structuredClone(defaultCards))
  const [runtimeInfo, setRuntimeInfo] = useState({
    runtime: isFiveM ? 'fivem' : 'standalone',
    framework: isFiveM ? 'detecting' : 'none',
    persistence: isFiveM ? 'detecting' : 'localStorage',
    inventory: isFiveM ? 'detecting' : 'none',
    capabilities: { editor: !isFiveM, catalogWrite: !isFiveM, collection: isFiveM, management: false },
  })
  const [nuiVisible, setNuiVisible] = useState(!isFiveM)
  const [catalogReady, setCatalogReady] = useState(false)
  const [catalogError, setCatalogError] = useState('')
  const [sets, setSets] = useState([])
  // real pull odds per print (footer star colours, inventory icons): from the saved catalogue and its sets.
  // Computed during render so every card drawn in this pass already sees them.
  useMemo(() => setPrintOdds(savedCards, sets), [savedCards, sets])
  useEffect(() => setCardSets(sets), [sets]) // an effect: it re-renders the cards on screen
  const [selectedId, setSelectedId] = useState(() => cards[0]?.id)
  const [selectedVariantId, setSelectedVariantId] = useState(() => cards[0]?.variants?.[0]?.id)
  const [tab, setTab] = useState('editor')
  const [system, setSystem] = useState('trading_card')
  const [collectibleDirty, setCollectibleDirty] = useState(false)
  const [collectibleBusy,setCollectibleBusy] = useState(false)
  const [objectOpenRequest,setObjectOpenRequest] = useState(null)
  const [collectibleReset,setCollectibleReset] = useState(0)
  const activeModule = listCollectibleTypes().find(module => module.id === system)
  const chooseSystem = async next => { if (next === system) return; if (collectibleDirty && !await confirm('Discard unsaved collectible, set, or container changes? Use Cancel to keep editing and Save or Revert first.')) return; guardUnsaved(() => {setCollectibleDirty(false);setCollectibleReset(current => current+1);setSystem(next);setTab('editor')}) }
  // FiveM booster pack item: centre-screen opening only (0 = normal app). Bumped for every new pack.
  const [overlayRun, setOverlayRun] = useState(0)
  // FiveM trading card item used: show just that card, large, in the centre of the screen
  const [cardView, setCardView] = useState(null)
  const [gradingView, setGradingView] = useState(null) // FiveM: the grading bench for one card item (server session)
  const [gradeRecordView, setGradeRecordView] = useState(null) // FiveM: /gradecheck cert lookup
  // FiveM binder item "View Binder" / standalone binder preview
  const [binderView, setBinderView] = useState(null)
  const [crateView, setCrateView] = useState(null) // FiveM shipping crate item: the 3D unpacking of what came out
  const [recordView, setRecordView] = useState(null) // FiveM vending registration certificate / ledger item
  const [minigameView, setMinigameView] = useState(null) // FiveM built-in skill check (client/minigames.lua)
  const oddsFetchedAt = useRef(0)
  // FiveM /cardoptions: compact player preference overlay
  const [packOptionsView, setPackOptionsView] = useState(false)
  const [binderPreview, setBinderPreview] = useState(null)
  const [saveState, setSaveState] = useState({ saving: false, error: '' })
  const [unsavedPrompt, setUnsavedPrompt] = useState(false)
  const pendingActionRef = useRef(null)
  const performCloseNui = () => (isEmbedded ? Promise.resolve(notifyEmbedHost('metaComic:embedClose')) : bridge.close()).catch(() => {}).finally(() => { setNuiVisible(false); setOverlayRun(0); setObjectOpenRequest(null); setCardView(null); setBinderView(null); setPackOptionsView(false) })
  const [previewViewer, setPreviewViewer] = useState(null)
  const importRef = useRef(null)
  const previewRef = useRef(null)
  const catalogRevision = useRef(0)

  // Embedded in another resource's NUI (exports GetEmbedUrl): open the requested view as soon as every listener is up.
  // The server still checks management permission on each request.
  useEffect(() => {
    if (!isEmbedded || !isFiveM) return undefined
    let cancelled = false
    const timer = setTimeout(async () => {
      const runtimeInfo = embedView === 'admin' ? await bridge.getInfo().catch(() => null) : null
      if (cancelled) return
      window.postMessage(embedView === 'admin'
        ? { type: 'metaComic:open', view: runtimeInfo?.capabilities?.editor ? 'editor' : 'gallery', overlay: false, mode: 'admin', tab: embedTab || undefined, runtimeInfo: runtimeInfo || undefined }
        : { type: 'metaComic:open', view: embedView, overlay: false }, '*')
      notifyEmbedHost('metaComic:embedReady', { view: embedView })
    }, 0)
    return () => { cancelled = true; clearTimeout(timer) }
  }, [])

  // FiveM: get coin bag / plushie box openings ready while idle, so using one shows it straight away.
  useEffect(() => {
    if (!isFiveM) return undefined
    const idle = window.requestIdleCallback || (fn => setTimeout(fn, 1500))
    const handle = idle(() => { loadPackPrefs().catch(() => {}); import('./collectibles/Container3D.js').then(module => module.prewarmContainerScenes()).catch(() => {}) }, { timeout: 5000 })
    return () => (window.cancelIdleCallback || clearTimeout)(handle)
  }, [])

  useEffect(() => {
    let cancelled = false
    const revision = ++catalogRevision.current
    Promise.all([
      storage.loadCatalog(defaultCards),
      bridge.getInfo().then(info => {if (!cancelled && info) setRuntimeInfo(current => ({...current,...info}));return info}).catch(() => null),
      bridge.getSets?.().then(result => {if (!cancelled && isFiveM && Array.isArray(result?.sets)) setSets(result.sets);return result}).catch(() => null),
    ]).then(([loaded, info, setResult]) => {
      if (cancelled || revision !== catalogRevision.current) return
      const normalized = normalizeCatalogForRuntime(loaded)
      if (isFiveM || normalized.length) {
        setCards(normalized)
        setSavedCards(structuredClone(normalized))
        setSelectedId(normalized[0]?.id)
        setSelectedVariantId(normalized[0]?.variants?.[0]?.id)
      }
      if (info) {
        setRuntimeInfo(current => ({ ...current, ...info }))
        if (isFiveM && info.capabilities?.editor === false) setTab(current => current === 'editor' ? 'pack' : current)
      }
      if (Array.isArray(setResult?.sets)) setSets(!isFiveM && !setResult.sets.length ? [{id:'base',name:'Base Set',code:'BASE',description:'',cardIds:normalized.map(card => card.id)}] : setResult.sets)
      setCatalogReady(true)
      setCatalogError('')
    }).catch(error => {
      if (cancelled || revision !== catalogRevision.current) return
      setCatalogReady(false)
      setCatalogError(error?.message || 'Could not load the server catalog. Reopen /cardadmin to retry.')
    })

    const unsubscribe = bridge.subscribe(message => {
      // FiveM: the server's print odds for the card stars (refreshed at most once a minute, whenever the UI opens)
      if (isFiveM && message.type === 'metaComic:open' && Date.now() - oddsFetchedAt.current > 60000) {
        oddsFetchedAt.current = Date.now()
        bridge.getPrintOdds?.().then(result => setServerOdds(result?.odds)).catch(() => {})
      }
      if (message.type === 'metaComic:collectibleContainer') {setNuiVisible(true);setOverlayRun(0);setCardView(null);setBinderView(null);setPackOptionsView(false);setObjectOpenRequest({...message,id:crypto.randomUUID()});return}

      // FiveM: the server asks for inventory icons of card prints it has no uploaded icon for yet.
      // Drawn here (works while the UI is hidden) and sent back; the server uploads them (Config.CardIcons.Mode = 'upload').
      if (message?.type === 'metaComic:renderIcons' && Array.isArray(message.items)) {
        ;(async () => {
          for (const item of message.items) {
            try {
              // coins + plushies are drawn from their 3D model; trading cards keep the 2D card icon
              const object = item.card?.collectibleType === 'challenge_coin' || item.card?.collectibleType === 'plushie'
              const data = object
                ? await import('./collectibles/Container3D.js').then(module => module.renderCollectibleIcon(item.card, Number(message.size) || 100, message.format))
                : await renderCardIcon(item.card, Number(message.size) || 100, message.format)
              await bridge.cardIcon?.(item.key, data || '') // '' = couldn't draw it, the server moves on
            } catch (error) {
              console.warn('Could not render card icon', item?.key, error)
              await bridge.cardIcon?.(item.key, '')
            }
          }
        })()
        return
      }
      // FiveM legacy artwork command (collectiblesoptimizeart): downscale one saved image here, the server uploads it.
      if (message?.type === 'metaComic:optimizeArtwork' && typeof message.id === 'string') {
        ;(async () => {
          let data = ''
          try {
            const state = await resolveAsset(message.src)
            if (state.status !== 'error' && state.url) data = await downscaleImageUrl(state.url, message.options || {})
          } catch (error) { console.warn('Could not downscale artwork', error) }
          await bridge.optimizedArtwork?.(message.id, data).catch(() => {}) // '' = keep / couldn't load: the server moves on
        })()
        return
      }
      if (message?.type === 'metaComic:open') {
        setObjectOpenRequest(null)
        setNuiVisible(true)
        setGradingView(message.overlay && message.mode === 'grading' && message.grading ? message.grading : null)
        setGradeRecordView(message.overlay && message.mode === 'gradeRecord' ? { key: Date.now(), cert: message.cert || '', found: message.found || null } : null)
        setCrateView(message.overlay && message.mode === 'crate' && message.crate ? { ...message.crate, key: Date.now() } : null)
        setRecordView(message.overlay && message.mode === 'vendingRecord' && message.record ? { ...message.record, key: Date.now() } : null)
        setMinigameView(message.overlay && message.mode === 'minigame' && message.minigame ? message.minigame : null)
        if (message.mode === 'admin') {
          setCollectibleReset(current => current + 1)
          setPackOptionsView(false)
          setOverlayRun(0)
          setCardView(null)
          setBinderView(null)
          if (message.runtimeInfo) setRuntimeInfo(current => ({ ...current, ...message.runtimeInfo }))
          const canEdit = message.runtimeInfo?.capabilities?.editor === true
          setTab(canEdit ? 'editor' : 'management')
          if (typeof message.tab === 'string' && message.tab) setTab(message.tab) // exports OpenAdmin(tab) / embed ?tab=

          // /cardadmin is expected to reflect the server's current catalog, sets and
          // permissions every time it opens, not only what existed when the hidden
          // NUI page first booted.
          ;(async () => {
            const revision = ++catalogRevision.current
            const [info, catalogResult, setResult] = await Promise.all([
              bridge.getInfo().then(info => {if (info) setRuntimeInfo(current => ({...current,...info}));return info}).catch(() => null),
              bridge.getCatalog().catch(error => ({ error: error?.message || 'Could not load the server catalog.' })),
              bridge.getSets?.().then(result => {if (Array.isArray(result?.sets)) setSets(result.sets);return result}).catch(() => null),
            ])
            if (revision !== catalogRevision.current) return
            if (info) setRuntimeInfo(current => ({ ...current, ...info }))
            if (Array.isArray(catalogResult?.cards)) {
              const normalized = normalizeCatalogForRuntime(catalogResult.cards)
              setCards(normalized)
              setSavedCards(structuredClone(normalized))
              setSelectedId(current => normalized.some(card => card.id === current) ? current : normalized[0]?.id)
              setSelectedVariantId(current => normalized.some(card => card.variants.some(variant => variant.id === current)) ? current : normalized[0]?.variants?.[0]?.id)
              setCatalogReady(true)
              setCatalogError('')
            } else {
              setCatalogReady(false)
              setCatalogError(catalogResult?.error || 'The server returned an invalid card catalog.')
            }
            if (Array.isArray(catalogResult?.sets)) setSets(catalogResult.sets)
            else if (Array.isArray(setResult?.sets)) setSets(setResult.sets)
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
        } else if (message.overlay && (message.mode === 'grading' || message.mode === 'gradeRecord' || message.mode === 'crate' || message.mode === 'vendingRecord' || message.mode === 'minigame')) {
          setPackOptionsView(false)
          setOverlayRun(0)
          setCardView(null)
          setBinderView(null)
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
      if (message?.type === 'metaComic:close') { setNuiVisible(false); setOverlayRun(0); setObjectOpenRequest(null); setCardView(null); setBinderView(null); setPackOptionsView(false); setGradingView(null); setGradeRecordView(null); setCrateView(null); setRecordView(null); setMinigameView(null) }
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
  const managementAllowed = !isFiveM || runtimeInfo.capabilities?.management === true
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
    if (isFiveM && !catalogReady) {
      setSaveState({ saving: false, error: 'Load the server catalog before saving. Reopen /cardadmin to retry.' })
      return false
    }
    if (!selected || !selectedDirty || saveState.saving) return !selectedDirty
    setSaveState({ saving: true, error: '' })
    // A catalog reload still in flight (e.g. started when /cardadmin opened) was read before this save:
    // letting it land afterwards replaced the saved card with the old copy and the editor kept saying "Unsaved changes".
    ++catalogRevision.current
    const snapshot = normalizeCard(structuredClone(selected))
    const savedJson = JSON.stringify(snapshot)
    const result = await storage.saveCard(snapshot)
    if (!result?.ok) {
      setSaveState({ saving: false, error: result?.error || 'Could not save card.' })
      return false
    }
    // edits made while the save was travelling stay in the editor (and keep it marked unsaved)
    setCards(current => current.map(card => card.id === snapshot.id && JSON.stringify(normalizeCard(card)) === savedJson ? structuredClone(snapshot) : card))
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
    if (savedSelected && !await confirm(`Delete ${selected.title}? This removes it from the saved catalog.`, 'Delete')) return
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
    if ((!nuiVisible && isFiveM) || objectOpenRequest) return undefined
    const onKeyDown = event => {
      if ((event.ctrlKey || event.metaKey) && event.key.toLowerCase() === 's' && tab === 'editor') {
        event.preventDefault()
        saveSelected()
        return
      }
      if (isFiveM && event.key === 'Escape' && !event.defaultPrevented) { // a page can keep Escape (minigame test)
        event.preventDefault()
        requestCloseNui()
      }
    }
    window.addEventListener('keydown', onKeyDown)
    return () => window.removeEventListener('keydown', onKeyDown)
  }, [nuiVisible, objectOpenRequest, tab, selectedDirty, selectedId, cards, savedCards, saveState.saving])

  useEffect(() => {
    if (isFiveM || !selectedDirty) return undefined
    const onBeforeUnload = event => { event.preventDefault(); event.returnValue = '' }
    window.addEventListener('beforeunload', onBeforeUnload)
    return () => window.removeEventListener('beforeunload', onBeforeUnload)
  }, [selectedDirty])

  const exportJson = () => {
    const blob = new Blob([JSON.stringify(cards, null, 2)], { type: 'application/json' })
    const url = URL.createObjectURL(blob)
    const a = document.createElement('a')
    a.href = url
    a.download = 'meta-comic-cards-v3.json'
    a.click()
    URL.revokeObjectURL(url)
  }

  const importJson = async (file) => {
    if (!file) return
    await importJsonText(await file.text())
  }
  const importJsonText = async (text) => {
    const parsed = JSON.parse(text)
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

  // FiveM's game browser can't open a file dialog, so there the JSON is pasted into a box instead.
  const [pasteImport, setPasteImport] = useState(null)
  const requestImport = () => guardUnsaved(() => isFiveM ? setPasteImport('') : importRef.current?.click())
  const submitPasteImport = () => importJsonText(pasteImport).then(() => setPasteImport(null)).catch(err => alert(err.message))

  const reset = () => guardUnsaved(async () => {
    if (!await confirm('Replace the saved catalog with the bundled demo cards?', 'Replace')) return
    const fresh = structuredClone(defaultCards)
    const result = await storage.saveCatalog(fresh)
    if (!result?.ok) { setSaveState({ saving: false, error: result?.error || 'Could not reset catalog.' }); return }
    setCards(fresh)
    setSavedCards(structuredClone(fresh))
    setSelectedId(fresh[0].id)
    setSelectedVariantId(fresh[0].variants[0].id)
  })

  if (isFiveM && !nuiVisible) return null

  if (objectOpenRequest) return <CollectibleOpeningOverlay key={objectOpenRequest.id} request={objectOpenRequest} onClose={performCloseNui} />
  if (crateView) return <ShippingCrateReveal key={crateView.key} crate={crateView} onClose={performCloseNui} />
  // skill check: hidden straight away on a result (the game script then closes the page, or opens the next game)
  if (minigameView) return <Minigame key={minigameView.id} config={minigameView} onResult={success => { bridge.minigameResult?.({ id: minigameView.id, success }).catch?.(() => {}); setMinigameView(null); if (isFiveM) setNuiVisible(false) }} />
  if (recordView) return <VendingRecordView key={recordView.key} record={recordView} onClose={performCloseNui} />

  // /cardoptions: only the compact preference panel, with the game visible around it
  if (isFiveM && packOptionsView) return <PackOptions onClose={performCloseNui} />
  // booster pack item used in FiveM: only the centre-screen opening, no app shell
  if (overlayRun) return <PackSimulator cards={savedCards} sets={sets} overlay overlayKey={overlayRun} onClose={performCloseNui} />
  // FiveM binder item: only the binder, the game stays visible around it
  if (isFiveM && binderView) return binderView.kind === 'case'
    ? <CardCaseView binder={binderView} onClose={performCloseNui} />
    : <BinderView binder={binderView} onClose={performCloseNui} />
  // FiveM /gradecheck: look up a slab's grading record by cert number
  if (gradeRecordView) return <GradeRecordLookup key={gradeRecordView.key} initial={gradeRecordView.found} initialCert={gradeRecordView.cert}
    lookup={cert => bridge.gradingRecord(cert)} onClose={performCloseNui} />
  // FiveM "Grade card" item button: the grading bench, every mark checked by the server
  if (gradingView) {
    const sessionId = gradingView.sessionId
    const session = {
      maxWrong: gradingView.maxWrong,
      gradeAdjust: gradingView.gradeAdjust,
      mark: mark => bridge.gradingMark({ sessionId, mark }),
      submit: ({ grade } = {}) => bridge.gradingSubmit({ sessionId, grade }),
      cancel: () => bridge.gradingCancel({ sessionId }),
    }
    return <GradingStation key={sessionId} card={gradingView.card} reference={gradingView.reference} session={session} debug={gradingView.debug === true} debugFlaws={gradingView.debugFlaws} onDone={performCloseNui} onCancel={performCloseNui} />
  }
  // trading card item used in FiveM: only that card, centred
  if (cardView) {
    const { card, shownBy } = cardView
    // your own raw card spun hard in the viewer: the server may crease / bend / tear it, and sends the result back
    const onRough = !shownBy && isFiveM && (!card.collectibleType || card.collectibleType === 'trading_card')
      ? () => bridge.roughHandling?.().then(response => { if (response?.card) setCardView(current => current && { ...current, card: response.card }) }).catch(() => {})
      : undefined
    return (
      <>
        {shownBy && <div className="card-shown-by">{shownBy} is showing you a card</div>}
        <CardViewer bare card={card} onClose={performCloseNui} onRough={onRough} title={`${card.title || 'Card'} ${card.variantName || ''}`.trim()} />
      </>
    )
  }

  return (
    <main className={`app-shell ${isFiveM ? 'runtime-fivem' : 'runtime-standalone'}`}>
      <nav className="topbar">
        <div className="brand"><div className="brand-mark">M</div><div><strong>Meta Comic Collectibles</strong><span>{isFiveM ? `FiveM NUI · ${runtimeInfo.framework}` : 'Standalone React App'}</span></div></div>
        <div className="top-actions">
          {editorAllowed && system === 'trading_card' && <>
            <button className="ghost" onClick={requestImport} disabled={isFiveM && !catalogReady}>Import JSON</button>
            <input ref={importRef} hidden type="file" accept="application/json" onChange={e => importJson(e.target.files?.[0]).catch(err => alert(err.message))} />
            <button className="ghost" onClick={exportJson}>Export JSON</button>
            {pasteImport !== null && <div className="paste-import" role="dialog" aria-label="Import card JSON">
              <textarea autoFocus rows="8" placeholder="Paste the exported card JSON here (Ctrl+V)" value={pasteImport} onChange={e => setPasteImport(e.target.value)} />
              <div><button className="ghost" onClick={() => setPasteImport(null)}>Cancel</button><button className="primary" disabled={!pasteImport.trim()} onClick={submitPasteImport}>Import</button></div>
            </div>}
            <button className="primary" onClick={add} disabled={isFiveM && !catalogReady}>+ New card</button>
          </>}
          {isFiveM && <button className="ghost" onClick={requestCloseNui}>Close</button>}
        </div>
      </nav>

      <label className="collectible-system-selector">Collectible system<select aria-label="Collectible system" disabled={collectibleBusy} value={system} onChange={event => chooseSystem(event.target.value)}>{listCollectibleTypes().map(module => <option key={module.id} value={module.id} disabled={isFiveM && module.id !== 'trading_card' && !runtimeInfo.capabilities?.collectibles}>{module.label}</option>)}</select></label>
      <section className="hero-copy">
        <div>
          {isFiveM && !catalogReady && !catalogError && <p role="status">Loading saved card catalog…</p>}
          <span className="eyebrow">{isFiveM ? 'FiveM NUI runtime' : 'Standalone runtime'}</span>
          <h1>{system !== 'trading_card' ? 'Create a collection beyond trading cards.' : 'Print variants, layered subject masks, and animated pack-opening tests.'}</h1>
          <p>{system !== 'trading_card' ? 'Design challenge coins and plushies, choose what goes into each container, and discover your next collectible.' : 'Each character can now have multiple pullable prints, each with its own rarity, layout, artwork override, full-card foil strength, and any number of transparent subject-mask layers for outline or subject-only foil effects.'}</p>
        </div>
        {system !== 'trading_card' ? <div className="hero-badges"><span>{activeModule?.label}</span><span>{activeModule?.container?.label}</span><span>Saved collections</span></div> : <div className="hero-badges"><span>{cards.length} base cards</span><span>{allPrints.length} print variants</span><span>{runtimeInfo.framework || 'none'} / {runtimeInfo.persistence || 'none'}</span></div>}
      </section>

      <div className="mode-tabs">
        {editorAllowed && <button className={tab === 'editor' ? 'active' : ''} onClick={() => changeTab('editor')}>Editor</button>}
        {managementAllowed && <button className={tab === 'management' ? 'active' : ''} onClick={() => changeTab('management')}>Sets & containers</button>}
        {managementAllowed && system === 'trading_card' && <button className={tab === 'vending' ? 'active' : ''} onClick={() => changeTab('vending')}>Vending machines</button>}
        {managementAllowed && system === 'trading_card' && <button className={tab === 'records' ? 'active' : ''} onClick={() => changeTab('records')}>Machine records</button>}
        {managementAllowed && <button className={tab === 'crafting' ? 'active' : ''} onClick={() => changeTab('crafting')}>Crafting</button>}
        {managementAllowed && <button className={tab === 'minigames' ? 'active' : ''} onClick={() => changeTab('minigames')}>Minigames</button>}
        <button className={tab === 'gallery' ? 'active' : ''} onClick={() => changeTab('gallery')}>Collection</button>
        <button className={tab === 'effects' ? 'active' : ''} onClick={() => changeTab('effects')}>Effect sampler</button>
        {!isFiveM && system === 'trading_card' && <button className={tab === 'grading' ? 'active' : ''} onClick={() => changeTab('grading')}>Grading</button>}
        <button className={tab === 'pack' ? 'active' : ''} onClick={() => changeTab('pack')}>{system === 'trading_card' ? 'Pack / box lab' : system === 'plushie' ? 'Box / case lab' : 'Bag / box lab'}</button>
      </div>

      {system === 'trading_card' && <>
      {catalogError && <div className="management-message" role="alert">{catalogError} Reopen /cardadmin to retry.</div>}
      {tab === 'editor' && catalogReady && !selected && <div className="management-message">No cards are saved in the server catalog. Add a new card or import a catalog.</div>}
      {tab === 'editor' && (!isFiveM || catalogReady) && selected && selectedPrint && (
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
            catalog={savedCards}
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
            onPrint={isFiveM && runtimeInfo.capabilities?.manualPrint === true ? async variant => { await bridge.printCard({ baseCardId: selected.id, variantId: variant.id }); return `Printed ${selected.title} — ${variant.name}. The item is marked MANUAL PRINT.` } : undefined}
          />
        </section>
      )}

      {tab === 'management' && managementAllowed && <ManagementPanel cards={cards} sets={sets} onSetsChange={setSets} />}
      {tab === 'vending' && managementAllowed && <VendingMapPanel />}
      {tab === 'records' && managementAllowed && <VendingRecordsPanel />}
      {tab === 'crafting' && managementAllowed && <CraftingPanel sets={sets} />}
      {tab === 'minigames' && managementAllowed && <MinigameTestPanel />}

      {tab === 'gallery' && (
        <div className="binder-preview-bar">
          <span>Binder preview: every print in collection order, 9 per sleeve page (in FiveM the order comes from the binder item's slots).</span>
          <button className="ghost" onClick={() => setBinderPreview({ label: 'Binder preview', slots: Math.max(18, Math.ceil(allPrints.length / 18) * 18), pockets: allPrints.slice(8).map((card, i) => ({ slot: i + 1, card })), hand: [...loadCopies().map(copy => copyCard(copy, cards)).filter(Boolean).slice(0, 8), ...allPrints.slice(0, 4)].map((card, i) => ({ slot: i + 1, card })) })}>View binder</button>
          <button className="ghost" onClick={() => setBinderPreview({ kind: 'case', label: 'Card case preview', slots: 48, pockets: allPrints.slice(4, 34).map((card, i) => ({ slot: i + 1 + Math.floor(i / 4) * 2, card })), hand: [...loadCopies().map(copy => copyCard(copy, cards)).filter(Boolean).slice(0, 8), ...allPrints.slice(0, 4)].map((card, i) => ({ slot: i + 1, card })) })}>View card case</button>
        </div>
      )}
      {binderPreview && (binderPreview.kind === 'case'
        ? <CardCaseView binder={binderPreview} onClose={() => setBinderPreview(null)} />
        : <BinderView binder={binderPreview} onClose={() => setBinderPreview(null)} />)}

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

      {tab === 'pack' && <PackSimulator cards={savedCards} sets={sets} />}
      {tab === 'grading' && !isFiveM && <GradingLab cards={savedCards} />}
      </>}
      <div hidden={system === 'trading_card'}><CollectiblesLab typeId={system === 'trading_card' ? 'challenge_coin' : system} activeTab={tab} onNavigate={changeTab} onDirty={setCollectibleDirty} onBusy={setCollectibleBusy} confirm={confirm} resetToken={collectibleReset} canProduce={runtimeInfo.capabilities?.createSealed === true} canPrint={isFiveM && runtimeInfo.capabilities?.manualPrint === true} /></div>

      {previewViewer && (
        <CardViewer
          card={previewViewer.card}
          originRect={previewViewer.originRect}
          onClose={() => setPreviewViewer(null)}
          title={`${previewViewer.card.title} ${previewViewer.card.variantName}`}
        />
      )}

      {confirmationDialog}
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
