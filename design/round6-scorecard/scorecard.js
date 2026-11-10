/* Round 6 · Cut scorecard (Stage 1). Every frame is drawn from model.js: the §13 fixture is run through a
   design model of §7 and the result is turned into the §11 strings here. Nothing below types a result by hand.
   EVERY VALUE IS SYNTHETIC ("Fixture Person", a fictional cut from Mon 6 Jan 2031, target 94.0 kg). */

/* ---------- local icons (noop.js ICONS is not edited; ic('cal') resolves #i-cal) ---------- */
document.body.insertAdjacentHTML('afterbegin', `<svg width="0" height="0" style="position:absolute"><defs>
<symbol id="i-cal" viewBox="0 0 24 24"><rect x="4" y="5.5" width="16" height="15" rx="3.5" fill="none" stroke="currentColor" stroke-width="1.9"/><path d="M4 10.5h16M8.5 3.5v4M15.5 3.5v4" fill="none" stroke="currentColor" stroke-width="1.9" stroke-linecap="round"/></symbol>
<symbol id="i-trash" viewBox="0 0 24 24"><path d="M5 7h14M10 4h4M7 7l1 12.5h8L17 7M10.5 11v5M13.5 11v5" fill="none" stroke="currentColor" stroke-width="1.9" stroke-linecap="round" stroke-linejoin="round"/></symbol>
<symbol id="i-pencil" viewBox="0 0 24 24"><path d="M5 19l1-4L16.5 4.5l3 3L9 18zM14.5 6.5l3 3" fill="none" stroke="currentColor" stroke-width="1.9" stroke-linecap="round" stroke-linejoin="round"/></symbol>
</defs></svg>`);

/* ---------- formatting ---------- */
const MON = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'], DOW = ['Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat'];
const sd = d => `${+d.slice(8)} ${MON[+d.slice(5, 7) - 1]}`;
const fd = d => `${DOW[new Date(dayNum(d) * 864e5).getUTCDay()]} ${sd(d)}`;
const METRIC = { w: 'kg', l: 'cm', wf: v => v.toFixed(1), lf: v => v.toFixed(1), rf: v => v.toFixed(2), tf: v => String(+v.toFixed(2)) };
const IMPERIAL = { w: 'lb', l: 'in', wf: v => (v * 2.20462).toFixed(1), lf: v => (v / 2.54).toFixed(1), rf: v => (v * 2.20462).toFixed(2), tf: v => String(+(v * 2.20462).toFixed(1)) };
const minus = s => String(s).replace(/^-/, '−');
const plural = (n, w) => `${n} ${w}${n === 1 ? '' : 's'}`;

/* ---------- signal states: met / not met / unknown. Shape and word carry the state; colour repeats it. ---------- */
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

/* ---------- weekly chart: line, gradient area, one point per weekly reading. No rules, bands or target lines.
   A week with no reading breaks the line (§10.2); it is never drawn across.
   <svg class="wk" data-v="100,99.2,x,98.4" data-l0 data-l1 data-fs> ---------- */
function weekChart(svg) {
  const d = svg.dataset, v = d.v.split(',').map(x => x === 'x' ? null : +x), c = C(d.c || '--t1');
  const fs = +(d.fs || 11), w = +svg.getAttribute('width'), H = +svg.getAttribute('height'), h = H - fs - 11, n = v.length;
  const real = v.filter(x => x !== null); let mn = Math.min(...real), mx = Math.max(...real); const span = (mx - mn) || 1; mn -= span * .14; mx += span * .14;
  const X = i => +(8 + i * (w - 16) / Math.max(1, n - 1)).toFixed(2), Y = x => +(12 + (1 - (x - mn) / (mx - mn)) * (h - 20)).toFixed(2);
  const id = 'wk' + (gid++), df = el('defs', {}, svg);
  const ga = el('linearGradient', { id: 'a' + id, x1: 0, y1: 12, x2: 0, y2: h, gradientUnits: 'userSpaceOnUse' }, df); el('stop', { offset: 0, 'stop-color': c, 'stop-opacity': .28 }, ga); el('stop', { offset: 1, 'stop-color': c, 'stop-opacity': 0 }, ga);
  const gs = el('linearGradient', { id: 's' + id, x1: 0, y1: 0, x2: w, y2: 0, gradientUnits: 'userSpaceOnUse' }, df); el('stop', { offset: 0, 'stop-color': c, 'stop-opacity': .35 }, gs); el('stop', { offset: 1, 'stop-color': c, 'stop-opacity': 1 }, gs);
  const runs = []; let cur = null; v.forEach((x, i) => { if (x === null) { cur = null; return; } if (!cur) runs.push(cur = []); cur.push([X(i), Y(x)]); });
  runs.forEach(pts => { if (pts.length < 2) return; const line = smooth(pts), a = pts[0], b = pts[pts.length - 1];
    el('path', { class: 'area', d: `${line} L${b[0]},${h} L${a[0]},${h} Z`, fill: `url(#a${id})` }, svg);
    el('path', { class: 'stroke', d: line, fill: 'none', stroke: `url(#s${id})`, 'stroke-width': 2.5, 'stroke-linecap': 'round', 'stroke-linejoin': 'round' }, svg); });
  const all = runs.flat();
  all.forEach((p, i) => { const last = i === all.length - 1;
    if (last) el('circle', { class: 'halo', cx: p[0], cy: p[1], r: 8, fill: c, opacity: .22 }, svg);
    el('circle', { class: 'pt', cx: p[0], cy: p[1], r: last ? 4 : 2.6, fill: c, stroke: '#0B0B0D', 'stroke-width': last ? 1.5 : 1.2 }, svg); });
  // A week with no reading: an open ring on the time axis.
  v.forEach((x, i) => { if (x === null) el('circle', { cx: X(i), cy: h + 3, r: 2.6, fill: 'none', stroke: '#FFFFFF', 'stroke-opacity': .4, 'stroke-width': 1.2 }, svg); });
  const text = (x, s, anchor) => { const t = el('text', { x, y: H - 3, 'text-anchor': anchor, fill: '#9B9BA3', 'font-size': fs, 'font-weight': 500, 'font-family': '-apple-system,system-ui' }, svg); t.textContent = s; };
  if (d.l0) text(X(0) - 4, d.l0, 'start');
  if (d.l1 && n > 1) text(X(n - 1) + 4, d.l1, 'end');
}

/* ---------- presenter: result -> the §11 strings ---------- */
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

