import React, { useEffect, useMemo, useState } from 'react'
import { bridge } from '../runtime'
import useConfirm from './useConfirm'
import './crafting.css'
import Minigame from '../minigames/Minigame'
import { loadCraftingPrints } from '../minigames/craftingPrints'
const productionDefaults = { enabled: true, cutter: 'random', cols: 5, rows: 3, rewardPacks: 3, maxErrors: 6, time: 900, minSeconds: 20, flawChance: 0.5, bonusSeconds: 180, bonusPacks: 1, bulkBonusEvery: 5, bulkBonusPacks: 1, bulkBonusMax: 5, scaleBonusTime: true }

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

export default function CraftingPanel({ sets = [], cards = [] }) {
  const { confirm, dialog } = useConfirm()
  const [state, setState] = useState(null)
  const [draft, setDraft] = useState([])
  const [selectedId, setSelectedId] = useState('')
  const [message, setMessage] = useState('')
  const [busy, setBusy] = useState(false)
  const [filter, setFilter] = useState('')
  const [testing, setTesting] = useState(null)
  const [testSet, setTestSet] = useState('')

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
  const production = { ...productionDefaults, ...selected?.minigame }
  const patchProduction = changes => patch({ minigame: { ...production, ...changes } })
  return (
    <section className="management-page crafting-page">
      {dialog}
      {testing && <Minigame config={testing} onResult={(success, details) => { setTesting(null); setMessage(`${success ? 'Batch completed' : 'Test failed or cancelled'}${details ? ` · ${details.errors || 0} errors · ${Math.round(details.seconds || 0)} seconds` : ''}. Test gives no items.`) }} />}
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

            {result.type === 'sealed' && result.kind !== 'box' && <div className="management-card">
              <div className="management-panel-title"><div><strong>Interactive card production</strong><span>One sheet batch per craft. Ingredients and costs apply once per batch, including a final partial batch. Players choose the card set and pack quantity before starting. Settings require the management ACE and explicit Save.</span></div></div>
              <fieldset disabled={busy || state.canEditMinigame === false} className="crafting-production">
                <label className="field crafting-check"><input type="checkbox" checked={selected.minigame?.enabled === true} onChange={e => patchProduction({ enabled: e.target.checked })} /><span>Print, inspect, cut, fold and seal instead of a progress bar</span></label>
                {selected.minigame?.enabled && <div className="form-grid compact-grid">
                  <label className="field"><span>Cutter</span><select value={production.cutter} onChange={e => patchProduction({ cutter: e.target.value })}><option value="random">Alternate randomly</option><option value="bench">Precision workbench</option><option value="industrial">Production cutter</option></select></label>
                  {[['cols','Sheet columns',1,10],['rows','Sheet rows',1,10],['rewardPacks','Packs awarded per completed batch',1,100],['maxErrors','Errors before batch fails',1,20],['time','Time limit (seconds)',30,1800],['minSeconds','Minimum completion time (seconds)',5,300],['bonusSeconds','Perfect bonus time for up to 15 cards (seconds)',0,1800],['bonusPacks','Extra packs for fast completion with zero errors',0,10],['bulkBonusEvery','Completed packs per bulk bonus milestone',2,100],['bulkBonusPacks','Guaranteed extra packs per milestone (0 disables)',0,10],['bulkBonusMax','Maximum bulk extra packs per order',0,100]].map(([key,label,min,max]) => <label className="field" key={key}><span>{label}</span><input type="number" min={min} max={max} step="1" value={production[key]} onChange={e => patchProduction({ [key]: Number(e.target.value) })} /></label>)}
                  <label className="field"><span>Obvious printing flaw chance (%)</span><input type="number" min="0" max="100" value={Math.round(production.flawChance * 100)} onChange={e => patchProduction({ flawChance: Number(e.target.value) / 100 })} /></label>
                  <label className="field crafting-check"><input type="checkbox" checked={production.scaleBonusTime !== false} onChange={e => patchProduction({ scaleBonusTime: e.target.checked })} /><span>Give larger sheets proportionally more time for the perfect batch bonus</span></label>
                  <span className="field span-2">Bulk extras are earned every {production.bulkBonusEvery} requested packs completed within one order, up to {production.bulkBonusMax} extra packs. Mistakes do not remove earned bulk extras. Perfect allowance: {Math.round(Math.min(production.time, production.bonusSeconds * (production.scaleBonusTime !== false ? Math.max(1, production.cols * production.rows / 15) : 1)))} seconds per sheet.</span>
                  <span className="field span-2">{production.cols * production.rows} cards → {production.cols * production.rows / 5} packs to fold/seal. Sheet total must be divisible by 5, maximum 60. Award count can differ from the visible batch; sealed packs retain the set's normal opening odds.</span>
                </div>}
              </fieldset>
              {selected.minigame?.enabled && <div className="crafting-actions">
                <label className="field"><span>Test production card set</span><select disabled={busy} value={testSet} onChange={e => setTestSet(e.target.value)}><option value="">Default set</option>{sets.map(set => <option key={set.id} value={set.id}>{set.name}</option>)}</select></label>
                <button disabled={busy} onClick={async () => {
                  setBusy(true); setMessage('')
                  try {
                    const prints = await loadCraftingPrints(testSet, sets, cards, production)
                    setTesting({ ...production, ...prints, game: 'crafting', cutter: production.cutter === 'random' ? (Math.random()<.5?'bench':'industrial') : production.cutter, id: `craft-test-${Date.now()}` })
                  } catch (error) { setMessage(error.message) } finally { setBusy(false) }
                }}>Test draft production · no rewards</button>
              </div>}
            </div>}

            <div className="management-card">
              <div className="management-panel-title"><div><strong>Makes</strong><span>What the player receives for each item crafted.</span></div></div>
              <div className="form-grid compact-grid">
                <label className="field"><span>Type</span><select value={result.type} onChange={e => patch({ result: { type: e.target.value, count: 1 }, ...(e.target.value !== 'sealed' ? { minigame: undefined } : {}) })}>
                  {(state.resultTypes || Object.keys(RESULT_LABELS)).map(type => <option key={type} value={type}>{RESULT_LABELS[type] || type}</option>)}</select></label>
                <label className="field"><span>Count</span><input type="number" min="1" max="1000" value={result.count || 1} onChange={e => patchResult({ count: Math.max(1, Math.floor(Number(e.target.value) || 1)) })} /></label>
                {result.type === 'item' && <label className="field span-2"><span>Item name</span><input value={result.item || ''} onChange={e => patchResult({ item: e.target.value.trim() })} placeholder="card_sleeve" /></label>}
                {result.type === 'sealed' && <>
                  <label className="field"><span>Pack or box</span><select value={result.kind || 'pack'} onChange={e => patch({ result: { ...result, kind: e.target.value }, ...(e.target.value === 'box' ? { minigame: undefined } : {}) })}><option value="pack">Booster pack</option><option value="box">Booster box</option></select></label>
                  <span className="field">Players choose the card set when starting this recipe.</span>
                </>}
                {result.type === 'container' && <>
                  <label className="field"><span>Collectible</span><select value={result.collectible || ''} onChange={e => patchResult({ collectible: e.target.value })}><option value="" disabled>Pick one</option>{(state.collectibles || []).map(id => <option key={id} value={id}>{id.replace('_', ' ')}</option>)}</select></label>
                  <label className="field"><span>Size</span><select value={result.outer ? 'outer' : 'inner'} onChange={e => patchResult({ outer: e.target.value === 'outer' })}><option value="inner">Box / bag</option><option value="outer">Case / bag box</option></select></label>
                </>}
                {result.type === 'crate' && <div className="field crate-sets"><span>Card sets for its booster packs / boxes (none = default set, or the crate's own sets)</span><div className="crate-set-list">{sets.map(set => <label key={set.id}><input type="checkbox" checked={(result.sets || []).includes(set.id)} onChange={e => patchResult({ sets: e.target.checked ? [...(result.sets || []), set.id] : (result.sets || []).filter(id => id !== set.id) })} /> {set.name}</label>)}</div></div>}
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
