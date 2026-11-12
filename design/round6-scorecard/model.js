/* Round 6 design model of CutScorecard.evaluate, written from docs/personal/superapp/specs/stage-1.md §7,
   and the §13 fixture. It exists so that every number drawn in a frame is computed, not typed. It is a
   mockup aid: it is NOT the implementation, it has no parity twin, and input validation (§6.5) is left out
   because the fixture is valid. EVERY VALUE IS SYNTHETIC ("Fixture Person" does not exist). */

/* ---------- days and weeks (day keys are "yyyy-MM-dd"; weeks are named by their Monday) ---------- */
const dayNum = s => { const [y, m, d] = s.split('-').map(Number); return Math.round(Date.UTC(y, m - 1, d) / 864e5); };
const dayKey = n => new Date(n * 864e5).toISOString().slice(0, 10);
const addDays = (s, k) => dayKey(dayNum(s) + k);
const weekStart = s => { const n = dayNum(s); return dayKey(n - (new Date(n * 864e5).getUTCDay() + 6) % 7); };
const weeksBetween = (a, b) => Math.round((dayNum(weekStart(b)) - dayNum(weekStart(a))) / 7);
const quantize = x => Math.sign(x) * Math.floor(Math.abs(x) * 1000 + 0.5) / 1000;
const RULES = ['liftsHoldingWaistShrinking', 'liftsDropping', 'slowLoss'];

/* ---------- parameters ---------- */
const GENERIC = { rateWindowWeeks: 4, waistWindowWeeks: 4, waistMinDecreaseCm: 0.1, liftDropTolerancePercent: 2.5, liftDropShare: 0.5,
  liftDropConsecutiveWeeks: 3, addCaloriesKcal: 100, slowLossThresholdKgPerWeek: 0.25, slowLossConsecutiveWeeks: 3, reduceCarbsKcal: 100,
  proteinFloorGrams: null, proteinMinDaysPerWeek: 5, maxWeighInAgeWeeks: 1, maxProjectionWeeks: 104, targetToleranceKg: 0 };
const GENERIC_BAND = [0.25, 0.75];
const FIXTURE_PARAMS = { rateWindowWeeks: 4, waistWindowWeeks: 2, waistMinDecreaseCm: 0.5, liftDropTolerancePercent: 5, liftDropShare: 0.5,
  liftDropConsecutiveWeeks: 3, addCaloriesKcal: 300, slowLossThresholdKgPerWeek: 0.4, slowLossConsecutiveWeeks: 3, reduceCarbsKcal: 250,
  proteinFloorGrams: 100, proteinMinDaysPerWeek: 5, maxWeighInAgeWeeks: 1, maxProjectionWeeks: 104, targetToleranceKg: 0 };
const FIXTURE_PHASE = { name: 'Fixture cut', startDay: '2031-01-06', targetWeightKg: 94.0, rateLowPercentPerWeek: 0.40, rateHighPercentPerWeek: 1.20 };

/* ---------- fixture (§13.2, §13.3): weeks 1–22, weigh-ins on Wednesdays from 2031-01-08 ---------- */
const FX_WEIGHT = [100.0, 99.2, 98.4, 97.6, 97.5, 97.4, 97.3, 97.2, 97.1, null, 96.0, 95.2, 95.1, 95.0, 94.9, 94.8, 94.7, 94.6, 94.5, 95.5, 94.0, 93.5];
const FX_WAIST = [100.0, 99.5, 99.0, 98.5, 98.0, 97.5, 97.0, 97.0, 97.0, null, 96.5, 96.0, 95.5, 95.0, 94.5, 94.5, 94.5, 94.5, 94.5, 94.5, 94.0, 93.5];
const FX_LIFTS = { '-1': [60, 50], 0: [60, 50], 1: [60, 50], 2: [60, 50], 3: [60, 50], 4: [60, 50], 5: [62.5, 50], 6: [62.5, 50], 7: [62.5, 52.5], 8: [62.5, 52.5], 9: [62.5, 52.5],
  16: [62.5, 52.5], 17: [57.5, 47.5], 18: [52.5, 42.5], 19: [47.5, 40], 20: [47.5, 40], 21: [47.5, 40], 22: [50, 40] };
