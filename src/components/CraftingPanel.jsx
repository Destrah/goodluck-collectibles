import React, { useEffect, useMemo, useState } from 'react'
import { bridge } from '../runtime'
import useConfirm from './useConfirm'
import './crafting.css'

// Admin "Crafting" tab: every recipe the server knows. Nothing is saved until "Save recipes"; Revert reloads.
// The server checks every recipe again when saving (unknown result types, sets or bad numbers are refused).
const RESULT_LABELS = { item: 'Inventory item', sealed: 'Booster pack / box', container: 'Collectible container', crate: 'Shipping crate', vending: 'Vending machine' }
const blankRecipe = () => ({ id: `recipe_${Math.random().toString(36).slice(2, 8)}`, label: 'New recipe', category: 'General', enabled: true, time: 5000, money: 0, account: 'cash', managersOnly: false,
  result: { type: 'item', item: '', count: 1 }, ingredients: [{ item: '', count: 1, keep: false }], jobs: {} })
const clone = value => JSON.parse(JSON.stringify(value))
const jobsText = jobs => Object.entries(jobs || {}).map(([name, grade]) => `${name}:${grade}`).join(', ')
const parseJobs = text => Object.fromEntries(String(text).split(',').map(part => part.trim()).filter(Boolean).map(part => {
  const [name, grade] = part.split(':').map(value => value.trim())
  return [name, Math.max(0, Math.floor(Number(grade) || 0))]
}).filter(([name]) => name))

