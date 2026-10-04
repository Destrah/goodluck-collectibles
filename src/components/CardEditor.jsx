import React from 'react'
import { CARD_TYPES, HOLOS, LAYOUTS, MASK_SOURCES, RARITIES, SUBJECT_EFFECTS, makeSubjectLayer, makeVariant } from '../cardData'
import { useResolvedAsset } from '../runtime/assets'

function Field({ label, children, className = '' }) {
  return <label className={`field ${className}`}><span>{label}</span>{children}</label>
}

function MaskAssetStatus({ url }) {
  const state = useResolvedAsset(url)
  if (!url) return <div className="mask-asset-status"><span><strong>No mask URL.</strong> Add a local path, data URL, or remote HTTP(S) image.</span></div>
  if (state.status === 'loading') return <div className="mask-asset-status is-loading"><span><strong>Mask loading…</strong> Testing direct browser access and the runtime resolver if needed.</span></div>
  if (state.status === 'error') {
    return (
      <div className="mask-asset-status is-error">
        <span><strong>Mask URL failed · {state.code || 'LOAD_FAILED'}</strong><br />{state.error || 'The image could not be loaded.'}</span>
      </div>
    )
  }
  const source = {
    local: 'local asset', data: 'embedded data image', blob: 'browser object URL',
    'direct-cors': 'remote URL (CORS allowed)', 'vite-proxy': 'Vite remote resolver',
    'fivem-proxy': 'FiveM server resolver', 'fivem-proxy-cache': 'FiveM server resolver cache',
  }[state.source] || state.source || 'asset resolver'
  const fallback = state.directError?.code ? ` · direct browser load: ${state.directError.code}` : ''
  return <div className="mask-asset-status is-loaded"><span><strong>Mask loaded</strong> · {source}{fallback}</span></div>
}

const presetColors = {
  'outline-gold': ['#f59e0b', '#fde68a', '#ffffff'],
  'outline-silver': ['#94a3b8', '#f8fafc', '#cbd5e1'],
  'outline-rainbow': ['#ff4d8d', '#4df3ff', '#ffe66d'],
  'foil-rainbow': ['#ff4d8d', '#4df3ff', '#ffe66d'],
  'foil-prism': ['#38bdf8', '#a78bfa', '#f8fafc'],
  'foil-etched': ['#d8b4fe', '#f8fafc', '#67e8f9'],
  'foil-cosmos': ['#c084fc', '#60a5fa', '#fb7185'],
  'foil-galaxy': ['#ff4dc8', '#38e8ff', '#fff27a'],
  'foil-flame': ['#f97316', '#fb7185', '#fde047'],
  'foil-flame-v2': ['#ff4b18', '#ff9f2d', '#ffe36b'],
  'foil-flame-hybrid': ['#ff5418', '#ffad33', '#fff08a'],
  'foil-flame-anime': ['#ef2b12', '#ff7a12', '#ffd62e'],
  'foil-flame-smoky': ['#f04a18', '#ff9a28', '#ffe077'],
  'foil-electric': ['#2563eb', '#67e8f9', '#f8fafc'],
  'foil-water': ['#0ea5e9', '#67e8f9', '#dbeafe'],
  'foil-smoke': ['#64748b', '#cbd5e1', '#0f172a'],
  'foil-frost': ['#a5f3fc', '#eff6ff', '#93c5fd'],
}

