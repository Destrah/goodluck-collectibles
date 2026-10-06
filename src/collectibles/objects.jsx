import { registerCollectibleType } from './registry.js'
import { useResolvedAsset } from '../runtime/assets'
import { EDGE_STYLES, STITCH_PATTERNS, backStyles } from './prints.js'

// Short rune strokes stamped around the rim of coins that have no artwork (each fits a 6x10 cell).
const RIM_RUNES = ['M0 0V10M0 2L5 5', 'M0 0V10M0 0L5 4L0 7', 'M2 0V10M0 3L5 7', 'M0 10L2.5 0L5 10', 'M0 0V10M5 0V10M0 4L5 6', 'M0 0L5 10M5 0L0 10']

function CoinEmblem({ item, back }) {
  return <svg className="collectible-coin-emblem" viewBox="0 0 100 100" aria-hidden="true">
    <circle cx="50" cy="50" r="46" fill="none" stroke="currentColor" strokeWidth="1.4" opacity=".7" />
    <circle cx="50" cy="50" r="34" fill="none" stroke="currentColor" strokeWidth="1.4" opacity=".7" />
    {Array.from({ length: 18 }, (_, index) => <path key={index} d={RIM_RUNES[index % RIM_RUNES.length]} transform={`rotate(${index * 20} 50 50) translate(47.5 6)`} fill="none" stroke="currentColor" strokeWidth="1.3" strokeLinecap="round" />)}
    {back
      ? <text x="50" y="58" textAnchor="middle" fill="currentColor" fontFamily="Impact,'Arial Black',sans-serif" fontSize="24" letterSpacing="1">MC</text>
      : <path d="M50 24L56.5 42H75L60 53L65.5 71L50 60L34.5 71L40 53L25 42H43.5Z" fill="currentColor" opacity=".9" />}
    {!back && item.title && <text x="50" y="86" textAnchor="middle" fill="currentColor" fontFamily="Arial,sans-serif" fontWeight="bold" fontSize="6" letterSpacing="1">{item.title.slice(0, 18).toUpperCase()}</text>}
  </svg>
}

// same framing semantics as the trading card artwork (and the 3D coin face)
const framing = item => {
  const x = Math.min(100, Math.max(0, Number(item.imagePositionX ?? 50))), y = Math.min(100, Math.max(0, Number(item.imagePositionY ?? 50)))
  return { objectPosition: `${x}% ${y}%`, transform: `scale(${Math.min(220, Math.max(100, Number(item.imageZoom ?? 100))) / 100})`, transformOrigin: `${x}% ${y}%` }
}

function ObjectView({ item, coin = false, back = false }) {
  const rim = useResolvedAsset(coin ? item.rimImage : '')
  const image = back ? item.backImage : item.image
  // No back artwork: the back can copy the front ('same' or 'mirror'); a plushie otherwise shows the front
  // turned around (darkened) rather than a blank tile.
  const copy = back && !item.backImage && item.image && (item.backStyle === 'same' || item.backStyle === 'mirror') ? item.backStyle : ''
  const mirrored = back && !item.backImage && item.image && (copy === 'mirror' || (!coin && !copy))
  const art = image || (copy || mirrored ? item.image : '')
  const framed = !back || !!copy
  return <figure className={`collectible-object ${coin ? 'collectible-object--coin' : 'collectible-object--plush'} ${back ? 'is-back' : ''}`} style={{ '--object-accent': item.accent || '#c9a34d' }}>
    <div className={`collectible-object-art finish-${item.finish || 'none'} ${art ? 'has-image' : ''} ${mirrored ? 'is-mirrored' : ''} ${copy ? 'is-copy' : ''}`} style={{ '--finish-strength': (item.finishStrength ?? 60) / 100, '--object-mask': art ? `url("${art}")` : 'none', ...(coin && rim.url ? { '--rim-image': `url("${rim.url}")` } : {}) }} data-rim={coin && rim.url ? '' : undefined}>
      {art && coin ? <span className="collectible-coin-face"><img src={art} alt={`${item.title} ${back ? 'back' : 'front'}`} draggable="false" style={framed ? framing(item) : undefined} /></span>
        : art ? <img src={art} alt={`${item.title} ${back ? 'back' : 'front'}`} draggable="false" /> : coin ? <CoinEmblem item={item} back={back} /> : <span aria-hidden="true">🧸</span>}
      {!coin && art && item.tint && Number(item.tintStrength) > 0 && <i className="collectible-object-tint" style={{ background: item.tint, opacity: Math.min(1, Number(item.tintStrength) / 100) }} aria-hidden="true" />}
      {!coin && back && !item.backImage && art && item.backColor && Number(item.backColorBlend) > 0 && <i className="collectible-object-backcolor" style={{ background: item.backColor, opacity: Math.min(1, Number(item.backColorBlend) / 100) }} aria-hidden="true" />}
      <i className="collectible-object-glare" aria-hidden="true" />
    </div>
    <figcaption><strong>{item.title || 'Untitled collectible'}</strong><span>{item.rarity || 'Common'}</span><p>{item.description}</p></figcaption>
  </figure>
}

