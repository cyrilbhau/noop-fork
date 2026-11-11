/* Round S6 design model, written from docs/personal/superapp/specs/stage-6.md §6 and §7, with the §13 fixture.
   It exists so that every label, day count, weekly mean and timeline row drawn in a frame is computed, not typed.
   It is a mockup aid: it is NOT the implementation and it has no tests of its own beyond check.js.
   EVERY VALUE IS SYNTHETIC ("Fixture Person" does not exist). Loadable in the browser (globals) and in Node. */

/* ---------- CanonicalDay (§6.0): "yyyy-MM-dd", years 0001–9999, a real date ---------- */
const S6Day = {
  number(key) {
    if (typeof key !== 'string' || !/^\d{4}-\d{2}-\d{2}$/.test(key)) return null;
    const y = +key.slice(0, 4), m = +key.slice(5, 7), d = +key.slice(8);
    if (y < 1) return null;
    const t = new Date(0); t.setUTCFullYear(y, m - 1, d);
    if (t.getUTCFullYear() !== y || t.getUTCMonth() !== m - 1 || t.getUTCDate() !== d) return null;
    return Math.round(t.getTime() / 864e5);
  },
  key(n) { const lo = S6Day.number('0001-01-01'), hi = S6Day.number('9999-12-31'); const t = new Date(Math.max(lo, Math.min(hi, n)) * 864e5);
    return `${String(t.getUTCFullYear()).padStart(4, '0')}-${String(t.getUTCMonth() + 1).padStart(2, '0')}-${String(t.getUTCDate()).padStart(2, '0')}`; },
  daysBetween(a, b) { const x = S6Day.number(a), y = S6Day.number(b); return x == null || y == null ? null : y - x; },
  weekStart(key) { const n = S6Day.number(key); return n == null ? null : S6Day.key(n - (new Date(n * 864e5).getUTCDay() + 6) % 7); },
  add(key, k) { return S6Day.key(S6Day.number(key) + k); },
};
const s6quantize = x => Math.sign(x) * Math.floor(Math.abs(x) * 1000 + 0.5) / 1000;   // CutScorecard.quantize (stage 1 §7)

/* ---------- §7.1 NiggleTriage ----------
   opt is for the two option frames only: { firstMatch: true } (Q2's alternative), { dayZero: true } (Q3's alternative). */