const FX_PROTEIN = { 2: [120, 120, 120, 80, 120, 120, 120], 3: [120, 120, 120, 80, 120, 120, 120], 4: [120, 120, 120, 80, 120, 120, 120],
  5: [120, 80, 80, 120, 80, 80, 120], 6: [120, null, 120, null, null, 120, null] };
const weighDay = k => addDays('2031-01-08', 7 * (k - 1));
const at7 = day => dayNum(day) * 86400 + 7 * 3600;

/** The fixture as an evaluate() input. o: { today, phase (null = none), params, noLifts, without: [week numbers],
    weights: [extra readings], set: { week: weightKg } } */
function fixtureInput(o) {
  const without = o.without || [], set = o.set || {};
  const weights = [], waists = [], lifts = [], protein = [];
  FX_WEIGHT.forEach((v, i) => { const k = i + 1; if (v == null || without.includes(k)) return;
    weights.push({ day: weighDay(k), takenAt: at7(weighDay(k)), value: set[k] != null ? set[k] : v });
    waists.push({ day: weighDay(k), takenAt: at7(weighDay(k)), value: FX_WAIST[i] }); });
  if (!without.includes(3)) weights.push({ day: '2031-01-20', takenAt: at7('2031-01-20'), value: 98.9 });     // the extra Monday reading in week 3
  (o.weights || []).forEach(r => weights.push({ takenAt: at7(r.day), ...r }));
  if (!o.noLifts) Object.keys(FX_LIFTS).forEach(k => { const day = addDays('2031-01-06', 7 * (+k - 1));
    lifts.push({ day, exercise: 'Fixture Press', weightKg: FX_LIFTS[k][0] }, { day, exercise: 'Fixture Row', weightKg: FX_LIFTS[k][1] }); });
  Object.keys(FX_PROTEIN).forEach(k => FX_PROTEIN[k].forEach((g, i) => { if (g != null) protein.push({ day: addDays(weighDay(+k), i - 7), grams: g }); }));
  return { weights, waists, lifts, protein, phase: o.phase === undefined ? FIXTURE_PHASE : o.phase, parameters: o.params || FIXTURE_PARAMS, today: o.today };
}

