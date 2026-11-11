/* Round S4 checks, run under Node (no browser): node design/round-s4-body-record/check.js
   1. the design model reproduces the specification's fixture tables (§13.2, §13.3, §13.4, §13.5);
   2. the fixture is the one Fixture Person: scan totals equal stage 1's weigh-ins (round 6's model);
   3. the frame builders run, and give the expected frame count, unique names and every state id of §10;
   4. every piece of text in every frame is a recorded string or fixture data, every specification string is in
      §10 or §11 of the specification, every reused app string is in the app's source or the stage 1 round, and
      every name is in the specification or the marker catalogue;
   5. the round's rules that can be checked without rendering (no chart, no notification, J9 equals J1).
   Exits non-zero on any failure. It does NOT view the frames. */
const fs = require('fs'), path = require('path'), assert = require('assert');
const M = require('./model.js'), F = require('./frames.js'), R6 = require('../round6-scorecard/model.js');
const repo = path.resolve(__dirname, '../..'), read = p => fs.readFileSync(path.join(repo, p), 'utf8');
let checks = 0; const ok = (c, msg) => { checks++; assert.ok(c, msg); }, eq = (a, b, msg) => { checks++; assert.deepStrictEqual(a, b, msg); };

/* ---- 1. the model against §13 ---- */
const rs = n => M.read({ A: M.SCAN_A, B: M.SCAN_B, C: M.SCAN_C }[n]);
const D = n => rs(n).derived, dv = x => x.value != null ? x.value : `notAvailable(${x.gap})`;
eq(['A', 'B', 'C'].map(n => [dv(D(n).armToLegLeanPercent), D(n).armsSource, dv(D(n).armSideDifferencePercent), dv(D(n).legSideDifferencePercent)]),
  [[50.0, 'printedTotal', -3.9, 0.0], [53.1, 'printedTotal', 0.0, 0.0], [54.4, 'sumOfSides', 0.0, 'notAvailable(missingComponent)']], '§13.2');
const c = (...v) => M.derive(Object.fromEntries(['armsLean', 'armLeftLean', 'armRightLean', 'legsLean', 'legLeftLean', 'legRightLean'].map((k, i) => [k, v[i]])));
eq(c(10, 4.9, 5.1, null, null, null).armToLegLeanPercent, { gap: 'missingComponent' }, '§13.2 legs removed');
eq(c(10, 4.9, 5.1, 0, 10, 10).armToLegLeanPercent, { gap: 'invalidComponent' }, '§13.2 legs zero');
// §13.3: [field id, earlier, later, delta, percent, direction] or [id, 'onlyEarlier' | 'onlyLater', value]
const T133 = [['totalMass', 100.0, 95.0, -5.0, -5.0, 'down'], ['fatMass', 30.0, 26.0, -4.0, -13.3, 'down'], ['leanMass', 67.0, 66.0, -1.0, -1.5, 'down'], ['boneMass', 3.00, 3.00, 0, 0.0, 'same'],
  ['fatFreeMass', 70.0, 69.0, -1.0, -1.4, 'down'], ['bodyFatPercent', 30.0, 27.4, -2.6, null, 'down'], ['visceralFatMass', 1000, 800, -200, -20.0, 'down'], ['visceralFatArea', 'onlyLater', 80],
  ['androidFatPercent', 36.0, 30.0, -6.0, null, 'down'], ['gynoidFatPercent', 30.0, 26.0, -4.0, null, 'down'], ['androidGynoidRatio', 1.20, 1.15, -0.05, -4.2, 'down'], ['armsLean', 10.00, 10.40, 0.40, 4.0, 'up'],
  ['armLeftLean', 4.90, 5.20, 0.30, 6.1, 'up'], ['armRightLean', 5.10, 5.20, 0.10, 2.0, 'up'], ['legsLean', 20.00, 19.60, -0.40, -2.0, 'down'], ['legLeftLean', 10.00, 9.80, -0.20, -2.0, 'down'],
  ['legRightLean', 10.00, 9.80, -0.20, -2.0, 'down'], ['trunkLean', 32.00, 31.50, -0.50, -1.6, 'down'], ['bmd', 'onlyEarlier', 1.2], ['tScore', 'onlyEarlier', 0.5], ['zScore', 'onlyEarlier', 0.4], ['rmr', 1900, 1850, -50, -2.6, 'down']];
