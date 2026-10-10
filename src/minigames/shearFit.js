// Fit the whole bench, including controls, inside the iframe without clipping or scrollbars.
const benchLayout=document.querySelector('.wrap');
function fitBench(){
  if(!benchLayout)return;
  const width=Math.min(850,window.innerWidth);
  benchLayout.style.width=width+'px';
  const height=benchLayout.offsetHeight;
  const scale=Math.min(1,window.innerWidth/width,window.innerHeight/Math.max(1,height));
  benchLayout.style.transform=`scale(${scale})`;
  benchLayout.style.left=(window.innerWidth-width*scale)/2+'px';
  benchLayout.style.top=Math.max(0,(window.innerHeight-height*scale)/2)+'px';
}
if(benchLayout){
  const style=document.createElement('style');
  style.textContent='html,body{width:100%;height:100%;overflow:hidden;margin:0}.wrap{position:absolute;box-sizing:border-box;max-width:none!important;margin:0!important;transform-origin:top left}';
  document.head.append(style);
  window.addEventListener('resize',fitBench);
  if(typeof ResizeObserver!=='undefined')new ResizeObserver(fitBench).observe(benchLayout);
  fitBench();
}
