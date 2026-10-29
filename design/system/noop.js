/* NOOP mockup runtime: icons, charts, rings, ambient field and load motion.
   Pages declare intent with data attributes; build() turns them into SVG. `?static=1` renders the
   settled state with no motion (used for the Figma export). */
const NS='http://www.w3.org/2000/svg';
const STATIC=/static/.test(location.search);
if(STATIC)document.documentElement.classList.add('static');

const ICONS={
  signal:'<symbol viewBox="0 0 18 12"><rect x="0" y="8" width="3" height="4" rx="1" fill="#fff"/><rect x="5" y="5.5" width="3" height="6.5" rx="1" fill="#fff"/><rect x="10" y="3" width="3" height="9" rx="1" fill="#fff"/><rect x="15" y="0" width="3" height="12" rx="1" fill="#fff"/></symbol>',
  wifi:'<symbol viewBox="0 0 16 12"><path d="M8 11.5l2.2-2.6a3.2 3.2 0 0 0-4.4 0zM8 4.2a7 7 0 0 1 4.9 2l1.4-1.6A9.2 9.2 0 0 0 8 2a9.2 9.2 0 0 0-6.3 2.6l1.4 1.6A7 7 0 0 1 8 4.2z" fill="#fff"/></symbol>',
  batt:'<symbol viewBox="0 0 27 13"><rect x=".5" y=".5" width="23" height="12" rx="3.5" fill="none" stroke="#fff" stroke-opacity=".4"/><rect x="2" y="2" width="18" height="9" rx="2" fill="#fff"/><path d="M25 4.5v4a2 2 0 0 0 0-4z" fill="#fff" fill-opacity=".4"/></symbol>',
  'chev-l':'<symbol viewBox="0 0 24 24"><path d="M15 5l-7 7 7 7" fill="none" stroke="currentColor" stroke-width="2.2" stroke-linecap="round" stroke-linejoin="round"/></symbol>',
  'chev-r':'<symbol viewBox="0 0 24 24"><path d="M9 5l7 7-7 7" fill="none" stroke="currentColor" stroke-width="2.2" stroke-linecap="round" stroke-linejoin="round"/></symbol>',
  'chev-d':'<symbol viewBox="0 0 24 24"><path d="M6 9l6 6 6-6" fill="none" stroke="currentColor" stroke-width="2.2" stroke-linecap="round" stroke-linejoin="round"/></symbol>',
  info:'<symbol viewBox="0 0 24 24"><circle cx="12" cy="12" r="9" fill="none" stroke="currentColor" stroke-width="1.8"/><path d="M12 11v6M12 7.5v.5" stroke="currentColor" stroke-width="2" stroke-linecap="round"/></symbol>',
  plus:'<symbol viewBox="0 0 24 24"><path d="M12 5v14M5 12h14" stroke="currentColor" stroke-width="2.2" stroke-linecap="round"/></symbol>',
  x:'<symbol viewBox="0 0 24 24"><path d="M6 6l12 12M18 6L6 18" stroke="currentColor" stroke-width="2.2" stroke-linecap="round"/></symbol>',
  sliders:'<symbol viewBox="0 0 24 24"><path d="M4 8h9M17 8h3M4 16h3M11 16h9M15 5.5v5M9 13.5v5" stroke="currentColor" stroke-width="2" stroke-linecap="round"/></symbol>',
  person:'<symbol viewBox="0 0 24 24"><circle cx="12" cy="9" r="3.6" fill="none" stroke="currentColor" stroke-width="1.9"/><path d="M5.5 19.5a6.5 6.5 0 0 1 13 0" fill="none" stroke="currentColor" stroke-width="1.9" stroke-linecap="round"/></symbol>',
  today:'<symbol viewBox="0 0 24 24"><circle cx="7" cy="12" r="3.6" fill="none" stroke="currentColor" stroke-width="2"/><circle cx="17" cy="12" r="3.6" fill="none" stroke="currentColor" stroke-width="2"/><circle cx="12" cy="12" r="3.6" fill="none" stroke="currentColor" stroke-width="2"/></symbol>',
  moon:'<symbol viewBox="0 0 24 24"><path d="M19 14.5A7.5 7.5 0 0 1 9.5 5a7.5 7.5 0 1 0 9.5 9.5z" fill="none" stroke="currentColor" stroke-width="2" stroke-linejoin="round"/></symbol>',
  sun:'<symbol viewBox="0 0 24 24"><circle cx="12" cy="12" r="4" fill="none" stroke="currentColor" stroke-width="2"/><path d="M12 3v2M12 19v2M3 12h2M19 12h2M5.6 5.6l1.4 1.4M17 17l1.4 1.4M5.6 18.4L7 17M17 7l1.4-1.4" stroke="currentColor" stroke-width="2" stroke-linecap="round"/></symbol>',
  dumbbell:'<symbol viewBox="0 0 24 24"><path d="M3.5 9.5v5M7 7v10M17 7v10M20.5 9.5v5M7 12h10" stroke="currentColor" stroke-width="2.1" stroke-linecap="round"/></symbol>',
  heart:'<symbol viewBox="0 0 24 24"><path d="M12 20C12 20 4.5 15.6 4.5 10C4.5 7.6 6.4 5.8 8.6 5.8C10.1 5.8 11.3 6.6 12 7.6C12.7 6.6 13.9 5.8 15.4 5.8C17.6 5.8 19.5 7.6 19.5 10C19.5 15.6 12 20 12 20Z" fill="none" stroke="currentColor" stroke-width="2" stroke-linejoin="round"/></symbol>',
  'heart-f':'<symbol viewBox="0 0 24 24"><path d="M12 20C12 20 4.5 15.6 4.5 10C4.5 7.6 6.4 5.8 8.6 5.8C10.1 5.8 11.3 6.6 12 7.6C12.7 6.6 13.9 5.8 15.4 5.8C17.6 5.8 19.5 7.6 19.5 10C19.5 15.6 12 20 12 20Z" fill="currentColor"/></symbol>',
  spark:'<symbol viewBox="0 0 24 24"><path d="M12 3.5l1.9 5.1 5.1 1.9-5.1 1.9L12 17.5l-1.9-5.1L5 10.5l5.1-1.9zM18.5 15.5l.8 2.2 2.2.8-2.2.8-.8 2.2-.8-2.2-2.2-.8 2.2-.8z" fill="currentColor"/></symbol>',
  check:'<symbol viewBox="0 0 24 24"><circle cx="12" cy="12" r="10" fill="currentColor"/><polyline points="7.5,12.3 10.5,15.3 16.5,9" fill="none" stroke="#000" stroke-width="2.3" stroke-linecap="round" stroke-linejoin="round"/></symbol>',
  tick:'<symbol viewBox="0 0 24 24"><polyline points="5,12.5 10,17.5 19,7.5" fill="none" stroke="currentColor" stroke-width="2.4" stroke-linecap="round" stroke-linejoin="round"/></symbol>',
  warn:'<symbol viewBox="0 0 24 24"><path d="M12 4L21 19H3Z" fill="none" stroke="currentColor" stroke-width="2" stroke-linejoin="round"/><path d="M12 10v4M12 16.6v.4" stroke="currentColor" stroke-width="2.2" stroke-linecap="round"/></symbol>',
  run:'<symbol viewBox="0 0 24 24"><circle cx="14.5" cy="4.8" r="2" fill="currentColor"/><path d="M8 21l3-6 3 2.5V22M6.5 11.5l3-3.5h4l2.5 4 3 1M11 8l-1.5 6" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"/></symbol>',
  bike:'<symbol viewBox="0 0 24 24"><circle cx="6" cy="16" r="3.6" fill="none" stroke="currentColor" stroke-width="1.9"/><circle cx="18" cy="16" r="3.6" fill="none" stroke="currentColor" stroke-width="1.9"/><path d="M6 16l4-7h5l3 7M10 9l2.5 7H6M14 6h2.5" fill="none" stroke="currentColor" stroke-width="1.9" stroke-linecap="round" stroke-linejoin="round"/></symbol>',
  paste:'<symbol viewBox="0 0 24 24"><rect x="5" y="5" width="14" height="16" rx="3" fill="none" stroke="currentColor" stroke-width="1.9"/><path d="M9 3.5h6v3H9zM8.5 11h7M8.5 15h5" stroke="currentColor" stroke-width="1.9" stroke-linecap="round"/></symbol>',
  doc:'<symbol viewBox="0 0 24 24"><path d="M7 3h7l4 4v14H7z" fill="none" stroke="currentColor" stroke-width="1.9" stroke-linejoin="round"/><path d="M14 3v4h4M10 12h5M10 16h5" stroke="currentColor" stroke-width="1.9" stroke-linecap="round"/></symbol>',
  gear:'<symbol viewBox="0 0 24 24"><circle cx="12" cy="12" r="3.2" fill="none" stroke="currentColor" stroke-width="1.9"/><path d="M12 3v2.5M12 18.5V21M3 12h2.5M18.5 12H21M5.6 5.6l1.8 1.8M16.6 16.6l1.8 1.8M5.6 18.4l1.8-1.8M16.6 7.4l1.8-1.8" stroke="currentColor" stroke-width="1.9" stroke-linecap="round"/></symbol>',
  alarm:'<symbol viewBox="0 0 24 24"><circle cx="12" cy="13" r="7" fill="none" stroke="currentColor" stroke-width="1.9"/><path d="M12 9.5V13l2.5 1.8M4.5 5.5l3-2.5M19.5 5.5l-3-2.5" fill="none" stroke="currentColor" stroke-width="1.9" stroke-linecap="round" stroke-linejoin="round"/></symbol>',
  wind:'<symbol viewBox="0 0 24 24"><path d="M3 9h11a3 3 0 1 0-3-3M3 13h15a3 3 0 1 1-3 3M3 17h7" fill="none" stroke="currentColor" stroke-width="1.9" stroke-linecap="round"/></symbol>',
  bolt:'<symbol viewBox="0 0 24 24"><path d="M13 3L5 14h6l-1 7 8-11h-6z" fill="none" stroke="currentColor" stroke-width="1.9" stroke-linejoin="round"/></symbol>',
  chart:'<symbol viewBox="0 0 24 24"><path d="M4 19h16M7 16v-4M11 16V8M15 16v-6M19 16V5" stroke="currentColor" stroke-width="2" stroke-linecap="round"/></symbol>',
  trend:'<symbol viewBox="0 0 24 24"><path d="M3 17l6-6 4 4 8-8M15 7h6v6" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"/></symbol>',
  chat:'<symbol viewBox="0 0 24 24"><path d="M5 5h14a2 2 0 0 1 2 2v8a2 2 0 0 1-2 2h-8l-5 4v-4H5a2 2 0 0 1-2-2V7a2 2 0 0 1 2-2z" fill="none" stroke="currentColor" stroke-width="1.9" stroke-linejoin="round"/></symbol>',
  send:'<symbol viewBox="0 0 24 24"><path d="M12 19V5M6 11l6-6 6 6" fill="none" stroke="currentColor" stroke-width="2.4" stroke-linecap="round" stroke-linejoin="round"/></symbol>',
  mic:'<symbol viewBox="0 0 24 24"><rect x="9" y="3" width="6" height="11" rx="3" fill="none" stroke="currentColor" stroke-width="1.9"/><path d="M5.5 11a6.5 6.5 0 0 0 13 0M12 17.5V21" fill="none" stroke="currentColor" stroke-width="1.9" stroke-linecap="round"/></symbol>',
  bt:'<symbol viewBox="0 0 24 24"><path d="M7 7l10 10-5 4V3l5 4L7 17" fill="none" stroke="currentColor" stroke-width="1.9" stroke-linecap="round" stroke-linejoin="round"/></symbol>',
  folder:'<symbol viewBox="0 0 24 24"><path d="M3 7a2 2 0 0 1 2-2h4l2 2h8a2 2 0 0 1 2 2v8a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2z" fill="none" stroke="currentColor" stroke-width="1.9" stroke-linejoin="round"/></symbol>',
  strap:'<symbol viewBox="0 0 24 24"><rect x="7" y="3" width="10" height="18" rx="3" fill="none" stroke="currentColor" stroke-width="1.9"/><path d="M10 9h4M10 12h4" stroke="currentColor" stroke-width="1.9" stroke-linecap="round"/></symbol>',
  timer:'<symbol viewBox="0 0 24 24"><circle cx="12" cy="13" r="7.5" fill="none" stroke="currentColor" stroke-width="1.9"/><path d="M12 9v4.5M10 3h4" stroke="currentColor" stroke-width="1.9" stroke-linecap="round"/></symbol>',
  pause:'<symbol viewBox="0 0 24 24"><rect x="6.5" y="5" width="4" height="14" rx="1.5" fill="currentColor"/><rect x="13.5" y="5" width="4" height="14" rx="1.5" fill="currentColor"/></symbol>',
  stop:'<symbol viewBox="0 0 24 24"><rect x="6" y="6" width="12" height="12" rx="3" fill="currentColor"/></symbol>',
  play:'<symbol viewBox="0 0 24 24"><path d="M8 5.5v13l11-6.5z" fill="currentColor"/></symbol>',
  search:'<symbol viewBox="0 0 24 24"><circle cx="11" cy="11" r="6.5" fill="none" stroke="currentColor" stroke-width="2"/><path d="M16 16l4 4" stroke="currentColor" stroke-width="2" stroke-linecap="round"/></symbol>',
  grip:'<symbol viewBox="0 0 24 24"><path d="M5 9h14M5 15h14" stroke="currentColor" stroke-width="2" stroke-linecap="round"/></symbol>',
  book:'<symbol viewBox="0 0 24 24"><path d="M4 5.5A2.5 2.5 0 0 1 6.5 3H20v15H6.5A2.5 2.5 0 0 0 4 20.5zM4 20.5A2.5 2.5 0 0 1 6.5 18H20v3H6.5" fill="none" stroke="currentColor" stroke-width="1.9" stroke-linejoin="round"/></symbol>',
  flask:'<symbol viewBox="0 0 24 24"><path d="M9 3h6M10 3v6L4.5 19a1.5 1.5 0 0 0 1.3 2h12.4a1.5 1.5 0 0 0 1.3-2L14 9V3M7 15h10" fill="none" stroke="currentColor" stroke-width="1.9" stroke-linecap="round" stroke-linejoin="round"/></symbol>',
  shield:'<symbol viewBox="0 0 24 24"><path d="M12 3l7 3v6c0 4.5-3 7.5-7 9-4-1.5-7-4.5-7-9V6z" fill="none" stroke="currentColor" stroke-width="1.9" stroke-linejoin="round"/></symbol>',
  bell:'<symbol viewBox="0 0 24 24"><path d="M6 16V11a6 6 0 0 1 12 0v5l1.5 2h-15zM10 20.5a2 2 0 0 0 4 0" fill="none" stroke="currentColor" stroke-width="1.9" stroke-linejoin="round" stroke-linecap="round"/></symbol>',
  download:'<symbol viewBox="0 0 24 24"><path d="M12 4v11M7 10.5l5 5 5-5M5 20h14" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"/></symbol>',
  upload:'<symbol viewBox="0 0 24 24"><path d="M12 15V4M7 8.5l5-5 5 5M5 20h14" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"/></symbol>',
  refresh:'<symbol viewBox="0 0 24 24"><path d="M20 12a8 8 0 1 1-2.3-5.6M20 4v5h-5" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"/></symbol>',
  cup:'<symbol viewBox="0 0 24 24"><path d="M5 8h11v6a5 5 0 0 1-5 5h-1a5 5 0 0 1-5-5zM16 10h1.5a2.5 2.5 0 0 1 0 5H16M8 3v2M11 3v2" fill="none" stroke="currentColor" stroke-width="1.9" stroke-linecap="round" stroke-linejoin="round"/></symbol>',
  wine:'<symbol viewBox="0 0 24 24"><path d="M8 3h8l-.5 6a3.5 3.5 0 0 1-7 0zM12 12.5V20M8.5 20h7" fill="none" stroke="currentColor" stroke-width="1.9" stroke-linecap="round" stroke-linejoin="round"/></symbol>',
  fork:'<symbol viewBox="0 0 24 24"><path d="M7 3v7a2 2 0 0 0 2 2v9M11 3v7a2 2 0 0 1-2 2M17 3c-1.7 1-3 3.5-3 7h3v11" fill="none" stroke="currentColor" stroke-width="1.9" stroke-linecap="round" stroke-linejoin="round"/></symbol>',
  phone:'<symbol viewBox="0 0 24 24"><rect x="6.5" y="2.5" width="11" height="19" rx="2.5" fill="none" stroke="currentColor" stroke-width="1.9"/><path d="M10.5 18.5h3" stroke="currentColor" stroke-width="1.9" stroke-linecap="round"/></symbol>',
  lock:'<symbol viewBox="0 0 24 24"><rect x="5" y="10.5" width="14" height="10" rx="2.5" fill="none" stroke="currentColor" stroke-width="1.9"/><path d="M8 10.5V8a4 4 0 0 1 8 0v2.5" fill="none" stroke="currentColor" stroke-width="1.9"/></symbol>',
  link:'<symbol viewBox="0 0 24 24"><path d="M10 14a4 4 0 0 0 5.7 0l3-3a4 4 0 0 0-5.7-5.7l-1 1M14 10a4 4 0 0 0-5.7 0l-3 3a4 4 0 0 0 5.7 5.7l1-1" fill="none" stroke="currentColor" stroke-width="1.9" stroke-linecap="round"/></symbol>',
  cloud:'<symbol viewBox="0 0 24 24"><path d="M7 18h10.5a4 4 0 0 0 .4-8A6 6 0 0 0 6.3 9.5 4.3 4.3 0 0 0 7 18z" fill="none" stroke="currentColor" stroke-width="1.9" stroke-linejoin="round"/></symbol>',
  scale:'<symbol viewBox="0 0 24 24"><rect x="3.5" y="3.5" width="17" height="17" rx="4" fill="none" stroke="currentColor" stroke-width="1.9"/><path d="M8.5 9a4.5 4.5 0 0 1 7 0L12 12" fill="none" stroke="currentColor" stroke-width="1.9" stroke-linecap="round"/></symbol>',
  steps:'<symbol viewBox="0 0 24 24"><path d="M8 3c2 0 3 2.5 3 5s-1 4-3 4-3-1.5-3-4 1-5 3-5zM6 15h4v2a2 2 0 0 1-4 0zM16 7c2 0 3 2.5 3 5s-1 4-3 4-3-1.5-3-4 1-5 3-5zM14 19h4v1a2 2 0 0 1-4 0z" fill="none" stroke="currentColor" stroke-width="1.7" stroke-linejoin="round"/></symbol>',
  drop:'<symbol viewBox="0 0 24 24"><path d="M12 3s6 6.5 6 11a6 6 0 0 1-12 0c0-4.5 6-11 6-11z" fill="none" stroke="currentColor" stroke-width="1.9" stroke-linejoin="round"/></symbol>',
  lungs:'<symbol viewBox="0 0 24 24"><path d="M12 4v8M12 10l-3 2M12 10l3 2M8.5 7C5.5 7 4 12 4 16.5 4 19 5.5 20 7 20s2.5-1 2.5-3V10M15.5 7c3 0 4.5 5 4.5 9.5 0 2.5-1.5 3.5-3 3.5s-2.5-1-2.5-3V10" fill="none" stroke="currentColor" stroke-width="1.7" stroke-linecap="round" stroke-linejoin="round"/></symbol>',
  thermo:'<symbol viewBox="0 0 24 24"><path d="M10 13.5V5a2 2 0 0 1 4 0v8.5a4 4 0 1 1-4 0z" fill="none" stroke="currentColor" stroke-width="1.9" stroke-linejoin="round"/></symbol>',
  apple:'<symbol viewBox="0 0 24 24"><rect x="3" y="3" width="18" height="18" rx="5" fill="#fff"/><path d="M12 17s-4.5-2.6-4.5-6A2.5 2.5 0 0 1 12 9.6 2.5 2.5 0 0 1 16.5 11c0 3.4-4.5 6-4.5 6z" fill="#FF3B5C"/></symbol>',
};
document.body.insertAdjacentHTML('afterbegin',`<svg width="0" height="0" style="position:absolute"><defs>${Object.entries(ICONS).map(([k,v])=>v.replace('<symbol ',`<symbol id="i-${k}" `)).join('')}</defs></svg>`);
const ic=(name,size=20,style='')=>`<svg width="${size}" height="${size}" style="${style}"><use href="#i-${name}"/></svg>`;