export default function CraftingPanel({ sets = [] }) {
  const { confirm, dialog } = useConfirm()
  const [state, setState] = useState(null)
  const [draft, setDraft] = useState([])
  const [selectedId, setSelectedId] = useState('')
  const [message, setMessage] = useState('')
  const [busy, setBusy] = useState(false)
  const [filter, setFilter] = useState('')

  const load = async () => {
    setBusy(true); setMessage('')
    try {
      const result = await bridge.getCrafting()
      setState(result)
      setDraft(clone(result.recipes || []))
      setSelectedId(current => (result.recipes || []).some(recipe => recipe.id === current) ? current : result.recipes?.[0]?.id || '')
    } catch (error) { setMessage(error?.message || String(error)) } finally { setBusy(false) }
  }
  useEffect(() => { load() }, [])

  const dirty = useMemo(() => state && JSON.stringify(draft) !== JSON.stringify(state.recipes || []), [draft, state])
  const selected = draft.find(recipe => recipe.id === selectedId)
  const patch = changes => setDraft(list => list.map(recipe => recipe.id === selectedId ? { ...recipe, ...changes } : recipe))
  const patchResult = changes => patch({ result: { ...selected.result, ...changes } })
  const patchIngredient = (index, changes) => patch({ ingredients: selected.ingredients.map((entry, i) => i === index ? { ...entry, ...changes } : entry) })
  const visible = draft.filter(recipe => !filter || `${recipe.label} ${recipe.category} ${recipe.id}`.toLowerCase().includes(filter.toLowerCase()))

  const save = async () => {
    setBusy(true); setMessage('')
    try {
      const result = await bridge.saveCrafting({ recipes: draft })
      setState(result); setDraft(clone(result.recipes || []))
      setMessage(`Saved ${result.recipes?.length || 0} recipes.`)
    } catch (error) { setMessage(error?.message || String(error)) } finally { setBusy(false) }
  }
  const reset = async () => {
    if (!await confirm('Go back to the recipes in config.lua? Your saved recipes are removed.', 'Use config.lua')) return
    setBusy(true)
    try { const result = await bridge.saveCrafting({ reset: true }); setState(result); setDraft(clone(result.recipes || [])); setMessage('Using the config.lua recipes again.') }
    catch (error) { setMessage(error?.message || String(error)) } finally { setBusy(false) }
  }
  const add = () => { const recipe = blankRecipe(); setDraft(list => [...list, recipe]); setSelectedId(recipe.id) }
  const duplicate = () => { const copy = { ...clone(selected), id: `${selected.id}_copy`, label: `${selected.label} (copy)` }; setDraft(list => [...list, copy]); setSelectedId(copy.id) }
  const remove = async () => {
    if (!await confirm(`Delete the recipe "${selected.label}"? It is gone once you save.`, 'Delete')) return
    setDraft(list => list.filter(recipe => recipe.id !== selectedId)); setSelectedId(draft.find(recipe => recipe.id !== selectedId)?.id || '')
  }
  const renameId = value => { const id = value.replace(/[^\w-]/g, ''); setDraft(list => list.map(recipe => recipe.id === selectedId ? { ...recipe, id } : recipe)); setSelectedId(id) }

  const result = selected?.result || {}
  return (
    <section className="management-page crafting-page">
      {dialog}
      <div className="management-heading">
        <div><span className="eyebrow">Restricted FiveM tools</span><h2>Crafting</h2><p>Recipes for every item: what goes in, what comes out, how long it takes and who may craft it.{state && !state.custom ? ' Showing the config.lua recipes.' : ''}</p></div>
        <button className="primary" disabled={busy || !dirty} onClick={save}>Save recipes</button>
        <button disabled={busy || !dirty} onClick={() => { setDraft(clone(state?.recipes || [])); setMessage('') }}>Revert</button>
        <button className="ghost" disabled={busy || !state?.custom} onClick={reset}>Use config.lua</button>
      </div>
      {message && <div className="management-message">{message}</div>}
      {!state && !message && <div className="management-message">Loading recipes…</div>}
      {state && <div className="management-grid">
        <aside className="set-list-panel">
          <div className="management-panel-title"><strong>Recipes</strong><button className="ghost small-button" onClick={add}>+ Recipe</button></div>
          <input className="crafting-filter" placeholder="Search recipes" value={filter} onChange={event => setFilter(event.target.value)} />
          <div className="set-list">
            {visible.map(recipe => <button key={recipe.id} className={`${recipe.id === selectedId ? 'active' : ''} ${recipe.enabled === false ? 'crafting-off' : ''}`} onClick={() => setSelectedId(recipe.id)}>
              <strong>{recipe.label}</strong><span>{recipe.category} · {RESULT_LABELS[recipe.result?.type] || recipe.result?.type}</span></button>)}
          </div>
        </aside>
        <div className="management-main">
          {!selected && <div className="management-card">Pick a recipe or add one.</div>}
          {selected && <>
            <div className="management-card">
              <div className="management-panel-title"><div><strong>Recipe</strong><span>The ID is how stations and other scripts refer to it.</span></div>
                <div className="crafting-actions"><button className="ghost small-button" onClick={duplicate}>Duplicate</button><button className="danger ghost small-button" onClick={remove}>Delete</button></div></div>
              <div className="form-grid compact-grid">
                <label className="field"><span>Name</span><input value={selected.label} onChange={e => patch({ label: e.target.value })} /></label>
                <label className="field"><span>Category</span><input value={selected.category} onChange={e => patch({ category: e.target.value })} /></label>
                <label className="field"><span>Recipe ID</span><input value={selected.id} onChange={e => renameId(e.target.value)} /></label>
                <label className="field"><span>Time per item (seconds)</span><input type="number" min="0" max="600" step="0.5" value={(selected.time || 0) / 1000} onChange={e => patch({ time: Math.round(Math.max(0, Number(e.target.value) || 0) * 1000) })} /></label>
                <label className="field"><span>Money per item</span><input type="number" min="0" value={selected.money || 0} onChange={e => patch({ money: Math.max(0, Math.floor(Number(e.target.value) || 0)) })} /></label>
                <label className="field"><span>Paid from</span><select value={selected.account || 'cash'} onChange={e => patch({ account: e.target.value })}><option value="cash">Cash</option><option value="bank">Bank</option></select></label>
                <label className="field span-2"><span>Jobs (job:minimum grade, comma separated; empty = everyone)</span><input value={jobsText(selected.jobs)} onChange={e => patch({ jobs: parseJobs(e.target.value) })} placeholder="cardshop:0, police:2" /></label>
                <label className="field crafting-check"><input type="checkbox" checked={selected.enabled !== false} onChange={e => patch({ enabled: e.target.checked })} /><span>Enabled</span></label>
                <label className="field crafting-check"><input type="checkbox" checked={!!selected.managersOnly} onChange={e => patch({ managersOnly: e.target.checked })} /><span>Managers only</span></label>
              </div>
              {!!state.stations?.length && <div className="crafting-stations"><span>Stations (none checked = every station)</span>
                {state.stations.map(station => <label key={station.id}><input type="checkbox" checked={(selected.stations || []).includes(station.id)} onChange={e => {
                  const next = new Set(selected.stations || []); e.target.checked ? next.add(station.id) : next.delete(station.id)
                  patch({ stations: next.size ? [...next] : undefined })
                }} />{station.label}</label>)}</div>}
            </div>

            <div className="management-card">
              <div className="management-panel-title"><div><strong>Makes</strong><span>What the player receives for each item crafted.</span></div></div>
              <div className="form-grid compact-grid">
                <label className="field"><span>Type</span><select value={result.type} onChange={e => patch({ result: { type: e.target.value, count: 1 } })}>
                  {(state.resultTypes || Object.keys(RESULT_LABELS)).map(type => <option key={type} value={type}>{RESULT_LABELS[type] || type}</option>)}</select></label>
                <label className="field"><span>Count</span><input type="number" min="1" max="1000" value={result.count || 1} onChange={e => patchResult({ count: Math.max(1, Math.floor(Number(e.target.value) || 1)) })} /></label>
                {result.type === 'item' && <label className="field span-2"><span>Item name</span><input value={result.item || ''} onChange={e => patchResult({ item: e.target.value.trim() })} placeholder="card_sleeve" /></label>}
                {result.type === 'sealed' && <>
                  <label className="field"><span>Pack or box</span><select value={result.kind || 'pack'} onChange={e => patchResult({ kind: e.target.value })}><option value="pack">Booster pack</option><option value="box">Booster box</option></select></label>
                  <label className="field"><span>Card set</span><select value={result.set || ''} onChange={e => patchResult({ set: e.target.value || undefined })}><option value="">Default set</option>{sets.map(set => <option key={set.id} value={set.id}>{set.name}</option>)}</select></label>
                </>}
                {result.type === 'container' && <>
                  <label className="field"><span>Collectible</span><select value={result.collectible || ''} onChange={e => patchResult({ collectible: e.target.value })}><option value="" disabled>Pick one</option>{(state.collectibles || []).map(id => <option key={id} value={id}>{id.replace('_', ' ')}</option>)}</select></label>
                  <label className="field"><span>Size</span><select value={result.outer ? 'outer' : 'inner'} onChange={e => patchResult({ outer: e.target.value === 'outer' })}><option value="inner">Box / bag</option><option value="outer">Case / bag box</option></select></label>
                </>}
                {result.type === 'crate' && <label className="field"><span>Crate</span><select value={result.crate || ''} onChange={e => patchResult({ crate: e.target.value })}><option value="" disabled>Pick one</option>{(state.crates || []).map(crate => <option key={crate.id} value={crate.id}>{crate.label}</option>)}</select></label>}
              </div>
            </div>

            <div className="management-card">
              <div className="management-panel-title"><div><strong>Ingredients</strong><span>Per item crafted. A tool is needed but not used up.</span></div>
                <button className="ghost small-button" disabled={selected.ingredients.length >= 12} onClick={() => patch({ ingredients: [...selected.ingredients, { item: '', count: 1, keep: false }] })}>+ Ingredient</button></div>
              <div className="crafting-ingredients">
                {selected.ingredients.map((entry, index) => <div className="crafting-ingredient" key={index}>
                  <input placeholder="item name" value={entry.item} onChange={e => patchIngredient(index, { item: e.target.value.trim() })} />
                  <input type="number" min="1" value={entry.count} onChange={e => patchIngredient(index, { count: Math.max(1, Math.floor(Number(e.target.value) || 1)) })} />
                  <label><input type="checkbox" checked={!!entry.keep} onChange={e => patchIngredient(index, { keep: e.target.checked })} />Tool</label>
                  <button className="ghost small-button" onClick={() => patch({ ingredients: selected.ingredients.filter((_, i) => i !== index) })}>Remove</button>
                </div>)}
                {!selected.ingredients.length && <small>No ingredients: anyone allowed can craft it for free.</small>}
              </div>
            </div>
          </>}
        </div>
      </div>}
    </section>
  )
}
