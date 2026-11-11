/* Round S6 checks, run without a browser:   node design/round-s6-niggle-timeline/check.js   (add --list for the frame list)
   1. the design model reproduces the tables of stage-6.md §13;
   2. every string in the SPEC table is in §11 of the specification, character for character, and every QUOTED string is in §10;
   3. the frame builders run, and the frame count and names are as expected;
   4. every piece of text in every frame is a specification string, a listed proposal, fixture text, a date or a number;
   5. the design rules that can be checked from markup hold.
   It does not render anything: layout, wrapping and overlap are NOT checked here. */
const fs = require('fs'), path = require('path'), assert = require('assert');
const M = require('./model.js'), S = require('./strings.js'), { G } = require('./frames.js');
const { S6FX: FX, s6Triage, s6Weekly, s6Timeline, s6TimelineInput, s6TimelineSpans, s6ScanDays, s6Complaint } = M;
const out = [], ok = s => out.push('ok    ' + s);
const eq = (a, b, what) => assert.deepStrictEqual(a, b, what);

/* ---------- 1. §13 ---------- */
const E = id => FX.entries.find(e => e.id === id), tri = (id, today) => s6Triage({ complaint: s6Complaint(E(id)), rules: FX.rules, today });
const row = (r) => [r.dayCount, r.status, r.ruleId, r.action, r.matchedRuleIds.join(','), r.ignoredUpdates, r.nextChange ? `${r.nextChange.dayCount} ${r.nextChange.day} ${r.nextChange.ruleId}` : null];
eq(row(tri('N1', '2031-03-01')), [10, 'resolved', null, null, '', 0, null], 'N1');
eq(row(tri('N2', '2031-03-03')), [1, 'noRuleMatches', null, null, '', 1, '5 2031-03-07 r-b'], 'N2a');
eq(row(tri('N2', '2031-03-07')), [5, 'matched', 'r-b', 'modify', 'r-b', 1, '30 2031-04-01 r-c'], 'N2b');
eq(row(tri('N2', '2031-03-21')), [19, 'matched', 'r-b', 'modify', 'r-b', 1, '30 2031-04-01 r-c'], 'N2c');
eq(row(tri('N2', '2031-03-22')), [20, 'matched', 'r-d', 'seeProfessional', 'r-b,r-d', 0, '30 2031-04-01 r-c'], 'N2d');
eq([tri('N2', '2031-03-21').currentTrend, tri('N2', '2031-03-21').stateDay, tri('N2', '2031-03-22').currentTrend, tri('N2', '2031-03-22').stateDay], ['unchanged', '2031-03-03', 'worsening', '2031-03-22'], 'N2 state');
eq(row(tri('N3', '2031-04-07')), [1, 'matched', 'r-e', 'modify', 'r-e', 0, '30 2031-05-06 r-c'], 'N3');
eq(row(tri('N5', '2031-05-14')), [10, 'noRuleMatches', null, null, '', 0, '30 2031-06-03 r-c'], 'N5');
eq(row(tri('N6', '2031-06-11')), [10, 'matched', 'r-a', 'watch', 'r-a', 0, '11 2031-06-12 null'], 'N6a');
eq(row(tri('N6', '2031-06-12')), [11, 'noRuleMatches', null, null, '', 0, '30 2031-07-01 r-c'], 'N6b');
ok('§13.2 triage: 10 rows (N1, N2a–d, N3, N5, N6a, N6b) and the N2 state days');

const wk = s6Weekly({ nights: FX.nights, firstWeekStart: '2031-01-06', today: '2031-02-05', minNightsPerWeek: 4, maxWeeks: 26 });
eq(wk.weeks.map(w => [w.weekStart, w.restingHrMean, w.restingHrNights, w.hrvMean, w.hrvNights, w.isCurrentWeek]), [
  ['2031-01-06', 60, 7, 50, 7, false], ['2031-01-13', 61, 4, 48, 4, false], ['2031-01-20', null, 3, null, 3, false],
  ['2031-01-27', 64.286, 7, 44.714, 7, false], ['2031-02-03', null, 3, null, 3, true]], '§13.3 weeks');
