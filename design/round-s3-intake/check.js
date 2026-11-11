/* Round S3 check, run with `node design/round-s3-intake/check.js`. No browser is involved: it proves that
   the model reproduces the specification's §13 tables, that every frame builds, and that every word in every
   frame came from strings.js (§11 verbatim, a listed proposal, an existing string, system text, a model
   value or an annotation). It does NOT prove what a frame looks like. */
const fs = require('fs'), path = require('path');
const M = require('./model.js'), St = require('./strings.js'), F = require('./frames.js');
const here = f => path.join(__dirname, f);
const SPEC_FILE = path.join(__dirname, '../../docs/personal/superapp/specs/stage-3.md');
let failed = 0;
const section = name => console.log(`\n== ${name}`);
const ok = (cond, msg) => { if (!cond) { failed++; console.log(`  FAIL  ${msg}`); } return cond; };
const eq = (got, want, msg) => ok(JSON.stringify(got) === JSON.stringify(want), `${msg}: got ${JSON.stringify(got)}, want ${JSON.stringify(want)}`);
const pass = (n, what) => console.log(`  ${n} ${what}`);

/* ---------- 1. the model against §13 ---------- */
section('model against stage-3.md §13');
{
  const d9 = '2030-12-09', d10 = '2030-12-10', pe = (r, day) => r.days[day] ? [r.days[day].proteinGrams, r.days[day].energyKcal] : null;
  const s8 = M.SAMPLES.slice(0, 8), without = ids => s8.filter(s => !ids.includes(s.id));
  let n = 0; const c = (got, want, msg) => { n++; eq(got, want, msg); };
  let r = M.aggregate(s8); c([pe(r, d9), pe(r, d10)], [[95, 1450], [20, 250]], '§13.3 s1 to s8');
  r = M.aggregate(M.SAMPLES); c([pe(r, d9), pe(r, d10)], [[105, 1450], [20, 250]], '§13.3 s1 to s9, all sources');
  r = M.aggregate(M.SAMPLES, { admitted: ['app.fixture.food'] }); c([pe(r, d9), pe(r, d10), r.excluded], [[95, 1450], [20, 250], 1], '§13.3 admitted app.fixture.food');
  r = M.aggregate(s8.map(s => s.id === 's3' ? M.S3B : s)); c([pe(r, d9), pe(r, d10)], [[100, 1450], [20, 250]], '§13.3 edit s3 -> s3b');
  r = M.aggregate(without(['s5', 's6'])); c([pe(r, d9), pe(r, d10)], [[70, 1150], [20, 250]], '§13.3 delete s5 and s6');
  r = M.aggregate(without(['s7', 's8'])); c([pe(r, d9), pe(r, d10)], [[95, 1450], null], '§13.3 delete s7 and s8');
  r = M.aggregate([]); c(Object.keys(r.days).length, 0, '§13.3 no samples');
  r = M.aggregate(s8, { zoneLog: M.LOG_E }); c([pe(r, d9), pe(r, d10)], [[70, 1150], [45, 550]], '§13.3 zone log E');
  const ep = iso => Date.parse(iso) / 1000;
  c([M.dayKeyAt(ep('2030-12-09T19:00:00Z'), M.LOG_W), M.dayKeyAt(ep('2030-12-09T21:00:00Z'), M.LOG_W)], [d10, d9], '§13.3 zone log W');
  M.PROTEIN_CASES.forEach(([g, f, state, shown, rem, over, ring]) => { const p = M.protein(g, f);
    c([p.state, p.shownGrams, p.remainingGrams, p.overGrams, p.ringFraction == null ? null : +p.ringFraction.toFixed(5)], [state, shown, rem, over, ring], `§13.4 protein ${g} / ${f}`); });
  M.ENERGY_CASES.forEach(k => { const e = M.energy(k.kcal, M.FIXTURE.targets, k.open);
    c([e.state, e.toLowEndKcal, e.overHighEndKcal], [k.state, k.toLow == null ? null : k.toLow, k.over == null ? null : k.over], `§13.4 energy ${k.kcal} ${k.open ? 'open' : 'closed'}`); });
  M.CUTOFF_CASES.forEach((k, i) => { const tr = M.cutoffTriggers(k.cutoff, k.windDown);
    c([tr.length, tr.filter(x => !x.playsSound).map(x => x.weekday)], [7, k.silent], `§13.5 row ${i + 1}`); });
  // §13.6 and the one Fixture Person: stage 1's floor and stage 1's protein days.
  c(M.FIXTURE.proteinFloorGrams, 100, 'floor is stage 1\'s');
  c(Array.from({ length: 7 }, (_, i) => M.storedProtein(M.addDays('2031-01-29', i - 7))), [120, 120, 120, 80, 120, 120, 120], '§13.6 the seven days before today');
  c([M.TODAY.below, M.TODAY.atFloor, M.TODAY.above, M.TODAY.kcal], [95, 100, 105, 1450], '§13.6 today states');
  c([M.entriesFor(95), M.entriesFor(100), M.entriesFor(105)].map(es => [es.reduce((s, e) => s + e.proteinGrams, 0), es.reduce((s, e) => s + (e.energyKcal || 0), 0)]), [[95, 1450], [100, 1450], [105, 1450]], 'Path B entries sum to the day totals');
  const fresh = M.scenario(), old = M.scenario({ readMinutesAgo: M.FIXTURE.staleMinutesAgo });
  c([fresh.stale, M.hhmm(fresh.readAt), old.stale, M.hhmm(old.readAt)], [false, '15:10', true, '11:20'], '§13.6 fresh and stale read times');
  c(M.scenario({ now: M.NOW.evening }).clock.dayIsOpen, false, '§7.5 the day is closed after the cutoff');
  c(M.widgetState(M.widgetReading(M.scenario({ valueSource: 'nutritionCsv' })), 920).kind, 'notSetUp', '§10.8 a CSV value is never published');
  pass(n, 'model checks run');
}

