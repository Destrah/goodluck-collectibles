import React, { useEffect, useState } from 'react'
import './vendingRecords.css'
import VendingKeyArchive from './VendingKeyArchive'

// FiveM record items: a machine's registration certificate (what was printed vs. the record today) or the business's
// ledger of every registered owner and machine. record = { kind: 'certificate' | 'ledger', ... } from the server.
const STATUS = { placed: 'In service', item: 'Not set up', stolen: 'Reported stolen', removed: 'Taken out of service' }

function Certificate({ record }) {
  const printed = record.printed || {}
  const current = record.current
  const warnings = []
  if (!current) warnings.push('No machine with this serial is on record.')
  else {
    if (printed.owner && current.ownerName !== printed.owner) warnings.push(`Out of date: the machine now belongs to ${current.ownerName}.`)
    if (current.status === 'stolen') warnings.push('This machine is reported stolen.')
    if (current.tampered) warnings.push(`Card payments are going to account ${current.routing}, not the owner's.`)
  }
  return (
    <div className="record-paper">
      <div className="record-paper-head">
        <span>{record.business}</span>
        <h2>Vending Machine Registration</h2>
      </div>
      <dl>
        <dt>Serial number</dt><dd className="mono">{printed.serial || '-'}</dd>
        <dt>Registered owner</dt><dd>{printed.owner || '-'}</dd>
        <dt>Routing number</dt><dd className="mono">{printed.routing || '-'}</dd>
        <dt>Tax rate</dt><dd>{printed.tax != null ? `${printed.tax}%` : '-'}</dd>
        <dt>Issued</dt><dd>{printed.issued || '-'}</dd>
        {current && <><dt>Status today</dt><dd>{STATUS[current.status] || current.status}</dd></>}
      </dl>
      {warnings.length > 0 && <ul className="record-warnings">{warnings.map(text => <li key={text}>{text}</li>)}</ul>}
      {!warnings.length && <p className="record-ok">Matches the business records.</p>}
      <div className="record-stamp">{record.business}</div>
    </div>
  )
}

function Ledger({ record }) {
  const [filter, setFilter] = useState('')
  const [page, setPage] = useState('machines')
  const match = text => !filter || String(text).toLowerCase().includes(filter.toLowerCase())
  const machines = (record.machines || []).filter(machine => match(`${machine.serial} ${machine.ownerName} ${machine.status}`))
  const people = (record.people || []).filter(person => match(`${person.name} ${person.routing}`))
  return (
    <div className="record-paper record-ledger">
      <div className="record-paper-head"><span>{record.business}</span><h2>Vending Machine Ledger</h2></div>
      <div className="record-ledger-tools">
        <button className={page === 'machines' ? 'active' : ''} onClick={() => setPage('machines')}>Machines ({(record.machines || []).length})</button>
        <button className={page === 'people' ? 'active' : ''} onClick={() => setPage('people')}>Owners ({(record.people || []).length})</button>
        <input placeholder="Search…" value={filter} onChange={event => setFilter(event.target.value)} />
      </div>
      <div className="record-ledger-list">
        {page === 'machines' && <table><thead><tr><th>Serial</th><th>Owner</th><th>Status</th></tr></thead><tbody>
          {machines.map(machine => <tr key={machine.serial} className={machine.status === 'stolen' ? 'stolen' : ''}><td className="mono">{machine.serial}</td><td>{machine.ownerName}</td><td>{STATUS[machine.status] || machine.status}</td></tr>)}
        </tbody></table>}
        {page === 'people' && <table><thead><tr><th>Owner</th><th>Routing</th><th>Tax</th></tr></thead><tbody>
          {people.map(person => <tr key={`${person.name}-${person.routing}`}><td>{person.name}</td><td className="mono">{person.routing}</td><td>{person.tax}%</td></tr>)}
        </tbody></table>}
      </div>
    </div>
  )
}

function KeyRecord({ record }) {
  const printed = record.printed || {}
  const report = record.kind === 'keyreport'
  return <div className={`record-paper${report ? ' record-key-report' : ''}`}>
    <div className="record-paper-head"><span>{record.business}</span><h2>{report ? 'Permanent Vending Key Records' : 'Vending Key Identification'}</h2></div>
    <dl>
      <dt>Machine serial</dt><dd className="mono">{printed.serial || '-'}</dd>
      {report && printed.reportId && <><dt>Report reference</dt><dd className="mono">{printed.reportId}</dd></>}
      <dt>{report ? 'Cylinder at printing' : 'Key cylinder'}</dt><dd className="mono">{printed.lockId || '-'}</dd>
      {report ? <><dt>Registered owner</dt><dd>{printed.ownerName || '-'}</dd><dt>Printed</dt><dd>{printed.printedAt ? new Date(printed.printedAt * 1000).toLocaleString() : '-'}</dd></> : <>
        <dt>Numbered key ID</dt><dd className="mono">{printed.keyId || '-'}</dd>
        <dt>Access</dt><dd>{printed.access || '-'}</dd>
        <dt>Cylinder match today</dt><dd>{record.currentLockId === printed.lockId ? 'Current cylinder' : 'Retired / no matching cylinder'}</dd>
      </>}
    </dl>
    {report && <VendingKeyArchive archive={printed.archive} currentLockId={printed.lockId} />}
    {!report && <p>Rekeying does not erase this key’s identification. A cylinder match alone does not bypass damage or a temporary security seal.</p>}
  </div>
}

export default function VendingRecordView({ record, onClose }) {
  useEffect(() => {
    const onKey = event => { if (event.key === 'Escape') onClose?.() }
    window.addEventListener('keydown', onKey)
    return () => window.removeEventListener('keydown', onKey)
  }, [onClose])
  return (
    <div className="record-overlay" role="dialog">
      {record?.kind === 'keyreport' || record?.kind === 'key' ? <KeyRecord record={record} /> : record?.kind === 'ledger' ? <Ledger record={record} /> : <Certificate record={record || {}} />}
      <button className="record-close primary" onClick={onClose}>Close</button>
    </div>
  )
}