/* ---------- Today pieces ---------- */
const todayTop = date => `<div class="sb"></div>
  <div class="hdr"><div><div class="lt">Today</div><div class="sub">${date}</div></div><div class="row gap10"><div class="pill"><span class="dot" style="background:var(--recovery)"></span><span class="num">84%</span></div><div class="ibtn" data-ic="person" data-s="22"></div></div></div>
  <div class="wrap" style="margin-top:20px"><div class="card" style="padding:18px 14px 16px"><div class="rings" data-s="86" data-r="68" data-st="11.4"></div></div></div>`;
const tile = (icon, tint, title, val, unit, cap, o = {}) => `<div class="yc motion"><div class="hd" style="color:var(${tint})"><span data-ic="${icon}" data-s="16"></span><b>${title}</b>${o.nolink ? '' : '<span class="chev">›</span>'}</div><div class="v num${val == null ? ' none' : o.dim ? ' tert' : ''}">${val == null ? '—' : val}${val != null && unit ? `<small>${unit}</small>` : ''}</div><div class="c">${cap}</div></div>`;
const STRESS = tile('bolt', '--stress', 'Stress', '1.4', 'of 3', 'Moderate'), FIT = tile('run', '--recovery', 'Fitness age', '≤ 34', 'yrs', 'as of 26 Jan');
const scTile = (c, U = METRIC) => tile('scale', '--t1', 'Scorecard', c.v, U.w, c.c, { dim: c.dim });
const skTile = `<div class="yc"><div class="skb" style="width:62%;height:13px"></div><div class="skb" style="width:54%;height:24px;margin-top:auto"></div><div class="skb" style="width:80%;height:12px"></div></div>`;
// Not in the spec: a full-width card that also carries the four signals. Drawn as a question for the owner.
function wideCard(vm) {
  return `<div class="yc wide scc motion"><div class="hd"><span data-ic="scale" data-s="16"></span><b>Scorecard</b><span class="chev">›</span></div>
    <div class="top"><div><div class="vd">${vm.verdict.title}</div><div class="vs">${vm.card.v} ${vm.U.w} · weighed ${fd(vm.r.currentWeightDay)}</div></div><svg class="line" data-c="--t1" data-v="${vm.weight.v.replace(/x,?/g, '')}" width="84" height="34"></svg></div>
    <div class="sigs">${vm.sig.map(x => `<span class="sg ${x.s === 'unknown' ? 'unk' : ''}">${glyph(x.s, 16)}${x.k.split(' ')[0] === 'Working' ? 'Lifts' : x.k.split(' ')[0]}</span>`).join('')}</div></div>`;
}
const todayFrame = (date, cards) => `${todayTop(date)}
  <div class="sec"><h3>Your cards</h3><a>Edit<span class="chev">›</span></a></div>
  <div class="wrap"><div class="ycgrid">${cards}</div></div>
  <div class="tabbar" data-on="0"></div><div class="home"></div>`;

/* ---------- scorecard screen ---------- */
const AMB = vm => { const m = vm.sig.filter(x => x.s === 'met').length, n = vm.sig.filter(x => x.s === 'notMet').length, a = [];
  if (m) a.push(['--recovery', 70, 0, 150 + 45 * m, +(.10 + .06 * m).toFixed(2)]); if (n) a.push(['--rec-mid', 350, 30, 140 + 50 * n, +(.10 + .07 * n).toFixed(2)]);
  return `data-ambient='${JSON.stringify(a)}' data-ambh="520"`; };