const S6_SEVERITY = { watch: 0, modify: 1, seeProfessional: 2 };
function s6RulesAreValid(rules) {
  const ids = new Set();
  return rules.every(r => { if (!r.id || ids.has(r.id)) return false; ids.add(r.id);
    if (r.fromDay != null && r.fromDay < 1) return false;
    return !(r.throughDay != null && r.throughDay < (r.fromDay == null ? 1 : r.fromDay)); });
}
function s6Triage(input, opt = {}) {
  const c = input.complaint, rules = input.rules, today = input.today, D = S6Day, one = opt.dayZero ? 0 : 1;
  const bad = invalid => ({ status: 'invalidInput', invalid, isOpen: false, dayCount: null, currentTrend: c.trend, currentWeakness: c.weakness, stateDay: null,
    ruleId: null, action: null, matchedRuleIds: [], nextChange: null, ignoredUpdates: 0 });
  if (D.number(today) == null) return bad('today');
  if (!s6RulesAreValid(rules)) return bad('rules');
  if (D.number(c.onsetDay) == null) return bad('onsetDay');
  if (c.onsetDay > today) return bad('onsetAfterToday');
  if (c.resolvedDay != null) {
    if (D.number(c.resolvedDay) == null) return bad('resolvedDay');
    if (c.resolvedDay < c.onsetDay) return bad('resolvedBeforeOnset');
    if (c.resolvedDay > today) return bad('resolvedAfterToday');
  }
  let ignored = 0, cur = null;
  (c.updates || []).forEach(u => {
    if (D.number(u.day) == null || u.day < c.onsetDay || u.day > today || (c.resolvedDay != null && u.day > c.resolvedDay)) { ignored++; return; }
    if (!cur || u.day > cur.day || (u.day === cur.day && u.sequence >= cur.sequence)) cur = u;
  });
  const base = { invalid: null, currentTrend: cur ? cur.trend : c.trend, currentWeakness: cur ? cur.weakness : c.weakness, stateDay: cur ? cur.day : c.onsetDay,
    ruleId: null, action: null, matchedRuleIds: [], nextChange: null, ignoredUpdates: ignored };
  if (c.resolvedDay != null) return { ...base, status: 'resolved', isOpen: false, dayCount: D.daysBetween(c.onsetDay, c.resolvedDay) + one };
  const n = D.daysBetween(c.onsetDay, today) + 1;                       // the rules always count the onset day as day 1
  const shown = n - 1 + one;                                             // what the screen prints
  if (!rules.length) return { ...base, status: 'noRulesEntered', isOpen: true, dayCount: shown };
  const fits = r => (!r.characters.length || r.characters.includes(c.character)) && (!r.trends.length || r.trends.includes(base.currentTrend))
    && (r.weakness == null || r.weakness === base.currentWeakness);
  const matchesAt = (r, k) => fits(r) && k >= (r.fromDay == null ? 1 : r.fromDay) && (r.throughDay == null || k <= r.throughDay);
  const winnerAt = k => { let w = null; for (const r of rules) { if (!matchesAt(r, k)) continue;
    if (!w) { w = r; if (opt.firstMatch) break; } else if (S6_SEVERITY[r.action] > S6_SEVERITY[w.action]) w = r; } return w; };
  const matched = rules.filter(r => matchesAt(r, n)).map(r => r.id), win = winnerAt(n);
  const cand = new Set();
  rules.filter(fits).forEach(r => { if (r.fromDay != null && r.fromDay > n) cand.add(r.fromDay);
    if (r.throughDay != null && r.throughDay >= n && r.throughDay < Number.MAX_SAFE_INTEGER) cand.add(r.throughDay + 1); });
  let next = null;
  for (const k of [...cand].sort((a, b) => a - b)) { const w = winnerAt(k);
    if ((w ? w.id : null) !== (win ? win.id : null)) { const dn = D.number(c.onsetDay) + k - 1;
      if (dn <= D.number('9999-12-31')) next = { dayCount: k - 1 + one, day: D.key(dn), ruleId: w ? w.id : null, action: w ? w.action : null };
      break; } }
  return { ...base, status: win ? 'matched' : 'noRuleMatches', isOpen: true, dayCount: shown, ruleId: win ? win.id : null, action: win ? win.action : null,
    matchedRuleIds: matched, nextChange: next };
}

/* ---------- §7.2 CutStressTrend ---------- */
const S6_BOUNDS = { restingHr: [30, 120], hrv: [5, 250] };   // Baselines.restingHRCfg / hrvCfg, minVal…maxVal (Baselines.swift:206-209)
function s6Weekly(input) {
  const D = S6Day, min = input.minNightsPerWeek == null ? 4 : input.minNightsPerWeek, maxW = input.maxWeeks == null ? 26 : input.maxWeeks, today = input.today;
  const rej = { nonFinite: 0, outOfRange: 0, invalidDay: 0, future: 0, duplicateDay: 0 };
  const out = invalidInput => ({ weeks: [], restingHrChange: null, hrvChange: null, rejections: rej, invalidInput });
  if (D.number(today) == null) return out('today');
  if (min < 1 || min > 7 || maxW < 1) return out('parameters');
  const f = input.firstWeekStart;
  if (f != null && (D.number(f) == null || D.weekStart(f) !== f || f > today)) return out('firstWeekStart');
  const byDay = new Map();
  input.nights.forEach(nt => { if (D.number(nt.day) == null) { rej.invalidDay++; return; } if (nt.day > today) { rej.future++; return; }
    if (byDay.has(nt.day)) rej.duplicateDay++; byDay.set(nt.day, nt); });
  const admit = (v, k) => { if (v == null) return null; if (!Number.isFinite(v)) { rej.nonFinite++; return null; }
    if (v < S6_BOUNDS[k][0] || v > S6_BOUNDS[k][1]) { rej.outOfRange++; return null; } return v; };
  const nights = [...byDay.values()].map(nt => ({ day: nt.day, restingHr: admit(nt.restingHr, 'restingHr'), hrv: admit(nt.hrv, 'hrv') })).sort((a, b) => a.day < b.day ? -1 : 1);
  const last = D.weekStart(today), bound = D.add(last, -7 * (maxW - 1));
  let start = f;
  if (start == null) { const first = nights.find(nt => nt.restingHr != null || nt.hrv != null); if (!first) return out(null); start = D.weekStart(first.day); }
  if (start < bound) start = bound;
  const weeks = [];
  for (let w = start; w <= last; w = D.add(w, 7)) {
    const mine = nights.filter(nt => D.weekStart(nt.day) === w), stat = k => { const v = mine.map(nt => nt[k]).filter(x => x != null);
      return [v.length >= min ? s6quantize(v.reduce((a, b) => a + b, 0) / v.length) : null, v.length]; };
    const [rm, rn] = stat('restingHr'), [hm, hn] = stat('hrv');
    weeks.push({ weekStart: w, restingHrMean: rm, restingHrNights: rn, hrvMean: hm, hrvNights: hn, isCurrentWeek: w === last });
  }
  const change = k => { const has = weeks.filter(w => w[k] != null); if (has.length < 2) return null; const a = has[0], b = has[has.length - 1];
    return { fromWeekStart: a.weekStart, toWeekStart: b.weekStart, from: a[k], to: b[k], delta: s6quantize(b[k] - a[k]) }; };
  return { weeks, restingHrChange: change('restingHrMean'), hrvChange: change('hrvMean'), rejections: rej, invalidInput: null };
}

