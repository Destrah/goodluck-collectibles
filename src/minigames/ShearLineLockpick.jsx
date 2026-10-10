import React,{useEffect,useRef} from 'react'
import pickHtml from './shearLine.html?raw'
import drillHtml from './shearDrill.html?raw'
import grinderHtml from './shearGrinder.html?raw'
import skimmerHtml from './shearSkimmer.html?raw'
import themes from './shearThemes.js?raw'
import fitLayout from './shearFit.js?raw'
const prepare=html=>html.replace('/* SHEAR_THEME_RENDERER */',themes).replace('/* SHEAR_FIT_LAYOUT */',fitLayout)
const documents={lockpick:prepare(pickHtml),drill:prepare(drillHtml),grinder:prepare(grinderHtml),skimmer:prepare(skimmerHtml)}
export default function ShearLineLockpick({config,done}) {
  const game=documents[config.game]?config.game:'lockpick'
  const frame=useRef(null),session=useRef(crypto.randomUUID()),sent=useRef(false)
  useEffect(()=>{
    const listener=event=>{
      if(event.source!==frame.current?.contentWindow || event.data?.type!=='metacomic:shearResult' || event.data.id!==session.current || sent.current)return
      sent.current=true;done(event.data.success===true)
    }
    window.addEventListener('message',listener)
    return()=>window.removeEventListener('message',listener)
  },[done])
  return <iframe ref={frame} className="mg-shear-frame" title={`Shear Line ${game}`} sandbox="allow-scripts" srcDoc={documents[game]} onLoad={()=>{
    frame.current?.contentWindow?.postMessage({action:`${game}:open`,id:session.current,config},'*')
    frame.current?.focus()
  }} />
}
