import { useEffect, useState } from 'react'
import { bridge, isFiveM } from '../runtime'

// Shipping crate creation for the Sets & containers tabs: each collectible tab creates its own crates from the set
// selected there, and MixedCrateCreator makes crates holding several collectibles, with a set picked for each.
const TYPE_LABELS = { trading_card: 'Booster packs / boxes', plushie: 'Plushies', challenge_coin: 'Challenge coins' }
const typesOf = crate => Array.isArray(crate?.types) ? crate.types : []

// the configured crates and the sets each collectible can come from (FiveM only)
export function useShippingCrates(enabled = isFiveM) {
  const [state, setState] = useState({ crates: [], sets: {}, error: '' })
  useEffect(() => {
    if (!enabled) return
    let cancelled = false
    bridge.getShippingCrates()
      .then(result => { if (!cancelled) setState({ crates: result.crates || [], sets: result.sets || {}, error: '' }) })
      .catch(error => { if (!cancelled) setState(current => ({ ...current, error: error?.message || String(error) })) })
    return () => { cancelled = true }
  }, [enabled])
  return state
}

// crates holding only this collectible ('trading_card' for booster packs / boxes)
export const cratesFor = (crates, typeId) => crates.filter(crate => { const types = typesOf(crate); return types.length === 1 && types[0] === typeId })

// sets: { trading_card: [card set ids], plushie: set id, challenge_coin: set id }
export async function createCrates(crate, amount, sets) {
  const result = await bridge.createShippingCrate({ crate: crate.id, amount: Math.max(1, Math.min(20, Number(amount) || 1)), sets })
  return `Created ${result.amount} ${crate.label}${result.amount === 1 ? '' : 's'} in your inventory.`
}

export function MixedCrateCreator({ crates, sets, busy, onCreate }) {
  const mixed = crates.filter(crate => typesOf(crate).length > 1)
  const [crateId, setCrateId] = useState('')
  const [amount, setAmount] = useState(1)
  const [chosen, setChosen] = useState({})
  if (!mixed.length) return null
  const crate = mixed.find(entry => entry.id === crateId) || mixed[0]
  const payload = () => {
    const out = {}
    for (const typeId of typesOf(crate)) if (chosen[typeId]) out[typeId] = typeId === 'trading_card' ? [chosen[typeId]] : chosen[typeId]
    return out
  }
  return <div className="management-card production-card">
    <div className="management-panel-title"><div><strong>Mixed shipping crates</strong><span>Crates holding several collectibles: pick the set each one comes from.</span></div></div>
    <div className="production-row">
      <label className="field"><span>Crate</span><select value={crate.id} onChange={e => setCrateId(e.target.value)}>{mixed.map(entry => <option key={entry.id} value={entry.id}>{entry.label}</option>)}</select></label>
      {typesOf(crate).map(typeId => <label key={typeId} className="field"><span>{TYPE_LABELS[typeId] || typeId} set</span>
        <select value={chosen[typeId] || ''} onChange={e => setChosen(current => ({ ...current, [typeId]: e.target.value }))}>
          <option value="">{typeId === 'trading_card' ? 'Default set' : "Container's set"}</option>
          {(sets[typeId] || []).map(set => <option key={set.id} value={set.id}>{set.name}</option>)}
        </select>
      </label>)}
      <label className="field amount-field"><span>Amount</span><input type="number" min="1" max="20" value={amount} onChange={e => setAmount(Math.max(1, Math.min(20, Number(e.target.value) || 1)))} /></label>
      <button className="primary" disabled={busy} onClick={() => onCreate(() => createCrates(crate, amount, payload()))}>Create {crate.label}</button>
    </div>
  </div>
}