/* ---------- §7.3 CheckpointTimeline ---------- */
const S6_KIND_ORDER = { phaseStart: 0, scan: 1, checkpoint: 2, dietBreak: 3, deload: 4, today: 5, projection: 6 };
function s6GoverningPhaseIndex(day, phases) {
  if (S6Day.number(day) == null) return null; let g = null;
  phases.forEach((p, i) => { if (S6Day.number(p.startDay) != null && p.startDay <= day && (g == null || p.startDay >= phases[g].startDay)) g = i; });
  return g;
}
const s6GoodWeight = w => w != null && Number.isFinite(w) && w > 0;
function s6WaypointIssue(weightKg, day, phases) {
  if (!s6GoodWeight(weightKg)) return 'nonFinite';
  const g = s6GoverningPhaseIndex(day, phases); if (g == null || !s6GoodWeight(phases[g].targetWeightKg)) return null;
  const t = phases[g].targetWeightKg;
  return (phases[g].isCut ? weightKg <= t : weightKg === t) ? 'atOrBeyondTarget' : null;
}
function s6Timeline(input) {
  const D = S6Day, today = input.today, rej = { invalidDay: 0, endBeforeStart: 0, futureScan: 0, duplicate: 0, nonFinite: 0, waypointBeyondTarget: 0 };
  if (D.number(today) == null) return { items: [], todayIndex: null, scans: input.scans, events: input.events, rejections: rej, invalidToday: true };
  const items = [], pos = d => d < today ? 'past' : d === today ? 'current' : 'upcoming';
  const item = (kind, day, more) => items.push({ kind, day, endDay: null, isOpenEnded: false, position: pos(day), sourceIndex: null, isApproximate: false, isDone: false,
    isEstimate: false, category: null, targetWeightKg: null, waypointWeightKg: null, phaseIndex: null, phaseIsCut: null, ...more });
  input.phases.forEach((p, i) => { if (D.number(p.startDay) == null) { rej.invalidDay++; return; }
    let t = p.targetWeightKg; if (t != null && !s6GoodWeight(t)) { rej.nonFinite++; t = null; }
    item('phaseStart', p.startDay, { sourceIndex: i, phaseIsCut: p.isCut, targetWeightKg: t == null ? null : t }); });
  const scanDays = new Set();
  if (input.scans === 'on') input.scanDays.forEach((d, i) => { if (D.number(d) == null) { rej.invalidDay++; return; } if (d > today) { rej.futureScan++; return; }
    if (scanDays.has(d)) { rej.duplicate++; return; } scanDays.add(d); item('scan', d, { sourceIndex: i }); });
  const targetPhases = new Set();
  input.checkpoints.forEach((c, i) => {
    if (D.number(c.day) == null) { rej.invalidDay++; return; }
    let wp = null, phaseIndex = null;
    if (c.category === 'weightWaypoint') { const issue = s6WaypointIssue(c.waypointWeightKg, c.day, input.phases);
      if (issue === 'nonFinite') rej.nonFinite++; else if (issue === 'atOrBeyondTarget') rej.waypointBeyondTarget++; else wp = c.waypointWeightKg; }
    if (c.category === 'targetDate' && c.phaseStartDay != null) { if (targetPhases.has(c.phaseStartDay)) { rej.duplicate++; return; } targetPhases.add(c.phaseStartDay);
      const k = input.phases.findIndex(p => D.number(p.startDay) != null && p.startDay === c.phaseStartDay); phaseIndex = k < 0 ? null : k; }
    if (c.category === 'scan' && scanDays.has(c.day)) { rej.duplicate++; return; }
    item('checkpoint', c.day, { sourceIndex: i, isApproximate: c.isApproximate, isDone: c.isDone, category: c.category, waypointWeightKg: wp, phaseIndex });
  });
  if (input.events === 'on') input.spans.forEach((s, i) => { if (D.number(s.startDay) == null) { rej.invalidDay++; return; }
    if (s.endDay != null) { if (D.number(s.endDay) == null) { rej.invalidDay++; return; } if (s.endDay < s.startDay) { rej.endBeforeStart++; return; } }
    item(s.kind, s.startDay, { sourceIndex: i, endDay: s.endDay == null ? null : s.endDay, isOpenEnded: s.endDay == null,
      position: s.startDay > today ? 'upcoming' : s.endDay != null && s.endDay < today ? 'past' : 'current' }); });
  const pj = input.projection;
  if (pj && pj.status === 'projected' && D.number(pj.targetDay) != null) item('projection', pj.targetDay, { isEstimate: true });
  item('today', today, {});
  items.sort((a, b) => (D.number(a.day) - D.number(b.day)) || (S6_KIND_ORDER[a.kind] - S6_KIND_ORDER[b.kind]) || ((a.sourceIndex || 0) - (b.sourceIndex || 0)));
  return { items, todayIndex: items.findIndex(i => i.kind === 'today'), scans: input.scans, events: input.events, rejections: rej, invalidToday: false };
}

