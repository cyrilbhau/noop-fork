/* Round S3 design model of the stage 3 pure logic, written from docs/personal/superapp/specs/stage-3.md
   §7.1, §7.2, §7.4, §7.5, §7.6, §8.3, §9.4, §9.5 and §10.8, with the §13 fixture. It exists so that every
   number drawn in a frame is computed, not typed. It is a mockup aid: it is NOT the implementation and it
   leaves out input validation (§6.4) because the fixture is valid.

   ONE FIXTURE PERSON. The person, the protein floor and the daily protein amounts are stage 1's and are
   read from the approved stage 1 round's model file (../round6-scorecard/model.js), not copied.
   EVERY VALUE IS SYNTHETIC ("Fixture Person" does not exist). */
const IntakeModel = (() => {
  const NODE = typeof module !== 'undefined' && module.exports;
  // eslint-disable-next-line no-undef
  const S1 = NODE ? require('../round6-scorecard/model.js') : { fixtureInput, addDays, quantize, weighDay, FIXTURE_PARAMS, FIXTURE_PHASE };
  // Local names differ from stage 1's globals on purpose: a `const quantize` here would shadow the one being read.
  const qz = S1.quantize, shiftDay = S1.addDays;

  /* ---------- §13.1 person and settings ---------- */
  const FIXTURE = {
    person: 'Fixture Person',
    phase: S1.FIXTURE_PHASE,                                   // "Fixture cut", from 2031-01-06
    proteinFloorGrams: S1.FIXTURE_PARAMS.proteinFloorGrams,    // stage 1's floor
    proteinFloorMaximumGrams: 100000,                          // stage 1 §9.2, CutScorecardSettings.proteinFloorMaximumGrams
    targets: { energyLowKcal: 2400, energyHighKcal: 2600, energyHardFloorKcal: 2100 },
    cutoffMinuteOfDay: 20 * 60,
    supplement: { name: 'Fixture supplement', question: 'Did you take Fixture supplement?' },
    foodApp: { name: 'Fixture Food', id: 'app.fixture.food' },
    otherApp: { name: 'Fixture Other', id: 'app.fixture.other' },
    preset: { label: 'Fixture shake', proteinGrams: 30, energyKcal: 150 },
    staleAfterMinutes: 3 * 60,     // §10.8 PersonalIntakeReading.staleAfter
    freshMinutesAgo: 10,           // §13.6 "fresh is ten minutes before now"
    staleMinutesAgo: 4 * 60,       // §13.6 "stale is four hours before now"
    quickAddMaximum: 100000,       // §9.3
    maxSupplements: 4, entryReachDays: 7, historyDays: 28, quietWindowMinutes: 30,
  };

  /* ---------- §13.2 samples ---------- */
  const SAMPLES = [
    { id: 's1', nutrient: 'protein', at: '2030-12-09T08:00:00Z', amount: 30, sourceId: 'app.fixture.food' },
    { id: 's2', nutrient: 'energy', at: '2030-12-09T08:00:00Z', amount: 450, sourceId: 'app.fixture.food' },
    { id: 's3', nutrient: 'protein', at: '2030-12-09T13:00:00Z', amount: 40, sourceId: 'app.fixture.food' },
    { id: 's4', nutrient: 'energy', at: '2030-12-09T13:00:00Z', amount: 700, sourceId: 'app.fixture.food' },
    { id: 's5', nutrient: 'protein', at: '2030-12-09T23:59:59Z', amount: 25, sourceId: 'app.fixture.food' },
    { id: 's6', nutrient: 'energy', at: '2030-12-09T23:59:59Z', amount: 300, sourceId: 'app.fixture.food' },
    { id: 's7', nutrient: 'protein', at: '2030-12-10T00:00:00Z', amount: 20, sourceId: 'app.fixture.food' },
    { id: 's8', nutrient: 'energy', at: '2030-12-10T00:00:00Z', amount: 250, sourceId: 'app.fixture.food' },
    { id: 's9', nutrient: 'protein', at: '2030-12-09T10:00:00Z', amount: 10, sourceId: 'app.fixture.other' },
  ];
  const S3B = { id: 's3b', nutrient: 'protein', at: '2030-12-09T13:00:00Z', amount: 45, sourceId: 'app.fixture.food' };
  const sample = id => SAMPLES.find(s => s.id === id);
  const upTo8 = SAMPLES.slice(0, 8);

  /* ---------- §7.1 the day an entry belongs to; §7.2 aggregation ---------- */
  // Offsets in hours on the fixture's dates (§13.3). A design aid: the app uses real zone rules.
  const ZONE_HOURS = { 'Etc/UTC': 0, 'Pacific/Auckland': 13, 'America/Los_Angeles': -8 };
  const epoch = iso => Date.parse(iso) / 1000;
  const LOG_U = [[0, 'Etc/UTC']];
  const LOG_E = [[0, 'Etc/UTC'], [epoch('2030-12-09T18:00:00Z'), 'Pacific/Auckland']];
  const LOG_W = [[0, 'Pacific/Auckland'], [epoch('2030-12-09T20:00:00Z'), 'America/Los_Angeles']];
  function dayKeyAt(epochSeconds, zoneLog) {
    let zone = zoneLog[0][1];
    zoneLog.forEach(([from, z]) => { if (from <= epochSeconds) zone = z; });
    return new Date((epochSeconds + ZONE_HOURS[zone] * 3600) * 1000).toISOString().slice(0, 10);
  }
  function aggregate(samples, o = {}) {
    const zoneLog = o.zoneLog || LOG_U, admitted = o.admitted || null, days = {}, sources = {};
    let excluded = 0;
    samples.slice().sort((a, b) => epoch(a.at) - epoch(b.at) || (a.id < b.id ? -1 : 1)).forEach(s => {
      if (admitted && !admitted.includes(s.sourceId)) { excluded++; return; }
      const day = dayKeyAt(epoch(s.at), zoneLog), row = days[day] || (days[day] = { proteinGrams: null, energyKcal: null });
      const k = s.nutrient === 'protein' ? 'proteinGrams' : 'energyKcal';
      row[k] = (row[k] || 0) + s.amount;
      (sources[day] || (sources[day] = [])).includes(s.sourceId) || sources[day].push(s.sourceId);
    });
    return { days, sources, excluded };
  }

  /* ---------- §7.4 the floor ---------- */
  const meetsFloor = (grams, floorGrams) => qz(grams) >= qz(floorGrams);
  function protein(grams, floorGrams) {
    const known = grams != null && Number.isFinite(grams) && grams >= 0;
    const hasFloor = floorGrams != null && Number.isFinite(floorGrams) && floorGrams > 0;
    const none = { shownGrams: null, shownFloorGrams: null, remainingGrams: null, overGrams: null, ringFraction: null };
    if (!hasFloor) return { ...none, state: 'noFloor', shownGrams: known ? Math.floor(qz(grams)) : null };
    if (!known) return { ...none, state: 'notMeasured', shownFloorGrams: Math.ceil(qz(floorGrams)) };
    const g = qz(grams), f = qz(floorGrams), sg = Math.floor(g), sf = Math.ceil(f);
    if (g < f) return { state: 'below', shownGrams: sg, shownFloorGrams: sf, remainingGrams: Math.max(1, sf - sg), overGrams: 0, ringFraction: g / f };
    if (sg <= sf) return { state: 'atFloor', shownGrams: sg, shownFloorGrams: sf, remainingGrams: 0, overGrams: 0, ringFraction: 1 };
    return { state: 'above', shownGrams: sg, shownFloorGrams: sf, remainingGrams: 0, overGrams: sg - sf, ringFraction: 1 };
  }

  /* ---------- §7.5 energy against the range ---------- */
  function targetsValid(t) {
    if (!t) return false;
    const ok = v => v == null || (Number.isFinite(v) && v >= 0);
    if (!ok(t.energyLowKcal) || !ok(t.energyHighKcal) || !ok(t.energyHardFloorKcal)) return false;
    if (t.energyLowKcal != null && t.energyHighKcal != null && t.energyLowKcal > t.energyHighKcal) return false;
    if (t.energyHardFloorKcal != null && t.energyLowKcal != null && t.energyHardFloorKcal > t.energyLowKcal) return false;
    return true;
  }
  function energy(kcal, targets, dayIsOpen) {
    const base = { shownKcal: null, toLowEndKcal: null, overHighEndKcal: null };
    if (kcal == null) return { ...base, state: 'notMeasured' };
    const k = qz(kcal), out = { ...base, shownKcal: Math.round(k) };
    const t = targets || {}, low = t.energyLowKcal, high = t.energyHighKcal, hard = t.energyHardFloorKcal;
    if ((low == null && high == null) || !targetsValid(t)) return { ...out, state: 'noRange' };
    if (high != null && k > qz(high)) return { ...out, state: 'aboveRange', overHighEndKcal: Math.ceil(k - qz(high)) };
    if (dayIsOpen && low != null && k < qz(low)) return { ...out, state: 'soFar', toLowEndKcal: Math.ceil(qz(low) - k) };
    if (!dayIsOpen && hard != null && k < qz(hard)) return { ...out, state: 'belowHardFloor' };
    if (!dayIsOpen && low != null && k < qz(low)) return { ...out, state: 'belowRange' };
    return { ...out, state: 'inRange' };
  }

  /* ---------- §7.6 the cutoff reminder and the wind-down nudge ---------- */
  const WEEK = 7 * 1440;
  function cutoffTriggers(cutoffMinuteOfDay, windDownMinuteByWeekday = {}, quietWindowMinutes = FIXTURE.quietWindowMinutes) {
    const minute = Math.max(0, Math.min(1439, cutoffMinuteOfDay));
    const fires = Object.keys(windDownMinuteByWeekday).map(w => (+w - 1) * 1440 + windDownMinuteByWeekday[w]);
    return [1, 2, 3, 4, 5, 6, 7].map(weekday => {
      const at = (weekday - 1) * 1440 + minute;
      const near = fires.some(f => { const dd = Math.abs(at - f) % WEEK; return Math.min(dd, WEEK - dd) <= quietWindowMinutes; });
      return { weekday, minuteOfDay: minute, playsSound: !near };
    });
  }
  const everyDay = minute => Object.fromEntries([1, 2, 3, 4, 5, 6, 7].map(w => [w, minute]));
  // §13.5, row by row. `windDown` is the fire map; row 5's 00:10 fires on the following weekday.
  const CUTOFF_CASES = [
    { cutoff: 1200, windDown: {}, silent: [] },
    { cutoff: 1200, windDown: everyDay(1220), silent: [1, 2, 3, 4, 5, 6, 7] },
    { cutoff: 1200, windDown: everyDay(1230), silent: [1, 2, 3, 4, 5, 6, 7] },
    { cutoff: 1200, windDown: everyDay(1231), silent: [] },
    { cutoff: 1430, windDown: everyDay(10), silent: [1, 2, 3, 4, 5, 6, 7] },
    { cutoff: 1200, windDown: { ...everyDay(1320), 2: 1210 }, silent: [2] },
  ];

  /* ---------- §9.4 the resolver ---------- */
  const order = policy => policy === 'legacy' ? ['nutritionCsv'] : policy === 'quickAdd' ? ['quickAdd', 'appleHealth', 'nutritionCsv'] : ['appleHealth', 'quickAdd', 'nutritionCsv'];
  const policyFor = (flagEnabled, sourceSetting) => !flagEnabled ? 'legacy' : sourceSetting === 'quickAdd' ? 'quickAdd' : sourceSetting === 'appleHealth' ? 'appleHealth' : 'none';
  function resolve(candidates, policy, key) {
    for (const source of order(policy)) {
      const c = candidates[source], v = c ? c[key] : null;
      if (v != null && Number.isFinite(v) && v >= 0) return { value: v, source, readAtMinute: source === 'nutritionCsv' ? null : c.readAtMinute };
    }
    return null;
  }

  /* ---------- §9.5 one clock. `now` is a wall-clock string "yyyy-MM-ddTHH:mm" in the phone's zone. ---------- */
  const hhmm = minute => `${String(Math.floor(minute / 60)).padStart(2, '0')}:${String(minute % 60).padStart(2, '0')}`;
  function clock(now, cutoffSet = true, cutoffMinuteOfDay = FIXTURE.cutoffMinuteOfDay) {
    const minuteOfDay = +now.slice(11, 13) * 60 + +now.slice(14, 16);
    return { now, today: now.slice(0, 10), minuteOfDay, dayIsOpen: !cutoffSet || minuteOfDay < cutoffMinuteOfDay };
  }

  /* ---------- the fixture's stored days ---------- */
  // Stage 1 §13.2 protein days (8 Jan to 11 Feb 2031), read from stage 1's model.
  const S1_PROTEIN = {};
  S1.fixtureInput({ today: '2031-12-31' }).protein.forEach(p => { S1_PROTEIN[p.day] = p.grams; });
  // The two sample days of §13.2, before stage 1's phase.
  const DEC = aggregate(SAMPLES).days;
  // §13.6: "today" for the card and widget states. Each amount is a §13.3 row, so nothing is typed:
  // 95 (s1 to s8), 100 (the edit s3 -> s3b), 105 (s1 to s9), and 1450 kcal with the day open.
  const d9 = '2030-12-09';
  const TODAY = {
    below: aggregate(upTo8).days[d9].proteinGrams,
    atFloor: aggregate(upTo8.map(s => s.id === 's3' ? S3B : s)).days[d9].proteinGrams,
    above: aggregate(SAMPLES).days[d9].proteinGrams,
    kcal: aggregate(upTo8).days[d9].energyKcal,
  };
  // §13.4 energy rows.
  const ENERGY_CASES = [
    { kcal: null, open: true, state: 'notMeasured' }, { kcal: 1450, open: true, state: 'soFar', toLow: 950 }, { kcal: 2700, open: true, state: 'aboveRange', over: 100 },
    { kcal: 1500, open: false, state: 'belowHardFloor' }, { kcal: 2100, open: false, state: 'belowRange' }, { kcal: 2400, open: false, state: 'inRange' },
    { kcal: 2600, open: false, state: 'inRange' }, { kcal: 2601, open: false, state: 'aboveRange', over: 1 },
  ];
  // §13.4 protein rows: grams, floor, state, shown, remaining, over, ring.
  const PROTEIN_CASES = [
    [null, 100, 'notMeasured', null, null, null, null], [95, 100, 'below', 95, 5, 0, 0.95], [99.9994, 100, 'below', 99, 1, 0, 0.99999], [99.9996, 100, 'atFloor', 100, 0, 0, 1],
    [100, 100, 'atFloor', 100, 0, 0, 1], [105, 100, 'above', 105, 0, 5, 1], [105, null, 'noFloor', 105, null, null, null],
  ];
  const energyCase = state => ENERGY_CASES.find(c => c.state === state);
  // Frames are the Fixture Person on these moments. Stage 1 states 120 g for Wed 29 Jan 2031 as that day's
  // total; the 95, 100 and 105 g of §13.6 are that day in progress, so no day has two totals.
  const NOW = { afternoon: '2031-01-29T15:20', evening: '2031-01-29T20:40', firstDay: '2030-12-09T15:20', gapDay: '2031-02-12T08:10' };
  // Closed past days for the calories line: the §13.4 rows 2400 (in range) and 2100 (below the range).
  const ENERGY_BY_DAY = { '2031-01-28': energyCase('inRange').kcal, '2031-01-27': energyCase('belowRange').kcal };
  const storedProtein = day => S1_PROTEIN[day] != null ? S1_PROTEIN[day] : DEC[day] ? DEC[day].proteinGrams : null;
  const storedEnergy = day => ENERGY_BY_DAY[day] != null ? ENERGY_BY_DAY[day] : DEC[day] ? DEC[day].energyKcal : null;

  // Path B: today's quick-add entries carry the §13.2 amounts (s1 to s6, then s9 for the 105 g state).
  // 08:00 and 13:00 are the samples' own times; 15:05 and 15:15 are this round's.
  function entriesFor(grams) {
    const e = [{ minute: 480, proteinGrams: sample('s1').amount, energyKcal: sample('s2').amount },
      { minute: 780, proteinGrams: grams >= TODAY.atFloor ? S3B.amount : sample('s3').amount, energyKcal: sample('s4').amount },
      { minute: 905, proteinGrams: sample('s5').amount, energyKcal: sample('s6').amount }];
    if (grams >= TODAY.above) { e[1].proteinGrams = sample('s3').amount; e.push({ minute: 915, proteinGrams: sample('s9').amount, energyKcal: null }); }
    return e;
  }

  /* ---------- one scenario: the fixture at a moment, resolved once and passed down ---------- */
  // o: now, day (selected), flag, source ('appleHealth' | 'quickAdd' | 'none' | null = not chosen), grams, kcal (today only),
  //    floor (null = none), targets (null = unreadable, {} = none), readMinutesAgo, outcome ('written' | 'failedRead' | 'preserved'),
  //    apps, admitted, valueSource, cutoffSet, supplements, restored, loading, historyEndsYesterday
  function scenario(o = {}) {
    const flag = o.flag !== false, source = o.source === undefined ? 'appleHealth' : o.source;
    const ck = clock(o.now || NOW.afternoon, o.cutoffSet !== false);
    const day = o.day || ck.today, isToday = day === ck.today;
    const floor = o.floor === undefined ? FIXTURE.proteinFloorGrams : o.floor;
    const targets = o.targets === undefined ? FIXTURE.targets : o.targets;
    const targetsUnreadable = targets === null || !targetsValid(targets);
    const todayGrams = 'grams' in o ? o.grams : TODAY.below;
    const grams = isToday ? todayGrams : storedProtein(day);
    const kcal = isToday ? ('kcal' in o ? o.kcal : TODAY.kcal) : storedEnergy(day);
    const valueSource = o.valueSource || (source === 'quickAdd' ? 'quickAdd' : 'appleHealth');
    const entries = valueSource === 'quickAdd' && isToday && !o.restored && grams != null ? entriesFor(grams) : [];
    const readAtMinute = valueSource === 'quickAdd' ? (entries.length ? entries[entries.length - 1].minute : null)
      : ck.minuteOfDay - (o.readMinutesAgo != null ? o.readMinutesAgo : FIXTURE.freshMinutesAgo);
    const candidates = { [valueSource]: { protein: grams, energy: kcal, readAtMinute } };
    const policy = policyFor(flag, source);
    const P = resolve(candidates, policy, 'protein'), E = resolve(candidates, policy, 'energy');
    const readAt = P ? P.readAtMinute : E ? E.readAtMinute : null;
    const history = [];
    for (let i = FIXTURE.historyDays - 1; i >= 0; i--) {
      const dd = shiftDay(ck.today, -i);
      history.push({ day: dd, grams: dd === ck.today ? (o.historyEndsYesterday ? null : todayGrams) : storedProtein(dd) });
    }
    if (o.historyEndsYesterday) history.pop();
    return { flag, source, policy, clock: ck, day, isToday, floor, targets, targetsUnreadable, protein: P, energy: E, readAt,
      progress: protein(P ? P.value : null, floor),
      energyState: energy(E ? E.value : null, targetsUnreadable ? {} : targets, isToday && ck.dayIsOpen),
      stale: !!P && P.source === 'appleHealth' && isToday && readAt != null && ck.minuteOfDay - readAt > FIXTURE.staleAfterMinutes,
      health: { outcome: o.outcome || 'written', attemptMinute: ck.minuteOfDay, apps: o.apps || [FIXTURE.foodApp], admitted: o.admitted || null },
      entries, restored: !!o.restored, history, loading: !!o.loading,
      supplements: o.supplements || [{ name: FIXTURE.supplement.name, state: 'notRecorded' }] };
  }

  /* ---------- §10.8 the widget ---------- */
  // The payload carries only the day, the shown grams, the shown floor, the source and the read time.
  function widgetReading(sc) {
    if (!sc.flag || sc.source == null || sc.source === 'none') return null;        // never published
    if (sc.protein && sc.readAt == null) return null;                               // a value is never drawn without its time
    return { day: sc.clock.today, proteinGrams: sc.progress.shownGrams, floorGrams: sc.floor == null ? null : Math.ceil(qz(sc.floor)),
      source: sc.protein ? sc.protein.source : null, readAtMinute: sc.protein ? sc.readAt : null };
  }
  function widgetState(reading, nowMinute) {
    if (!reading) return { kind: 'notSetUp' };
    if (reading.proteinGrams == null) return { kind: 'nothing', floorGrams: reading.floorGrams };
    const stale = reading.source === 'appleHealth' && nowMinute - reading.readAtMinute > FIXTURE.staleAfterMinutes;
    const base = { stale, grams: reading.proteinGrams, floorGrams: reading.floorGrams, readAtMinute: reading.readAtMinute, source: reading.source };
    if (reading.floorGrams == null) return { ...base, kind: 'noFloor' };
    const toGo = reading.floorGrams - reading.proteinGrams;
    return toGo > 0 ? { ...base, kind: 'below', toGo, fraction: reading.proteinGrams / reading.floorGrams }
      : toGo === 0 ? { ...base, kind: 'met', fraction: 1 } : { ...base, kind: 'above', over: -toGo, fraction: 1 };
  }

  /* Round 6's Today header and neighbour tiles, as approved there. They are page furniture, not intake values. */
  const CHROME = { sleep: 86, recovery: 68, strain: 11.4, stress: '1.4', stressOf: 'of 3', stressWord: 'Moderate', fitnessAge: '≤ 34', fitnessUnit: 'yrs', fitnessAsOf: '2031-01-26' };

  const api = { FIXTURE, SAMPLES, S3B, sample, LOG_U, LOG_E, LOG_W, aggregate, dayKeyAt, meetsFloor, protein, targetsValid, energy, cutoffTriggers, everyDay, CUTOFF_CASES,
    order, policyFor, resolve, hhmm, clock, S1_PROTEIN, TODAY, ENERGY_CASES, PROTEIN_CASES, energyCase, NOW, ENERGY_BY_DAY, storedProtein, storedEnergy,
    entriesFor, scenario, widgetReading, widgetState, CHROME, addDays: shiftDay, quantize: qz };
  if (NODE) module.exports = api;
  return api;
})();
