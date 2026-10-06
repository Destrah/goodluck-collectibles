import React, { useState } from 'react'
import { createRoot } from 'react-dom/client'
import TradingCard from '../src/components/TradingCard.jsx'
import { resolveCardVariant } from '../src/cardData.js'
import samples from '../fivem/data/sample-cards.json'
import '../src/styles.css'
import './grading-comparison.css'

const card = resolveCardVariant(samples.cards.find(card => card.id === 'sample-085'))

function Comparison() {
  const [centering, setCentering] = useState(.6)
  const [art, setArt] = useState(4)
  const [fullBleed,setFullBleed]=useState(true)
  const shownCard={...card,layout:fullBleed?'illustration':card.layout}
  const views = [
    { title:'Correct print', note:'Even borders. Artwork sits in its intended position.', condition:null },
    { title:'Off-centre / print shifted', note:'Compare the green outer border: left and top are wider; right and bottom are narrower. This represents the print sitting unevenly inside the cut.', condition:{centering:{front:[centering,centering]}} },
    { title:'Artwork shifted', note:'The outer border stays even. Only the picture moves right and down inside its window; the name, HP and text stay in place.', condition:{art:[art,art]} },
    { title:'Two text sections shifted', note:'Only the title and footer move. Subtitle, HP, type, description and attacks stay aligned. These are two separate findings.', condition:{v:2,text:{title:[2,1],footer:[-2,0]}} },
  ]
  return <main className="comparison-demo">
    <h1>Centering versus artwork alignment</h1>
    <p>The same Azure Ranger Standard print, rendered by the actual card component. Offsets are exaggerated to make them easy to compare.</p>
    <div className="comparison-controls">
      <label><input type="checkbox" checked={fullBleed} onChange={event=>setFullBleed(event.target.checked)}/> Full-art border example</label>
      <label>Border imbalance <input type="range" min="0" max="0.8" step="0.01" value={centering} onChange={event=>setCentering(Number(event.target.value))} /> {Math.round((1+centering)*50)}/{Math.round((1-centering)*50)}</label>
      <label>Artwork shift <input type="range" min="0" max="6" step="0.1" value={art} onChange={event=>setArt(Number(event.target.value))} /> {art.toFixed(1)}% per axis</label>
    </div>
    <div className="comparison-grid">{views.map(view=><section key={view.title}>
      <h2>{view.title}</h2>
      <TradingCard card={{...shownCard,condition:view.condition}} size="viewer" interactive={false} showProtection={false}/>
      <p>{view.note}</p>
    </section>)}</div>
    <p className="comparison-footnote">On the grading bench, “Off-centre borders” checks border imbalance. “Artwork shifted” checks picture registration. “Text shifted” checks the specific text section you click. Differences inside tolerance do not count as flaws.</p>
  </main>
}
createRoot(document.getElementById('root')).render(<Comparison/> )