/* §8.4 adapters: a private event has no row; only diet breaks and deloads become spans; scan days are de-duplicated. */
const s6TimelineSpans = events => events.filter(e => !e.sensitive).filter(e => e.kind === 'dietBreak' || e.kind === 'deload').map(e => ({ kind: e.kind, startDay: e.startDay, endDay: e.endDay == null ? null : e.endDay }));
const s6ScanDays = scans => [...new Set(scans.map(s => s.day))];

/* §9.3 CheckpointTimelineSettings.issue: the first issue, in the order of CheckpointIssue's cases. phases are stored phases
   { name, startDay, isCut, targetWeightKg }. */
function s6CheckpointIssue(cp, others, phases) {
  const title = (cp.title || '').trim(), wp = cp.category === 'weightWaypoint', td = cp.category === 'targetDate';
  if (!title) return 'emptyTitle';
  if (title.length > 60) return 'titleTooLong';
  if (S6Day.number(cp.day) == null) return 'invalidDay';
  if (wp && cp.waypointWeightKg == null) return 'weightMissing';
  if (!wp && cp.waypointWeightKg != null) return 'weightNotAllowed';
  if (wp && !(cp.waypointWeightKg >= 30 && cp.waypointWeightKg <= 250)) return 'weightOutOfRange';
  if (wp && s6WaypointIssue(cp.waypointWeightKg, cp.day, phases) === 'atOrBeyondTarget') return 'waypointAtOrBeyondTarget';
  if (td && (cp.phaseStartDay == null || !phases.some(p => p.startDay === cp.phaseStartDay))) return 'phaseMissing';
  if (!td && cp.phaseStartDay != null) return 'phaseNotAllowed';
  if (td && cp.day <= cp.phaseStartDay) return 'targetDateNotAfterPhaseStart';
  if (td && others.some(o => o.category === 'targetDate' && o.phaseStartDay === cp.phaseStartDay)) return 'phaseAlreadyHasTargetDate';
  return null;
}

