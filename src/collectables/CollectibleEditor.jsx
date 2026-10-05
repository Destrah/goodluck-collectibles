import { RARITIES, FINISHES, makePrint, printsOf, rarityLabel } from './prints.js'

// Same structure and classes as the trading card editor (components/CardEditor.jsx): identity shared by every
// print, then print tabs with each print's rarity, pull weight and look.
function Field({ label, children, className = '' }) {
  return <label className={`field ${className}`}><span>{label}</span>{children}</label>
}

const loadFile = (onLoaded, file) => {
  if (!file) return
  const reader = new FileReader()
  reader.onload = () => onLoaded(reader.result)
  reader.readAsDataURL(file)
}

function TypedField({ field, value, onChange, className }) {
  if (field.options) return <Field label={field.label} className={className}><select value={value ?? field.options[0].value} onChange={e => onChange(e.target.value)}>{field.options.map(option => <option key={option.value} value={option.value}>{option.label}</option>)}</select></Field>
  if (field.type === 'range') {
    const shown = value ?? field.fallback ?? field.min
    return <Field label={`${field.label} — ${shown}${field.suffix || ''}`} className={`range-field ${className || ''}`}><input type="range" min={field.min} max={field.max} step={field.step || 1} value={shown} onChange={e => onChange(Number(e.target.value))} /></Field>
  }
  if (field.type === 'color') return <Field label={field.label} className={className}><input type="color" value={value || field.fallback || '#ffffff'} onChange={e => onChange(e.target.value)} /></Field>
  return <Field label={field.label} className={className}><input type={field.type || 'text'} placeholder={field.placeholder} value={value ?? ''} onChange={e => onChange(field.type === 'number' ? Number(e.target.value) : e.target.value)} /></Field>
}

