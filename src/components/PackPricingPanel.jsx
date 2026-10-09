import React,{useEffect,useMemo,useState,useRef} from 'react'
import {bridge,isFiveM} from '../runtime'
import {previewPackPricing,priceComparison} from '../runtime/packPricing.js'
import './packPricing.css'
import {sharePricingRequest} from '../runtime/pricingRequests.js'
const money=v=>Number(v||0).toLocaleString(undefined,{style:'currency',currency:'USD',maximumFractionDigits:2})
const percent=v=>`${(v*100).toFixed(1)}%`
export default function PackPricingPanel({cards,sets}){
  const lastReportKey=useRef(''),retailKey=useRef('')
  const [options,setOptions]=useState({buyers:[],sets:[]}),[buyer,setBuyer]=useState(''),[setId,setSetId]=useState(''),[report,setReport]=useState(null)
  const [payoutPercent,setPayoutPercent]=useState(100),[previewMultiplier,setPreviewMultiplier]=useState(null),[saving,setSaving]=useState(false),[notice,setNotice]=useState('')
  const [scenario,setScenario]=useState('fresh'),[packPrice,setPackPrice]=useState(250),[supplyCost,setSupplyCost]=useState(0),[fee,setFee]=useState(0),[margin,setMargin]=useState(20),[gradingFee,setGradingFee]=useState(0),[includeBuyback,setIncludeBuyback]=useState(true)
  const [error,setError]=useState(''),[busy,setBusy]=useState(false),[refresh,setRefresh]=useState(0)
  useEffect(()=>{let cancelled=false
    const request=isFiveM?sharePricingRequest('options',()=>bridge.getCardMarketOptions()):Promise.resolve({buyers:[{index:1,label:'Default buyer preview'}],sets})
    request.then(data=>{if(cancelled)return;setOptions(data);setBuyer(String(data.buyers[0]?.index||''));setSetId(current=>data.sets.some(s=>s.id===current)?current:data.sets[0]?.id||'')}).catch(e=>{if(!cancelled)setError(e.message)})
    return()=>{cancelled=true}
  },[isFiveM?null:sets])
  useEffect(()=>{if(!buyer||!setId)return;let cancelled=false;setBusy(true);setError('');const key=`${buyer}:${setId}`;if(lastReportKey.current!==key)setReport(null)
    const request=isFiveM?sharePricingRequest(`${key}:${previewMultiplier??'saved'}`,()=>bridge.getCardMarketAnalysis({index:Number(buyer),setId,...(previewMultiplier==null?{}:{previewMultiplier})})):Promise.resolve().then(()=>({report:previewPackPricing(cards,options.sets.find(s=>s.id===setId))}))
    request.then(({report:value})=>{if(cancelled)return;setReport(value);lastReportKey.current=key;if(previewMultiplier==null)setPayoutPercent((value.savedPayoutMultiplier??1)*100);if(retailKey.current!==key){setPackPrice(value.defaultPackPrice??250);retailKey.current=key}}).catch(e=>{if(!cancelled)setError(e.message)}).finally(()=>{if(!cancelled)setBusy(false)})
    return()=>{cancelled=true}
  },[buyer,setId,refresh,isFiveM?null:cards,isFiveM?null:options.sets,previewMultiplier])
  const savePayout=async()=>{
    setSaving(true);setError('');setNotice('')
    try{await bridge.saveCardSetPayout({setId,multiplier:Number(payoutPercent)/100});setPreviewMultiplier(null);setRefresh(v=>v+1);setNotice('Set payout saved. New sale quotes use this adjustment.')}
    catch(e){setError(e.message)}finally{setSaving(false)}
  }
  const validPayout=Number.isFinite(Number(payoutPercent))&&Number(payoutPercent)>=10&&Number(payoutPercent)<=1000
  const stats=report?.[scenario]
  const cost=scenario==='graded'?gradingFee*5:0
  const comparison=stats&&priceComparison(stats,{packPrice,supplyCost,fee,margin,gradingCost:cost,includeBuyback})
  const bins=useMemo(()=>{
    if(!stats)return[];const maximum=stats.max||1,grouped=Array.from({length:20},(_,i)=>({from:i*maximum/20,to:(i+1)*maximum/20,count:0}))
    for(const b of stats.histogram)grouped[Math.min(19,Math.floor(b.value/maximum*20))].count+=b.count
    return grouped
  },[stats])
  const input=(label,value,set,max=1000000)=><label>{label}<input type="number" min="0" max={max} step="0.01" value={value} onChange={e=>set(Math.max(0,Math.min(max,Number(e.target.value)||0)))} /></label>
  return <section className="pp-panel" aria-label="Pack pricing analysis">
    <header><div><span className="eyebrow">PACK ECONOMICS</span><h2>Pack pricing & resale returns</h2><p>Compare customer returns with the cost of selling packs and funding buyback.</p></div><button disabled={busy||saving} onClick={()=>setRefresh(v=>v+1)}>Refresh analysis</button></header>
    <div className="pp-controls"><label>Buyer<select disabled={saving} value={buyer} onChange={e=>setBuyer(e.target.value)}>{options.buyers.map(b=><option value={b.index} key={b.index}>{b.label}</option>)}</select></label><label>Card set<select disabled={saving} value={setId} onChange={e=>{setPreviewMultiplier(null);setNotice('');setSetId(e.target.value)}}>{options.sets.map(s=><option value={s.id} key={s.id}>{s.name}</option>)}</select></label><label>Resale scenario<select value={scenario} onChange={e=>setScenario(e.target.value)}><option value="fresh">Fresh pack · raw cards</option><option value="clean">Clean raw cards · exact average</option><option value="graded">Factory cards · suggested grades</option></select></label></div>
    {options.canAdjustPayouts&&<div className="pp-controls">
      <label>Set buyback payout (%)<input type="number" min="10" max="1000" step="1" disabled={busy||saving} value={payoutPercent} onChange={e=>setPayoutPercent(e.target.value)} /></label>
      <button disabled={busy||saving||!report||!validPayout} onClick={()=>{setPreviewMultiplier(Number(payoutPercent)/100);setRefresh(v=>v+1);setNotice('')}}>Preview payout</button>
      <button disabled={busy||saving||!report||!validPayout} onClick={savePayout}>{saving?'Saving…':'Save set payout'}</button>
      <button disabled={busy||saving||!report} onClick={()=>{setPayoutPercent((report.savedPayoutMultiplier??1)*100);setPreviewMultiplier(null);setRefresh(v=>v+1);setNotice('')}}>Revert</button>
      <p className="pp-note">100% is default; 50% lowers automatic offers and 150% raises them. Applies to this set at all buyers. Minimums, caps, whole-dollar rounding and fixed card prices still apply. Preview does not save.</p>
    </div>}
    {notice&&<p role="status">{notice}</p>}
    {report?.payoutMultiplier!=null&&<p className="pp-note">{report.payoutPreview?'Unsaved preview':'Saved payout'}: {(report.payoutMultiplier*100).toFixed(1)}% · Saved: {(report.savedPayoutMultiplier*100).toFixed(1)}%</p>}
    {error&&<p role="alert">{error}</p>}{busy&&<p role="status">Calculating pull odds, condition and buyer offers…</p>}
    {report&&<>
      {report.preview&&<p className="pp-note">Standalone preview uses default $1 pricing and no recorded population. FiveM uses live server catalog, buyer overrides and population.</p>}
      <p className="pp-note">Each card offer is rounded to whole dollars using the sale rules before adding pack payouts. Pack and box averages can have decimals because they combine the odds of different whole-dollar payouts; they are not an individual sale amount.</p>
      <div className="pp-metrics"><div><span>Average resale / pack</span><strong>{money(stats.mean)}</strong><small>{stats.exact?'Exact weighted expectation':`Simulation · 95% mean interval ${money(stats.confidence95[0])}–${money(stats.confidence95[1])}`}</small></div><div><span>Typical pack (median)</span><strong>{money(stats.median)}</strong><small>10th–90th percentile: {money(stats.p10)}–{money(stats.p90)}</small></div><div><span>Average resale / box</span><strong>{money(stats.mean*report.packsPerBox)}</strong><small>{report.packsPerBox} packs; before purchase / grading costs</small></div></div>
      <div className="pp-workbench"><div className="pp-inputs">
        {input('Proposed pack sale price ($)',packPrice,setPackPrice)}{input('Business supply cost per pack ($)',supplyCost,setSupplyCost)}{input('Sales fees / tax (%)',fee,setFee,100)}{input('Target business margin (%)',margin,setMargin,100)}{scenario==='graded'&&input('Grading cost per card ($)',gradingFee,setGradingFee)}
        <label className="pp-checkbox"><input type="checkbox" checked={includeBuyback} onChange={e=>setIncludeBuyback(e.target.checked)} /> Include expected card buyback in price target</label>
      </div><div className="pp-results"><h3>At {money(packPrice)} per pack</h3><dl><dt>Customer expected net return</dt><dd className={comparison.playerProfit<0?'pp-negative':'pp-positive'}>{money(comparison.playerProfit)}</dd><dt>Chance of recovering purchase{cost>0?' + grading cost':''}</dt><dd>{percent(comparison.breakEvenChance)}</dd><dt>Business margin: retail only</dt><dd>{money(comparison.retailMargin)}</dd><dt>Business margin: retail + buying all pulls back</dt><dd>{money(comparison.buybackMargin)}</dd><dt>Price for {margin}% margin{includeBuyback?' including buyback':''}</dt><dd>{comparison.targetPrice==null?'Fees + target margin must be below 100%':money(comparison.targetPrice)}</dd></dl><p>Supply cost and fees are your inputs. This projection assumes all five cards are sold to this buyer. It does not change shop prices or reserve buyer funds.</p></div></div>
      <h3>Pack resale distribution</h3><div className="pp-histogram" role="img" aria-label={`Resale distribution from ${report.samples} simulated packs. Median ${money(stats.median)}, average ${money(stats.mean)}.`}>{bins.map((b,i)=><div key={i} title={`${money(b.from)}–${money(b.to)}: ${percent(b.count/stats.samples)}`}><i style={{height:`${Math.max(1,b.count/Math.max(...bins.map(x=>x.count),1)*100)}%`}} /></div>)}</div><div className="pp-axis"><span>{money(0)}</span><span>{money(stats.max)} highest sampled payout</span></div>
      <p className="pp-note">{report.samples.toLocaleString()} sampled packs. Quantiles and recovery chances are estimates; rare jackpots can make the average much higher than a typical pack. Fresh raw cards use actual factory defects and obvious-defect discounts. Suggested-grade returns assume every flaw is found and use current population held constant; grader adjustments, grading fees, later wear and future supply changes can alter returns.</p>
      <div className="pp-tables"><div><h3>Where clean-pack value comes from</h3><table><thead><tr><th>Slot</th><th>Cards</th><th>Expected resale</th></tr></thead><tbody>{report.slots.map(s=><tr key={s.label}><td>{s.label}{s.tier&&<small>{s.tier.replaceAll('_',' ')} pool</small>}</td><td>{s.count}</td><td>{money(s.mean)}</td></tr>)}</tbody></table></div><div><h3>Grade scenarios</h3><table><thead><tr><th>Every card at grade</th><th>Average pack resale</th></tr></thead><tbody>{report.gradeScenarios.map(g=><tr key={g.grade}><td>{g.grade}</td><td>{money(g.mean)}</td></tr>)}</tbody></table><small>Hypothetical grades, before grading costs; these are not likely grade frequencies.</small></div><div><h3>Fresh-card suggested grades</h3><table><thead><tr><th>Grade</th><th>Share of sampled cards</th></tr></thead><tbody>{report.gradeDistribution.map(g=><tr key={g.grade}><td>{g.grade}</td><td>{percent(g.chance)}</td></tr>)}</tbody></table></div></div>
      <h3>Print contributions</h3><div className="pp-print-table"><table><thead><tr><th>Card / print</th><th>Tier</th><th>Copies / pack</th><th>Clean offer</th><th>Expected pack value</th></tr></thead><tbody>{report.prints.map(p=><tr key={p.key}><td>{p.label}<small>{p.variant}</small></td><td>{p.rarity?.replaceAll('_',' ')}</td><td>{p.expectedCopies.toFixed(5)}</td><td>{money(p.cleanPrice)}</td><td>{money(p.expectedCopies*p.cleanPrice)}</td></tr>)}</tbody></table></div>
    </>}
  </section>
}
