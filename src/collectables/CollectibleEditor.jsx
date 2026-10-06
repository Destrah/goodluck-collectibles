import { RARITIES, FINISHES, makePrint, printsOf, rarityLabel } from './prints.js'
import { useState } from 'react'
import { artworkPasteProps } from '../utils/compressImage.js'
import ArtworkFileInput from '../components/ArtworkFileInput'
import { useResolvedAsset } from '../runtime/assets'

// Same structure and classes as the trading card editor (components/CardEditor.jsx): identity shared by every
// print, then print tabs with each print's rarity, pull weight and look.
function Field({ label, children, className = '' }) {
  return <label className={`field ${className}`}><span>{label}</span>{children}</label>
}

const hex = (r, g, b) => `#${[r, g, b].map(v => v.toString(16).padStart(2, '0')).join('')}`

// Click the artwork to take its colour (averaged over a few pixels so fur texture doesn't give a stray speck).
function ArtworkColorSampler({ artwork, onPick }) {
  const asset = useResolvedAsset(artwork, { showOriginalWhileLoading: true })
  const [open, setOpen] = useState(false)
  const [note, setNote] = useState('')
  const src = asset.url || artwork
  const eyeDropper = typeof window !== 'undefined' && 'EyeDropper' in window
  const pickScreen = async () => {
    try { const { sRGBHex } = await new window.EyeDropper().open(); onPick(sRGBHex) } catch { /* cancelled */ }
  }
  const sample = event => {
    const img = event.currentTarget, rect = img.getBoundingClientRect()
    const x = Math.floor((event.clientX - rect.left) / rect.width * img.naturalWidth), y = Math.floor((event.clientY - rect.top) / rect.height * img.naturalHeight)
    try {
      const r = 2, canvas = document.createElement('canvas'); canvas.width = canvas.height = r * 2 + 1
      const g = canvas.getContext('2d', { willReadFrequently: true }); g.drawImage(img, x - r, y - r, canvas.width, canvas.height, 0, 0, canvas.width, canvas.height)
      const data = g.getImageData(0, 0, canvas.width, canvas.height).data
      let rr = 0, gg = 0, bb = 0, n = 0
      for (let k = 0; k < data.length; k += 4) if (data[k + 3] > 100) { rr += data[k]; gg += data[k + 1]; bb += data[k + 2]; n++ }
      if (!n) { setNote('That spot is transparent — click on the plushie itself.'); return }
      onPick(hex(Math.round(rr / n), Math.round(gg / n), Math.round(bb / n))); setNote('')
    } catch { setNote(eyeDropper ? 'This image host blocks colour reading; use the screen eyedropper instead.' : 'This image host blocks colour reading; pick the colour manually.') }
  }
  if (!artwork && !eyeDropper) return null
  return <div className="artwork-color-sampler">
    <div className="panel-actions">
      {artwork && <button type="button" className="ghost small-button" onClick={() => setOpen(!open)}>{open ? 'Hide artwork' : 'Pick from artwork'}</button>}
      {eyeDropper && <button type="button" className="ghost small-button" onClick={pickScreen}>Screen eyedropper</button>}
    </div>
    {open && artwork && <img src={src} crossOrigin="anonymous" alt="Click to sample a colour" draggable="false" onClick={sample} />}
    {note && <small>{note}</small>}
  </div>
}

function TypedField({ field, value, onChange, className, onInfo, artwork }) {
  // Image fields pair the URL box (paste / drop an image too) with a file chooser, which is a paste box in FiveM.
  if (field.type === 'image') return <>
    <Field label={field.label} className={className}><input {...artworkPasteProps(onChange, { onInfo })} placeholder={field.placeholder || 'URL, or paste / drop an image'} value={value ?? ''} onChange={e => onChange(e.target.value)} /></Field>
    <Field label={field.fileLabel || `${field.label.replace(/ URL.*$/, '')} file`}><ArtworkFileInput onLoaded={onChange} options={{ onInfo }} /></Field>
  </>
  if (field.options) return <Field label={field.label} className={className}><select value={value ?? field.options[0].value} onChange={e => onChange(e.target.value)}>{field.options.map(option => <option key={option.value} value={option.value}>{option.label}</option>)}</select></Field>
  if (field.type === 'range') {
    const shown = value ?? field.fallback ?? field.min
    return <Field label={`${field.label} — ${shown}${field.suffix || ''}`} className={`range-field ${className || ''}`}><input type="range" min={field.min} max={field.max} step={field.step || 1} value={shown} onChange={e => onChange(Number(e.target.value))} /></Field>
  }
  // the sampler sits outside the <label> so clicking the artwork doesn't also open the colour input
  if (field.type === 'color' && field.sampleArtwork) return <div className={`artwork-color-field ${className || ''}`}>
    <Field label={field.label}><input type="color" value={value || field.fallback || '#ffffff'} onChange={e => onChange(e.target.value)} /></Field>
    <ArtworkColorSampler artwork={artwork} onPick={onChange} />
  </div>
  if (field.type === 'color') return <Field label={field.label} className={className}><input type="color" value={value || field.fallback || '#ffffff'} onChange={e => onChange(e.target.value)} /></Field>
  return <Field label={field.label} className={className}><input type={field.type || 'text'} placeholder={field.placeholder} value={value ?? ''} onChange={e => onChange(field.type === 'number' ? Number(e.target.value) : e.target.value)} /></Field>
}