const count = v => `<span data-count="${v}" data-dec="1">${v}</span>`;
const kvCell = ([k, v, u]) => `<div><div class="k">${k}</div><div class="v num${v == null ? ' none' : ''}">${v == null ? '—' : v}${v != null && u ? `<small>${u}</small>` : ''}</div></div>`;
function curve(title, unit, c, kv, tail, ax) {
  return `<div class="card cv"><div class="lab">${title}</div><div class="big num">${count(c.cur)}<small>${unit}</small></div><div class="src" style="margin-top:8px"><i></i>${c.src}</div>
    <svg class="wk" width="${ax ? 330 : 332}" height="${(c.v.includes(',') ? 142 : 96) + (ax ? 14 : 0)}" data-v="${c.v}"${ax ? ' data-fs="24"' : ''} data-l0="${c.l0}" data-l1="${c.l1}"></svg>
    <div class="kv">${kv.map(kvCell).join('')}</div>${tail}</div>`;
}
const emptyCurves = `<div class="card cv"><div class="lab">Weight and waist</div><div class="big num none" style="margin-top:6px">—</div><div class="lab" style="margin-top:8px">Not measured yet</div></div>`;
const sigRows = sig => sig.map(x => `<div class="sig">${glyph(x.s)}<div class="grow1"><div class="k">${x.k}</div><div class="n n1">${x.reason}</div>${x.detail ? `<div class="n">${x.detail}</div>` : ''}</div><div class="w" style="color:var(${ST[x.s].c})">${ST[x.s].w}</div></div>`).join('<div class="sep"></div>');
const ruleRows = rules => rules.map(x => `<div class="rrow">${ruleDot(x.state)}<div class="grow1"><div class="rk">${x.name}</div>${x.sub ? `<div class="rs">${x.sub}</div>` : ''}</div><div class="rw ${x.state}">${x.word}</div></div>`).join('');
const navbar = (title, right = 'plus') => `<div class="navbar"><div class="ibtn" data-ic="chev-l" data-s="22"></div><div class="ttl">${title}</div>${right ? `<div class="ibtn" data-ic="${right}" data-s="22"></div>` : '<div style="width:40px"></div>'}</div>`;
const nrow = (t, v, ch = 1) => `<div class="nrow"><div class="t">${t}</div><div class="val">${v}</div>${ch ? '<span class="chev">›</span>' : ''}</div>`;
const grp = rows => `<div class="wrap"><div class="card" style="padding:4px 18px">${rows.join('<div class="sep"></div>')}</div></div>`;
function scorecard(vm, o = {}) {
  const U = vm.U, vd = vm.verdict, met = vm.sig.filter(x => x.s === 'met').length, known = vm.sig.filter(x => x.s !== 'unknown').length, showRules = !!vm.phase && vm.r.started && !o.invalid;
  const top = o.root ? `<div class="sb"></div><div class="hdr"><div><div class="lt">Scorecard</div></div><div class="ibtn" data-ic="plus" data-s="22"></div></div>` : `<div class="sb"></div>${navbar('Scorecard')}`;
  const noPhase = !vm.phase;
  return `${top}
  ${vm.phase ? `<div class="phase motion"><div class="lab">${vm.phase.lab}</div><div class="nm">${vm.phase.nm}</div><div class="meta">${vm.phase.meta}</div></div>` : ''}
  ${vm.due ? `<div class="wrap mt16"><div class="banner motion"><div><div class="bt">Weigh-in due this week</div><div class="bd">The verdict below is from the ${vd.week}.</div></div><span class="cta">Log weigh-in</span></div></div>` : ''}
  ${vm.reached ? `<div class="wrap mt16"><div class="banner motion"><div><div class="bt">${vm.reached.t}</div><div class="bd">${vm.reached.d}</div></div></div></div>` : ''}
  <div class="wrap mt16"><div class="card verdict">
    <div class="row1"><span class="lab">Verdict${vd.week ? ` · ${vd.week}` : ''}</span><span class="lab">${known ? `${met} of 4 signals met` : ''}</span></div>
    <div class="vt${vd.none ? ' none' : ''}${vd.title.length > 22 ? ' long' : ''}">${vd.title}</div>
    ${vd.lines.map(l => `<div class="rt">${l}</div>`).join('')}
    ${vd.uneval.map(l => `<div class="une">${ruleDot('unknown')}<span>${l}</span></div>`).join('')}
    ${vd.advice ? `<div class="rt t2 own">This is your own rule applied to your own numbers. Nothing has been changed.</div>` : ''}
    ${o.invalid ? `<div class="rt t2">A stored rule value is not valid, so no verdict is shown. Your weigh-ins are unaffected.</div><div class="lnk">Open phase and rules<span class="chev">›</span></div>` : ''}
    ${noPhase ? `<div class="rt t2">Verdicts are given during a cut phase. Your weigh-ins and curves are kept either way.</div><div class="btn primary" style="margin-top:14px">Set up phase</div>` : ''}
    ${showRules ? `<div class="sep" style="margin:14px 0 6px"></div><div class="lab" style="margin-bottom:2px">Your three rules, in order</div>${ruleRows(vm.rules)}` : ''}
  </div></div>
  <div class="sec"><h3>Four signals</h3>${vd.week ? `<a>${vd.week}</a>` : ''}</div>
  <div class="wrap"><div class="card" style="padding:14px 18px">${sigRows(vm.sig)}</div></div>
  <div class="foottext" style="padding-top:8px">Compares the heaviest working set of each exercise with the week before.</div>
  <div class="sec"><h3>Weekly curves</h3><a>History<span class="chev">›</span></a></div>
  ${vm.weight ? `<div class="wrap">${curve('Weight', U.w, vm.weight, [[vm.weight.gain ? 'Rate of gain' : 'Rate of loss', vm.weight.rate, `${U.w}/week`], ['Of bodyweight', vm.weight.pct, '%/week']], `<div class="lab" style="margin-top:6px">${vm.weight.note}</div>`, o.ax)}</div>` : `<div class="wrap">${emptyCurves}</div>`}
  ${vm.waist ? `<div class="wrap mt12">${curve('Waist', U.l, vm.waist, [vm.waist.a, vm.waist.b], '', o.ax)}</div>` : ''}
  <div class="wrap mt12"><div class="card proj" style="margin-top:0"><div class="lab">${vm.proj.lab}${vm.proj.est ? '<span class="est">Estimate</span>' : ''}</div><div class="t${vm.proj.est ? '' : ' none'}">${vm.proj.text}</div>${vm.proj.sub ? `<div class="lab" style="margin-top:2px">${vm.proj.sub}</div>` : ''}</div></div>
  <div class="wrap mt16"><div class="btn ${vm.due || !vm.weight || vm.r.verdict.reason === 'weighInOverdue' ? 'primary' : 'secondary'}">Log weigh-in</div></div>
  <div class="wrap mt16"><div class="card" style="padding:4px 18px">${nrow('History', plural(vm.count, 'weigh-in'))}<div class="sep"></div>${nrow('Phase and rules', vm.phase ? vm.phase.nm : 'Not set up')}</div></div>
  ${o.tab != null ? `<div class="tabbar" data-on="${o.tab}"${o.five ? ' data-five="1"' : ''}></div>` : ''}<div class="home"></div>`;
}
const skeleton = `<div class="sb"></div>${navbar('Scorecard')}
  <div class="phase"><div class="skb" style="width:110px;height:13px"></div><div class="skb" style="width:190px;height:30px;margin-top:8px"></div><div class="skb" style="width:280px;height:13px;margin-top:10px"></div></div>
  <div class="wrap mt16"><div class="card"><div class="skb" style="width:150px;height:13px"></div><div class="skb" style="width:210px;height:34px;margin-top:12px"></div><div class="skb" style="width:100%;height:14px;margin-top:18px"></div><div class="skb" style="width:78%;height:14px;margin-top:8px"></div></div></div>
  <div class="sec"><div class="skb" style="width:130px;height:20px"></div></div>
  <div class="wrap"><div class="card" style="padding:14px 18px">${[0, 1, 2, 3].map(i => `<div class="sig" style="align-items:center"><div class="skb" style="width:24px;height:24px;border-radius:50%;flex:none"></div><div class="grow1"><div class="skb" style="width:${[52, 78, 70, 82][i]}%;height:14px"></div><div class="skb" style="width:${[64, 58, 50, 60][i]}%;height:12px;margin-top:8px"></div></div></div>`).join('<div class="sep"></div>')}</div></div>
  <div class="sec"><div class="skb" style="width:150px;height:20px"></div></div>
  <div class="wrap"><div class="card"><div class="skb" style="width:60px;height:13px"></div><div class="skb" style="width:130px;height:40px;margin-top:10px"></div><div class="skb" style="width:100%;height:120px;margin-top:16px;border-radius:14px"></div></div></div>
  <div class="wrap mt12"><div class="card"><div class="skb" style="width:150px;height:13px"></div><div class="skb" style="width:230px;height:18px;margin-top:10px"></div></div></div><div class="home"></div>`;