eq(wk.rejections, { nonFinite: 1, outOfRange: 1, invalidDay: 0, future: 1, duplicateDay: 0 }, '§13.3 counters');
eq([wk.restingHrChange.from, wk.restingHrChange.to, wk.restingHrChange.delta, wk.hrvChange.from, wk.hrvChange.to, wk.hrvChange.delta], [60, 64.286, 4.286, 50, 44.714, -5.286], '§13.3 changes');
ok('§13.3 weekly means, night counts, rejection counters and changes');

const tl = o => s6Timeline(s6TimelineInput(o)), sig = r => r.items.map(i => `${i.kind}${i.kind === 'checkpoint' ? ':' + FX.checkpoints[i.sourceIndex].id : ''} ${i.day.slice(5)} ${i.position}`);
const a = tl({ today: '2031-02-05' });
eq(sig(a), ['phaseStart 01-06 past', 'scan 01-08 past', 'checkpoint:C4 02-05 current', 'today 02-05 current', 'checkpoint:C2 02-10 upcoming', 'deload 02-17 upcoming',
  'checkpoint:C3 03-17 upcoming', 'checkpoint:C1 03-19 upcoming', 'dietBreak 03-24 upcoming', 'projection 05-27 upcoming', 'checkpoint:C5 06-02 upcoming', 'phaseStart 06-16 upcoming'], '§13.4 case 1');
eq(a.rejections, { invalidDay: 0, endBeforeStart: 0, futureScan: 1, duplicate: 0, nonFinite: 0, waypointBeyondTarget: 0 }, 'case 1 rejections');
const c1 = a.items.find(i => i.waypointWeightKg != null), c5 = a.items.find(i => i.category === 'targetDate');
eq([c1.waypointWeightKg, c1.isApproximate, c1.targetWeightKg, c5.phaseIndex, c5.waypointWeightKg, c5.targetWeightKg, a.items[0].targetWeightKg], [96, true, null, 0, null, null, 94], 'case 1 fields');
const b = tl({ today: '2031-03-24' });
eq(sig(b), ['phaseStart 01-06 past', 'scan 01-08 past', 'checkpoint:C4 02-05 past', 'checkpoint:C2 02-10 past', 'deload 02-17 past', 'scan 03-17 past', 'checkpoint:C1 03-19 past',
  'dietBreak 03-24 current', 'today 03-24 current', 'projection 05-27 upcoming', 'checkpoint:C5 06-02 upcoming', 'phaseStart 06-16 upcoming'], '§13.4 case 2');
eq(b.rejections.duplicate, 1, 'case 2 duplicate');
const c = tl({ today: '2031-02-20', events: 'off', projection: null });
eq([c.items.some(i => ['deload', 'dietBreak', 'projection'].includes(i.kind)), c.events, c.rejections.futureScan], [false, 'off', 1], '§13.4 case 3');
const v96 = tl({ today: '2031-02-05', phases: [{ ...FX.phases[0], targetWeightKg: 96.0 }, FX.phases[1]] }), v959 = tl({ today: '2031-02-05', phases: [{ ...FX.phases[0], targetWeightKg: 95.9 }, FX.phases[1]] });
eq([v96.items.some(i => i.waypointWeightKg != null), v96.rejections.waypointBeyondTarget, v96.items[0].targetWeightKg, sig(v96).length, v959.items.find(i => i.category === 'weightWaypoint').waypointWeightKg, v959.rejections.waypointBeyondTarget],
  [false, 1, 96, 12, 96, 0], '§13.4 changed target');
eq(s6TimelineSpans(FX.events), [{ kind: 'deload', startDay: '2031-02-17', endDay: '2031-02-23' }, { kind: 'dietBreak', startDay: '2031-03-24', endDay: null }], 'adapter spans');
eq(s6ScanDays(FX.scans), ['2031-01-08', '2031-03-17'], 'adapter scan days');
ok('§13.4 timeline: three cases, the changed-target variant, the adapter fixture');

