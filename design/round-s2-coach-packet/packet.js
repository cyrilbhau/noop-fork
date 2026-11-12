/* Round S2 · Coach packet (Stage 2). Browser glue only: it puts the frames of frames.js on the page, lets
   noop.js build icons and chrome, fits each preview to its viewport, and offers the export hook.
   All content, strings and numbers come from frames.js and model.js. */
(() => {
  const Q = new URLSearchParams(location.search);
  // ?only=B (or ?only=B2) shows just the frames whose id starts with that text. Handy for review; not used for export.
  const ONLY = Q.get('only');
  const groups = S2Frames.groups.map(g => ({ ...g, frames: g.frames.filter(f => !ONLY || f.id.startsWith(ONLY)) })).filter(g => g.frames.length);
  document.getElementById('boards').innerHTML = groups.map(g => `<h2 class="grp-title">${g.title}</h2><p class="grp-note">${g.note}</p><div class="board">${g.frames.map(f =>
    `<section><div class="board-title">S2 / ${f.name}</div><div class="screen${f.cls ? ' ' + f.cls : ''}" ${f.attrs || ''} style="${f.style || ''}">${f.html}</div>${f.note ? `<p class="fnote">${f.note}</p>` : ''}</section>`).join('')}</div>`).join('');

  /* The preview is a scroll viewport. The export walks every character that exists, clipped or not, so the
     lines and characters outside the viewport are removed here, measured, never guessed. The full text of
     each preview stays in frames.js (S2Frames.PREVIEWS) and in group R. */
  function fitPreview(pv) {
    if (pv.classList.contains('full') || !pv.querySelector('.pl')) return;
    const cs = getComputedStyle(pv), c = document.createElement('canvas').getContext('2d');
    c.font = `${cs.fontWeight} ${cs.fontSize} ${cs.fontFamily}`;
    const cw = c.measureText('0'.repeat(40)).width / 40, inner = pv.clientWidth - parseFloat(cs.paddingLeft) - parseFloat(cs.paddingRight);
    if (!pv.classList.contains('wrap') && cw > 0) pv.querySelectorAll('.pl').forEach(l => {
      const cap = Math.max(0, Math.floor(inner / cw) - (l.classList.contains('in') ? 2 : 0));
      if (l.textContent.length > cap) l.textContent = l.textContent.slice(0, cap); });
    while (pv.lastElementChild && pv.scrollHeight > pv.clientHeight + 1) pv.lastElementChild.remove();
  }

  boot(() => {
    // One clock per frame: the status bar shows the time the packet in that frame was generated.
    document.querySelectorAll('.sb[data-t]').forEach(s => { if (s.firstElementChild) s.firstElementChild.textContent = s.dataset.t; });
    document.querySelectorAll('.pv').forEach(fitPreview);
  });

  // ?static=1&export=s2-frames.json: write the frames file for the Figma plugin (design/tools/serve.py --export).
  const EXPORT_NAME = Q.get('export');
  if (EXPORT_NAME) window.addEventListener('load', () => setTimeout(() => exportSvgFrames(EXPORT_NAME).then(r => { document.title = `exported ${r.frames.length} frames`; }), 400));
})();