/* ---------- weigh-in sheet (§10.3). "Today" in these frames is Wed 5 Feb 2031, week 5 of the fixture. ---------- */
const KEYS = sepr => `<div class="keys">${['1', '2', '3', '4', '5', '6', '7', '8', '9', sepr, '0', '⌫'].map(k => `<span${k === sepr || k === '⌫' ? ' class="fn"' : ''}>${k}</span>`).join('')}</div>`;
const backdrop = tall => `<div class="sb"></div><div class="dim">${navbar('Scorecard')}${tall ? '' : `<div class="phase"><div class="lab">Phase · week 5</div><div class="nm">Fixture cut</div></div>`}</div>`;
function calendar() { // January 2031, Monday first; 1 Jan is a Wednesday. Thu 16 Jan is selected; dots mark days that already hold a reading.
  const has = [8, 15, 20, 22, 29], cells = ['30', '31'].map(d => `<span class="o">${d}</span>`);
  for (let d = 1; d <= 31; d++) cells.push(`<span class="${d === 16 ? 'sel' : ''}${has.includes(d) ? ' has' : ''}">${d === 16 ? `<b>${d}</b>` : d}</span>`);
  ['1', '2'].forEach(d => cells.push(`<span class="o">${d}</span>`));
  return `<div class="cal"><div class="mh">January 2031<span><span>‹</span><span>›</span></span></div><div class="g">${['M', 'T', 'W', 'T', 'F', 'S', 'S'].map(x => `<i>${x}</i>`).join('')}${cells.join('')}</div></div>`;
}
function sheet(o) {
  const field = o.val === '' ? '<i class="caret"></i>' : o.sel ? `<span class="selv">${o.val}</span>` : `${o.val}<i class="caret"></i>`;
  return `${backdrop(o.cal || o.full || o.tall || o.step === 2)}<div class="sheet wsheet"${o.full ? ' style="top:64px"' : ''}><div class="grabber"></div>
    <div class="sbar"><span${o.busy ? ' class="t3"' : ''}>Cancel</span><span class="t">${o.title || 'Weigh-in'}</span><span class="stp">Step ${o.step} of 2</span></div>
    <div class="datechip${o.cal ? ' on' : ''}"><span data-ic="cal" data-s="16"></span>${o.date}<span class="chev" style="margin-left:0">›</span></div>
    ${o.cal ? calendar() : ''}${o.dateNote ? `<div class="datenote">${o.dateNote}</div>` : ''}
    ${o.done ? `<div class="donerow">${glyph('met', 18)}<span>Weight <b class="num">${o.done}</b></span><span class="ed">Edit</span></div>` : ''}
    <div class="entry"><div class="lab">${o.label}</div><div class="bigin num${o.bad ? ' bad' : ''}">${field}<small>${o.unit}</small></div><div class="hint${o.bad ? ' bad' : ''}">${o.hint}</div></div>
    ${o.fail ? `<div class="fail"><b>Could not save.</b> Your entries are still here.</div>` : ''}
    <div class="btn primary${o.off || o.busy ? ' off' : ''}">${o.primary}</div>
    ${o.skip ? `<div class="skip${o.busy ? ' t3' : ''}">Skip</div>` : ''}${o.skip && !o.fail ? `<div class="skipnote">Saves the weight only. Waist for this week will read "Not measured this week".</div>` : ''}
    ${o.cal ? '' : KEYS(o.sepr || '.')}</div>`;
}

/* ---------- history (§10.4), as it stands after the week 5 weigh-in ---------- */
const HIST = [
  ['Wed 5 Feb', 'Lab Book', '97.5', '98.0', 1], ['Wed 29 Jan', 'Lab Book', '97.6', '98.5', 1], ['Wed 22 Jan', 'Lab Book', '98.4', '99.0', 1], ['Mon 20 Jan', 'Lab Book', '98.9', null, 0],
  ['Wed 15 Jan', 'Lab Book', '99.2', '99.5', 1], ['Wed 8 Jan', 'Lab Book', '100.0', '100.0', 1], ['Sat 4 Jan', 'Apple Health · read-only', '100.6', null, 1], ['Wed 1 Jan', 'Lab Book · CSV import', '101.0', '100.5', 0],
];
const REP = `<svg width="8" height="8" viewBox="0 0 8 8" style="margin-right:6px"><circle cx="4" cy="4" r="3.5" fill="#F5F5F7"/></svg>`;
const hrow = ([d, src, w, wa, rep]) => `<div class="hrow${rep ? '' : ' off'}"><div><div class="d">${rep ? REP : ''}${d}</div><div class="m">${rep ? 'Represents its week' : 'Not the weekly point'} · ${src}</div></div><div class="x num">${w}<small>kg</small></div>${wa ? `<div class="x num">${wa}<small>cm</small></div>` : '<div class="x none">not measured</div>'}</div>`;
const swiped = ([d, src]) => `<div class="swipe"><div class="hrow"><div><div class="d">${d}</div><div class="m">Not the weekly point · ${src}</div></div></div><div class="act e"><span data-ic="pencil" data-s="20"></span>Edit</div><div class="act x"><span data-ic="trash" data-s="20"></span>Delete</div></div>`;
const histTop = `<div class="sb"></div>${navbar('History', 'plus')}`;
const histList = (swipe, n = 99) => `<div class="colh"><span></span><span>Weight</span><span>Waist</span></div>
  <div class="wrap" style="margin-top:8px"><div class="card" style="padding:4px 18px">${HIST.slice(0, n).map((r, i) => swipe && i === 3 ? swiped(r) : hrow(r)).join('<div class="sep"></div>')}</div></div>
  <div class="foottext"${n < 99 ? ' style="display:none"' : ''}>The dot marks the reading that represents its week: the latest one. 1 reading in a unit that is not recognised is not listed. It remains in Lab Book.</div>`;
const history = swipe => `${histTop}${histList(swipe)}<div class="home"></div>`;
const histDelete = `${histTop}<div class="dim">${histList(false, 4)}</div>
  <div class="sheet wsheet"><div class="grabber"></div><div class="at">Delete this weigh-in?</div><div class="ad">Mon 20 Jan · 98.9 kg. The weekly series and the verdict are worked out again without it.</div>
    <div class="btn danger" style="margin-top:18px"><span data-ic="trash" data-s="20"></span>Delete</div><div class="btn secondary" style="margin-top:10px">Cancel</div></div>`;
const histEmpty = `${histTop}<div class="wrap" style="margin-top:28px"><div class="card empty"><div style="color:var(--t2);display:grid;place-items:center" data-ic="scale" data-s="36"></div><div class="et">No weigh-ins yet</div><div class="btn primary" style="margin-top:18px">Log weigh-in</div></div></div><div class="home"></div>`;
const histLoading = `${histTop}<div class="colh"><span></span><span>Weight</span><span>Waist</span></div><div class="wrap" style="margin-top:8px"><div class="card" style="padding:4px 18px">${[0, 1, 2, 3, 4].map(() => `<div class="hrow"><div><div class="skb" style="width:90px;height:14px"></div><div class="skb" style="width:150px;height:11px;margin-top:7px"></div></div><div class="skb" style="height:16px"></div><div class="skb" style="height:16px"></div></div>`).join('<div class="sep"></div>')}</div></div><div class="home"></div>`;

