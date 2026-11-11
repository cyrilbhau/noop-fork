#!/usr/bin/env node
/* Round combined · checks that run without a browser:  node design/round-combined/check.js  [--list] [--proposals]
   They prove that the model and the frame builders execute, that the frame list is what the README says, that
   every string taken from a specification is in that specification, and that the fixtures reproduce the
   specifications' own worked tables. They do NOT prove how a frame looks: nothing here renders. */
const fs = require('fs'), path = require('path'), vm = require('vm');
const HERE = __dirname, REPO = path.resolve(HERE, '../..'), SPECS = path.join(REPO, 'docs/personal/superapp/specs');
const read = p => fs.readFileSync(p, 'utf8');
let failed = 0, passed = 0;
const ok = (cond, what, detail) => { if (cond) passed++; else { failed++; console.log(`FAIL  ${what}${detail ? `\n      ${detail}` : ''}`); } };
const eq = (a, b, what) => ok(JSON.stringify(a) === JSON.stringify(b), what, `got ${JSON.stringify(a)}\n      expected ${JSON.stringify(b)}`);
const section = s => console.log(`\n== ${s}`);

/* ---------- 1. the files load in Node and the frame list is well-formed ---------- */
section('1. frame list');
const M = require('./model.js'), P = require('./r6-presenter.js'), F = require('./frames.js');
const EXPECTED = { H: 8, S: 11, B: 18, T: 9, N: 1 };
const total = Object.values(EXPECTED).reduce((a, b) => a + b, 0);
eq(F.frames.length, total, `frame count is ${total}`);
eq(new Set(F.frames.map(f => f.title)).size, F.frames.length, 'frame names are unique');
ok(F.frames.every(f => /^SC \/ [HSBTN]\d+ \S/.test(f.title)), 'every frame is named "SC / <id> <title>"');
for (const [g, n] of Object.entries(EXPECTED)) eq(F.frames.filter(f => f.name[0] === g).map(f => +f.name.match(/^\w(\d+)/)[1]), Array.from({ length: n }, (_, i) => i + 1), `group ${g} has ids ${g}1 to ${g}${n}`);
ok(F.frames.every(f => typeof f.html === 'string' && f.html.length > 300 && !/undefined|NaN|\[object|null/.test(f.html.replace(/<svg[\s\S]*?<\/svg>/g, ''))), 'no frame contains undefined, NaN, null or [object');
ok(F.frames.filter(f => f.cls === 'ax').map(f => f.name.slice(0, 2)).join() === 'H8,S1,B1,T9', 'one AX5 frame per primary screen (H8, S11, B15, T9)');
if (process.argv.includes('--list')) F.frames.forEach(f => console.log('  ' + f.title));

/* ---------- 2. the same files as the page loads them: classic scripts sharing one global scope ---------- */
section('2. page load order, simulated');
const TOKENS = P.C.toString();                               // the Node fallback token reader, reused as the page's C
const ctx = vm.createContext({ console, URLSearchParams });
vm.runInContext('var window = globalThis;', ctx);
// The top-level names design/system/noop.js declares, so a clash with them would throw here as it would in the page.
const noopNames = [...read(path.join(REPO, 'design/system/noop.js')).matchAll(/^(?:const|let|function|async function)\s+([A-Za-z_$][\w$]*)/gm)].map(m => m[1]);
const fallback = "v => !v ? '#F5F5F7' : ({ '--t1': '#F5F5F7', '--t2': '#9B9BA3', '--recovery': '#2FD27A', '--rec-mid': '#FFC83D', '--rec-low': '#FF5A4F', '--sig-met': '#2FD27A', '--sig-not': '#FFC83D', '--sig-unk': '#8A8A93' })[v] || v";
vm.runInContext(noopNames.map(n => n === 'C' ? `const C = ${fallback};` : `const ${n} = function () {};`).join('\n'), ctx);
let loadError = null;
for (const file of ['../round6-scorecard/model.js', 'model.js', 'r6-presenter.js', 'frames.js']) {
  try { vm.runInContext(read(path.join(HERE, file)), ctx, { filename: file }); } catch (e) { loadError = `${file}: ${e.message}`; break; }
}
ok(!loadError, 'model.js, r6-presenter.js and frames.js load as page scripts after noop.js and round 6\'s model.js', loadError);
if (!loadError) {
  const pageFrames = vm.runInContext('SCF.frames.map(f => [f.title, f.html])', ctx);
  eq(pageFrames.length, F.frames.length, 'page load builds the same number of frames');
  ok(pageFrames.every(([title, html], i) => title === F.frames[i].title && html === F.frames[i].html), 'page load builds byte-identical frames to the Node load');
  eq(vm.runInContext('Object.keys(globalThis).filter(k => /^SC/.test(k)).sort()', ctx), ['SCF', 'SCM', 'SCP'], 'the three files add exactly three globals: SCM, SCP, SCF');
}
for (const file of ['model.js', 'r6-presenter.js', 'frames.js', 'combined.js']) ok(/^\(function \(/m.test(read(path.join(HERE, file)).replace(/\/\*[\s\S]*?\*\//, '').trim().slice(0, 12)), `${file} is one function scope (declares no page-level name)`);

/* ---------- 3. combined.js against a stub page: boards are built and every chart is drawn ---------- */
section('3. page script against a stub document');
const charts = [];
if (!loadError) {
  const stub = { boards: '', inserted: 0 };
  const fakeSvg = tag => { const attrs = Object.fromEntries([...tag.matchAll(/([\w-]+)="([^"]*)"/g)].map(m => [m[1], m[2]])); const kids = [];
    return { attrs, kids, dataset: Object.fromEntries(Object.entries(attrs).filter(([k]) => k.startsWith('data-')).map(([k, v]) => [k.slice(5), v])), getAttribute: k => attrs[k] }; };
  let svgs = [];
  const ctx2 = vm.createContext({ console, URLSearchParams, setTimeout: () => 0 });
  vm.runInContext('var window = globalThis;', ctx2);
  ctx2.SCF = F; ctx2.location = { search: '?static=1' }; ctx2.STATIC = true;
  ctx2.C = eval(fallback);
  ctx2.el = (t, a, parent) => { const e = { t, a: { ...a }, kids: [], textContent: null }; (parent.kids || parent.kids === undefined && (parent.kids = [])).push(e); return e; };
  ctx2.document = { body: { insertAdjacentHTML: () => { stub.inserted++; } },
    getElementById: id => id === 'boards' ? { set innerHTML(v) { stub.boards = v; svgs = [...v.matchAll(/<svg class="wk"[^>]*>/g)].map(m => fakeSvg(m[0])); } } : null,
    querySelectorAll: sel => sel === 'svg.wk' ? svgs : [] };
  ctx2.boot = extra => extra && extra();
  let err = null;
  try { vm.runInContext(read(path.join(HERE, 'combined.js')), ctx2, { filename: 'combined.js' }); } catch (e) { err = e.stack.split('\n').slice(0, 3).join(' | '); }
  ok(!err, 'combined.js runs to the end', err);
  eq((stub.boards.match(/class="board-title"/g) || []).length, total, 'the page gets one titled board per frame');
  ok(F.frames.every(f => stub.boards.includes(`<div class="board-title">${f.title}</div>`)), 'each board title is the frame name the export will use');
  ok(svgs.length > 0 && svgs.every(s => s.kids.length > 0), `every weekly chart is drawn (${svgs.length} charts)`);
  const flat = n => [n].concat((n.kids || []).flatMap(flat));
  for (const s of svgs) charts.push({ d: s.dataset, nodes: s.kids.flatMap(flat) });
  ok(charts.every(c => c.nodes.every(n => Object.values(n.a).every(v => !/NaN|undefined|Infinity/.test(String(v))))), 'no chart attribute is NaN, undefined or infinite');
  ok(charts.every(c => c.nodes.every(n => ['defs', 'linearGradient', 'stop', 'path', 'circle', 'text'].includes(n.t))), 'charts hold only gradients, paths, circles and two date labels: no line, rect or band element');
  ok(charts.every(c => c.nodes.filter(n => n.t === 'path').every(n => !/^M[\d.]+,([\d.]+) L[\d.]+,\1$/.test(n.a.d))), 'no chart path is a straight horizontal rule');
  ok(charts.every(c => c.nodes.filter(n => n.a.class === 'evmark').length === (c.d.m ? c.d.m.split(',').filter(x => x === '1').length : 0)), 'one axis dot per week an event covers, and none without the data-m attribute');
  ok(charts.every(c => c.nodes.filter(n => n.a.class === 'missed').length === c.d.v.split(',').filter(x => x === 'x').length), 'one open ring per week with no reading');
  ok(charts.every(c => { const runs = c.d.v.split(/(?:,|^)x(?:,|$)/).filter(Boolean).filter(r => r.split(',').length > 1).length; return c.nodes.filter(n => n.a.class === 'stroke').length === runs; }), 'a week with no reading breaks the line: one stroke per unbroken run');
}

/* ---------- 4. strings ---------- */
section('4. strings');
const sources = {};
const fileFor = src => /^stage-\d\.md$/.test(src) ? path.join(SPECS, src) : path.join(REPO, src);
const proposals = [], unused = [];
for (const [key, [text, src]] of Object.entries(F.STR)) {
  if (!F.used.has(key)) unused.push(key);
  if (src === 'proposal') { proposals.push(text); continue; }
  sources[src] = sources[src] || read(fileFor(src));
  ok(sources[src].includes(text), `"${text}" is in ${src}`);
}
// The fixture's only illness is private, so its kind name is never drawn; the string stays for a non-private one.
eq(unused.filter(k => k !== 'kIllness'), [], 'every string in the table is used by a frame');
console.log(`  ${Object.keys(F.STR).length} strings in the table: ${Object.keys(F.STR).length - proposals.length} found verbatim in their source, ${proposals.length} proposals`);
if (process.argv.includes('--proposals')) proposals.forEach(p => console.log('  proposal: ' + p));

/* ---------- 5. every text in every frame is accounted for ---------- */
section('5. text audit');
const texts = html => html.replace(/<div class="[^"]*\banno\b[^"]*"[^>]*>[^<]*<\/div>/g, ' ').replace(/<svg[\s\S]*?<\/svg>/g, ' ').replace(/<[^>]+>/g, '\n').split('\n').map(s => s.trim()).filter(Boolean);
const esc = s => s.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
const GENERIC = new Set(['evLine', 'evRange', 'evSince']);     // "%@ · %@" would match anything; event lines get their own pattern below
const templates = Object.entries(F.STR).filter(([k]) => !GENERIC.has(k)).map(([, [text]]) => new RegExp('^' + esc(text).replace(/%lld/g, '[\\d.]+').replace(/%@|<date>/g, '.+') + '$'));
// What the unchanged stage 1 presenter says for every day and variant a frame uses.
const leaves = new Set(), walk = v => { if (typeof v === 'string') leaves.add(v); else if (Array.isArray(v)) v.forEach(walk); else if (v && typeof v === 'object') Object.entries(v).forEach(([k, x]) => { if (k !== 'r' && k !== 'U') walk(x); }); };
const ALL = Array.from({ length: 22 }, (_, i) => i + 1);
[...ALL.map(k => ({ today: M.R6.weighDay(k) })), { today: M.TODAY }, { today: '2031-03-12' }, { today: '2031-01-06', without: ALL }, { today: '2031-01-08', without: ALL }, { today: '2031-01-29', phase: null },
  { today: '2031-02-19', noLifts: true, phase: { ...M.R6.FIXTURE_PHASE, startDay: '2031-02-03' } }, { today: '2031-03-19', without: [11] }, { today: M.TODAY, params: { ...M.R6.FIXTURE_PARAMS, proteinFloorGrams: null } }].forEach(o => walk(P.FX(o)));
const LAYOUT = [/^Verdict( · week of \d+ \w{3})?$/, /^\d of 4 signals met$/, /^Your three rules, in order$/, /^Four signals$/, /^week of \d+ \w{3}$/, /^Weekly curves$/, /^History$/, /^(Weight|Waist)$/, /^Rate of (loss|gain)$/, /^Of bodyweight$/,
  /^(kg|cm|g|ms|bpm|kg\/week|%\/week)$/, /^Estimate$/, /^Log weigh-in$/, /^Phase and rules$/, /^\d+ weigh-ins?$/, /^Compares the heaviest working set of each exercise with the week before\.$/,
  /^This is your own rule applied to your own numbers\. Nothing has been changed\.$/, /^Weigh-in due this week$/, /^The verdict below is from the week of \d+ \w{3}\.$/, /^(Met|Not met|Unknown|Fired|Not fired|Could not check)$/,
  /^[›—−+]$/, /^[−+]?\d+(\.\d+)?$/, /^\d\d:\d\d$/, /^(Health|Today|Settings|Vitals|All|HRV|Resting heart rate|Last night|Edit|Cancel|Save|Shown|More cards|Stress|Fitness age|Coupled view|Coach|Hydration)$/,
  /^(Mon|Tue|Wed|Thu|Fri|Sat|Sun), \d+ \w{3}$/, /^Shown for today only$/, /^Not measured yet$/, /^Weight and waist$/,
  /^(Travel|Illness|Diet break|Deload|Supplement change|Private event) · (since )?\d+( \w{3})?( – \d+ \w{3})?$/];
const FIXTURE_TEXT = new Set([M.INTAKE.supplement, `${M.INTAKE.foodApp}, ${M.INTAKE.otherApp}`, M.REMINDER.day, `${M.INTAKE.refusedFloorEntry} g`]);
const known = s => templates.some(r => r.test(s)) || leaves.has(s) || LAYOUT.some(r => r.test(s)) || FIXTURE_TEXT.has(s);
const accounted = s => known(s) || (/ · (\d\d:\d\d|imported)$/.test(s) && known(s.replace(/ · (\d\d:\d\d|imported)$/, ''))) || (/ · \d+\.\d kg$/.test(s) && known(s.replace(/ · \d+\.\d kg$/, '')));
const stray = new Map(); let nTexts = 0;
for (const f of F.frames) for (const s of texts(f.html)) { nTexts++; if (!accounted(s)) stray.set(s, (stray.get(s) || []).concat(f.name.split(' ')[0])); }
eq([...stray.keys()], [], 'every text is a specification string, a proposal in the table, the stage 1 presenter\'s output, round 6 layout copy, or fixture data');
console.log(`  ${nTexts} text runs in ${F.frames.length} frames checked (reviewer annotations excluded)`);

/* ---------- 6. the rules a frame is checked against, as far as text can show them ---------- */
section('6. design rules visible in text');
const allText = F.frames.flatMap(f => texts(f.html).map(s => [f.name, s]));
const banned = /\b(warning|streak|in a row|should|must|great|well done|good job|keep it up|don.t forget|missed|overdue|failed|bad|poor|unhealthy|diagnos|risk|danger|too (low|high|little|much))\b/i;
eq(allText.filter(([, s]) => banned.test(s)).map(([n, s]) => `${n}: ${s}`), [], 'no warning, streak, praise, guilt or medical wording in any frame');
eq(allText.filter(([, s]) => /^0( (g|kg|cm|ms|bpm|kcal|open|now))?$/.test(s)).map(([n, s]) => `${n}: ${s}`), [], 'no value, count or detail reads 0 ("0.0 cm" on a waist curve is a measured change of nothing)');
const h6 = texts(F.frames.find(f => f.name.startsWith('H6 ')).html);
ok(h6.filter(s => s === '—').length === 2 && h6.filter(s => s === 'Not measured').length === 2 && !h6.some(s => /\d+ (now|open)|Next:|Last scan/.test(s)), 'first use: unmeasured vitals read "—" and "Not measured"; rows with nothing to report show no detail');
const n1 = texts(F.frames.find(f => f.name.startsWith('N1 ')).html);
eq(n1, ['Weekly weigh-in', '08:00', 'Weight, then waist. It takes under a minute.', 'Food cutoff', '20:00', 'Your cutoff time is now.'], 'the notification frame holds exactly the two notifications, word for word');
const notifText = F.frames.flatMap(f => [...f.html.matchAll(/<div class="notif">([\s\S]*?)<\/div><\/div><\/div>/g)].map(m => texts(m[1]).join(' | ')));
ok(notifText.length >= 4 && notifText.every(s => s === 'Weekly weigh-in | 08:00 | Weight, then waist. It takes under a minute.' || s === 'Food cutoff | 20:00 | Your cutoff time is now.'), 'every drawn notification is one of those two; none carries a measurement, verdict, amount or name');
ok(F.frames.filter(f => /B6 |B7 /.test(f.name)).every(f => !/Fixture change|Fixture note|Illness/.test(f.html)), 'a private event never shows its kind, label or note outside the Events screen');
ok(F.frames.filter(f => f.name[0] === 'B' && /Estimated \w{3} \d+ \w{3} at this rate/.test(f.html)).every(f => f.html.includes('<span class="est">Estimate</span>')), 'every projected date carries the Estimate label');
const order = ['Scorecard', 'Coach packet', 'Intake', 'Body record', 'Events', 'Niggle log', 'Recovery context', 'Timeline'];
const rowTitles = f => [...f.html.matchAll(/<div class="lrow hr">.*?<div class="t grow1">([^<]*)<\/div>/g)].map(m => m[1]).filter(s => order.includes(s));
const cardTitles = f => [...f.html.matchAll(/<div class="shd">.*?<b>([^<]*)<\/b>/g)].map(m => m[1]);
const fr = id => F.frames.find(f => f.name.startsWith(id + ' '));
eq(rowTitles(fr('H1')), order, 'H1: the eight Health rows are in the order of ruling A1');
eq(rowTitles(fr('H2')), order.filter(s => s !== 'Recovery context'), 'H2: the option without a Recovery context row keeps the order');
eq(rowTitles(fr('H3')), ['Coach packet', 'Events', 'Timeline'], 'H3: only rows whose switch is on, order unchanged; no Recovery context row while the scorecard is off');
eq(rowTitles(fr('H5')), [], 'H5: no stage row with every switch off');
for (const id of ['S1', 'S2', 'S3', 'S11']) eq(cardTitles(fr(id)), order, `${id}: all eight Settings cards are drawn, in the order of ruling A1`);
eq((fr('S1').html.match(/class="toggle on"/g) || []).length, 0, 'S1: every switch is off by default');
eq((fr('S1').html.match(/class="toggle"/g) || []).length, 9, 'S1: nine switches (Body record holds two), and nothing else in any card');

/* ---------- 7. the fixtures reproduce the specifications' own worked tables ---------- */
section('7. fixture goldens');
const weeks22 = ALL.map(k => M.R6.weekStart(M.R6.weighDay(k)));
eq(M.marked(weeks22, M.EVENTS, '2031-06-04').map((b, i) => b ? i + 1 : 0).filter(Boolean), [3, 5, 7, 8, 10, 12, 15, 16, 20, 21, 22], 'stage 5 §13.2: events cover weeks 3, 5, 7, 8, 10, 12, 15, 16, 20, 21, 22');
const note = d => { const n = M.eventNote(M.result({ today: d }), M.EVENTS, d); return n && { week: n.inWeek.map(e => e.id), earlier: n.earlier.map(e => e.id), start: n.evidenceStartDay }; };
eq(note('2031-03-26'), { week: ['E6'], earlier: ['E1', 'E8'], start: '2031-02-10' }, 'stage 5 §13.2: on 26 Mar the judged week holds E6 and E1 is in the earlier section');
eq(note('2031-02-05'), { week: ['E2'], earlier: ['E4'], start: '2030-12-23' }, 'on 5 Feb the deload covers the judged week and the supplement change is earlier');
eq(note('2031-01-08'), { week: [], earlier: ['E7'], start: '2030-11-25' }, 'week 1: the evidence window (stage 1 §7.9) reaches back before the phase, so the December trip is listed as earlier');
eq(M.eventNote(M.result({ today: '2031-02-05' }), [], '2031-02-05'), null, 'no events stored: no note');
eq(M.eventNote(M.result({ today: '2031-01-08', without: ALL }), M.EVENTS, '2031-01-08'), null, 'no judged week: no note');
eq([null, 95, 99.9994, 99.9996, 100, 105].map(g => { const p = M.proteinProgress(g, 100); return [p.state, p.shown, p.remaining, p.over]; }),
  [['notMeasured', null, null, null], ['below', 95, 5, 0], ['below', 99, 1, 0], ['atFloor', 100, 0, 0], ['atFloor', 100, 0, 0], ['above', 105, 0, 5]], 'stage 3 §13.4: protein progress table');
eq((p => [p.state, p.shown, p.ring])(M.proteinProgress(105, null)), ['noFloor', 105, null], 'stage 3 §13.4: no floor set');
eq([M.openNiggles('2031-02-05'), M.openNiggles('2031-03-01'), M.openNiggles('2031-01-06')], [1, 0, 0], 'stage 6 §13.2: one complaint open on 5 Feb, none on 1 Mar (N1 resolved) or before any onset');
eq(M.nextTimelineDay('2031-02-05', M.ALL_ON, M.result({ today: '2031-02-05' }), M.EVENTS), '2031-02-10', 'stage 6 §13.4: on 5 Feb the first upcoming item is the checkpoint of 10 Feb');
eq([M.lastScan('2031-02-05'), M.lastScan('2031-01-06')], ['2031-01-08', null], 'stage 4 §13: the last scan on 5 Feb is 8 Jan; none before it');
eq([M.lastNight('2031-02-05'), M.lastNight('2031-02-06'), M.lastNight('2031-01-06')], [{ rhr: 64, hrv: 45 }, null, { rhr: 60, hrv: 50 }], 'stage 6 §13.3: nights of 5 Feb and 6 Jan; no night on 6 Feb is "not measured"');
eq([M.eventsNow(M.EVENTS, '2031-02-05'), M.eventsNow(M.EVENTS, '2031-01-08')], [1, 0], 'stage 5 §13.1: one event overlaps 5 Feb, none on 8 Jan');
eq(M.present(M.ALL_ON), ['scorecard', 'packet', 'intake', 'bodyRecord', 'events', 'niggle', 'recovery', 'timeline'], 'ruling A1: the one order');
const b1 = P.FX({ today: M.TODAY });
eq([b1.verdict.title, b1.card.v, b1.sig[2].reason], ['Change nothing', '97.5', 'Below your floor on 4 days'], 'stage 1 §13.3 week 5: verdict, weight and protein signal');

console.log(`\n${failed ? 'FAILED' : 'OK'}: ${passed} checks passed, ${failed} failed. ${F.frames.length} frames. Nothing was rendered: the frames have not been viewed.`);
process.exit(failed ? 1 : 0);