const root=getComputedStyle(document.documentElement);
const C=v=>!v?'#F5F5F7':v.startsWith('--')?root.getPropertyValue(v).trim():v;
const el=(t,a,p)=>{const e=document.createElementNS(NS,t);for(const k in a)e.setAttribute(k,a[k]);p&&p.appendChild(e);return e};
let seed=7;const rnd=()=>(seed=(seed*16807)%2147483647)/2147483647;
let gid=0;
const hexA=(hex,a)=>{const h=hex.replace('#','');const n=parseInt(h,16);return `rgba(${n>>16&255},${n>>8&255},${n&255},${a})`};
const band=r=>r>=67?'--recovery':r>=34?'--rec-mid':'--rec-low';
const springEase=t=>t>=1?1:1-Math.exp(-7*t)*Math.cos(7*t);
const outCubic=t=>1-Math.pow(1-t,3);
function tween(ms,ease,fn,done){const t0=performance.now();const f=now=>{const t=Math.max(0,Math.min(1,(now-t0)/ms));fn(ease(t));if(t<1)requestAnimationFrame(f);else done&&done()};requestAnimationFrame(f)}

/* ---------- builders ---------- */
function statusBar(sb){sb.innerHTML=`<span>9:41</span><span class="row gap8">${ic('signal',18).replace('height="18"','height="12"')}${ic('wifi',16).replace('height="16"','height="12"')}${ic('batt',27).replace('height="27"','height="13"')}</span>`}

