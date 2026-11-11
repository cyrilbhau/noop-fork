/* Round combined · the stage 1 presenter and primitives, COPIED UNCHANGED from ../round6-scorecard/scorecard.js
   (the approved round 6) so the shared surfaces word a stage 1 result exactly as the approved frames do.
   Lines copied: 13-19, 22-32, 61-137, 143, 145-146, 159-163, 169, 171, 173-174, 256-257, 281-282, 304.
   Only this wrapper is new: it keeps the copied names out of the page's globals and lets Node load the file.
   Do not edit the copied lines here; change round 6 and copy again. EVERY VALUE IS SYNTHETIC. Declares one global, SCP. */
(function (root, C0) {
  const NODE = typeof module !== 'undefined' && module.exports;
  const M = NODE ? require('./model.js') : root.SCM;
  const { evaluate, fixtureInput, weighDay, addDays, weekStart, weeksBetween, quantize, RULES, GENERIC, GENERIC_BAND, FIXTURE_PARAMS, FIXTURE_PHASE } = M.R6;
  const dayNum = s => { const [y, m, d] = s.split('-').map(Number); return Math.round(Date.UTC(y, m - 1, d) / 864e5); };
  // In the page C is design/system/noop.js's token reader. In Node (checks only) the same tokens are listed here.
  const TOKENS = { '--t1': '#F5F5F7', '--t2': '#9B9BA3', '--recovery': '#2FD27A', '--rec-mid': '#FFC83D', '--rec-low': '#FF5A4F', '--sig-met': '#2FD27A', '--sig-not': '#FFC83D', '--sig-unk': '#8A8A93' };
  const C = C0 || (v => !v ? '#F5F5F7' : TOKENS[v] || v);
  /* ---- copied from round 6, unchanged ---- */
const MON = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'], DOW = ['Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat'];
const sd = d => `${+d.slice(8)} ${MON[+d.slice(5, 7) - 1]}`;
const fd = d => `${DOW[new Date(dayNum(d) * 864e5).getUTCDay()]} ${sd(d)}`;
const METRIC = { w: 'kg', l: 'cm', wf: v => v.toFixed(1), lf: v => v.toFixed(1), rf: v => v.toFixed(2), tf: v => String(+v.toFixed(2)) };
const IMPERIAL = { w: 'lb', l: 'in', wf: v => (v * 2.20462).toFixed(1), lf: v => (v / 2.54).toFixed(1), rf: v => (v * 2.20462).toFixed(2), tf: v => String(+(v * 2.20462).toFixed(1)) };
const minus = s => String(s).replace(/^-/, '−');
const plural = (n, w) => `${n} ${w}${n === 1 ? '' : 's'}`;
const ST = { met: { c: '--sig-met', w: 'Met' }, notMet: { c: '--sig-not', w: 'Not met' }, unknown: { c: '--sig-unk', w: 'Unknown' } };
function glyph(s, z = 24) {
  const c = C(ST[s].c);
  if (s === 'unknown') return `<svg width="${z}" height="${z}" viewBox="0 0 24 24"><circle cx="12" cy="12" r="9.6" fill="none" stroke="#FFFFFF" stroke-opacity=".34" stroke-width="1.7" stroke-dasharray="3 3.3"/></svg>`;
  const mark = s === 'met' ? '<polyline points="7.4,12.4 10.6,15.6 16.8,8.9"' : '<path d="M8.2 8.2l7.6 7.6M15.8 8.2l-7.6 7.6"';
  return `<svg width="${z}" height="${z}" viewBox="0 0 24 24"><circle cx="12" cy="12" r="11" fill="${c}" fill-opacity=".18"/>${mark} fill="none" stroke="${c}" stroke-width="2.2" stroke-linecap="round" stroke-linejoin="round"/></svg>`;
}
// Rule states are neutral: a rule that fired is a fact, not a good or bad week.
const ruleDot = s => s === 'fired' ? '<svg width="18" height="18" viewBox="0 0 18 18"><circle cx="9" cy="9" r="5" fill="#F5F5F7"/></svg>'
  : s === 'notFired' ? '<svg width="18" height="18" viewBox="0 0 18 18"><circle cx="9" cy="9" r="5" fill="none" stroke="#9B9BA3" stroke-width="1.6"/></svg>'
  : '<svg width="18" height="18" viewBox="0 0 18 18"><circle cx="9" cy="9" r="5.6" fill="none" stroke="#FFFFFF" stroke-opacity=".34" stroke-width="1.5" stroke-dasharray="2.4 2.6"/></svg>';
const RULE_NAME = { liftsHoldingWaistShrinking: 'Lifts holding and waist shrinking', liftsDropping: 'Lifts dropping', slowLoss: 'Slow loss' };
const COULD_NOT = { liftsHoldingWaistShrinking: 'Could not check: lifts holding and waist shrinking', liftsDropping: 'Could not check: lifts dropping', slowLoss: 'Could not check: slow loss' };
// Not in §11: why a rule row is unknown. Proposed wording, listed in the README.
const RULE_WHY = { liftSignalUnknown: 'lifts not known', waistSignalUnknown: 'waist not known', fewerWeeksThanWindow: 'the phase is younger than this rule needs', missedWeighIn: 'a week has no weigh-in',
  noActivePhase: 'no cut phase is active', weighInOverdue: 'the last weigh-in is too old', noReadings: 'no weigh-ins yet' };

function present(r, U = METRIC, invalid = false) {
  const inp = r.input, P = inp.parameters, ph = inp.phase, today = inp.today, J = r.judgedWeekStart, rule = k => r.rules.find(x => x.rule === k);
  const vm = { r, U, today };
  const kgw = v => `${U.rf(v)} ${U.w}`;
  // phase header
  if (!ph) vm.phase = null;
  else vm.phase = { lab: r.started ? `Phase · week ${weeksBetween(ph.startDay, today) + 1}` : 'Phase · not started', nm: ph.name,
    meta: `${ph.targetWeightKg == null ? 'No target set' : `Target ${U.wf(ph.targetWeightKg)} ${U.w}`} · ${r.started ? 'started' : 'starts'} ${fd(ph.startDay)} · band ${ph.rateLowPercentPerWeek.toFixed(2)}–${ph.rateHighPercentPerWeek.toFixed(2)}% per week` };
  // verdict
  const V = r.verdict, vd = { lines: [], uneval: V.unevaluatedRules.map(k => COULD_NOT[k]), none: V.kind === 'insufficientData', advice: false };
  if (invalid) { vd.title = 'Your rules need attention'; vd.none = true; vd.uneval = []; }
  else if (V.reason === 'ruleFired' && V.kind === 'holdSteady') { vd.title = 'Change nothing'; vd.lines.push('Lifts are holding and your waist is shrinking.');
    if (V.overriddenRules.length) vd.lines.push(`The scale was slow for ${rule('slowLoss').consecutiveWeeks} weeks. That is expected when waist and lifts are on track.`); }
  else if (V.reason === 'noChangeRuleFired') { vd.title = 'Change nothing'; vd.lines.push('None of your change rules fired.'); }
  else if (V.kind === 'addCalories') { vd.title = `Your rule: add ${V.calorieChangeKcal} kcal`; vd.advice = true; vd.lines.push(`Working weights dropped ${rule('liftsDropping').consecutiveWeeks} weeks running.`);
    if (V.overriddenRules.length) vd.lines.push('The scale was also slow. Your lifts rule comes first.'); }
  else if (V.kind === 'reduceCarbs') { vd.title = `Your rule: take ${-V.calorieChangeKcal} kcal from carbohydrate`; vd.advice = true;
    vd.lines.push(`Loss was under ${U.tf(P.slowLossThresholdKgPerWeek)} ${U.w} per week for ${rule('slowLoss').consecutiveWeeks} weeks.`); }
  else if (V.reason === 'recompositionCheckIncomplete') { vd.title = 'No verdict this week'; vd.lines.push('The scale was slow, but lifts are not known, so a good week cannot be told from a stall.'); }
  else vd.title = { noRuleEvaluable: 'Not enough to judge yet', noReadings: 'Log a weigh-in to begin', noActivePhase: 'No cut phase is active',
    phaseNotStarted: `Your phase starts ${fd(ph ? ph.startDay : today)}`, weighInOverdue: `Last weigh-in ${fd(r.currentWeightDay || today)}` }[V.reason];
  vd.week = J && r.started ? `week of ${sd(J)}` : null;
  vm.verdict = vd;
  // rule rows
  vm.rules = r.rules.map(x => ({ name: RULE_NAME[x.rule], state: x.state, word: x.state === 'fired' ? 'Fired' : x.state === 'notFired' ? 'Not fired' : 'Could not check',
    sub: [x.requiredWeeks > 1 ? `${Math.min(x.consecutiveWeeks, x.requiredWeeks)} of ${plural(x.requiredWeeks, 'week')}` : null, x.state === 'unknown' ? RULE_WHY[x.unknownReason] : null].filter(Boolean).join(' · ') }));
  // signals
  const S = r.signals, over = `Last weigh-in ${fd(r.currentWeightDay || today)}`, generic = x => x.reason === 'weighInOverdue' ? 'No current weigh-in' : x.reason === 'noReadings' ? 'Not measured yet' : null;
  const wa = S.waist, li = S.lifts, pr = S.protein, rb = S.rateBand, win = x => x.windowStartDay ? `${sd(x.windowStartDay)} – ${sd(x.windowEndDay)}` : '';
  const rateText = r.rate ? `${kgw(Math.abs(r.rate.lossKgPerWeek))} per week, ${Math.abs(r.rate.percentPerWeek).toFixed(2)}% of bodyweight` : null;
  vm.sig = [
    { k: 'Waist', s: wa.state, reason: generic(wa) || { shrinking: `Down ${U.lf(-wa.changeCm || 0)} ${U.l} in ${plural(wa.weeks, 'week')}`, notShrinking: 'Not shrinking', noWaistThisWeek: 'Not measured this week', noEarlierWaist: 'Needs an earlier reading' }[wa.reason],
      detail: wa.referenceCm != null ? `${U.lf(wa.currentCm)} ${U.l} now · ${U.lf(wa.referenceCm)} ${U.l} in the week of ${sd(wa.referenceWeekStart)}` : wa.currentCm != null ? `${U.lf(wa.currentCm)} ${U.l} now` : '' },
    { k: 'Working weights', s: li.state, reason: generic(li) || { holding: 'Holding or climbing', dropping: 'Dropping', noLiftData: 'Not known: no imported sessions', noSessionsThisWeek: 'Not known: no sessions in these days',
        noSessionsPriorWeek: 'Not known: nothing to compare with', noCommonExercises: 'Not known: no exercise in common' }[li.reason],
      detail: li.commonExercises ? `${li.climbed} climbed, ${li.held} held, ${li.dropped} dropped of ${plural(li.commonExercises, 'exercise')} · ${win(li)}` : win(li) },
    { k: 'Protein floor', s: pr.state, reason: generic(pr) || { floorMet: `${pr.daysAtOrAboveFloor} of 7 days at or above your floor`, floorMissed: `Below your floor on ${plural(pr.daysLogged - pr.daysAtOrAboveFloor, 'day')}`,
        noFloorConfigured: 'No floor set', noProteinData: 'No protein data', incompleteLogging: 'Not enough days logged' }[pr.reason],
      detail: pr.floorGrams != null && pr.daysLogged ? `Floor ${pr.floorGrams} g · ${pr.daysLogged} of 7 days logged, ${pr.daysAtOrAboveFloor} at or above · needs ${pr.requiredDays}` : pr.floorGrams != null && pr.reason === 'noProteinData' ? `Floor ${pr.floorGrams} g` : '' },
    { k: 'Rate of loss', s: rb.state, reason: generic(rb) || (rb.reason === 'noActivePhase' ? 'No cut phase is active' : rb.reason === 'rateUnknown' ? (r.rateUnavailable === 'singleReading' ? 'Needs a second weigh-in' : `Gap longer than ${P.rateWindowWeeks} weeks`)
        : rb.reason === 'withinBand' ? rateText : rb.reason === 'belowBand' ? 'Below your band' : 'Above your band'),
      detail: rb.percentPerWeek != null ? `${rb.reason === 'withinBand' ? '' : `${r.rate.lossKgPerWeek < 0 ? 'Gaining ' : ''}${rateText} · `}band ${rb.lowPercentPerWeek.toFixed(2)}–${rb.highPercentPerWeek.toFixed(2)}%` : rb.reason === 'noActivePhase' && rateText ? rateText : '' },
  ];
  // curves
  const weeks = r.weekKeys.filter(w => w >= (r.started ? r.domainStart : r.weekKeys[0])), series = m => weeks.map(w => m[w] ? m[w].value : 'x').join(',');
  const lastW = [...weeks].reverse().find(w => r.sp[w]), firstW = weeks.find(w => r.sp[w]);
  vm.weight = r.currentWeightKg == null ? null : { cur: U.wf(r.currentWeightKg), src: `Weighed ${fd(r.currentWeightDay)} · Lab Book`, v: series(r.wp).split(',').map(x => x === 'x' ? x : U.wf(+x)).join(','), l0: sd(weeks[0]), l1: sd(weeks[weeks.length - 1]),
    gain: r.rate && r.rate.lossKgPerWeek < 0, rate: r.rate ? U.rf(Math.abs(r.rate.lossKgPerWeek)) : null, pct: r.rate ? Math.abs(r.rate.percentPerWeek).toFixed(2) : null,
    note: r.rate ? `Line fitted to ${r.rate.pointsUsed} weekly points, weeks of ${sd(r.rate.firstWeekStart)} – ${sd(r.rate.lastWeekStart)}` : vm.sig[3].reason };
  vm.waist = !lastW ? null : { cur: U.lf(r.sp[lastW].value), src: `Measured ${fd(r.sp[lastW].day)} · Lab Book`, v: series(r.sp).split(',').map(x => x === 'x' ? x : U.lf(+x)).join(','), l0: sd(weeks[0]), l1: sd(weeks[weeks.length - 1]),
    a: wa.changeCm != null ? [`Since the week of ${sd(wa.referenceWeekStart)}`, minus(U.lf(wa.changeCm)), U.l] : ['Change', null], b: firstW !== lastW ? [`Since the week of ${sd(firstW)}`, minus(U.lf(r.sp[lastW].value - r.sp[firstW].value)), U.l] : ['Since the first reading', null] };
  // projection
  const pj = r.projection, tgt = ph && ph.targetWeightKg != null ? `${U.wf(ph.targetWeightKg)} ${U.w}` : null;
  vm.proj = { est: pj.status === 'projected', lab: tgt ? `Projection · target ${tgt}` : 'Projection',
    text: { projected: `Estimated ${fd(pj.targetDay || today)} at this rate`, targetReached: 'Target reached', noTarget: 'No target set', notLosing: 'No date while weight is not falling',
      beyondHorizon: `More than ${P.maxProjectionWeeks} weeks at this rate`, needsNewWeighIn: 'Log a weigh-in to check the target', noActivePhase: 'No cut phase is active',
      weighInOverdue: over, rateUnknown: r.rateUnavailable === 'noReadings' ? 'Not measured yet' : r.rateUnavailable === 'singleReading' ? 'Needs a second weigh-in' : `Gap longer than ${P.rateWindowWeeks} weeks` }[pj.status],
    sub: pj.remainingKg > 0 && r.rate && pj.status !== 'needsNewWeighIn' ? `${U.wf(pj.remainingKg)} ${U.w} to go${pj.status === 'projected' ? ` · about ${plural(Math.round(pj.weeksRemaining), 'week')}` : ''}` : '' };
  vm.count = inp.weights.filter(x => x.day <= today).length;
  vm.due = r.started && J && weeksBetween(J, today) >= 1 && V.reason !== 'weighInOverdue';
  vm.reached = pj.status === 'targetReached' ? { t: 'Target reached', d: `${U.wf(r.wp[J].value)} ${U.w} on ${fd(r.wp[J].day)} · target ${tgt}` } : null;
  // §10.1 card: value and caption. The order of these checks is not in the spec; it is listed in the README.
  const inDomain = r.weekKeys.filter(w => w >= r.domainStart && r.wp[w]).length, val = r.currentWeightKg == null ? null : U.wf(r.currentWeightKg), r3 = rule('slowLoss');
  vm.card = !ph || !r.started ? { v: null, c: 'Set up your phase' } : val == null ? { v: null, c: 'Log your first weigh-in' }
    : V.reason === 'weighInOverdue' ? { v: val, c: vd.title, dim: 1 } : vm.due ? { v: val, c: 'Weigh-in due this week' } : inDomain === 1 ? { v: val, c: 'First weigh-in logged' }
    : vm.reached ? { v: val, c: 'Target reached' } : V.reason === 'recompositionCheckIncomplete' ? { v: val, c: 'Lifts not known this week' }
    : V.reason === 'noRuleEvaluable' ? { v: val, c: `Building: ${r3.consecutiveWeeks} of ${r3.requiredWeeks} weeks` } : { v: val, c: vd.title };
  return vm;
}
const FX = (o, U, invalid) => present(evaluate(fixtureInput(o)), U, invalid);
const wk = k => FX({ today: weighDay(k) });
const tile = (icon, tint, title, val, unit, cap, o = {}) => `<div class="yc motion"><div class="hd" style="color:var(${tint})"><span data-ic="${icon}" data-s="16"></span><b>${title}</b>${o.nolink ? '' : '<span class="chev">›</span>'}</div><div class="v num${val == null ? ' none' : o.dim ? ' tert' : ''}">${val == null ? '—' : val}${val != null && unit ? `<small>${unit}</small>` : ''}</div><div class="c">${cap}</div></div>`;
const scTile = (c, U = METRIC) => tile('scale', '--t1', 'Scorecard', c.v, U.w, c.c, { dim: c.dim });
const skTile = `<div class="yc"><div class="skb" style="width:62%;height:13px"></div><div class="skb" style="width:54%;height:24px;margin-top:auto"></div><div class="skb" style="width:80%;height:12px"></div></div>`;
const AMB = vm => { const m = vm.sig.filter(x => x.s === 'met').length, n = vm.sig.filter(x => x.s === 'notMet').length, a = [];
  if (m) a.push(['--recovery', 70, 0, 150 + 45 * m, +(.10 + .06 * m).toFixed(2)]); if (n) a.push(['--rec-mid', 350, 30, 140 + 50 * n, +(.10 + .07 * n).toFixed(2)]);
  return `data-ambient='${JSON.stringify(a)}' data-ambh="520"`; };
const count = v => `<span data-count="${v}" data-dec="1">${v}</span>`;
const kvCell = ([k, v, u]) => `<div><div class="k">${k}</div><div class="v num${v == null ? ' none' : ''}">${v == null ? '—' : v}${v != null && u ? `<small>${u}</small>` : ''}</div></div>`;
const emptyCurves = `<div class="card cv"><div class="lab">Weight and waist</div><div class="big num none" style="margin-top:6px">—</div><div class="lab" style="margin-top:8px">Not measured yet</div></div>`;
const ruleRows = rules => rules.map(x => `<div class="rrow">${ruleDot(x.state)}<div class="grow1"><div class="rk">${x.name}</div>${x.sub ? `<div class="rs">${x.sub}</div>` : ''}</div><div class="rw ${x.state}">${x.word}</div></div>`).join('');
const nrow = (t, v, ch = 1) => `<div class="nrow"><div class="t">${t}</div><div class="val">${v}</div>${ch ? '<span class="chev">›</span>' : ''}</div>`;
const grp = rows => `<div class="wrap"><div class="card" style="padding:4px 18px">${rows.join('<div class="sep"></div>')}</div></div>`;
const gh = (t, first) => `<div class="gh"${first ? ' style="padding-top:10px"' : ''}>${t}</div>`;
const gf = t => `<div class="gf">${t}</div>`;
const NOTIF = `<div class="notif"><div class="ai" data-ic="today" data-s="22"></div><div class="grow1"><div class="row gap8"><div class="nt">Weekly weigh-in</div><div class="nw">08:00</div></div><div class="nb">Weight, then waist. It takes under a minute.</div></div></div>`;
const tog = (t, on) => `<div class="nrow"><div class="t">${t}</div><div class="toggle${on ? ' on' : ''}"></div></div>`;
const er = (sign, title, sub) => `<div class="nrow"><span class="pm ${sign}">${sign === 'add' ? '+' : '−'}</span><div class="grow1"><div class="t">${title}</div>${sub ? `<div class="rs">${sub}</div>` : ''}</div></div>`;
  /* ---- end of the copied lines ---- */
  const api = { MON, DOW, sd, fd, METRIC, IMPERIAL, minus, plural, ST, glyph, ruleDot, RULE_NAME, COULD_NOT, RULE_WHY, present, FX, wk,
    tile, scTile, skTile, AMB, count, kvCell, emptyCurves, ruleRows, nrow, grp, gh, gf, NOTIF, tog, er, dayNum, C };
  if (NODE) module.exports = api; else root.SCP = api;
})(typeof window !== 'undefined' ? window : globalThis, typeof C === 'function' ? C : null);
