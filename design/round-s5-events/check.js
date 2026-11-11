/* Round S5 · node check. Run: node design/round-s5-events/check.js
   No browser is involved: this proves the model and the frame builders execute, that the model reproduces the
   specification's fixture tables, that every stage 5 string a frame can show is a §11 string, and that the frames
   keep the round's rules that can be read from markup. It does NOT prove what a frame looks like. */
const fs = require('fs'), path = require('path'), assert = require('assert');
const M = require('./model.js'), F = require('./frames.js');
const spec = fs.readFileSync(path.join(__dirname, '../../docs/personal/superapp/specs/stage-5.md'), 'utf8');
let checks = 0; const ok = (c, m) => { assert.ok(c, m); checks++; }, eq = (a, b, m) => { assert.deepStrictEqual(a, b, m); checks++; };

/* 1. the model against §13 */
const weeks = Array.from({ length: 22 }, (_, i) => M.add('2031-01-06', 7 * i)), wk = n => weeks[n - 1];
const coveredWeeks = list => M.coveredSlots(list, M.weekSlots(weeks)).map((c, i) => c ? i + 1 : 0).filter(Boolean);
eq(coveredWeeks(M.EVENTS), [3, 5, 7, 8, 10, 12, 15, 16, 20, 21, 22], '§13.2 covered weeks');
eq(coveredWeeks(M.VARIANTS.V1), [], 'V1');
eq(coveredWeeks(M.VARIANTS.V2), [12, 20, 21, 22], 'V2');
eq(coveredWeeks(M.VARIANTS.V5), [3, 5, 7, 8, 10, 12, 15, 16, 20], 'V5');
eq(coveredWeeks(M.VARIANTS.V9), coveredWeeks(M.EVENTS), 'V9 keeps its marks');
const rel = (id, n) => M.relation(M.E(id), wk(n), M.add(wk(n), 6));
eq([rel('e4', 3), rel('e2', 5), rel('e8', 7), rel('e8', 8), rel('e5', 20), rel('e5', 21), rel('e7', 1)], ['within', 'within', 'startsWithin', 'endsWithin', 'startsWithin', 'covers', 'before'], '§13.2 relations');
eq(M.normalized([{ ...M.E('e1'), endDay: '2031-03-09' }]).length, 0, 'V3 dropped');
eq(M.normalized([M.E('e1'), { ...M.E('e1'), startDay: '2031-03-11' }])[0].startDay, '2031-03-11', 'V4 last wins');
eq(M.KINDS.filter(k => M.DEFAULT_SENSITIVE[k]), ['illness', 'custom'], '§7.2 defaults');
eq(M.num('2031-02-30'), null, 'not a real date'); eq(M.num('2031-2-03'), null, 'not canonical');
eq(M.scorecardDay('2031-03-26', M.EVENTS).note.lines, ['Private event · 26 Mar'], '§13.2 note on 26 Mar');
ok(M.scorecardDay('2031-03-26', M.EVENTS).note.earlierLines.includes('Travel · 10 – 16 Mar'), 'E1 in the earlier section on 26 Mar');
eq(M.evidenceStartDay(M.scorecardDay('2031-03-26', M.EVENTS).result), '2031-02-10', 'stage 1 §7.9');
eq(M.scorecardDay('2031-03-12', M.EVENTS).marked[9], true, 'week 10 marked on 12 Mar');
eq(M.present(M.EVENTS, '2031-03-12').healthRowValue, '1 now'); eq(M.present(M.EVENTS, '2031-01-29').healthRowValue, null);
eq(M.caption(M.VARIANTS.V2, '2031-01-06', '2031-06-08', '2031-06-04').lines, ['Private event · since 19 May', 'Private event · 26 Mar'], 'V2 captions');
eq(M.caption(M.EVENTS, '2031-01-01', '2031-01-20', '2031-01-20'), null, 'no event, no caption');
// the events never reach the stage 1 evaluation: same verdict with and without them, on every fixture weigh-in day
for (let n = 1; n <= 22; n++) { const d = M.add('2031-01-08', 7 * (n - 1)); eq(M.scorecardDay(d, M.EVENTS).result.verdict, M.scorecardDay(d, []).result.verdict, `verdict unchanged, week ${n}`); }