// <div class="ring" data-size data-p data-c data-sw data-label data-unit data-fs data-empty>
function ring(host){const d=host.dataset,s=+d.size,sw=+(d.sw||7),c=C(d.c||'--t1'),p=+d.p,r=50-sw/2-1;
  const svg=el('svg',{width:s,height:s,viewBox:'0 0 100 100'});
  if(d.empty!==undefined){el('circle',{cx:50,cy:50,r,fill:'none',stroke:'#FFFFFF','stroke-opacity':.22,'stroke-width':sw*.45,'stroke-dasharray':'3 5'},svg)}
  else{el('circle',{cx:50,cy:50,r,fill:'none',stroke:'#FFFFFF','stroke-opacity':.08,'stroke-width':sw},svg);
    el('circle',{class:'prog',cx:50,cy:50,r,fill:'none',stroke:c,'stroke-width':sw,'stroke-linecap':'round',pathLength:100,'stroke-dasharray':`${p} 100`,transform:'rotate(-90 50 50)','data-p':p},svg)}
  if(d.label!==undefined&&d.label!==''){const t=el('text',{x:50,y:50+(+d.fs||24)*.36,'text-anchor':'middle',fill:d.empty!==undefined?'#5F5F67':'#F5F5F7','font-size':d.fs||24,'font-weight':d.fw||600,'font-family':'-apple-system,system-ui'},svg);
    t.textContent=d.label;if(d.unit){const u=el('tspan',{'font-size':d.ufs||13,fill:'#9B9BA3','font-weight':400},t);u.textContent=d.unit}}
  if(d.icon){const g=el('g',{transform:'translate(36 36) scale(1.17)',color:c},svg);g.innerHTML=ICONS[d.icon].replace(/<\/?symbol[^>]*>/g,'').replace(/currentColor/g,c)}
  svg.setAttribute('style',host.getAttribute('style')||'');host.replaceWith(svg);return svg}

