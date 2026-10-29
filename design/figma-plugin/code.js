// Local development plugin for the NOOP redesign file (import with Plugins > Development > Import plugin
// from manifest). It works without the Figma MCP, which the Starter plan rate-limits.
//
//  import  Builds frames from design/round4 (import5: design/round5) via the local preview server: the
//          page's exportSvgFrames() writes export/r4-frames.json (r5-frames.json), the hidden UI fetches it, and each frame is
//          created with createNodeFromSvg on the "Round 4 · System surfaces" page (replacing same-named
//          frames, so it is safe to re-run).
//  repair  Fixes html_to_figma ring imports (see repairRings). Safe to re-run.
//  align   Moves section titles onto the 16px gutter (see alignSectionTitles). Safe to re-run.

// html_to_figma draws an SVG ring's contents in viewBox units, so a 230px ring renders ~100px in a
// corner and a 46px ring overflows. Scale the contents back into the frame and centre them; a ring
// that already fits is left alone.
async function repairRings() {
  let fixed = 0;
  for (const page of figma.root.children) {
    await page.loadAsync();
    if (!page.name.startsWith('Round 3')) continue;
    const rings = page.findAll(n => {
      if (n.type !== 'FRAME' || !n.children || !n.children.length) return false;
      const b = n.absoluteBoundingBox;
      if (!b || Math.abs(b.width - b.height) > 2 || b.width < 24 || b.width > 300) return false;
      const ok = n.children.every(c => ['VECTOR', 'GROUP', 'ELLIPSE', 'TEXT', 'BOOLEAN_OPERATION'].includes(c.type));
      return ok && n.children.some(c => c.type !== 'TEXT');
    });
    for (const r of rings) {
      const rb = r.absoluteBoundingBox;
      const shapes = r.children.filter(c => c.type !== 'TEXT');
      let x0 = Infinity, y0 = Infinity, x1 = -Infinity, y1 = -Infinity;
      for (const c of shapes) { const b = c.absoluteBoundingBox; x0 = Math.min(x0, b.x); y0 = Math.min(y0, b.y); x1 = Math.max(x1, b.x + b.width); y1 = Math.max(y1, b.y + b.height); }
      const u = Math.max(x1 - x0, y1 - y0);
      const off = Math.hypot((x0 + x1) / 2 - (rb.x + rb.width / 2), (y0 + y1) / 2 - (rb.y + rb.height / 2));
      if (Math.abs(u - rb.width * 0.96) <= rb.width * 0.12 && off <= Math.max(3, rb.width * 0.06)) continue;
      const s = (rb.width * 0.96) / u;
      const ucx = (x0 + x1) / 2 - rb.x, ucy = (y0 + y1) / 2 - rb.y;
      if ('clipsContent' in r) r.clipsContent = false;
      for (const c of r.children) {
        const ox = c.x, oy = c.y;
        if (c.type === 'TEXT') await Promise.all(c.getRangeAllFontNames(0, c.characters.length).map(f => figma.loadFontAsync(f)));
        c.rescale(s);
        c.x = rb.width / 2 + (ox - ucx) * s;
        c.y = rb.height / 2 + (oy - ucy) * s;
      }
      fixed++;
    }
  }
  return `Rescaled ${fixed} rings`;
}

// Section titles (20px semibold) were drawn 20px in from the screen edge while cards start at the 16px
// gutter. Move each title, and the "See all"-style link sharing its row, onto the gutter. Titles already
// at 16 no longer match, so this is safe to re-run.
const SCREEN_MIN_W = 370, SCREEN_MAX_W = 440, SCREEN_MIN_H = 600, OLD_SIDE = 20, NEW_SIDE = 16;

function screenOf(node) {
  for (let p = node.parent; p && p.type !== 'PAGE'; p = p.parent) {
    const b = p.absoluteBoundingBox;
    if (b && (p.type === 'FRAME' || p.type === 'GROUP') && b.width >= SCREEN_MIN_W && b.width <= SCREEN_MAX_W && b.height >= SCREEN_MIN_H) return p;
  }
  return null;
}

function nudge(node, dx) {
  const parent = node.parent;
  if (parent && 'layoutMode' in parent && parent.layoutMode !== 'NONE' && node.layoutPositioning !== 'ABSOLUTE') {
    // An auto-layout row owns its children's x: shrink the row's side padding instead.
    if (dx < 0) parent.paddingLeft = Math.max(0, parent.paddingLeft + dx);
    else parent.paddingRight = Math.max(0, parent.paddingRight - dx);
    return 'padding';
  }
  node.x += dx;
  return 'moved';
}

async function alignSectionTitles() {
  const stats = { titles: 0, links: 0, padding: 0, pages: 0 };
  const isTitleStyle = t => typeof t.fontName === 'object' && /Semi|Bold|Medium/i.test(t.fontName.style);
  for (const page of figma.root.children) {
    await page.loadAsync();
    const texts = page.findAll(n => n.type === 'TEXT');
    const titles = [];
    for (const t of texts) {
      if (t.fontSize !== 20 || !isTitleStyle(t)) continue;
      const screen = screenOf(t); if (!screen) continue;
      const sb = screen.absoluteBoundingBox, b = t.absoluteBoundingBox;
      if (Math.abs(b.x - sb.x - OLD_SIDE) > 1.5) continue;
      titles.push({ t, screen, b });
    }
    for (const { t, screen, b } of titles) {
      const sb = screen.absoluteBoundingBox;
      // The row's trailing link: same screen, vertically overlapping the title, ending 20px from the edge.
      const link = texts.find(o => o !== t && o.fontSize <= 17 && screenOf(o) === screen && (() => {
        const ob = o.absoluteBoundingBox;
        return Math.abs(sb.x + sb.width - (ob.x + ob.width) - OLD_SIDE) <= 2 && ob.y < b.y + b.height && ob.y + ob.height > b.y;
      })());
      if (nudge(t, NEW_SIDE - OLD_SIDE) === 'padding') stats.padding++;
      stats.titles++;
      if (link) { if (nudge(link, OLD_SIDE - NEW_SIDE) === 'padding') stats.padding++; stats.links++; }
    }
    if (titles.length) stats.pages++;
  }
  return `Aligned ${stats.titles} section titles and ${stats.links} links on ${stats.pages} pages (${stats.padding} via auto-layout padding)`;
}

