import { useEffect, useMemo, useRef, useState } from 'react'
import CollectibleView from './CollectibleView'
import CollectibleEditor from './CollectibleEditor'
import RotatableCollectible from './RotatableCollectible'
import { listCollectibleTypes } from './registry.js'
import { loadCollectibles, saveCollectibles, saveDefinition, openContainer, openOuterContainer, openSealedContainer, saveSet } from './standaloneStore.js'
import { allPrints, FINISHES, printsOf, RARITIES, rarityKeyOf, withPrint } from './prints.js'
import CardViewer from '../components/CardViewer'
import ContainerOpening3D, { ContainerPreview3D } from './ContainerOpening3D'
import { CONTAINER_LOOKS, normalizeLook } from './container3dOptions'
import { useResolvedAsset } from '../runtime/assets'
import { bridge, isFiveM } from '../runtime'
import './collectibles.css'
import { loadPackPrefs } from '../runtime/packPrefs'
import { openingLook } from './containerPrefs.js'
import { MixedCrateCreator, cratesFor, createCrates, useShippingCrates } from '../components/ShippingCrateTools'

const modules = listCollectibleTypes().filter(module => module.authorable)
const clone = value => structuredClone(value)

// Older definitions have no prints: give them one "Standard" print (id 'base' keeps their inventory icon key).
const withPrints = item => Array.isArray(item.prints) && item.prints.length ? item
  : { ...item, prints: [{ id: 'base', name: 'Standard', rarityKey: rarityKeyOf(item.rarityKey || item.rarity), chanceWeight: 100 }] }

function Thumb({ item }) {
  const art = useResolvedAsset(item.image, { showOriginalWhileLoading: true })
  const coin = item.collectibleType === 'challenge_coin'
  return <span className={`collectible-thumb ${coin ? 'is-coin' : 'is-plush'}`} style={{ '--object-accent': item.accent || '#c9a34d' }}>
    {item.image ? <img src={art.displayUrl || item.image} alt="" /> : <b aria-hidden="true">{coin ? '★' : '🧸'}</b>}
  </span>
}

// Debounced copy of a value, so the live 3D preview rebuilds after typing pauses rather than on every keystroke.
function useSettled(value, delay = 350) {
  const [settled, setSettled] = useState(value)
  useEffect(() => { const timer = setTimeout(() => setSettled(value), delay); return () => clearTimeout(timer) }, [value, delay])
  return settled
}

