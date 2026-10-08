import React, { useEffect, useState } from 'react'
import { bridge } from '../runtime'

const money = n => `$${Math.round(Number(n) || 0).toLocaleString()}`
const when = seconds => seconds ? new Date(seconds * 1000).toLocaleString() : '-'

function RecordTable({ serial, kind, revision }) {
  const [page, setPage] = useState(1)
  const [pageSize, setPageSize] = useState(50)
  const [data, setData] = useState(null)
  const [loading, setLoading] = useState(true)
  const [error, setError] = useState('')
  const [retry, setRetry] = useState(0)
  useEffect(() => {
    let cancelled = false
    setLoading(true); setError(''); setData(null)
    bridge.getVendingRecordPage({ serial, kind, page, pageSize }).then(result => {
      if (cancelled) return
      if (result?.ok === false) throw new Error(result.error || 'Could not load records.')
      setData(result)
    }).catch(reason => { if (!cancelled) setError(reason?.message || String(reason)) })
      .finally(() => { if (!cancelled) setLoading(false) })
    return () => { cancelled = true }
  }, [serial, kind, page, pageSize, revision, retry])

  const history = kind === 'history'
  const title = history ? 'History' : 'Sales'
  const rows = Array.isArray(data?.items) ? data.items : []
  const current = data?.page || page
  const first = data?.total ? (current - 1) * pageSize + 1 : 0
  return <section className={`records-log records-log-${kind}`} aria-label={`${serial} ${title}`}>
    <div className="records-log-heading">
      <h4>{title}</h4>
      <label>Rows per page <select aria-label={`${title} rows per page`} disabled={loading} value={pageSize} onChange={event => { setPageSize(Number(event.target.value)); setPage(1) }}>
        {[25, 50, 100].map(size => <option key={size} value={size}>{size}</option>)}
      </select></label>
    </div>
    <div className="records-log-table" tabIndex={0} aria-label={`${title} table`} aria-busy={loading}>
      <table>
        <thead>{history ? <tr><th>#</th><th>When</th><th>Event</th><th>Operator</th></tr>
          : <tr><th>When</th><th>Item</th><th>Paid with</th><th>Price</th><th>Tax</th><th>Paid to owner</th></tr>}</thead>
        <tbody>
          {rows.map((row, index) => history ? <tr key={index}>
            <td>{first + index}</td><td>{when(row.at)}</td><td>{row.event}</td><td>{row.by || '-'}</td>
          </tr> : <tr key={index}>
            <td>{row.at ? when(row.at) : row.when || '-'}</td><td>{row.item || '-'}</td><td>{row.method === 'cash' ? 'Cash' : 'Card'}</td>
            <td>{money(row.price)}</td><td>{row.method === 'card' ? money(row.tax) : '-'}</td><td>{row.method === 'card' ? money(row.paid) : 'Kept in the cash box'}</td>
          </tr>)}
          {!rows.length && <tr><td colSpan={history ? 4 : 6} className="records-empty" role="status">
            {loading ? 'Loading records…' : error || `No ${kind} recorded yet.`}
            {error && <button onClick={() => setRetry(value => value + 1)}>Retry</button>}
          </td></tr>}
        </tbody>
      </table>
    </div>
    <div className="records-pagination">
      <span role="status">{data ? `${first}–${Math.min(current * pageSize, data.total)} of ${data.total} records · Page ${current} of ${data.pages}` : loading ? 'Loading…' : 'Records unavailable'}</span>
      <button disabled={loading || !data || current <= 1} aria-label={`Previous ${title.toLowerCase()} page`} onClick={() => setPage(current - 1)}>Previous</button>
      <button disabled={loading || !data || current >= data.pages} aria-label={`Next ${title.toLowerCase()} page`} onClick={() => setPage(current + 1)}>Next</button>
    </div>
  </section>
}

export default function VendingRecordTables({ serial, revision }) {
  return <><RecordTable serial={serial} kind="history" revision={revision} /><RecordTable serial={serial} kind="sales" revision={revision} /></>
}