// Arc gauge: <svg class="arc" data-p (0..1) data-c width height data-r data-sw>
function arcGauge(svg){const d=svg.dataset,w=+svg.getAttribute('width'),h=+svg.getAttribute('height'),r=+(d.r||112),sw=+(d.sw||22),cx=w/2,cy=+(d.cy||150),p=+d.p,c=C(d.c);
  el('circle',{cx,cy,r,fill:'none',stroke:'#FFFFFF','stroke-opacity':.08,'stroke-width':sw,'stroke-linecap':'round',pathLength:100,'stroke-dasharray':'66.67 100',transform:`rotate(150 ${cx} ${cy})`,'data-p':66.67},svg);
  const id='arcg'+(gid++);const df=el('defs',{},svg);const lg=el('linearGradient',{id,x1:0,y1:1,x2:1,y2:0},df);el('stop',{offset:0,'stop-color':c,'stop-opacity':.55},lg);el('stop',{offset:1,'stop-color':c},lg);
  el('circle',{class:'prog',cx,cy,r,fill:'none',stroke:`url(#${id})`,'stroke-width':sw,'stroke-linecap':'round',pathLength:100,'stroke-dasharray':`${66.67*p} 100`,transform:`rotate(150 ${cx} ${cy})`,'data-p':66.67*p},svg);
  if(d.target){const [a,b]=d.target.split(',').map(Number);const ang=x=>(150+240*x)*Math.PI/180;
    [a,b].forEach(x=>el('line',{x1:cx+(r-sw/2-4)*Math.cos(ang(x)),y1:cy+(r-sw/2-4)*Math.sin(ang(x)),x2:cx+(r+sw/2+4)*Math.cos(ang(x)),y2:cy+(r+sw/2+4)*Math.sin(ang(x)),stroke:'#FFFFFF','stroke-width':2.5,'stroke-linecap':'round','stroke-opacity':.8},svg))}
  const a=(150+240*p)*Math.PI/180;el('circle',{cx:cx+r*Math.cos(a),cy:cy+r*Math.sin(a),r:7,fill:'#fff'},svg)}

function ringsRow(host){const s=+host.dataset.s,r=+host.dataset.r,st=+host.dataset.st,size=+(host.dataset.size||96);
  const recWord=r>=67?'Recovered':r>=34?'Adequate':'Low';
  host.style.cssText='display:grid;grid-template-columns:repeat(3,1fr);text-align:center';
  host.innerHTML=`<div><div class="ring" data-size="${size}" data-p="${s}" data-c="--sleep" data-label="${s}" data-unit="%"></div><div class="lbl" style="margin-top:8px">Sleep</div><div class="cap" style="margin-top:2px;color:var(--t2)">${s>=85?'7h 42m':s>=70?'6h 50m':'5h 31m'}</div></div>
  <div><div class="ring" data-size="${size}" data-p="${r}" data-c="${band(r)}" data-label="${r}" data-unit="%"></div><div class="lbl" style="margin-top:8px">Recovery</div><div class="cap" style="margin-top:2px;color:var(${band(r)})">${recWord}</div></div>
  <div><div class="ring" data-size="${size}" data-p="${Math.round(st/21*100)}" data-c="--strain" data-label="${st}"></div><div class="lbl" style="margin-top:8px">Strain</div><div class="cap" style="margin-top:2px;color:var(--t2)">of 21</div></div>`;
  host.querySelectorAll('.ring').forEach(ring)}

function smooth(pts){let d=`M${pts[0][0]},${pts[0][1]}`;for(let i=0;i<pts.length-1;i++){const p0=pts[i-1]||pts[i],p1=pts[i],p2=pts[i+1],p3=pts[i+2]||p2;
  d+=` C${(p1[0]+(p2[0]-p0[0])/6).toFixed(2)},${(p1[1]+(p2[1]-p0[1])/6).toFixed(2)} ${(p2[0]-(p3[0]-p1[0])/6).toFixed(2)},${(p2[1]-(p3[1]-p1[1])/6).toFixed(2)} ${p2[0]},${p2[1]}`}return d}