export default function CollectiblesLab({ typeId, activeTab, onNavigate, onDirty, onBusy, confirm, resetToken, openRequest, canProduce = false, canPrint = false }) {
  const [loaded] = useState(() => { try { return { data: isFiveM ? {definitions:[],sets:[],containers:{},instances:[],sealed:[]} : loadCollectibles() } } catch (error) { return { error: error.message } } })
  const [data, setData] = useState(loaded.data)
  const [draft, setDraft] = useState(null)
  const [printId, setPrintId] = useState('')
  const [containerDraft, setContainerDraft] = useState(null)
  const view = { editor:'editor', management:'management', gallery:'collection', effects:'effects', pack:'container' }[activeTab]
  const [setEdit,setSetDraft] = useState(null)
  const [viewer,setViewer] = useState(null)
  const [run,setRun] = useState(null)
  const [opening,setOpening] = useState(false)
  const [error, setError] = useState('')
  const [message, setMessage] = useState('')
  const [busy,setBusy] = useState(false)
  const [amount,setAmount] = useState(1)
  // version (design) of the sealed items being created; blank = the saved look
  const [sealedStyle,setSealedStyle] = useState('')
  const [sealedOuterStyle,setSealedOuterStyle] = useState('')
  const lastOpen = useRef(null)
  const generation = useRef(0)
  useEffect(() => {onBusy?.(busy)},[busy,onBusy])
  const [selectedSetId,setSelectedSetId] = useState('')
  const module = modules.find(entry => entry.id === typeId)
  const innerKind = module?.container.kind === 'bag' ? 'bag' : 'box'
  const definitions = data?.definitions.filter(item => item.collectibleType === typeId) || []
  const saved = data?.definitions.find(item => item.id === draft?.id)
  const dirty = useMemo(() => draft && JSON.stringify(draft) !== JSON.stringify(saved && withPrints(saved)), [draft,saved])
  const containerDirty = useMemo(() => containerDraft && JSON.stringify(containerDraft) !== JSON.stringify(data?.containers[typeId]), [containerDraft,data?.containers,typeId])
  const setDirty = useMemo(() => setEdit && JSON.stringify(setEdit) !== JSON.stringify(data?.sets?.find(set => set.id === setEdit.id)), [setEdit,data?.sets])
  useEffect(() => {onDirty?.(!!(dirty || containerDirty || setDirty))},[dirty,containerDirty,setDirty,onDirty])
  useEffect(() => {setDraft(null); setContainerDraft(null); setSetDraft(null); setRun(null);setViewer(null);setOpening(false);setMessage('')},[typeId,resetToken])
  useEffect(() => {
    if (isFiveM) return
    const warn = event => { if (dirty || containerDirty || setDirty) { event.preventDefault(); event.returnValue = '' } }
    window.addEventListener('beforeunload', warn)
    return () => window.removeEventListener('beforeunload', warn)
  }, [dirty, containerDirty,setDirty])
  // open the first saved collectible in the editor, like the card editor does
  useEffect(() => { if (!draft && definitions[0]) { setDraft(withPrints(clone(definitions[0]))); setPrintId(printsOf(withPrints(definitions[0]))[0].id) } }, [definitions.length, typeId, draft])

  useEffect(() => {
    if (!isFiveM) return
    let alive=true
    const revision=++generation.current
    bridge.getCollectibles().then(response => {
      if(!alive || revision!==generation.current)return
      const first=response.data.definitions.find(item => item.collectibleType===typeId)
      const next=first ? withPrints(clone(first)) : null
      setData(response.data);setDraft(next);setPrintId(next?.prints[0]?.id || '');setError('')
    }).catch(err => {if(alive && revision===generation.current)setError(err.message)})
    return () => {alive=false}
  },[typeId,resetToken])
  useEffect(() => {
    if (!isFiveM || !openRequest || openRequest.typeId !== typeId || lastOpen.current===openRequest.id) return
    lastOpen.current=openRequest.id
    startOpening(openRequest.outer,undefined,openRequest.slot)
  },[openRequest,typeId])
  const previewSource = useMemo(() => draft ? withPrint(draft, printsOf(draft).find(entry => entry.id === printId) || printsOf(draft)[0]) : null, [draft, printId])
  const preview = useSettled(previewSource)
  const crateInfo = useShippingCrates(isFiveM && canProduce)
  if (loaded.error) return <div role="alert">{loaded.error}</div>
  const attempt = async action => { setBusy(true); try { await action(); setError('') } catch (err) { setError(err.message) } finally {setBusy(false)} }
  const commit = async (next,operation) => { ++generation.current; const stored = isFiveM ? ((await bridge.saveCollectible(operation)).data || clone(next)) : saveCollectibles(next); setData(stored);return stored }
  const chooseItem = async item => { if (dirty && !await confirm('Discard unsaved collectible changes?')) return; const next = withPrints(clone(item)); setDraft(next); setPrintId(next.prints[0].id) }
  const newItem = () => chooseItem({ id: crypto.randomUUID(), collectibleType: typeId, title: `New ${module.singular}`, description: '', image: '', chanceWeight: 100, accent: '#c9a34d', backImage:'', finish:'none', finishStrength:60, prints:[{ id: crypto.randomUUID(), name: 'Standard', rarityKey: 'common', chanceWeight: 100 }] })
  const duplicateItem = () => draft && chooseItem({ ...clone(draft), id: crypto.randomUUID(), title: `${draft.title} Copy`, prints: printsOf(draft).map(entry => ({ ...entry, id: crypto.randomUUID() })) })
  const saveItem = () => attempt(async () => {
    const first = printsOf(draft)[0]
    const value = { ...draft, rarityKey: rarityKeyOf(first.rarityKey), rarity: RARITIES.find(entry => entry.value === rarityKeyOf(first.rarityKey))?.label }
    const sent=JSON.stringify(draft)
    const stored=await commit(saveDefinition(data, value), { kind:'definition', value })
    // take the server's copy, unless the draft was edited while the save was travelling (it then stays unsaved)
    setDraft(current => current && JSON.stringify(current) !== sent ? current : withPrints(clone(stored.definitions.find(item => item.id===value.id))))
  })
  const deleteItem = async () => { if (saved && await confirm(`Delete ${saved.title} from definitions? Pulled copies will remain.`, 'Delete')) attempt(async () => { await commit({ ...data, definitions: data.definitions.filter(item => item.id !== saved.id), sets:(data.sets||[]).map(set => ({...set,itemIds:set.itemIds.filter(id => id !== saved.id)})) },{kind:'delete',id:saved.id}); setDraft(null) }) }
  const typeSets = data.sets?.filter(set => set.collectibleType === typeId) || []
  const box = containerDraft || data.containers[typeId] || { ...clone(module.container), setId:typeSets[0]?.id || '', itemIds: definitions.map(item => item.id) }
  const selectedSet = setEdit || typeSets.find(set => set.id === selectedSetId) || typeSets[0]
  const inspect = item => setViewer(item)
  const startOpening = (outer = false, sealedId, slot) => attempt(async () => {
    if (isFiveM) { ++generation.current; const [response,prefs]=await Promise.all([bridge.openCollectibleContainer({typeId,outer,slot:slot || data.sealed.find(item => item.instanceId === sealedId)?.slot}),loadPackPrefs()]);setData(current => response.data || {...current,sealed:(current.sealed || []).filter(item => item.instanceId !== sealedId)});setOpening(true);setRun({...response.run,playbackLook:openingLook(response.run,prefs)});return }
    const result = sealedId ? openSealedContainer(data,sealedId) : outer ? openOuterContainer(data,typeId) : openContainer(data,typeId)
    await commit(result.data); setOpening(true)
    const container = sealedId ? data.sealed.find(item => item.instanceId === sealedId).containerSnapshot : data.containers[typeId]
    setRun({id:crypto.randomUUID(),typeId,container:clone(container),outer,items:result.pulled || result.sealed})
  })
  const editBox = patch => setContainerDraft({ ...clone(box), ...patch })
  const saveContainers = () => attempt(async () => {if (!box.label.trim() || !typeSets.some(set => set.id === box.setId && set.itemIds.length)) throw new Error('Choose a saved set with collectibles before saving the container.');const value={...clone(box),kind:module.container.kind,count:Math.min(24,Math.max(1,Math.floor(Number(box.count)||1))),outer:{...(box.outer || module.container.outer),count:Math.min(100,Math.max(1,Math.floor(Number(box.outer?.count || module.container.outer.count)||1)))}};await commit({...data,containers:{...data.containers,[typeId]:value}},{kind:'container',typeId,value});setContainerDraft(null);setMessage('Containers saved.')})
  const saveCurrentSet = () => attempt(async () => {await commit(saveSet(data,selectedSet),{kind:'set',value:selectedSet});setSelectedSetId(selectedSet.id);setSetDraft(null);setMessage(`${selectedSet.name} saved.`)})
  const createSealed = outer => attempt(async () => { const response = await bridge.createCollectibleContainer({typeId,amount:Number(amount)||1,outer,style:chosenStyle,outerStyle:chosenOuterStyle}); setData(response.data); setMessage(`Created ${amount} ${outer ? box.outer?.label || module.container.outer.label : box.label} item${Number(amount) === 1 ? '' : 's'} in your inventory.`) })
  // shipping crates of this collectible pull from the set selected here (its saved, non-empty version)
  const typeCrates = cratesFor(crateInfo.crates, typeId)
  const crateSet = typeSets.find(set => set.id === selectedSet?.id && set.itemIds.length > 0)
  const runCrate = make => attempt(async () => setMessage(await make()))
  // 3D design + opening animation, saved on the container so every player (and each sealed snapshot) gets it
  const innerLook = normalizeLook(innerKind, box.look)
  const outerLook = normalizeLook('case', box.outer?.look)
  const chosenStyle = CONTAINER_LOOKS[innerKind].styles.some(entry => entry.id === sealedStyle) ? sealedStyle : innerLook.style
  const chosenOuterStyle = CONTAINER_LOOKS.case.styles.some(entry => entry.id === sealedOuterStyle) ? sealedOuterStyle : outerLook.style
  const lookGroup = (kind, value, onChange, title) => <>
    <div className="pk-set-group"><span className="pk-set-title">{title} design</span><div className="pk-set-row">{CONTAINER_LOOKS[kind].styles.map(option => <button key={option.id} type="button" className={`pk-opt ${value.style === option.id ? 'selected' : ''}`} disabled={opening} onClick={() => onChange({...value,style:option.id})}>{option.label}</button>)}</div></div>
    <div className="pk-set-group"><span className="pk-set-title">{title} opening</span><div className="pk-set-row">{CONTAINER_LOOKS[kind].animations.map(option => <button key={option.id} type="button" className={`pk-opt ${value.animation === option.id ? 'selected' : ''}`} disabled={opening} onClick={() => onChange({...value,animation:option.id})}>{option.label}</button>)}</div></div>
  </>
  const instances = data.instances.filter(item => item.collectibleType === typeId)
  const prints = allPrints(definitions)
  const tierCounts = RARITIES.map(tier => ({ ...tier, prints: prints.filter(entry => entry.rarityKey === tier.value).length, items: new Set(prints.filter(entry => entry.rarityKey === tier.value).map(entry => entry.definitionId)).size }))
  const sampleItem = preview || (definitions[0] && withPrint(definitions[0], printsOf(definitions[0])[0])) || { collectibleType: typeId, title: module.singular }
  const containerNoun = module.container.kind === 'bag' ? 'coin bags' : 'plushie boxes'
  const sealedList = (data.sealed || []).filter(item => item.collectibleType === typeId)
  const canManage = !isFiveM || canProduce

  return <section className="collectibles-lab">
    {error && <div className="management-message" role="alert">{error}</div>}

    {view === 'editor' && <>
      {!draft && <div className="management-message">No {module.label.toLowerCase()} are saved yet. <button className="primary" onClick={newItem}>+ New {module.singular.toLowerCase()}</button></div>}
      {draft && <section className="workspace">
        <aside className="card-list">
          <div className="list-heading"><span>{module.label}</span><small>{definitions.length}</small></div>
          {definitions.map(item => (
            <button key={item.id} className={`card-list-item ${item.id === draft.id ? 'selected' : ''}`} onClick={() => chooseItem(item)}>
              <Thumb item={withPrint(withPrints(item), printsOf(withPrints(item))[0])} />
              <div><strong>{item.title}</strong><span>{printsOf(item).length} print{printsOf(item).length === 1 ? '' : 's'}</span></div>
            </button>
          ))}
          {!saved && <button className="card-list-item selected"><Thumb item={sampleItem} /><div><strong>{draft.title || 'New'}</strong><span>unsaved</span></div></button>}
          <button className="reset-link" onClick={newItem}>+ New {module.singular.toLowerCase()}</button>
        </aside>

        <section className="preview-column collectible-preview-column">
          <div className="preview-label"><span>Interactive 3D preview</span><small>{sampleItem.printName || 'Standard'} · {sampleItem.rarity || 'Common'} · drag to turn</small></div>
          {preview && <RotatableCollectible key={preview.collectibleType} item={preview} />}
          <button className="ghost small-button collectible-enlarge" onClick={() => preview && inspect(preview)}>Enlarge</button>
        </section>

        <CollectibleEditor module={module} draft={draft} printId={printId} onSelectPrint={setPrintId} onChange={setDraft}
          onSave={saveItem} onRevert={() => { if (saved) { const next = withPrints(clone(saved)); setDraft(next); if (!next.prints.some(entry => entry.id === printId)) setPrintId(next.prints[0].id) } else setDraft(null) }} onDelete={deleteItem} onDuplicate={duplicateItem}
          dirty={!!dirty} isNew={!saved} saving={busy} saveError={error}
          onPrint={canPrint ? async print => { await bridge.printCollectible({ typeId, definitionId: draft.id, printId: print.id }); return `Printed ${draft.title} — ${print.name}. The item is marked MANUAL PRINT.` } : undefined} />
      </section>}
    </>}

    {view === 'management' && <section className="management-page">
      <div className="management-heading">
        <div><span className="eyebrow">{isFiveM ? 'Restricted FiveM tools' : `${module.singular} sets and containers`}</span><h2>Sets & containers</h2><p>Create sets, choose their {module.label.toLowerCase()}, and configure or manufacture their sealed {containerNoun} and {(box.outer?.label || module.container.outer.label).toLowerCase()}es.</p></div>
        <button className="primary" disabled={busy || !selectedSet || !setDirty} onClick={saveCurrentSet}>Save set</button>
        <button disabled={busy || !setDirty} onClick={() => setSetDraft(null)}>Revert</button>
      </div>
      {message && <div className="management-message">{message}</div>}
      <div className="management-grid">
        <aside className="set-list-panel">
          <div className="management-panel-title"><strong>Series / sets</strong><button className="ghost small-button" onClick={async () => {if (!setDirty || await confirm('Discard unsaved set changes?')) setSetDraft({id:crypto.randomUUID(),collectibleType:typeId,name:'New Set',itemIds:[]})}}>+ Set</button></div>
          <div className="set-list">
            {typeSets.map(set => <button key={set.id} className={set.id === selectedSet?.id ? 'active' : ''} onClick={async () => {if (!setDirty || await confirm('Discard unsaved set changes?')) {setSelectedSetId(set.id);setSetDraft(null)}}}><strong>{set.name}</strong><span>{set.itemIds.length} {module.label.toLowerCase()}</span></button>)}
            {setEdit && !typeSets.some(set => set.id === setEdit.id) && <button className="active"><strong>{setEdit.name}</strong><span>unsaved</span></button>}
          </div>
        </aside>
        <div className="management-main">
          {selectedSet && <>
            <div className="management-card">
              <div className="management-panel-title"><div><strong>Set details</strong><span>Containers draw their {module.label.toLowerCase()} from one set.</span></div></div>
              <div className="form-grid compact-grid"><label className="field span-2"><span>Name</span><input value={selectedSet.name} onChange={e => setSetDraft({...selectedSet,name:e.target.value})} /></label></div>
            </div>
            <div className="management-card">
              <div className="management-panel-title"><div><strong>{module.label} in {selectedSet.name}</strong><span>Only checked {module.label.toLowerCase()} can be pulled. Their prints still follow their rarity and weights.</span></div></div>
              <div className="set-card-grid">
                {definitions.map(item => <label key={item.id} className={`set-card-option ${selectedSet.itemIds.includes(item.id) ? 'selected' : ''}`}><input type="checkbox" checked={selectedSet.itemIds.includes(item.id)} onChange={event => setSetDraft({...selectedSet,itemIds:event.target.checked ? [...selectedSet.itemIds,item.id] : selectedSet.itemIds.filter(id => id !== item.id)})} /><Thumb item={withPrint(withPrints(item), printsOf(withPrints(item))[0])} /><span><strong>{item.title}</strong><small>{printsOf(item).length} print{printsOf(item).length === 1 ? '' : 's'}</small></span></label>)}
              </div>
            </div>
          </>}
          <div className="management-card">
            <div className="management-panel-title"><div><strong>Containers</strong><span>Sealed items keep a copy of these settings when they are made.</span></div></div>
            <div className="form-grid compact-grid">
              <label className="field"><span>Set</span><select value={box.setId} onChange={event => editBox({setId:event.target.value})}><option value="">Choose a set</option>{typeSets.map(set => <option key={set.id} value={set.id}>{set.name}</option>)}</select></label>
              <label className="field"><span>Inner container name</span><input value={box.label} onChange={event => editBox({label:event.target.value})} /></label>
              <label className="field"><span>{module.label} per {module.container.kind}</span><input type="number" min="1" max="24" value={box.count} onChange={event => editBox({count:Number(event.target.value)})} /></label>
              <label className="field"><span>Outer case name</span><input value={box.outer?.label || module.container.outer.label} onChange={event => editBox({outer:{...(box.outer || module.container.outer),label:event.target.value}})} /></label>
              <label className="field"><span>Inner containers per outer case</span><input type="number" min="1" max="100" value={box.outer?.count || module.container.outer.count} onChange={event => editBox({outer:{...(box.outer || module.container.outer),count:Number(event.target.value)}})} /></label>
            </div>
            <div className="production-row"><button className="primary" disabled={busy || !containerDirty} onClick={saveContainers}>Save containers</button><button disabled={!containerDirty} onClick={() => setContainerDraft(null)}>Revert</button></div>
          </div>
          {isFiveM && canProduce && <div className="management-card production-card">
            <div className="management-panel-title"><div><strong>Create sealed inventory items</strong><span>Outer case → sealed {containerNoun} → pulled {module.label.toLowerCase()}.</span></div></div>
            <div className="production-row">
              <label className="field"><span>{box.label} version</span><select value={chosenStyle} onChange={e => setSealedStyle(e.target.value)}>{CONTAINER_LOOKS[innerKind].styles.map(entry => <option key={entry.id} value={entry.id}>{entry.label}</option>)}</select></label>
              <label className="field"><span>{box.outer?.label || module.container.outer.label} version</span><select value={chosenOuterStyle} onChange={e => setSealedOuterStyle(e.target.value)}>{CONTAINER_LOOKS.case.styles.map(entry => <option key={entry.id} value={entry.id}>{entry.label}</option>)}</select></label>
              <label className="field amount-field"><span>Amount</span><input type="number" min="1" max="100" value={amount} onChange={e => setAmount(Math.max(1, Number(e.target.value) || 1))} /></label>
              <button className="primary" disabled={busy || !data.containers[typeId]} onClick={() => createSealed(false)}>Create {box.label}</button>
              <button className="primary" disabled={busy || !data.containers[typeId]} onClick={() => createSealed(true)}>Create {box.outer?.label || module.container.outer.label}</button>
              {typeCrates.map(crate => <button key={crate.id} className="primary" disabled={busy || !data.containers[typeId] || !crateSet} onClick={() => runCrate(() => createCrates(crate, amount, { [typeId]: crateSet.id }))}>Create {crate.label}</button>)}
            </div>
            {typeCrates.length > 0 && <small>{crateSet ? `Crates hold ${crateSet.name} ${containerNoun} (up to 20 per click).` : 'Save the selected set with some collectibles to create crates from it.'}</small>}
          </div>}
          {isFiveM && canProduce && <MixedCrateCreator crates={crateInfo.crates} sets={crateInfo.sets} busy={busy} onCreate={runCrate} />}
        </div>
      </div>
    </section>}

    {view === 'collection' && <>
      <div className="binder-preview-bar"><span>Every print of every {module.singular.toLowerCase()}, then the copies you have pulled. Click a print to edit it.</span></div>
      <section className="gallery-grid">
        {prints.map(print => (
          <div className="gallery-item" key={`${print.definitionId}-${print.printId}`} onClick={() => { const item = definitions.find(entry => entry.id === print.definitionId); if (item) { chooseItem(item); setPrintId(print.printId); onNavigate?.('editor') } }}>
            <CollectibleView item={print} />
            <div><strong>{print.title} — {print.printName}</strong><span>{print.rarity}</span></div>
          </div>
        ))}
      </section>
      {!!instances.length && <section className="gallery-grid collectible-acquired">
        <div className="effect-intro"><span className="eyebrow">Acquired collection</span><h2>{instances.length} pulled</h2><p>These copies keep their original appearance after definition edits.</p></div>
        {instances.map(item => <div className="gallery-item" key={item.instanceId} onClick={() => inspect(item)}><CollectibleView item={item} /><div><strong>{item.title}{item.printName && item.printName !== 'Standard' ? ` — ${item.printName}` : ''}</strong><span>{item.rarity}</span></div></div>)}
      </section>}
    </>}

    {view === 'effects' && <section className="effect-section">
      <div className="effect-intro">
        <span className="eyebrow">Same print, different finish</span>
        <h2>{module.singular} finish sampler</h2>
        <p>These previews swap only the finish of {sampleItem.title} — {sampleItem.printName || 'Standard'}. Click one to inspect it in 3D. Nothing is saved.</p>
      </div>
      <div className="effect-grid">
        {FINISHES.map(({ value, label }) => <div className="effect-card" key={value} onClick={() => inspect({ ...sampleItem, finish: value })}><CollectibleView item={{ ...sampleItem, finish: value }} /><strong>{label}</strong></div>)}
      </div>
    </section>}

    {view === 'container' && <section className="pack-lab">
      <div className="pack-heading">
        <div>
          <span className="eyebrow">{isFiveM ? 'Server-authoritative pulls' : 'Standalone pulls'} + print rarities</span>
          <h2>{module.container.kind === 'bag' ? 'Bag & box opening lab' : 'Box & case opening lab'}</h2>
          <p>The 3D opening is shared by standalone and FiveM. In FiveM the server rolls each {module.singular.toLowerCase()} and its print; only the presentation runs here.</p>
        </div>
        <div className="pack-heading-actions">
          <button className="primary pack-button" disabled={busy || opening || !data.containers[typeId]} onClick={() => startOpening()}>Open {data.containers[typeId]?.label || module.container.label}</button>
          <button className="primary pack-button" disabled={busy || opening || !data.containers[typeId]} onClick={() => startOpening(true)}>Open {box.outer?.label || module.container.outer.label}</button>
        </div>
      </div>
      {!data.containers[typeId] && <div className="runtime-error">Save a set and its containers in Sets &amp; containers first.</div>}
      <div className="rarity-pills">{tierCounts.map(tier => <span key={tier.value}>{tier.label} <b>{tier.items} {module.label.toLowerCase()} / {tier.prints} prints</b></span>)}</div>
      {canManage && <div className="pk-settings">
        {lookGroup(innerKind, innerLook, look => editBox({look}), box.label || module.container.label)}
        {lookGroup('case', outerLook, look => editBox({outer:{...(box.outer || module.container.outer),look}}), box.outer?.label || module.container.outer.label)}
        <div className="pk-set-group"><span className="pk-set-title">Looks</span><div className="pk-set-row"><button className="pk-opt selected" disabled={busy || !containerDirty} onClick={saveContainers}>Save looks</button><button className="pk-opt" disabled={!containerDirty} onClick={() => setContainerDraft(null)}>Revert</button></div><small className="pk-set-desc">Unsaved looks preview here; saving applies them for every player and to newly sealed containers.</small></div>
      </div>}
      {!run && <div className="collectibles-container-layout">
        <div className="collectibles-opening"><ContainerPreview3D typeId={typeId} container={box} look={innerLook} /><small>{box.label} · {box.count} {module.label.toLowerCase()}</small></div>
        <div className="collectibles-opening"><ContainerPreview3D typeId={typeId} container={box} outer look={outerLook} /><small>{box.outer?.label || module.container.outer.label} · {box.outer?.count || module.container.outer.count} sealed {containerNoun}</small></div>
      </div>}
      {run && <><ContainerOpening3D key={run.id} run={run} look={run.playbackLook || (run.outer ? outerLook : innerLook)} onInspect={inspect} onComplete={() => setOpening(false)} onAllRevealed={() => isFiveM && attempt(async () => {await bridge.claimCollectibles();setData((await bridge.getCollectibles()).data)})} /><div className="pack-heading-actions collectibles-run-actions"><button className="ghost" disabled={busy} onClick={() => attempt(async () => {if(isFiveM){await bridge.claimCollectibles();setData((await bridge.getCollectibles()).data)}setOpening(false);setRun(null)})}>Close opening</button></div></>}
      {!!sealedList.length && <div className="management-card collectibles-sealed-card"><div className="management-panel-title"><div><strong>Sealed {containerNoun} ({sealedList.length})</strong><span>From opened outer cases.</span></div></div><div className="collectibles-sealed">{sealedList.map(item => <button key={item.instanceId} className="pk-opt" disabled={opening} onClick={() => startOpening(false,item.instanceId)}>Open {item.label}</button>)}</div></div>}
    </section>}

    {viewer && <CardViewer card={viewer} title={viewer.title || module.singular} onClose={() => setViewer(null)} />}
  </section>
}
