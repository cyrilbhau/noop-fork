/* Round S3 · Protein and intake (Stage 3). Page runtime: mounts the frames that frames.js built, draws the
   28-day chart, and offers the same export hook as round 6. All content comes from frames.js. */

/* local icons (noop.js ICONS is not edited; ic('cal') resolves #i-cal). Same drawings as round 6. */
document.body.insertAdjacentHTML('afterbegin', `<svg width="0" height="0" style="position:absolute"><defs>
<symbol id="i-cal" viewBox="0 0 24 24"><rect x="4" y="5.5" width="16" height="15" rx="3.5" fill="none" stroke="currentColor" stroke-width="1.9"/><path d="M4 10.5h16M8.5 3.5v4M15.5 3.5v4" fill="none" stroke="currentColor" stroke-width="1.9" stroke-linecap="round"/></symbol>
<symbol id="i-trash" viewBox="0 0 24 24"><path d="M5 7h14M10 4h4M7 7l1 12.5h8L17 7M10.5 11v5M13.5 11v5" fill="none" stroke="currentColor" stroke-width="1.9" stroke-linecap="round" stroke-linejoin="round"/></symbol>
</defs></svg>`);

/* 28-day chart: a smooth line with a gradient area fill, one point per measured day. No rule, band or
   floor line. A day that was not measured breaks the line and leaves a quiet open mark on the time axis.
   <svg class="dc" data-v="120,x,80" data-m="1,x,0" data-l0 data-l1 data-fs>   m: 1 at or above the floor,
   0 below it, n no floor set, x not measured. Adapted from round 6's weekChart. */
function dayChart(svg) {
  const ds = svg.dataset, v = ds.v.split(',').map(x => x === 'x' ? null : +x), m = ds.m.split(','), c = C(ds.c || '--t1');
  const fs = +(ds.fs || 11), w = +svg.getAttribute('width'), H = +svg.getAttribute('height'), h = H - fs - 11, n = v.length;
  const real = v.filter(x => x !== null); let mn = Math.min(...real), mx = Math.max(...real); const span = (mx - mn) || 1; mn -= span * .14; mx += span * .14;
  const X = i => +(8 + i * (w - 16) / Math.max(1, n - 1)).toFixed(2), Y = x => +(12 + (1 - (x - mn) / (mx - mn)) * (h - 20)).toFixed(2);
  const id = 'dc' + (gid++), df = el('defs', {}, svg);
  const ga = el('linearGradient', { id: 'a' + id, x1: 0, y1: 12, x2: 0, y2: h, gradientUnits: 'userSpaceOnUse' }, df); el('stop', { offset: 0, 'stop-color': c, 'stop-opacity': .28 }, ga); el('stop', { offset: 1, 'stop-color': c, 'stop-opacity': 0 }, ga);
  const gs = el('linearGradient', { id: 's' + id, x1: 0, y1: 0, x2: w, y2: 0, gradientUnits: 'userSpaceOnUse' }, df); el('stop', { offset: 0, 'stop-color': c, 'stop-opacity': .35 }, gs); el('stop', { offset: 1, 'stop-color': c, 'stop-opacity': 1 }, gs);
  const runs = []; let cur = null;
  v.forEach((x, i) => { if (x === null) { cur = null; return; } if (!cur) runs.push(cur = []); cur.push([X(i), Y(x), m[i]]); });
  runs.forEach(pts => { if (pts.length < 2) return; const line = smooth(pts), a = pts[0], b = pts[pts.length - 1];
    el('path', { class: 'area', d: `${line} L${b[0]},${h} L${a[0]},${h} Z`, fill: `url(#a${id})` }, svg);
    el('path', { class: 'stroke', d: line, fill: 'none', stroke: `url(#s${id})`, 'stroke-width': 2.5, 'stroke-linecap': 'round', 'stroke-linejoin': 'round' }, svg); });
  const all = runs.flat(), hole = C('--card-solid');
  all.forEach((p, i) => { const last = i === all.length - 1, r = p[2] === 'n' ? 1.9 : last ? 3.6 : 2.6;
    if (last) el('circle', { class: 'halo', cx: p[0], cy: p[1], r: 8, fill: c, opacity: .22 }, svg);
    if (p[2] === '0') el('circle', { class: 'pt', cx: p[0], cy: p[1], r, fill: hole, stroke: c, 'stroke-width': 1.5 }, svg);
    else el('circle', { class: 'pt', cx: p[0], cy: p[1], r, fill: c, stroke: '#0B0B0D', 'stroke-width': 1.2 }, svg); });
  // A day with no figure, after the first measured day: a quiet open mark on the time axis. Days before the
  // first figure carry no mark (nothing was being recorded yet).
  const first = v.findIndex(x => x !== null);
  v.forEach((x, i) => { if (x === null && i > first) el('circle', { cx: X(i), cy: h + 3, r: 1.8, fill: 'none', stroke: '#FFFFFF', 'stroke-opacity': .4, 'stroke-width': 1.1 }, svg); });
  const text = (x, s, anchor) => { const t = el('text', { x, y: H - 3, 'text-anchor': anchor, fill: '#9B9BA3', 'font-size': fs, 'font-weight': 500, 'font-family': '-apple-system,system-ui' }, svg); t.textContent = s; };
  if (ds.l0) text(X(0) - 4, ds.l0, 'start');
  if (ds.l1 && n > 1) text(X(n - 1) + 4, ds.l1, 'end');
}

/* mount. ?only=B (or ?only=B1) shows just the frames whose id starts with that text; not used for export. */
(() => {
  const G = IntakeFrames.G.map(g => ({ ...g, frames: g.frames.slice() }));
  const ONLY = new URLSearchParams(location.search).get('only');
  if (ONLY) { G.forEach(g => { g.frames = g.frames.filter(f => f.name.startsWith(ONLY)); }); for (let i = G.length - 1; i >= 0; i--) if (!G[i].frames.length) G.splice(i, 1); }
  document.getElementById('boards').innerHTML = G.map(g => `<h2 class="grp-title">${g.title}</h2><p class="grp-note">${g.note}</p><div class="board">${g.frames.map(f =>
    `<section><div class="board-title">${IntakeFrames.PREFIX}${f.name}</div><div class="screen${f.cls ? ' ' + f.cls : ''}" ${f.attrs || ''} data-clock="${f.clock}" style="${f.style || ''}">${f.html}</div>${f.note ? `<p class="fnote">${f.note}</p>` : ''}</section>`).join('')}</div>`).join('');
})();

boot(() => {
  document.querySelectorAll('svg.dc').forEach(dayChart);
  // noop.js prints 9:41 in every status bar. Each frame has a stated "now"; show that instead, so the
  // status bar and the read times in the frame are one clock.
  document.querySelectorAll('.screen[data-clock]').forEach(s => s.querySelectorAll('.sb > span:first-child').forEach(n => { n.textContent = s.dataset.clock; }));
});
if (!STATIC) {
  const draw = () => setTimeout(() => document.querySelectorAll('.screen:not([data-nomotion]) svg.dc').forEach(drawLine), 1150);
  draw(); document.getElementById('replay').addEventListener('click', draw);
}
// ?static=1&export=s3-frames.json: write the frames file for the Figma plugin (design/tools/serve.py --export).
const EXPORT_NAME = new URLSearchParams(location.search).get('export');
if (EXPORT_NAME) window.addEventListener('load', () => setTimeout(() => exportSvgFrames(EXPORT_NAME).then(r => { document.title = `exported ${r.frames.length} frames`; }), 400));
