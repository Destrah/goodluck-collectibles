import React, { useEffect, useMemo, useState } from 'react'
import { bridge } from '../runtime'
import useConfirm from './useConfirm'
import './vendingRecords.css'
import VendingKeyArchive from './VendingKeyArchive'
import VendingRecordView from './VendingRecordView'
import VendingRecordTables from './VendingRecordTables'

// Admin "Machine records" tab: registered owners with their tax rates, and every vending machine serial with its
// owner, card payment routing, where it is and what happened to it. Tax rates are edited here and saved with
// "Save tax rates"; the other buttons (register, assign, reset routing, ...) save straight away after confirming.
// An owner opening it through the portal (Config.Portal, scope 'owner') sees only their own machines, read-only
// apart from printing their papers. Each machine lists its recent sales (Ownership.SalesLog).
const STATUS = { placed: 'Placed', item: 'Item', stolen: 'Stolen', removed: 'Removed' }
const money = n => `$${Math.round(Number(n) || 0).toLocaleString()}`
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
  const [keyForm, setKeyForm] = useState({ serial: '', serverId: '', access: 'full' })
  const [osPlayers, setOSPlayers] = useState({})
  const [report, setReport] = useState(null)

  const apply = result => { setState(result); setTaxes(taxMap(result.people)) }
  const load = async () => {
    setBusy(true); setMessage('')
    try { apply(await bridge.getVendingRecords()) } catch (error) { setMessage(error?.message || String(error)) } finally { setBusy(false) }
  }
  useEffect(() => { load() }, [])
  useEffect(() => {
    const refresh = event => { if (event.data?.type === 'metaComic:vendingRemoteAccessChanged') load() }
    window.addEventListener('message', refresh)
    return () => window.removeEventListener('message', refresh)
  }, [])

  const act = async (payload, done) => {
    setBusy(true); setMessage('')
    try { const result = await bridge.saveVendingRecords(payload); apply(result); if (result.keyReportPreview) setReport(result.keyReportPreview); if (done) setMessage(done) }
    catch (error) { setMessage(error?.message || String(error)) } finally { setBusy(false) }
  }
  const dirtyTaxes = useMemo(() => {
    const saved = taxMap(state?.people)
    return Object.fromEntries(Object.entries(taxes).filter(([id, value]) => value !== saved[id]))
  }, [taxes, state])
  const taxesDirty = Object.keys(dirtyTaxes).length > 0
  const taxesValid = Object.values(dirtyTaxes).every(value => value !== '' && Number(value) >= 0 && Number(value) <= 100)
  const saveTaxes = () => act({ action: 'tax', taxes: Object.fromEntries(Object.entries(dirtyTaxes).map(([id, value]) => [id, Number(value)])) }, 'Tax rates saved.')

  const ownerView = state?.scope === 'owner' || state?.scope === 'os'
  const people = state?.people || []
  const owners = [{ id: 'business', name: state?.business || 'The business' }, ...people]
  const machines = (state?.machines || []).filter(machine => !filter || `${machine.serial} ${machine.ownerName} ${machine.routing} ${machine.status} ${machine.holder?.name || ''} ${JSON.stringify(machine.keyArchive || {})}`.toLowerCase().includes(filter.toLowerCase()))
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
  const issueKey = async () => {
    if (!await confirm(`Issue a ${keyForm.access} key for ${keyForm.serial} to player ${keyForm.serverId}? Existing keys remain valid.`, 'Issue key')) return
    act({ action: 'issueKey', serial: keyForm.serial, serverId: Number(keyForm.serverId), access: keyForm.access }, 'Numbered key issued and permanently recorded.')
  }

  return (
    <section className="management-page records-page">
      {dialog}
      {report && <VendingRecordView record={report} onClose={() => setReport(null)} />}
      <div className="management-heading">
        {ownerView
          ? <div><span className="eyebrow">Your accessible vending machines</span><h2>Machine records</h2><p>Registered history and authorized OS records. Taken-over OS logs start at takeover and contain no previous business records.</p></div>
          : <div><span className="eyebrow">Restricted FiveM tools</span><h2>Machine records</h2><p>Who owns each vending machine, where its card payments go and what happened to it. Owners must be registered before machines can be assigned to them.</p></div>}
        <button onClick={load} disabled={busy}>Refresh</button>
        {!ownerView && <button disabled={busy || !state} onClick={() => act({ action: 'ledger' }, 'Ledger given to you.')}>Give me a ledger</button>}
      </div>
      {message && <div className="management-message">{message}</div>}
      {!state && !message && <div className="management-message">Loading records…</div>}
      {state && <>
        {ownerView ? <div className="records-summary">
          <div><span>Owner</span><strong>{people[0]?.name || '-'}</strong><em>{people[0] ? `Routing ${people[0].routing} · tax ${people[0].tax}%` : ''}</em></div>
          <div><span>Machines</span><strong>{(state.machines || []).filter(m => m.status !== 'removed').length}</strong></div>
          <div><span>Card earnings waiting</span><strong>{money(people[0]?.pending)}</strong><em>Paid when you are in the city</em></div>
        </div> : <div className="records-summary">
          <div><span>Business</span><strong>{state.business}</strong><em>Routing {state.businessRouting}</em></div>
          <div><span>Registered owners</span><strong>{people.length}</strong></div>
          <div><span>Machines</span><strong>{(state.machines || []).filter(m => m.status !== 'removed').length}</strong><em>{(state.machines || []).filter(m => m.status === 'stolen').length} stolen · {(state.machines || []).filter(m => m.tampered).length} rerouted</em></div>
          <div><span>Held business earnings</span><strong>{money(state.businessPending)}</strong><button className="ghost" disabled={busy || !(state.businessPending > 0)} onClick={withdraw}>Pay out to me</button></div>
        </div>}

        <div className={`records-grid${ownerView ? ' owner-view' : ''}`}>
          {!ownerView && <div className="management-card records-people">
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
          </div>}

          <div className="management-card records-machines">
            {state.keysEnabled && !ownerView && <div className="records-register">
              <h4>Issue a numbered machine key</h4>
              <select aria-label="Key machine" value={keyForm.serial} onChange={event => setKeyForm(current => ({ ...current, serial: event.target.value }))}>
                <option value="">Choose machine…</option>
                {(state.machines || []).filter(machine => machine.status !== 'removed').map(machine => <option key={machine.serial} value={machine.serial}>{machine.serial} · {machine.ownerName}</option>)}
              </select>
              <select aria-label="Key recipient" value={keyForm.serverId} onChange={event => setKeyForm(current => ({ ...current, serverId: event.target.value }))}>
                <option value="">Choose recipient…</option>
                {(state.online || []).map(player => <option key={player.serverId} value={String(player.serverId)}>[{player.serverId}] {player.name}</option>)}
              </select>
              <select aria-label="Key access" value={keyForm.access} onChange={event => setKeyForm(current => ({ ...current, access: event.target.value }))}>
                <option value="full">Full access: stock, prices, cash, bolts</option><option value="service">Service: restock and prices</option>
              </select>
              <button disabled={busy || !keyForm.serial || !keyForm.serverId} onClick={issueKey}>Issue key</button>
              <p>Rekey or repair at the physical machine using a replacement cylinder. Previous keys stay in the permanent archive.</p>
            </div>}
            <div className="records-card-head">
              <h3>Machines</h3>
              <input className="records-filter" placeholder="Search serial, owner, key, cylinder…" value={filter} onChange={event => setFilter(event.target.value)} />
            </div>
            {!machines.length && <p className="records-empty">No machines{filter ? ' match' : ' yet'}.</p>}
            {machines.map(machine => (
              <div key={machine.serial} className={`records-machine status-${machine.status}${machine.tampered ? ' tampered' : ''}`}>
                <div className="records-machine-row">
                  <button className="records-serial" onClick={() => setOpen(current => current === machine.serial ? '' : machine.serial)}>{machine.serial}</button>
                  <span className={`records-pill ${machine.status}`}>{STATUS[machine.status] || machine.status}</span>
                  {machine.tampered && <span className="records-pill rerouted">Rerouted</span>}
                  {machine.remoteOffline && <span className="records-pill">OS offline · historical records only</span>}
                  {machine.osView && <span className="records-pill">Private OS records</span>}
                  {ownerView ? <span className="records-owner-name">{machine.ownerName}</span> : <select value={machine.owner || 'business'} disabled={busy || machine.status === 'removed'} onChange={event => assign(machine, event.target.value)}>
                    {owners.map(owner => <option key={owner.id} value={owner.id}>{owner.name}</option>)}
                  </select>}
                </div>
                <div className="records-machine-meta">
                  <span>Card payments: {machine.tampered ? <b>{machine.routing} ({machine.routingName})</b> : `${machine.routingName} · ${machine.routing}`}</span>
                  {machine.status === 'placed' && machine.coords && <span>At {Math.round(machine.coords.x)}, {Math.round(machine.coords.y)}{machine.cash != null ? ` · ${money(machine.cash)} ${state.forensic ? 'cash inside' : 'recorded cash inside'}` : ''}</span>}
                  {state.forensic && <span>GPS {machine.gpsDisabled ? 'disabled' : 'enabled'} · Skimmer {machine.skimmer ? 'installed' : 'absent'}</span>}
                  {machine.status !== 'placed' && machine.holder && <span>Last held by {machine.holder.name}</span>}
                  {machine.owner !== 'business' && <span>Tax {machine.tax}%</span>}
                  {machine.salesCount > 0 && <span>{machine.salesCount} recorded sale{machine.salesCount === 1 ? '' : 's'} · {money(machine.salesAmount)}</span>}
                  {machine.lockId && <span>Cylinder {machine.lockId} · {machine.securitySeal ? 'Temporarily sealed; replacement required' : machine.lockCondition}</span>}
                </div>
                <div className="records-machine-actions">
                  {machine.tampered && !ownerView && <button className="ghost" disabled={busy} onClick={() => resetRouting(machine)}>Reset routing</button>}
                  {!machine.osView && <button className="ghost" disabled={busy} onClick={() => act({ action: 'certificate', serial: machine.serial }, `Certificate for ${machine.serial} given to you.`)}>Print certificate</button>}
                  {machine.canManageOSAccess && <>
                    {(machine.osOperators || []).map(id => <button key={id} className="ghost" disabled={busy} onClick={() => act({ action: 'osAccess', serial: machine.serial, serverId: id, allowed: false }, 'OS operating access revoked.')}>Revoke {id}</button>)}
                    <input type="number" min="1" step="1" aria-label={`Online player ID for ${machine.serial} OS access`} placeholder="Player ID" value={osPlayers[machine.serial] || ''} onChange={event => setOSPlayers(current => ({ ...current, [machine.serial]: event.target.value }))} />
                    <button className="ghost" disabled={busy || !Number.isInteger(Number(osPlayers[machine.serial])) || Number(osPlayers[machine.serial]) < 1} onClick={() => act({ action: 'osAccess', serial: machine.serial, serverId: Number(osPlayers[machine.serial]), allowed: true }, 'OS operating access granted.')}>Grant OS access</button>
                    <button className="ghost" disabled={busy || !Number.isInteger(Number(osPlayers[machine.serial])) || Number(osPlayers[machine.serial]) < 1} onClick={() => act({ action: 'osAccess', serial: machine.serial, serverId: Number(osPlayers[machine.serial]), allowed: false }, 'OS operating access revoked.')}>Revoke OS access</button>
                  </>}
                  {state.keysEnabled && <button className="ghost" disabled={busy} onClick={() => act({ action: 'keyReport', serial: machine.serial }, `Permanent key records for ${machine.serial} printed.`)}>Print key records</button>}
                  <button className="ghost" onClick={() => setOpen(current => current === machine.serial ? '' : machine.serial)}>{open === machine.serial ? 'Hide history & sales' : 'History & sales'}</button>
                </div>
                {open === machine.serial && <VendingRecordTables key={machine.serial} serial={machine.serial} revision={state} />}
                {open === machine.serial && state.keysEnabled && <VendingKeyArchive archive={machine.keyArchive} currentLockId={machine.lockId} />}
              </div>
            ))}
          </div>
        </div>
      </>}
    </section>
  )
}
