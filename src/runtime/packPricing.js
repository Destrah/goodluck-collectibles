// Standalone preview only. FiveM always calculates offers and projections on the server.
import { PACK_TIER_CHAINS } from './packRules.js'
import { computePrintOdds } from '../utils/printOdds.js'
import { resolveCardVariant } from '../cardData.js'
import { generateCondition, listFlaws, flawOptions, gradeFromFlaws } from '../grading/condition.js'
const rarity={common:1,uncommon:2,rare:5,ultra_rare:15,legendary:50}
const grades={1:.15,2:.25,3:.35,4:.45,5:.55,6:.65,7:.8,8:1,8.5:1.15,9:1.4,9.5:1.75,10:2.5}
const weight=v=>Math.max(1,Number(v)||1)
export function defaultOffer(card,odds) {
  const chance=odds.get(`${card.baseCardId}::${card.variantId}`)||0
  const best=Math.max(0,...odds.values())
  const base=Math.min(1000,Math.max(rarity[card.rarityKey]||1,chance>0?best/chance:1))
  let factor=1
  if(card.graded){const grade=card.graded.grade,lo=Math.floor(grade),hi=Math.ceil(grade);factor=(grades[grade]??((grades[lo]||1)*(hi-grade)+(grades[hi]||1)*(grade-lo)))*1.25}
  else if(card.condition){
    const c=card.condition,off=v=>Math.hypot(v?.[0]||0,v?.[1]||0)
    const flaws=listFlaws(c,flawOptions(card)).filter(f=>{
      if(f.type==='centering')return Math.max(...(c.centering?.[f.side]||[0,0]).map(Math.abs))>(f.side==='front'?.2:.7)
      if(f.type==='art')return off(c.art)>1.5
      if(f.type==='text')return off(f.textPart?c.text?.[f.textPart]:c.text)>1.2
      if(f.type==='foil')return off(c.foil)>3||Math.abs(c.foil?.[2]||0)>30
      if(f.type==='mask')return off(c.mask)>1.6
      if(f.type==='corner'||f.type==='edge')return (c[f.type==='corner'?'corners':'edges']?.[f.side]?.[f.index]||0)>.4
      const m=f.mark;if(!m)return false
      const severity={scratch:.5,dent:.7,crease:.2,bend:.4,tear:.15,roller:.7,printline:.5,inkspot:.7,stain:.5}
      const lengths={scratch:12,crease:8,bend:10,tear:2,printline:20,roller:15}
      return (m.s||0)>=(severity[f.type]??.6)&&Math.hypot((m.x2??m.x1??0)-(m.x1||0),(m.y2??m.y1??0)-(m.y1||0))>=(lengths[f.type]||0)
    })
    factor=1-Math.min(.8,flaws.reduce((sum,f)=>sum+f.deduction,0)*.08)
  }
  return Math.min(1000,Math.max(1,Math.floor(base*factor+.5+1e-9)))
}
export function packStats(values,exactMean,exactVariance){
  values.sort((a,b)=>a-b);const n=values.length,sum=values.reduce((a,b)=>a+b,0),mean=sum/n
  const variance=values.reduce((a,b)=>a+(b-mean)**2,0)/Math.max(1,n-1),error=1.96*Math.sqrt(variance/n)
  const histogram=new Map();for(const v of values)histogram.set(v,(histogram.get(v)||0)+1)
  return {mean:exactMean??mean,variance:exactVariance??variance,standardDeviation:Math.sqrt(exactVariance??variance),exact:exactMean!=null,
    confidence95:[mean-error,mean+error],samples:n,p10:values[Math.ceil(n*.1)-1],median:values[Math.ceil(n*.5)-1],p90:values[Math.ceil(n*.9)-1],min:values[0],max:values[n-1],
    histogram:[...histogram].map(([value,count])=>({value,count}))}
}
export function previewPackPricing(catalog,set,samples=2000){
  const cards=catalog.filter(c=>set.cardIds?.includes(c.id)),odds=computePrintOdds(cards)
  if(!odds.size)throw new Error('This set has no pullable cards.')
  const pool=chain=>{
    const tier=chain.find(t=>cards.some(c=>c.variants.some(v=>v.rarityKey===t)))
    const bases=cards.filter(c=>c.variants.some(v=>v.rarityKey===tier)),baseTotal=bases.reduce((n,c)=>n+weight(c.chanceWeight),0)
    return bases.flatMap(c=>{const variants=c.variants.filter(v=>v.rarityKey===tier),total=variants.reduce((n,v)=>n+weight(v.chanceWeight),0)
      return variants.map(v=>({card:{...resolveCardVariant(c,v),setId:set.id},chance:weight(c.chanceWeight)/baseTotal*weight(v.chanceWeight)/total}))})
  }
  const slots=[{count:3,label:'Common slots',outcomes:pool(PACK_TIER_CHAINS.common)},{count:1,label:'Uncommon-or-higher slot',outcomes:pool(PACK_TIER_CHAINS.uncommon)},
    {count:1,label:'Rare-or-higher slot',outcomes:[[.75,'rare'],[.2,'ultra_rare'],[.05,'legendary']].flatMap(([chance,tier])=>pool(PACK_TIER_CHAINS[tier]).map(o=>({...o,chance:o.chance*chance})))}]
  let mean=0,variance=0,seed=17017
  const random=()=>{seed=seed*48271%2147483647;return seed/2147483647}
  const prints=[],byPrint=new Map(),gradeScenarios=[1,5,8,9,9.5,10].map(grade=>({grade,mean:0}))
  for(const slot of slots){let m=0,sq=0
    for(const o of slot.outcomes){o.price=defaultOffer(o.card,odds);m+=o.chance*o.price;sq+=o.chance*o.price**2
      const key=`${o.card.baseCardId}::${o.card.variantId}`
      if(!byPrint.has(key)){const row={key,label:o.card.title,variant:o.card.variantName,rarity:o.card.rarityKey,expectedCopies:0,cleanPrice:o.price,
        grades:gradeScenarios.map(g=>({grade:g.grade,price:defaultOffer({...o.card,graded:{grade:g.grade}},odds),population:0}))};prints.push(row);byPrint.set(key,row)}
      const row=byPrint.get(key);row.expectedCopies+=slot.count*o.chance
      gradeScenarios.forEach((g,i)=>{g.mean+=slot.count*o.chance*row.grades[i].price})
    }slot.mean=m*slot.count;mean+=slot.mean;variance+=slot.count*(sq-m*m)
  }
  const values={clean:[],fresh:[],graded:[]},counts=new Map()
  for(let s=0;s<samples;s++){let clean=0,fresh=0,graded=0
    for(const slot of slots)for(let j=0;j<slot.count;j++){
      let roll=random(),o=slot.outcomes.at(-1);for(const candidate of slot.outcomes){roll-=candidate.chance;if(roll<=0){o=candidate;break}}
      const card={...o.card,condition:generateCondition(random)},grade=gradeFromFlaws(listFlaws(card.condition,flawOptions(card)))
      clean+=o.price;fresh+=defaultOffer(card,odds);graded+=defaultOffer({...card,graded:{grade}},odds);counts.set(grade,(counts.get(grade)||0)+1)
    }values.clean.push(clean);values.fresh.push(fresh);values.graded.push(graded)
  }
  return {setId:set.id,setName:set.name,buyerName:'Default buyer preview',clean:packStats(values.clean,mean,variance),fresh:packStats(values.fresh),graded:packStats(values.graded),
    slots:slots.map(({label,count,mean})=>({label,count,mean})),prints:prints.sort((a,b)=>b.expectedCopies*b.cleanPrice-a.expectedCopies*a.cleanPrice),gradeScenarios,
    gradeDistribution:[...counts].map(([grade,count])=>({grade,chance:count/(samples*5)})).sort((a,b)=>b.grade-a.grade),samples,packsPerBox:12,defaultPackPrice:250,preview:true}
}
export function priceComparison(stats,{packPrice=0,supplyCost=0,fee=0,margin=0,gradingCost=0,includeBuyback=true}={}){
  const threshold=packPrice+gradingCost,mean=stats.mean,denominator=1-fee/100-margin/100
  const probability=stats.histogram.reduce((sum,bin)=>sum+(bin.value>=threshold?bin.count:0),0)/stats.samples
  return {playerProfit:mean-threshold,breakEvenChance:probability,retailMargin:packPrice*(1-fee/100)-supplyCost,
    buybackMargin:packPrice*(1-fee/100)-supplyCost-mean,
    targetPrice:denominator>0?Math.ceil((supplyCost+(includeBuyback?mean:0))/denominator):null}
}
