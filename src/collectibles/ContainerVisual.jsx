import { useId } from 'react'

// Rune strokes for the decorative coins resting in front of the pouch (viewBox -20..20).
const RUNES = [
  'M-4-9V9M-4-9L4-3M-4-1L4 5',
  'M0-9V9M-6-4L0 2L6-4',
  'M0-10V10M-10 0H10M-7-7L7 7M7-7L-7 7',
]
const COIN_STYLES = [
  { face: 'iron', ink: '#d9b45a' },
  { face: 'gold', ink: '#4a3210' },
  { face: 'bright', ink: '#6b4a12' },
]

function PouchCoin({ x, y, r, tilt, index, ids }) {
  const style = COIN_STYLES[index]
  return <g className="meta-pouch-coin" transform={`translate(${x} ${y}) rotate(${tilt}) scale(${r / 20} ${r / 20 * .78})`}>
    <ellipse cx="1" cy="5" rx="22" ry="20" fill="#000" opacity=".6" />
    <circle cy="2.6" r="20" fill={style.face === 'iron' ? '#5a4520' : '#7a5418'} />
    <circle r="20" fill={`url(#${style.face === 'iron' ? ids.iron : style.face === 'bright' ? ids.bright : ids.metal})`} stroke="#c99a3d" strokeWidth="1.2" />
    <circle r="15.5" fill="none" stroke={style.ink} strokeWidth=".9" opacity=".85" />
    <circle r="17.7" fill="none" stroke={style.ink} strokeWidth="2.4" strokeDasharray="1.4 1.8" opacity=".7" />
    <path d={RUNES[index]} fill="none" stroke={style.ink} strokeWidth="2.2" strokeLinecap="round" strokeLinejoin="round" />
    <ellipse cx="-7" cy="-9" rx="9" ry="3.5" fill="#fff" opacity=".18" transform="rotate(-30 -7 -9)" />
  </g>
}

