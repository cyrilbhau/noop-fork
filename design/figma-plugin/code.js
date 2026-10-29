// Repairs html_to_figma import faults on the round-3 frames, using geometry only (the importer's
// layer names are generic). Safe to re-run: a ring that already fits its frame is left alone.
//
// Rings are SVGs with a 0–100 viewBox. The importer places each SVG frame correctly but draws its
// contents in viewBox units, so a 230px ring renders ~100px in a corner and a 46px ring overflows
// and clips. Map the contents back into the frame: scale by frame/viewBox and centre, treating any
// label text the same way as the arcs.
(async () => {
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
  figma.closePlugin(`Rescaled ${fixed} rings`);
})().catch(e => figma.closePlugin(`Error: ${e.message}`));
