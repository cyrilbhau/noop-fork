/* Round S2 design model of the coach packet, written from docs/personal/superapp/specs/stage-2.md §7 (the
   format, version 1), §7.10 (budget), §7.11 (privacy scan), §9.1 (copy plan) and the §13 fixture. It exists so
   that every number drawn in a frame is computed, not typed. It is a mockup aid: it is NOT the implementation
   and it has no tests of its own beyond check.js, which compares its output with the specification's §7.9 text.
   The scorecard is stage 1's Fixture Person run through round 6's design model (../round6-scorecard/model.js).
   EVERY VALUE IS SYNTHETIC ("Fixture Person" does not exist). */
const S2Model = (() => {
  /* global evaluate, fixtureInput, weeksBetween, FIXTURE_PARAMS, FIXTURE_PHASE */
  const S1 = typeof require !== 'undefined' ? require('../round6-scorecard/model.js')
    : { evaluate, fixtureInput, weeksBetween, FIXTURE_PARAMS, FIXTURE_PHASE };

  /* ---------- days ---------- */
  const dnum = s => { const [y, m, d] = s.split('-').map(Number); return Math.round(Date.UTC(y, m - 1, d) / 864e5); };
  const dkey = n => new Date(n * 864e5).toISOString().slice(0, 10);
  const plusDays = (s, k) => dkey(dnum(s) + k);
  const dayKeys = (a, b) => { const out = []; for (let n = dnum(a); n <= dnum(b); n++) out.push(dkey(n)); return out; };

  /* ---------- §13 fixture ---------- */
  const CLOCK = { generatedAt: '2031-03-16T07:42:10+01:00', today: '2031-03-16' };
  const STRAIN_FACTOR = 0.21, DEFAULT_RANGE = 14, RANGES = [7, 14, 28];
  const SECTIONS = ['scorecard', 'weigh-ins', 'recovery-sleep', 'trends', 'activity'];
  // §13.2: day, recovery, stored strain (0–100), sleep, deep, REM, light (minutes), efficiency, HRV, RHR, HR-only
  const N = null;
  const DAILY = [
    ['2031-03-03', 62, 47, 444, 78, 102, 264, 0.91, 58, 54], ['2031-03-04', 71, 38, 462, 84, 108, 270, 0.93, 63, 52],
    ['2031-03-05', 55, 62, 402, 66, 90, 246, 0.88, 52, 56], ['2031-03-06', 48, 30, 378, 60, 84, 234, 0.86, 47, 58],
    /* 2031-03-07: no row */
    ['2031-03-08', 66, 44, 450, 81, 105, 264, 0.92, 60, 53], ['2031-03-09', 74, 25, 480, 90, 114, 276, 0.94, 66, 51],
    ['2031-03-10', 60, 50, 432, 75, 99, 258, 0.90, 57, 54], ['2031-03-11', 58, 41, 420, N, N, N, N, 55, 55, true],
    ['2031-03-12', 64, 58, 438, 78, 96, 264, 0.91, 59, 54], ['2031-03-13', N, 35, N, N, N, N, N, N, N],
    ['2031-03-14', 69, 46, 456, 84, 102, 270, 0.92, 62, 52], ['2031-03-15', 72, 33, 468, 87, 108, 273, 0.93, 64, 52],
    ['2031-03-16', 67, 6, 450, 81, 102, 267, 0.92, 61, 53],
  ].map(([day, recovery, strain, sleep, deep, rem, light, eff, hrv, rhr, hrOnly]) => ({ day, recovery, strain, sleep, deep, rem, light, eff, hrv, rhr, hrOnly: !!hrOnly }));
  const BASELINES = { hrv: { center: 57.2, typical: [50.8, 63.6], status: 'trusted', nights: 21 }, rhr: { center: 54.1, typical: [51.9, 56.3], status: 'trusted', nights: 21 } };
  const A = 'apple-health', E = 'strap-estimate';
  const STEPS = [['2031-03-03', 9120, A], ['2031-03-04', 11240, A], ['2031-03-05', 8460, A], ['2031-03-06', 7300, E], ['2031-03-08', 12080, A], ['2031-03-09', 6540, A], ['2031-03-10', 9870, A],
    ['2031-03-11', 10310, A], ['2031-03-12', 8890, A], ['2031-03-13', 5200, E], ['2031-03-14', 9640, A], ['2031-03-15', 13020, A], ['2031-03-16', 1480, A]].map(([day, steps, source]) => ({ day, steps, source }));
  const WORKOUTS = [
    { day: '2031-03-03', startMinuteOfDay: 18 * 60 + 10, sport: 'strength', source: 'lift-log', durationMinutes: 62, avgHr: 108, energyKcal: 380, distanceKm: null },
    { day: '2031-03-05', startMinuteOfDay: 7 * 60 + 5, sport: 'cycling', source: 'apple-health', durationMinutes: 45, avgHr: 132, energyKcal: 410, distanceKm: 18.4 },
    { day: '2031-03-08', startMinuteOfDay: 9 * 60 + 30, sport: 'hiking', source: 'manual', durationMinutes: 95, avgHr: null, energyKcal: null, distanceKm: null },
    { day: '2031-03-10', startMinuteOfDay: 6 * 60 + 50, sport: 'walking', source: 'detected', durationMinutes: 40, avgHr: 96, energyKcal: 170, distanceKm: 3.6 },
    { day: '2031-03-12', startMinuteOfDay: 18 * 60 + 5, sport: 'rowing', source: 'whoop', durationMinutes: 30, avgHr: 128, energyKcal: 300, distanceKm: null },
  ];
  // §13.4: invented identifiers for the privacy scan
  const IDENTIFIERS = ['FIXTURE-STRAP-0001', 'Fixture Band', '00000000-0000-4000-8000-000000000001', 'fixture.person@example.invalid', 'Fixture Phone', '/Users/fixture'];

  /* ---------- §7.1 number formats: no locale, never a negative zero ----------
     fx is String(format: "%.Nf"): it rounds the stored binary value, and an exact tie goes to the even digit
     (75 minutes is "1.2h"). int is Int(x.rounded()): halves away from zero. */
  const fx = (x, d) => { const a = Math.abs(x), m = 10 ** d; let s;
    if (Number.isInteger(a * 2 ** (d + 1)) && (a * m) % 1 === 0.5) { const f = Math.floor(a * m); s = ((f % 2 ? f + 1 : f) / m).toFixed(d); } else s = a.toFixed(d);
    return (x < 0 && Number(s) !== 0 ? '-' : '') + s; };
  const int = x => { const v = Math.floor(Math.abs(x) + 0.5); return (x < 0 && v !== 0 ? '-' : '') + String(v); };
  const signed = (x, d) => { const s = fx(x, d); return s.startsWith('-') ? s : '+' + s; };
  const DASH = '—';
  const mean = a => a.reduce((s, v) => s + v, 0) / a.length;
  const utf8 = s => new TextEncoder().encode(s).length;

  /* ---------- §6.2 sanitize ---------- */
  function sanitize(text) {
    let s = String(text == null ? '' : text).replace(/[\u0000-\u001f\u007f\u2028\u2029]/g, ' ').replace(/ +/g, ' ').trim().replace(/"/g, "'");
    while (utf8(s) > 48) s = [...s].slice(0, -1).join('');
    return s.trim() || 'unnamed';
  }

  /* ---------- §6.1 CoachDayFormat, packet style ---------- */
  const hours = m => m == null ? DASH : fx(m / 60, 1) + 'h';
  const effPercent = e => { if (e == null || e <= 0) return DASH; if (e > 1.5) e /= 100; return e > 0 && e <= 1 ? int(e * 100) + '%' : DASH; };
  const dayLine = (row, factor) => `${row.day}: ` + [
    `recovery ${row.recovery == null ? DASH : int(row.recovery)}`, `strain ${row.strain == null ? DASH : fx(row.strain * factor, 1)}`, `sleep ${hours(row.sleep)}`,
    `deep ${hours(row.deep)}`, `REM ${hours(row.rem)}`, `light ${hours(row.light)}`, `eff ${effPercent(row.eff)}`,
    `HRV ${row.hrv == null ? DASH : int(row.hrv) + 'ms'}`, `RHR ${row.rhr == null ? DASH : row.rhr + 'bpm'}`].join(', ');
  const averagesLine = (rows, factor) => { const col = (k, f) => { const v = rows.map(r => r[k]).filter(x => x != null); return v.length ? f(mean(v)) : DASH; };
    return `recovery: ${col('recovery', int)}, strain: ${col('strain', m => fx(m * factor, 1))}, sleep: ${col('sleep', m => fx(m / 60, 1))}h, HRV: ${col('hrv', int)} ms, RHR: ${col('rhr', int)} bpm`; };

  /* ---------- §7.3 scorecard lines, from a round 6 model result ---------- */
  function scorecardLines(sc) {
    if (sc.kind === 'switchedOff') return ['not available: the scorecard is switched off in the app'];
    const r = sc.result, ph = sc.phase, P = r.input.parameters, V = r.verdict, S = r.signals, out = [];
    out.push(!ph ? 'phase: none active' : `phase: "${sanitize(ph.name)}" (cut), ${V.reason === 'phaseNotStarted' ? 'starts' : 'started'} ${ph.startDay}, ${ph.targetWeightKg == null ? 'no target' : `target ${fx(ph.targetWeightKg, 1)} kg`}, band ${fx(ph.rateLowPercentPerWeek, 2)} to ${fx(ph.rateHighPercentPerWeek, 2)} %/week`);
    out.push(`judged-week: ${r.judgedWeekStart || 'none'}`);
    const kcal = V.calorieChangeKcal == null ? 'none' : `${V.calorieChangeKcal < 0 ? '-' : '+'}${int(Math.abs(V.calorieChangeKcal))} kcal`;
    out.push(`verdict: ${V.kind}; reason ${V.reason}; rule ${V.rule || 'none'}; calorie-change ${kcal}; overridden ${V.overriddenRules.join(', ') || 'none'}; could-not-check ${V.unevaluatedRules.join(', ') || 'none'}`);
    r.rules.forEach(x => out.push(`rule ${x.rule}: ${x.state}${x.unknownReason ? ` (${x.unknownReason})` : ''}, ${x.consecutiveWeeks} of ${x.requiredWeeks} weeks`));
    const wa = S.waist, li = S.lifts, pr = S.protein, rb = S.rateBand;
    out.push(`signal waist: ${wa.state} (${wa.reason})` + (wa.currentCm != null ? `; now ${fx(wa.currentCm, 1)} cm` : '')
      + (wa.referenceCm != null && wa.referenceWeekStart ? `; reference ${fx(wa.referenceCm, 1)} cm in week ${wa.referenceWeekStart}` : '') + (wa.changeCm != null ? `; change ${signed(wa.changeCm, 1)} cm` : ''));
    out.push(`signal lifts: ${li.state} (${li.reason})` + (li.commonExercises > 0 ? `; ${li.commonExercises} exercises in common: ${li.dropped} dropped, ${li.climbed} climbed, ${li.held} held` : '')
      + (li.windowStartDay && li.windowEndDay ? `; days ${li.windowStartDay}..${li.windowEndDay}` : ''));
    const floor = pr.floorGrams != null ? pr.floorGrams : P.proteinFloorGrams;
    out.push(`signal protein: ${pr.state} (${pr.reason}); ${pr.daysAtOrAboveFloor || 0} of ${pr.requiredDays != null ? pr.requiredDays : P.proteinMinDaysPerWeek} days at or above floor; ${pr.daysLogged || 0} days logged; ${floor == null ? 'floor not set' : `floor ${int(floor)} g`}`);
    out.push(`signal rate-band: ${rb.state} (${rb.reason})` + (rb.percentPerWeek != null ? `; ${fx(rb.percentPerWeek, 2)} %/week` : '')
      + (rb.lowPercentPerWeek != null && rb.highPercentPerWeek != null ? `; band ${fx(rb.lowPercentPerWeek, 2)} to ${fx(rb.highPercentPerWeek, 2)} %/week` : ''));
    if (r.rate) { const l = r.rate.lossKgPerWeek;
      out.push(`rate: ${l > 0 ? 'losing' : l < 0 ? 'gaining' : 'flat'} ${fx(Math.abs(l), 2)} kg/week (${fx(Math.abs(r.rate.percentPerWeek), 2)} %/week of ${fx(r.rate.referenceWeightKg, 1)} kg); fitted over ${r.rate.pointsUsed} weigh-ins, weeks ${r.rate.firstWeekStart}..${r.rate.lastWeekStart}`); }
    else out.push(`rate: not available (${r.rateUnavailable})`);
    const pj = r.projection;
    out.push(pj.status === 'projected' ? `projection: ${pj.targetDay} (estimate), ${fx(pj.weeksRemaining, 1)} weeks, ${fx(pj.remainingKg, 1)} kg remaining`
      : `projection: none (${pj.status})` + (pj.remainingKg != null ? `; ${fx(pj.remainingKg, 1)} kg remaining` : ''));
    return out;
  }

  /* ---------- §7.4 weigh-ins ---------- */
  function weighInLines(inp) {
    const body = k => { const b = inp.body.find(x => x.kind === k); return b ? `${fx(b.value, 1)} ${k === 'weight' ? 'kg' : 'cm'} (${b.source}${b.day ? `, ${b.day}` : ''})` : DASH; };
    const out = [`current weight: ${body('weight')}`, `current waist: ${body('waist')}`], sc = inp.scorecard;
    if (sc.kind === 'switchedOff') return out.concat('weekly: not available (the scorecard is switched off in the app)');
    const r = sc.result, weeks = r.weekKeys;
    if (!weeks.length) return out.concat('weekly: no weigh-ins yet');
    const k = Math.min(weeks.length, 8);
    out.push(`weekly, weeks start Monday, the latest reading of a week represents it, last ${k} of ${weeks.length} weeks:`);
    weeks.slice(-k).forEach(w => { const a = r.wp[w], b = r.sp[w], l = r.loss(w);
      out.push(`  ${w}: weight ${a ? `${fx(a.value, 1)} kg (${a.day})` : DASH}, waist ${b ? `${fx(b.value, 1)} cm (${b.day})` : DASH}, change ${l == null ? DASH : `${signed(-l, 1)} kg`}`); });
    return out;
  }

  /* ---------- §7.5 recovery and sleep ---------- */
  function recoveryLines(inp, days) {
    const by = {}; inp.days.forEach(r => { if (days.includes(r.day)) by[r.day] = r; });
    const blank = day => ({ day, recovery: N, strain: N, sleep: N, deep: N, rem: N, light: N, eff: N, hrv: N, rhr: N });
    const out = [`per day, oldest first: recovery (0-100), strain (${inp.strainFactor < 1 ? '0-21 scale' : '0-100 scale'}), sleep (h), deep/REM/light (h), eff (%), HRV (ms), RHR (bpm)`];
    days.forEach(d => { const row = by[d] || blank(d); out.push(`  ${dayLine(row, inp.strainFactor)}${row.hrOnly ? ' [sleep staged from heart rate only]' : ''}`); });
    const rows = days.filter(d => by[d]).map(d => by[d]);
    out.push(rows.length ? `averages over ${rows.length} of ${days.length} days with data: ${averagesLine(rows, inp.strainFactor)}` : 'averages: no data in range');
    return out;
  }

  /* ---------- §7.6 trends ---------- */
  function trendLine(name, unit, key, base, inp, days) {
    const by = {}; inp.days.forEach(r => { by[r.day] = r; });
    const vals = ds => ds.map(d => by[d] && by[d][key]).filter(v => v != null);
    const usable = !!(base && base.typical), B = base ? Number(int(base.center)) : null;
    const versus = M => usable ? ` (${signed(M - B, 0)} vs baseline)` : '';
    const parts = [!base ? 'baseline not available' : usable ? `baseline ${B} ${unit} (typical ${int(base.typical[0])} to ${int(base.typical[1])}, ${base.status}, ${base.nights} nights)` : `baseline not established (${base.status}, ${base.nights} nights)`];
    const all = vals(days);
    if (!all.length) parts.push(`range mean ${DASH} over 0 nights`);
    else { const M = Number(int(mean(all))); parts.push(`range mean ${M} ${unit} over ${all.length} nights${versus(M)}`); }
    const last = vals(days.slice(-7));
    if (days.length > 7 && last.length) { const M7 = Number(int(mean(last))); parts.push(`last 7 days mean ${M7} ${unit} over ${last.length} nights${versus(M7)}`); }
    if (usable && all.length) parts.push(`outside typical: ${all.filter(v => v < base.typical[0]).length} below, ${all.filter(v => v > base.typical[1]).length} above`);
    return `${name}: ${parts.join('; ')}`;
  }

  /* ---------- §7.7 activity ---------- */
  function activityLines(inp, days) {
    const by = {}; inp.steps.forEach(s => { if (days.includes(s.day)) by[s.day] = s; });
    const out = ['steps per day; "strap-estimate" is an estimate from strap motion, not a count:'], today = days[days.length - 1];
    days.forEach(d => { const s = by[d]; out.push(`  ${d}: ${!s ? DASH : `${s.source === 'strap-estimate' ? '~' : ''}${int(s.steps)} ${s.source}${d === today ? ' (today so far)' : ''}`}`); });
    const full = days.slice(0, -1).filter(d => by[d]).map(d => by[d]);
    out.push(!full.length ? `steps average: ${DASH} (no step data in range)`
      : `steps average: ${int(mean(full.map(s => s.steps)))} over ${full.length} of ${days.length - 1} full days (${['strap', 'apple-health', 'strap-estimate'].map(k => [k, full.filter(s => s.source === k).length]).filter(x => x[1]).map(x => x.join(' ')).join(', ')})`);
    const ws = inp.workouts.filter(w => days.includes(w.day)).sort((a, b) => a.day < b.day ? -1 : a.day > b.day ? 1 : a.startMinuteOfDay - b.startMinuteOfDay);
    if (!ws.length) return out.concat('workouts: none recorded in range');
    out.push('workouts in range, oldest first, summaries only:');
    if (ws.length > 20) out.push(`  (${ws.length - 20} earlier workouts in range not shown)`);
    const p2 = n => String(n).padStart(2, '0');
    ws.slice(-20).forEach(w => out.push(`  ${w.day} ${p2(Math.floor(w.startMinuteOfDay / 60))}:${p2(w.startMinuteOfDay % 60)} ${sanitize(w.sport)}, ${w.durationMinutes == null ? DASH : int(w.durationMinutes)} min, avg HR ${w.avgHr == null ? DASH : `${w.avgHr} bpm`}, ${w.energyKcal == null ? DASH : int(w.energyKcal)} kcal${w.distanceKm == null ? '' : `, ${fx(w.distanceKm, 2)} km`} [${w.source}]`));
    return out;
  }

  /* ---------- §7 render ---------- */
  function render(inp) {
    const days = dayKeys(inp.rangeStartDay, inp.rangeEndDay), on = SECTIONS.filter(s => inp.sections.includes(s)), off = SECTIONS.filter(s => !inp.sections.includes(s));
    const blocks = [[
      'NOOP-COACH-PACKET v1', `generated: ${inp.generatedAt}`, `range: ${inp.rangeStartDay}..${inp.rangeEndDay} (${days.length} days; the last day is today and is partial)`,
      `sections: ${on.join(', ') || 'none'}`, `switched-off: ${off.join(', ') || 'none'}`, 'not-recorded-by-app: intake, events',
      "units: kg, cm, hours (h), ms, bpm, steps, kcal, km; dates are YYYY-MM-DD in the phone's time zone", 'missing: "—" means NOT MEASURED, never zero']];
    const has = s => on.includes(s);
    if (has('scorecard')) blocks.push(['== SCORECARD ==', ...scorecardLines(inp.scorecard)]);
    if (has('weigh-ins')) blocks.push(['== WEIGH-INS ==', ...weighInLines(inp)]);
    if (has('recovery-sleep')) blocks.push(['== RECOVERY AND SLEEP ==', ...recoveryLines(inp, days)]);
    if (has('trends')) blocks.push(['== TRENDS ==', "baseline is the app's personal baseline behind the recovery score; typical is baseline plus or minus one sigma",
      trendLine('HRV', 'ms', 'hrv', inp.hrvBaseline, inp, days), trendLine('RHR', 'bpm', 'rhr', inp.restingHrBaseline, inp, days)]);
    if (has('activity')) blocks.push(['== ACTIVITY ==', ...activityLines(inp, days)]);
    blocks.push(['== NOTES ==',
      'measured: weight and waist as entered, heart rate, HRV and resting heart rate from the strap, steps marked apple-health or strap.',
      'estimated by the app: recovery and strain scores (not WHOOP\'s scores), sleep duration and stages, steps marked strap-estimate, calories, the projection date.',
      'the app cannot know: food intake, lifting loads beyond imported sessions, anything on a day the strap was not worn, how the owner feels.',
      "the verdict is the owner's own rule applied to the owner's own numbers; the app changed nothing and makes no medical claim.",
      'end of NOOP-COACH-PACKET v1']);
    return blocks.map(b => b.join('\n')).join('\n\n') + '\n';
  }
  const byteBudget = rangeDays => 8000 + 220 * rangeDays;

  /* ---------- §7.11 privacy scan ---------- */
  function privacyViolations(text, identifiers) {
    const out = [], low = text.toLowerCase();
    identifiers.forEach(id => { if (id.length >= 4 && low.includes(id.toLowerCase())) out.push('identifier'); });
    ['my-whoop', '-noop', '/Users/', '/var/', '/private/', 'file://', '~/'].forEach(l => { if (text.includes(l)) out.push(`literal ${l}`); });
    if (/[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}/i.test(text)) out.push('uuid');
    if (/(^|[^0-9a-f])([0-9a-f]{2}[:-]){5}[0-9a-f]{2}([^0-9a-f]|$)/i.test(text)) out.push('mac address');
    if (/\S+@\S+\.\S+/.test(text)) out.push('email address');
    return out;
  }

  /* ---------- the assembler's part, for the frames ----------
     o: { rangeDays, off: [section ids switched off], scorecardOff, data: 'full' | 'none', phaseName, storeUnreadable, generatedAt } */
  function assemble(o = {}) {
    const rangeDays = o.rangeDays || DEFAULT_RANGE, today = CLOCK.today, sections = SECTIONS.filter(s => !(o.off || []).includes(s)), none = o.data === 'none';
    if (o.storeUnreadable) return { state: 'unavailable', rangeDays, sections };
    const phase = none ? null : { ...S1.FIXTURE_PHASE, name: o.phaseName || S1.FIXTURE_PHASE.name };
    const result = S1.evaluate(S1.fixtureInput(none ? { today, phase: null, noLifts: true, without: Array.from({ length: 22 }, (_, i) => i + 1) } : { today, phase }));
    const lastWaist = [...result.weekKeys].reverse().map(w => result.sp[w]).find(Boolean);
    const body = none ? [] : [{ kind: 'weight', value: result.currentWeightKg, source: 'lab-book', day: result.currentWeightDay }].concat(lastWaist ? [{ kind: 'waist', value: lastWaist.value, source: 'lab-book', day: lastWaist.day }] : []);
    const input = { generatedAt: o.generatedAt || CLOCK.generatedAt, rangeStartDay: plusDays(today, 1 - rangeDays), rangeEndDay: today, sections, days: none ? [] : DAILY, strainFactor: STRAIN_FACTOR,
      scorecard: o.scorecardOff ? { kind: 'switchedOff' } : { kind: 'evaluated', phase, result }, body,
      hrvBaseline: none ? null : BASELINES.hrv, restingHrBaseline: none ? null : BASELINES.rhr, steps: none ? [] : STEPS, workouts: none ? [] : WORKOUTS };
    const text = render(input);
    if (privacyViolations(text, IDENTIFIERS).length) return { state: 'blocked', rangeDays, sections };
    const days = dayKeys(input.rangeStartDay, today), inRange = d => days.includes(d);
    const nothingMeasured = !input.days.some(r => inRange(r.day)) && !input.steps.some(s => inRange(s.day)) && !input.workouts.some(w => inRange(w.day)) && !body.length;
    return { state: 'ready', text, lines: text.replace(/\n$/, '').split('\n'), bytes: utf8(text), budget: byteBudget(rangeDays), rangeDays, sections, generatedAt: input.generatedAt,
      scorecardOff: !!o.scorecardOff, nothingMeasured, result, input };
  }

  /* ---------- §9.1 copy plan and the interface's own formats ---------- */
  const LIFETIME_SECONDS = 600;
  /** "HH:mm" of an ISO local time plus some seconds. The clock is the packet's own, so the two cannot disagree. */
  const clockPlus = (iso, seconds) => { const [h, m, s] = iso.slice(11, 19).split(':').map(Number), t = h * 3600 + m * 60 + s + seconds; return `${String(Math.floor(t / 3600) % 24).padStart(2, '0')}:${String(Math.floor(t / 60) % 60).padStart(2, '0')}`; };
  /** copiedAfterSeconds is a design input: how long after the packet was generated the owner tapped Copy. */
  const copyPlan = (doc, copiedAfterSeconds) => ({ text: doc.text, copiedAt: clockPlus(doc.generatedAt, copiedAfterSeconds), expiresAt: clockPlus(doc.generatedAt, copiedAfterSeconds + LIFETIME_SECONDS), localOnly: true });
  /** The size the sheet shows. The specification gives the example "6.2 kB" and no rule; drawn as bytes / 1000, one decimal. */
  const sizeLabel = bytes => `${fx(bytes / 1000, 1)} kB`;

  return { S1, CLOCK, DAILY, BASELINES, STEPS, WORKOUTS, IDENTIFIERS, SECTIONS, RANGES, DEFAULT_RANGE, STRAIN_FACTOR, LIFETIME_SECONDS,
    render, assemble, byteBudget, privacyViolations, sanitize, copyPlan, clockPlus, sizeLabel, dayKeys, plusDays, fx, int, utf8, dnum };
})();
if (typeof module !== 'undefined') module.exports = S2Model;
