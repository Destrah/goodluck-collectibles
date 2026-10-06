import React from 'react'
import { createRoot } from 'react-dom/client'
import { createContainerScene } from '../src/collectibles/Container3D.js'
import RotatableCollectible from '../src/collectibles/RotatableCollectible.jsx'
import PackSimulator from '../src/components/PackSimulator.jsx'
import { defaultCards, resolveCardVariant } from '../src/cardData.js'
import '../src/collectibles/objects.jsx'
import '../src/collectibles/tradingCards.jsx'
import '../src/styles.css'
import '../src/collectibles/collectibles.css'
import '../src/styles/packOpen.css'

const root = createRoot(document.getElementById('root'))
const style = document.createElement('style')
style.textContent = `body{margin:0;background:#100d19;color:#fff;font-family:Arial,sans-serif;overflow:hidden}*{box-sizing:border-box}#capture{position:relative;width:800px;height:500px;background:radial-gradient(ellipse at 50% 48%,#34263e 0%,#171221 58%,#100d19 100%);overflow:hidden}header{position:absolute;top:22px;left:26px;z-index:5;pointer-events:none}header b{display:block;font-size:12px;color:#ffd23c;letter-spacing:3px;margin-bottom:7px}header h1{font-size:23px;margin:0}footer{position:absolute;bottom:16px;left:26px;z-index:5;font-size:11px;color:#b9acc8;letter-spacing:.6px}.stage{position:absolute;inset:74px 15px 32px;display:flex;align-items:center;justify-content:center;gap:16px}.scene-canvas{width:100%;height:100%;display:block}.tile{flex:1;min-width:0;height:100%;position:relative;text-align:center}.tile span{font-size:12px;color:#e9dbee;position:absolute;bottom:0;left:0;right:0}.tile canvas{width:100%;height:calc(100% - 22px)}.collectible-inspector{height:100%}.collectible-3d-stage{width:340px;height:330px}.collectible-rotation-stage{transform:scale(.57);transform-origin:top center;height:325px;width:390px;margin:0 auto}.collectible-inspect-controls{position:absolute;bottom:10px;left:0;right:0;display:flex;justify-content:center;gap:6px}.collectible-inspect-controls button{padding:6px 10px;font-size:11px} .collectible-inspector>small{display:none}.pack-overlay{position:absolute!important;inset:0!important;background:transparent!important}.pack-overlay .pack-stage{height:350px!important;min-height:0!important}.pk-stage{height:350px!important;min-height:0!important}.pk-table{background:transparent!important}`
document.head.appendChild(style)

const coin = { id:'readme-coin',instanceId:'coin',collectibleType:'challenge_coin',title:'Meta Comics Coin',rarity:'Ultra Rare',rarityKey:'ultra_rare',finish:'metallic',finishStrength:65,accent:'#d6af57',edgeStyle:'reeded',diameter:40,material:'Gold',image:'',backImage:'' }
const plush = { id:'readme-plush',instanceId:'plush',collectibleType:'plushie',title:'Collector Bear',rarity:'Rare',rarityKey:'rare',finish:'none',accent:'#e4a4cf',image:'/fivem/examples/ox_inventory_images/collectible_plushie.png',stitchColor:'#f3e6cf',stitchPattern:'blanket',stitchWidth:2.2,plushThickness:125 }
const bag = { id:'coin_bag',kind:'bag',label:'Coin Bag',count:3,look:{style:'satin',animation:'pour'},outer:{count:6,label:'Coin Bag Box',look:{style:'chest',animation:'lift'}} }
const cardBase = defaultCards.find(c => c.title === 'Nate Gatto') || defaultCards[0]
const print = cardBase.variants.find(v => v.holo === 'rainbow') || cardBase.variants[0]
const card = { ...resolveCardVariant(cardBase,print.id),collectibleType:'trading_card' }
let scenes=[]
const frame = (title, child) => <div id="capture"><header><b>META COMIC COLLECTIBLES</b><h1>{title}</h1></header><div className="stage">{child}</div><footer>Actual resource renderer · Standalone UI preview</footer></div>
const ready = () => new Promise(resolve => requestAnimationFrame(() => requestAnimationFrame(resolve)))
window.showDemo = async name => {
  scenes.forEach(s => s.dispose()); scenes=[]
  if (name === 'pack-opening') {
    localStorage.setItem('meta-comic-pack-prefs-v1',JSON.stringify({speed:1.5,tear:'peel',fan:'arc'}))
    root.render(frame('Booster pack · tear, fan out & reveal',<PackSimulator cards={defaultCards} overlay overlayKey={1} onClose={() => {}} />))
    await ready(); return
  }
  if (name.endsWith('viewing')) {
    const titles = {'card-viewing':'Trading card · rotate & catch the foil','collectible-viewing':'Challenge coin & plushie · front, edge & back','container-viewing':'Sealed containers · rotating previews'}
    if (name === 'container-viewing') {
      root.render(frame(titles[name],<>{['Meta satin pouch','Collector window box','Treasure chest'].map((label,i) => <div className="tile" key={i}><canvas className="scene-canvas"/><span>{label}</span></div>)}</>));await ready()
      for (const [i,opts] of [{kind:'bag',style:'satin'},{kind:'box',style:'window'},{kind:'case',style:'chest',caseInfo:{count:6,innerLabel:'Coin Bag'}}].entries()) scenes.push(await createContainerScene(document.querySelectorAll('canvas')[i],{...opts,preview:true,maxPixelRatio:1}))
    } else {
      root.render(frame(titles[name],name === 'card-viewing' ? <RotatableCollectible item={card}/> : <>{[coin,plush].map(item => <div className="tile" key={item.id}><RotatableCollectible item={item}/><span>{item.title}</span></div>)}</>));await ready()
    }
    return
  }
  const config = name === 'coin-opening'
    ? { title:'Coin bag · pour & reveal',kind:'bag',style:'satin',animation:'pour',items:[coin,{...coin,instanceId:'coin2',accent:'#9ad8ef',finish:'rainbow'},{...coin,instanceId:'coin3',accent:'#e6a4dc'}] }
    : name === 'plushie-opening' ? {title:'Plushie box · open & reveal',kind:'box',style:'window',animation:'unfold',items:[plush]}
    : {title:'Outer case · unpack sealed coin bags',kind:'case',style:'chest',animation:'lift',caseInfo:{count:6,innerLabel:'Coin Bag'},items:Array.from({length:6},(_,i) => ({instanceId:`sealed-${i}`,collectibleType:'challenge_coin',label:'Coin Bag',containerSnapshot:bag}))}
  root.render(frame(config.title,<canvas className="scene-canvas"/>));await ready()
  scenes.push(await createContainerScene(document.querySelector('canvas'),{...config,maxPixelRatio:1}))
  scenes[0].seek(0)
}
window.seekDemo = (time,reveal) => {for (const s of scenes) {s.seek(time);if(reveal) {s.reveal(0);s.reveal(1);s.reveal(2)}}}
window.demoReady = true