/* ---------- phase and rules sheet (§10.5): every parameter the owner can set ---------- */
const gh = (t, first) => `<div class="gh"${first ? ' style="padding-top:10px"' : ''}>${t}</div>`;
const gf = t => `<div class="gf">${t}</div>`;
const prow = (t, v, bad) => `<div class="nrow${bad ? ' bad' : ''}"><div class="t">${t}</div><div class="val">${v}</div></div>`;
function phaseSheet(o) {
  const P = o.P, ph = o.phase, other = o.kind === 'other', n = v => v == null ? 'Not set' : v;
  const bar = `<div class="sb"></div><div class="navbar"><div class="lnk" style="margin:0;font-weight:500">Cancel</div><div class="ttl">${o.title}</div><div class="lnk" style="margin:0${o.bad ? ';color:var(--t3)' : ''}">Save</div></div>`;
  const phaseGrp = `${gh('Phase', 1)}<div class="wrap"><div class="seg"><span${other ? '' : ' class="on"'}>Cut</span><span${other ? ' class="on"' : ''}>Other</span></div></div>
    <div style="height:10px"></div>${grp([prow('Name', ph.name), prow('Start date', ph.start)].concat(other ? [] : [prow('Target weight', ph.target == null ? 'Not set' : `${ph.target} kg`)]))}`;
  if (other) return `${bar}${phaseGrp}${gf('A phase that is not a cut has no target, no band and no rules. While it is active the scorecard shows "No cut phase is active". Weigh-ins and curves carry on.')}
    ${o.newPhase ? gf('Starting this phase keeps "Fixture cut" in your list of past phases.') : ''}<div class="home"></div>`;
  return `${bar}${phaseGrp}${gf('The target is optional. With no target there is no projection.')}
    ${gh('Expected rate of loss')}${grp([prow('At least', `${ph.low}% of bodyweight per week`, o.bad), prow('At most', `${ph.high}% of bodyweight per week`, o.bad)])}
    ${o.bad ? `<div class="gf bad">"At least" is above "At most". Fix one of them to save.</div>` : gf('The rate signal is met inside this band. The band never changes the verdict.')}
    ${gh('Rule 1 · change nothing')}${grp([prow('Waist compared over', plural(P.waistWindowWeeks, 'week')), prow('Waist must be down at least', `${P.waistMinDecreaseCm} cm`)])}
    ${gf('Fires when lifts are holding and the waist is shrinking. It comes first.')}
    ${gh('Rule 2 · lifts dropping')}${grp([prow('A lift has dropped below', `${P.liftDropTolerancePercent}% under last week`), prow('Share of lifts that dropped', `${Math.round(P.liftDropShare * 100)}% or more`), prow('For', `${P.liftDropConsecutiveWeeks} weeks running`), prow('Then add', `${P.addCaloriesKcal} kcal`)])}
    ${gh('Rule 3 · slow loss')}${grp([prow('Loss under', `${P.slowLossThresholdKgPerWeek} kg per week`), prow('For', `${P.slowLossConsecutiveWeeks} weeks running`), prow('Then take from carbohydrate', `${P.reduceCarbsKcal} kcal`)])}
    ${gh('Rate and projection')}${grp([prow('Rate fitted over', plural(P.rateWindowWeeks, 'week')), prow('Projection stops at', plural(P.maxProjectionWeeks, 'week')), prow('Target counts as reached within', `${P.targetToleranceKg} kg`)])}
    ${gh('Protein')}${grp([prow('Daily floor', P.proteinFloorGrams == null ? 'Not set' : `${P.proteinFloorGrams} g`), prow('Days a week at or above it', `${P.proteinMinDaysPerWeek} of 7`)])}
    ${gf(P.proteinFloorGrams == null ? 'With no floor the protein signal reads "No floor set". Protein never changes the verdict.' : 'Protein is shown as a signal and never changes the verdict.')}
    ${gh('Weigh-ins')}${grp([prow('A verdict lapses after', `${plural(P.maxWeighInAgeWeeks, 'week')} without a weigh-in`)])}
    ${o.newPhase !== undefined ? `<div class="wrap mt24"><div class="btn secondary">Start a new phase</div></div>${gf('The current phase stays in your list of past phases.')}` : ''}<div class="home"></div>`;
}

/* ---------- settings (§10.6, §10.7) ---------- */
const NOTIF = `<div class="notif"><div class="ai" data-ic="today" data-s="22"></div><div class="grow1"><div class="row gap8"><div class="nt">Weekly weigh-in</div><div class="nw">08:00</div></div><div class="nb">Weight, then waist. It takes under a minute.</div></div></div>`;
const tog = (t, on) => `<div class="nrow"><div class="t">${t}</div><div class="toggle${on ? ' on' : ''}"></div></div>`;
const settings = mode => `<div class="sb"></div>${navbar('Settings', null)}
  ${gh('Scorecard', 1)}${grp([tog('Weekly weigh-in and scorecard', 1), tog('Weekly reminder', mode !== 'off')].concat(mode === 'on' ? [nrow('Day', 'Saturday'), nrow('Time', '08:00')] : []))}
  ${mode === 'off' ? gf('The reminder is off unless you turn it on. One notification a week, on the day and at the time you choose.') : ''}
  ${mode === 'on' ? `${gf('One notification a week. It never contains a measurement, a verdict or the phase name.')}${gh('What it looks like')}<div class="wrap">${NOTIF}</div>` : ''}
  ${mode === 'denied' ? `<div class="wrap mt12"><div class="banner"><div><div class="bt">Notifications are off for NOOP</div><div class="bd">The reminder cannot be delivered until they are allowed.</div></div><span class="cta">Open Settings</span></div></div>` : ''}
  <div class="home"></div>`;
const bodyRows = `<div class="sb"></div>${navbar('Settings', null)}
  ${gh('Body metrics · a dated reading exists', 1)}${grp([`<div class="nrow"><div class="grow1"><div class="t">Weight</div><div class="rs">Lab Book · Wed 5 Feb</div></div><div class="val num" style="color:var(--t1)">97.5 kg</div></div>`,
    `<div class="nrow"><div class="grow1"><div class="t">Waist</div><div class="rs">Lab Book · Wed 5 Feb</div></div><div class="val num" style="color:var(--t1)">98.0 cm</div></div>`, `<div class="nrow"><div class="t" style="font-weight:600">Log weigh-in</div><span class="chev">›</span></div>`])}
  ${gf('With the scorecard on, weight and waist come from the latest dated reading, so Settings and the scorecard cannot disagree.')}
  ${gh('Body metrics · no dated reading yet')}${grp([`<div class="nrow"><div class="t">Weight</div><div class="val num">100.0 kg</div><div class="stepper"><span>−</span><span>+</span></div></div>`, `<div class="nrow"><div class="t">Waist</div><div class="val num">100.0 cm</div><div class="stepper"><span>−</span><span>+</span></div></div>`])}
  ${gf('Until a weigh-in exists, the profile value and its stepper stay as they are today.')}<div class="home"></div>`;