// Each import command reads one exported file onto its own page.
const IMPORTS = {
  import: { file: 'r4-frames.json', page: 'Round 4 · System surfaces' },
  import5: { file: 'r5-frames.json', page: 'Round 5 · Your cards' },
};

async function importFrames(json, PAGE) {
  const frames = JSON.parse(json);
  const fonts = await figma.listAvailableFontsAsync();
  const families = new Set(fonts.map(f => f.fontName.family));
  // A family can be listed yet not lay out (e.g. a system font Figma cannot render): probe each candidate.
  let family = 'Inter';
  for (const cand of ['SF Pro Display', 'SF Pro', 'SF Pro Text', 'Inter']) {
    if (!families.has(cand)) continue;
    const style = fonts.find(f => f.fontName.family === cand && f.fontName.style === 'Regular') ? 'Regular' : fonts.find(f => f.fontName.family === cand).fontName.style;
    try {
      await figma.loadFontAsync({ family: cand, style });
      const probe = figma.createText(); probe.fontName = { family: cand, style }; probe.characters = 'Probe 68%';
      const ok = probe.width > 1; probe.remove();
      if (ok) { family = cand; break; }
    } catch (e) { /* try the next family */ }
  }
  const styles = fonts.filter(f => f.fontName.family === family).map(f => f.fontName.style);
  for (const style of styles) await figma.loadFontAsync({ family, style });
  // CSS weight -> the family's style name, falling back to the nearest one it has.
  const NAMES = { 100: 'Ultralight', 200: 'Thin', 300: 'Light', 400: 'Regular', 500: 'Medium', 600: 'Semibold', 700: 'Bold', 800: 'Heavy', 900: 'Black' };
  const styleFor = w => {
    const want = Math.round((w || 400) / 100) * 100;
    for (const d of [0, 100, -100, 200, -200, 300]) { const n = NAMES[want + d]; if (n && styles.includes(n)) return n; }
    return styles.includes('Regular') ? 'Regular' : styles[0];
  };
  const paint = c => {
    const m = /rgba?\(([^)]+)\)/.exec(c);
    if (m) { const p = m[1].split(/[ ,\/]+/).filter(Boolean).map(Number); return { color: { r: p[0] / 255, g: p[1] / 255, b: p[2] / 255 }, opacity: p.length > 3 ? p[3] : 1 }; }
    const h = c.replace('#', ''); const n = parseInt(h.length === 3 ? h.split('').map(x => x + x).join('') : h.slice(0, 6), 16);
    return { color: { r: (n >> 16 & 255) / 255, g: (n >> 8 & 255) / 255, b: (n & 255) / 255 }, opacity: 1 };
  };

  let page = figma.root.children.find(p => p.name === PAGE);
  if (!page) { page = figma.createPage(); page.name = PAGE; }
  await page.loadAsync();
  let x = 0;
  for (const f of frames) {
    for (const old of page.children.filter(n => n.name === f.name)) old.remove();
    const svg = f.svg.replace(/font-family="[^"]*"/g, `font-family="${family}"`);
    const node = figma.createNodeFromSvg(svg);
    node.name = f.name;
    page.appendChild(node);
    node.x = x; node.y = 0;
    // Figma's SVG importer drops <text>, so text arrives as positioned items and becomes real layers.
    for (const t of f.texts || []) {
      if (!t.s) continue;
      const tx = figma.createText();
      tx.fontName = { family, style: styleFor(t.weight) };
      tx.characters = t.s;
      tx.fontSize = t.size;
      if (t.ls) tx.letterSpacing = { unit: 'PIXELS', value: t.ls };
      const p = paint(t.color);
      tx.fills = [{ type: 'SOLID', color: p.color, opacity: p.opacity }];
      if (t.o < 1) tx.opacity = t.o;
      node.appendChild(tx);
      tx.x = t.x;
      tx.y = t.y + (t.h - tx.height) / 2;
    }
    x += node.width + 80;
  }
  return `Imported ${frames.length} frames in ${family}`;
}

if (figma.command === 'repair') {
  repairRings().then(m => figma.closePlugin(m), e => figma.closePlugin(`Error: ${e.message}`));
} else if (figma.command === 'align') {
  alignSectionTitles().then(m => figma.closePlugin(m), e => figma.closePlugin(`Error: ${e.message}`));
} else {
  const target = IMPORTS[figma.command] || IMPORTS.import;
  figma.showUI(__html__, { visible: false });
  figma.ui.onmessage = msg => {
    if (msg.type === 'ready') figma.ui.postMessage({ file: target.file });
    else if (msg.type === 'frames') importFrames(msg.json, target.page).then(m => figma.closePlugin(m), e => figma.closePlugin(`Error: ${e.message}`));
    else figma.closePlugin(`Could not reach the preview server: ${msg.message}`);
  };
}