/* ---------- 2. strings.js against §11 ---------- */
section('strings against stage-3.md §11');
const spec = fs.readFileSync(SPEC_FILE, 'utf8');
const sec11 = spec.slice(spec.indexOf('## 11. User-facing strings'), spec.indexOf('## 12. Test plan'));
const specStrings = new Set();
sec11.split('\n').filter(l => l.startsWith('|') && !l.startsWith('|---') && !l.startsWith('| Where')).forEach(l => {
  const cell = l.split('|')[2] || ''; (cell.match(/"([^"]+)"/g) || []).forEach(s => specStrings.add(s.slice(1, -1))); });
{
  const mine = new Set(Object.values(St.SPEC));
  Object.entries(St.SPEC).forEach(([k, v]) => ok(specStrings.has(v), `${k} is marked SPEC but is not a §11 string: "${v}"`));
  [...specStrings].forEach(s => ok(mine.has(s), `§11 string missing from strings.js: "${s}"`));
  const others = [...Object.values(St.PROPOSED), ...Object.values(St.EXISTING)].map(v => v[0]);
  others.forEach(s => ok(!specStrings.has(s) || s === 'as of %@', `"${s}" is a §11 string but is listed outside SPEC`));
  pass(specStrings.size, `strings in §11; ${mine.size} distinct in strings.js SPEC`);
}

/* ---------- 3. the frames ---------- */
section('frames');
const EXPECTED = { A: 7, B: 26, C: 1, D: 10, E: 17, F: 2, W: 9, O: 4 };
const GLYPHS = /^[›—–⌫+−]+$/;
const unesc = s => s.replace(/&lt;/g, '<').replace(/&gt;/g, '>').replace(/&amp;/g, '&');
{
  const names = new Set(), byGroup = {};
  let texts = 0;
  F.frames.forEach(f => {
    const full = F.PREFIX + f.name;
    ok(/^S3 \/ [A-Z]\d+ \S/.test(full), `bad frame name: ${full}`);
    ok(!names.has(full), `duplicate frame name: ${full}`); names.add(full);
    byGroup[f.id[0]] = (byGroup[f.id[0]] || 0) + 1;
    ok(typeof f.html === 'string' && f.html.length > 200, `${f.id}: empty frame`);
    ok(!/undefined|NaN|\[object|null</.test(f.html.replace(/data-ambient='[^']*'/g, '')), `${f.id}: the html contains undefined, NaN, null or [object`);
    // every text node, and every attribute that noop.js draws as text
    const body = f.html.replace(/<svg[^>]*>[\s\S]*?<\/svg>/g, '');
    body.split(/<[^>]+>/).map(s => unesc(s.replace(/\s+/g, ' ').trim())).filter(Boolean).forEach(text => {
      texts++;
      text.split(' · ').forEach(part => ok(St.REG.has(part) || GLYPHS.test(part), `${f.id}: text that did not come from strings.js or the model: "${part}"`));
    });
    (f.html.match(/data-(label|l0|l1)="[^"]*"/g) || []).forEach(at => { const v = unesc(at.slice(at.indexOf('"') + 1, -1)); ok(St.REG.has(v) || GLYPHS.test(v), `${f.id}: attribute text not registered: ${at}`); });
    // design rules that can be read from the markup
    ok(!/<line\b|data-band|data-target|stroke-dasharray="[^"]*"[^>]*class="(rule|band)/.test(f.html), `${f.id}: a chart rule, band or target line`);
  });
  eq(byGroup, EXPECTED, 'frames per group');
  eq(F.frames.length, Object.values(EXPECTED).reduce((s, n) => s + n, 0), 'frame count');
  pass(F.frames.length, `frames built, ${texts} text nodes read, all traced to strings.js or the model`);
}

/* ---------- 4. tone and privacy ---------- */
section('tone and privacy');
{
  const appText = [...St.used.spec, ...St.used.proposed];
  const banned = /\b(streak|in a row|well done|great|good job|congrat|warning|danger|unhealthy|healthy|should|must|don't forget|remember to|risk|deficien|diagnos)\b|!/i;
  appText.forEach(s => ok(!banned.test(s), `tone: "${s}"`));
  const sensitive = [M.FIXTURE.supplement.name, M.FIXTURE.foodApp.name, M.FIXTURE.otherApp.name, M.FIXTURE.preset.label, 'kcal', 'Calories'];
  F.frames.filter(f => 'WF'.includes(f.id[0])).forEach(f => sensitive.forEach(s => ok(!f.html.includes(s), `${f.id}: a widget or notification frame contains "${s}"`)));
  // the notification is exactly the specification's two strings
  const f1 = F.frames.find(f => f.id === 'F1').html;
  ok(f1.includes('>Food cutoff<') && f1.includes('>Your cutoff time is now.<'), 'F1 carries the exact notification title and body');
  pass(appText.length, 'app strings scanned; widget and notification frames carry no calories, supplement, app or label');
}

/* ---------- 5. the sources ---------- */
section('sources');
{
  const src = fs.readFileSync(here('frames.js'), 'utf8');
  ok(!/\b(?:d|a|t|N)\(\s*['"`]?\d{2,}/.test(src), 'frames.js passes a typed number of two or more digits to d(), t() or N()');
  ok(!/require\(|PersonalData/.test(src.replace(/require\('\.\/(model|strings)\.js'\)/g, '')), 'frames.js reads nothing but model.js and strings.js');
  const css = fs.readFileSync(path.join(__dirname, '../system/noop.css'), 'utf8');
  const tok = name => (new RegExp(`--${name}:\\s*(#[0-9A-Fa-f]{6})`).exec(css) || [])[1];
  eq(tok('t1'), '#F5F5F7', 'the primary text colour typed into SVG marks is noop.css --t1');
  const hexes = new Set(src.match(/#[0-9A-Fa-f]{6}\b/g) || []);
  eq([...hexes].sort(), ['#000000', '#F5F5F7', '#FFFFFF'], 'colours typed into frames.js');
  pass(hexes.size, 'literal colours in frames.js: primary text, white, black');
}

/* ---------- 6. the page scripts, loaded together over a stub DOM ---------- */
// No browser is used. The six scripts index.html loads are run in one context in page order, which catches
// a name declared twice across files, and the 28-day chart is drawn into stub elements so its marks can be
// counted. This says nothing about layout.
section('page scripts over a stub DOM');
{
  const vm = require('vm');
  const mk = tag => ({ tag, attrs: {}, children: [], style: {}, dataset: {}, classList: { add() {}, remove() {} },
    setAttribute(k, v) { this.attrs[k] = String(v); }, getAttribute(k) { return this.attrs[k]; }, appendChild(c) { this.children.push(c); return c; },
    querySelectorAll() { return []; }, querySelector() { return null; }, insertAdjacentHTML() {}, addEventListener() {} });
  const byId = {}, css = fs.readFileSync(path.join(__dirname, '../system/noop.css'), 'utf8') + fs.readFileSync(path.join(__dirname, '../round6-scorecard/scorecard.css'), 'utf8');
  const tokens = {}; (css.match(/--[\w-]+:\s*[^;}]+/g) || []).forEach(d => { const i = d.indexOf(':'); tokens[d.slice(0, i)] = d.slice(i + 1).trim(); });
  const ctx = { console, URLSearchParams, setTimeout() {}, requestAnimationFrame() {}, performance: { now: () => 0 }, location: { search: '?static=1' }, window: { addEventListener() {} },
    getComputedStyle: () => ({ getPropertyValue: n => tokens[n] || '' }),
    document: { documentElement: mk('html'), body: mk('body'), createElementNS: (_, tag) => mk(tag), createElement: tag => mk(tag), getElementById: id => byId[id] || (byId[id] = mk('div')), querySelectorAll: () => [], querySelector: () => null } };
  vm.createContext(ctx);
  const order = ['../system/noop.js', '../round6-scorecard/model.js', 'model.js', 'strings.js', 'frames.js', 'intake.js'];
  const html = fs.readFileSync(here('index.html'), 'utf8');
  eq((html.match(/<script src="([^"]+)"/g) || []).map(x => x.slice(13, -1)), order, 'index.html script order');
  (html.match(/href="([^"]+\.css)"/g) || []).forEach(h => ok(fs.existsSync(here(h.slice(6, -1))), `stylesheet exists: ${h}`));
  let loaded = true;
  try { vm.runInContext(order.map(f => fs.readFileSync(here(f), 'utf8')).join('\n;\n'), ctx, { filename: 'page-scripts' }); }
  catch (e) { loaded = false; ok(false, `the page scripts do not load together: ${e.message}`); }
  if (loaded) {
    const boards = byId.boards.innerHTML || '';
    const titles = (boards.match(/<div class="board-title">([^<]+)</g) || []).map(x => x.slice(25, -1));
    eq(titles.length, F.frames.length, 'frames mounted in #boards');
    ok(titles.every(x => x.startsWith('S3 / ')), 'every mounted frame is named "S3 / <id> <title>"');
    eq(titles, F.frames.map(f => F.PREFIX + f.name), 'mounted names match frames.js');
    // classes used by the frames exist in one of the three stylesheets or are noop.js hooks
    const allCss = css + fs.readFileSync(here('intake.css'), 'utf8'), hooks = new Set(['ring', 'rings', 'motion', 'num', 'screen', 'tabbar', 'home', 'dc', 'grow1', 'on', 'off', 'none', 'bad', 'add', 'rem', 'note', 'stale', 'tert', 's', 'm', 'ph', 'plus', 'of', 'pc', 'ec', 'cv', 'slab', 'dimmed', 'rdc', 'wsheet', 'primary', 'secondary', 'danger', 'quiet']);
    const used = new Set(); (boards.match(/class="[^"]+"/g) || []).forEach(c => c.slice(7, -1).split(/\s+/).forEach(x => x && used.add(x)));
    [...used].forEach(c => ok(hooks.has(c) || new RegExp(`\\.${c}(?![\\w-])`).test(allCss), `class "${c}" has no style`));
    // the chart: B1 (22 measured days, 6 not measured before the first) and B8 (stage 1's week 6 gaps)
    const draw = id => { const m = /<svg class="dc" width="(\d+)" height="(\d+)" data-v="([^"]+)" data-m="([^"]+)" data-l0="([^"]+)" data-l1="([^"]+)"/.exec(F.frames.find(f => f.id === id).html);
      const svg = mk('svg'); svg.attrs = { width: m[1], height: m[2] }; svg.dataset = { v: m[3], m: m[4], l0: m[5], l1: m[6] }; ctx.dayChart(svg);
      const kids = svg.children, count = (tag, cls) => kids.filter(k => k.tag === tag && (!cls || k.attrs.class === cls)).length;
      return { values: m[3].split(','), marks: m[4].split(','), strokes: count('path', 'stroke'), areas: count('path', 'area'), points: count('circle', 'pt'), lines: count('line'), rects: count('rect'),
        open: kids.filter(k => k.attrs.class === 'pt' && k.attrs['stroke-width'] === '1.5').length, axisMarks: kids.filter(k => k.tag === 'circle' && !k.attrs.class).length, labels: kids.filter(k => k.tag === 'text').map(k => k.textContent) }; };
    const b1 = draw('B1'), b8 = draw('B8');
    eq([b1.values.length, b1.values.filter(x => x !== 'x').length, b1.strokes, b1.areas, b1.points, b1.lines, b1.rects], [28, 22, 1, 1, 22, 0, 0], 'B1 chart: 28 days, 22 measured, one unbroken run, no rule or band');
    eq(b1.open, b1.marks.filter(x => x === '0').length, 'B1 chart: one open point per day below the floor');
    eq(b1.labels, ['2 Jan', '29 Jan'], 'B1 chart: axis labels');
    eq([b8.values.filter(x => x !== 'x').length, b8.strokes, b8.axisMarks, b8.lines], [23, 1, 5, 0], 'B8 chart: one stroked run; 6, 8, 9, 11 and 12 Feb are not measured, marked on the axis and never drawn across');
    pass(titles.length, 'frames mounted; chart marks counted for B1 and B8');
  }
}

/* ---------- report ---------- */
section('strings used in frames');
const unusedSpec = Object.values(St.SPEC).filter(s => !St.used.spec.has(s));
console.log(`  §11 strings drawn: ${new Set(Object.values(St.SPEC)).size - new Set(unusedSpec).size} of ${new Set(Object.values(St.SPEC)).size}`);
console.log(`  §11 strings not drawn: ${unusedSpec.length ? unusedSpec.map(s => `"${s}"`).join(', ') : 'none'}`);
const unusedProp = Object.entries(St.PROPOSED).filter(([, v]) => !St.used.proposed.has(v[0]));
ok(unusedProp.length === 0, `proposals that no frame uses: ${unusedProp.map(([k]) => k).join(', ')}`);
console.log(`  proposed strings drawn: ${St.used.proposed.size}; existing app strings: ${St.used.existing.size}; iOS system strings: ${St.used.system.size}; annotations: ${St.used.note.size}`);

if (process.argv.includes('--list')) { section('frame names'); F.frames.forEach(f => console.log(`  ${F.PREFIX}${f.name}`)); }
console.log(failed ? `\n${failed} FAILED` : `\nALL CHECKS PASSED · ${F.frames.length} frames`);
process.exit(failed ? 1 : 0);