export default function CollectibleEditor({ module, draft, printId, onSelectPrint, onChange, onSave, onRevert, onDelete, onDuplicate, dirty, isNew, saving, saveError, onPrint }) {
  const prints = printsOf(draft)
  // FiveM manual print: one inventory item of the saved version, marked MANUAL PRINT
  const [printState, setPrintState] = useState({ busy: false, note: '' })
  const printItem = async () => {
    setPrintState({ busy: true, note: '' })
    try { setPrintState({ busy: false, note: await onPrint(print) }) }
    catch (error) { setPrintState({ busy: false, note: error?.message || String(error) }) }
  }
  // Uploaded artwork is downscaled/re-encoded first so it fits browser storage and FiveM saves.
  const [uploadNote, setUploadNote] = useState('')
  const pasteArt = onLoaded => artworkPasteProps(onLoaded, { onInfo: setUploadNote })
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
      {uploadNote && <div className="editor-save-hint">{uploadNote}</div>}

      <div className="editor-subheading">
        <div><span className="eyebrow">Base {singular}</span><h4>Identity</h4></div>
        <small>Shared by every print.</small>
      </div>
      <div className="form-grid compact-grid">
        <Field label="Name"><input value={draft.title || ''} onChange={e => patchBase('title', e.target.value)} /></Field>
        <Field label={`${module.singular} pull weight`}><input type="number" min="1" value={draft.chanceWeight || 1} onChange={e => patchBase('chanceWeight', Number(e.target.value))} /></Field>
        <Field label="Base artwork URL"><input {...pasteArt(value => patchBase('image', value))} placeholder="URL, or paste / drop an image" value={draft.image || ''} onChange={e => patchBase('image', e.target.value)} /></Field>
        <Field label="Base artwork file"><ArtworkFileInput onLoaded={value => patchBase('image', value)} options={{ onInfo: setUploadNote }} /></Field>
        <Field label="Back artwork URL"><input {...pasteArt(value => patchBase('backImage', value))} placeholder={module.id === 'plushie' ? 'Blank = soft back from the front colours' : 'Blank = minted MC back'} value={draft.backImage || ''} onChange={e => patchBase('backImage', e.target.value)} /></Field>
        <Field label="Back artwork file"><ArtworkFileInput onLoaded={value => patchBase('backImage', value)} options={{ onInfo: setUploadNote }} /></Field>
        {module.fields.map(field => <TypedField key={field.key} field={field} value={draft[field.key]} onChange={value => patchBase(field.key, value)} onInfo={setUploadNote} />)}
        <Field label="Description" className="span-2"><textarea rows="3" value={draft.description || ''} onChange={e => patchBase('description', e.target.value)} /></Field>
      </div>

      <div className="variant-editor">
        <div className="editor-subheading variant-heading">
          <div><span className="eyebrow">Prints / versions</span><h4>{print.name}</h4></div>
          <div className="variant-actions">
            <button className="ghost small-button" onClick={addPrint}>+ Print</button>
            <button className="ghost small-button" onClick={duplicatePrint}>Duplicate</button>
            <button className="danger ghost small-button" disabled={prints.length <= 1} onClick={removePrint}>Remove</button>
            {onPrint && <button className="primary small-button" disabled={dirty || isNew || saving || printState.busy} title={dirty || isNew ? 'Save changes first: the item is printed from the saved version.' : 'Put one item of this print in your inventory, marked MANUAL PRINT.'} onClick={printItem}>{printState.busy ? 'Printing…' : 'Print item'}</button>}
          </div>
        </div>
        {printState.note && <div className="editor-save-hint">{printState.note}</div>}
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
          <Field label="Print artwork URL"><input {...pasteArt(value => patchPrint({ image: value }))} placeholder="Blank = base artwork" value={print.image || ''} onChange={e => patchPrint({ image: e.target.value })} /></Field>
          <Field label="Print artwork file"><ArtworkFileInput onLoaded={value => patchPrint({ image: value })} options={{ onInfo: setUploadNote }} /></Field>
          <Field label="Print back artwork URL"><input {...pasteArt(value => patchPrint({ backImage: value }))} placeholder="Blank = base back artwork" value={print.backImage || ''} onChange={e => patchPrint({ backImage: e.target.value })} /></Field>
          <Field label="Print back artwork file"><ArtworkFileInput onLoaded={value => patchPrint({ backImage: value })} options={{ onInfo: setUploadNote }} /></Field>
          {module.printFields?.map(field => <TypedField key={field.key} field={field} value={print[field.key]} onChange={value => patchPrint({ [field.key]: value })} onInfo={setUploadNote} artwork={print.image || draft.image} />)}
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
