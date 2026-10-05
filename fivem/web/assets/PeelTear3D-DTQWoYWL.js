import{W as Be,a2 as Se,S as be,g as Ae,ac as Ce,G as Fe,i as _,n as E,x as Y,o as J,Z as Re,p as _e,C as Pe,q as ue,b as Ie,J as ke,V as Ue}from"./three.module-CHRBPEPm.js";const Ve={front:"/img/pack_open_front.jpg",back:"/img/pack_open_back.jpg",cardBack:"/img/Cards_Back.jpg",maxPixelRatio:1.5,packFill:.72},Oe={spinA:.25,spinB:2.05,pushB:2.55,seamA:3.5,seamB:3.85,peelB:4.95,riseB:6.6},t=Oe,Q=[[0,"front"],[t.spinA,"tilt"],[t.spinA+.15,"flip-start"],[1.15,"flip-half"],[t.spinB,"back"],[t.seamA,"seam-tension"],[t.seamB,"tear-start"],[t.seamB+.3,"tear-mid"],[t.seamB+.6,"tear-open"],[t.peelB,"cards-pull"]],qe=2,y=qe*480/840,A=.1,O=y*.84,I=O*322/230,ve=.76-I/2,pe=1+I/2+.12,g=(r,M=0,m=1)=>Math.min(m,Math.max(M,r)),P=(r,M,m)=>r+(M-r)*m,x=(r,M,m)=>{const u=g((m-r)/(M-r));return u*u*(3-2*u)},C=r=>r<.5?4*r*r*r:1-Math.pow(-2*r+2,3)/2,ze=r=>1+(1.3+1)*Math.pow(r-1,3)+1.3*Math.pow(r-1,2),Ge=`
float hash(vec2 p){ return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float noise(vec2 p){ vec2 i = floor(p), f = fract(p); vec2 u = f*f*(3.0-2.0*f);
  return mix(mix(hash(i), hash(i+vec2(1,0)), u.x), mix(hash(i+vec2(0,1)), hash(i+vec2(1,1)), u.x), u.y); }`,Ne=`
varying vec2 vUv; varying vec3 vN; varying vec3 vV;
void main(){ vUv = uv; vN = normalize(normalMatrix * normal);
  vec4 mv = modelViewMatrix * vec4(position, 1.0); vV = mv.xyz; gl_Position = projectionMatrix * mv; }`,Te=`
uniform sampler2D uFront, uBack; uniform float uSheet, uSeam, uOpacity, uHaloI, uSheen, uGlow;
varying vec2 vUv; varying vec3 vN; varying vec3 vV;
${Ge}
void main(){
  vec2 uv = vUv;
  float teeth = abs(fract(uv.x * 24.0) - 0.5) * 2.0;
  float cr = 0.03;
  if (uv.y > 1.0 - cr * (0.3 + 0.7 * teeth) || uv.y < cr * (0.3 + 0.7 * teeth)) discard;
  float side = 0.006 + 0.006 * noise(vec2(uv.y * 38.0, 3.0));
  if (uv.x < side || uv.x > 1.0 - side) discard;
  if (uSeam > 0.0) {
    float j = abs(fract(uv.y * 34.0 + noise(uv * vec2(4.0, 70.0)) * 0.8) - 0.5) * 2.0;
    if (abs(uv.x - 0.5) < uSeam * (0.003 + 0.016 * j)) discard;
  }
  bool fr = gl_FrontFacing;
  bool outside = uSheet < 0.5 ? fr : !fr;
  vec3 N = normalize(vN) * (fr ? 1.0 : -1.0);
  vec3 V = normalize(-vV), L = normalize(vec3(-0.45, 0.55, 0.85));
  vec3 col;
  if (outside) {
    col = uSheet < 0.5 ? texture2D(uFront, uv).rgb : texture2D(uBack, vec2(1.0 - uv.x, uv.y)).rgb;
    vec2 q = uv * vec2(10.0, 22.0); float e = 0.05;
    float n0 = noise(q), nx = noise(q + vec2(e, 0.0)), ny = noise(q + vec2(0.0, e));
    N = normalize(N + vec3(n0 - nx, n0 - ny, 0.0) * 5.0);
    float diff = max(dot(N, L), 0.0);
    float spec = pow(max(dot(reflect(-L, N), V), 0.0), 28.0);
    float fres = pow(1.0 - max(dot(N, V), 0.0), 3.0);
    col = col * (0.62 + 0.5 * diff) + spec * (0.35 + uSheen) + fres * uHaloI * vec3(1.0, 0.75, 0.95) * 0.9;
  } else {
    vec2 q = uv * vec2(5.0, 9.0); float e = 0.06;
    float n0 = noise(q) + 0.25 * noise(q * 3.1);
    float nx = noise(q + vec2(e, 0.0)) + 0.25 * noise((q + vec2(e, 0.0)) * 3.1);
    float ny = noise(q + vec2(0.0, e)) + 0.25 * noise((q + vec2(0.0, e)) * 3.1);
    N = normalize(N + vec3(n0 - nx, n0 - ny, 0.0) * 6.0);
    vec3 R = reflect(-V, N);
    float env = 0.1 + 0.55 * pow(clamp(R.y * 0.5 + 0.5, 0.0, 1.0), 3.0);
    env += 0.7 * smoothstep(0.42, 0.9, noise(R.xy * 2.2 + vec2(3.1, 7.4))) + 0.25 * noise(R.xy * 6.0);
    float spec = pow(max(dot(reflect(-L, N), V), 0.0), 40.0);
    vec3 silver = vec3(0.74, 0.76, 0.82) * (0.92 + 0.08 * sin(uv.x * 220.0 + noise(uv * vec2(3.0, 40.0)) * 4.0));
    col = silver * env * (1.0 + 0.6 * uGlow) + spec * 0.9 + uGlow * vec3(1.0, 0.86, 0.97) * 0.18 * smoothstep(0.55, 1.0, uv.y);
  }
  gl_FragColor = vec4(col, uOpacity);
}`,fe={blending:Pe,blendEquation:_e,blendSrc:J,blendDst:J,blendSrcAlpha:Re,blendDstAlpha:J},ee="varying vec2 vUv; void main(){ vUv = uv; gl_Position = projectionMatrix * modelViewMatrix * vec4(position, 1.0); }",De=`
uniform vec3 uCol; uniform float uI; uniform float uSoft; varying vec2 vUv;
void main(){ vec2 p = vUv * 2.0 - 1.0; float r = length(p);
  float g = exp(-r * r * uSoft) * (1.0 - smoothstep(0.85, 1.0, r));
  gl_FragColor = vec4(uCol * g * uI, 1.0); }`,Ee=`
uniform float uI, uTime; uniform vec3 uCol; varying vec2 vUv;
void main(){
  vec2 p = vec2((vUv.x - 0.5) * 6.0, vUv.y * 7.0);
  float a = atan(p.x, p.y), r = length(p);
  float cone = smoothstep(0.78, 0.18, abs(a));
  float s = 0.5 + 0.5 * sin(a * 23.0 + uTime * 0.6) * sin(a * 37.0 - uTime * 0.45);
  s += 0.9 * pow(max(0.0, sin(a * 11.0 + 1.3 + uTime * 0.25)), 14.0);
  float fall = exp(-r * 0.42);
  float core = exp(-abs(a) * 6.0) * exp(-r * 0.9);
  float I = uI * (cone * s * fall * 0.8 + core * 1.1) * smoothstep(0.0, 0.12, r) * smoothstep(1.0, 0.7, vUv.y);
  gl_FragColor = vec4(uCol * I, 1.0);
}`,Ye=`
uniform sampler2D uMap; uniform float uBright, uOpacity; varying vec2 vUv;
void main(){
  vec2 s = vec2(${O.toFixed(4)}, ${I.toFixed(4)});
  vec2 p = (vUv - 0.5) * s; float rad = s.x * 0.07;
  vec2 d = abs(p) - (s * 0.5 - rad);
  if (length(max(d, 0.0)) - rad > 0.0) discard;
  vec2 uv = gl_FrontFacing ? vUv : vec2(1.0 - vUv.x, vUv.y);
  gl_FragColor = vec4(texture2D(uMap, uv).rgb * uBright, uOpacity);
}`;async function He(r,M={}){const m={...Ve,...M},u=new Be({canvas:r,antialias:!0,alpha:!0});u.outputColorSpace=Se,u.setClearColor(0,0);const F=new be,v=new Ae(30,16/9,.1,60),L=[],me=new Ce,W=e=>new Promise((o,s)=>me.load(e,n=>{n.anisotropy=4,L.push(n),o(n)},void 0,s)),[de,he,xe]=await Promise.all([W(m.front),W(m.back),W(m.cardBack)]),B=(e,o,s)=>{L.push(e,o);const n=new Ie(e,o);return n.renderOrder=s,n},j=e=>new E({uniforms:{uFront:{value:de},uBack:{value:he},uSheet:{value:e},uSeam:{value:0},uOpacity:{value:1},uHaloI:{value:0},uSheen:{value:0},uGlow:{value:0}},vertexShader:Ne,fragmentShader:Te,side:Y,transparent:!0}),te=(e,o,s={})=>new E({uniforms:{uCol:{value:new ue(...e)},uI:{value:0},uSoft:{value:o}},vertexShader:ee,fragmentShader:De,transparent:!0,...fe,depthWrite:!1,...s}),oe=(e,o,s,n)=>{const c=new _(y,o-e,s,n),l=c.attributes.position,i=c.attributes.uv;for(let a=0;a<l.count;a++){const f=l.getY(a)+(e+o)/2;l.setY(a,f),i.setXY(a,l.getX(a)/y+.5,(f+1)/2)}return c},h=new Fe;F.add(h);const q=B(new _(5.2,5.2),te([1,.82,.96],9),0);q.position.z=-.8,F.add(q);const ae=j(0),se=j(1);h.add(B(oe(-1,1,10,16),ae,1));const ne=B(oe(-1,A,10,12),se,3);ne.position.z=-.024,h.add(ne);const H=[],re=[],ie=[];for(const e of[-1,1]){const o=new _(y/2,1-A,10,14),s=o.attributes.position,n=o.attributes.uv;for(let i=0;i<s.count;i++){const a=s.getX(i)+e*y/4,f=s.getY(i)+(1+A)/2;s.setXYZ(i,a,f,-.024),n.setXY(i,a/y+.5,(f+1)/2)}const c=j(1);H.push(c),re.push(Float32Array.from(s.array));const l=B(o,c,4);ie.push(l),h.add(l)}const z=B(new _(6,7),new E({uniforms:{uI:{value:0},uTime:{value:0},uCol:{value:new ue(1,.9,.98)}},vertexShader:ee,fragmentShader:Ee,transparent:!0,...fe,depthWrite:!1,side:Y}),1.5);z.position.set(0,.92+3.5,-.024/2),h.add(z);const X=B(new _(y*1.1,.7),te([1,.95,1],2.2,{side:Y}),2.5);X.position.set(0,.98,-.024*.85),h.add(X);const G=[];for(let e=0;e<5;e++){const o=B(new _(O,I),new E({uniforms:{uMap:{value:xe},uBright:{value:1},uOpacity:{value:1}},vertexShader:ee,fragmentShader:Ye,transparent:!0,side:Y}),2);G.push(o),h.add(o)}const ye=(e,o,s,n,c)=>{const l=e.geometry.attributes.position,i=s*y/2;for(let a=0;a<l.count;a++){const f=o[a*3],S=o[a*3+1],k=Math.abs(f)/(y/2),U=(S-A)/(1-A),b=Math.pow(U,1.1)*(1.05-.5*k),V=f-i,D=S-A,R=-s*n*.5*b,w=V*Math.cos(R)-D*Math.sin(R),p=V*Math.sin(R)+D*Math.cos(R),d=n*1.15*b,K=Math.abs(w)*Math.sin(d)+n*.2*b*b+n*.02*Math.sin(U*9+k*5+c*2)*b;l.setXYZ(a,i+w*Math.cos(d),A+p,-.024-K)}l.needsUpdate=!0,e.geometry.computeVertexNormals()};let N=4.85;const ge=typeof matchMedia=="function"&&matchMedia("(prefers-reduced-motion: reduce)").matches,T=e=>{const s=C(g((e-t.spinA)/(t.spinB-t.spinA)))*Math.PI*3+.05*Math.sin(e*1.4),n=Math.abs(Math.sin(s)),c=C(g((e-t.spinB)/(t.pushB-t.spinB))),l=x(t.seamA,t.seamB,e),i=ze(g((e-t.seamB)/1)),a=g((e-t.peelB)/(t.riseB-t.peelB)),f=C(g(a/.62)),S=C(g((a-.55)/.45)),k=ge?0:.006*l*(1-i)*Math.sin(e*70)+.012*Math.exp(-Math.max(0,e-t.seamB)*7)*Math.sin(e*95)*(e>t.seamB?1:0),U=-1.5*x(.45,1,a),b=U+P(ve,pe,f)+.35*S,V=P(P(0,.7,c),b,C(g(a*1.1))),D=P(P(N,N*.69,c)-.07*x(t.pushB,t.seamA,e),N*.9,C(a));v.position.set(k,V+k*.6,D),v.lookAt(0,V,0),h.rotation.y=s*(1-c)+Math.PI*c+.03*Math.sin(e*.9)*c*(1-a),h.rotation.x=.04*Math.sin(e*1.1)*(1-a),h.position.y=U;const R=1-x(t.riseB-.5,t.riseB-.05,e),w=x(t.seamB-.05,t.seamB+.55,e);for(const p of[ae,se,...H])p.uniforms.uOpacity.value=R,p.uniforms.uHaloI.value=(.25+.9*n)*(1-c*.7),p.uniforms.uSheen.value=.35*Math.pow(n,2),p.uniforms.uGlow.value=w*(1-.6*x(t.peelB,t.riseB,e));for(const p of H)p.uniforms.uSeam.value=Math.max(.25*l,x(t.seamB-.05,t.seamB+.12,e));ie.forEach((p,d)=>ye(p,re[d],d===0?-1:1,Math.max(0,i),e)),q.material.uniforms.uI.value=(.55+.9*n)*(1-.75*c)+.25*w*(1-a),q.position.y=v.position.y,z.material.uniforms.uI.value=w*(1-x(t.peelB+.4,t.riseB-.2,e))*(1+.06*Math.sin(e*13)),z.material.uniforms.uTime.value=e,X.material.uniforms.uI.value=w*.4*(1-.7*x(t.peelB+.3,t.riseB,e)),G.forEach((p,d)=>{const K=g(f*1.06-d*.015),we=P(ve,pe,C(K))+.35*S-d*.006*(1-S);p.position.set((d-2)*.01*(1-f),we,-.004-d*.003-.6*S),p.rotation.z=(d-2)*.01*(1-f),p.material.uniforms.uBright.value=1+.7*w*(1-x(t.peelB+.5,t.riseB-.1,e))})},ce=()=>{const e=r.clientWidth||1,o=r.clientHeight||1;u.setPixelRatio(Math.min(window.devicePixelRatio||1,m.maxPixelRatio)),u.setSize(e,o,!1),v.aspect=e/o,v.fov=e/o<1?38:30;const s=m.centerOffset;s&&(s.x||s.y)?v.setViewOffset(e,o,-s.x,-s.y,e,o):v.clearViewOffset(),v.updateProjectionMatrix(),N=1/(Math.max(.2,m.packFill)/.982*Math.tan(ke.degToRad(v.fov)/2))};ce();const le=typeof ResizeObserver=="function"?new ResizeObserver(ce):null;le?.observe(r);const Me=()=>{const e=G[G.length-1];e.updateMatrixWorld(!0);const o=r.clientWidth,s=r.clientHeight,n=[[-O/2,-I/2],[O/2,I/2]].map(([i,a])=>new Ue(i,a,0).applyMatrix4(e.matrixWorld).project(v)),c=n.map(i=>(i.x+1)/2*o),l=n.map(i=>(1-i.y)/2*s);return{x:Math.min(...c),y:Math.min(...l),w:Math.abs(c[1]-c[0]),h:Math.abs(l[1]-l[0])}};let Z=0,$=!1;return T(0),u.render(F,v),{play:({speed:e=1,onPhase:o,isDead:s=()=>!1}={})=>new Promise(n=>{const c=performance.now();let l=0;const i=()=>{if($||s()){n(null);return}const a=(performance.now()-c)/1e3*e;for(;l<Q.length&&a>=Q[l][0];)o?.(Q[l++][1]);if(a>=t.riseB){T(t.riseB),u.render(F,v),n(Me());return}T(a),u.render(F,v),Z=requestAnimationFrame(i)};Z=requestAnimationFrame(i)}),dispose:()=>{$||($=!0,cancelAnimationFrame(Z),le?.disconnect(),L.forEach(e=>e.dispose?.()),u.dispose(),u.forceContextLoss?.())},seek:e=>{T(e),u.render(F,v)}}}export{Oe as PEEL_T,He as createPeelScene};