// <svg class="line" data-v="..." data-c data-band="lo,hi" (scale only) data-bars data-dot="i" data-zones>
function lineChart(svg){const d=svg.dataset,v=d.v.split(',').map(Number),c=C(d.c),w=+svg.getAttribute('width'),h=+svg.getAttribute('height');
  if(d.bars){const mx=Math.max(...v),bw=+(d.bw||6),g=(w-8-bw*v.length)/(v.length-1);
    const id='gb'+(gid++);const df=el('defs',{},svg);const lg=el('linearGradient',{id,x1:0,y1:0,x2:0,y2:1},df);el('stop',{offset:0,'stop-color':c},lg);el('stop',{offset:1,'stop-color':c,'stop-opacity':.25},lg);
    v.forEach((x,i)=>{const bh=Math.max(4,x/mx*(h-6));el('rect',{class:'barg',x:4+i*(bw+g),y:h-bh,width:bw,height:bh,rx:bw/2,fill:`url(#${id})`,opacity:i===v.length-1?1:.45},svg)});return}
  const bandV=d.band?d.band.split(',').map(Number):null;
  let mn=d.min!==undefined?+d.min:Math.min(...v,...(bandV||[])),mx=d.max!==undefined?+d.max:Math.max(...v,...(bandV||[]));const padT=h>50?10:6,padB=h>50?4:5;
  if(d.min===undefined){const span=(mx-mn)||1;mn-=span*.08;mx+=span*.08}
  const X=i=>4+i*(w-12)/(v.length-1),Y=x=>padT+(1-(x-mn)/(mx-mn))*(h-padT-padB);
  const pts=v.map((x,i)=>[+X(i).toFixed(2),+Y(x).toFixed(2)]);
  const id=gid++;const df=el('defs',{},svg);
  const ga=el('linearGradient',{id:'ga'+id,x1:0,y1:0,x2:0,y2:1},df);
  let strokePaint;
  if(d.zones){ // vertical heart-rate zone gradient: colour follows intensity
    const zs=['--z5','--z4','--z3','--z2','--z1'];zs.forEach((z,i)=>{el('stop',{offset:i/4,'stop-color':C(z),'stop-opacity':.38-i*.06},ga)});el('stop',{offset:1,'stop-color':C('--z1'),'stop-opacity':0},ga);
    const gz=el('linearGradient',{id:'gz'+id,x1:0,y1:0,x2:0,y2:1,gradientUnits:'userSpaceOnUse','y1':padT,'y2':h-padB},df);zs.forEach((z,i)=>el('stop',{offset:i/4,'stop-color':C(z)},gz));strokePaint=`url(#gz${id})`}
  else{el('stop',{offset:0,'stop-color':c,'stop-opacity':.42},ga);el('stop',{offset:1,'stop-color':c,'stop-opacity':0},ga);
    const gs=el('linearGradient',{id:'gs'+id,x1:0,y1:0,x2:1,y2:0},df);el('stop',{offset:0,'stop-color':c,'stop-opacity':.3},gs);el('stop',{offset:1,'stop-color':c,'stop-opacity':1},gs);strokePaint=`url(#gs${id})`}
  const line=smooth(pts);
  el('path',{class:'area',d:`${line} L${pts[pts.length-1][0]},${h} L${pts[0][0]},${h} Z`,fill:`url(#ga${id})`},svg);
  el('path',{class:'stroke',d:line,fill:'none',stroke:strokePaint,'stroke-width':h>50?2.5:2,'stroke-linecap':'round','stroke-linejoin':'round'},svg);
  const di=d.dot!==undefined?+d.dot:pts.length-1;const [lx,ly]=pts[di];
  if(d.dot!==undefined)el('line',{x1:lx,x2:lx,y1:0,y2:h,stroke:'#FFFFFF','stroke-opacity':.25,'stroke-width':1},svg);
  if(d.nodot===undefined){el('circle',{class:'halo',cx:lx,cy:ly,r:h>50?8:6,fill:d.zones?C('--z4'):c,opacity:.22},svg);
    el('circle',{class:'pt',cx:lx,cy:ly,r:h>50?4:3,fill:d.zones?C('--z4'):c,stroke:'#0B0B0D','stroke-width':1.5},svg)}}

// Bars coloured per value: <svg class="cbars" data-v data-c (single) or data-band="recovery">
function colorBars(svg){const d=svg.dataset,v=d.v.split(',').map(Number),w=+svg.getAttribute('width'),h=+svg.getAttribute('height'),n=v.length,bw=+(d.bw||7),g=(w-bw*n)/(n-1),mx=+(d.max||Math.max(...v));
  v.forEach((x,i)=>{const col=d.band==='recovery'?C(band(x)):C(d.c);const bh=Math.max(3,x/mx*h);el('rect',{class:'rb',x:i*(bw+g),y:h-bh,width:bw,height:bh,rx:bw/2,fill:col,opacity:i===n-1?1:.75},svg)})}

function tabbar(host){const on=+host.dataset.on;const items=[['today','Today'],['moon','Sleep'],['dumbbell','Training'],['heart','Health']];
  host.innerHTML=`<div class="tabs">${items.map(([i,l],k)=>`<div class="tab${k===on?' on':''}">${ic(i,24)}${l}</div>`).join('')}</div><div class="coachbtn"${host.dataset.on==='4'?' style="background:rgba(200,168,255,.22);color:var(--coach)"':''}>${ic('spark',26)}</div>`}

/* ---------- ambient field: colours and sizes come from the data ---------- */
function ambient(host,blobs,opts={}){const a=document.createElement('div');a.className='ambient';const H=opts.h||600;if(opts.h)a.style.height=H+'px';
  blobs.forEach(([c,x,y,r,alpha],i)=>{const b=document.createElement('div');b.className='blob'+(i%2?' drift':'');
    b.style.cssText=`left:${x-r}px;top:${y-r}px;width:${2*r}px;height:${2*r}px;background:radial-gradient(circle at 50% 50%,${hexA(C(c),alpha)} 0%,${hexA(C(c),alpha*.45)} 38%,${hexA(C(c),0)} 70%)`;a.appendChild(b)});
  const svg=el('svg',{width:402,height:H,viewBox:`0 0 402 ${H}`});const cx=opts.cx??330,cy=opts.cy??40;
  for(let r=48;r<640;r+=34)el('circle',{cx,cy,r,fill:'none',stroke:'#FFFFFF','stroke-opacity':.035,'stroke-width':1},svg);
  a.appendChild(svg);const f=document.createElement('div');f.className='fade';a.appendChild(f);
  host.insertBefore(a,host.firstChild)}
const todayBlobs=(s,r,st)=>{const sf=s/100,rf=r/100,tf=st/21;return[['--sleep',40,10,150+170*sf,.16+.38*sf],['--strain',380,40,150+170*tf,.16+.38*tf],[band(r),210,-30,170+190*rf,.18+.42*rf]]};

function buildAll(){
  document.querySelectorAll('.sb').forEach(statusBar);
  document.querySelectorAll('[data-ic]').forEach(n=>{n.innerHTML=ic(n.dataset.ic,+(n.dataset.s||20))+n.innerHTML});
  document.querySelectorAll('.rings').forEach(ringsRow);
  document.querySelectorAll('.ring').forEach(ring);
  document.querySelectorAll('svg.arc').forEach(arcGauge);
  document.querySelectorAll('svg.line').forEach(lineChart);
  document.querySelectorAll('svg.cbars').forEach(colorBars);
  document.querySelectorAll('.tabbar').forEach(tabbar);
  document.querySelectorAll('[data-ambient]').forEach(s=>{const v=s.dataset.ambient;const opts=s.dataset.ambh?{h:+s.dataset.ambh}:{};
    ambient(s,v.startsWith('today:')?todayBlobs(...v.slice(6).split(',').map(Number)):JSON.parse(v),opts)});
}

/* ---------- motion ---------- */
function countUp(span,ms){const tgt=+span.dataset.count,dec=+(span.dataset.dec||0),sep=span.dataset.sep;
  const fmt=x=>{const s=x.toFixed(dec);return sep?Number(s).toLocaleString('en-US',{minimumFractionDigits:dec}):s};
  tween(ms,outCubic,k=>span.textContent=fmt(tgt*k),()=>span.textContent=fmt(tgt))}