/* ---------- 2. strings against the specification ---------- */
const spec = fs.readFileSync(path.join(__dirname, '../../docs/personal/superapp/specs/stage-6.md'), 'utf8');
const s11 = spec.slice(spec.indexOf('## 11. User-facing strings'), spec.indexOf('## 12. Test plan')), s10 = spec.slice(spec.indexOf('## 10. Screens and states'), spec.indexOf('## 11. User-facing strings'));
const missing = Object.entries(S.S6_SPEC).filter(([, v]) => !s11.includes(`"${v}"`)), missingQ = Object.entries(S.S6_QUOTED).filter(([, v]) => !s10.includes(`"${v}"`));
eq(missing, [], 'SPEC strings not found verbatim in §11'); eq(missingQ, [], 'QUOTED strings not found in §10');
ok(`${Object.keys(S.S6_SPEC).length} SPEC strings found verbatim in §11; ${Object.keys(S.S6_QUOTED).length} QUOTED strings found in §10`);
const all11 = [...s11.matchAll(/"([^"]+)"/g)].map(m => m[1]), spv = new Set(Object.values(S.S6_SPEC));
const undrawn = [...new Set(all11)].filter(s => !spv.has(s));

/* ---------- 3. frames ---------- */
const frames = G.flatMap(g => g.frames), names = frames.map(f => 'S6 / ' + f.name);
eq(new Set(names).size, names.length, 'duplicate frame name');
frames.forEach(f => assert(/^[A-Z]\d*(\.\d+)?\d* \S/.test(f.name) && f.html.length > 200, 'bad frame ' + f.name));
const perGroup = {}; frames.forEach(f => { const k = f.id.replace(/[\d.]+$/, ''); perGroup[k] = (perGroup[k] || 0) + 1; });
eq(perGroup, { A: 16, B: 9, C: 10, D: 8, E: 5, F: 12, G: 16, H: 12, P: 6 }, 'frames per group');
eq(frames.filter(f => f.cls === 'ax').map(f => f.id), ['A16', 'B9', 'C10', 'D8', 'E5', 'F12', 'G16', 'H12'], 'AX5 frames');
ok(`${frames.length} frames, names unique, each "S6 / <id> <title>"; one AX5 frame for each of the 8 screens`);

/* ---------- 4. every text node ---------- */
const esc = s => s.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
const rx = tbl => Object.values(tbl).map(v => new RegExp('^' + esc(v).replace(/%@/g, '(.+)').replace(/%lld/g, '(\\d+)') + '$'));
const R = { spec: rx(S.S6_SPEC), quoted: rx(S.S6_QUOTED), prop: rx(S.S6_PROP) };
const DATE = /^((Mon|Tue|Wed|Thu|Fri|Sat|Sun) )?\d{1,2} (Jan|Feb|Mar|Apr|May|Jun|Jul|Aug|Sep|Oct|Nov|Dec)$/;
const VALUE = [/^[+−]?\d+(\.\d+)?$/, /^\d+\.\d kg$/, /^—$/, /^›$/, DATE];
const tally = { spec: 0, quoted: 0, prop: 0, fixture: 0, value: 0 }, unmatched = [];
const classify = s => R.spec.some(r => r.test(s)) ? 'spec' : R.quoted.some(r => r.test(s)) ? 'quoted' : R.prop.some(r => r.test(s)) ? 'prop' : /^Fixture /.test(s) ? 'fixture' : VALUE.some(r => r.test(s)) ? 'value' : null;
frames.forEach(f => f.html.split(/<[^>]+>/).map(s => s.trim()).filter(Boolean).forEach(node => {
  const whole = classify(node);
  (whole ? [node] : node.split(' · ')).forEach(part => { const k = whole || classify(part.trim()); if (k) tally[k]++; else unmatched.push(`${f.id}: "${part}"`); }); }));
eq(unmatched, [], 'text that is neither a specification string, a listed proposal, fixture text, a date nor a number');
ok(`text pieces: ${tally.spec} specification (§11), ${tally.quoted} quoted in §10, ${tally.prop} proposals, ${tally.fixture} fixture text, ${tally.value} dates and numbers; 0 unmatched`);