/* ---------- placement ---------- */
const healthTab = body => `<div class="sb"></div><div class="hdr"><div><div class="lt">Health</div><div class="sub">Wed, 29 Jan</div></div><div class="ibtn" data-ic="person" data-s="22"></div></div>
  <div class="sec"><h3>Vitals</h3><a>All<span class="chev">›</span></a></div>
  <div class="wrap"><div class="ycgrid">${tile('trend', '--hrv', 'HRV', '62', 'ms', 'Last night')}${tile('heart', '--heart', 'Resting heart rate', '52', 'bpm', 'Last night')}</div></div>
  ${body ? `<div class="sec"><h3>Body</h3><a>History<span class="chev">›</span></a></div><div class="wrap"><div class="ycgrid">${wideCard(wk(4))}</div></div>` : ''}
  <div class="sec"><h3>More</h3></div>
  ${grp((body ? [] : [nrow('Scorecard', 'Change nothing · 97.6 kg')]).concat([nrow('Lab Book', '14 markers'), nrow('Fitness age', '≤ 34 yrs'), nrow('Steps', 'Apple Health')]))}
  <div class="tabbar" data-on="3"></div><div class="home"></div>`;
const er = (sign, title, sub) => `<div class="nrow"><span class="pm ${sign}">${sign === 'add' ? '+' : '−'}</span><div class="grow1"><div class="t">${title}</div>${sub ? `<div class="rs">${sub}</div>` : ''}</div></div>`;
const customize = `<div class="sb"></div><div class="navbar"><div class="lnk" style="margin:0;font-weight:500">Cancel</div><div class="ttl">Your cards</div><div class="lnk" style="margin:0">Save</div></div>
  ${gh('Shown', 1)}${grp([er('rem', 'Stress'), er('rem', 'Fitness age'), er('rem', 'Vitality'), er('rem', 'VO₂ max')])}
  ${gh('More cards')}${grp([er('add', 'Scorecard', 'Weight and this week\'s verdict'), er('add', 'Coupled view'), er('add', 'Coach'), er('add', 'Hydration')])}
  ${gf('Scorecard is not in the default selection. It appears on Today only after you add it here, and only while "Weekly weigh-in and scorecard" is on in Settings.')}<div class="home"></div>`;

/* ---------- frames ---------- */
const G = []; let cur;
const group = (title, note) => { cur = { title, note, frames: [] }; G.push(cur); };
const frame = (name, html, o = {}) => cur.frames.push({ name, html, ...o });
const TODAY_AMB = 'data-ambient="today:86,68,11.4"', STILL = { attrs: 'data-nomotion' };
const sc = (name, vm, o = {}, note) => frame(name, scorecard(vm, o), { attrs: AMB(vm), cls: o.ax ? 'ax' : '', note });
const lab = (l, t) => `<div><div class="lab" style="padding:0 2px 6px;min-height:42px;display:flex;align-items:flex-end">${l}</div>${t}</div>`;
const noLiftsLate = { today: '2031-02-19', noLifts: true, phase: { ...FIXTURE_PHASE, startDay: '2031-02-03' } };

group('A · Entry card in Your cards (§10.1)', 'A value card like the other tiles: the current weight and one caption. It is <b>not in the default selection</b>; the owner adds it. Every caption is the §10.1 text. Weight is drawn in the primary text colour: the palette has no colour for body composition and none is invented.');
frame('A1 Today card · verdict available', todayFrame('Wed, 29 Jan', scTile(wk(4).card) + STRESS + tile('scale', '--t1', 'Weight', '97.6', 'kg', 'Lab Book') + FIT), { attrs: TODAY_AMB, note: 'Fixture week 4. The existing Weight tile (§10.8) shows the same resolved value and names its source.' });
frame('A2 Today card · every state', `<div class="sb"></div><div class="navbar"><div style="width:40px"></div><div class="ttl">Card states</div><div style="width:40px"></div></div>
  <div class="wrap"><div class="ycgrid" style="row-gap:6px">${[['Loading', skTile], ['No cut phase', scTile(FX({ today: '2031-01-29', phase: null }).card)], ['No readings', scTile(FX({ today: '2031-01-08', without: Array.from({ length: 22 }, (_, i) => i + 1) }).card)],
    ['One reading', scTile(wk(1).card)], ['Fewer readings than the rules need', scTile(FX(noLiftsLate).card)], ['Weigh-in due this week', scTile(FX({ today: '2031-03-12' }).card)],
    ['Overdue', scTile(FX({ today: '2031-03-19', without: [11] }).card)], ['Lifts unknown, verdict withheld', scTile(wk(15).card)], ['Target reached', scTile(wk(21).card)], ['Weight rising', scTile(wk(20).card)],
    ['Your rule: add', scTile(wk(19).card)], ['A past day selected', tile('scale', '--t1', 'Scorecard', null, '', 'Shown for today only', { nolink: 1 })]].map(([l, t]) => lab(l, t)).join('')}</div></div><div class="home"></div>`, STILL);
frame('A3 Today card · AX5', `<div class="sb"></div><div class="navbar"><div style="width:40px"></div><div class="ttl">Today</div><div style="width:40px"></div></div>
  <div class="sec" style="padding-top:12px"><h3>Your cards</h3><a>Edit<span class="chev">›</span></a></div>
  <div class="wrap"><div class="ycgrid">${scTile(wk(4).card)}${scTile(wk(9).card)}${scTile(FX({ today: '2031-03-19', without: [11] }).card)}</div></div><div class="home"></div>`, { cls: 'ax' });
frame('A4 Today card · wider card with the four signals (proposal, not in the specification)', todayFrame('Wed, 29 Jan', wideCard(wk(4)) + STRESS + FIT), { attrs: TODAY_AMB, note: 'A question for the owner: the specification asks for a plain value card (A1). This full-width version also names the four signals.' });

