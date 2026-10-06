import { useState } from 'react'
import TradingCard from '../components/TradingCard'
import { CardBack } from '../collectables/tradingCards.jsx'
import { asArray, gradeName, flawLabel } from './condition.js'
import './grading.css'

// A grading record looked up by cert number: the graded card with the grader's marked flaws pinned where they
// clicked, and the list of those calls. lookup(cert) -> Promise<{ record, card }> (FiveM: the server's record).
export default function GradeRecordLookup({ lookup, initial = null, initialCert = '', onClose }) {
  const [cert, setCert] = useState(initialCert || initial?.record?.cert || '')
  const [found, setFound] = useState(initial)
  const [side, setSide] = useState('front')
  const [busy, setBusy] = useState(false)
  const [error, setError] = useState('')
  const search = async event => {
    event?.preventDefault()
    const value = String(cert).replace(/\D/g, '')
    if (!value) { setError('Type the cert number from the slab label.'); return }
    setBusy(true); setError('')
    try {
      const response = await lookup(value)
      if (!response?.record) { setFound(null); setError(`No grading record for cert #${value}.`) } else { setFound(response); setSide('front') }
    } catch (failure) { setFound(null); setError(failure?.message || String(failure)) } finally { setBusy(false) }
  }
  const record = found?.record
  const card = found?.card && record ? { ...found.card, condition: record.condition ?? found.card.condition, graded: { grade: record.grade, name: record.name, cert: record.cert, grader: record.grader, gradedAt: record.gradedAt } } : null
  const marks = asArray(record?.marks)
  const when = record?.gradedAt ? new Date(record.gradedAt) : null

  return <div className="grade-record" role="dialog" aria-label="Grading record lookup">
    <header className="grade-record-head">
      <div><span className="eyebrow">Meta Comics Grading</span><h2>Cert lookup</h2></div>
      <form onSubmit={search} className="grade-record-search">
        <input value={cert} onChange={event => setCert(event.target.value)} placeholder="Cert number, e.g. 61828903" inputMode="numeric" autoFocus />
        <button className="primary" disabled={busy}>{busy ? 'Looking…' : 'Look up'}</button>
      </form>
      {onClose && <button className="ghost" onClick={onClose}>Close</button>}
    </header>
    {error && <div className="management-message" role="alert">{error}</div>}
    {record && card && <div className="grade-record-body">
      <div className="grade-record-card">
        <div className="grade-record-face">
          {side === 'front' ? <TradingCard card={card} size="viewer" interactive={false} showProtection={false} /> : <div className="grading-back"><CardBack item={card} showProtection={false} /></div>}
          <div className="grading-pins">
            {marks.filter(mark => (mark.side || 'front') === side && Number.isFinite(Number(mark.x))).map((mark, index) =>
              <span key={index} className="grading-pin is-confirmed" style={{ left: `${mark.x}%`, top: `${mark.y}%` }} title={mark.label || flawLabel(mark.type)} />)}
          </div>
        </div>
        <button className="ghost" onClick={() => setSide(side === 'front' ? 'back' : 'front')}>Show {side === 'front' ? 'back' : 'front'}</button>
      </div>
      <div className="grade-record-copy">
        <div className="grade-record-grade"><b>{record.grade}</b><span>{record.name || gradeName(record.grade)}</span></div>
        <dl>
          <dt>Card</dt><dd>{record.title} · {record.variantName}{record.setName ? ` · ${record.setName}` : ''}</dd>
          <dt>Cert</dt><dd>#{record.cert}</dd>
          <dt>Graded by</dt><dd>{record.grader || 'Unknown'}</dd>
          {when && !isNaN(when) && <><dt>Graded on</dt><dd>{when.toLocaleString()}</dd></>}
          {record.suggested !== undefined && record.suggested !== record.grade && <><dt>Calls suggested</dt><dd>{record.suggested} {gradeName(record.suggested)} — graded {record.grade > record.suggested ? 'higher' : 'lower'} by the grader</dd></>}
        </dl>
        <strong>Flaws the grader marked ({marks.length})</strong>
        {!marks.length && <p className="muted">The grader marked no flaws.</p>}
        <ol className="grade-record-marks">
          {marks.map((mark, index) => <li key={index}><span>{mark.label || flawLabel(mark.type)}</span>{Number(mark.deduction) > 0 && <small>−{mark.deduction}</small>}</li>)}
        </ol>
        <p className="muted">Pins show where the grader clicked. Flaws they didn't mark aren't listed: look at the card yourself.</p>
      </div>
    </div>}
  </div>
}
