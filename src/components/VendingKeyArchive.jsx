import React from 'react'

const when = seconds => seconds ? new Date(seconds * 1000).toLocaleString() : '-'

export default function VendingKeyArchive({ archive, currentLockId }) {
  if (!archive) return <p>No key records yet.</p>
  return <div className="vending-key-archive">
    <p>Permanent records include retired cylinders and keys. Issuance identifies the original recipient; possession may have changed.</p>
    {(archive.cylinders || []).map(cylinder => <section key={cylinder.id}>
      <h4>{cylinder.id} · {cylinder.id === currentLockId ? 'Current' : 'Retired'}</h4>
      <p>Installed {when(cylinder.installedAt)} by {cylinder.installedBy || '-'}{cylinder.retiredAt ? ` · Retired ${when(cylinder.retiredAt)} by ${cylinder.retiredBy || '-'}` : ''}</p>
      <div className="vending-key-table"><table>
        <thead><tr><th>Key ID</th><th>Access</th><th>Issued to</th><th>Issued by / date</th></tr></thead>
        <tbody>{(archive.keys || []).filter(key => key.lockId === cylinder.id).map(key => <tr key={key.id}>
          <td>{key.id}{key.deliveryFailed && <strong> · Delivery failed</strong>}</td><td>{key.access}</td>
          <td>{key.issuedToName}<small>{key.issuedTo}</small></td>
          <td>{key.issuedByName}<small>{key.issuedBy} · {when(key.issuedAt)}</small></td>
        </tr>)}</tbody>
      </table></div>
      {!(archive.keys || []).some(key => key.lockId === cylinder.id) && <p>No keys issued for this cylinder.</p>}
    </section>)}
  </div>
}