export default function CardEditor({ card, selectedVariantId, onSelectVariant, onChange, onDelete, onDuplicate, dirty, isNew, saving, saveError, onSave, onRevert }) {
  const variant = card.variants.find(item => item.id === selectedVariantId) || card.variants[0]
  const variantUsesDifferentImage = Boolean(String(variant.image || '').trim()) && String(variant.image || '').trim() !== String(card.image || '').trim()
  const patchBase = (key, value) => onChange({ ...card, [key]: value })
  const patchVariant = (key, value) => {
    const variants = card.variants.map(item => item.id === variant.id ? { ...item, [key]: value } : item)
    onChange({ ...card, variants })
  }

  const patchVariantObject = (nextVariant) => {
    onChange({ ...card, variants: card.variants.map(item => item.id === variant.id ? nextVariant : item) })
  }

  const setVariantArtwork = (value) => {
    const image = String(value || '')
    const different = Boolean(image.trim()) && image.trim() !== String(card.image || '').trim()
    patchVariantObject(different
      ? { ...variant, image }
      : { ...variant, image, imagePositionX: undefined, imagePositionY: undefined, imageZoom: undefined })
  }

  const updateAttack = (index, key, value) => {
    const attacks = card.attacks.map((attack, i) => i === index ? { ...attack, [key]: value } : attack)
    patchBase('attacks', attacks)
  }
  const addAttack = () => patchBase('attacks', [...card.attacks, { name: 'New Move', cost: 1, damage: 10, text: 'Describe this move.' }])
  const removeAttack = (index) => patchBase('attacks', card.attacks.filter((_, i) => i !== index))

  const loadFile = (onLoaded, file) => {
    if (!file) return
    const reader = new FileReader()
    reader.onload = () => onLoaded(reader.result)
    reader.readAsDataURL(file)
  }

  const addVariant = () => {
    const next = makeVariant({
      name: `Print ${card.variants.length + 1}`,
      rarity: variant.rarity,
      rarityKey: variant.rarityKey,
      layout: variant.layout,
      holo: variant.holo,
      holoStrength: variant.holoStrength,
    })
    onChange({ ...card, variants: [...card.variants, next] })
    onSelectVariant(next.id)
  }

  const duplicateVariant = () => {
    const next = {
      ...structuredClone(variant),
      id: crypto.randomUUID(),
      name: `${variant.name} Copy`,
      subjectLayers: (variant.subjectLayers || []).map(layer => ({ ...layer, id: crypto.randomUUID() })),
    }
    onChange({ ...card, variants: [...card.variants, next] })
    onSelectVariant(next.id)
  }

  const removeVariant = () => {
    if (card.variants.length <= 1) return
    const remaining = card.variants.filter(item => item.id !== variant.id)
    onChange({ ...card, variants: remaining })
    onSelectVariant(remaining[0].id)
  }

  const addSubjectLayer = () => {
    patchVariant('subjectLayers', [...(variant.subjectLayers || []), makeSubjectLayer({
      name: `Subject layer ${(variant.subjectLayers || []).length + 1}`,
      foilA: variant.foilA || card.foilA,
      foilB: variant.foilB || card.foilB,
      foilC: variant.foilC || card.foilC,
    })])
  }

  const updateSubjectLayer = (index, patch) => {
    const layers = (variant.subjectLayers || []).map((layer, i) => i === index ? { ...layer, ...patch } : layer)
    patchVariant('subjectLayers', layers)
  }

  const changeLayerMode = (index, mode) => {
    const colors = presetColors[mode]
    updateSubjectLayer(index, colors
      ? { mode, foilA: colors[0], foilB: colors[1], foilC: colors[2] }
      : { mode })
  }

  const removeSubjectLayer = (index) => patchVariant('subjectLayers', (variant.subjectLayers || []).filter((_, i) => i !== index))

  return (
    <div className="editor-panel">
      <div className="panel-heading">
        <div><p>Draft editor</p><h3>Card configuration</h3><div className={`editor-save-state ${dirty ? 'is-dirty' : 'is-saved'}`}>{dirty ? '● Unsaved changes' : '✓ Saved'}</div></div>
        <div className="panel-actions editor-primary-actions">
          <button className="ghost" onClick={onDuplicate} disabled={saving}>Duplicate card</button>
          {!isNew && <button className="danger ghost" onClick={onDelete} disabled={saving}>Delete</button>}
          <button className="ghost" onClick={onRevert} disabled={!dirty || saving}>{isNew ? 'Cancel new card' : 'Revert changes'}</button>
          <button className="primary" onClick={onSave} disabled={!dirty || saving}>{saving ? 'Saving…' : 'Save changes'}</button>
        </div>
      </div>
      {saveError && <div className="editor-save-error">{saveError}</div>}
      <div className="editor-save-hint">Edits update the preview only until you save. <kbd>Ctrl</kbd> + <kbd>S</kbd> saves this card.</div>

      <div className="editor-subheading">
        <div><span className="eyebrow">Base card</span><h4>Character / card identity</h4></div>
        <small>Shared by every print variant.</small>
      </div>

      <div className="form-grid compact-grid">
        <Field label="Title"><input value={card.title} onChange={e => patchBase('title', e.target.value)} /></Field>
        <Field label="Subtitle"><input value={card.subtitle} onChange={e => patchBase('subtitle', e.target.value)} /></Field>
        <Field label="HP"><input type="number" min="1" max="999" value={card.hp} onChange={e => patchBase('hp', Number(e.target.value))} /></Field>
        <Field label="Game type"><select value={card.type} onChange={e => patchBase('type', e.target.value)}>{CARD_TYPES.map(type => <option key={type}>{type}</option>)}</select></Field>
        <Field label="Card pull weight"><input type="number" min="1" value={card.chanceWeight || 1} onChange={e => patchBase('chanceWeight', Number(e.target.value))} /></Field>
        <Field label="Base artwork URL"><input value={card.image} onChange={e => patchBase('image', e.target.value)} /></Field>
        <Field label="Base artwork file" className="span-2"><input className="file-input" type="file" accept="image/*" onChange={e => loadFile(value => patchBase('image', value), e.target.files?.[0])} /></Field>
        <div className="art-position-controls native-art-position span-2">
          <div className="art-position-heading"><strong>Base artwork crop / position</strong><small>Move the focal point or zoom the image so the correct part shows inside the card frame. Subject/mask layers follow this exact crop.</small></div>
          <Field label={`Horizontal — ${Math.round(card.imagePositionX ?? 50)}%`} className="range-field"><input type="range" min="0" max="100" step="1" value={card.imagePositionX ?? 50} onChange={e => patchBase('imagePositionX', Number(e.target.value))} /></Field>
          <Field label={`Vertical — ${Math.round(card.imagePositionY ?? 50)}%`} className="range-field"><input type="range" min="0" max="100" step="1" value={card.imagePositionY ?? 50} onChange={e => patchBase('imagePositionY', Number(e.target.value))} /></Field>
          <Field label={`Zoom — ${Math.round(card.imageZoom ?? 100)}%`} className="range-field"><input type="range" min="100" max="220" step="1" value={card.imageZoom ?? 100} onChange={e => patchBase('imageZoom', Number(e.target.value))} /></Field>
          <button className="ghost small-button" type="button" onClick={() => onChange({ ...card, imagePositionX: 50, imagePositionY: 50, imageZoom: 100 })}>Center / reset base art</button>
        </div>
        <Field label="Description" className="span-2"><textarea rows="3" value={card.description} onChange={e => patchBase('description', e.target.value)} /></Field>
      </div>

      <div className="variant-editor">
        <div className="editor-subheading variant-heading">
          <div><span className="eyebrow">Print variants</span><h4>{variant.name}</h4></div>
          <div className="variant-actions">
            <button className="ghost small-button" onClick={addVariant}>+ Print</button>
            <button className="ghost small-button" onClick={duplicateVariant}>Duplicate</button>
            <button className="danger ghost small-button" disabled={card.variants.length <= 1} onClick={removeVariant}>Remove</button>
          </div>
        </div>

        <div className="variant-tabs">
          {card.variants.map(item => (
            <button key={item.id} className={item.id === variant.id ? 'active' : ''} onClick={() => onSelectVariant(item.id)}>
              <strong>{item.name}</strong><small>{item.rarityKey.replace('_', ' ')}</small>
            </button>
          ))}
        </div>

        <div className="form-grid compact-grid">
          <Field label="Print name"><input value={variant.name} onChange={e => patchVariant('name', e.target.value)} /></Field>
          <Field label="Rarity label"><input value={variant.rarity} onChange={e => patchVariant('rarity', e.target.value)} /></Field>
          <Field label="Pack rarity tier"><select value={variant.rarityKey || 'common'} onChange={e => patchVariant('rarityKey', e.target.value)}>{RARITIES.map(x => <option key={x.value} value={x.value}>{x.label}</option>)}</select></Field>
          <Field label="Variant chance weight"><input type="number" min="1" value={variant.chanceWeight || 1} onChange={e => patchVariant('chanceWeight', Number(e.target.value))} /></Field>
          <Field label="Card layout"><select value={variant.layout} onChange={e => patchVariant('layout', e.target.value)}>{LAYOUTS.map(x => <option key={x.value} value={x.value}>{x.label}</option>)}</select></Field>
          <Field label="Full-card holo"><select value={variant.holo} onChange={e => patchVariant('holo', e.target.value)}>{HOLOS.map(x => <option key={x.value} value={x.value}>{x.label}</option>)}</select></Field>
          <Field label={`Holo strength — ${variant.holoStrength ?? 55}%`} className="span-2 range-field">
            <input type="range" min="0" max="100" step="1" value={variant.holoStrength ?? 55} onChange={e => patchVariant('holoStrength', Number(e.target.value))} />
          </Field>
          <Field label="Variant artwork URL"><input placeholder="Blank = base artwork" value={variant.image || ''} onChange={e => setVariantArtwork(e.target.value)} /></Field>
          <Field label="Variant artwork file"><input className="file-input" type="file" accept="image/*" onChange={e => loadFile(setVariantArtwork, e.target.files?.[0])} /></Field>
          {variantUsesDifferentImage && <>
            <button className="ghost span-2" onClick={() => patchVariantObject({ ...variant, image: '', imagePositionX: undefined, imagePositionY: undefined, imageZoom: undefined })}>Use base artwork for this print</button>
            <div className="art-position-controls native-art-position span-2">
              <div className="art-position-heading"><strong>Print artwork crop / position</strong><small>This print uses a different image, so it can have its own crop. Subject/mask layers follow this exact crop.</small></div>
              <Field label={`Horizontal — ${Math.round(variant.imagePositionX ?? 50)}%`} className="range-field"><input type="range" min="0" max="100" step="1" value={variant.imagePositionX ?? 50} onChange={e => patchVariant('imagePositionX', Number(e.target.value))} /></Field>
              <Field label={`Vertical — ${Math.round(variant.imagePositionY ?? 50)}%`} className="range-field"><input type="range" min="0" max="100" step="1" value={variant.imagePositionY ?? 50} onChange={e => patchVariant('imagePositionY', Number(e.target.value))} /></Field>
              <Field label={`Zoom — ${Math.round(variant.imageZoom ?? 100)}%`} className="range-field"><input type="range" min="100" max="220" step="1" value={variant.imageZoom ?? 100} onChange={e => patchVariant('imageZoom', Number(e.target.value))} /></Field>
              <button className="ghost small-button" type="button" onClick={() => patchVariantObject({ ...variant, imagePositionX: 50, imagePositionY: 50, imageZoom: 100 })}>Center / reset print art</button>
            </div>
          </>}
        </div>

        <div className="color-section">
          <h4>Print foil colors</h4>
          <p>Leave a print color empty to inherit the base card color.</p>
          <div className="color-grid">
            <Field label="Accent"><input type="color" value={variant.accent || card.accent} onChange={e => patchVariant('accent', e.target.value)} /></Field>
            <Field label="Foil A"><input type="color" value={variant.foilA || card.foilA} onChange={e => patchVariant('foilA', e.target.value)} /></Field>
            <Field label="Foil B"><input type="color" value={variant.foilB || card.foilB} onChange={e => patchVariant('foilB', e.target.value)} /></Field>
            <Field label="Foil C"><input type="color" value={variant.foilC || card.foilC} onChange={e => patchVariant('foilC', e.target.value)} /></Field>
          </div>
        </div>

        <div className="subject-editor">
          <div className="section-title">
            <div>
              <h4>Subject / character foil layers</h4>
              <p>Add transparent cutouts or true mask-only PNGs. Each layer can have its own image, effect, strength, and colors on top of the full-card holo.</p>
            </div>
            <button className="ghost" onClick={addSubjectLayer}>+ Subject layer</button>
          </div>
          <div className="mask-help"><strong>Supported workflows:</strong> (1) a full-color transparent subject cutout, (2) a dedicated mask-only PNG, or (3) a black/white luminance mask. Use <em>Alpha mask</em> for transparent PNG/WebP cutouts. Use <em>Luminance mask</em> when white should reveal the foil. Use <em>Inverted luminance</em> when black should reveal the foil, which is useful for some mask sheets exported from art tools.<br /><br /><strong>Reference sample:</strong> select <em>Holo Mask Lab</em> in the card list. It now includes dedicated outline, electric, flame, and water examples using separate subject, outline-ring, and accent masks.</div>

          {(variant.subjectLayers || []).map((layer, index) => (
            <div className="subject-layer-editor" key={layer.id}>
              <div className="subject-layer-title"><strong>{layer.name || `Layer ${index + 1}`}</strong><button className="icon-button" onClick={() => removeSubjectLayer(index)}>×</button></div>
              <div className="form-grid compact-grid">
                <Field label="Layer name"><input value={layer.name || ''} onChange={e => updateSubjectLayer(index, { name: e.target.value })} /></Field>
                <Field label="Effect"><select value={layer.mode} onChange={e => changeLayerMode(index, e.target.value)}>{SUBJECT_EFFECTS.map(x => <option key={x.value} value={x.value}>{x.label}</option>)}</select></Field>
                <Field label="Subject / mask image URL"><input value={layer.image || ''} onChange={e => updateSubjectLayer(index, { image: e.target.value })} /></Field>
                <Field label="Subject / mask file"><input className="file-input" type="file" accept="image/png,image/webp,image/jpeg,image/jpg" onChange={e => loadFile(value => updateSubjectLayer(index, { image: value }), e.target.files?.[0])} /></Field>
                <Field label="Mask source"><select value={layer.maskSource || 'alpha'} onChange={e => updateSubjectLayer(index, { maskSource: e.target.value })}>{MASK_SOURCES.map(x => <option key={x.value} value={x.value}>{x.label}</option>)}</select></Field>
                <MaskAssetStatus url={layer.image || ''} />
                <Field label={`Layer strength — ${layer.strength ?? 70}%`} className="span-2 range-field"><input type="range" min="0" max="100" step="1" value={layer.strength ?? 70} onChange={e => updateSubjectLayer(index, { strength: Number(e.target.value) })} /></Field>
                <label className="mask-only-toggle span-2"><input type="checkbox" checked={Boolean(layer.maskOnly)} onChange={e => updateSubjectLayer(index, { maskOnly: e.target.checked })} /><span><strong>Mask-only asset</strong><small>Do not draw the PNG itself; use only its mask region for the effect. Great for outline rings, black/white fill masks, electricity masks, flame masks, and water masks.</small></span></label>
              </div>
              <div className="color-grid subject-colors">
                <Field label="Layer A"><input type="color" value={layer.foilA} onChange={e => updateSubjectLayer(index, { foilA: e.target.value })} /></Field>
                <Field label="Layer B"><input type="color" value={layer.foilB} onChange={e => updateSubjectLayer(index, { foilB: e.target.value })} /></Field>
                <Field label="Layer C"><input type="color" value={layer.foilC} onChange={e => updateSubjectLayer(index, { foilC: e.target.value })} /></Field>
              </div>
            </div>
          ))}
        </div>
      </div>

      <div className="color-section base-colors">
        <h4>Base colors</h4>
        <p>Inherited by print variants unless that variant overrides them.</p>
        <div className="color-grid">
          <Field label="Accent"><input type="color" value={card.accent} onChange={e => patchBase('accent', e.target.value)} /></Field>
          <Field label="Foil A"><input type="color" value={card.foilA} onChange={e => patchBase('foilA', e.target.value)} /></Field>
          <Field label="Foil B"><input type="color" value={card.foilB} onChange={e => patchBase('foilB', e.target.value)} /></Field>
          <Field label="Foil C"><input type="color" value={card.foilC} onChange={e => patchBase('foilC', e.target.value)} /></Field>
        </div>
      </div>

      <div className="attacks-editor">
        <div className="section-title"><div><h4>Moves / attacks</h4><p>Shared by every print. Up to three are rendered on the card.</p></div><button className="ghost" onClick={addAttack}>+ Add move</button></div>
        {card.attacks.map((attack, index) => (
          <div className="attack-editor" key={index}>
            <input value={attack.name} onChange={e => updateAttack(index, 'name', e.target.value)} placeholder="Move name" />
            <input type="number" min="0" max="4" value={attack.cost} onChange={e => updateAttack(index, 'cost', Number(e.target.value))} title="Cost" />
            <input type="number" min="0" value={attack.damage} onChange={e => updateAttack(index, 'damage', Number(e.target.value))} title="Damage" />
            <input value={attack.text} onChange={e => updateAttack(index, 'text', e.target.value)} placeholder="Move description" />
            <button className="icon-button" onClick={() => removeAttack(index)} aria-label="Remove move">×</button>
          </div>
        ))}
      </div>
    </div>
  )
}