/* 2. strings: every STR value is a §11 string; no proposal is */
const s11 = spec.slice(spec.indexOf('## 11. User-facing strings'), spec.indexOf('## 12. Test plan')).replace(/\\"/g, '"');
const leaves = o => Object.values(o).flatMap(v => typeof v === 'string' ? [v] : leaves(v));
leaves(M.STR).forEach(s => ok(s11.includes(`"${s}"`), `not a §11 string: ${s}`));
leaves(M.PROPOSED).forEach(s => ok(!s11.includes(`"${s}"`), `listed as a proposal but is in §11: ${s}`));
const readme = fs.existsSync(path.join(__dirname, 'README.md')) ? fs.readFileSync(path.join(__dirname, 'README.md'), 'utf8') : null;
if (readme) leaves(M.PROPOSED).forEach(s => ok(readme.includes(s), `proposal missing from the README: ${s}`));

/* 3. frames */
const frames = F.frames, id = f => f.name.slice(5).split(' ')[0];
ok(frames.length === 82, `frame count ${frames.length}`);
eq(new Set(frames.map(f => f.name)).size, frames.length, 'names unique'); eq(new Set(frames.map(id)).size, frames.length, 'ids unique');
frames.forEach(f => { ok(/^S5 \/ [A-Z]\d+ \S/.test(f.name), `name: ${f.name}`); ok(f.html.length > 200, `empty: ${f.name}`); ok(!/NaN|undefined|null|\[object/.test(f.html), `bad value in ${f.name}`); });
const texts = f => f.html.replace(/<svg[^>]*>|<\/svg>/g, ' ').split(/<[^>]+>/).map(t => t.replace(/\s+/g, ' ').trim()).filter(Boolean);
const by = l => frames.filter(f => id(f)[0] === l);
// a private event's own words appear only on the Events screen, its delete sheet and its editor
frames.forEach(f => { if (!'LDS'.includes(id(f)[0])) ok(!/Fixture change|Fixture note/.test(f.html), `private text outside the Events screen: ${f.name}`); });
ok(by('L').some(f => f.html.includes('Fixture change')), 'the Events screen shows the label in full');
// every event line outside the Events screen is "<kind or Private event> · <dates>"
const kinds = Object.values(M.STR.kind).concat(M.STR.privateEvent).join('|'), dateRe = '(since )?\\d{1,2}( [A-Z][a-z]{2})?( – \\d{1,2} [A-Z][a-z]{2})?( \\d{4})?';
const lineRe = new RegExp(`^(${kinds}) · ${dateRe}$`);
let lines = 0; frames.forEach(f => (f.html.match(/<div class="evl">.*?<\/div>/g) || []).forEach(l => { const t = l.replace(/<svg.*?<\/svg>|<[^>]+>/g, ''); ok(lineRe.test(t), `event line "${t}" in ${f.name}`); lines++; }));
ok(lines > 60, 'event lines found');
// the stage's own screens: every text node is a §11 string, a proposal, a fixture value, a date or a named host word
const tpl = s => '^' + s.replace(/[.*+?^${}()|[\]\\]/g, '\\$&').replace(/%@/g, '.+').replace(/%lld/g, '\\d+') + '$';
const allowed = leaves(M.STR).concat(leaves(M.PROPOSED)).map(tpl).concat(['^Fixture (trip|change|note)$', '^' + M.LONG_NOTE.replace(/[.]/g, '\\.') + '$',
  `^${dateRe}$`, '^From \\d{1,2} [A-Z][a-z]{2}$', '^(Mon|Tue|Wed|Thu|Fri|Sat|Sun) \\d{1,2} [A-Z][a-z]{2} \\d{4}$', '^[A-Z][a-z]+ 2031$', '^[MTWFS]$', '^[‹›⌄✓]$', '^\\d{1,2}$',
  '^(Settings|Body record|Niggle log)$']).map(r => new RegExp(r));
let nodes = 0; ['L', 'D', 'S', 'G'].forEach(l => by(l).forEach(f => texts(f).forEach(t => { ok(allowed.some(r => r.test(t)), `text not from §11 or the fixture: "${t}" in ${f.name}`); nodes++; })));
// tone: nothing causal, medical, urging or scored
frames.forEach(f => texts(f).forEach(t => ok(!/\bbecause\b|warning|\bshould\b|streak|remind|diagnos|symptom|\bsick\b|treatment|well done|don.t forget|missed your/i.test(t), `tone: "${t}" in ${f.name}`)));
// charts: no rule, band or target line; no zero bar; marks as computed
const plots = f => f.html.match(/<svg class="evplot".*?<\/svg>/g) || [];
let nplots = 0; frames.forEach(f => plots(f).forEach(p => { nplots++; ok(!/<line\b|stroke-dasharray|<rect(?![^>]*class="rb")/.test(p), `rule or band in ${f.name}`); ok(!/height="0"/.test(p), `zero bar in ${f.name}`); }));
const marks = n => plots(frames.find(f => id(f) === n)).map(p => (p.match(/class="evmark/g) || []).length);
eq(marks('M1'), [0]); eq(marks('M2'), [1]); eq(marks('M3'), [11]); eq(marks('M4'), [5]); eq(marks('M5'), [0]); eq(marks('M6'), [1]); eq(marks('M7'), [14]); eq(marks('M9'), [0]); eq(marks('M13'), [3]);
const m11 = M.dayWindow('sleep', '2031-04-28', 90, M.EVENTS); ok(marks('M11')[0] < m11.covered.filter(Boolean).length, 'M11 is thinned');
const m8 = plots(frames.find(f => id(f) === 'M8'))[0]; eq((m8.match(/class="rb"/g) || []).length, 28, 'M8: 28 bars for 30 days'); eq((m8.match(/stroke-opacity=".4"/g) || []).length, 2, 'M8: two not-measured rings');
ok(!/evplot/.test(frames.find(f => id(f) === 'N11').html) && !/evnote/.test(frames.find(f => id(f) === 'N11').html), 'N11: no note, no marks');
ok(!/evnote|evmark/.test(frames.find(f => id(f) === 'N1').html), 'N1: no events, nothing added');
ok(!/evnote/.test(frames.find(f => id(f) === 'N12').html) && /evmark/.test(frames.find(f => id(f) === 'N12').html), 'N12: no note, marks stay');
ok(!/evmark|evcap|evnote/.test(frames.find(f => id(f) === 'N14').html), 'N14: the Today card carries nothing');
ok(!frames.find(f => id(f) === 'H3').html.includes('>Events<'), 'H3: no row while off');
['L', 'S', 'M', 'C', 'N', 'G'].forEach(l => ok(by(l).some(f => f.cls === 'ax'), `no AX5 frame in group ${l}`));

/* 4. the browser path, run against a stub document: the three scripts in one shared scope, as index.html loads them.
      This catches a name clash or a load-order error that the node path cannot. It renders nothing. */
const vm = require('vm'); let boards = null, inserted = 0;
const box = { console, URLSearchParams, setTimeout, location: { search: '?static=1' },
  getComputedStyle: () => ({ getPropertyValue: () => '#808080' }),
  document: { documentElement: { classList: { add() {} } }, body: { insertAdjacentHTML() { inserted++; } }, querySelectorAll: () => [],
    getElementById: () => ({ set innerHTML(v) { boards = v; } }), createElementNS: () => ({ setAttribute() {}, appendChild() {} }), createElement: () => ({ style: {}, appendChild() {} }) } };
box.window = box; box.window.addEventListener = () => {}; vm.createContext(box);
['../system/noop.js', '../round6-scorecard/model.js', 'model.js', 'frames.js'].forEach(f => vm.runInContext(fs.readFileSync(path.join(__dirname, f), 'utf8'), box, { filename: f }));
ok(boards && inserted >= 1, `the page script wrote the boards (${inserted} icon inserts)`);
eq((boards.match(/<div class="board-title">S5 \/ /g) || []).length, frames.length, 'browser path draws every frame');
frames.forEach(f => ok(boards.includes(`<div class="board-title">${f.name}</div>`), `browser path is missing ${f.name}`));
const index = fs.readFileSync(path.join(__dirname, 'index.html'), 'utf8');
['../system/noop.css', '../round6-scorecard/scorecard.css', 'events.css', '../system/noop.js', '../round6-scorecard/model.js', 'model.js', 'frames.js'].forEach(f => ok(index.includes(`"${f}"`) && fs.existsSync(path.join(__dirname, f)), `index.html: ${f}`));
const css = ['../system/noop.css', '../round6-scorecard/scorecard.css', 'events.css'].map(f => fs.readFileSync(path.join(__dirname, f), 'utf8')).join('\n');
const used = new Set(); frames.forEach(f => (f.html.match(/class="[^"]*"/g) || []).forEach(c => c.slice(7, -1).split(/\s+/).filter(Boolean).forEach(x => used.add(x))));
const unstyled = [...used].filter(c => !new RegExp('\\.' + c + '(?![\\w-])').test(css) && !['evplot', 'evmark', 'open', 'area', 'stroke', 'pt', 'halo', 'rb', 'motion', 'num', 'evd', 'esheet', 'own', 'second', 'endt', 'e', 'x', 'on', 'notFired'].includes(c));
eq(unstyled, [], 'every class used by a frame has a style rule');

console.log(`frames: ${frames.length}`);
F.groups.forEach(g => console.log(`  ${g.title}: ${g.frames.length}`));
console.log(`plots: ${nplots}   event lines: ${lines}   text nodes checked against §11 and the fixture: ${nodes}`);
console.log(`README proposals check: ${readme ? 'done' : 'skipped (no README yet)'}`);
console.log('browser path (stub document): every frame written to #boards');
console.log(`OK: ${checks} checks passed`);