const cmp = M.comparison(rs('A'), rs('B'));
eq(cmp.rows.map(r => r.change.kind === 'both' ? [r.field.id, r.change.earlier, r.change.later, r.change.delta, r.field.pct ? r.change.percent : null, r.change.direction] : [r.field.id, r.change.kind, r.change.value]), T133, '§13.3');
eq([cmp.armToLeg.earlier, cmp.armToLeg.later, cmp.armToLeg.delta, cmp.armToLeg.direction], [50.0, 53.1, 3.1, 'up'], '§13.3 arms to legs');
// §13.4 V3, V4, V5, V6
const stored = (s, p) => ({ ...s.values, ...p });
eq(M.mismatches(M.SCAN_A.values).concat(M.mismatches(M.SCAN_B.values), M.mismatches(M.SCAN_C.values)), [], 'the fixture scans are internally consistent');
eq(M.mismatches(stored(M.SCAN_B, { fatFreeMass: M.V3_FAT_FREE_TYPED })), ['fatFreeIsLeanBone'], 'V3');
eq(M.mismatches(stored(M.SCAN_B, { bodyFatPercent: 28.3 })), [], 'V4');
eq(M.mismatches(stored(M.SCAN_B, { bodyFatPercent: 31.0 })), ['bodyFatPercentIsFatShare'], 'V5');
eq(M.displayString(M.fieldToStored(M.field('totalMass'), 220.5, 'lb'), 1), '100.0', 'V6');
// §13.5
const dh = M.benchmark('bench_dead_hang_s');
eq([dh.sincePrevious.delta, dh.sinceFirst.delta, dh.rows.map(r => r.value)], [15, 25, [45, 30, 20]], '§13.5 dead hang');
eq(M.BLOOD_TYPED.map(b => { const x = M.blood(b[0]); return [x.key, `${x.shown} ${x.storedUnit}`, x.annotation]; }),
  [['hba1c', '37 mmol/mol', '5.5 %'], ['ldl', '2.59 mmol/L', '100 mg/dL'], ['hdl', '1.29 mmol/L', '50 mg/dL'], ['total_cholesterol', '5.17 mmol/L', '200 mg/dL'], ['triglycerides', '1.69 mmol/L', '150 mg/dL'],
    ['fasting_glucose', '5.0 mmol/L', '90 mg/dL'], ['ferritin', '80 µg/L', '80 ng/mL'], ['tsh', '2.00 mIU/L', null]], '§13.5 blood results');
eq([M.parseEntry('5,5', ','), M.parseEntry('5,5', '.'), M.parseEntry('1,500', '.'), M.parseEntry('nan'), M.parseEntry('5.')], [5.5, null, null, null, null], '§6.2 parseEntry');
eq([M.displayString(-0.04, 1), M.displayString(2.5, 0), M.displayString(-2.5, 0), M.displayString(NaN, 1)], ['0.0', '3', '-3', '—'], '§6.3 displayString');

/* ---- 2. one Fixture Person ---- */
const w1 = R6.fixtureInput({ today: '2031-06-04' }).weights;
M.WEIGH_INS.forEach(w => ok(w1.some(x => x.day === w.day && x.value === w.weightKg), `stage 1 weigh-in ${w.day}`));
[M.SCAN_A, M.SCAN_B, M.SCAN_C].forEach(s => { eq(s.values.totalMass, M.weighInOn(s.day).weightKg, `scan ${s.name} total is the stage 1 weight of its day`); });
eq([M.SCAN_A, M.SCAN_B, M.SCAN_C].map(s => [s.day, s.takenAt, M.weighInOn(s.day).week]), [['2031-01-08', 1925640000, 1], ['2031-04-09', 1933502400, 14], ['2031-05-28', 1937736000, 21]], '§13 scan days, instants and stage 1 weeks');

