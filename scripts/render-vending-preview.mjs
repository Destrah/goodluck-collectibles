// Documentation preview of the actual streamed YDR meshes, using the runtime hinge values.
// Requires Python/Pillow and Playwright; accepts --texture <DDS atlas>.
// PYTHON and PLAYWRIGHT_PATH can point to installed runtimes without changing project dependencies.
import fs from 'node:fs';
import path from 'node:path';
import os from 'node:os';
import zlib from 'node:zlib';
import http from 'node:http';
import { createRequire } from 'node:module';
import { execFileSync } from 'node:child_process';
import assert from 'node:assert/strict';

const root = path.resolve(import.meta.dirname, '..');
const python = process.env.PYTHON || 'python';
const require = createRequire(import.meta.url);
const { chromium } = require(process.env.PLAYWRIGHT_PATH || 'playwright');
const work = fs.mkdtempSync(path.join(os.tmpdir(), 'collectibles-vending-preview-'));
const textureIndex = process.argv.indexOf('--texture');
const texture = textureIndex >= 0 ? process.argv[textureIndex + 1] : path.join(root, 'fivem/stream/metacomics_vending_body/vending_basecolor_2048.dds');
execFileSync(python, ['-c', 'from PIL import Image;import sys;Image.open(sys.argv[1]).convert("RGB").save(sys.argv[2])', texture, path.join(work, 'atlas.png')]);

