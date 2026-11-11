/* Round combined · design model for the surfaces every stage shares (rulings addendum A1, A7).
   It adds to the stage 1 design model (../round6-scorecard/model.js, the §13 Fixture Person) only what the
   other stages contribute to the shared surfaces, taken from each specification's fixture:
     stage 3 §13.1, §13.4, §13.6 (intake), stage 4 §13 (scan days), stage 5 §13.1 (events), stage 6 §13.2, §13.4.
   It exists so that every number drawn in a frame is computed, not typed. It is a mockup aid: it is NOT the
   implementation and has no parity twin. EVERY VALUE IS SYNTHETIC ("Fixture Person" does not exist).
   Loadable in Node (require) and in the page (after ../round6-scorecard/model.js); it declares one global, SCM. */
(function (root, R6_GLOBALS) {
  const NODE = typeof module !== 'undefined' && module.exports;
  // In Node the stage 1 model is required. In the page it is the globals round 6's model.js declares, gathered
  // at the bottom of this file, outside this function, so the names declared in here cannot shadow them.
  const R6 = NODE ? require('../round6-scorecard/model.js') : R6_GLOBALS;
  const { addDays, weekStart, quantize, FIXTURE_PARAMS, FIXTURE_PHASE } = R6;

  /* ---------- the one order (ruling A1). Health rows and Settings cards both follow it. ---------- */
  const ORDER = [
    { id: 'scorecard', stage: 1, flag: 'noop.cutScorecardEnabled' },
    { id: 'packet', stage: 2, flag: 'noop.coachPacketEnabled' },
    { id: 'intake', stage: 3, flag: 'noop.intakeEnabled' },
    { id: 'bodyRecord', stage: 4, flag: 'noop.bodyRecordEnabled' },
    { id: 'events', stage: 5, flag: 'noop.personalEventsEnabled' },
    { id: 'niggle', stage: 6, flag: 'noop.niggleLogEnabled' },
    { id: 'recovery', stage: 6, flag: 'noop.cutStressEnabled' },
    { id: 'timeline', stage: 6, flag: 'noop.checkpointTimelineEnabled' },
  ];
  const IDS = ORDER.map(o => o.id);
  const flags = (...on) => Object.fromEntries(IDS.map(id => [id, on.includes(id)]));
  const ALL_ON = flags(...IDS), ALL_OFF = flags();
  // The "some switches on" example: four on, the scorecard among those off (so Recovery context has no way in).
  const SOME_ON = flags('packet', 'events', 'recovery', 'timeline');
  const present = f => IDS.filter(id => f[id]);

  /* ---------- the clock of the frames ---------- */
  // The default day: Wed 5 Feb 2031, week 5 of the fixture. It is the day stage 6's fixtures use (§13.3, §13.4)
  // and the week stage 5's deload (E2) covers, so every stage has something to show on it.
  const TODAY = '2031-02-05';
  // The status bar drawn by design/system/noop.js reads 9:41, so "now" is 09:41 and read times follow from it.
  const NOW_MIN = 9 * 60 + 41;
  const hhmm = m => { const x = ((m % 1440) + 1440) % 1440; return `${String(Math.floor(x / 60)).padStart(2, '0')}:${String(x % 60).padStart(2, '0')}`; };
  const FRESH_MIN = 10, STALE_MIN = 240;           // stage 3 §13.6: fresh is ten minutes before now, stale four hours
  const STALE_AFTER_MIN = 180;                      // stage 3 §10.8 staleAfter

  /* ---------- stage 5 §13.1: events ---------- */
  const EVENTS = [
    { id: 'E1', kind: 'travel', label: null, start: '2031-03-10', end: '2031-03-16', note: 'Fixture trip', sensitive: false },
    { id: 'E2', kind: 'deload', label: null, start: '2031-02-03', end: '2031-02-09', note: null, sensitive: false },
    { id: 'E3', kind: 'dietBreak', label: null, start: '2031-04-14', end: '2031-04-27', note: null, sensitive: false },
    { id: 'E4', kind: 'supplementChange', label: null, start: '2031-01-22', end: '2031-01-22', note: null, sensitive: false },
    { id: 'E5', kind: 'illness', label: null, start: '2031-05-19', end: null, note: null, sensitive: true },
    { id: 'E6', kind: 'custom', label: 'Fixture change', start: '2031-03-26', end: '2031-03-26', note: 'Fixture note', sensitive: true },
    { id: 'E7', kind: 'travel', label: null, start: '2030-12-01', end: '2030-12-07', note: null, sensitive: false },
    { id: 'E8', kind: 'travel', label: null, start: '2031-02-22', end: '2031-02-24', note: null, sensitive: false },
  ];
  // Not in any fixture: three more one-day travel events, used only by the frame for "more than three in a list".
  const EXTRA_EVENTS = ['2031-03-03', '2031-03-05', '2031-03-07'].map((d, i) => ({ id: `X${i + 1}`, kind: 'travel', label: null, start: d, end: d, note: null, sensitive: false }));
  const overlaps = (e, first, last) => e.start <= last && (e.end == null || e.end >= first);
  // A future start "overlaps nothing shown" (stage 5 §7.1), so an event counts only once it has started.
  const started = (events, today) => events.filter(e => e.start <= today);
  const newestFirst = (a, b) => a.start < b.start ? 1 : a.start > b.start ? -1 : 0;
  const eventsNow = (events, today) => events.filter(e => overlaps(e, today, today)).length;
  const NOTE_LIMIT = 3;
  /** Stage 5 §10.6 EventNote from a stage 1 result. Null with no judged week or nothing to list. */
  function eventNote(result, events, today) {
    const J = result.judgedWeekStart; if (!J) return null;
    const P = result.input.parameters, sunday = addDays(J, 6);
    const m = Math.max(P.rateWindowWeeks, P.waistWindowWeeks, P.slowLossConsecutiveWeeks, P.liftDropConsecutiveWeeks);
    const evidenceStartDay = addDays(J, -7 * (m + 2));                       // stage 1 §7.9
    const live = started(events, today).slice().sort(newestFirst);
    const inWeek = live.filter(e => overlaps(e, J, sunday));
    const earlier = live.filter(e => !overlaps(e, J, sunday) && overlaps(e, evidenceStartDay, sunday));
    if (!inWeek.length && !earlier.length) return null;
    const cut = Math.max(0, inWeek.length - NOTE_LIMIT) + Math.max(0, earlier.length - NOTE_LIMIT);
    return { judgedWeekStart: J, evidenceStartDay, inWeek: inWeek.slice(0, NOTE_LIMIT), earlier: earlier.slice(0, NOTE_LIMIT), more: cut };
  }
  /** One boolean per week: an event that has started overlaps it (PersonalEvents.coveredSlots). */
  const marked = (weekStarts, events, today) => weekStarts.map(w => started(events, today).some(e => overlaps(e, w, addDays(w, 6))));

  /* ---------- stage 3 §13.1, §13.4, §13.6: intake ---------- */
  const INTAKE = { floorGrams: FIXTURE_PARAMS.proteinFloorGrams, rangeLowKcal: 2400, rangeHighKcal: 2600, hardFloorKcal: 2100, cutoffMinute: 1200,
    supplement: 'Fixture supplement', foodApp: 'Fixture Food', otherApp: 'Fixture Other', todayKcal: 1450,
    todayGrams: { notMeasured: null, below: 95, atFloor: 100, above: 105 }, pastDayGrams: 120, windDownMinute: 1220,
    refusedFloorEntry: '99.5' };                    // stage 1 §10.5: an entry the whole-gram field refuses
  // Stage 1's weekly reminder at its stored defaults, as round 6 frame F2 draws it: Saturday 08:00.
  const REMINDER = { day: 'Saturday', minute: 480 };
  /** Stage 3 §13.4. grams nil: not measured (never zero). floor nil: no floor set. */
  function proteinProgress(grams, floor) {
    if (grams == null) return { state: 'notMeasured', shown: null, remaining: null, over: null, ring: null };
    const q = quantize(grams);
    if (floor == null) return { state: 'noFloor', shown: Math.floor(q), remaining: null, over: null, ring: null };
    const state = q < floor ? 'below' : q === floor ? 'atFloor' : 'above', shown = Math.floor(q);
    return { state, shown, remaining: state === 'below' ? floor - shown : 0, over: state === 'above' ? shown - floor : 0, ring: Math.min(1, grams / floor) };
  }
  const readAt = stale => NOW_MIN - (stale ? STALE_MIN : FRESH_MIN);
  const isStale = readMinute => NOW_MIN - readMinute > STALE_AFTER_MIN;
  /** Stage 3 §10.4: one caption for the seven days the protein signal reads. sources: one per logged day. */
  const proteinSource = sources => { const u = [...new Set(sources)]; return !u.length ? null : u.length > 1 ? 'several' : u[0]; };
  const SOURCE_DAYS = { appleHealth: Array(7).fill('appleHealth'), quickAdd: Array(7).fill('quickAdd'), csv: Array(7).fill('csv'),
    several: ['appleHealth', 'appleHealth', 'quickAdd', 'csv', 'appleHealth', 'appleHealth', 'appleHealth'] };

  /* ---------- stage 4 §13: scans, each on a stage 1 weigh-in day ---------- */
  const SCAN_DAYS = ['2031-01-08', '2031-04-09', '2031-05-28'];
  const lastScan = today => SCAN_DAYS.filter(d => d <= today).pop() || null;

  /* ---------- stage 6 §13.2: complaints (an observation is not a complaint and is not counted) ---------- */
  const COMPLAINTS = [
    { id: 'N1', onset: '2031-02-03', resolved: '2031-02-12' }, { id: 'N2', onset: '2031-03-03', resolved: null },
    { id: 'N3', onset: '2031-04-07', resolved: null }, { id: 'N5', onset: '2031-05-05', resolved: null }, { id: 'N6', onset: '2031-06-02', resolved: null },
  ];
  const openNiggles = today => COMPLAINTS.filter(c => c.onset <= today && (c.resolved == null || c.resolved > today)).length;

  /* ---------- stage 6 §13.4: checkpoints and the second phase; spans and scans come from stages 5 and 4 ---------- */
  const CHECKPOINTS = [
    { id: 'C1', title: 'Fixture waypoint', day: '2031-03-19' }, { id: 'C2', title: 'Fixture panel', day: '2031-02-10' }, { id: 'C3', title: 'Fixture second scan', day: '2031-03-17' },
    { id: 'C4', title: 'Fixture benchmark', day: '2031-02-05' }, { id: 'C5', title: 'Fixture target date', day: '2031-06-02' },
  ];
  const PHASE_STARTS = [FIXTURE_PHASE.startDay, '2031-06-16'];
  /** The day of the first upcoming item of the timeline (stage 6 §10.1 "Next:"). Never a private event, a title or a weight. */
  function nextTimelineDay(today, f, result, events) {
    const days = CHECKPOINTS.map(c => c.day).concat(PHASE_STARTS);
    if (f.events) events.filter(e => !e.sensitive && (e.kind === 'dietBreak' || e.kind === 'deload')).forEach(e => days.push(e.start));
    if (f.scorecard && result && result.projection.status === 'projected') days.push(result.projection.targetDay);
    return days.filter(d => d > today).sort()[0] || null;
  }

  /* ---------- stage 6 §13.3: nightly resting heart rate (bpm) and HRV (ms), by week, Monday first ---------- */
  const NIGHTS = { '2031-01-06': { rhr: Array(7).fill(60), hrv: Array(7).fill(50) }, '2031-01-13': { rhr: Array(4).fill(61), hrv: Array(4).fill(48) },
    '2031-01-20': { rhr: Array(3).fill(62), hrv: Array(3).fill(47) }, '2031-01-27': { rhr: [63, 63, 64, 64, 65, 65, 66], hrv: [46, 46, 45, 45, 44, 44, 43] },
    '2031-02-03': { rhr: Array(3).fill(64), hrv: Array(3).fill(45) } };
  const dayNum = s => { const [y, m, d] = s.split('-').map(Number); return Math.round(Date.UTC(y, m - 1, d) / 864e5); };
  /** The night recorded for a day, or null: not measured, never zero. */
  function lastNight(day) {
    const w = weekStart(day), n = NIGHTS[w], i = dayNum(day) - dayNum(w);
    return n && n.rhr[i] != null ? { rhr: n.rhr[i], hrv: n.hrv[i] } : null;
  }

  /* ---------- the fixture on a day, through the stage 1 model ---------- */
  const result = o => R6.evaluate(R6.fixtureInput(o));

  const api = { R6, ORDER, IDS, flags, ALL_ON, ALL_OFF, SOME_ON, present, TODAY, NOW_MIN, hhmm, FRESH_MIN, STALE_MIN, readAt, isStale,
    EVENTS, EXTRA_EVENTS, overlaps, eventsNow, eventNote, marked, NOTE_LIMIT, INTAKE, proteinProgress, proteinSource, SOURCE_DAYS,
    SCAN_DAYS, lastScan, NIGHTS, lastNight, REMINDER, COMPLAINTS, openNiggles, CHECKPOINTS, PHASE_STARTS, nextTimelineDay, result, weekStart };
  if (NODE) module.exports = api; else root.SCM = api;
})(typeof window !== 'undefined' ? window : globalThis,
  typeof module !== 'undefined' && module.exports ? null
    : { evaluate, fixtureInput, weighDay, addDays, weekStart, weeksBetween, quantize, RULES, GENERIC, GENERIC_BAND, FIXTURE_PARAMS, FIXTURE_PHASE });
