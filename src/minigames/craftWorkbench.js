// Approved precision/production workbench interaction model. React owns the card faces.
export function mountCraftWorkbench(root,config,onResult){
const phases=['Print','Inspect','Workbench'],phaseIds=[0,1,2];
const art=config.cards.map((card,index)=>({...card,index,name:card.title||'Card'}));
const grouped=new Map();for(const c of art){const accent=/^#[0-9a-f]{3,8}$/i.test(c.accent||'')?c.accent:'#22d3ee';const mixed=CSS.supports('color','color-mix(in srgb,red,blue)');const edge=c.layout==='dark-borderless'?'#151822':c.layout==='illustration'?(mixed?`color-mix(in srgb,${accent},#f7d8a0 38%)`:'#e9c98c'):(mixed?`color-mix(in srgb,${accent},#fff 18%)`:accent);const key=edge+'|'+(c.layout||'classic');if(!grouped.has(key))grouped.set(key,{name:accent+' '+(c.layout||'classic'),edge,pool:[]});grouped.get(key).pool.push(c.index);}
// Prefer sheets with broad identity variation, then choose prints within each identity at random.
const stocks=[...grouped.values()].map(stock=>{
 const identities=new Map();for(const index of stock.pool){const id=art[index].baseCardId||art[index].id||art[index].title||index;if(!identities.has(id))identities.set(id,[]);identities.get(id).push(index);}
 const groups=[...identities.values()];for(let i=groups.length-1;i>0;i--){const j=Math.floor(Math.random()*(i+1));[groups[i],groups[j]]=[groups[j],groups[i]];}
 stock.pool=groups.map(prints=>prints[Math.floor(Math.random()*prints.length)]);return stock;
}).sort((a,b)=>b.pool.length-a.pool.length).slice(0,6);
if(!stocks.length){onResult(false,{error:'No printable cards in this set.'});return ()=>{};}
// The server sends a complete requested stock and small decoy previews. Shuffle their
// display order, keeping that complete stock as the job instead of always calling it A.
const requestedStock=stocks[0];
for(let i=stocks.length-1;i>0;i--){const j=Math.floor(Math.random()*(i+1));[stocks[i],stocks[j]]=[stocks[j],stocks[i]];}
const packFront=config.packFront||'/img/pack_open_front.jpg',packBack=config.packBack||'/img/pack_open_back.jpg';
const escape=value=>String(value).replace(/[&<>"']/g,c=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]));
for(const c of art)c.name=escape(c.name);
const face=(c,key)=>`<span class="cw-face" data-print="${c.index}" data-face="${key}"></span>`;
function contain(p,el){if(!el)return;const area=el.parentElement;const a=(p.angle||0)*Math.PI/180,w=el.offsetWidth*(el.classList.contains('bench-empty')?2:1),h=el.offsetHeight;const hw=(Math.abs(w*Math.cos(a))+Math.abs(h*Math.sin(a)))/2+5,hh=(Math.abs(h*Math.cos(a))+Math.abs(w*Math.sin(a)))/2+5;const px=Math.min(area.clientWidth/2,hw),py=Math.min(area.clientHeight/2,hh);p.x=Math.max(px/area.clientWidth*100,Math.min(100-px/area.clientWidth*100,p.x));p.y=Math.max(py/area.clientHeight*100,Math.min(100-py/area.clientHeight*100,p.y));}
let audio=null;
function sound(kind,enabled){if(!enabled)return;try{audio??=new (window.AudioContext||window.webkitAudioContext)();audio.resume().catch(()=>{});const now=audio.currentTime;const tone=(freq,duration,type='sine',delay=0,vol=.045)=>{const o=audio.createOscillator(),g=audio.createGain();o.type=type;o.frequency.setValueAtTime(freq,now+delay);o.frequency.exponentialRampToValueAtTime(Math.max(35,freq*.45),now+delay+duration);g.gain.setValueAtTime(vol,now+delay);g.gain.exponentialRampToValueAtTime(.001,now+delay+duration);o.connect(g);g.connect(audio.destination);o.start(now+delay);o.stop(now+delay+duration);};if(kind==='cut'){tone(130,.2,'triangle');tone(80,.16,'square',.1,.025);}else if(kind==='clamp')tone(95,.16,'triangle');else if(kind==='seal'){tone(950,.28,'sawtooth',0,.018);tone(600,.12,'sine',.28);}else if(kind==='fold'){tone(400,.14,'triangle');tone(260,.12,'triangle',.14);}else tone(200,.08,'sine');}catch{}}
const win=root.querySelector('.shop');{
 const industrial=config.cutter==='industrial';win.dataset.kind=industrial?'industrial':'bench';const lifetime=new AbortController();const startedAt=performance.now();let finished=false;const maxErrors=Number(config.maxErrors)||6;const stats={cuts:0,folds:0,seals:0,printed:false,inspected:false};function complete(success){if(finished)return;finished=true;cancelHeat();onResult(success,{errors:s.errors,seconds:(performance.now()-startedAt)/1000,packs:s.packs.filter(p=>p.sealed).length,...stats});}
 const s={cols:config.cols||5,rows:config.rows||3,stage:0,job:stocks.indexOf(requestedStock),selected:0,flaw:Math.random()<(config.flawChance??.5),flag:false,errors:0,rowCuts:[],strip:0,cardCuts:[],used:[],loaded:[],packs:[],sealIndex:0,x:0,y:0,angle:0,blade:45,clamped:false,busy:false,sounds:true,token:0};
 let drag=null,moveFrame=0,pendingMove=null,heat=null,heatTimer=null,held=new Set();
 let pieces=[],nextPiece=0,selected=null,bedWidth=0;
 let mode='cut',empty=null,selectedPack=null,tool=null,toolSelected=false;
 win.innerHTML=`<h2>${industrial?'Hydraulic production bench':'Precision workbench'}</h2><div class="summary"></div><div class="setup"><label>Columns <input class="cols" type="number" min="1" max="10" value="5"></label><label>Rows <input class="rows" type="number" min="1" max="10" value="3"></label><button class="apply">Apply grid</button><button class="sounds" aria-pressed="true">Sound on</button></div><div class="steps"></div><div class="hint"></div><div class="choices"></div><div class="field"></div><div class="actions"></div><div class="meter" hidden><div class="meter-fill"></div></div><div class="tray" aria-label="Folded and sealed packs"></div><div class="status" aria-live="polite"></div><div class="footer"><span class="errors"></span><button class="restart">New job</button></div>`;
 const field=win.querySelector('.field'),status=win.querySelector('.status'),actions=win.querySelector('.actions');
 const total=()=>s.cols*s.rows,packCount=()=>total()/5;
 const cardRatio=322/230,sealMin=1.2,sealMax=1.8;
 function stockSize(){const cw=Math.max(12,Math.min(105,(field.clientWidth*.84-16-(s.cols-1)*12)/s.cols,(field.clientHeight*.72-(s.rows-1)*12-16)/s.rows/cardRatio,(field.clientHeight-50-(s.cols-1)*12-16)/s.cols));return {cw,ch:cw*cardRatio};}
 function sizeSheet(){const {cw,ch}=stockSize();field.style.setProperty('--sheet-width',s.cols*cw+(s.cols-1)*12+16+'px');field.style.setProperty('--sheet-height',s.rows*ch+(s.rows-1)*12+16+'px');}
 const card=i=>{const pool=stocks[s.stage===0?s.selected:s.job].pool;return art[pool[i%pool.length]];};
 function note(text,errors=0){s.errors+=errors;if(s.errors>=maxErrors)complete(false);win.querySelector('.errors').textContent=`Errors: ${s.errors} / ${maxErrors}`;status.textContent=s.errors>=maxErrors?'Batch failed. Too many accumulated errors. Start a new job.':text;}
 function active(){return !finished&&root.isConnected;}
 async function animate(el,frames,ms=450){if(!el)return;const motion=matchMedia('(prefers-reduced-motion: reduce)').matches?1:ms;const a=el.animate(frames,{duration:motion,easing:'ease-in-out',fill:'forwards'});try{await a.finished;}catch{} }
 function button(text,fn,primary=false){const b=document.createElement('button');b.textContent=text;b.className=primary?'primary cursor-interaction':'cursor-interaction';b.onclick=fn;actions.append(b);return b;}
 function cells(offset=0,count=s.cols){return Array.from({length:count},(_,j)=>{const i=offset+j;return `<button class="cell ${s.stage===1&&s.flaw&&i===Math.min(7,total()-1)?'misprint':''} ${s.stage===1&&s.flag&&i===Math.min(7,total()-1)?'flag':''}" data-id="${i}" aria-label="${card(i).name}">${face(card(i),'card-'+i)}</button>`;}).join('');}
 function sheet(){return `<div class="sheet">${Array.from({length:s.rows},(_,r)=>`<div class="print-row" data-row="${r}">${cells(r*s.cols)}</div>`).join('')}</div>`;}
 function packet(cls=''){return `<div class="packet ${cls}"><img class="front" src="${packFront}" alt="Meta Comics pack front"><img class="back" src="${packBack}" alt="Meta Comics pack back"><div class="seam"></div></div>`;}
 function tray(){win.querySelector('.tray').innerHTML=s.packs.map((p,i)=>`<div class="tray-item ${p.sealed?'sealed':''}"><img src="${p.sealed?packFront:packBack}" alt="Pack ${i+1}">${i+1} · ${p.sealed?'sealed':'folded'}</div>`).join('');}
 function transform(){const paper=field.querySelector('.sheet');if(paper){const a=s.angle*Math.PI/180,w=paper.offsetWidth,h=paper.offsetHeight,bw=Math.abs(w*Math.cos(a))+Math.abs(h*Math.sin(a)),bh=Math.abs(h*Math.cos(a))+Math.abs(w*Math.sin(a));s.x=Math.max((bw-w)/2-paper.offsetLeft,Math.min(field.clientWidth-paper.offsetLeft-(bw+w)/2,s.x));s.y=Math.max((bh-h)/2-paper.offsetTop,Math.min(field.clientHeight-paper.offsetTop-(bh+h)/2,s.y));paper.style.transform=`translate(${s.x}px,${s.y}px) rotate(${s.angle}deg)`;}const strip=field.querySelector('.strip');if(strip)strip.style.transform=`translate(${s.x}px,${s.y}px) rotate(${industrial?90:0}deg)`;const blade=field.querySelector('.blade');if(blade&&!industrial)blade.style[s.stage===3?'left':'top']=s.blade+'%';}
 function render(){
  s.token++;s.busy=false;cancelHeat();held.clear();drag=null;s.clamped=false;s.x=0;s.y=0;s.angle=0;s.blade=s.stage===2?39:45;
  win.style.setProperty('--cols',s.cols);win.style.setProperty('--stock-edge',stocks[s.stage===0?s.selected:s.job].edge);win.querySelector('.summary').textContent=`${config.setName ? config.setName + ' · ' : ''}${s.cols} × ${s.rows} · ${total()} cards · ${s.rows} strips · ${packCount()} packs · ${stocks[s.job].name}${config.requestedPacks ? ` · ${config.requestedPacks} packs remaining${config.bulkBonusRemaining ? ` · +${config.bulkBonusRemaining} bulk extras to earn` : ''}` : ''}`;
  win.querySelector('.steps').innerHTML=phases.map((name,i)=>`<button data-stage="${phaseIds[i]}" aria-pressed="${s.stage===phaseIds[i]}">${name}</button>`).join('');win.querySelectorAll('[data-stage]').forEach(b=>{b.disabled=true;});actions.innerHTML='';win.querySelector('.choices').innerHTML='';win.querySelector('.meter').hidden=s.stage!==5;
  field.className='field '+(industrial&&[2,3].includes(s.stage)?'industrial':'');field.style.minHeight='0';
  const hints=[`Requested: Sheet ${'ABCDEF'[s.job]}. Choose artwork; drag to the registration marks. Q/E rotate, arrows nudge, Enter prints.`,`Click the obvious flaw to flag it. Accept it for review or reject and reprint. Missing an obvious flaw adds two errors.`,industrial?'Drag a white row gutter under the red line. C clamps; Q + E cycles the blade.':'Drag the blade into a white row gutter. Space cuts and separates the sheet.',industrial?'Each strip feeds sideways. Drag a white card gutter under the red line; C clamps, Q + E cuts.':'Each strip contains its own cards. Drag the blade into a white card gutter; Space cuts.',`Load five cards, fold the wrapper, then repeat for all ${packCount()} packs.`,`Seal each of the ${packCount()} folded packs. Drag the jaw onto the back seam, then hold for 1.2–1.8 seconds.`];win.querySelector('.hint').textContent=hints[s.stage];
  sizeSheet();
  if(s.stage===0){field.innerHTML='<div class="registration"></div>'+sheet();s.x=14;s.y=12;s.angle=3;transform();const choices=win.querySelector('.choices');choices.innerHTML=stocks.map((_,i)=>`<button data-job="${i}" aria-pressed="${s.selected===i}">${face(art[stocks[i].pool[0]],'choice-'+i)}Sheet ${'ABCDEF'[i]} · ${stocks[i].name}</button>`).join('');choices.querySelectorAll('button').forEach(b=>b.onclick=()=>{s.selected=+b.dataset.job;win.style.setProperty('--stock-edge',stocks[s.selected].edge);choices.querySelectorAll('button').forEach(c=>c.setAttribute('aria-pressed',c===b));field.querySelector('.sheet').outerHTML=sheet();transform();note(`Sheet ${'ABCDEF'[s.selected]} selected. Compatible ${stocks[s.selected].name} cards only.`);});button('Rotate left · Q',()=>{s.angle--;transform();});button('Rotate right · E',()=>{s.angle++;transform();});button('Print · Enter',print,true);note('Align the sheet with the registration frame.');
  }else if(s.stage===1){field.innerHTML=sheet();field.querySelectorAll('.cell').forEach(b=>b.onclick=()=>{if(+b.dataset.id===Math.min(7,total()-1)&&s.flaw){s.flag=true;b.classList.add('flag');note('Caught: ink banding and shifted registration.');}else note('This print looks clean.');});button('Accept inspected sheet',()=>{const missed=s.flaw&&!s.flag;stats.inspected=true;s.stage=2;render();note(missed?'Obvious flaw missed: +2 errors.':'Print inspected; cut the matching-colour gutters.',missed?2:0);},true);button('Reject & reprint',()=>{s.flaw=false;s.flag=false;sound('fold',s.sounds);render();note('Clean replacement. Inspect it, then accept.');});note(s.flaw?'Inspect the print before cutting.':'Clean replacement sheet.');
  }else if(s.stage===2){
   renderCutWorkspace();
   if(mode!=='cut')renderBenchTools();
  }tray();note(status.textContent);
 }
 async function print(){if(s.busy||s.errors>=maxErrors)return;if(s.selected!==s.job)return note('Wrong sheet selected: +1 error.',1);if(Math.abs(s.x)>6||Math.abs(s.y)>6||Math.abs(s.angle)>1)return note('Stock is misregistered: +1 error.',1);s.busy=true;const token=s.token;sound('fold',s.sounds);await animate(field.querySelector('.sheet'),[{filter:'brightness(.65)'},{filter:'brightness(1)'}],550);if(token!==s.token)return;stats.printed=true;s.stage=1;render();note('Printed. Inspect for flaws.');}
 function clamp(){if(s.busy)return;s.clamped=!s.clamped;field.querySelector('.clamp')?.classList.toggle('closed',s.clamped);sound('clamp',s.sounds);note(s.clamped?'Stock clamped. Q + E cycles the blade.':'Unclamped. Reposition the stock.');}
 function label(p){return p.rows>1?`${p.rows}-row sheet section`:p.cols>1?`Strip ${Math.floor(p.ids[0]/s.cols)+1} · ${p.cols} joined cards`:`Card ${p.ids[0]+1}`;}
 function renderCutWorkspace(){
  const {cw,ch}=stockSize();
  field.style.minHeight='0';
  if(!pieces.length){bedWidth=field.clientWidth;pieces=[{id:nextPiece++,ids:Array.from({length:total()},(_,i)=>i),cols:s.cols,rows:s.rows,w:s.cols*cw+(s.cols-1)*12+16,h:s.rows*ch+(s.rows-1)*12+16,x:50,y:53,angle:0}];selected=pieces[0].id;}
  field.innerHTML=(industrial?'<div class="head"><span>HYDRAULIC CUTTER</span><span class="display">CUTTING BED</span></div>':'')+'<div class="blade">'+(industrial?'':'<button class="blade-grip" aria-label="Move blade">↕</button>')+'</div>'+(industrial?'<div class="clamp"></div><div class="guillotine"></div>':'')+'<span class="guide"></span>';
  if(industrial){button('Clamp · C',clamp);button('Cut · Q + E',cut,true);}else button('Cut · Space',cut,true);
  button('Rotate left · F',()=>rotate(-90));button('Rotate right · R',()=>rotate(90));
  win.querySelector('.hint').textContent=industrial?'Drag each piece individually. F/R rotate it. Cut the matching-colour gutters; keep artwork clear. C clamps; Q + E cuts.':'Drag each piece individually. F/R rotate it. Cut the matching-colour gutters; Space cuts. Keep other pieces clear.';
  drawPieces();note('Cut the sheet into strips first, then rotate and position each strip to cut its cards.');
 }
 function drawPieces(){
  const scale=field.clientWidth/bedWidth;
  const existing=new Map([...field.querySelectorAll('.work-piece')].map(el=>[+el.dataset.piece,el]));
  const cells=new Map([...field.querySelectorAll('[data-cut-card]')].map(el=>[+el.dataset.cutCard,el]));
  for(const p of pieces){
   let el=existing.get(p.id);
   if(!el){el=document.createElement('div');el.dataset.piece=p.id;field.append(el);}
   existing.delete(p.id);
   el.className='work-piece '+(p.cols===1&&p.rows===1?'single ':'')+(p.id===selected?'selected':'');el.setAttribute('aria-label',label(p));el.style.width=p.w*scale+'px';el.style.height=p.h*scale+'px';el.style.gridTemplateColumns=`repeat(${p.cols},1fr)`;el.style.gridTemplateRows=`repeat(${p.rows},1fr)`;el.style.transform=`translate(-50%,-50%) rotate(${p.angle}deg)`;
   for(const i of p.ids){let cell=cells.get(i);if(!cell){cell=document.createElement('button');cell.className='cell';cell.dataset.cutCard=i;cell.innerHTML=face(card(i),'card-'+i);cell.onclick=()=>{selected=+cell.parentElement.dataset.piece;selectedPack=null;toolSelected=false;highlight();};}cell.setAttribute('aria-label',`Select ${label(p)}`);if(cell.parentElement!==el)el.append(cell);}
   let caption=el.querySelector('.piece-label');if(!caption){caption=document.createElement('span');caption.className='piece-label';el.append(caption);}caption.textContent=label(p);
   contain(p,el);el.style.left=p.x+'%';el.style.top=p.y+'%';
  }
  existing.forEach(el=>el.remove());
  const finished=pieces.filter(p=>p.cols===1&&p.rows===1).length;
  field.querySelector('.guide').textContent=`${pieces.length} separate pieces · ${finished} / ${total()} individual cards`;
  if(mode==='cut'&&finished===total()&&!actions.querySelector('.collect')){const b=button('Grab an empty pack',()=>{mode='load';s.clamped=false;renderBenchTools();spawnPack();},true);b.classList.add('collect');}
  transform();
 }
 function highlight(){field.querySelectorAll('.work-piece').forEach(el=>el.classList.toggle('selected',+el.dataset.piece===selected));const p=pieces.find(p=>p.id===selected);if(p)note(`Selected: ${label(p)}. Drag or use F/R to rotate.`);}
 function rotate(deg){if(s.busy||s.clamped)return;if(toolSelected&&tool){tool.angle=(tool.angle+deg+360)%360;drawBenchTools();contain(tool,field.querySelector('.bench-tool'));drawBenchTools();return;}if(selectedPack!==null){const p=s.packs[selectedPack];if(p&&!p.sealed){p.angle=(p.angle+deg+360)%360;drawBenchTools();contain(p,field.querySelector(`[data-pack="${selectedPack}"]`));drawBenchTools();}return;}const p=pieces.find(p=>p.id===selected);if(!p)return;p.angle=(p.angle+deg+360)%360;const el=field.querySelector(`[data-piece="${p.id}"]`);contain(p,el);el.style.transform=`translate(-50%,-50%) rotate(${p.angle}deg)`;el.style.left=p.x+'%';el.style.top=p.y+'%';highlight();}
 function proposals(){
  const box=field.getBoundingClientRect(),line=box.top+(industrial ? .39 : s.blade/100)*box.height,plans=[],bad=[];
  const sheetRemaining=pieces.some(p=>p.rows>1);
  for(const p of pieces){const el=field.querySelector(`[data-piece="${p.id}"]`),b=el.getBoundingClientRect();if(line<=b.top+1||line>=b.bottom-1||b.right<=box.left+box.width*.03||b.left>=box.right-box.width*.03)continue;
   const axis=p.rows>1&&p.angle%180===0?'row':!sheetRemaining&&p.cols>1&&p.angle%180===90?'col':null;
   if(!axis){bad.push(label(p));continue;}
   const w=el.clientWidth,h=el.clientHeight,cw=(w-16-(p.cols-1)*12)/p.cols,ch=(h-16-(p.rows-1)*12)/p.rows,rad=p.angle*Math.PI/180,cy=(b.top+b.bottom)/2,count=axis==='row'?p.rows:p.cols;
   let index=-1;for(let i=0;i<count-1;i++){const local=axis==='row'?-h/2+8+(i+1)*ch+i*12+6:-w/2+8+(i+1)*cw+i*12+6;const y=cy+local*(axis==='row'?Math.cos(rad):Math.sin(rad));if(Math.abs(y-line)<=5){index=i;break;}}
   if(index<0){bad.push(label(p));continue;}plans.push({p,axis,index,w,h,cw,ch});
  }
  return {plans,bad};
 }
 function splitPiece(plan){
  const {p,axis,index,w,h,cw,ch}=plan,n=index+1,scale=field.clientWidth/bedWidth,rad=p.angle*Math.PI/180;
  const a={...p,id:nextPiece++},b={...p,id:nextPiece++};let da,db;
  if(axis==='row'){a.rows=n;b.rows=p.rows-n;a.ids=p.ids.slice(0,n*p.cols);b.ids=p.ids.slice(n*p.cols);a.h=(16+n*ch+(n-1)*12)/scale;b.h=(16+b.rows*ch+(b.rows-1)*12)/scale;da=(a.h*scale-h)/2;db=(h-b.h*scale)/2;}else{a.cols=n;b.cols=p.cols-n;a.ids=p.ids.slice(0,n);b.ids=p.ids.slice(n);a.w=(16+n*cw+(n-1)*12)/scale;b.w=(16+b.cols*cw+(b.cols-1)*12)/scale;da=(a.w*scale-w)/2;db=(w-b.w*scale)/2;}
  for(const [child,delta] of [[a,da],[b,db]]){const dx=delta*(axis==='row'?-Math.sin(rad):Math.cos(rad)),dy=delta*(axis==='row'?Math.cos(rad):Math.sin(rad));child.x=p.x+dx/field.clientWidth*100;child.y=p.y+(dy+Math.sign(dy||delta)*10)/field.clientHeight*100;}
  // Trim the outside stock margin only when a piece becomes an individual card.
  for(const child of [a,b])if(child.rows===1&&child.cols===1){child.w=cw/scale;child.h=ch/scale;}
  pieces.splice(pieces.indexOf(p),1,a,b);if(selected===p.id)selected=a.ids.length>b.ids.length?a.id:b.id;
 }
 async function cut(){if(s.busy||s.errors>=maxErrors)return;if(industrial&&!s.clamped)return note('Clamp the stock before cycling the blade.');const {plans,bad}=proposals();if(bad.length)return note(`Blade would hit artwork or a wrongly oriented piece: ${bad.join(', ')}. Move it clear. +2 errors.`,2);if(!plans.length)return note('No uncut gutter under the blade. Position a piece first.');s.busy=true;const token=s.token;
  if(industrial)await animate(field.querySelector('.guillotine'),[{opacity:1,transform:'translateY(0)'},{opacity:1,transform:'translateY(50px)'},{opacity:0,transform:'translateY(0)'}],650);else{const b=field.querySelector('.blade'),base=getComputedStyle(b).transform;await animate(b,[{transform:base+' scale(1)'},{transform:base+' scale(.97)'},{transform:base+' scale(1)'}],180);}
  if(token!==s.token)return;sound('cut',s.sounds&&active());stats.cuts+=plans.length;for(const plan of plans)splitPiece(plan);s.clamped=false;field.querySelector('.clamp')?.classList.remove('closed');drawPieces();s.busy=false;note(`Clean cut across ${plans.length} ${plans.length===1?'piece':'pieces'}. Only those cut boundaries separated.`);
 }
 function renderBenchTools(){
  actions.innerHTML='';field.querySelectorAll('.blade,.head,.clamp,.guillotine,.guide').forEach(el=>el.style.display='none');win.querySelector('.meter').hidden=mode!=='seal';
  if(mode==='load'){button('Grab empty pack',spawnPack,true);button('Fold & place pack',foldBenchPack);win.querySelector('.hint').textContent=`Keep working on this table. Grab an empty wrapper, move it where you want, and drag five cut cards into it. Fold all ${packCount()} packs.`;}else{button('Grab sealer',()=>{tool??={x:15,y:55,angle:0};toolSelected=true;selectedPack=null;selected=null;drawBenchTools();},true);const b=button('Hold to seal · Space',()=>{},true);b.onpointerdown=e=>{e.preventDefault();startHeat();};b.onpointerup=b.onpointerleave=()=>stopHeat();button('Rotate left · F',()=>rotate(-90));button('Rotate right · R',()=>rotate(90));win.querySelector('.hint').textContent='Grab the sealer and a folded pack. Move and rotate both until the jaw covers the back seam; hold for 1.2–1.8 seconds.';}
  drawBenchTools();
 }
 function spawnPack(){if(s.busy||mode!=='load'||empty||s.packs.length>=packCount())return;empty={x:72,y:58,angle:0,ids:[]};drawBenchTools();note(`Empty pack ${s.packs.length+1} ready. Drag five individual cards into it.`);}
 function drawBenchTools(){
  field.querySelectorAll('.bench-empty,.bench-pack,.bench-tool').forEach(el=>el.remove());
  if(empty){field.insertAdjacentHTML('beforeend',packet('bench-empty'));const el=field.querySelector('.bench-empty');el.style.setProperty('--wrapper-back',`url("${packBack}")`);el.style.left=empty.x+'%';el.style.top=empty.y+'%';el.insertAdjacentHTML('beforeend',`<div class="flap left"><span class="foil-inside"></span><span class="foil-outside left-half"></span></div><div class="flap right"><span class="foil-inside"></span><span class="foil-outside right-half"></span></div><div class="bench-count">Pack ${s.packs.length+1}<br>${empty.ids.length} / 5</div>`);empty.ids.forEach((id,i)=>{const img=document.createElement('span');img.dataset.print=card(id).index;img.dataset.face='card-'+id;img.className='cw-face loaded-card';img.style.transform=`rotate(${i*3-6}deg)`;img.alt='Loaded card';el.append(img);});}
  s.packs.forEach((p,i)=>{field.insertAdjacentHTML('beforeend',packet('bench-pack '+(p.sealed?'sealed ':'')+(selectedPack===i?'selected':'')));const el=field.querySelector('.bench-pack:last-child');el.dataset.pack=i;el.style.left=p.x+'%';el.style.top=p.y+'%';el.style.transform=`translate(-50%,-50%) rotate(${p.angle}deg)`;el.setAttribute('aria-label',`Pack ${i+1} ${p.sealed?'sealed':'folded'}`);});
  if(tool){const el=document.createElement('div');el.className='jaw bench-tool';el.style.left=tool.x+'%';el.style.top=tool.y+'%';el.style.transform=`translate(-50%,-50%) rotate(${tool.angle}deg)`;el.setAttribute('aria-label','Heat sealer');field.append(el);contain(tool,el);el.style.left=tool.x+'%';el.style.top=tool.y+'%';}
  if(empty){const el=field.querySelector('.bench-empty');contain(empty,el);el.style.left=empty.x+'%';el.style.top=empty.y+'%';}
  s.packs.forEach((p,i)=>{const el=field.querySelector(`[data-pack="${i}"]`);contain(p,el);el.style.left=p.x+'%';el.style.top=p.y+'%';});
  tray();
 }
 function loadBenchCard(p){if(!empty||empty.ids.length>=5||p.ids.length!==1||s.busy)return;const id=p.ids[0];empty.ids.push(id);s.used.push(id);pieces.splice(pieces.indexOf(p),1);selected=null;sound('place',s.sounds);drawPieces();drawBenchTools();note(empty.ids.length===5?'Five cards loaded. Fold and place this wrapper.':`${empty.ids.length} / 5 cards loaded.`);}
 async function foldBenchPack(){
  if(s.busy||!empty)return;if(empty.ids.length!==5)return note('Load exactly five individual cards before folding.',1);
  s.busy=true;const token=s.token,el=field.querySelector('.bench-empty');sound('fold',s.sounds);el.querySelector('.bench-count').style.opacity=0;
  await Promise.all([animate(el.querySelector('.flap.left'),[{transform:'rotateY(0)'},{transform:'rotateY(178deg)'}],550),animate(el.querySelector('.flap.right'),[{transform:'rotateY(0)'},{transform:'rotateY(-178deg)'}],650)]);
  if(token!==s.token)return;const p={cards:[...empty.ids],sealed:false,x:82,y:20+(s.packs.length%3)*28,angle:0};
  el.classList.replace('bench-empty','bench-pack');el.innerHTML=`<img class="back" src="${packBack}" alt="Folded pack">`;
  const b=el.getBoundingClientRect(),f=field.getBoundingClientRect();await animate(el,[{transform:'translate(-50%,-50%)'},{transform:`translate(calc(-50% + ${f.left+f.width*p.x/100-b.left-b.width/2}px),calc(-50% + ${f.top+f.height*p.y/100-b.top-b.height/2}px)) rotate(8deg)`}],450);
  if(token!==s.token)return;s.packs.push(p);stats.folds++;empty=null;s.busy=false;if(s.packs.length===packCount())mode='seal';renderBenchTools();note(mode==='seal'?'All packs folded. Grab the sealer and line up the first pack.':`Pack ${s.packs.length} folded and placed. Grab another empty wrapper.`);
 }
 function benchTarget(){if(!tool)return null;for(let i=0;i<s.packs.length;i++){const p=s.packs[i];if(p.sealed)continue;const x=(p.x-tool.x)*field.clientWidth/100,y=(p.y-tool.y)*field.clientHeight/100,angle=Math.abs(((p.angle-tool.angle+540)%360)-180);if(Math.hypot(x,y)<12&&angle<2)return i;}return null;}
 function paintHeat(elapsed){const jaw=field.querySelector('.bench-tool');if(!jaw)return;const ready=elapsed>=sealMin&&elapsed<=sealMax;jaw.style.setProperty('--heat-fill',Math.min(100,elapsed/sealMin*100)+'%');jaw.classList.toggle('ready',ready);jaw.classList.toggle('overheated',elapsed>sealMax);jaw.setAttribute('aria-label',ready?'Heat sealer: release now':elapsed>sealMax?'Heat sealer: overheated':'Heat sealer: heating');}
 function startBenchHeat(){if(heat||s.busy||s.errors>=maxErrors||mode!=='seal')return;const index=benchTarget();if(index===null)return note('Line the sealer up with the folded pack: match position and angle.');heat={start:performance.now(),good:true,index};sound('seal',s.sounds);field.querySelector('.bench-tool').classList.add('hot');paintHeat(0);const tick=()=>{if(!heat)return;if(!active()){cancelHeat();return;}const elapsed=(performance.now()-heat.start)/1000;heat.good&&=benchTarget()===index;paintHeat(elapsed);win.querySelector('.meter-fill').style.width=Math.min(100,elapsed/sealMin*100)+'%';status.textContent=`Pack ${index+1} · ${elapsed.toFixed(1)} s · ${elapsed>=sealMin&&elapsed<=sealMax?'Release now':elapsed>sealMax?'Overheated':'Heating…'}`;if(elapsed>2.2)stopHeat();else heatTimer=requestAnimationFrame(tick);};heatTimer=requestAnimationFrame(tick);}
 async function stopBenchHeat(){if(!heat)return;const {start,good,index}=heat,elapsed=(performance.now()-start)/1000;cancelHeat();if(elapsed<sealMin||elapsed>sealMax||!good)return note(!good?'Sealer moved off the seam: +1 error.':elapsed<sealMin?'Weak seal: +1 error.':'Scorched foil: +2 errors.',elapsed>sealMax?2:1);s.busy=true;const token=s.token,p=s.packs[index],el=field.querySelector(`[data-pack="${index}"]`);sound('seal',s.sounds);await animate(el,[{transform:`translate(-50%,-50%) rotate(${p.angle}deg) rotateY(0)`},{transform:`translate(-50%,-50%) rotate(${p.angle}deg) rotateY(180deg)`}],600);if(token!==s.token)return;const nextX=18+(index%4)*19,nextY=87;await animate(el,[{transform:`translate(-50%,-50%) rotate(${p.angle}deg) rotateY(180deg)`},{transform:`translate(calc(-50% + ${(nextX-p.x)*field.clientWidth/100}px),calc(-50% + ${(nextY-p.y)*field.clientHeight/100}px)) rotateY(180deg)`}],450);if(token!==s.token)return;p.sealed=true;stats.seals++;p.x=nextX;p.y=nextY;p.angle=0;s.busy=false;drawBenchTools();note(s.packs.every(p=>p.sealed)?`Batch complete: all ${packCount()} packs sealed and placed on this table.`:`Pack ${index+1} sealed. Position the next pack and sealer.`);if(s.packs.every(p=>p.sealed))complete(true);}
 function startHeat(){return startBenchHeat();}
 function cancelHeat(){if(!heat)return;cancelAnimationFrame(heatTimer);heat=null;const jaw=field.querySelector('.jaw');jaw?.classList.remove('hot','ready','overheated');jaw?.style.setProperty('--heat-fill','0%');jaw?.setAttribute('aria-label','Heat sealer');win.querySelector('.meter-fill').style.width='0%';}
 async function stopHeat(){return stopBenchHeat();}
 field.onpointerdown=e=>{
  e.preventDefault();win.querySelector('.sounds').focus({preventScroll:true});if(s.busy||s.errors>=maxErrors)return;
  const piece=e.target.closest('.work-piece'),packetEl=e.target.closest('.bench-pack'),emptyEl=e.target.closest('.bench-empty'),toolEl=e.target.closest('.bench-tool');
  if(s.stage===2){
   if(toolEl&&tool){toolSelected=true;selectedPack=null;selected=null;drag={kind:'tool',model:tool,el:toolEl};}
   else if(packetEl){const i=+packetEl.dataset.pack;if(s.packs[i].sealed)return;selectedPack=i;toolSelected=false;selected=null;field.querySelectorAll('.bench-pack').forEach(el=>el.classList.toggle('selected',el===packetEl));drag={kind:'pack',model:s.packs[i],el:packetEl};}
   else if(emptyEl&&empty){drag={kind:'empty',model:empty,el:emptyEl};}
   else if(piece&&!s.clamped){selected=+piece.dataset.piece;selectedPack=null;toolSelected=false;const p=pieces.find(p=>p.id===selected);highlight();drag={kind:'piece',id:p.id,model:p,el:piece};}
   else if(mode==='cut'&&!industrial&&e.target.closest('.blade'))drag={kind:'blade'};
  }else if(s.stage===0)drag={kind:'stock',x:e.clientX,y:e.clientY,baseX:s.x,baseY:s.y};
  if(drag){if(drag.model)Object.assign(drag,{x:e.clientX,y:e.clientY,baseX:drag.model.x,baseY:drag.model.y});field.setPointerCapture(e.pointerId);}
 };
 function movePointer(e){if(!drag)return;const r=field.getBoundingClientRect();if(drag.model){drag.model.x=drag.baseX+(e.clientX-drag.x)/r.width*100;drag.model.y=drag.baseY+(e.clientY-drag.y)/r.height*100;contain(drag.model,drag.el);drag.el.style.left=drag.model.x+'%';drag.el.style.top=drag.model.y+'%';}
  else if(drag.kind==='stock'){s.x=drag.baseX+e.clientX-drag.x;s.y=drag.baseY+e.clientY-drag.y;transform();}
  else{s.blade=Math.max(3,Math.min(97,(e.clientY-r.top)/r.height*100));transform();}
 };
 field.onpointermove=e=>{if(!drag)return;pendingMove={clientX:e.clientX,clientY:e.clientY};if(!moveFrame)moveFrame=requestAnimationFrame(()=>{moveFrame=0;const point=pendingMove;pendingMove=null;if(point)movePointer(point);});};
 field.onpointerup=e=>{cancelAnimationFrame(moveFrame);moveFrame=0;if(pendingMove){movePointer(pendingMove);pendingMove=null;}if(drag?.kind==='piece'&&mode==='load'&&empty){const r=field.querySelector('.bench-empty').getBoundingClientRect();if(e.clientX>=r.left&&e.clientX<=r.right&&e.clientY>=r.top&&e.clientY<=r.bottom)loadBenchCard(drag.model);}drag=null;};
 field.onpointercancel=()=>{cancelAnimationFrame(moveFrame);moveFrame=0;pendingMove=null;drag=null;cancelHeat();};
 document.addEventListener('keydown',e=>{
  if(!active()||!win.contains(document.activeElement)||/INPUT|SELECT|TEXTAREA/.test(e.target.tagName)||s.busy)return;const k=e.key.toLowerCase();if(!['q','e','c','f','r',' ','enter','arrowleft','arrowright','arrowup','arrowdown'].includes(k))return;e.preventDefault();if(e.repeat)return;
  if(s.stage===0){if(k==='q')s.angle--;if(k==='e')s.angle++;if(k==='arrowleft')s.x-=2;if(k==='arrowright')s.x+=2;if(k==='arrowup')s.y-=2;if(k==='arrowdown')s.y+=2;transform();if(k==='enter')print();}
  else if(s.stage===2){
   if(k==='f')rotate(-90);else if(k==='r')rotate(90);
   else if(k.startsWith('arrow')&&!s.clamped){const p=toolSelected?tool:selectedPack!==null?s.packs[selectedPack]:pieces.find(p=>p.id===selected);if(p){if(k==='arrowleft')p.x-=.5;if(k==='arrowright')p.x+=.5;if(k==='arrowup')p.y-=.5;if(k==='arrowdown')p.y+=.5;if(p===tool||selectedPack!==null){drawBenchTools();contain(p,field.querySelector(toolSelected?'.bench-tool':`[data-pack="${selectedPack}"]`));}else contain(p,field.querySelector(`[data-piece="${p.id}"]`));if(p===tool||selectedPack!==null)drawBenchTools();else{const el=field.querySelector(`[data-piece="${p.id}"]`);el.style.left=p.x+'%';el.style.top=p.y+'%';}}}
   else if(mode==='seal'&&k===' ')startHeat();
   else if(mode==='cut'){if(industrial){if(k==='c')clamp();held.add(k);if(held.has('q')&&held.has('e'))cut();}else if(k===' ')cut();}
  }
 },{signal:lifetime.signal});document.addEventListener('keyup',e=>{held.delete(e.key.toLowerCase());if(e.key===' ')stopHeat();},{signal:lifetime.signal});
 win.querySelector('.sounds').onclick=e=>{s.sounds=!s.sounds;e.currentTarget.setAttribute('aria-pressed',s.sounds);e.currentTarget.textContent=s.sounds?'Sound on':'Sound off';if(s.sounds)sound('place',true);};
 document.addEventListener('visibilitychange',()=>{if(document.hidden)cancelHeat();},{signal:lifetime.signal});render();
 const resize=new ResizeObserver(()=>{if(s.stage===2&&pieces.length&&field.clientWidth>100&&field.querySelector('.guide')&&!s.busy){if(p===tool||selectedPack!==null)drawBenchTools();else{const el=field.querySelector(`[data-piece="${p.id}"]`);el.style.left=p.x+'%';el.style.top=p.y+'%';}}});resize.observe(field);

 const timeout=setTimeout(()=>complete(false),Math.max(30,Number(config.time)||900)*1000);document.addEventListener('keydown',e=>{if(e.key==='Escape'){e.preventDefault();complete(false);}},{signal:lifetime.signal});
 return ()=>{finished=true;s.token++;cancelAnimationFrame(moveFrame);cancelHeat();clearTimeout(timeout);lifetime.abort();resize.disconnect();root.getAnimations({subtree:true}).forEach(a=>a.cancel());audio?.close().catch(()=>{});root.innerHTML='';};
}
}
