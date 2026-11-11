/* Round S5 design model of the events layer, written from docs/personal/superapp/specs/stage-5.md
   (§7 overlap, §10.5 marks and captions, §10.6 scorecard note, §10.9 presenter, §11 strings, §13 fixture).
   It exists so that every number, date and line drawn in a frame is computed, not typed. It is a mockup aid:
   it is NOT the implementation and has no tests of its own beyond check.js.
   The person is the ONE Fixture Person of stage 1 §13: weights, waists, lifts, protein, phase and the
   scorecard come from ../round6-scorecard/model.js, which this file imports and never restates.
   EVERY VALUE IS SYNTHETIC ("Fixture Person" does not exist). */
(function (root) {
  const S1 = typeof module !== 'undefined' && module.exports ? require('../round6-scorecard/model.js')
    : { evaluate, fixtureInput, weighDay, addDays, weekStart, weeksBetween, FIXTURE_PARAMS, FIXTURE_PHASE };   // browser: globals of the stage 1 model

  /* ---------- days (§7.1): canonical ten-character keys; comparison is string comparison ---------- */
  const num = s => { if (typeof s !== 'string' || !/^\d{4}-\d{2}-\d{2}$/.test(s)) return null; const [y, m, d] = s.split('-').map(Number);
    if (y < 1) return null; const t = new Date(Date.UTC(2000, m - 1, d)); t.setUTCFullYear(y);
    return t.getUTCMonth() === m - 1 && t.getUTCDate() === d ? Math.round(t.getTime() / 864e5) : null; };
  const key = n => new Date(n * 864e5).toISOString().slice(0, 10);
  const add = (s, k) => key(num(s) + k);
  const weekOf = s => { const n = num(s); return key(n - (new Date(n * 864e5).getUTCDay() + 6) % 7); };
  const dow = s => new Date(num(s) * 864e5).getUTCDay();
  const span = (a, b) => { const out = []; for (let d = a; d <= b; d = add(d, 1)) out.push(d); return out; };

  /* ---------- §11 strings. Every word a frame shows from this stage comes from here. ---------- */
  const STR = {
    kind: { travel: 'Travel', illness: 'Illness', dietBreak: 'Diet break', deload: 'Deload', supplementChange: 'Supplement change', custom: 'Something else' },
    privateEvent: 'Private event', tag: 'Private',
    range: '%@ – %@', since: 'Since %@', sinceLower: 'since %@', from: 'From %@',
    healthRow: 'Events', healthValue: '%lld now',
    screen: 'Events', now: 'Now', upcoming: 'Upcoming', earlier: 'Earlier', add: 'Add event', endToday: 'End today',
    emptyTitle: 'No events yet', emptyBody: 'Add travel, illness, a diet break or a deload, and charts will show when it happened.',
    unreadableEntries: '%lld entries could not be read. They are kept.',
    storeTitle: 'Your events could not be read', storeBody: 'Nothing has been changed. You can copy the stored text before starting again.',
    copyStored: 'Copy stored text', startAgain: 'Start again', startAgainAsk: 'Start again and discard the stored events?',
    newEvent: 'New event', editEvent: 'Edit event', kindLabel: 'Kind', name: 'Name', nameNeeded: 'A name is needed', starts: 'Starts', length: 'Length',
    oneDay: 'One day', until: 'Until', ongoing: 'Ongoing', ends: 'Ends', endRule: 'Must be on or after the start', planned: 'Planned: this starts in the future',
    note: 'Note', privateSwitch: 'Private', privateFoot: 'Private events show as "Private event" outside this screen.', save: 'Save', saveFailed: 'Could not save. Try again.',
    deleteTitle: 'Delete this event?', deleteWarning: 'This cannot be undone.', del: 'Delete', cancel: 'Cancel',
    line: '%@ · %@', more: 'and %lld more',
    noteTitle: 'Events this week', noteEarlier: 'Earlier in the weeks behind this verdict', noteFoot: 'Shown for context. Events do not change the verdict.',
    settingsCard: 'Events', settingsSwitch: 'Personal events',
    spoken: 'Events:',
    // §9.6, added by the packet v2 change, drawn here as frames for that change only
    packetSwitch: 'Include private events in the coach packet', packetFoot: 'Private events and their notes stay out of the packet unless this is on.',
    packetSheetLine: 'Private events stay out of the coach packet unless you include them in Settings.',
  };
  /* Strings §11 does not give. Each is a proposal and is listed in the README. */
  const PROPOSED = {
    entryOne: '%lld entry could not be read. It is kept.',     // singular of the unreadable-entries line
    noteLeft: '%lld left',                                      // remaining count on the note, from 240 characters on
    edit: 'Edit',                                               // swipe action on a row
  };
  const fill = (tpl, ...a) => { let i = 0; return tpl.replace(/%@|%lld/g, () => a[i++]); };

  /* ---------- kinds (§7.2) ---------- */
  const KINDS = ['travel', 'illness', 'dietBreak', 'deload', 'supplementChange', 'custom'];
  const DEFAULT_SENSITIVE = { travel: false, illness: true, dietBreak: false, deload: false, supplementChange: false, custom: true };

  /* ---------- fixture (§13.1) ---------- */
  const ev = (id, kind, label, startDay, endDay, note, sensitive, createdAt) => ({ id, kind, label, startDay, endDay, note, sensitive, createdAt });
  const EVENTS = [
    ev('e1', 'travel', null, '2031-03-10', '2031-03-16', 'Fixture trip', false, 1000),
    ev('e2', 'deload', null, '2031-02-03', '2031-02-09', null, false, 1001),
    ev('e3', 'dietBreak', null, '2031-04-14', '2031-04-27', null, false, 1002),
    ev('e4', 'supplementChange', null, '2031-01-22', '2031-01-22', null, false, 1003),
    ev('e5', 'illness', null, '2031-05-19', null, null, true, 1004),
    ev('e6', 'custom', 'Fixture change', '2031-03-26', '2031-03-26', 'Fixture note', true, 1005),
    ev('e7', 'travel', null, '2030-12-01', '2030-12-07', null, false, 1006),
    ev('e8', 'travel', null, '2031-02-22', '2031-02-24', null, false, 1007),
  ];
  const E = id => EVENTS.find(e => e.id === id);
  const VARIANTS = {
    V1: [],
    V2: EVENTS.filter(e => e.id === 'e5' || e.id === 'e6'),
    V5: EVENTS.map(e => e.id === 'e5' ? { ...e, endDay: '2031-05-25' } : e),
    V9: EVENTS.map(e => e.id === 'e2' || e.id === 'e3' ? { ...e, sensitive: true } : e),
    // Design-only variants, outside §13.4 (listed in the README):
    DOpen: EVENTS.map(e => e.id === 'e5' ? { ...e, sensitive: false } : e),                     // the owner switched Private off on the ongoing illness
    DMany: EVENTS.concat([ev('d1', 'deload', null, '2031-04-15', '2031-04-15', null, false, 1010), ev('d2', 'travel', null, '2031-04-16', '2031-04-17', null, false, 1011),
      ev('d3', 'supplementChange', null, '2031-04-18', '2031-04-18', null, false, 1012)]),   // four events in week 15
    DUpcoming: EVENTS.filter(e => ['e1', 'e3', 'e5'].includes(e.id)),                          // seen from Wed 8 Jan: all in the future
  };

  /* ---------- validation, order, overlap (§7.3, §7.4) ---------- */
  const trim = s => s == null ? s : s.replace(/^[\s\n]+|[\s\n]+$/g, '');
  function issues(e) {
    const out = [];
    if (!e.id) out.push('emptyId');
    if (num(e.startDay) == null) out.push('invalidStartDay');
    if (e.endDay != null && num(e.endDay) == null) out.push('invalidEndDay');
    if (num(e.startDay) != null && e.endDay != null && num(e.endDay) != null && e.endDay < e.startDay) out.push('endBeforeStart');
    if (e.kind === 'custom' && !trim(e.label)) out.push('missingLabel');
    if (e.kind !== 'custom' && e.label != null) out.push('unexpectedLabel');
    if (e.label != null && [...e.label].length > 40) out.push('labelTooLong');
    if (e.note != null && [...e.note].length > 280) out.push('noteTooLong');
    if (e.note != null && !trim(e.note)) out.push('emptyNote');
    return out;
  }
  function normalized(list) {
    const last = new Map(); list.forEach(e => { if (!issues(e).length) { last.delete(e.id); last.set(e.id, e); } });
    return [...last.values()].sort((a, b) => a.startDay < b.startDay ? -1 : a.startDay > b.startDay ? 1 : (a.createdAt - b.createdAt) || (a.id < b.id ? -1 : 1));
  }
  function relation(e, a, b) {
    if (num(a) == null || num(b) == null || b < a || issues(e).length) return null;
    const s = e.startDay, x = e.endDay;
    if (x != null && x < a) return 'before';
    if (s > b) return 'after';
    if (s >= a) return x != null && x <= b ? 'within' : 'startsWithin';
    return x != null && x <= b ? 'endsWithin' : 'covers';
  }
  const overlaps = (e, a, b) => { const r = relation(e, a, b); return r != null && r !== 'before' && r !== 'after'; };
  const overlapping = (list, a, b) => normalized(list).filter(e => overlaps(e, a, b));
  const overlappingWeek = (list, w) => num(w) != null && weekOf(w) === w ? overlapping(list, w, add(w, 6)) : [];
  const coveredSlots = (list, slots) => { const n = normalized(list); return slots.map(sl => n.some(e => overlaps(e, sl.firstDay, sl.lastDay))); };
  const daySlots = days => days.map(d => ({ firstDay: d, lastDay: d }));
  const weekSlots = weeks => weeks.map(w => ({ firstDay: w, lastDay: add(w, 6) }));
  const newestFirst = list => normalized(list).reverse();

  /* ---------- dates as text. en_GB day and short month; the year is added only when it differs from today's (README) ---------- */
  const MON = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'], DOW = ['Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat'];
  const sd = d => `${+d.slice(8)} ${MON[+d.slice(5, 7) - 1]}`;
  const fd = d => `${DOW[dow(d)]} ${sd(d)}`;
  const yr = (d, today) => d.slice(0, 4) === today.slice(0, 4) ? '' : ` ${d.slice(0, 4)}`;
  function dateText(e, today, lower) {
    if (e.endDay == null) return fill(e.startDay > today ? STR.from : lower ? STR.sinceLower : STR.since, sd(e.startDay) + yr(e.startDay, today));
    if (e.endDay === e.startDay) return sd(e.startDay) + yr(e.startDay, today);
    const sameMonth = e.startDay.slice(0, 7) === e.endDay.slice(0, 7);
    return fill(STR.range, sameMonth ? String(+e.startDay.slice(8)) : sd(e.startDay) + (e.startDay.slice(0, 4) === e.endDay.slice(0, 4) ? '' : yr(e.startDay, today)), sd(e.endDay) + yr(e.endDay, today));
  }
  const kindName = k => STR.kind[k];
  /** One line for an event outside the Events screen (§10.9): never the label of a sensitive event, never a note. */
  const outsideLine = (e, today) => fill(STR.line, e.sensitive ? STR.privateEvent : kindName(e.kind), dateText(e, today, true));

  /* ---------- Events screen (§10.2, §10.9) ---------- */
  function present(list, today, o = {}) {
    if (o.needsAttention) return { state: 'storeUnreadable', now: [], upcoming: [], earlier: [], unreadableEntriesText: null, healthRowValue: null };
    const row = e => ({ id: e.id, title: e.kind === 'custom' ? e.label : kindName(e.kind), dateText: dateText(e, today, false),
      noteFirstLine: e.note ? e.note.split('\n')[0] : null, isPrivate: e.sensitive, offersEndToday: e.endDay == null && e.startDay <= today });
    const all = newestFirst(list), now = all.filter(e => overlaps(e, today, today)), n = o.unreadableEntryCount || 0;
    return { state: all.length ? 'rows' : 'empty', now: now.map(row), upcoming: all.filter(e => e.startDay > today).map(row),
      earlier: all.filter(e => e.endDay != null && e.endDay < today).map(row),
      unreadableEntriesText: n ? fill(n === 1 ? PROPOSED.entryOne : STR.unreadableEntries, n) : null,
      healthRowValue: now.length ? fill(STR.healthValue, now.length) : null };
  }
  function deleteConfirmation(e, today) {
    return { title: STR.deleteTitle, detail: fill(STR.line, e.kind === 'custom' ? e.label : kindName(e.kind), dateText(e, today, false)), warning: STR.deleteWarning, confirmTitle: STR.del, cancelTitle: STR.cancel };
  }
  const endToday = (list, id, today) => list.map(e => e.id === id ? { ...e, endDay: today } : e);

  /* ---------- chart caption (§10.5) ---------- */
  function caption(list, firstDay, lastDay, today) {
    const hit = overlapping(list, firstDay, lastDay).reverse();          // latest start first
    if (!hit.length) return null;
    const lines = hit.slice(0, 2).map(e => outsideLine(e, today)), moreText = hit.length > 2 ? fill(STR.more, hit.length - 2) : null;
    return { lines, moreText, spokenText: [STR.spoken].concat(lines, moreText || []).join(', ').replace(`${STR.spoken}, `, `${STR.spoken} `) };
  }

  /* ---------- marks (§10.5): fractions along the plot, then offsets thinned to a minimum spacing ---------- */
  const TOKENS = { chartAxisMark: 4, chartAxisMarkRow: 8, chartAxisMarkSpacing: 6 };   // proposed NoopTheme.Layout values
  const fractions = (covered, style) => covered.map((_, i) => style === 'bars' ? (i + 0.5) / covered.length : covered.length === 1 ? 0.5 : i / (covered.length - 1));
  /** x offsets of the marks kept. Within each unbroken run the first and last are always kept. */
  function markOffsets(covered, style, width, leading, trailing, minSpacing = TOKENS.chartAxisMarkSpacing) {
    const f = fractions(covered, style), x = i => +(leading + f[i] * (width - leading - trailing)).toFixed(2), out = [];
    for (let i = 0; i < covered.length; i++) { if (!covered[i]) continue; let j = i; while (j + 1 < covered.length && covered[j + 1]) j++;
      const kept = [i]; for (let k = i + 1; k < j; k++) if (x(k) - x(kept[kept.length - 1]) >= minSpacing && x(j) - x(k) >= minSpacing) kept.push(k);
      if (j > i) kept.push(j); kept.forEach(k => out.push({ index: k, x: x(k), open: false })); i = j; }
    return out;
  }
  /** The other option of §17: per event, a filled dot at its start slot and an open dot at its end slot. */
  function markEnds(list, slots, style, width, leading, trailing) {
    const f = fractions(slots, style), x = i => +(leading + f[i] * (width - leading - trailing)).toFixed(2), out = new Map();
    overlapping(list, slots[0].firstDay, slots[slots.length - 1].lastDay).forEach(e => {
      const a = slots.findIndex(sl => e.startDay >= sl.firstDay && e.startDay <= sl.lastDay), b = e.endDay == null ? -1 : slots.findIndex(sl => e.endDay >= sl.firstDay && e.endDay <= sl.lastDay);
      if (a >= 0) out.set(a, { index: a, x: x(a), open: false });
      if (b >= 0 && b !== a && !out.has(b)) out.set(b, { index: b, x: x(b), open: true }); });
    return [...out.values()].sort((p, q) => p.index - q.index);
  }

  /* ---------- scorecard note (§10.6). `result` is the stage 1 model's result for the same day. ---------- */
  function evidenceStartDay(result) {   // stage 1 §7.9
    const P = result.input.parameters, m = Math.max(P.rateWindowWeeks, P.waistWindowWeeks, P.slowLossConsecutiveWeeks, P.liftDropConsecutiveWeeks);
    return result.judgedWeekStart ? add(result.judgedWeekStart, -7 * (m + 2)) : null;
  }
  function eventNote(result, list, today, o = {}) {
    const J = result.judgedWeekStart, why = result.verdict.reason;
    if (!J || why === 'noReadings' || why === 'weighInOverdue') return null;
    const sunday = add(J, 6), judged = overlappingWeek(list, J).reverse(), ids = new Set(judged.map(e => e.id));
    const earlier = o.judgedWeekOnly ? [] : overlapping(list, evidenceStartDay(result), sunday).filter(e => !ids.has(e.id)).reverse();
    if (!judged.length && !earlier.length) return null;
    const cut = Math.max(0, judged.length - 3) + Math.max(0, earlier.length - 3), line = e => outsideLine(e, today);
    return { title: STR.noteTitle, lines: judged.slice(0, 3).map(line), earlierTitle: earlier.length ? STR.noteEarlier : null, earlierLines: earlier.slice(0, 3).map(line),
      moreText: cut ? fill(STR.more, cut) : null, footnote: STR.noteFoot };
  }
  /** The stage 1 fixture on `today`, and the weeks its curves show (one per point), with their covered flags. */
  function scorecardDay(today, list, o = {}) {
    const result = S1.evaluate(S1.fixtureInput({ today, ...(o.fixture || {}) }));
    const weeks = result.weekKeys.filter(w => w >= (result.started ? result.domainStart : result.weekKeys[0]));
    return { result, weeks, marked: coveredSlots(list, weekSlots(weeks)), note: eventNote(result, list, today, o),
      caption: weeks.length ? caption(list, weeks[0], add(weeks[weeks.length - 1], 6), today) : null };
  }

  /* ---------- event sheet (§10.3, §10.9): the draft as a small reducer, so a frame's Private switch is derived ---------- */
  function draft(today, actions = [], editing = null) {
    let d = editing ? { kind: editing.kind, label: editing.label || '', start: editing.startDay, length: editing.endDay == null ? 'ongoing' : editing.endDay === editing.startDay ? 'oneDay' : 'until',
      end: editing.endDay || editing.startDay, note: editing.note || '', isPrivate: editing.sensitive }
      : { kind: 'travel', label: '', start: today, length: 'oneDay', end: today, note: '', isPrivate: DEFAULT_SENSITIVE.travel };
    let touched = false;
    actions.forEach(([what, v]) => {
      if (what === 'kind') { d.kind = v; if (!touched) d.isPrivate = DEFAULT_SENSITIVE[v]; }
      else if (what === 'private') { d.isPrivate = v; touched = true; }
      else d[what] = v; });
    const asEvent = { id: editing ? editing.id : 'new', kind: d.kind, label: d.kind === 'custom' ? d.label : null, startDay: d.start,
      endDay: d.length === 'ongoing' ? null : d.length === 'oneDay' ? d.start : d.end, note: d.note === '' ? null : d.note, sensitive: d.isPrivate, createdAt: editing ? editing.createdAt : 2000 };
    const iss = issues(asEvent), len = [...d.note].length;
    return { ...d, issues: iss, canSave: iss.length === 0, isPlanned: d.start > today, noteRemaining: len >= 240 ? 280 - len : null, isEdit: !!editing };
  }
  const LONG_NOTE = Array.from({ length: 18 }, (_, i) => `Fixture note line ${i + 1}.`).join(' ').slice(0, 252);   // 252 characters of invented text

  /* ---------- daily series for the day-axis charts.
     Stage 1 §13 gives the Fixture Person weekly weights only. Recovery, sleep and steps per day are derived here by a
     fixed hash of the day number, so the same day always draws the same value and nothing is typed. The strap is taken
     as not worn on two days of the fixture trip, which gives the "not measured" gap. Listed in the README. ---------- */
  const NOT_WORN = ['2031-03-13', '2031-03-14'];
  const hash = (n, salt) => { let x = Math.imul((n + salt * 7919) | 0, 0x85EBCA6B); x ^= x >>> 13; x = Math.imul(x, 0xC2B2AE35); x ^= x >>> 16; return (x >>> 0) / 4294967296; };
  const blend = (d, salt) => { const n = num(d); return (hash(n - 1, salt) + 2 * hash(n, salt) + hash(n + 1, salt)) / 4; };
  const DAILY = {
    recovery: d => NOT_WORN.includes(d) ? null : Math.round(34 + 58 * blend(d, 1)),            // percent
    sleep: d => NOT_WORN.includes(d) ? null : +(5.9 + 2.4 * blend(d, 2)).toFixed(1),           // hours
    steps: d => Math.round((3800 + 8400 * blend(d, 3)) / 10) * 10,                              // Apple Health count; the phone was carried
  };
  /** A day-axis chart window ending on `today`: days, values (null = not measured), covered flags, caption. */
  function dayWindow(metric, today, days, list) {
    const keys = span(add(today, -(days - 1)), today);
    return { metric, today, keys, values: keys.map(DAILY[metric]), covered: coveredSlots(list, daySlots(keys)), caption: caption(list, keys[0], today, today),
      latest: [...keys].reverse().map(DAILY[metric]).find(v => v != null) };
  }

  /** A calendar month as rows of cells for the date picker drawing (Monday first). */
  function month(day) {
    const first = day.slice(0, 8) + '01', lead = (dow(first) + 6) % 7, cells = [];
    for (let d = add(first, -lead); cells.length < 42; d = add(d, 1)) { if (cells.length >= 35 && d.slice(0, 7) !== day.slice(0, 7)) break; cells.push({ day: d, n: +d.slice(8), inMonth: d.slice(0, 7) === day.slice(0, 7) }); }
    return { title: `${['January', 'February', 'March', 'April', 'May', 'June', 'July', 'August', 'September', 'October', 'November', 'December'][+day.slice(5, 7) - 1]} ${day.slice(0, 4)}`, cells };
  }

  const api = { S1, STR, PROPOSED, KINDS, DEFAULT_SENSITIVE, EVENTS, E, VARIANTS, TOKENS, num, key, add, weekOf, span, sd, fd, fill,
    issues, normalized, relation, overlaps, overlapping, overlappingWeek, coveredSlots, daySlots, weekSlots, dateText, kindName, outsideLine,
    present, deleteConfirmation, endToday, caption, fractions, markOffsets, markEnds, evidenceStartDay, eventNote, scorecardDay, draft, LONG_NOTE,
    NOT_WORN, DAILY, dayWindow, month };
  if (typeof module !== 'undefined' && module.exports) module.exports = api; else root.S5M = api;
})(typeof window !== 'undefined' ? window : globalThis);