function CoinPouch() {
  const raw = useId().replace(/:/g, '')
  const ids = { velvet:`${raw}v`, sheen:`${raw}s`, nap:`${raw}n`, glow:`${raw}g`, cord:`${raw}c`, metal:`${raw}m`, iron:`${raw}i`, bright:`${raw}b`, label:`${raw}l`, inside:`${raw}in`, beam:`${raw}bm` }
  const body = 'M80 78C48 96 26 136 28 182C30 224 62 242 110 242C158 242 190 224 192 182C194 136 172 96 140 78Z'
  return <svg className="meta-pouch" viewBox="0 0 220 255" aria-hidden="true">
    <defs>
      <radialGradient id={ids.velvet} cx="40%" cy="40%" r="75%">
        <stop offset="0" stopColor="#2b2730" /><stop offset=".5" stopColor="#141217" /><stop offset="1" stopColor="#050406" />
      </radialGradient>
      <linearGradient id={ids.sheen} x1="0" x2="1">
        <stop offset="0" stopColor="#ff2bd6" stopOpacity=".05" /><stop offset=".28" stopColor="#ffd88a" stopOpacity=".1" /><stop offset=".6" stopColor="#000" stopOpacity="0" /><stop offset="1" stopColor="#000" stopOpacity=".45" />
      </linearGradient>
      <filter id={ids.nap} x="0" y="0" width="100%" height="100%">
        <feTurbulence type="fractalNoise" baseFrequency=".95" numOctaves="2" seed="4" result="noise" />
        <feColorMatrix in="noise" type="matrix" values="0 0 0 0 .55  0 0 0 0 .5  0 0 0 0 .6  0 0 0 .08 0" />
        <feComposite in2="SourceGraphic" operator="in" />
      </filter>
      <filter id={ids.glow} x="-80%" y="-80%" width="260%" height="260%">
        <feGaussianBlur in="SourceAlpha" stdDeviation="9" result="wide" />
        <feFlood floodColor="#ff9d1f" /><feComposite in2="wide" operator="in" result="amber" />
        <feGaussianBlur in="SourceAlpha" stdDeviation="3" result="tight" />
        <feFlood floodColor="#ffd23c" /><feComposite in2="tight" operator="in" result="gold" />
        <feMerge><feMergeNode in="amber" /><feMergeNode in="amber" /><feMergeNode in="gold" /><feMergeNode in="SourceGraphic" /></feMerge>
      </filter>
      <linearGradient id={ids.cord} x1="0" y1="0" x2="0" y2="1">
        <stop offset="0" stopColor="#3a3540" /><stop offset=".5" stopColor="#1d1a21" /><stop offset="1" stopColor="#0c0b0e" />
      </linearGradient>
      <radialGradient id={ids.metal} cx="35%" cy="30%" r="80%">
        <stop offset="0" stopColor="#fff1c2" /><stop offset=".35" stopColor="#d6a84c" /><stop offset=".75" stopColor="#8b6424" /><stop offset="1" stopColor="#4a3210" />
      </radialGradient>
      <radialGradient id={ids.bright} cx="35%" cy="30%" r="80%">
        <stop offset="0" stopColor="#fff8d8" /><stop offset=".45" stopColor="#f0c95a" /><stop offset="1" stopColor="#a2741e" />
      </radialGradient>
      <radialGradient id={ids.iron} cx="35%" cy="30%" r="80%">
        <stop offset="0" stopColor="#4b4a4f" /><stop offset=".6" stopColor="#1e1d22" /><stop offset="1" stopColor="#0b0a0d" />
      </radialGradient>
      <linearGradient id={ids.label} x1="0" x2="1">
        <stop offset="0" stopColor="#ff2bd6" /><stop offset=".5" stopColor="#ffd23c" /><stop offset="1" stopColor="#4df3ff" />
      </linearGradient>
      <radialGradient id={ids.inside} cx="50%" cy="60%" r="60%">
        <stop offset="0" stopColor="#ffe9a0" /><stop offset=".35" stopColor="#c27a1a" /><stop offset=".8" stopColor="#1a0f08" /><stop offset="1" stopColor="#060406" />
      </radialGradient>
      <linearGradient id={ids.beam} x1="0" y1="1" x2="0" y2="0">
        <stop offset="0" stopColor="#ffe08a" stopOpacity=".9" /><stop offset=".5" stopColor="#ff7bf0" stopOpacity=".35" /><stop offset="1" stopColor="#ff7bf0" stopOpacity="0" />
      </linearGradient>
    </defs>

    <ellipse className="meta-pouch-floor" cx="110" cy="243" rx="96" ry="11" fill="#ffb02e" opacity=".18" />

    <g className="meta-pouch-tilt">
      <g className="meta-pouch-sack">
        {/* Body: a soft sack that bulges below the gathered neck. */}
        <path d={body} fill={`url(#${ids.velvet})`} />
        <path d={body} fill={`url(#${ids.sheen})`} />
        <path d={body} filter={`url(#${ids.nap})`} />
        <g fill="none" stroke="#000" strokeOpacity=".6" strokeWidth="6" strokeLinecap="round">
          <path d="M90 86C72 122 64 162 72 214" /><path d="M110 88C106 132 108 182 112 234" /><path d="M130 86C148 120 158 162 150 214" />
        </g>
        <g fill="none" stroke="#5c5466" strokeOpacity=".28" strokeWidth="2" strokeLinecap="round">
          <path d="M97 88C84 124 78 160 84 206" /><path d="M122 88C134 120 140 160 136 206" />
        </g>
      </g>

      {/* Light spilling out of the open mouth. */}
      <path className="meta-pouch-beam" d="M72 50L14 -70H206L148 50Z" fill={`url(#${ids.beam})`} />

      <g className="meta-pouch-neck">
        <g className="meta-pouch-ruffle">
          <path d="M70 76C60 56 62 36 72 20C80 30 86 24 92 12C100 24 106 20 112 10C118 22 126 22 132 12C138 26 146 28 150 20C160 38 160 58 150 76Z" fill={`url(#${ids.velvet})`} stroke="#2a2630" strokeWidth="1" />
          <path d="M80 72C76 50 80 34 88 22M100 72C98 50 102 32 106 18M120 72C122 50 122 32 120 18M140 72C146 52 146 36 142 26" fill="none" stroke="#000" strokeOpacity=".65" strokeWidth="3.5" strokeLinecap="round" />
          <path d="M72 20C80 30 86 24 92 12C100 24 106 20 112 10C118 22 126 22 132 12C138 26 146 28 150 20" fill="none" stroke="#4a4452" strokeOpacity=".7" strokeWidth="1.5" />
        </g>
        <g className="meta-pouch-mouth"><ellipse cx="110" cy="50" rx="46" ry="15" fill={`url(#${ids.inside})`} /><ellipse cx="110" cy="50" rx="46" ry="15" fill="none" stroke="#2a2630" strokeWidth="5" /><ellipse cx="110" cy="48" rx="44" ry="13" fill="none" stroke="#4a4452" strokeOpacity=".6" strokeWidth="1.2" /></g>
        {/* Gathered cinch band. */}
        <path d="M68 70C88 82 132 82 152 70L154 82C132 94 88 94 66 82Z" fill="#0e0d10" />
        <path d="M74 76l4 10M86 79l2 11M98 81l1 11M110 82v11M122 81l-1 11M134 79l-2 11M146 76l-4 10" stroke="#2c2832" strokeWidth="1.6" />
      </g>

      {/* Drawstrings hanging down either side, ending in beads. */}
      <g className="meta-pouch-cords" fill="none" stroke={`url(#${ids.cord})`} strokeWidth="3.4" strokeLinecap="round">
        <g className="meta-pouch-cord cord-l"><path d="M70 78C52 92 42 120 40 156C39 172 40 180 38 188" /><path d="M72 82C58 98 50 124 48 152" opacity=".8" /><ellipse cx="38" cy="192" rx="4.2" ry="5.5" fill="#1d1a21" stroke="#4a4452" strokeWidth="1" /><path d="M38 197l-3 9M38 197l1 9M38 197l4 8" stroke="#1d1a21" strokeWidth="1.4" /></g>
        <g className="meta-pouch-cord cord-r"><path d="M150 78C168 92 178 120 180 156C181 172 180 180 182 188" /><path d="M148 82C162 98 170 124 172 152" opacity=".8" /><ellipse cx="182" cy="192" rx="4.2" ry="5.5" fill="#1d1a21" stroke="#4a4452" strokeWidth="1" /><path d="M182 197l3 9M182 197l-1 9M182 197l-4 8" stroke="#1d1a21" strokeWidth="1.4" /></g>
      </g>

      {/* Meta Comics branding embroidered on the velvet, using the booster pack palette. */}
      <g className="meta-pouch-brand">
        <rect x="70" y="100" width="80" height="32" rx="4" fill="#09070b" stroke={`url(#${ids.label})`} strokeWidth="1.3" strokeDasharray="3 2" />
        <text x="110" y="114" textAnchor="middle" fill="#ffd23c" stroke="#120518" strokeWidth="2.4" paintOrder="stroke" fontFamily="Impact,'Arial Black',sans-serif" fontSize="13.5" letterSpacing="1.5">META</text>
        <text x="110" y="128" textAnchor="middle" fill="#ff2bd6" stroke="#120518" strokeWidth="2.4" paintOrder="stroke" fontFamily="Impact,'Arial Black',sans-serif" fontSize="13.5" letterSpacing="1.5">COMICS</text>
      </g>
      <text className="meta-pouch-mark" x="110" y="204" textAnchor="middle" fill="#ffe7a3" filter={`url(#${ids.glow})`} fontFamily="Georgia,'Times New Roman',serif" fontWeight="bold" fontSize="68">?</text>
      <text x="110" y="144" textAnchor="middle" fill="#4df3ff" fillOpacity=".75" fontFamily="Arial,sans-serif" fontWeight="bold" fontSize="7" letterSpacing="2.2">CHALLENGE COINS</text>
    </g>

    <g className="meta-pouch-coins">
      <PouchCoin x={50} y={230} r={23} tilt={-12} index={0} ids={ids} />
      <PouchCoin x={170} y={230} r={23} tilt={10} index={2} ids={ids} />
      <PouchCoin x={110} y={240} r={25} tilt={-2} index={1} ids={ids} />
    </g>
  </svg>
}

export default function ContainerVisual({ typeId, container, outer = false, opening = false }) {
  const bag = !outer && container.kind === 'bag'
  const plural = label => `${label}${/box$/i.test(label) ? 'es' : 's'}`
  return <div className={`meta-container ${bag ? 'meta-bag' : 'meta-carton'} ${outer ? 'meta-container--outer' : ''} ${opening ? 'is-opening' : ''}`} aria-label={outer ? container.outer.label : container.label}>
    {bag ? <CoinPouch /> : <><div className="meta-carton-glow" aria-hidden="true" /><div className="meta-carton-lid" /><div className="meta-carton-body"><span className="meta-container-brand">META<br />COMICS</span><span className="meta-container-symbol">{typeId === 'plushie' ? '★' : '◉'}</span><small>{outer ? `${container.outer.count} ${(container.outer.count === 1 ? container.label : plural(container.label)).toUpperCase()}` : `${container.count} ${typeId === 'plushie' ? 'PLUSHIE' : 'COIN'}${container.count === 1 ? '' : 'S'}`}</small></div></>}
  </div>
}