export default function CollectibleEditor({ module, draft, printId, onSelectPrint, onChange, onSave, onRevert, onDelete, onDuplicate, dirty, isNew, saving, saveError }) {
  const prints = printsOf(draft)
  const print = prints.find(entry => entry.id === printId) || prints[0]
  const patchBase = (key, value) => onChange({ ...draft, [key]: value })
  const patchPrint = patch => onChange({ ...draft, prints: prints.map(entry => entry.id === print.id ? { ...entry, ...patch } : entry) })
  const addPrint = () => {
    const next = makePrint({ name: `Print ${prints.length + 1}`, rarityKey: print.rarityKey, chanceWeight: print.chanceWeight })
    onChange({ ...draft, prints: [...prints, next] }); onSelectPrint(next.id)
  }
  const duplicatePrint = () => {
    const next = { ...structuredClone(print), id: crypto.randomUUID(), name: `${print.name} Copy` }
    onChange({ ...draft, prints: [...prints, next] }); onSelectPrint(next.id)
  }
  const removePrint = () => {
    if (prints.length <= 1) return
    const remaining = prints.filter(entry => entry.id !== print.id)
    onChange({ ...draft, prints: remaining }); onSelectPrint(remaining[0].id)
  }
  const singular = module.singular.toLowerCase()
  const totalWeight = prints.reduce((sum, entry) => sum + Math.max(1, Number(entry.chanceWeight) || 1), 0)
  const odds = entry => `${Math.round(Math.max(1, Number(entry.chanceWeight) || 1) / totalWeight * 1000) / 10}%`

  return (
    <div className="editor-panel">
      <div className="panel-heading">
        <div><p>Draft editor</p><h3>{module.singular} configuration</h3><div className={`editor-save-state ${dirty ? 'is-dirty' : 'is-saved'}`}>{dirty ? '● Unsaved changes' : '✓ Saved'}</div></div>
        <div className="panel-actions editor-primary-actions">
          <button className="ghost" onClick={onDuplicate} disabled={saving}>Duplicate {singular}</button>
          {!isNew && <button className="danger ghost" onClick={onDelete} disabled={saving}>Delete</button>}
          <button className="ghost" onClick={onRevert} disabled={!dirty || saving}>{isNew ? `Cancel new ${singular}` : 'Revert changes'}</button>
          <button className="primary" onClick={onSave} disabled={!dirty || saving}>{saving ? 'Saving…' : 'Save changes'}</button>
        </div>
      </div>
      {saveError && <div className="editor-save-error">{saveError}</div>}
      <div className="editor-save-hint">Edits update the preview only until you save. Pulled copies keep the look they had when they were pulled.</div>

      <div className="editor-subheading">
        <div><span className="eyebrow">Base {singular}</span><h4>Identity</h4></div>
        <small>Shared by every print.</small>
      </div>
      <div className="form-grid compact-grid">
        <Field label="Name"><input value={draft.title || ''} onChange={e => patchBase('title', e.target.value)} /></Field>
        <Field label={`${module.singular} pull weight`}><input type="number" min="1" value={draft.chanceWeight || 1} onChange={e => patchBase('chanceWeight', Number(e.target.value))} /></Field>
        <Field label="Base artwork URL"><input value={draft.image || ''} onChange={e => patchBase('image', e.target.value)} /></Field>
        <Field label="Base artwork file"><input className="file-input" type="file" accept="image/*" onChange={e => loadFile(value => patchBase('image', value), e.target.files?.[0])} /></Field>
        <Field label="Back artwork URL"><input placeholder={module.id === 'plushie' ? 'Blank = soft back from the front colours' : 'Blank = minted MC back'} value={draft.backImage || ''} onChange={e => patchBase('backImage', e.target.value)} /></Field>
        {module.fields.map(field => <TypedField key={field.key} field={field} value={draft[field.key]} onChange={value => patchBase(field.key, value)} />)}
        <Field label="Description" className="span-2"><textarea rows="3" value={draft.description || ''} onChange={e => patchBase('description', e.target.value)} /></Field>
      </div>

      <div className="variant-editor">
        <div className="editor-subheading variant-heading">
          <div><span className="eyebrow">Prints / versions</span><h4>{print.name}</h4></div>
          <div className="variant-actions">
            <button className="ghost small-button" onClick={addPrint}>+ Print</button>
            <button className="ghost small-button" onClick={duplicatePrint}>Duplicate</button>
            <button className="danger ghost small-button" disabled={prints.length <= 1} onClick={removePrint}>Remove</button>
          </div>
        </div>
        <div className="variant-tabs">
          {prints.map(entry => (
            <button key={entry.id} className={entry.id === print.id ? 'active' : ''} onClick={() => onSelectPrint(entry.id)}>
              <strong>{entry.name}</strong><small>{rarityLabel(entry.rarityKey)} · {odds(entry)}</small>
            </button>
          ))}
        </div>

        <div className="form-grid compact-grid">
          <Field label="Print name"><input value={print.name || ''} onChange={e => patchPrint({ name: e.target.value })} /></Field>
          <Field label="Rarity tier"><select value={print.rarityKey || 'common'} onChange={e => patchPrint({ rarityKey: e.target.value })}>{RARITIES.map(x => <option key={x.value} value={x.value}>{x.label}</option>)}</select></Field>
          <Field label={`Print chance weight (${odds(print)} of this ${singular})`}><input type="number" min="1" value={print.chanceWeight || 1} onChange={e => patchPrint({ chanceWeight: Number(e.target.value) })} /></Field>
          <Field label="Finish"><select value={print.finish || draft.finish || 'none'} onChange={e => patchPrint({ finish: e.target.value })}>{FINISHES.map(x => <option key={x.value} value={x.value}>{x.label}</option>)}</select></Field>
          <Field label={`Finish strength — ${print.finishStrength ?? draft.finishStrength ?? 60}%`} className="span-2 range-field"><input type="range" min="0" max="100" value={print.finishStrength ?? draft.finishStrength ?? 60} onChange={e => patchPrint({ finishStrength: Number(e.target.value) })} /></Field>
          <Field label="Print artwork URL"><input placeholder="Blank = base artwork" value={print.image || ''} onChange={e => patchPrint({ image: e.target.value })} /></Field>
          <Field label="Print artwork file"><input className="file-input" type="file" accept="image/*" onChange={e => loadFile(value => patchPrint({ image: value }), e.target.files?.[0])} /></Field>
          <Field label="Print back artwork URL" className="span-2"><input placeholder="Blank = base back artwork" value={print.backImage || ''} onChange={e => patchPrint({ backImage: e.target.value })} /></Field>
          {module.printFields?.map(field => <TypedField key={field.key} field={field} value={print[field.key]} onChange={value => patchPrint({ [field.key]: value })} />)}
          {module.framing && <div className="art-position-controls native-art-position span-2">
            <div className="art-position-heading"><strong>Face artwork crop / position</strong><small>Positions the artwork inside the coin face, the same way card artwork is framed. Used by the 2D and 3D coin.</small></div>
            <Field label={`Horizontal — ${Math.round(print.imagePositionX ?? 50)}%`} className="range-field"><input type="range" min="0" max="100" value={print.imagePositionX ?? 50} onChange={e => patchPrint({ imagePositionX: Number(e.target.value) })} /></Field>
            <Field label={`Vertical — ${Math.round(print.imagePositionY ?? 50)}%`} className="range-field"><input type="range" min="0" max="100" value={print.imagePositionY ?? 50} onChange={e => patchPrint({ imagePositionY: Number(e.target.value) })} /></Field>
            <Field label={`Zoom — ${Math.round(print.imageZoom ?? 100)}%`} className="range-field"><input type="range" min="100" max="220" value={print.imageZoom ?? 100} onChange={e => patchPrint({ imageZoom: Number(e.target.value) })} /></Field>
            <button className="ghost small-button" type="button" onClick={() => patchPrint({ imagePositionX: 50, imagePositionY: 50, imageZoom: 100 })}>Center / reset face art</button>
          </div>}
        </div>

        <div className="color-section">
          <h4>Print colours</h4>
          <p>{module.id === 'challenge_coin' ? 'The accent is the metal colour of the coin, its rim and edge.' : 'The accent tints the glow and fuzz highlights; use fabric colour above to recolour the plushie itself.'}</p>
          <div className="color-grid">
            <Field label="Accent"><input type="color" value={print.accent || draft.accent || '#c9a34d'} onChange={e => patchPrint({ accent: e.target.value })} /></Field>
          </div>
        </div>
      </div>
    </div>
  )
}