/* ---------- 5. design rules visible in markup ---------- */
const html = frames.map(f => f.html).join('\n'), words = html.replace(/<[^>]+>/g, ' ');
frames.forEach(f => (f.html.match(/<svg class="wk"[\s\S]*?<\/svg>/g) || []).forEach(svg => {
  const tags = new Set([...svg.matchAll(/<([a-zA-Z]+)/g)].map(m => m[1]));
  ['line', 'rect', 'polyline', 'polygon'].forEach(tg => assert(!tags.has(tg), `${f.id}: a chart contains <${tg}>`));
  [...svg.matchAll(/<path class="stroke" d="([^"]+)"/g)].forEach(m => assert(/ C/.test(m[1]) && !/[HV]/.test(m[1]), `${f.id}: a chart line is not a smooth curve`)); }));
ok(`${(html.match(/<svg class="wk"/g) || []).length} charts: only a smooth line, a gradient area, points and axis labels; no rule, band or target line`);
assert(!/var\(--(recovery|rec-mid|rec-low|sleep|strain|heart|hrv|sig-)/.test(html) && !/#(2FD27A|FFC83D|FF5A4F|3A9BFF|8F7DFF|FF4D6B|47C8F5)/i.test(html), 'a semantic colour is used in frame markup');
ok('no semantic colour in any frame\'s markup (labels, actions and both curves are neutral; Delete and invalid fields take red from the round 6 styles)');
const banned = /\b(diagnos\w*|overdue|warning|streak|elevated|suppressed|abnormal|normal|good|bad|should|must|injur\w*|treat\w*|cause[sd]?|risk\w*)\b/gi;
const hits = (words.replace(new RegExp(esc(S.S6_SPEC.disclaimer), 'g'), '').match(banned) || []);
eq(hits, [], 'judgement, medical or nagging wording');
ok('no diagnosis, cause, treatment, warning, "overdue", streak or good/bad wording (the one "not a diagnosis" sentence of §11 aside)');
const Fframes = frames.filter(f => f.id[0] === 'F');
Fframes.forEach(f => assert(!/>\s*0(\.0)?\s*</.test(f.html), `${f.id}: a zero stands where nothing was measured`));
assert(Fframes.some(f => f.html.includes(S.S6_SPEC.notMeasured)) && Fframes.some(f => f.html.includes('>—<')), 'not measured states missing');
ok('recovery context: no 0 is drawn for an unmeasured week; "—" and "Not measured yet" are');
frames.filter(f => /Estimated /.test(f.html)).forEach(f => assert(f.html.includes(`>${S.S6_SPEC.estimate}<`), `${f.id}: an estimate without its tag`));
ok('every frame that shows the projection tags it "estimate"');
assert(!/notif|widget/i.test(html), 'a notification or widget is drawn'); ok('no notification and no widget is drawn (stage 6 adds none, §10.9)');
frames.filter(f => f.id[0] === 'G' || f.id.startsWith('P3')).forEach(f => assert(!/Fixture note|private/i.test(f.html), `${f.id}: an event note or a private marker on the timeline`));
ok('timeline: no event label or note, and nothing marks a private event');
frames.filter(f => f.id[0] === 'G' || f.id[0] === 'H' || f.id.startsWith('P3')).forEach(f => (f.html.match(/Waypoint [^<]*|Fixture waypoint[^<]*/g) || []).forEach(s => assert(!/target/i.test(s), `${f.id}: a waypoint worded as a target`)));
ok('a waypoint row never carries the word "target"');

console.log(out.join('\n'));
const used = [...S.s6Used];
console.log(`\nSPEC strings not drawn in any frame (${Object.keys(S.S6_SPEC).filter(k => !used.includes(k)).length}): ${Object.keys(S.S6_SPEC).filter(k => !used.includes(k)).map(k => `"${S.S6_SPEC[k]}"`).join(', ') || 'none'}`);
console.log(`§11 strings with no entry in the SPEC table (${undrawn.length}): ${undrawn.map(s => `"${s}"`).join(', ') || 'none'}`);
console.log(`PROP strings defined but not drawn: ${Object.keys(S.S6_PROP).filter(k => !used.includes(k)).join(', ') || 'none'}`);
if (process.argv.includes('--list')) { console.log(''); G.forEach(g => { console.log(g.title); g.frames.forEach(f => console.log('  S6 / ' + f.name)); }); }
if (process.argv.includes('--proposals')) { console.log(''); Object.entries(S.S6_PROP).filter(([k]) => used.includes(k)).forEach(([k, v]) => console.log(`  ${k}: "${v}"`)); }
console.log(`\nALL CHECKS PASSED · ${frames.length} frames`);