function fillRing(c,ms){const p=+c.dataset.p;tween(ms,springEase,k=>c.setAttribute('stroke-dasharray',`${Math.max(0,Math.min(99.9,p*k))} 100`))}
function drawLine(svg){const s=svg.querySelector('.stroke');if(s){const L=s.getTotalLength();s.style.strokeDasharray=L;s.style.strokeDashoffset=L;s.getBoundingClientRect();s.style.transition='stroke-dashoffset .7s cubic-bezier(.2,.8,.2,1)';s.style.strokeDashoffset=0}
  const a=svg.querySelector('.area');if(a){a.style.opacity=0;a.style.transition='opacity .5s ease .2s';requestAnimationFrame(()=>a.style.opacity=1)}
  svg.querySelectorAll('.pt,.halo').forEach(p=>{p.style.transformBox='fill-box';p.style.transformOrigin='center';p.classList.remove('pop');p.getBoundingClientRect();p.style.animationDelay='.6s';p.classList.add('pop')})}
function growBars(svg,sel,ms,stag){svg.querySelectorAll(sel).forEach((b,i)=>{b.style.transformBox='fill-box';b.style.transformOrigin='bottom';b.style.transform='scaleY(0)';b.getBoundingClientRect();b.style.transition=`transform ${ms}ms var(--spring) ${i*stag}ms`;b.style.transform='scaleY(1)'})}
function revealCard(c){
  c.querySelectorAll('circle.prog').forEach(p=>fillRing(p,1100));
  c.querySelectorAll('[data-count]').forEach(s=>countUp(s,900));
  c.querySelectorAll('svg.line').forEach(drawLine);
  (c.matches('svg')?[c]:[...c.querySelectorAll('svg')]).forEach(s=>{growBars(s,'.rb',600,18);growBars(s,'.barg',500,40);growBars(s,'.hrb',500,8)});
  c.querySelectorAll('.grow').forEach(b=>{const w=b.style.width;b.style.width='0%';b.getBoundingClientRect();b.style.transition='width .9s var(--spring)';b.style.width=w});
  c.querySelectorAll('.seg-in').forEach((s,i)=>{s.style.opacity=0;s.getBoundingClientRect();s.style.transition=`opacity .3s ease ${i*30}ms`;s.style.opacity=1});
  c.querySelectorAll('.cd').forEach((d,i)=>{d.style.transform='scale(0)';d.getBoundingClientRect();d.style.transition=`transform .45s var(--spring) ${i*6}ms`;d.style.transform='scale(1)'});
}
function play(){
  document.querySelectorAll('.screen').forEach(screen=>{if(screen.dataset.nomotion!==undefined)return;
    const units=[...screen.querySelectorAll('.card,.tile,.sec,.lt,.h1,svg.arc,.motion')].filter(u=>!u.parentElement.closest('.card,.tile,.motion'));
    units.forEach(u=>{u.classList.remove('in');u.classList.add('enter');if(u.matches('.card,.tile'))u.classList.add('sk')});
    screen.querySelectorAll('circle.prog').forEach(p=>p.setAttribute('stroke-dasharray','0 100'));
    screen.querySelectorAll('[data-count]').forEach(s=>s.textContent=s.dataset.dec?(0).toFixed(+s.dataset.dec):'0');
    const amb=screen.querySelectorAll('.ambient');amb.forEach(a=>{a.style.opacity=0;a.style.transition='none'});
    units.forEach((u,i)=>setTimeout(()=>{u.classList.add('in');u.classList.remove('enter')},60+i*40));
    setTimeout(()=>amb.forEach(a=>{a.style.transition='opacity .8s ease';a.style.opacity=1}),150);
    units.forEach((u,i)=>setTimeout(()=>{u.classList.remove('sk');revealCard(u)},750+i*60));
  })}

function boot(extra){buildAll();extra&&extra();if(!STATIC){play();const b=document.getElementById('replay');if(b)b.onclick=play}}

