import React, { useEffect, useMemo, useState } from 'react'
import { resolveCardVariant } from '../cardData'
import { bridge, isFiveM } from '../runtime'
import ArtworkFileInput from './ArtworkFileInput'
import './vendingMap.css'

const slug = value => String(value || 'set')
  .toLowerCase()
  .replace(/[^a-z0-9]+/g, '-')
  .replace(/^-+|-+$/g, '') || 'set'

function clone(value) {
  return typeof structuredClone === 'function' ? structuredClone(value) : JSON.parse(JSON.stringify(value))
}

export default function ManagementPanel({ cards, sets, onSetsChange }) {
  const [selectedSetId, setSelectedSetId] = useState(sets[0]?.id || '')
  const [amount, setAmount] = useState(1)
  const [cardId, setCardId] = useState(cards[0]?.id || '')
  const selectedCard = cards.find(card => card.id === cardId) || cards[0]
  const [variantId, setVariantId] = useState(selectedCard?.variants?.[0]?.id || '')
  const [message, setMessage] = useState('')
  const [busy, setBusy] = useState(false)
  const [containers,setContainers] = useState({count:5,outerCount:12})
  useEffect(() => {if(!isFiveM) bridge.getCardContainers().then(setContainers)},[])

  useEffect(() => {
    if (!sets.some(set => set.id === selectedSetId)) setSelectedSetId(sets[0]?.id || '')
  }, [sets, selectedSetId])

  useEffect(() => {
    const current = cards.find(card => card.id === cardId) || cards[0]
    if (!current) return
    if (!current.variants.some(variant => variant.id === variantId)) setVariantId(current.variants[0]?.id || '')
  }, [cards, cardId, variantId])

  const selectedSet = sets.find(set => set.id === selectedSetId) || sets[0]
  const selectedPrint = selectedCard ? resolveCardVariant(selectedCard, variantId) : null
  const assigned = useMemo(() => new Set(selectedSet?.cardIds || []), [selectedSet])

  const patchSet = patch => {
    if (!selectedSet) return
    onSetsChange(sets.map(set => set.id === selectedSet.id ? { ...set, ...patch } : set))
  }

  const addSet = () => {
    let base = 'new-set'
    let id = base
    let i = 2
    const used = new Set(sets.map(set => set.id))
    while (used.has(id)) id = `${base}-${i++}`
    const next = { id, name: 'New Set', code: id.toUpperCase().slice(0, 12), description: '', cardIds: [] }
    onSetsChange([...sets, next])
    setSelectedSetId(id)
  }

  const removeSet = () => {
    if (!selectedSet || sets.length <= 1) return
    const next = sets.filter(set => set.id !== selectedSet.id)
    onSetsChange(next)
    setSelectedSetId(next[0]?.id || '')
  }

  const renameId = value => {
    if (!selectedSet) return
    const nextId = slug(value)
    if (sets.some(set => set.id === nextId && set.id !== selectedSet.id)) return
    onSetsChange(sets.map(set => set.id === selectedSet.id ? { ...set, id: nextId } : set))
    setSelectedSetId(nextId)
  }

  const toggleCard = id => {
    if (!selectedSet) return
    const cardIds = new Set(selectedSet.cardIds || [])
    if (cardIds.has(id)) cardIds.delete(id)
    else cardIds.add(id)
    patchSet({ cardIds: [...cardIds] })
  }

  const saveSets = async () => {
    setBusy(true); setMessage('')
    try {
      const result = await bridge.saveSets(clone(sets))
      if(!isFiveM) await bridge.saveCardContainers(containers)
      if (Array.isArray(result?.sets)) onSetsChange(result.sets)
      setMessage(isFiveM ? 'Sets saved to the FiveM resource.' : 'Sets and containers saved in this browser.')
    } catch (error) {
      setMessage(error?.message || String(error))
    } finally { setBusy(false) }
  }

  const createSealed = async kind => {
    if (!selectedSet) return
    setBusy(true); setMessage('')
    try {
      await bridge.saveSets(clone(sets))
      const result = await bridge.createSealed({ kind, setId: selectedSet.id, amount: Number(amount) || 1 })
      setMessage(`Created ${result.amount} ${selectedSet.name} ${kind}${result.amount === 1 ? '' : 's'} in your inventory.`)
    } catch (error) {
      setMessage(error?.message || String(error))
    } finally { setBusy(false) }
  }

  const printCard = async () => {
    if (!selectedPrint) return
    setBusy(true); setMessage('')
    try {
      await bridge.printCard({ baseCardId: selectedPrint.baseCardId, variantId: selectedPrint.variantId })
      setMessage(`Printed ${selectedPrint.title} — ${selectedPrint.variantName}. The item is marked MANUAL PRINT.`)
    } catch (error) {
      setMessage(error?.message || String(error))
    } finally { setBusy(false) }
  }

  return (
    <section className="management-page">
      <div className="management-heading">
        <div><span className="eyebrow">{isFiveM ? 'Restricted FiveM tools' : 'Card sets and containers'}</span><h2>Sets & containers</h2><p>Create sets, choose their cards, and configure or manufacture their sealed containers.</p></div>
        <button className="primary" disabled={busy || !sets.length} onClick={saveSets}>Save sets</button>
        <button disabled={busy} onClick={async () => {try {const saved=await bridge.getSets();onSetsChange(saved.sets);if(!isFiveM)setContainers(await bridge.getCardContainers())} catch(error) {setMessage(error.message)}}}>Revert</button>
      </div>

      {message && <div className="management-message">{message}</div>}
      {!isFiveM && <div className="management-card"><label className="field"><span>Cards per pack</span><input type="number" min="1" max="24" value={containers.count} onChange={event => setContainers({...containers,count:Math.max(1,Math.min(24,Number(event.target.value)||1))})} /></label><label className="field"><span>Packs per box</span><input type="number" min="1" max="100" value={containers.outerCount} onChange={event => setContainers({...containers,outerCount:Math.max(1,Math.min(100,Number(event.target.value)||1))})} /></label></div>}

      <div className="management-grid">
        <aside className="set-list-panel">
          <div className="management-panel-title"><strong>Series / sets</strong><button className="ghost small-button" onClick={addSet}>+ Set</button></div>
          <div className="set-list">
            {sets.map(set => <button key={set.id} className={set.id === selectedSet?.id ? 'active' : ''} onClick={() => setSelectedSetId(set.id)}><strong>{set.name}</strong><span>{set.code || set.id} · {(set.cardIds || []).length} cards</span></button>)}
          </div>
          <button className="danger ghost" disabled={sets.length <= 1} onClick={removeSet}>Delete selected set</button>
        </aside>

        <div className="management-main">
          {selectedSet && <>
            <div className="management-card">
              <div className="management-panel-title"><div><strong>Set details</strong><span>Packs and boxes store this set ID in item metadata.</span></div></div>
              <div className="form-grid compact-grid">
                <label className="field"><span>Name</span><input value={selectedSet.name} onChange={e => patchSet({ name: e.target.value })} /></label>
                <label className="field"><span>Code</span><input value={selectedSet.code || ''} onChange={e => patchSet({ code: e.target.value.toUpperCase() })} /></label>
                <label className="field span-2"><span>Set ID</span><input value={selectedSet.id} onChange={e => renameId(e.target.value)} /></label>
                <label className="field span-2"><span>Description</span><textarea rows="2" value={selectedSet.description || ''} onChange={e => patchSet({ description: e.target.value })} /></label>
                <div className="field span-2"><span>Logo (vending machines, set lists)</span>
                  <div className="set-logo-field">
                    {selectedSet.logo ? <img className="set-logo-preview" src={selectedSet.logo} alt="" /> : <span className="set-logo-preview" />}
                    <div className="set-logo-inputs">
                      <input placeholder="https://… image URL" value={selectedSet.logo?.startsWith('data:') ? '' : (selectedSet.logo || '')} onChange={e => patchSet({ logo: e.target.value })} />
                      <ArtworkFileInput onLoaded={value => patchSet({ logo: value })} options={{ maxEdge: 256 }} />
                      {selectedSet.logo && <button className="ghost small-button" onClick={() => patchSet({ logo: '' })}>Remove logo</button>}
                    </div>
                  </div>
                </div>
              </div>
            </div>

            <div className="management-card">
              <div className="management-panel-title"><div><strong>Cards in {selectedSet.name}</strong><span>Only checked base cards can be pulled from packs for this set. Their eligible print variants still follow rarity/weight rules.</span></div><span className="set-count">{assigned.size}/{cards.length}</span></div>
              <div className="set-card-grid">
                {cards.map(card => <label key={card.id} className={`set-card-option ${assigned.has(card.id) ? 'selected' : ''}`}><input type="checkbox" checked={assigned.has(card.id)} onChange={() => toggleCard(card.id)} /><img src={card.image} alt="" /><span><strong>{card.title}</strong><small>{card.variants.length} print{card.variants.length === 1 ? '' : 's'}</small></span></label>)}
              </div>
            </div>

            <div className="management-card production-card">
              <div className="management-panel-title"><div><strong>Create sealed inventory items</strong><span>The set metadata follows box → packs → pulled cards.</span></div></div>
              <div className="production-row">
                <label className="field amount-field"><span>Amount</span><input type="number" min="1" max="100" value={amount} onChange={e => setAmount(Math.max(1, Number(e.target.value) || 1))} /></label>
                <button className="primary" disabled={busy || assigned.size === 0} onClick={() => createSealed('pack')}>Create pack</button>
                <button className="primary" disabled={busy || assigned.size === 0} onClick={() => createSealed('box')}>Create box</button>
              </div>
              {assigned.size === 0 && <small className="warning-copy">Assign at least one card before producing this set.</small>}
            </div>

            <div className="management-card production-card">
              <div className="management-panel-title"><div><strong>Manual card print</strong><span>Creates one physical card item with MANUAL PRINT metadata, printer name, and timestamp. It is separate from normal pack pulls.</span></div></div>
              <div className="manual-print-row">
                <label className="field"><span>Card</span><select value={selectedCard?.id || ''} onChange={e => { setCardId(e.target.value); const c = cards.find(card => card.id === e.target.value); setVariantId(c?.variants?.[0]?.id || '') }}>{cards.map(card => <option key={card.id} value={card.id}>{card.title}</option>)}</select></label>
                <label className="field"><span>Print</span><select value={selectedPrint?.variantId || ''} onChange={e => setVariantId(e.target.value)}>{(selectedCard?.variants || []).map(variant => <option key={variant.id} value={variant.id}>{variant.name} · {variant.rarity}</option>)}</select></label>
                <button className="primary manual-print-button" disabled={busy || !selectedPrint} onClick={printCard}>Print card</button>
              </div>
            </div>
          </>}
        </div>
      </div>
    </section>
  )
}