/* ---- 3. frames ---- */
const frames = F.frames(), names = frames.map(f => f.name);
eq(new Set(names).size, names.length, 'frame names are unique');
const ids = names.map(n => n.split(' ')[0]);
const want = ['G1', 'G2', 'G3', 'G4', 'G5', 'G5b', 'G6', 'G7', 'G8', 'G9', 'G10', ...Array.from({ length: 14 }, (_, i) => `H${i + 1}`), 'I1', 'I2', 'I3', 'I4', 'I5', 'I5b', 'I6', 'I7', 'I8',
  'J1', 'J2', 'J3', 'J4', 'J5', 'J6', 'J7', 'J8', 'J9', 'J10', 'J10b', 'J11', ...Array.from({ length: 8 }, (_, i) => `K${i + 1}`), ...Array.from({ length: 7 }, (_, i) => `L${i + 1}`)];
want.forEach(id => ok(ids.includes(id), `state ${id} of §10 has a frame`));
frames.forEach(f => ok(typeof f.html === 'string' && f.html.length > 200 && !/undefined|NaN|null|\[object/.test(f.html), `${f.name}: html is well formed`));
const EXPECTED = 72; eq(frames.length, EXPECTED, 'frame count');
const byId = id => frames.find(f => f.name.startsWith(id + ' '));
eq(byId('J9').html, byId('J1').html, 'J9 (entered out of order) is identical to J1');
ok(byId('H6').html.includes('nbtn strong">Save') && byId('O7').html.includes('nbtn strong off">Save'), 'H6 keeps Save enabled; O7 disables it');
['H1', 'H4', 'H5', 'H7', 'H10'].forEach(id => ok(byId(id).html.includes('nbtn strong off">Save'), `${id}: Save disabled`));
['H2', 'H3', 'H8', 'H9', 'H12'].forEach(id => ok(byId(id).html.includes('nbtn strong">Save'), `${id}: Save enabled`));
const H8 = 'You have a weigh-in this week.';
['H8', 'H9'].forEach(id => ok(byId(id).html.includes(H8), `${id}: weigh-in line shown`)); ['H1', 'H2', 'H3', 'H6', 'H7'].forEach(id => ok(!byId(id).html.includes(H8), `${id}: weigh-in line absent`));

/* ---- 4. strings ---- */
const spec = read('docs/personal/superapp/specs/stage-4.md'), lines = spec.split('\n');
const from = lines.findIndex(l => l.startsWith('## 10. Screens and states')), to = lines.findIndex(l => l.startsWith('## 12. Test plan'));
const specUi = lines.slice(from, to).join('\n').replace(/<[^>\n]+>/g, '%@');
const bad = [];
F.USED.spec.forEach(t => { checks++; if (!specUi.includes(t)) bad.push(`not in §10 or §11: "${t}"`); });
const app = ['Strand/Screens/LabBookView.swift', 'Strand/Screens/MarkerEditorView.swift', 'Strand/Screens/SettingsView.swift', 'StrandiOS/Redesign/RedesignHealthView.swift',
  'design/round6-scorecard/scorecard.js', 'docs/personal/superapp/specs/stage-1.md'].map(read).join('\n');
F.USED.app.forEach(t => t.split('%@').map(x => x.trim()).filter(Boolean).forEach(part => { checks++; if (!app.includes(part)) bad.push(`not found in the app or stage 1: "${part}" (of "${t}")`); }));
const catalog = read('Packages/StrandImport/Sources/StrandImport/MarkerCatalog.swift');
const humanised = Object.keys(M.BENCH_READINGS).map(k => k.split('_').map(w => w[0].toUpperCase() + w.slice(1)).join(' '));
F.USED.name.forEach(t => { checks++; if (!spec.includes(t) && !catalog.includes(`"${t}"`) && !humanised.includes(t) && t !== M.CUSTOM_BENCH.name) bad.push(`name not in the specification or the catalogue: "${t}"`); });
// every text node
const UNIT = 'ratio|kg|lb|g|cm|cm²|%|SD|kcal/day|g/cm²|s|reps|min|mmol/L|mg/dL|mmol/mol|µg/L|ng/mL|ng/L|pg/mL|pmol/L|mIU/L|µIU/mL';
const DATA = [/^[+−]?\d+([.,:]\d+)*%?$/, new RegExp(`^(${UNIT})$`), new RegExp(`^[+−]?\\d+([.,]\\d+)? (${UNIT})$`),
  /^(Mon|Tue|Wed|Thu|Fri|Sat|Sun) \d{1,2} (Jan|Feb|Mar|Apr|May|Jun|Jul|Aug|Sep|Oct|Nov|Dec)( \d{4})?$/, /^[›▾·+−]$/];
const known = new Set([...F.USED.spec.keys(), ...F.USED.prop.keys(), ...F.USED.app.keys(), ...F.USED.name.keys()]);
let nodes = 0;
frames.forEach(f => f.html.replace(/<svg[\s\S]*?<\/svg>/g, '').split(/<[^>]*>/).map(t => t.replace(/\s+/g, ' ').trim()).filter(Boolean).forEach(t => { nodes++; checks++;
  if (!known.has(t) && !DATA.some(r => r.test(t))) bad.push(`${f.name}: text that is neither a recorded string nor fixture data: "${t}"`); }));
// §11 strings the frames never use
const S11 = lines.slice(lines.findIndex(l => l.startsWith('## 11.')), to).filter(l => /^\| /.test(l)).slice(2).flatMap(l => l.split('|')[2].split(' · ').map(x => x.trim().replace(/<[^>]+>/g, '%@')));
const unused = S11.filter(s => ![...F.USED.spec.values()].includes(s));

/* ---- 5. rules that need no rendering ---- */
frames.forEach(f => { ok(!/class="(line|wk|arc|cbars|ring|rings)"|<line |data-ambient/.test(f.html), `${f.name}: no chart, ring or glow`); ok(!/notif/.test(f.html), `${f.name}: no notification`);
  ok(!/var\(--(recovery|rec-mid|sleep|strain|heart|hrv|stress)\)/.test(f.html), `${f.name}: no metric colour in markup`); });

if (bad.length) { console.error(bad.join('\n')); console.error(`\nFAILED: ${bad.length} problem(s)`); process.exit(1); }
console.log(`model: §13.2, §13.3 (22 rows + derived), V3–V6, §13.5 reproduced; scans A, B, C sit on stage 1 weigh-ins`);
console.log(`frames: ${frames.length} in ${F.G.length} groups, names unique, every §10 state id present (${want.length})`);
console.log(`text: ${nodes} text nodes audited; ${F.USED.spec.size} specification strings, ${F.USED.app.size} existing app strings, ${F.USED.name.size} names, ${F.USED.prop.size} proposals`);
console.log(`checks passed: ${checks}`);
if (process.argv.includes('--list')) { console.log('\nFRAMES'); F.G.forEach(g => { console.log(`\n${g.title}`); g.frames.forEach(f => console.log(`  S4 / ${f.name}`)); });
  console.log('\nPROPOSED STRINGS'); [...new Set(F.USED.prop.values())].forEach(t => console.log(`  ${t}`));
  console.log('\n§11 STRINGS NOT USED BY ANY FRAME'); unused.forEach(t => console.log(`  ${t}`)); }