group('B · Scorecard screen (§10.2)', 'Top to bottom: phase, verdict with the three rules, four signals, weight curve, waist curve, projection, Log weigh-in, links. Each frame is the fixture on the stated day, run through the design model of §7; strings are §11. Curves are a line with a gradient fill and one point per weekly reading. No band, rule or target line: the target is a number in the projection row.');
sc('B1 Scorecard · steady loss in the band', wk(4), {}, 'Fixture week 4, Wed 29 Jan 2031.');
sc('B2 Scorecard · no readings', FX({ today: '2031-01-08', without: Array.from({ length: 22 }, (_, i) => i + 1) }));
sc('B3 Scorecard · no cut phase', FX({ today: '2031-01-29', phase: null }), {}, 'Variant V4. Curves and the fitted rate still show; there is no verdict and no band.');
sc('B4 Scorecard · phase not started', FX({ today: '2031-01-29', phase: { ...FIXTURE_PHASE, startDay: '2031-02-03' } }));
sc('B5 Scorecard · one reading', wk(1), {}, 'Fixture week 1. With lift sessions on record rule 2 is settled, so §7.7 line 4b applies and two rules are named as not checked.');
sc('B6 Scorecard · one reading, no lift sessions', FX({ today: '2031-01-08', noLifts: true }), {}, 'Variant V2: no rule can be evaluated.');
sc('B7 Scorecard · fewer readings than a rule needs', FX(noLiftsLate), {}, 'Variant V5 without lift sessions, Wed 19 Feb: the phase is three weeks old.');
sc('B8 Scorecard · protein below the floor', wk(5), {}, 'Fixture week 5.');
sc('B9 Scorecard · protein logging incomplete', wk(6), {}, 'Fixture week 6: 3 of 7 days logged. Slow loss stands at 2 of 3 weeks.');
sc('B10 Scorecard · recomposition week', wk(7), {}, 'Fixture week 7: rule 3 fired and rule 1 overrides it.');
sc('B11 Scorecard · reduce carbohydrate', wk(9), {}, 'Fixture week 9.');
sc('B12 Scorecard · weigh-in due, last verdict stands', FX({ today: '2031-03-12' }), {}, 'Fixture week 10: no reading yet this week. The verdict from week 9 stays for one week.');
sc('B13 Scorecard · after a missed week', wk(11), {}, 'Fixture week 11. The curves break at the missed week. Rule 3 restarts.');
sc('B14 Scorecard · no rule fired, lifts not known', wk(13), {}, 'Fixture week 13 (§7.7 line 4b). It does not say lifts are holding.');
sc('B15 Scorecard · verdict withheld', wk(15), {}, 'Fixture week 15 (§7.7 line 3a).');
sc('B16 Scorecard · reduce carbohydrate, lifts rule not checked', wk(17), {}, 'Fixture week 17 (§7.7 line 3b).');
sc('B17 Scorecard · add calories, slow loss overridden', wk(19), {}, 'Fixture week 19.');
sc('B18 Scorecard · weight rising', wk(20), {}, 'Fixture week 20.');
sc('B19 Scorecard · target reached', wk(21), {}, 'Fixture week 21.');
sc('B20 Scorecard · weigh-in overdue', FX({ today: '2031-03-19', without: [11] }), {}, 'Variant V3: two weeks with no reading.');
sc('B21 Scorecard · no target set, no protein floor', FX({ today: '2031-01-29', phase: { ...FIXTURE_PHASE, targetWeightKg: null }, params: { ...FIXTURE_PARAMS, proteinFloorGrams: null } }), {}, 'Variant V6, with the protein floor left empty.');
sc('B22 Scorecard · projection beyond the horizon', FX({ today: '2031-02-26', phase: { ...FIXTURE_PHASE, targetWeightKg: 80 } }), {}, 'Variant V12.');
sc('B23 Scorecard · projected day passed', FX({ today: '2031-02-05', without: [5], phase: { ...FIXTURE_PHASE, targetWeightKg: 97 } }), {}, 'Target 97.0 kg, last weigh-in Wed 29 Jan, viewed Wed 5 Feb.');
sc('B24 Scorecard · rules need attention', FX({ today: '2031-01-29' }, METRIC, true), { invalid: 1 });
sc('B25 Scorecard · pounds and inches', FX({ today: '2031-01-29' }, IMPERIAL));
frame('B26 Scorecard · loading skeleton', skeleton, STILL);
sc('B27 Scorecard · AX5', wk(17), { ax: 1 });

group('C · Weigh-in sheet (§10.3)', 'Step 1 weight, step 2 waist, one date for both. In these frames "now" is Wed 5 Feb 2031, 07:02. The keypad is the system decimal pad.');
frame('C1 Weigh-in · step 1, first use', sheet({ step: 1, date: 'Today · Wed 8 Jan · 07:02', label: 'Weight', val: '', unit: 'kg', hint: '30 to 250 kg', primary: 'Next', off: 1 }), STILL);
frame('C2 Weigh-in · step 1, last weight prefilled', sheet({ step: 1, date: 'Today · Wed 5 Feb · 07:02', label: 'Weight', val: '97.6', sel: 1, unit: 'kg', hint: 'Last: 97.6 kg · Wed 29 Jan. Type to replace.', primary: 'Next' }), STILL);
frame('C3 Weigh-in · out of range', sheet({ step: 1, date: 'Today · Wed 5 Feb · 07:02', label: 'Weight', val: '975', unit: 'kg', bad: 1, hint: 'Enter 250 kg or less.', primary: 'Next', off: 1 }), STILL);
frame('C4 Weigh-in · backdating', sheet({ step: 1, date: 'Thu 16 Jan · 07:02', cal: 1, dateNote: 'Falls in the week of 13 Jan. You logged 99.2 kg on Wed 15 Jan. This reading will represent the week.', label: 'Weight', val: '98.0', unit: 'kg', hint: 'Future dates cannot be picked.', primary: 'Next' }), STILL);
frame('C5 Weigh-in · already logged this week', sheet({ step: 1, date: 'Today · Fri 31 Jan · 07:10', dateNote: 'You logged 97.6 kg on Wed 29 Jan. This reading will represent the week.', label: 'Weight', val: '97.6', sel: 1, unit: 'kg', hint: 'Last: 97.6 kg · Wed 29 Jan. Type to replace.', primary: 'Next' }), STILL);
frame('C6 Weigh-in · step 2 waist', sheet({ step: 2, date: 'Today · Wed 5 Feb · 07:02', done: '97.5 kg', label: 'Waist', val: '98.5', sel: 1, unit: 'cm', hint: 'Last: 98.5 cm · Wed 29 Jan. Type to replace. 40 to 200 cm.', primary: 'Save', skip: 1 }), STILL);
frame('C7 Weigh-in · saving', sheet({ step: 2, date: 'Today · Wed 5 Feb · 07:02', done: '97.5 kg', label: 'Waist', val: '98.0', unit: 'cm', hint: 'Last: 98.5 cm · Wed 29 Jan', primary: 'Saving…', busy: 1, skip: 1 }), STILL);
frame('C8 Weigh-in · save failed', sheet({ step: 2, tall: 1, date: 'Today · Wed 5 Feb · 07:02', done: '97.5 kg', label: 'Waist', val: '98.0', unit: 'cm', hint: 'Last: 98.5 cm · Wed 29 Jan', primary: 'Try again', fail: 1, skip: 1 }), STILL);
frame('C9 Weigh-in · pounds, comma decimal separator', sheet({ step: 1, date: 'Today · Wed 5 Feb · 07:02', label: 'Weight', val: '215,0', unit: 'lb', hint: 'Last: 215,2 lb · Wed 29 Jan', primary: 'Next', sepr: ',' }), { attrs: 'data-nomotion', note: 'Stored in kilograms. The separator follows the device locale.' });
frame('C10 Weigh-in · AX5', sheet({ step: 1, full: 1, date: 'Today · Wed 5 Feb · 07:02', label: 'Weight', val: '97.6', sel: 1, unit: 'kg', hint: 'Last: 97.6 kg · Wed 29 Jan. Type to replace.', primary: 'Next' }), { cls: 'ax', attrs: 'data-nomotion', style: 'min-height:1180px' });

