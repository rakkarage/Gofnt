# ✒️ Gofnt

<!-- <!doctype html>
<html lang="en"><head><meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1, viewport-fit=cover">
<title>BMFont Workbench</title>
<style>
:root{--bg:#f6f5f2;--panel:#fff;--ink:#1d1d1b;--mut:#6b6b66;--line:#d9d7d0;--acc:#2f6fed;--on:#fff;box-sizing:border-box;padding-top:env(safe-area-inset-top,0px);padding-bottom:env(safe-area-inset-bottom,0px);color-scheme:light}
@media (prefers-color-scheme:dark){:root:not([data-theme="light"]){--bg:#141416;--panel:#1e1e22;--ink:#ececea;--mut:#9a9a94;--line:#34343a;--acc:#6b9cff;--on:#101014;color-scheme:dark}}
:root[data-theme="dark"]{--bg:#141416;--panel:#1e1e22;--ink:#ececea;--mut:#9a9a94;--line:#34343a;--acc:#6b9cff;--on:#101014;color-scheme:dark}
html{scroll-padding-top:env(safe-area-inset-top,0px)}
*{box-sizing:border-box}
body{margin:0;background:var(--bg);color:var(--ink);font:14px/1.4 system-ui,-apple-system,"Segoe UI",Roboto,sans-serif}
header{display:flex;flex-wrap:wrap;gap:10px;align-items:center;padding:12px 16px;border-bottom:1px solid var(--line);background:var(--panel)}
h1{font-size:16px;margin:0 8px 0 0}
button,select,input,textarea{font:inherit;color:var(--ink);background:var(--bg);border:1px solid var(--line);border-radius:6px;padding:5px 9px}
button{cursor:pointer}button:hover:not(:disabled){border-color:var(--acc)}button:disabled{opacity:.45;cursor:default}
button.p{background:var(--acc);color:var(--on);border-color:var(--acc)}
.app{display:grid;grid-template-columns:minmax(0,1fr) 340px;gap:14px;padding:14px 16px}
@media (max-width:860px){.app{grid-template-columns:1fr}}
.card{background:var(--panel);border:1px solid var(--line);border-radius:10px;padding:12px;margin-bottom:14px}
.card h2{font-size:12px;text-transform:uppercase;letter-spacing:.06em;color:var(--mut);margin:0 0 8px}
.scroll{overflow:auto;max-height:62vh;border:1px solid var(--line);border-radius:6px}
canvas{display:block;image-rendering:pixelated}
#atlas{cursor:crosshair}
.row{display:flex;flex-wrap:wrap;gap:8px;align-items:center;margin-bottom:8px}
.grid{display:grid;grid-template-columns:1fr 1fr;gap:8px}
.grid label{display:flex;flex-direction:column;font-size:12px;color:var(--mut);gap:2px}
.grid input{width:100%}
#pick{display:flex;flex-wrap:wrap;gap:3px;max-height:130px;overflow:auto}
#pick button{min-width:28px;padding:2px 5px;font-family:ui-monospace,Menlo,monospace}
#pick button.on{background:var(--acc);color:var(--on);border-color:var(--acc)}
#msg{color:var(--mut);font-size:13px;min-height:18px}
.drop{border:2px dashed var(--line);border-radius:10px;padding:34px;text-align:center;color:var(--mut)}
body.drag .drop,body.drag .card{outline:2px solid var(--acc)}
textarea{width:100%;resize:vertical}
.mut{color:var(--mut);font-size:12px}
</style></head>
<body>
<header>
  <h1>BMFont Workbench</h1>
  <label><button class="p" onclick="$('#file').click()">Open .fnt + .png</button></label>
  <input id="file" type="file" multiple accept=".fnt,.txt,.xml,.png" hidden>
  <button id="undo" disabled>Undo</button>
  <button id="expFnt" disabled>Save .fnt</button>
  <button id="expPng" disabled>Save .png</button>
  <button id="copy" disabled>Copy .fnt text</button>
  <span id="msg">Drop a .fnt and its .png anywhere on the page.</span>
</header>

<div id="empty" style="padding:14px 16px"><div class="drop">Drop your <b>.fnt</b> (text or XML) and the matching <b>.png</b> here, or use Open.<br><span class="mut">Everything runs locally in your browser. Nothing is uploaded.</span></div></div>

<div class="app" id="app" hidden>
  <div>
    <div class="card">
      <h2>Atlas</h2>
      <div class="row">
        <label>Zoom <input id="zoom" type="range" min="1" max="12" value="3"></label>
        <label>Background <select id="bg"><option value="checker">Checker</option><option value="dark">Dark</option><option value="light">Light</option><option value="mid">Mid grey</option></select></label>
        <span class="mut" id="dims"></span>
      </div>
      <div class="scroll"><canvas id="atlas"></canvas></div>
      <div class="mut" style="margin-top:6px">Click a glyph to select it. Drag to move its rectangle on the atlas.</div>
    </div>
    <div class="card">
      <h2>Live preview</h2>
      <div class="row"><label>Scale <select id="pvs"><option>1</option><option selected>2</option><option>3</option><option>4</option><option>6</option><option>8</option></select></label></div>
      <textarea id="txt" rows="3">The quick brown fox jumps over the lazy dog.
0123456789 !?&amp;@#$%</textarea>
      <div class="scroll" style="margin-top:8px"><canvas id="pv"></canvas></div>
    </div>
  </div>

  <div>
    <div class="card">
      <h2>Glyph <span id="gname" style="text-transform:none;letter-spacing:0"></span></h2>
      <div class="grid" id="fields"></div>
      <div class="mut" style="margin-top:6px" id="hint">Select a glyph to edit it.</div>
    </div>
    <div class="card"><h2>Pick glyph</h2><div id="pick"></div></div>
    <div class="card">
      <h2>Font</h2>
      <div class="grid">
        <label>lineHeight <input type="number" id="lineHeight"></label>
        <label>base <input type="number" id="base"></label>
      </div>
      <div class="row" style="margin-top:10px"><select id="bf"><option>xadvance</option><option>xoffset</option><option>yoffset</option></select>
        <span>all glyphs</span><button id="dec">−1</button><button id="inc">+1</button></div>
      <div class="mut">Adjust spacing or vertical position for every glyph at once.</div>
    </div>
    <div class="card">
      <h2>Repack / optimize</h2>
      <div class="row"><label>Padding <input type="number" id="pad" value="1" min="0" max="8" style="width:60px"></label>
        <label style="display:flex;gap:6px;align-items:center"><input type="checkbox" id="p2"> Power-of-two size</label><button class="p" id="repack">Repack atlas</button></div>
      <div class="mut">Shelf-packs every glyph into the smallest texture that fits (tick power-of-two if your target needs it), and rewrites all glyph positions. Undo restores the original.</div>
      <div id="rpt" class="mut" style="margin-top:6px"></div>
    </div>
  </div>
</div>

<script>
const $=s=>document.querySelector(s);
let M=null,atlas=null,sel=null,hist=[],pngName='font.png',pendingFnt=null,pendingImg=null,dl=null;
const KEYS=['x','y','width','height','xoffset','yoffset','xadvance'];
const num=v=>/^-?\d+$/.test(v)?+v:v;
const msg=t=>{$('#msg').textContent=t};

if(window.claude&&claude.use){claude.use('downloads').then(d=>{dl=d}).catch(()=>{})}

/* ---------- parsing ---------- */
function add(m,k,o){
  for(const key in o){ if(!(k==='info'&&(key==='face'||key==='charset'))&&!(k==='page'&&key==='file')) o[key]=num(o[key]); }
  if(k==='info')m.info=o;else if(k==='common')m.common=o;else if(k==='page')m.pages.push(o);
  else if(k==='char'){delete o.letter;m.chars.set(o.id,o)}else if(k==='kerning')m.kernings.push(o);
}
function parseFnt(t){
  const m={info:{},common:{},pages:[],chars:new Map(),kernings:[]};
  if(/^\s*<\?xml|^\s*<font/i.test(t)){
    const d=new DOMParser().parseFromString(t,'text/xml');
    for(const k of ['info','common','page','char','kerning']) d.querySelectorAll(k).forEach(e=>{const o={};for(const a of e.attributes)o[a.name]=a.value;add(m,k,o)});
  }else{
    for(const line of t.split(/\r?\n/)){
      const w=line.match(/^\s*(\w+)/);if(!w)continue;
      const k=w[1];if(!['info','common','page','char','kerning'].includes(k))continue;
      const o={};for(const mm of line.matchAll(/(\w+)=("[^"]*"|\S*)/g)){let v=mm[2];if(v.length>1&&v[0]==='"')v=v.slice(1,-1);o[mm[1]]=v}
      add(m,k,o);
    }
  }
  if(!m.chars.size)throw new Error('No glyphs found in that .fnt file');
  return m;
}
function serialize(){
  const q=(o,qs)=>Object.entries(o).map(([k,v])=>k+'='+(qs.includes(k)?'"'+v+'"':v)).join(' ');
  let s='info '+q(M.info,['face','charset'])+'\ncommon '+q(M.common,[])+'\n';
  M.pages.forEach(p=>s+='page '+q(p,['file'])+'\n');
  const cs=[...M.chars.values()].sort((a,b)=>a.id-b.id);
  s+='chars count='+cs.length+'\n';
  cs.forEach(c=>{s+='char '+q(c,[])+' letter="'+(c.id===32?'space':String.fromCodePoint(c.id))+'"\n'});
  if(M.kernings.length){s+='kernings count='+M.kernings.length+'\n';M.kernings.forEach(k=>{s+='kerning '+q(k,[])+'\n'})}
  return s;
}

/* ---------- loading ---------- */
async function loadFiles(files){
  for(const f of files){
    try{
      if(/\.png$/i.test(f.name)||f.type==='image/png'){
        const bmp=await createImageBitmap(f);const c=document.createElement('canvas');c.width=bmp.width;c.height=bmp.height;
        c.getContext('2d').drawImage(bmp,0,0);pendingImg=c;pngName=f.name;
      }else pendingFnt=parseFnt(await f.text());
    }catch(e){msg('Could not read '+f.name+': '+e.message);return}
  }
  if(pendingFnt&&pendingImg){M=pendingFnt;atlas=pendingImg;pendingFnt=pendingImg=null;hist=[];sel=null;init()}
  else msg(pendingFnt?'Got the .fnt. Now add its .png.':'Got the .png. Now add its .fnt.');
}
$('#file').onchange=e=>loadFiles([...e.target.files]);
addEventListener('dragover',e=>{e.preventDefault();document.body.classList.add('drag')});
addEventListener('dragleave',()=>document.body.classList.remove('drag'));
addEventListener('drop',e=>{e.preventDefault();document.body.classList.remove('drag');loadFiles([...e.dataTransfer.files])});

/* ---------- history ---------- */
const snapJ=()=>JSON.stringify({...M,chars:[...M.chars.values()]});
function snap(){if(!M)return;const j=snapJ(),t=hist[hist.length-1];if(t&&t.j===j&&t.a===atlas)return;hist.push({j,a:atlas});if(hist.length>100)hist.shift();$('#undo').disabled=false}
function undo(){
  const h=hist.pop();if(!h)return;
  const o=JSON.parse(h.j);o.chars=new Map(o.chars.map(c=>[c.id,c]));M=o;atlas=h.a;
  $('#undo').disabled=!hist.length;refresh(true);
}
$('#undo').onclick=undo;
addEventListener('keydown',e=>{if((e.ctrlKey||e.metaKey)&&e.key==='z'&&!/INPUT|TEXTAREA/.test(document.activeElement.tagName)){e.preventDefault();undo()}});

/* ---------- drawing ---------- */
let pat=null;
function fillBg(x,w,h){
  const b=$('#bg').value;
  if(b==='checker'){
    if(!pat){const t=document.createElement('canvas');t.width=t.height=16;const g=t.getContext('2d');g.fillStyle='#8a8a8a';g.fillRect(0,0,16,16);g.fillStyle='#9a9a9a';g.fillRect(0,0,8,8);g.fillRect(8,8,8,8);pat=x.createPattern(t,'repeat')}
    x.fillStyle=pat;
  }else x.fillStyle={dark:'#111',light:'#f4f4f4',mid:'#777'}[b];
  x.fillRect(0,0,w,h);
}
function drawAtlas(){
  const c=$('#atlas'),z=+$('#zoom').value,W=atlas.width,H=atlas.height;
  c.width=W*z;c.height=H*z;const x=c.getContext('2d');x.imageSmoothingEnabled=false;
  fillBg(x,c.width,c.height);x.drawImage(atlas,0,0,c.width,c.height);
  x.lineWidth=1;
  for(const g of M.chars.values()){
    if(!g.width||!g.height)continue;
    x.strokeStyle=g.id===sel?'#ff3b30':'rgba(60,130,255,.85)';
    x.strokeRect(g.x*z+.5,g.y*z+.5,g.width*z-1,g.height*z-1);
  }
  $('#dims').textContent=W+'×'+H+' px, '+M.chars.size+' glyphs';
}
function drawPreview(){
  const c=$('#pv'),s=+$('#pvs').value,lh=+M.common.lineHeight||12,m=4;
  const kern=new Map(M.kernings.map(k=>[k.first+','+k.second,k.amount]));
  let W=1;
  const lines=$('#txt').value.split('\n').map(l=>{
    let x=0,pl=null;const a=[];
    for(const ch of l){const id=ch.codePointAt(0),G=M.chars.get(id)||M.chars.get(63);if(!G)continue;if(pl!=null)x+=kern.get(pl+','+id)||0;a.push([G,x]);x+=G.xadvance;pl=id}
    W=Math.max(W,x);return a});
  c.width=Math.min(8000,(W+2*m)*s);c.height=Math.min(4000,(lines.length*lh+2*m)*s);
  const x=c.getContext('2d');x.imageSmoothingEnabled=false;fillBg(x,c.width,c.height);
  lines.forEach((a,li)=>a.forEach(([G,gx])=>{if(G.width&&G.height)x.drawImage(atlas,G.x,G.y,G.width,G.height,(m+gx+G.xoffset)*s,(m+li*lh+G.yoffset)*s,G.width*s,G.height*s)}));
}
const ch=id=>id===32?'␣':String.fromCodePoint(id);
function fillFields(){
  const g=M.chars.get(sel);
  KEYS.forEach(k=>{const e=$('#f_'+k);e.disabled=!g;e.value=g?g[k]:''});
  $('#gname').textContent=g?'“'+(g.id===32?'space':ch(g.id))+'” (id '+g.id+')':'';
  $('#hint').style.display=g?'none':'';
  document.querySelectorAll('#pick button').forEach(b=>b.classList.toggle('on',+b.dataset.id===sel));
}
function refresh(full){
  $('#lineHeight').value=M.common.lineHeight;$('#base').value=M.common.base;
  drawAtlas();drawPreview();fillFields();
}

/* ---------- init UI ---------- */
function init(){
  $('#empty').hidden=true;$('#app').hidden=false;
  ['expFnt','expPng','copy'].forEach(i=>$('#'+i).disabled=false);
  $('#undo').disabled=true;$('#rpt').textContent='';
  if(!$('#f_x')){
    $('#fields').innerHTML=KEYS.map(k=>`<label>${k}<input type="number" id="f_${k}"></label>`).join('');
    KEYS.forEach(k=>{const e=$('#f_'+k);e.onfocus=snap;e.oninput=()=>{const g=M.chars.get(sel);if(!g)return;g[k]=parseInt(e.value)||0;drawAtlas();drawPreview()}});
  }
  $('#zoom').value=Math.max(1,Math.min(8,Math.floor(560/atlas.width)));
  $('#pick').innerHTML='';
  [...M.chars.values()].sort((a,b)=>a.id-b.id).forEach(g=>{const b=document.createElement('button');b.textContent=ch(g.id);b.dataset.id=g.id;b.onclick=()=>{sel=g.id;fillFields();drawAtlas()};$('#pick').appendChild(b)});
  refresh();
  msg('Loaded '+(M.info.face||'font')+'.');
}
['zoom','bg'].forEach(i=>$('#'+i).oninput=()=>{pat=null;drawAtlas();drawPreview()});
$('#pvs').oninput=drawPreview;$('#txt').oninput=drawPreview;
['lineHeight','base'].forEach(k=>{const e=$('#'+k);e.onfocus=snap;e.oninput=()=>{M.common[k]=parseInt(e.value)||0;drawPreview()}});

/* ---------- atlas pointer: select + drag ---------- */
let drag=null;
$('#atlas').onpointerdown=e=>{
  const z=+$('#zoom').value,px=e.offsetX/z,py=e.offsetY/z;let best=null,ba=1e12;
  for(const g of M.chars.values()){if(px>=g.x&&px<g.x+g.width&&py>=g.y&&py<g.y+g.height&&g.width*g.height<ba){best=g;ba=g.width*g.height}}
  sel=best?best.id:null;fillFields();drawAtlas();
  if(best){drag={g:best,sx:e.clientX,sy:e.clientY,ox:best.x,oy:best.y,moved:false};e.target.setPointerCapture(e.pointerId)}
};
$('#atlas').onpointermove=e=>{
  if(!drag)return;const z=+$('#zoom').value,g=drag.g;
  const dx=Math.round((e.clientX-drag.sx)/z),dy=Math.round((e.clientY-drag.sy)/z);
  if(!drag.moved&&(dx||dy)){drag.moved=true;const nx=g.x,ny=g.y;g.x=drag.ox;g.y=drag.oy;snap();g.x=nx;g.y=ny}
  if(!drag.moved)return;
  g.x=Math.max(0,Math.min(atlas.width-g.width,drag.ox+dx));g.y=Math.max(0,Math.min(atlas.height-g.height,drag.oy+dy));
  fillFields();drawAtlas();drawPreview();
};
$('#atlas').onpointerup=()=>{drag=null};

/* ---------- bulk adjust ---------- */
const bulk=d=>{snap();const k=$('#bf').value;M.chars.forEach(g=>{g[k]+=d});refresh()};
$('#inc').onclick=()=>bulk(1);$('#dec').onclick=()=>bulk(-1);

/* ---------- repack ---------- */
$('#repack').onclick=()=>{
  const pad=Math.max(0,parseInt($('#pad').value)||0),old=atlas,oldW=old.width,oldH=old.height;
  const gs=[...M.chars.values()].filter(g=>g.width>0&&g.height>0).sort((a,b)=>b.height-a.height||b.width-a.width);
  const tryPack=(W,H)=>{
    let x=pad,y=pad,rh=0;const pos=[];
    for(const g of gs){
      if(g.width+2*pad>W)return null;
      if(x+g.width+pad>W){x=pad;y+=rh+pad;rh=0}
      if(y+g.height+pad>H)return null;
      pos.push([g,x,y]);x+=g.width+pad;rh=Math.max(rh,g.height);
    }
    return pos;
  };
  const sizes=[];
  if($('#p2').checked){for(let w=16;w<=4096;w*=2)for(let h=16;h<=w;h*=2)sizes.push([w,h])}
  else{const mw=Math.max(...gs.map(g=>g.width))+2*pad;for(let w=mw;w<=2048;w++){const p=tryPack(w,1e6);if(p)sizes.push([w,Math.max(...p.map(([g,,y])=>y+g.height))+pad])}}
  sizes.sort((a,b)=>a[0]*a[1]-b[0]*b[1]||a[0]-b[0]);
  for(const [W,H] of sizes){
    const pos=tryPack(W,H);if(!pos)continue;
    snap();
    const nc=document.createElement('canvas');nc.width=W;nc.height=H;const x=nc.getContext('2d');
    for(const [g,nx,ny] of pos){x.drawImage(old,g.x,g.y,g.width,g.height,nx,ny,g.width,g.height);g.x=nx;g.y=ny}
    M.chars.forEach(g=>{if(!(g.width>0&&g.height>0)){g.x=0;g.y=0}});
    M.common.scaleW=W;M.common.scaleH=H;M.common.pages=1;atlas=nc;
    const r=Math.round(100*(1-W*H/(oldW*oldH)));$('#rpt').textContent=oldW+'×'+oldH+' → '+W+'×'+H+' ('+(r>=0?r+'% smaller':(-r)+'% larger')+' by area).'+(r<0?' Try unticking power-of-two, or undo.':'');
    refresh();$('#zoom').value=Math.max(1,Math.min(8,Math.floor(560/W)));drawAtlas();return;
  }
  $('#rpt').textContent='Glyphs don’t fit in 4096×4096. Try less padding.';
};

/* ---------- export ---------- */
const base=()=>(M.pages[0]&&String(M.pages[0].file).replace(/\.png$/i,''))||M.info.face||'font';
async function save(filename,data,label){
  if(!dl){msg('Saving files isn’t available in this view. Use “Copy .fnt text” for the font file.');return}
  try{await dl.save({filename,data});msg('Saved '+label+'.')}catch(e){msg(e&&e.code==='declined'?'Save cancelled.':'Could not save: '+(e&&e.message||e))}
}
$('#expFnt').onclick=()=>{
  if(M.pages[0])M.pages[0].file=base()+'.png';
  save(base()+'.fnt.txt',serialize(),'the .fnt text. Rename it to .fnt after downloading (the extension is restricted here)');
};
$('#expPng').onclick=()=>atlas.toBlob(b=>save(base()+'.png',b,'the atlas PNG'),'image/png');
$('#copy').onclick=async()=>{
  try{await navigator.clipboard.writeText(serialize());msg('Copied the .fnt text to your clipboard.')}
  catch{const t=document.createElement('textarea');t.value=serialize();document.body.appendChild(t);t.select();
    try{document.execCommand('copy');msg('Copied the .fnt text to your clipboard.')}catch{msg('Clipboard is blocked here.')}t.remove()}
};
</script>
</body></html> -->
