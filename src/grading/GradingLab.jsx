import { useMemo, useState } from 'react'
import RotatableCollectible from '../collectables/RotatableCollectible'
import GradingStation, { localGradingSession } from './GradingStation.jsx'
import { loadCopies, addCopy, updateCopy, removeCopy, copyCard, saveRecord, getRecord } from './standaloneCopies.js'
import GradeRecordLookup from './GradeRecord.jsx'
import { applyWear, generateCondition, gradeName, PROTECTION_LABELS } from './condition.js'
import { resolveCardVariant } from '../cardData.js'
import './grading.css'

// Standalone Grading tab: the copies pulled from packs (or a test copy of any print), with sleeves / toploaders,
// handling wear and the grading bench. In FiveM the same happens through the card item's buttons.
export default function GradingLab({ cards }) {
  const [copies, setCopies] = useState(loadCopies)
  const [selectedId, setSelectedId] = useState(() => loadCopies()[0]?.instanceId || '')
  const [grading, setGrading] = useState(null)
  const [message, setMessage] = useState('')
  const [testPrint, setTestPrint] = useState('')
  const [lookup, setLookup] = useState(null) // cert lookup screen (null: closed)
  const prints = useMemo(() => cards.flatMap(card => card.variants.map(variant => ({ key: `${card.id}::${variant.id}`, card, variant }))), [cards])
  const list = useMemo(() => copies.map(copy => copyCard(copy, cards)).filter(Boolean), [copies, cards])
  const selected = list.find(copy => copy.instanceId === selectedId) || list[0]

  const refresh = next => { setCopies(next); return next }
  const protect = kind => {
    if (!selected) return
    if (selected.graded) { setMessage('Graded cards stay sealed in their slab.'); return }
    const current = selected.protection || 'none'
    const protection = kind === 'none' ? (current === 'toploader' && selected.sleeved ? 'sleeve' : 'none') : kind
    refresh(updateCopy(selected.instanceId, { protection, sleeved: kind === 'toploader' && current === 'sleeve' ? true : undefined }))
    setMessage(kind === 'none' ? 'Taken out.' : `Put in a ${kind === 'sleeve' ? 'penny sleeve' : 'toploader'}.`)
  }
  const handle = rough => {
    if (!selected) return
    const worn = applyWear(selected.condition, { protection: selected.graded ? 'slab' : selected.protection, rough })
    if (worn === selected.condition) { setMessage(rough ? 'It survived the rough handling.' : 'No new wear.'); return }
    refresh(updateCopy(selected.instanceId, { condition: worn }))
    setMessage(rough ? 'Ouch: the rough handling left a mark.' : 'Handling left a little wear.')
  }
  const pullTest = () => {
    const entry = prints.find(item => item.key === testPrint) || prints[0]
    if (!entry) return
    const card = { ...resolveCardVariant(entry.card, entry.variant.id), instanceId: crypto.randomUUID(), condition: generateCondition() }
    const next = refresh(addCopy(card))
    setSelectedId(next[0].instanceId)
    setMessage('A fresh copy came off the press.')
  }
  const startGrading = () => {
    if (!selected || selected.graded) return
    const base = cards.find(card => card.id === selected.baseCardId)
    setGrading({ card: selected, reference: base ? resolveCardVariant(base, selected.variantId) : selected, session: localGradingSession(selected) })
  }

  // cert lookup over the records kept in this browser (FiveM: /gradecheck on the server's records)
  const lookupCert = async cert => {
    const record = getRecord(cert)
    if (!record) return { record: null }
    const base = cards.find(card => card.id === record.baseCardId)
    const copy = list.find(item => item.graded?.cert === record.cert)
    return { record, card: base ? resolveCardVariant(base, record.variantId) : copy || null }
  }

  if (lookup !== null) return <GradeRecordLookup lookup={lookupCert} initialCert={lookup} onClose={() => setLookup(null)} />
  if (grading) return <GradingStation card={grading.card} reference={grading.reference} session={grading.session} debug
    onCancel={() => setGrading(null)}
    onDone={(card, record) => { saveRecord(record); refresh(updateCopy(card.instanceId, { graded: card.graded, protection: 'slab' })); setGrading(null); setMessage(`Graded ${card.graded.grade} ${gradeName(card.graded.grade)} · cert #${card.graded.cert}.`) }} />

  return <section className="grading-lab">
    <div>
      <div className="management-panel-title"><div><strong>Your pulled cards</strong><span>Every copy from a pack has its own small print imperfections. Sleeve them to keep them safe, then grade them.</span></div></div>
      <div className="grading-tool-row" style={{ margin: '10px 0 14px' }}>
        <select value={testPrint} onChange={event => setTestPrint(event.target.value)}>
          {prints.map(entry => <option key={entry.key} value={entry.key}>{entry.card.title} · {entry.variant.name}</option>)}
        </select>
        <button className="ghost" onClick={pullTest} disabled={!prints.length}>Print a test copy</button>
        <button className="ghost" onClick={() => setLookup(selected?.graded?.cert || '')}>Look up a cert</button>
      </div>
      {!list.length && <div className="management-message">No pulled cards yet. Open packs in the Pack / box lab, or print a test copy.</div>}
      <div className="grading-copy-list">
        {list.map(copy => <button key={copy.instanceId} className={`grading-copy ${copy.instanceId === selected?.instanceId ? 'selected' : ''}`} onClick={() => setSelectedId(copy.instanceId)}>
          <strong>{copy.title}</strong>
          <small>{copy.variantName} · {copy.rarity}</small>
          <small>{copy.graded ? `Graded ${copy.graded.grade} ${gradeName(copy.graded.grade)}` : PROTECTION_LABELS[copy.protection || 'none']}</small>
        </button>)}
      </div>
    </div>
    {selected && <div className="grading-copy-preview">
      <RotatableCollectible item={{ ...selected, collectableType: 'trading_card' }} onRough={() => handle(true)} />
      {message && <div className="management-message">{message}</div>}
      <div className="grading-copy-actions">
        {!selected.graded && <>
          <button className="ghost" onClick={() => protect('sleeve')} disabled={selected.protection === 'sleeve' || selected.protection === 'toploader'}>Sleeve</button>
          <button className="ghost" onClick={() => protect('toploader')} disabled={selected.protection === 'toploader'}>Toploader</button>
          <button className="ghost" onClick={() => protect('none')} disabled={!selected.protection || selected.protection === 'none'}>Take out</button>
          <button className="ghost" onClick={() => handle(false)}>Handle it</button>
          <button className="primary" onClick={startGrading}>Grade this card</button>
        </>}
        <button className="danger ghost" onClick={() => { refresh(removeCopy(selected.instanceId)); setMessage('') }}>Discard</button>
      </div>
      <small className="muted">Spinning a raw card hard in the viewer can crease, bend or tear it.</small>
    </div>}
  </section>
}
