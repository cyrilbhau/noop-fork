/* Round combined · the page. frames.js builds every frame as a string from model.js; this file only puts them on
   the page, draws the weekly charts from frames.js's chart data, and carries the export hook. It follows
   ../round6-scorecard/scorecard.js for the board markup, the motion and the export, so the pipeline is the same:
     ?static=1                          settled state, no motion
     ?only=B                            only frames whose id starts with B (review; not used for export)
     ?static=1&export=combined-frames.json   write the frames file for the Figma plugin (design/tools/serve.py --export)
   EVERY VALUE IS SYNTHETIC. */
(function () {
  /* Local icons (design/system/noop.js ICONS is not edited; ic('cal') resolves #i-cal). cal and pencil are copied
     from round 6; timeline is new. In the app each is an SF Symbol. */
  document.body.insertAdjacentHTML('afterbegin', `<svg width="0" height="0" style="position:absolute"><defs>
<symbol id="i-cal" viewBox="0 0 24 24"><rect x="4" y="5.5" width="16" height="15" rx="3.5" fill="none" stroke="currentColor" stroke-width="1.9"/><path d="M4 10.5h16M8.5 3.5v4M15.5 3.5v4" fill="none" stroke="currentColor" stroke-width="1.9" stroke-linecap="round"/></symbol>
<symbol id="i-pencil" viewBox="0 0 24 24"><path d="M5 19l1-4L16.5 4.5l3 3L9 18zM14.5 6.5l3 3" fill="none" stroke="currentColor" stroke-width="1.9" stroke-linecap="round" stroke-linejoin="round"/></symbol>
<symbol id="i-timeline" viewBox="0 0 24 24"><path d="M7 4.5v15M12.5 7.5h7M12.5 16.5h5" fill="none" stroke="currentColor" stroke-width="1.9" stroke-linecap="round"/><circle cx="7" cy="7.5" r="2.4" fill="currentColor"/><circle cx="7" cy="16.5" r="2.4" fill="currentColor"/></symbol>
</defs></svg>`);

  const F = window.SCF, Q = new URLSearchParams(location.search), ONLY = Q.get('only');
  const groups = F.G.map(g => ({ title: g.title, note: g.note, frames: g.frames.filter(f => !ONLY || f.name.startsWith(ONLY)) })).filter(g => g.frames.length);
  document.getElementById('boards').innerHTML = groups.map(g => `<h2 class="grp-title">${g.title}</h2><p class="grp-note">${g.note}</p><div class="board">${g.frames.map(f =>
    `<section><div class="board-title">${F.PREFIX}${f.name}</div><div class="screen${f.cls ? ' ' + f.cls : ''}" ${f.attrs || ''} style="${f.style || ''}">${f.html}</div>${f.note ? `<p class="fnote">${f.note}</p>` : ''}</section>`).join('')}</div>`).join('');

  // <svg class="wk" data-v="100,99.2,x,98.4" data-m="0,0,1,0" data-l0 data-l1 data-fs>: built from frames.js's chart data.
  function weekChart(svg, i) {
    const d = svg.dataset;
    const nodes = F.weekChartSpec({ v: d.v, m: d.m, fs: d.fs, l0: d.l0, l1: d.l1 }, +svg.getAttribute('width'), +svg.getAttribute('height'), C(d.c || '--t1'), 'sc' + i);
    const build = (n, parent) => { const e = el(n.t, n.a, parent); if (n.x != null) e.textContent = n.x; (n.k || []).forEach(k => build(k, e)); };
    nodes.forEach(n => build(n, svg));
  }
  boot(() => document.querySelectorAll('svg.wk').forEach(weekChart));
  if (!STATIC) {
    const draw = () => setTimeout(() => document.querySelectorAll('.screen:not([data-nomotion]) svg.wk').forEach(drawLine), 1150);
    draw(); const b = document.getElementById('replay'); if (b) b.addEventListener('click', draw);
  }
  const EXPORT_NAME = Q.get('export');
  if (EXPORT_NAME) window.addEventListener('load', () => setTimeout(() => exportSvgFrames(EXPORT_NAME).then(r => { document.title = `exported ${r.frames.length} frames`; }), 400));
})();