/* ---------- Figma export: flatten to static, self-contained HTML and post it to the local server ---------- */
async function exportForFigma(name){
  const css=await Promise.all([...document.querySelectorAll('link[rel=stylesheet]')].map(async l=>{const t=await fetch(l.href).then(r=>r.text());const s=document.createElement('style');s.textContent=t;l.replaceWith(s);return t.length}));
  const cs=getComputedStyle(document.documentElement);
  const resolve=v=>v&&v.includes('var(')?v.replace(/var\((--[\w-]+)\)/g,(_,n)=>cs.getPropertyValue(n).trim()):v;
  // Figma ignores pathLength, so dashed progress circles become explicit arcs.
  document.querySelectorAll('circle[pathLength]').forEach(c=>{const cx=+c.getAttribute('cx'),cy=+c.getAttribute('cy'),r=+c.getAttribute('r');
    const p=parseFloat(c.dataset.p??(c.getAttribute('stroke-dasharray')||'100').split(/[ ,]+/)[0]);
    const m=/rotate\(([-\d.]+)/.exec(c.getAttribute('transform')||'');const a0=(m?+m[1]:0)*Math.PI/180;
    const sweep=Math.min(p,99.9)/100*2*Math.PI,a1=a0+sweep;const pt=a=>`${(cx+r*Math.cos(a)).toFixed(2)} ${(cy+r*Math.sin(a)).toFixed(2)}`;
    const path=document.createElementNS(NS,'path');for(const at of c.attributes)if(!['cx','cy','r','pathLength','stroke-dasharray','transform','data-p','class'].includes(at.name))path.setAttribute(at.name,at.value);
    path.setAttribute('d',`M ${pt(a0)} A ${r} ${r} 0 ${sweep>Math.PI?1:0} 1 ${pt(a1)}`);path.setAttribute('fill','none');c.replaceWith(path)});
  document.querySelectorAll('svg use').forEach(u=>{const sym=document.getElementById((u.getAttribute('href')||'').slice(1)),svg=u.closest('svg');if(!sym||!svg)return;
    if(!svg.getAttribute('viewBox'))svg.setAttribute('viewBox',sym.getAttribute('viewBox'));const color=getComputedStyle(svg).color;const frag=sym.cloneNode(true);
    [...frag.querySelectorAll('*')].forEach(n=>['fill','stroke'].forEach(a=>{if(n.getAttribute(a)==='currentColor')n.setAttribute(a,color)}));u.replaceWith(...frag.childNodes)});
  document.querySelectorAll('svg [color]').forEach(g=>g.removeAttribute('color'));
  document.querySelectorAll('svg *').forEach(n=>['fill','stroke'].forEach(a=>{const v=n.getAttribute(a);if(v&&v.includes('var('))n.setAttribute(a,resolve(v))}));
  document.querySelectorAll('[style]').forEach(n=>{const s=n.getAttribute('style');if(s.includes('var('))n.setAttribute('style',resolve(s))});
  document.querySelectorAll('.drift,.beat,.breathe,.pulse').forEach(n=>n.classList.remove('drift','beat','breathe','pulse'));
  document.querySelectorAll('script,.controls').forEach(s=>s.remove());
  document.querySelector('body > svg[width="0"]')?.remove();
  const html='<!doctype html>'+document.documentElement.outerHTML;
  const n=await fetch('/save?name='+encodeURIComponent(name),{method:'POST',headers:{'Content-Type':'text/plain'},body:html}).then(r=>r.text());
  return {bytes:n,screens:document.querySelectorAll('.screen').length,css};
}

/* ---------- Figma fallback: serialise rendered frames to SVG for a local plugin's createNodeFromSvg ---------- */
// Used when the Figma MCP is unavailable. Walks each rendered .screen and emits shapes (rounded rects,
// CSS gradients, borders, ::after knobs), text lines with their real positions, and inline SVGs mapped
// into place with a transform (Figma's importer does not honour a nested SVG's viewBox).
async function exportSvgFrames(name){
  const cs0=getComputedStyle(document.documentElement);
  const resolve=v=>v&&v.includes('var(')?v.replace(/var\((--[\w-]+)\)/g,(_,n)=>cs0.getPropertyValue(n).trim()):v;
  document.querySelectorAll('svg use').forEach(u=>{const sym=document.getElementById((u.getAttribute('href')||'').slice(1)),svg=u.closest('svg');if(!sym||!svg)return;
    if(!svg.getAttribute('viewBox'))svg.setAttribute('viewBox',sym.getAttribute('viewBox'));const color=getComputedStyle(svg).color;const frag=sym.cloneNode(true);
    [...frag.querySelectorAll('*')].forEach(n=>['fill','stroke'].forEach(a=>{if(n.getAttribute(a)==='currentColor')n.setAttribute(a,color)}));u.replaceWith(...frag.childNodes)});
  document.querySelectorAll('circle[pathLength]').forEach(c=>{const cx=+c.getAttribute('cx'),cy=+c.getAttribute('cy'),r=+c.getAttribute('r');
    const p=parseFloat(c.dataset.p??(c.getAttribute('stroke-dasharray')||'100').split(/[ ,]+/)[0]);
    const m=/rotate\(([-\d.]+)/.exec(c.getAttribute('transform')||'');const a0=(m?+m[1]:0)*Math.PI/180;
    const sweep=Math.min(p,99.9)/100*2*Math.PI,a1=a0+sweep;const pt=a=>`${(cx+r*Math.cos(a)).toFixed(2)} ${(cy+r*Math.sin(a)).toFixed(2)}`;
    const path=document.createElementNS(NS,'path');for(const at of c.attributes)if(!['cx','cy','r','pathLength','stroke-dasharray','transform','data-p','class'].includes(at.name))path.setAttribute(at.name,at.value);
    path.setAttribute('d',`M ${pt(a0)} A ${r} ${r} 0 ${sweep>Math.PI?1:0} 1 ${pt(a1)}`);path.setAttribute('fill','none');c.replaceWith(path)});
  document.querySelectorAll('svg *').forEach(n=>['fill','stroke'].forEach(a=>{const v=n.getAttribute(a);if(v&&v.includes('var('))n.setAttribute(a,resolve(v))}));

  const esc=s=>s.replace(/&/g,'&amp;').replace(/</g,'&lt;').replace(/>/g,'&gt;');
  const px=v=>parseFloat(v)||0;
  const alpha=c=>{const m=/rgba?\(([^)]+)\)/.exec(c);if(!m)return c==='transparent'?0:1;const p=m[1].split(/[ ,\/]+/).filter(Boolean);return p.length>3?+p[3]:1};
  const splitTop=s=>{const out=[];let d=0,cur='';for(const ch of s){if(ch==='(')d++;if(ch===')')d--;if(ch===','&&d===0){out.push(cur.trim());cur=''}else cur+=ch}if(cur.trim())out.push(cur.trim());return out};
  const ctx=document.createElement('canvas').getContext('2d');
  const out=[];
  for(const screen of document.querySelectorAll('.screen')){
    const R=screen.getBoundingClientRect(),W=Math.round(R.width),H=Math.round(R.height);
    let defs='',body='',gid=0,groupOpacity=1;const T=[];
    const rr=(x,y,w,h,r)=>{const m=Math.min(w,h)/2;const [a,b,c,d]=r.map(v=>Math.max(0,Math.min(v,m)));
      return `M${x+a},${y}H${x+w-b}${b?`A${b},${b} 0 0 1 ${x+w},${y+b}`:''}V${y+h-c}${c?`A${c},${c} 0 0 1 ${x+w-c},${y+h}`:''}H${x+d}${d?`A${d},${d} 0 0 1 ${x},${y+h-d}`:''}V${y+a}${a?`A${a},${a} 0 0 1 ${x+a},${y}`:''}Z`};
    const radii=(cs,w,h)=>['borderTopLeftRadius','borderTopRightRadius','borderBottomRightRadius','borderBottomLeftRadius'].map(k=>{const v=cs[k];return v.endsWith('%')?parseFloat(v)/100*Math.min(w,h):px(v)});
    const stops=parts=>{const n=parts.length;return parts.map((p,i)=>{const m=/^(.*?\))\s*([\d.]+%)?$/.exec(p)||/^(\S+)\s*([\d.]+%)?$/.exec(p);const col=m?m[1]:p;const off=m&&m[2]?m[2]:`${(i/(n-1||1))*100}%`;
      const a=alpha(col);const rgb=col.replace(/rgba\(([^,]+),([^,]+),([^,]+),[^)]+\)/,'rgb($1,$2,$3)');return `<stop offset="${off}" stop-color="${col==='transparent'?'#000':rgb}" stop-opacity="${col==='transparent'?0:a}"/>`}).join('')};
    const gradient=g=>{const id=`f${out.length}g${gid++}`;let m;
      if((m=/^linear-gradient\((.*)\)$/s.exec(g))){let p=splitTop(m[1]);let ang=180;if(/deg$/.test(p[0])){ang=parseFloat(p[0]);p=p.slice(1)}else if(/^to /.test(p[0])){ang={'to right':90,'to left':270,'to top':0,'to bottom':180}[p[0]]??180;p=p.slice(1)}
        const r=ang*Math.PI/180,dx=Math.sin(r),dy=-Math.cos(r);defs+=`<linearGradient id="${id}" x1="${.5-dx/2}" y1="${.5-dy/2}" x2="${.5+dx/2}" y2="${.5+dy/2}">${stops(p)}</linearGradient>`;return id}
      if((m=/^radial-gradient\((.*)\)$/s.exec(g))){let p=splitTop(m[1]);let cx=.5,cy=.5,rx=.71,ry=.71;
        if(!/^rgb|^#|^transparent/.test(p[0])){const shape=p[0];const at=/at ([\d.]+)% ([\d.]+)%/.exec(shape);if(at){cx=+at[1]/100;cy=+at[2]/100}
          const sz=/^([\d.]+)% ([\d.]+)%/.exec(shape);if(sz){rx=+sz[1]/100;ry=+sz[2]/100}p=p.slice(1)}
        defs+=`<radialGradient id="${id}" cx="${cx}" cy="${cy}" r="${rx}" gradientTransform="translate(${cx} ${cy}) scale(1 ${ry/rx}) translate(${-cx} ${-cy})">${stops(p)}</radialGradient>`;return id}
      return null};
    const shape=(cs,x,y,w,h)=>{const d=rr(x,y,w,h,radii(cs,w,h));let s='';
      if(alpha(cs.backgroundColor)>0)s+=`<path d="${d}" fill="${cs.backgroundColor}"/>`;
      if(cs.backgroundImage&&cs.backgroundImage!=='none')for(const layer of splitTop(cs.backgroundImage).reverse()){const id=gradient(layer);if(id)s+=`<path d="${d}" fill="url(#${id})"/>`}
      const bw=px(cs.borderTopWidth);if(bw>0&&alpha(cs.borderTopColor)>0&&cs.borderTopStyle!=='none'){const di=rr(x+bw/2,y+bw/2,w-bw,h-bw,radii(cs,w,h).map(v=>Math.max(0,v-bw/2)));
        s+=`<path d="${di}" fill="none" stroke="${cs.borderTopColor}" stroke-width="${bw}"${cs.borderTopStyle==='dashed'?' stroke-dasharray="4 4"':''}/>`}
      return s};
    const textLines=(node,cs)=>{const t=node.textContent;const rg=document.createRange();const lines=[];let cur=null;
      for(let i=0;i<t.length;i++){rg.setStart(node,i);rg.setEnd(node,i+1);const r=rg.getBoundingClientRect();if(!r.width&&/\s/.test(t[i]))continue;if(!r.height)continue;
        const top=Math.round(r.top);if(!cur||Math.abs(cur.top-top)>2){cur={top,x:r.left,h:r.height,s:''};lines.push(cur)}cur.s+=t[i]}
      ctx.font=`${cs.fontWeight} ${cs.fontSize} ${cs.fontFamily}`;const mt=ctx.measureText('Hg');const asc=mt.fontBoundingBoxAscent,des=mt.fontBoundingBoxDescent;
      for(const l of lines)T.push({_owner:node.parentElement,_cx:l.x+2,_cy:l.top+l.h/2,x:+(l.x-R.left).toFixed(1),y:+(l.top-R.top).toFixed(1),h:+l.h.toFixed(1),size:px(cs.fontSize),weight:+cs.fontWeight,color:cs.color,ls:cs.letterSpacing==='normal'?0:px(cs.letterSpacing),s:l.s.replace(/\s+/g,' '),o:groupOpacity});
      return ''};
    const walk=el=>{const cs=getComputedStyle(el);if(cs.display==='none'||cs.visibility==='hidden'||+cs.opacity===0)return'';
      const saved=groupOpacity;groupOpacity*=+cs.opacity;try{return walkInner(el,cs)}finally{groupOpacity=saved}};
    const walkInner=(el,cs)=>{
      const r=el.getBoundingClientRect(),x=r.left-R.left,y=r.top-R.top,w=r.width,h=r.height;
      if(el.tagName.toLowerCase()==='svg'){const vb=(el.getAttribute('viewBox')||`0 0 ${el.getAttribute('width')||w} ${el.getAttribute('height')||h}`).split(/[ ,]+/).map(Number);
        for(const t of el.querySelectorAll('text')){const fill=t.getAttribute('fill')||'#fff';const fw=+(t.getAttribute('font-weight')||400);const sc=h/vb[3];
          const rg=document.createRange();const tn=[...t.childNodes].find(n=>n.nodeType===3&&n.textContent.trim());
          if(tn){rg.selectNodeContents(tn);const r2=rg.getBoundingClientRect();T.push({_owner:el,_cx:r2.left+r2.width/2,_cy:r2.top+r2.height/2,x:+(r2.left-R.left).toFixed(1),y:+(r2.top-R.top).toFixed(1),h:+r2.height.toFixed(1),size:+(+t.getAttribute('font-size')*sc).toFixed(2),weight:fw,color:fill,ls:0,s:tn.textContent.trim(),o:groupOpacity})}
          for(const sp of t.querySelectorAll('tspan')){const r3=sp.getBoundingClientRect();T.push({_owner:el,_cx:r3.left+r3.width/2,_cy:r3.top+r3.height/2,x:+(r3.left-R.left).toFixed(1),y:+(r3.top-R.top).toFixed(1),h:+r3.height.toFixed(1),size:+(+(sp.getAttribute('font-size')||t.getAttribute('font-size'))*sc).toFixed(2),weight:+(sp.getAttribute('font-weight')||fw),color:sp.getAttribute('fill')||fill,ls:0,s:sp.textContent.trim(),o:groupOpacity})}}
        let inner='';for(const c of el.childNodes)if(c.nodeType===1&&c.tagName.toLowerCase()!=='text')inner+=c.outerHTML;
        return `<g transform="translate(${x.toFixed(2)} ${y.toFixed(2)}) scale(${(w/vb[2]).toFixed(4)} ${(h/vb[3]).toFixed(4)}) translate(${-vb[0]} ${-vb[1]})"${+cs.opacity<1?` opacity="${cs.opacity}"`:''}>${inner}</g>`}
      let s=shape(cs,x,y,w,h);
      const af=getComputedStyle(el,'::after');if(af.content&&af.content!=='none'&&af.position==='absolute'){const ax=x+px(af.left),ay=y+px(af.top),aw=px(af.width),ah=px(af.height);if(aw&&ah)s+=shape(af,ax,ay,aw,ah)}
      let kids='';for(const c of el.childNodes){if(c.nodeType===3&&c.textContent.trim())kids+=textLines(c,cs);else if(c.nodeType===1)kids+=walk(c)}
      if(cs.overflow==='hidden'&&kids){const id=`f${out.length}c${gid++}`;defs+=`<clipPath id="${id}"><path d="${rr(x,y,w,h,radii(cs,w,h))}"/></clipPath>`;kids=`<g clip-path="url(#${id})">${kids}</g>`}
      s+=kids;return +cs.opacity<1?`<g opacity="${cs.opacity}">${s}</g>`:s};
    let inner='';for(const c of screen.childNodes){if(c.nodeType===1)inner+=walk(c);else if(c.nodeType===3&&c.textContent.trim())inner+=textLines(c,getComputedStyle(screen))}
    const scs=getComputedStyle(screen);const bg=shape(scs,0,0,W,H);
    const title=screen.closest('section')?.querySelector('.board-title')?.textContent.trim()||`Frame ${out.length+1}`;
    // Text is layered above every shape in the plugin, so drop lines that something painted later covers.
    const visible=T.filter(t=>{const hit=document.elementFromPoint(t._cx,t._cy);return !hit||hit===t._owner||t._owner.contains(hit)||hit.contains(t._owner)}).map(({_owner,_cx,_cy,...rest})=>rest);
    out.push({name:title,w:W,h:H,texts:visible,svg:`<svg xmlns="http://www.w3.org/2000/svg" width="${W}" height="${H}" viewBox="0 0 ${W} ${H}"><defs>${defs}</defs><g clip-path="url(#f${out.length}clip)">${bg}${inner}</g><clipPath id="f${out.length}clip"><rect width="${W}" height="${H}"/></clipPath></svg>`});
  }
  const json=JSON.stringify(out);
  const n=await fetch('/save?name='+encodeURIComponent(name),{method:'POST',headers:{'Content-Type':'text/plain'},body:json}).then(r=>r.text());
  return {bytes:n,frames:out.map(f=>`${f.name} ${f.w}x${f.h} ${f.svg.length}`)};
}