/* ---------- §13 fixture ---------- */
const S6FX = {
  // §13.1. `note` is not in §13.1 (the stored example has an empty note); "Fixture rule note X" is added so the detail screen can show one.
  professionalRule: 'Fixture rule text.',
  rules: [
    { id: 'r-a', label: 'Fixture label A', action: 'watch', characters: ['diffuse'], trends: ['easing'], weakness: null, fromDay: 1, throughDay: 10, note: 'Fixture rule note A' },
    { id: 'r-b', label: 'Fixture label B', action: 'modify', characters: ['positional'], trends: [], weakness: null, fromDay: 5, throughDay: null, note: 'Fixture rule note B' },
    { id: 'r-c', label: 'Fixture label C', action: 'seeProfessional', characters: [], trends: [], weakness: null, fromDay: 30, throughDay: null, note: 'Fixture rule note C' },
    { id: 'r-d', label: 'Fixture label D', action: 'seeProfessional', characters: [], trends: ['worsening'], weakness: null, fromDay: 20, throughDay: null, note: 'Fixture rule note D' },
    { id: 'r-e', label: 'Fixture label E', action: 'modify', characters: ['localised'], trends: [], weakness: true, fromDay: 1, throughDay: null, note: 'Fixture rule note E' },
  ],
  // §13.2. N7 is the "second Fixture location B, right, onset 2031-06-16"; its character and trend are not given there and repeat N2's.
  entries: [
    { id: 'N1', kind: 'complaint', location: 'Fixture location A', side: 'left', character: 'diffuse', trend: 'easing', weakness: false, onsetDay: '2031-02-03', resolvedDay: '2031-02-12', note: 'Fixture note', updates: [] },
    { id: 'N2', kind: 'complaint', location: 'Fixture location B', side: 'right', character: 'positional', trend: 'unchanged', weakness: false, onsetDay: '2031-03-03', resolvedDay: null, note: 'Fixture note',
      updates: [{ day: '2031-03-22', sequence: 1, trend: 'worsening', weakness: false, note: '' }] },
    { id: 'N3', kind: 'complaint', location: 'Fixture location C', side: 'both', character: 'localised', trend: 'unchanged', weakness: true, onsetDay: '2031-04-07', resolvedDay: null, note: '', updates: [] },
    { id: 'N4', kind: 'observation', location: 'Fixture observation', side: 'notApplicable', character: 'other', trend: 'notRecorded', weakness: false, onsetDay: '2031-01-13', resolvedDay: null, note: 'Fixture note', updates: [] },
    { id: 'N5', kind: 'complaint', location: 'Fixture location D', side: 'right', character: 'diffuse', trend: 'notRecorded', weakness: false, onsetDay: '2031-05-05', resolvedDay: null, note: '', updates: [] },
    { id: 'N6', kind: 'complaint', location: 'Fixture location E', side: 'left', character: 'diffuse', trend: 'easing', weakness: false, onsetDay: '2031-06-02', resolvedDay: null, note: '', updates: [] },
    { id: 'N7', kind: 'complaint', location: 'Fixture location B', side: 'right', character: 'positional', trend: 'unchanged', weakness: false, onsetDay: '2031-06-16', resolvedDay: null, note: '', updates: [] },
  ],
  paused: [
    { id: 'p1', exercise: 'Fixture Press', pausedDay: '2031-03-10', reason: 'Fixture reason A', until: 'Fixture until text', niggleId: 'N2', resumedDay: null },
    { id: 'p2', exercise: 'Fixture Row', pausedDay: '2031-01-20', reason: 'Fixture reason B', until: null, niggleId: null, resumedDay: '2031-02-10' },
  ],
  // §13.3. The values of the 2031-02-09 and 2030-12-30 extra nights are not given there; they repeat their neighbours' values.
  nights: (() => { const out = [], put = (start, rhr, hrv) => rhr.forEach((v, i) => out.push({ day: S6Day.add(start, i), restingHr: v, hrv: hrv[i] }));
    put('2031-01-06', [60, 60, 60, 60, 60, 60, 60], [50, 50, 50, 50, 50, 50, 50]);
    put('2031-01-13', [61, 61, 61, 61], [48, 48, 48, 48]);
    put('2031-01-20', [62, 62, 62], [47, 47, 47]);
    put('2031-01-27', [63, 63, 64, 64, 65, 65, 66], [46, 46, 45, 45, 44, 44, 43]);
    put('2031-02-03', [64, 64, 64], [45, 45, 45]);
    out.push({ day: '2031-01-17', restingHr: 500, hrv: null }, { day: '2031-01-18', restingHr: null, hrv: NaN },
      { day: '2031-02-09', restingHr: 64, hrv: 45 }, { day: '2030-12-30', restingHr: 60, hrv: 50 });
    return out; })(),
  // Not in stage 6 §13: the typical range comes from ChargeTypicalBand in the app. These are the Fixture Person's values in the
  // stage 2 specification's packet example (stage-2.md, "typical 52 to 56" bpm and "typical 51 to 64" ms).
  typical: { restingHr: [52, 56], hrv: [51, 64] },
  // §13.4
  phases: [{ name: 'Fixture cut', startDay: '2031-01-06', isCut: true, targetWeightKg: 94.0 }, { name: 'Fixture hold', startDay: '2031-06-16', isCut: false, targetWeightKg: null }],
  checkpoints: [
    { id: 'C1', title: 'Fixture waypoint', category: 'weightWaypoint', day: '2031-03-19', isApproximate: true, waypointWeightKg: 96.0, phaseStartDay: null, isDone: false },
    { id: 'C2', title: 'Fixture panel', category: 'bloodPanel', day: '2031-02-10', isApproximate: false, waypointWeightKg: null, phaseStartDay: null, isDone: true },
    { id: 'C3', title: 'Fixture second scan', category: 'scan', day: '2031-03-17', isApproximate: false, waypointWeightKg: null, phaseStartDay: null, isDone: false },
    { id: 'C4', title: 'Fixture benchmark', category: 'benchmark', day: '2031-02-05', isApproximate: false, waypointWeightKg: null, phaseStartDay: null, isDone: false },
    { id: 'C5', title: 'Fixture target date', category: 'targetDate', day: '2031-06-02', isApproximate: false, waypointWeightKg: null, phaseStartDay: '2031-01-06', isDone: false },
  ],
  scans: [{ day: '2031-01-08' }, { day: '2031-03-17' }, { day: '2031-01-08' }],
  spans: [{ kind: 'deload', startDay: '2031-02-17', endDay: '2031-02-23' }, { kind: 'dietBreak', startDay: '2031-03-24', endDay: null }],
  projection: { status: 'projected', targetDay: '2031-05-27' },
  // §13.4 adapter fixture
  events: [
    { id: 'E1', kind: 'deload', startDay: '2031-02-17', endDay: '2031-02-23', sensitive: false },
    { id: 'E2', kind: 'deload', startDay: '2031-04-07', endDay: '2031-04-13', sensitive: true, note: 'Fixture note' },
    { id: 'E3', kind: 'dietBreak', startDay: '2031-03-24', endDay: null, sensitive: false },
    { id: 'E4', kind: 'travel', startDay: '2031-05-05', endDay: '2031-05-09', sensitive: false },
  ],
};
const s6Complaint = e => ({ onsetDay: e.onsetDay, resolvedDay: e.resolvedDay, character: e.character, trend: e.trend, weakness: e.weakness, updates: e.updates });
function s6TimelineInput(o) {
  return { phases: o.phases || S6FX.phases, checkpoints: o.checkpoints || S6FX.checkpoints, scanDays: o.scanDays || s6ScanDays(S6FX.scans), spans: o.spans || S6FX.spans,
    projection: o.projection === undefined ? S6FX.projection : o.projection, scans: o.scans || 'on', events: o.events || 'on', today: o.today };
}

const S6Model = { S6Day, s6quantize, S6_SEVERITY, s6RulesAreValid, s6Triage, s6Weekly, S6_KIND_ORDER, s6GoverningPhaseIndex, s6WaypointIssue, s6Timeline,
  s6TimelineSpans, s6ScanDays, s6CheckpointIssue, S6FX, s6Complaint, s6TimelineInput };
if (typeof module !== 'undefined') module.exports = S6Model;