// Legacy RSC7 layouts: https://github.com/dexyfex/CodeWalker/blob/master/CodeWalker.Core/GameFiles/Resources/Drawable.cs
function resourceSize(f) {
  return (0x200 * 2 ** (f & 15)) * (((f >>> 27) & 1) + ((f >>> 26) & 1) * 2 + ((f >>> 25) & 1) * 4 + ((f >>> 24) & 1) * 8 + ((f >>> 17) & 127) * 16 + ((f >>> 11) & 63) * 32 + ((f >>> 7) & 15) * 64 + ((f >>> 5) & 3) * 128 + ((f >>> 4) & 1) * 256);
}
function mesh(name) {
  const file = fs.readFileSync(path.join(root, 'fivem/stream', `${name}.ydr`));
  assert.equal(file.subarray(0, 4).toString(), 'RSC7');
  const data = zlib.inflateRawSync(file.subarray(16));
  const systemSize = resourceSize(file.readUInt32LE(8));
  const ptr = (at) => {
    const p = Number(data.readBigUInt64LE(at));
    const offset = p >= 0x60000000 ? p - 0x60000000 + systemSize : p - 0x50000000;
    assert.ok(offset >= 0 && offset < data.length, 'Invalid resource pointer');
    return offset;
  };
  const high = ptr(0x50), models = ptr(high), output = [];
  for (let m = 0; m < data.readUInt16LE(high + 8); m++) {
    const model = ptr(models + m * 8), geometries = ptr(model + 8);
    for (let g = 0; g < data.readUInt16LE(model + 16); g++) {
      const geometry = ptr(geometries + g * 8), vb = ptr(geometry + 0x18), ib = ptr(geometry + 0x38);
      const count = data.readUInt16LE(geometry + 0x60), stride = data.readUInt16LE(vb + 8);
      const declaration = ptr(vb + 0x30);
      assert.equal(stride, 52, 'Preview expects the vending position/normal/color/UV/tangent layout');
      assert.equal(data.readUInt32LE(declaration), 0x4059);
      assert.equal(data.readBigUInt64LE(declaration + 8), 0x7755555555996996n);
      const vertices = ptr(vb + 0x10), indices = ptr(ib + 0x10);
      const position = [], normal = [], uv = [], index = [];
      for (let v = 0; v < count; v++) {
        const at = vertices + v * stride;
        for (let c = 0; c < 3; c++) {
          position.push(data.readFloatLE(at + c * 4));
          normal.push(data.readFloatLE(at + 12 + c * 4));
        }
        uv.push(data.readFloatLE(at + 28), 1 - data.readFloatLE(at + 32));
      }
      for (let i = 0; i < data.readUInt32LE(ib + 8); i++) index.push(data.readUInt16LE(indices + i * 2));
      assert.ok(index.every(i => i < count));
      output.push({ position, normal, uv, index, glass: g === 1 });
    }
  }
  return output;
}
const assets = Object.fromEntries(['body', 'door', 'racklid', 'cashlid'].map(n => [n, mesh(`metacomics_vending_${n}`)]));
const config = fs.readFileSync(path.join(root, 'fivem/config.lua'), 'utf8');
function hinge(pattern) {
  const match = config.match(pattern);
  assert.ok(match, 'Could not read runtime hinge settings');
  return match.slice(1).map(Number);
}
const main = hinge(/Hinge = vec3\(([-\d.]+), ([-\d.]+), ([-\d.]+)\), Angle = ([-\d.]+), Speed = ([-\d.]+), Direction = ([-\d.]+)/);
const cash = hinge(/CashBox[\s\S]*?LidHinge = vec3\(([-\d.]+), ([-\d.]+), ([-\d.]+)\), LidAngle = ([-\d.]+), LidDirection = ([-\d.]+)/);
const rack = hinge(/Rack = [\s\S]*?LidHinge = vec3\(([-\d.]+), ([-\d.]+), ([-\d.]+)\), LidAngle = ([-\d.]+), LidDirection = ([-\d.]+)/);
const html = `<!doctype html><html><head><meta charset="utf-8"><style>
body{margin:0;background:#101622;color:#eef3ff;font-family:Arial,sans-serif}canvas{display:block}
.title{position:absolute;top:0;left:0;right:0;padding:24px 28px 42px;background:#101622;font-size:23px;font-weight:bold}.sub{position:absolute;top:57px;left:28px;color:#95a9c7;font-size:13px}
#stage{position:absolute;bottom:62px;left:28px;font-size:19px;color:#78e0e6}.note{position:absolute;bottom:30px;left:28px;font-size:12px;color:#95a9c7}
#detail{display:none;position:absolute;right:23px;bottom:390px;color:#95a9c7;font-size:12px}
</style></head><body><div class="title">MetaComics vending machine</div><div class="sub">Main door · Server cabinet · Cashbox</div><div id="stage"></div><div id="detail">Cashbox lid detail</div><div class="note">Asset animation preview • Actual prop meshes and configured hinges</div>
<script type="module">
import * as THREE from '/three.js';
const assets=${JSON.stringify(assets)}, hinges=${JSON.stringify({main,cash,rack})};
const scene=new THREE.Scene();scene.background=new THREE.Color('#101622');
const camera=new THREE.PerspectiveCamera(36,1,0.1,50);camera.up.set(0,0,1);
const renderer=new THREE.WebGLRenderer({antialias:true});renderer.setSize(720,720);renderer.setPixelRatio(1);renderer.outputColorSpace=THREE.SRGBColorSpace;document.body.appendChild(renderer.domElement);
scene.add(new THREE.HemisphereLight(0xf4f7ff,0x525d76,2.4));
const light=new THREE.DirectionalLight(0xffffff,2.8);light.position.set(2,-4,5);scene.add(light);
const texture=await new THREE.TextureLoader().loadAsync('/atlas.png');texture.colorSpace=THREE.SRGBColorSpace;
const material=new THREE.MeshStandardMaterial({map:texture,roughness:0.7,metalness:0.12,side:THREE.DoubleSide});
const glass=new THREE.MeshStandardMaterial({color:0x9fcbd4,transparent:true,opacity:0.13,roughness:0.18,side:THREE.DoubleSide,depthWrite:false});
function add(name,at=[0,0,0]){const group=new THREE.Group();group.position.set(...at);scene.add(group);for(const asset of assets[name]){const geo=new THREE.BufferGeometry();geo.setAttribute('position',new THREE.Float32BufferAttribute(asset.position,3));geo.setAttribute('normal',new THREE.Float32BufferAttribute(asset.normal,3));geo.setAttribute('uv',new THREE.Float32BufferAttribute(asset.uv,2));geo.setIndex(asset.index);group.add(new THREE.Mesh(geo,asset.glass?glass:material));}return group;}
add('body');const door=add('door',hinges.main.slice(0,3)),rack=add('racklid',hinges.rack.slice(0,3)),cash=add('cashlid',hinges.cash.slice(0,3));
// Soft inspection lighting and a subtle edge on the dark cash lid keep its movement legible.
const fill=new THREE.PointLight(0xe7f4ff,0.8,5);fill.position.set(0.5,-0.5,-0.2);scene.add(fill);
for(const part of cash.children.slice()){cash.add(new THREE.LineSegments(new THREE.EdgesGeometry(part.geometry,30),new THREE.LineBasicMaterial({color:0x8898ad,transparent:true,opacity:0.7})));}
const detailScene=new THREE.Scene();detailScene.background=new THREE.Color('#101622');const detailLid=cash.clone();detailLid.position.set(0,0,0);detailScene.add(detailLid);detailScene.add(new THREE.HemisphereLight(0xffffff,0x8898ad,3));const detailLight=new THREE.DirectionalLight(0xffffff,3);detailLight.position.set(1,-2,3);detailScene.add(detailLight);const detailCamera=new THREE.PerspectiveCamera(36,220/180,0.01,10);detailCamera.up.set(0,0,1);detailCamera.position.set(0.5,-0.7,0.6);detailCamera.lookAt(0,-0.1,0.1);
const floor=new THREE.Mesh(new THREE.PlaneGeometry(200,200),new THREE.MeshStandardMaterial({color:0x171f2d,roughness:1}));floor.position.z=-0.955;scene.add(floor);
function ramp(t,start,end){return Math.max(0,Math.min(1,(t-start)/(end-start)));}
window.frame=(t)=>{const d=ramp(t,1,2.2)-ramp(t,10.6,11.8),r=ramp(t,3.1,4.25)-ramp(t,8.9,10),c=ramp(t,5.1,6)-ramp(t,7.2,8.1);
const close=ramp(t,4.3,5.1)-ramp(t,8.1,8.9);const zoom=close*close*(3-2*close);camera.position.set(1.5-0.7*zoom,-5.8+2.7*zoom,2.6-1.1*zoom);camera.lookAt(-0.2+0.5*zoom,0,-0.5*zoom);
door.rotation.z=THREE.MathUtils.degToRad(hinges.main[3]*hinges.main[5]*d);rack.rotation.z=THREE.MathUtils.degToRad(hinges.rack[3]*hinges.rack[4]*r);cash.rotation.x=THREE.MathUtils.degToRad(hinges.cash[3]*hinges.cash[4]*c);
document.getElementById('stage').textContent=t<1?'Machine closed':t<3.1?'Opening main door':t<5.1?'Opening server cabinet':t<7.2?'Opening cashbox':t<8.9?'Closing cashbox':t<10.6?'Closing server cabinet':t<11.8?'Closing main door':'Machine closed';renderer.setScissorTest(false);renderer.setViewport(0,0,720,720);renderer.render(scene,camera);const show=t>=5.1&&t<8.9;document.getElementById('detail').style.display=show?'block':'none';if(show){detailLid.rotation.copy(cash.rotation);renderer.setViewport(480,200,220,180);renderer.setScissor(480,200,220,180);renderer.setScissorTest(true);renderer.render(detailScene,detailCamera);}};window.frame(0);window.ready=true;
</script></body></html>`;
const server = http.createServer((req,res)=>{
  const files={'/three.js':path.join(root,'node_modules/three/build/three.module.js'),'/three.core.js':path.join(root,'node_modules/three/build/three.core.js'),'/atlas.png':path.join(work,'atlas.png')};
  if(req.url==='/'){res.setHeader('Content-Type','text/html');res.end(html);}else if(files[req.url]){res.setHeader('Content-Type',req.url.endsWith('.png')?'image/png':'text/javascript');res.end(fs.readFileSync(files[req.url]));}else{res.writeHead(404);res.end();}
});
await new Promise(resolve=>server.listen(0,'127.0.0.1',resolve));
let browser;
try{
  browser=await chromium.launch({headless:true,channel:'chrome',args:['--use-angle=swiftshader','--enable-unsafe-swiftshader']});
  const page=await browser.newPage({viewport:{width:720,height:720}});
  page.on('pageerror',error=>console.error(error));
  await page.goto(`http://127.0.0.1:${server.address().port}`);await page.waitForFunction(()=>window.ready);
  for(let i=0;i<130;i++){await page.evaluate(t=>window.frame(t),i/10);await page.screenshot({path:path.join(work,`${String(i).padStart(3,'0')}.png`)});}
  const output=path.join(root,'docs/media/vending-machine.gif');
  execFileSync(python,['-c','from PIL import Image;from pathlib import Path;import sys;frames=[Image.open(p).convert("RGB") for p in sorted(Path(sys.argv[1]).glob("[0-9]*.png"))];palette=frames[65].quantize(colors=256);frames=[im.quantize(palette=palette,dither=Image.Dither.NONE) for im in frames];frames[0].save(sys.argv[2],save_all=True,append_images=frames[1:],duration=100,loop=0,optimize=False,disposal=2)',work,output]);
  console.log(`Saved ${output}`);
  console.log(`Verification frames: ${work}`);
}finally{if(browser)await browser.close();server.close();}