/* ---------- §7 ---------- */
function evaluate(inp) {
  const P = inp.parameters, phase = inp.phase, today = inp.today;
  const upTo = r => r.day <= today;
  const weights = inp.weights.filter(upTo), waists = inp.waists.filter(upTo), lifts = inp.lifts.filter(upTo), protein = inp.protein.filter(upTo);
  const order = (a, b) => a.day < b.day ? -1 : a.day > b.day ? 1 : (a.takenAt - b.takenAt) || (a.value - b.value);
  const latest = arr => { const m = {}; arr.forEach(r => { const w = weekStart(r.day); if (!m[w] || order(r, m[w]) > 0) m[w] = r; }); return m; };
  const wp = latest(weights), sp = latest(waists);
  const keys = Object.keys(wp).concat(Object.keys(sp)).sort();
  const weekKeys = []; if (keys.length) for (let w = keys[0]; w <= weekStart(today); w = addDays(w, 7)) weekKeys.push(w);
  const current = weights.slice().sort(order).pop() || null;
  const started = !!phase && today >= phase.startDay;
  const ds = started ? weekStart(phase.startDay) : (weekKeys[0] || null);
  const withWeight = weekKeys.filter(w => w >= ds && wp[w]);
  const J = withWeight[withWeight.length - 1] || null;
  const loss = w => { const p = addDays(w, -7); return w >= ds && p >= ds && wp[w] && wp[p] ? quantize(wp[p].value - wp[w].value) : null; };
  const res = { input: inp, weekKeys, wp, sp, loss, judgedWeekStart: J, domainStart: ds, started,
    currentWeightKg: current ? current.value : null, currentWeightDay: current ? current.day : null };
  const req = r => r === RULES[0] ? 1 : r === RULES[1] ? P.liftDropConsecutiveWeeks : P.slowLossConsecutiveWeeks;
  const unk = reason => ({ state: 'unknown', reason });
  const allUnknown = (reason, verdictReason) => Object.assign(res, { rate: null, rateUnavailable: reason === 'weighInOverdue' ? 'weighInOverdue' : 'noReadings',
    signals: { waist: unk(reason), lifts: unk(reason), protein: unk(reason), rateBand: unk(reason) },
    rules: RULES.map(rule => ({ rule, state: 'unknown', unknownReason: reason, consecutiveWeeks: 0, requiredWeeks: req(rule) })),
    projection: { status: !started ? 'noActivePhase' : reason === 'weighInOverdue' ? 'weighInOverdue' : phase.targetWeightKg == null ? 'noTarget' : 'rateUnknown' },
    verdict: { kind: 'insufficientData', reason: verdictReason, rule: null, calorieChangeKcal: null, overriddenRules: [], unevaluatedRules: [] } });
  if (!J) return allUnknown('noReadings', started ? 'noReadings' : phase ? 'phaseNotStarted' : 'noActivePhase');
  if (started && weeksBetween(J, today) > P.maxWeighInAgeWeeks) return allUnknown('weighInOverdue', 'weighInOverdue');

  // 7.4 rate: least-squares line over the window's weekly points
  const first = [addDays(J, -7 * P.rateWindowWeeks), ds].sort().pop();
  const pts = weekKeys.filter(w => w >= first && w <= J && wp[w]).map(w => [weeksBetween(first, w), wp[w].value, w]);
  if (pts.length < 2) { res.rate = null; res.rateUnavailable = withWeight.length === 1 ? 'singleReading' : 'gapLongerThanWindow'; }
  else { const x0 = pts[0][0]; let sx = 0, sy = 0; pts.forEach(p => { sx += p[0] - x0; sy += p[1]; });
    const xb = sx / pts.length, yb = sy / pts.length; let num = 0, den = 0; pts.forEach(p => { num += (p[0] - x0 - xb) * (p[1] - yb); den += (p[0] - x0 - xb) ** 2; });
    const lossKg = quantize(-(num / den));
    res.rate = { lossKgPerWeek: lossKg, percentPerWeek: quantize(100 * lossKg / yb), referenceWeightKg: yb, pointsUsed: pts.length,
      spanWeeks: pts[pts.length - 1][0] - x0, firstWeekStart: pts[0][2], lastWeekStart: pts[pts.length - 1][2] }; res.rateUnavailable = null; }

  // 7.5 signals
  const anchor = w => wp[w].day;
  let waist;
  if (!sp[J]) waist = unk('noWaistThisWeek');
  else { const lo = [addDays(J, -7 * P.waistWindowWeeks), ds].sort().pop(); const ref = weekKeys.find(w => w >= lo && w < J && sp[w]);
    if (!ref) waist = { ...unk('noEarlierWaist'), currentCm: sp[J].value };
    else { const change = quantize(sp[J].value - sp[ref].value); const met = change <= -quantize(P.waistMinDecreaseCm);
      waist = { state: met ? 'met' : 'notMet', reason: met ? 'shrinking' : 'notShrinking', currentCm: sp[J].value, referenceCm: sp[ref].value, referenceWeekStart: ref, changeCm: change, weeks: weeksBetween(ref, J) }; } }
  const liftStatus = w => {
    if (!wp[w]) return { status: 'unknown', reason: 'missedWeighIn' };
    if (!lifts.length) return { status: 'unknown', reason: 'noLiftData' };
    const a = anchor(w), best = (from, to) => { const m = {}; lifts.forEach(l => { if (l.day >= addDays(a, from) && l.day <= addDays(a, to)) m[l.exercise] = Math.max(m[l.exercise] || 0, l.weightKg); }); return m; };
    const cur = best(-7, -1), prev = best(-14, -8), win = { windowStartDay: addDays(a, -7), windowEndDay: addDays(a, -1) };
    if (!Object.keys(cur).length) return { status: 'unknown', reason: 'noSessionsThisWeek', ...win };
    if (!Object.keys(prev).length) return { status: 'unknown', reason: 'noSessionsPriorWeek', ...win };
    const common = Object.keys(cur).filter(e => e in prev);
    if (!common.length) return { status: 'unknown', reason: 'noCommonExercises', ...win };
    let dropped = 0, climbed = 0, held = 0;
    common.forEach(e => { if (quantize(cur[e]) < quantize(prev[e] * (1 - P.liftDropTolerancePercent / 100))) dropped++; else if (quantize(cur[e]) > quantize(prev[e])) climbed++; else held++; });
    const dropping = dropped >= 1 && dropped / common.length >= P.liftDropShare;
    return { status: dropping ? 'dropping' : 'holding', reason: dropping ? 'dropping' : 'holding', commonExercises: common.length, dropped, climbed, held, ...win };
  };
  const lj = liftStatus(J);
  const liftSig = { ...lj, state: lj.status === 'holding' ? 'met' : lj.status === 'dropping' ? 'notMet' : 'unknown' };
  let prot;
  if (P.proteinFloorGrams == null) prot = unk('noFloorConfigured');
  else { const a = anchor(J), days = {}; protein.forEach(p => { if (p.day >= addDays(a, -7) && p.day <= addDays(a, -1)) days[p.day] = p.grams; });
    const logged = Object.keys(days).length, atFloor = Object.values(days).filter(g => quantize(g) >= quantize(P.proteinFloorGrams)).length;
    const base = { daysLogged: logged, daysAtOrAboveFloor: atFloor, requiredDays: P.proteinMinDaysPerWeek, floorGrams: P.proteinFloorGrams };
    prot = !logged ? { ...unk('noProteinData'), ...base } : atFloor >= P.proteinMinDaysPerWeek ? { state: 'met', reason: 'floorMet', ...base }
      : atFloor + (7 - logged) < P.proteinMinDaysPerWeek ? { state: 'notMet', reason: 'floorMissed', ...base } : { ...unk('incompleteLogging'), ...base }; }
  let band;
  if (!started) band = unk('noActivePhase');
  else if (!res.rate) band = unk('rateUnknown');
  else { const p = res.rate.percentPerWeek, lo = phase.rateLowPercentPerWeek, hi = phase.rateHighPercentPerWeek;
    band = { state: p >= lo && p <= hi ? 'met' : 'notMet', reason: p < lo ? 'belowBand' : p > hi ? 'aboveBand' : 'withinBand', percentPerWeek: p, lowPercentPerWeek: lo, highPercentPerWeek: hi }; }
  res.signals = { waist, lifts: liftSig, protein: prot, rateBand: band };

  if (!started) { // 7.2: no active phase, or the phase has not started
    res.rules = RULES.map(rule => ({ rule, state: 'unknown', unknownReason: 'noActivePhase', consecutiveWeeks: 0, requiredWeeks: req(rule) }));
    res.projection = { status: 'noActivePhase' };
    res.verdict = { kind: 'insufficientData', reason: phase ? 'phaseNotStarted' : 'noActivePhase', rule: null, calorieChangeKcal: null, overriddenRules: [], unevaluatedRules: [] };
    return res; }

  // 7.6 rules
  const back = n => Array.from({ length: n }, (_, i) => addDays(J, -7 * (n - 1 - i)));
  const run = ok => { let c = 0; for (let w = J; w >= ds && ok(w); w = addDays(w, -7)) c++; return c; };
  const r1 = lj.status === 'holding' && waist.state === 'met' ? { state: 'fired' } : lj.status === 'dropping' || waist.state === 'notMet' ? { state: 'notFired' }
    : { state: 'unknown', unknownReason: lj.status === 'unknown' ? 'liftSignalUnknown' : 'waistSignalUnknown' };
  const N2 = P.liftDropConsecutiveWeeks, w2 = back(N2), in2 = w2.filter(w => w >= ds).map(liftStatus);
  const r2 = in2.some(s => s.status === 'holding') ? { state: 'notFired' } : in2.length === N2 && in2.every(s => s.status === 'dropping') ? { state: 'fired' }
    : { state: 'unknown', unknownReason: w2[0] < ds ? 'fewerWeeksThanWindow' : w2.some(w => !wp[w]) ? 'missedWeighIn' : 'liftSignalUnknown' };
  const N3 = P.slowLossConsecutiveWeeks, thr = quantize(P.slowLossThresholdKgPerWeek), l3 = back(N3).map(loss);
  const r3 = l3.some(l => l != null && l >= thr) ? { state: 'notFired' } : l3.every(l => l != null) ? { state: 'fired' }
    : { state: 'unknown', unknownReason: addDays(J, -7 * N3) < ds ? 'fewerWeeksThanWindow' : 'missedWeighIn' };
  res.rules = [
    { rule: RULES[0], ...r1, consecutiveWeeks: r1.state === 'fired' ? 1 : 0, requiredWeeks: 1 },
    { rule: RULES[1], ...r2, consecutiveWeeks: run(w => liftStatus(w).status === 'dropping'), requiredWeeks: N2 },
    { rule: RULES[2], ...r3, consecutiveWeeks: run(w => loss(w) != null && loss(w) < thr), requiredWeeks: N3 },
  ];

  // 7.7 verdict
  const f = i => res.rules[i].state === 'fired', u = i => res.rules[i].state === 'unknown';
  const v = (kind, reason, rule, kcal, overridden, unevaluated) => ({ kind, reason, rule, calorieChangeKcal: kcal, overriddenRules: overridden, unevaluatedRules: unevaluated });
  res.verdict = f(0) ? v('holdSteady', 'ruleFired', RULES[0], null, f(2) ? [RULES[2]] : [], [])
    : f(1) ? v('addCalories', 'ruleFired', RULES[1], P.addCaloriesKcal, f(2) ? [RULES[2]] : [], [])
    : f(2) && u(0) ? v('insufficientData', 'recompositionCheckIncomplete', null, null, [], [RULES[0]].concat(u(1) ? [RULES[1]] : []))
    : f(2) ? v('reduceCarbs', 'ruleFired', RULES[2], -P.reduceCarbsKcal, [], u(1) ? [RULES[1]] : [])
    : u(0) && u(1) && u(2) ? v('insufficientData', 'noRuleEvaluable', null, null, [], RULES.slice())
    : v('holdSteady', 'noChangeRuleFired', null, null, [], RULES.filter((_, i) => u(i)));

  // 7.8 projection
  const proj = { status: null, targetDay: null, weeksRemaining: null, remainingKg: null };
  if (phase.targetWeightKg == null) proj.status = 'noTarget';
  else { proj.remainingKg = quantize(wp[J].value - phase.targetWeightKg);
    if (proj.remainingKg <= quantize(P.targetToleranceKg)) proj.status = 'targetReached';
    else if (!res.rate) proj.status = 'rateUnknown';
    else if (res.rate.lossKgPerWeek <= 0) proj.status = 'notLosing';
    else { const weeks = proj.remainingKg / res.rate.lossKgPerWeek;
      if (weeks > P.maxProjectionWeeks) proj.status = 'beyondHorizon';
      else { const target = addDays(anchor(J), Math.max(1, Math.ceil(quantize(weeks * 7))));
        if (target < today) proj.status = 'needsNewWeighIn'; else { proj.status = 'projected'; proj.targetDay = target; proj.weeksRemaining = weeks; } } } }
  res.projection = proj;
  return res;
}

if (typeof module !== 'undefined') module.exports = { evaluate, fixtureInput, weighDay, addDays, weekStart, weeksBetween, quantize, RULES, GENERIC, GENERIC_BAND, FIXTURE_PARAMS, FIXTURE_PHASE };