// fields: shared by every print of a collectible. printFields: chosen per print (version), alongside the common
// print settings (name, rarity tier, pull weight, artwork overrides, finish, accent).
registerCollectibleType('challenge_coin', {
  label: 'Challenge Coins', singular: 'Challenge Coin', authorable: true,
  container: { id: 'coin_bag', label: 'Coin Bag', kind: 'bag', count: 3, outer: { id: 'coin_bag_box', label: 'Coin Bag Box', count: 10 } },
  fields: [{ key: 'material', label: 'Material' }, { key: 'diameter', label: 'Diameter (mm)', type: 'number' }],
  printFields: [
    { key: 'edgeStyle', label: 'Edge style', options: EDGE_STYLES },
    { key: 'backStyle', label: 'Back (when there is no back artwork)', options: backStyles('Minted MC back') },
    { key: 'rimImage', label: 'Rim artwork URL (ring around the face)', type: 'image', fileLabel: 'Rim artwork file', placeholder: 'Blank = minted runes' },
    { key: 'edgeImage', label: 'Edge artwork URL (wrapped round the side)', type: 'image', fileLabel: 'Edge artwork file', placeholder: 'Blank = edge style' },
  ],
  framing: true,
  render: props => <ObjectView {...props} coin />,
})
registerCollectibleType('plushie', {
  label: 'Plushies', singular: 'Plushie', authorable: true,
  container: { id: 'plushie_box', label: 'Plushie Box', kind: 'box', count: 1, outer: { id: 'plushie_case', label: 'Plushie Case', count: 18 } },
  fields: [{ key: 'fabric', label: 'Fabric' }, { key: 'height', label: 'Height (cm)', type: 'number' }],
  printFields: [
    { key: 'tint', label: 'Fabric colour', type: 'color', fallback: '#c98a5a' },
    { key: 'tintStrength', label: 'Fabric colour strength', type: 'range', min: 0, max: 100, fallback: 0, suffix: '%' },
    { key: 'plushThickness', label: 'Thickness', type: 'range', min: 50, max: 300, step: 5, fallback: 100, suffix: '%' },
    { key: 'plushFullness', label: 'Side fullness (flatter faces, rounder top / bottom)', type: 'range', min: 0, max: 100, fallback: 0, suffix: '%' },
    { key: 'backStyle', label: 'Back (when there is no back artwork)', options: backStyles('Soft back from the front colours') },
    { key: 'backColor', label: 'Back colour (when there is no back artwork)', type: 'color', fallback: '#5b5560', sampleArtwork: true },
    { key: 'backColorBlend', label: 'Back colour blend (100% = solid)', type: 'range', min: 0, max: 100, fallback: 0, suffix: '%' },
    { key: 'stitchColor', label: 'Stitching colour', type: 'color', fallback: '#f3e6cf' },
    { key: 'stitchPattern', label: 'Stitch pattern', options: STITCH_PATTERNS },
    { key: 'stitchWidth', label: 'Thread thickness', type: 'range', min: 1, max: 5, step: 0.5, fallback: 2.2 },
  ],
  render: ObjectView,
})