group('D · History (§10.4)', 'Newest first; weight and waist of one weigh-in on one row; a dot on the reading that represents its week. Edit opens the weigh-in sheet (C) with that reading\'s values.');
frame('D1 History · list, with other sources', history(false));
frame('D2 History · swipe to edit or delete', history(true), STILL);
frame('D3 History · delete asks once', histDelete, STILL);
frame('D4 History · empty', histEmpty);
frame('D5 History · loading', histLoading, STILL);

group('E · Phase and rules sheet (§10.5)', 'Every value the rules use, grouped by rule. First use is prefilled with the generic defaults; nothing here is the owner\'s.');
frame('E1 Phase and rules · first use, generic defaults', phaseSheet({ title: 'New phase', P: GENERIC, phase: { name: 'Cut', start: 'Today · Mon 6 Jan 2031', target: null, low: GENERIC_BAND[0], high: GENERIC_BAND[1] } }), STILL);
frame('E2 Phase and rules · editing', phaseSheet({ title: 'Phase and rules', P: FIXTURE_PARAMS, newPhase: 0, phase: { name: 'Fixture cut', start: 'Mon 6 Jan 2031', target: '94.0', low: '0.40', high: '1.20' } }), STILL);
frame('E3 Phase and rules · a value that cannot be saved', phaseSheet({ title: 'Phase and rules', P: FIXTURE_PARAMS, bad: 1, phase: { name: 'Fixture cut', start: 'Mon 6 Jan 2031', target: '94.0', low: '1.40', high: '1.20' } }), STILL);
frame('E4 Phase and rules · new phase of kind Other', phaseSheet({ title: 'New phase', kind: 'other', newPhase: 1, P: FIXTURE_PARAMS, phase: { name: 'Maintenance', start: 'Today · Thu 5 Jun 2031' } }), STILL);

group('F · Settings (§10.6, §10.7) and the notification', 'The feature switch, the reminder beneath it, and what the weight and waist rows in Settings become once a dated reading exists.');
frame('F1 Settings · scorecard on, reminder off', settings('off'));
frame('F2 Settings · reminder on, with the notification', settings('on'));
frame('F3 Settings · notifications denied', settings('denied'));
frame('F4 Settings · body metrics rows', bodyRows);

group('P1 · Placement: a Today card and a Health row (the specification\'s recommendation)', 'The card is not in the default selection: the owner adds it under Your cards. A row in the Health tab is the permanent way in. Both push the same screen.');
frame('P1.1 Placement P1 · Today card, once added', todayFrame('Wed, 29 Jan', scTile(wk(4).card) + STRESS), { attrs: TODAY_AMB });
frame('P1.2 Placement P1 · adding the card', customize, STILL);
frame('P1.3 Placement P1 · row in the Health tab', healthTab(false), { attrs: `data-ambient='[["--heart",350,20,190,0.2],["--hrv",50,0,200,0.2]]'` });
sc('P1.4 Placement P1 · scorecard pushed', wk(4), { tab: 0 });
group('P2 · Placement: a Body section under Health', 'The scorecard is a destination in the Health tab, summarised by a full-width card there. No Today card.');
frame('P2.1 Placement P2 · Health tab, Body section', healthTab(true), { attrs: `data-ambient='[["--heart",350,20,190,0.2],["--hrv",50,0,200,0.2]]'` });
sc('P2.2 Placement P2 · scorecard under Health', wk(4), { tab: 3 });
group('P3 · Placement: its own tab (not recommended)', 'The bar already holds four tabs plus Coach. With Coach on, a Scorecard tab is the sixth destination, so iOS moves one into a "More" overflow, or it has to replace an existing tab. Drawn here with Coach as the round button, which is the kindest case.');
sc('P3.1 Placement P3 · Scorecard tab', wk(4), { tab: 4, five: 1, root: 1 });

// ?only=B (or ?only=B1) shows just the frames whose id starts with that text. Handy for review; not used for export.
const ONLY = new URLSearchParams(location.search).get('only');
if (ONLY) { G.forEach(g => g.frames = g.frames.filter(f => f.name.startsWith(ONLY))); for (let i = G.length - 1; i >= 0; i--) if (!G[i].frames.length) G.splice(i, 1); }
document.getElementById('boards').innerHTML = G.map(g => `<h2 class="grp-title">${g.title}</h2><p class="grp-note">${g.note}</p><div class="board">${g.frames.map(f =>
  `<section><div class="board-title">R6 / ${f.name}</div><div class="screen${f.cls ? ' ' + f.cls : ''}" ${f.attrs || ''} style="${f.style || ''}">${f.html}</div>${f.note ? `<p class="fnote">${f.note}</p>` : ''}</section>`).join('')}</div>`).join('');

boot(() => {
  document.querySelectorAll('svg.wk').forEach(weekChart);
  // Placement P3 only: a five-item bar. noop.js tabbar() draws the shipped four.
  document.querySelectorAll('.tabbar[data-five]').forEach(t => {
    const items = [['today', 'Today'], ['moon', 'Sleep'], ['dumbbell', 'Training'], ['heart', 'Health'], ['scale', 'Scorecard']];
    t.innerHTML = `<div class="tabs tabs5">${items.map(([i, l], k) => `<div class="tab${k === +t.dataset.on ? ' on' : ''}">${ic(i, 24)}${l}</div>`).join('')}</div><div class="coachbtn">${ic('spark', 26)}</div>`;
  });
});
if (!STATIC) {
  const draw = () => setTimeout(() => document.querySelectorAll('.screen:not([data-nomotion]) svg.wk').forEach(drawLine), 1150);
  draw(); document.getElementById('replay').addEventListener('click', draw);
}
// ?static=1&export=r6-frames.json: write the frames file for the Figma plugin (design/tools/serve.py --export).
const EXPORT_NAME = new URLSearchParams(location.search).get('export');
if (EXPORT_NAME) window.addEventListener('load', () => setTimeout(() => exportSvgFrames(EXPORT_NAME).then(r => { document.title = `exported ${r.frames.length} frames`; }), 400));
