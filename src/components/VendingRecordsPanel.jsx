import React, { useEffect, useMemo, useState } from 'react'
import { bridge } from '../runtime'
import useConfirm from './useConfirm'
import './vendingRecords.css'

// Admin "Machine records" tab: registered owners with their tax rates, and every vending machine serial with its
// owner, card payment routing, where it is and what happened to it. Tax rates are edited here and saved with
// "Save tax rates"; the other buttons (register, assign, reset routing, ...) save straight away after confirming.
const STATUS = { placed: 'Placed', item: 'Item', stolen: 'Stolen', removed: 'Removed' }
const money = n => `$${Math.round(Number(n) || 0).toLocaleString()}`
const when = seconds => seconds ? new Date(seconds * 1000).toLocaleString() : '-'
const taxMap = people => Object.fromEntries((people || []).map(person => [person.id, String(person.tax ?? '')]))

export default function VendingRecordsPanel() {
  const { confirm, dialog } = useConfirm()
  const [state, setState] = useState(null)
  const [taxes, setTaxes] = useState({})
  const [message, setMessage] = useState('')
  const [busy, setBusy] = useState(false)
  const [filter, setFilter] = useState('')
  const [open, setOpen] = useState('')
  const [form, setForm] = useState({ serverId: '', id: '', name: '', tax: '' })

  const apply = result => { setState(result); setTaxes(taxMap(result.people)) }
  const load = async () => {
    setBusy(true); setMessage('')
    try { apply(await bridge.getVendingRecords()) } catch (error) { setMessage(error?.message || String(error)) } finally { setBusy(false) }
  }
  useEffect(() => { load() }, [])

  const act = async (payload, done) => {
    setBusy(true); setMessage('')
    try { apply(await bridge.saveVendingRecords(payload)); if (done) setMessage(done) }
    catch (error) { setMessage(error?.message || String(error)) } finally { setBusy(false) }
  }
  const dirtyTaxes = useMemo(() => {
    const saved = taxMap(state?.people)
    return Object.fromEntries(Object.entries(taxes).filter(([id, value]) => value !== saved[id]))
  }, [taxes, state])
  const taxesDirty = Object.keys(dirtyTaxes).length > 0
  const taxesValid = Object.values(dirtyTaxes).every(value => value !== '' && Number(value) >= 0 && Number(value) <= 100)
  const saveTaxes = () => act({ action: 'tax', taxes: Object.fromEntries(Object.entries(dirtyTaxes).map(([id, value]) => [id, Number(value)])) }, 'Tax rates saved.')

  const people = state?.people || []
  const owners = [{ id: 'business', name: state?.business || 'The business' }, ...people]
  const machines = (state?.machines || []).filter(machine => !filter || `${machine.serial} ${machine.ownerName} ${machine.routing} ${machine.status} ${machine.holder?.name || ''}`.toLowerCase().includes(filter.toLowerCase()))
  const online = (state?.online || []).filter(player => !people.some(person => person.id === player.id))

  const register = async () => {
    const player = online.find(entry => String(entry.serverId) === form.serverId)
    const name = form.name || player?.name || form.id
    if (!await confirm(`Register ${name} as a vending machine owner?`, 'Register')) return
    act({ action: 'register', serverId: player ? player.serverId : undefined, id: player ? undefined : form.id.trim(), name: form.name.trim() || undefined,
      tax: form.tax === '' ? undefined : Number(form.tax) }, `${name} registered.`)
    setForm({ serverId: '', id: '', name: '', tax: '' })
  }
  const unregister = async person => {
    if (!await confirm(`Remove ${person.name} from the register? They must not own any machines.`, 'Remove')) return
    act({ action: 'unregister', id: person.id }, `${person.name} removed.`)
  }
  const assign = async (machine, owner) => {
    const name = owners.find(entry => entry.id === owner)?.name || owner
    if (!await confirm(`Assign ${machine.serial} to ${name}? Its card payments go to ${name} from now on (a hacked routing is reset).`, 'Assign')) return
    act({ action: 'assign', serial: machine.serial, owner }, `${machine.serial} assigned to ${name}.`)
  }
  const resetRouting = async machine => {
    if (!await confirm(`Send ${machine.serial}'s card payments to ${machine.ownerName} again?`, 'Reset routing')) return
    act({ action: 'resetRouting', serial: machine.serial }, 'Routing reset.')
  }
  const withdraw = async () => {
    if (!await confirm(`Pay ${money(state.businessPending)} of held business earnings into your bank account?`, 'Pay out')) return
    act({ action: 'withdraw' }, 'Paid out.')
  }

  return (
    <section className="management-page records-page">
      {dialog}
      <div className="management-heading">
        <div><span className="eyebrow">Restricted FiveM tools</span><h2>Machine records</h2><p>Who owns each vending machine, where its card payments go and what happened to it. Owners must be registered before machines can be assigned to them.</p></div>
        <button onClick={load} disabled={busy}>Refresh</button>
        <button disabled={busy || !state} onClick={() => act({ action: 'ledger' }, 'Ledger given to you.')}>Give me a ledger</button>
      </div>
      {message && <div className="management-message">{message}</div>}
      {!state && !message && <div className="management-message">Loading records…</div>}
      {state && <>
        <div className="records-summary">
          <div><span>Business</span><strong>{state.business}</strong><em>Routing {state.businessRouting}</em></div>
          <div><span>Registered owners</span><strong>{people.length}</strong></div>
          <div><span>Machines</span><strong>{(state.machines || []).filter(m => m.status !== 'removed').length}</strong><em>{(state.machines || []).filter(m => m.status === 'stolen').length} stolen · {(state.machines || []).filter(m => m.tampered).length} rerouted</em></div>
          <div><span>Held business earnings</span><strong>{money(state.businessPending)}</strong><button className="ghost" disabled={busy || !(state.businessPending > 0)} onClick={withdraw}>Pay out to me</button></div>
        </div>

        <div className="records-grid">
          <div className="management-card records-people">
            <div className="records-card-head">
              <h3>Registered owners</h3>
              <button className="primary" disabled={busy || !taxesDirty || !taxesValid} onClick={saveTaxes}>Save tax rates</button>
              <button disabled={busy || !taxesDirty} onClick={() => setTaxes(taxMap(state.people))}>Revert</button>
            </div>
            {!people.length && <p className="records-empty">Nobody is registered yet.</p>}
            {people.map(person => (
              <div key={person.id} className={`records-person${dirtyTaxes[person.id] !== undefined ? ' dirty' : ''}`}>
                <div className="records-person-info">
                  <strong>{person.name}</strong>
                  <span>Routing {person.routing} · {person.machines} machine{person.machines === 1 ? '' : 's'}{person.pending > 0 ? ` · ${money(person.pending)} waiting` : ''}</span>
                  <span className="records-id">{person.id}</span>
                </div>
                <label className="records-tax">Tax %<input type="number" min="0" max="100" step="0.5" value={taxes[person.id] ?? ''} onChange={event => setTaxes(current => ({ ...current, [person.id]: event.target.value }))} /></label>
                <button className="ghost" disabled={busy || person.machines > 0} title={person.machines > 0 ? 'Assign their machines to someone else first' : ''} onClick={() => unregister(person)}>Remove</button>
              </div>
            ))}
            <div className="records-register">
              <h4>Register an owner</h4>
              <select value={form.serverId} onChange={event => setForm(current => ({ ...current, serverId: event.target.value }))}>
                <option value="">Online player…</option>
                {online.map(player => <option key={player.serverId} value={String(player.serverId)}>[{player.serverId}] {player.name}</option>)}
              </select>
              {!form.serverId && <input placeholder="or their identifier (citizenid / char:id)" value={form.id} onChange={event => setForm(current => ({ ...current, id: event.target.value }))} />}
              <input placeholder="Name on the records (optional)" value={form.name} onChange={event => setForm(current => ({ ...current, name: event.target.value }))} />
              <input type="number" min="0" max="100" placeholder={`Tax % (default ${state.defaultTax})`} value={form.tax} onChange={event => setForm(current => ({ ...current, tax: event.target.value }))} />
              <button className="primary" disabled={busy || (!form.serverId && !form.id.trim())} onClick={register}>Register</button>
            </div>
          </div>

          <div className="management-card records-machines">
            <div className="records-card-head">
              <h3>Machines</h3>
              <input className="records-filter" placeholder="Search serial, owner, routing…" value={filter} onChange={event => setFilter(event.target.value)} />
            </div>
            {!machines.length && <p className="records-empty">No machines{filter ? ' match' : ' yet'}.</p>}
            {machines.map(machine => (
              <div key={machine.serial} className={`records-machine status-${machine.status}${machine.tampered ? ' tampered' : ''}`}>
                <div className="records-machine-row">
                  <button className="records-serial" onClick={() => setOpen(current => current === machine.serial ? '' : machine.serial)}>{machine.serial}</button>
                  <span className={`records-pill ${machine.status}`}>{STATUS[machine.status] || machine.status}</span>
                  {machine.tampered && <span className="records-pill rerouted">Rerouted</span>}
                  <select value={machine.owner || 'business'} disabled={busy || machine.status === 'removed'} onChange={event => assign(machine, event.target.value)}>
                    {owners.map(owner => <option key={owner.id} value={owner.id}>{owner.name}</option>)}
                  </select>
                </div>
                <div className="records-machine-meta">
                  <span>Card payments: {machine.tampered ? <b>{machine.routing} ({machine.routingName})</b> : `${machine.routingName} · ${machine.routing}`}</span>
                  {machine.status === 'placed' && machine.coords && <span>At {Math.round(machine.coords.x)}, {Math.round(machine.coords.y)}{machine.cash != null ? ` · ${money(machine.cash)} cash inside` : ''}</span>}
                  {machine.status !== 'placed' && machine.holder && <span>Last held by {machine.holder.name}</span>}
                  {machine.owner !== 'business' && <span>Tax {machine.tax}%</span>}
                </div>
                <div className="records-machine-actions">
                  {machine.tampered && <button className="ghost" disabled={busy} onClick={() => resetRouting(machine)}>Reset routing</button>}
                  <button className="ghost" disabled={busy} onClick={() => act({ action: 'certificate', serial: machine.serial }, `Certificate for ${machine.serial} given to you.`)}>Print certificate</button>
                  <button className="ghost" onClick={() => setOpen(current => current === machine.serial ? '' : machine.serial)}>{open === machine.serial ? 'Hide history' : 'History'}</button>
                </div>
                {open === machine.serial && <ol className="records-history">
                  {(machine.history || []).map((event, index) => <li key={index}><time>{when(event.at)}</time>{event.event}{event.by ? <em> · {event.by}</em> : null}</li>)}
                  {!(machine.history || []).length && <li>No history yet.</li>}
                </ol>}
              </div>
            ))}
          </div>
        </div>
      </>}
    </section>
  )
}
