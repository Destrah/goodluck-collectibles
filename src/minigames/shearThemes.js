// Shared canvas artwork, injected into the isolated game documents.
function camTheme(){return options.theme==='camlock'}
function metal(c,x,y,w,h,brass=false){
  c.fillStyle=lin(x,y,x+w,y+h,brass?['#ffe8a0','#b7903c','#f1d57b','#826025']:['#eef2ef','#737e83','#d1d9db','#687176']);
  rr(x,y,w,h,12);c.fill();c.strokeStyle=brass?'#644b20':'#41494d';c.lineWidth=2;c.stroke();
}
function shackle(c,x,y,width,height,retainedHeight=height){
  c.lineCap='round';
  for(const [color,size] of [['#454e53',27],['#adb7bb',23],['#ecf0ef',9]]){
    c.strokeStyle=color;c.lineWidth=size;c.beginPath();c.moveTo(x,y+retainedHeight);c.lineTo(x,y+width/2);c.arc(x+width/2,y+width/2,width/2,Math.PI,0);c.lineTo(x+width,y+height);c.stroke();
  }
}
function drawThemeHousing(c){
  if(camTheme()){
    metal(c,156,38,514,336);metal(c,148,24,42,364);
    // Tailpiece attaches on the cylinder axis, through the middle of the housing.
    metal(c,670,186,48,44);metal(c,704,100,26,130);
    c.strokeStyle='#53616b';c.lineWidth=2;for(let i=0;i<6;i++){c.beginPath();c.moveTo(158+i*4,42);c.lineTo(158+i*4,362);c.stroke()}
  }else{
    c.lineCap='round';for(const [color,size] of [['#454e53',27],['#adb7bb',23],['#ecf0ef',9]]){
      c.strokeStyle=color;c.lineWidth=size;c.beginPath();c.moveTo(620,96);c.lineTo(688,96);c.bezierCurveTo(798,96,798,316,688,316);c.lineTo(620,316);c.stroke();
    }
    metal(c,170,34,490,340,true);
    c.fillStyle='#463c21';c.fillRect(638,88,23,17);c.fillRect(638,308,23,17);
    c.fillStyle='#ebe2ba';for(const y of [96,316]){c.beginPath();c.arc(638,y,9,0,Math.PI*2);c.fill()}
  }
}
function drawThemeFaceBack(c,cx,cy){
  if(camTheme()){
    c.fillStyle=lin(cx-130,cy-130,cx+130,cy+130,['#f8faf7','#6f7d85','#d1dadf']);c.beginPath();c.arc(cx,cy,128,0,Math.PI*2);c.fill();
    for(let i=0;i<6;i++){const a=i*Math.PI/3;c.fillStyle='#454f56';c.beginPath();c.arc(cx+113*Math.cos(a),cy+113*Math.sin(a),3,0,Math.PI*2);c.fill()}
  }else metal(c,cx-170,cy-125,340,250,true);
}
function drawSideSection(alpha,q){
  const c=ctx;c.save();c.globalAlpha=alpha;c.translate(400,220);
  if(camTheme()){
    c.rotate(-.18);metal(c,-174,-74,290,148);metal(c,-194,-86,38,172);
    c.strokeStyle='#899297';c.lineWidth=3;for(let i=0;i<7;i++){c.beginPath();c.moveTo(-150+i*11,-65);c.lineTo(-150+i*11,65);c.stroke()}
    metal(c,106,-25,60,50);c.translate(156,0);c.rotate(q.turn*Math.PI/2);metal(c,-16,-12,125,24);metal(c,87,-12,24,83);
    c.restore();return;
  }
  c.rotate(-.38);
  // The retained leg slides up from its bore; the short leg clears the body before swivelling.
  c.save();c.translate(-84,-145-q.pop*56);c.scale(1-.58*q.swivel,1);shackle(c,0,0,168,174,250);c.restore();
  metal(c,-122,-4,244,180,true);
  c.fillStyle='#574321';c.beginPath();c.ellipse(-84,0,17,5,0,0,Math.PI*2);c.ellipse(84,0,17,5,0,0,Math.PI*2);c.fill();
  c.restore();
}
