/* Round S5 · Events layer (Stage 5). Every frame is drawn from model.js: the §13 fixture is run through a design
   model of §7 and §10, and the result is worded with the §11 strings held in model.js (STR). Nothing below types a
   date, a count, a value or an event line by hand. Charts are built as strings, so this file also runs under node
   (see check.js). The scorecard screen is a copy of round 6's presenter and layout (design/round6-scorecard/
   scorecard.js), with two additions: the event note under the verdict and the mark row under each curve.
   EVERY VALUE IS SYNTHETIC ("Fixture Person", stage 1 §13). */
(function () {
  const NODE = typeof document === 'undefined';
  const M = NODE ? require('./model.js') : S5M;
  const { S1, STR, PROPOSED, EVENTS, VARIANTS, E, sd, fd, fill } = M;
  const tok = v => NODE ? v : C(v);                                  // noop.js C(): a CSS token to its value
  const bandTok = r => r >= 67 ? '--recovery' : r >= 34 ? '--rec-mid' : '--rec-low';
  const fdy = d => `${fd(d)} ${d.slice(0, 4)}`;
  const plural = (n, w) => `${n} ${w}${n === 1 ? '' : 's'}`;
  const minus = s => String(s).replace(/^-/, '−');
  const U = { w: 'kg', l: 'cm', wf: v => v.toFixed(1), lf: v => v.toFixed(1), rf: v => v.toFixed(2), tf: v => String(+v.toFixed(2)) };

  /* ---------- local icons (noop.js ICONS is not edited), as in round 6 ---------- */
  if (!NODE) document.body.insertAdjacentHTML('afterbegin', `<svg width="0" height="0" style="position:absolute"><defs>
<symbol id="i-cal" viewBox="0 0 24 24"><rect x="4" y="5.5" width="16" height="15" rx="3.5" fill="none" stroke="currentColor" stroke-width="1.9"/><path d="M4 10.5h16M8.5 3.5v4M15.5 3.5v4" fill="none" stroke="currentColor" stroke-width="1.9" stroke-linecap="round"/></symbol>
<symbol id="i-trash" viewBox="0 0 24 24"><path d="M5 7h14M10 4h4M7 7l1 12.5h8L17 7M10.5 11v5M13.5 11v5" fill="none" stroke="currentColor" stroke-width="1.9" stroke-linecap="round" stroke-linejoin="round"/></symbol>
<symbol id="i-pencil" viewBox="0 0 24 24"><path d="M5 19l1-4L16.5 4.5l3 3L9 18zM14.5 6.5l3 3" fill="none" stroke="currentColor" stroke-width="1.9" stroke-linecap="round" stroke-linejoin="round"/></symbol>
</defs></svg>`);

  /* ---------- shared pieces (round 6) ---------- */
  const ST = { met: { c: '--sig-met', w: 'Met' }, notMet: { c: '--sig-not', w: 'Not met' }, unknown: { c: '--sig-unk', w: 'Unknown' } };
  function glyph(s, z = 24) {
    const c = tok(ST[s].c);
    if (s === 'unknown') return `<svg width="${z}" height="${z}" viewBox="0 0 24 24"><circle cx="12" cy="12" r="9.6" fill="none" stroke="#FFFFFF" stroke-opacity=".34" stroke-width="1.7" stroke-dasharray="3 3.3"/></svg>`;
    const mark = s === 'met' ? '<polyline points="7.4,12.4 10.6,15.6 16.8,8.9"' : '<path d="M8.2 8.2l7.6 7.6M15.8 8.2l-7.6 7.6"';
    return `<svg width="${z}" height="${z}" viewBox="0 0 24 24"><circle cx="12" cy="12" r="11" fill="${c}" fill-opacity=".18"/>${mark} fill="none" stroke="${c}" stroke-width="2.2" stroke-linecap="round" stroke-linejoin="round"/></svg>`;
  }
  const ruleDot = s => s === 'fired' ? '<svg width="18" height="18" viewBox="0 0 18 18"><circle cx="9" cy="9" r="5" fill="#F5F5F7"/></svg>'
    : s === 'notFired' ? '<svg width="18" height="18" viewBox="0 0 18 18"><circle cx="9" cy="9" r="5" fill="none" stroke="#9B9BA3" stroke-width="1.6"/></svg>'
    : '<svg width="18" height="18" viewBox="0 0 18 18"><circle cx="9" cy="9" r="5.6" fill="none" stroke="#FFFFFF" stroke-opacity=".34" stroke-width="1.5" stroke-dasharray="2.4 2.6"/></svg>';
  const navbar = (title, right = 'plus') => `<div class="navbar"><div class="ibtn" data-ic="chev-l" data-s="22"></div><div class="ttl">${title}</div>${right ? `<div class="ibtn" data-ic="${right}" data-s="22"></div>` : '<div style="width:40px"></div>'}</div>`;
  const nrow = (t, v, ch = 1) => `<div class="nrow"><div class="t">${t}</div><div class="val">${v}</div>${ch ? '<span class="chev">›</span>' : ''}</div>`;
  const grp = rows => `<div class="wrap"><div class="card" style="padding:4px 18px">${rows.join('<div class="sep"></div>')}</div></div>`;
  const gh = (t, first) => `<div class="gh"${first ? ' style="padding-top:10px"' : ''}>${t}</div>`;
  const gf = t => `<div class="gf">${t}</div>`;
  const tog = (t, on) => `<div class="nrow"><div class="t">${t}</div><div class="toggle${on ? ' on' : ''}"></div></div>`;
  const tile = (icon, tint, title, val, unit, cap) => `<div class="yc motion"><div class="hd" style="color:var(${tint})"><span data-ic="${icon}" data-s="16"></span><b>${title}</b><span class="chev">›</span></div><div class="v num${val == null ? ' none' : ''}">${val == null ? '—' : val}${val != null && unit ? `<small>${unit}</small>` : ''}</div><div class="c">${cap}</div></div>`;
  const smoothPath = pts => { let d = `M${pts[0][0]},${pts[0][1]}`; for (let i = 0; i < pts.length - 1; i++) { const p0 = pts[i - 1] || pts[i], p1 = pts[i], p2 = pts[i + 1], p3 = pts[i + 2] || p2;
    d += ` C${(p1[0] + (p2[0] - p0[0]) / 6).toFixed(2)},${(p1[1] + (p2[1] - p0[1]) / 6).toFixed(2)} ${(p2[0] - (p3[0] - p1[0]) / 6).toFixed(2)},${(p2[1] - (p3[1] - p1[1]) / 6).toFixed(2)} ${p2[0]},${p2[1]}`; } return d; };

  /* ---------- the chart: line or bars, gradient area, and the mark row.
     No rules, bands or target lines. A value that is null is "not measured": the line breaks or the bar is absent,
     and an open ring sits on the axis. An event is a 4pt dot in the 8pt row under the plot, above the date labels.
     With no marks the row takes no height, so the chart is the chart of today. ---------- */
  let uid = 0;
  const MARK = () => tok('--t3a');
  function plot(o) {
    const fs = o.fs || 11, w = o.w, h = o.ph, v = o.v, n = v.length, id = 'ev' + (uid++), real = v.filter(x => x != null), marks = o.marks || [];
    const rowH = marks.length ? M.TOKENS.chartAxisMarkRow : 0, H = h + rowH + fs + 11, out = [];
    if (o.type === 'bars') {
      const slot = w / n, bw = o.bw || Math.min(8, slot - 3), mx = o.max || Math.max(...real);
      v.forEach((x, i) => { const cx = +((i + 0.5) * slot).toFixed(2);
        if (x == null) { out.push(`<circle cx="${cx}" cy="${h - 3.4}" r="2.6" fill="none" stroke="#FFFFFF" stroke-opacity=".4" stroke-width="1.2"/>`); return; }
        const bh = +Math.max(3, x / mx * (h - 6)).toFixed(2);
        out.push(`<rect class="rb" x="${+(cx - bw / 2).toFixed(2)}" y="${+(h - bh).toFixed(2)}" width="${bw}" height="${bh}" rx="${bw / 2}" fill="${tok(o.c === 'band' ? bandTok(x) : o.c)}" opacity="${i === n - 1 ? 1 : .75}"/>`); });
    } else {
      const c = tok(o.c || '--t1'); let mn = Math.min(...real), mx = Math.max(...real); const sp = (mx - mn) || 1; mn -= sp * .14; mx += sp * .14;
      const X = i => +(8 + i * (w - 16) / Math.max(1, n - 1)).toFixed(2), Y = x => +(12 + (1 - (x - mn) / (mx - mn)) * (h - 20)).toFixed(2);
      out.push(`<defs><linearGradient id="a${id}" x1="0" y1="12" x2="0" y2="${h}" gradientUnits="userSpaceOnUse"><stop offset="0" stop-color="${c}" stop-opacity=".28"/><stop offset="1" stop-color="${c}" stop-opacity="0"/></linearGradient>` +
        `<linearGradient id="s${id}" x1="0" y1="0" x2="${w}" y2="0" gradientUnits="userSpaceOnUse"><stop offset="0" stop-color="${c}" stop-opacity=".35"/><stop offset="1" stop-color="${c}" stop-opacity="1"/></linearGradient></defs>`);
      const runs = []; let cur = null; v.forEach((x, i) => { if (x == null) { cur = null; return; } if (!cur) runs.push(cur = []); cur.push([X(i), Y(x)]); });
      runs.forEach(pts => { if (pts.length < 2) return; const line = smoothPath(pts), a = pts[0], b = pts[pts.length - 1];
        out.push(`<path class="area" d="${line} L${b[0]},${h} L${a[0]},${h} Z" fill="url(#a${id})"/><path class="stroke" d="${line}" fill="none" stroke="url(#s${id})" stroke-width="2.5" stroke-linecap="round" stroke-linejoin="round"/>`); });
      const all = runs.flat();
      all.forEach((p, i) => { const last = i === all.length - 1, lone = runs.some(r => r.length === 1 && r[0] === p);
        if (last) out.push(`<circle class="halo" cx="${p[0]}" cy="${p[1]}" r="8" fill="${c}" opacity=".22"/>`);
        if (last || o.type === 'points' || lone) out.push(`<circle class="pt" cx="${p[0]}" cy="${p[1]}" r="${last ? 4 : 2.6}" fill="${c}" stroke="#0B0B0D" stroke-width="${last ? 1.5 : 1.2}"/>`); });
      v.forEach((x, i) => { if (x == null) out.push(`<circle cx="${X(i)}" cy="${h + 3}" r="2.6" fill="none" stroke="#FFFFFF" stroke-opacity=".4" stroke-width="1.2"/>`); });
    }
    const cy = h + (o.type === 'bars' ? 2 : 7) + rowH / 2;
    marks.forEach(m => out.push(m.open ? `<circle class="evmark open" cx="${m.x}" cy="${cy}" r="1.5" fill="none" stroke="${MARK()}" stroke-width="1"/>` : `<circle class="evmark" cx="${m.x}" cy="${cy}" r="${M.TOKENS.chartAxisMark / 2}" fill="${MARK()}"/>`));
    const text = (x, s, anchor) => `<text x="${x}" y="${H - 3}" text-anchor="${anchor}" fill="#9B9BA3" font-size="${fs}" font-weight="500" font-family="-apple-system,system-ui">${s}</text>`;
    if (o.l0) out.push(text(o.type === 'bars' ? 0 : 4, o.l0, 'start'));
    if (o.l1 && n > 1) out.push(text(o.type === 'bars' ? w : w - 4, o.l1, 'end'));
    return `<svg class="evplot" width="${w}" height="${H}" viewBox="0 0 ${w} ${H}" data-marks="${marks.length}">${out.join('')}</svg>`;
  }
  const lead = type => type === 'bars' ? 0 : 8;
  const dots = (covered, type, w) => M.markOffsets(covered, type === 'bars' ? 'bars' : 'points', w, lead(type), lead(type));
  const ends = (list, slots, type, w) => M.markEnds(list, slots, type === 'bars' ? 'bars' : 'points', w, lead(type), lead(type));

  /* ---------- the caption (§10.5): what the dots mean ---------- */
  const DOT = () => `<svg class="evd" width="8" height="8" viewBox="0 0 8 8"><circle cx="4" cy="4" r="2" fill="${MARK()}"/></svg>`;
  const evLine = l => `<div class="evl">${DOT()}<span>${l}</span></div>`;
  const captionHtml = cap => !cap ? '' : `<div class="evcap">${cap.lines.map(evLine).join('')}${cap.moreText ? `<div class="evmore">${cap.moreText}</div>` : ''}</div>`;

  /* ---------- day-axis chart cards: sketches of the existing Recovery, Sleep and Steps charts ---------- */
  const DAYCARD = {
    recovery: { title: 'Recovery', type: 'bars', c: 'band', unit: '%', max: 100, fmt: v => String(v), tint: v => `color:var(${bandTok(v)})`, src: 'Strap' },
    sleep: { title: 'Sleep', type: 'line', c: '--sleep', unit: 'h', fmt: v => v.toFixed(1), tint: () => 'color:var(--sleep)', src: 'Strap' },
    steps: { title: 'Steps', type: 'bars', c: '--t1', unit: '', fmt: v => v.toLocaleString('en-GB'), tint: () => '', src: 'Apple Health' },
  };
  function dayCard(metric, today, days, list, o = {}) {
    const win = M.dayWindow(metric, today, days, list), k = DAYCARD[metric], w = o.ax ? 330 : 332, slots = M.daySlots(win.keys);
    const marks = o.ends ? ends(list, slots, k.type, w) : dots(win.covered, k.type, w);
    return `<div class="card cv"><div class="lab">${k.title} · ${days} days</div><div class="big num" style="margin-top:6px;${k.tint(win.latest)}">${k.fmt(win.latest)}${k.unit ? `<small>${k.unit}</small>` : ''}</div>
      <div class="src" style="margin-top:8px"><i></i>${fd(today)} · ${k.src}</div>
      ${plot({ type: k.type, c: k.c, max: k.max, v: win.values, w, ph: o.ax ? 132 : 110, fs: o.ax ? 24 : 11, l0: sd(win.keys[0]), l1: sd(today), marks })}
      ${captionHtml(win.caption)}${o.tail || ''}</div>`;
  }
  const chartFrame = (title, cards) => `<div class="sb"></div>${navbar(title, null)}<div class="wrap mt8">${[].concat(cards).join('<div style="height:12px"></div>')}</div><div class="home"></div>`;

  /* ---------- stage 1 presenter: result -> stage 1 §11 strings. Copied from round 6 (metric units only). ---------- */
  const RULE_NAME = { liftsHoldingWaistShrinking: 'Lifts holding and waist shrinking', liftsDropping: 'Lifts dropping', slowLoss: 'Slow loss' };
  const COULD_NOT = { liftsHoldingWaistShrinking: 'Could not check: lifts holding and waist shrinking', liftsDropping: 'Could not check: lifts dropping', slowLoss: 'Could not check: slow loss' };
  const RULE_WHY = { liftSignalUnknown: 'lifts not known', waistSignalUnknown: 'waist not known', fewerWeeksThanWindow: 'the phase is younger than this rule needs', missedWeighIn: 'a week has no weigh-in',
    noActivePhase: 'no cut phase is active', weighInOverdue: 'the last weigh-in is too old', noReadings: 'no weigh-ins yet' };
  function present1(r) {
    const inp = r.input, P = inp.parameters, ph = inp.phase, today = inp.today, J = r.judgedWeekStart, rule = k => r.rules.find(x => x.rule === k), wb = S1.weeksBetween;
    const vm = { r, today }, kgw = v => `${U.rf(v)} ${U.w}`;
    vm.phase = !ph ? null : { lab: r.started ? `Phase · week ${wb(ph.startDay, today) + 1}` : 'Phase · not started', nm: ph.name,
      meta: `${ph.targetWeightKg == null ? 'No target set' : `Target ${U.wf(ph.targetWeightKg)} ${U.w}`} · ${r.started ? 'started' : 'starts'} ${fd(ph.startDay)} · band ${ph.rateLowPercentPerWeek.toFixed(2)}–${ph.rateHighPercentPerWeek.toFixed(2)}% per week` };
    const V = r.verdict, vd = { lines: [], uneval: V.unevaluatedRules.map(k => COULD_NOT[k]), none: V.kind === 'insufficientData', advice: false };
    if (V.reason === 'ruleFired' && V.kind === 'holdSteady') { vd.title = 'Change nothing'; vd.lines.push('Lifts are holding and your waist is shrinking.');
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
    vm.rules = r.rules.map(x => ({ name: RULE_NAME[x.rule], state: x.state, word: x.state === 'fired' ? 'Fired' : x.state === 'notFired' ? 'Not fired' : 'Could not check',
      sub: [x.requiredWeeks > 1 ? `${Math.min(x.consecutiveWeeks, x.requiredWeeks)} of ${plural(x.requiredWeeks, 'week')}` : null, x.state === 'unknown' ? RULE_WHY[x.unknownReason] : null].filter(Boolean).join(' · ') }));
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
    const weeks = r.weekKeys.filter(w => w >= (r.started ? r.domainStart : r.weekKeys[0])), series = m => weeks.map(w => m[w] ? m[w].value : null);
    const lastW = [...weeks].reverse().find(w => r.sp[w]), firstW = weeks.find(w => r.sp[w]);
    vm.weeks = weeks;
    vm.weight = r.currentWeightKg == null ? null : { cur: U.wf(r.currentWeightKg), src: `Weighed ${fd(r.currentWeightDay)} · Lab Book`, v: series(r.wp), l0: sd(weeks[0]), l1: sd(weeks[weeks.length - 1]),
      gain: r.rate && r.rate.lossKgPerWeek < 0, rate: r.rate ? U.rf(Math.abs(r.rate.lossKgPerWeek)) : null, pct: r.rate ? Math.abs(r.rate.percentPerWeek).toFixed(2) : null,
      note: r.rate ? `Line fitted to ${r.rate.pointsUsed} weekly points, weeks of ${sd(r.rate.firstWeekStart)} – ${sd(r.rate.lastWeekStart)}` : vm.sig[3].reason };
    vm.waist = !lastW ? null : { cur: U.lf(r.sp[lastW].value), src: `Measured ${fd(r.sp[lastW].day)} · Lab Book`, v: series(r.sp), l0: sd(weeks[0]), l1: sd(weeks[weeks.length - 1]),
      a: wa.changeCm != null ? [`Since the week of ${sd(wa.referenceWeekStart)}`, minus(U.lf(wa.changeCm)), U.l] : ['Change', null], b: firstW !== lastW ? [`Since the week of ${sd(firstW)}`, minus(U.lf(r.sp[lastW].value - r.sp[firstW].value)), U.l] : ['Since the first reading', null] };
    const pj = r.projection, tgt = ph && ph.targetWeightKg != null ? `${U.wf(ph.targetWeightKg)} ${U.w}` : null;
    vm.proj = { est: pj.status === 'projected', lab: tgt ? `Projection · target ${tgt}` : 'Projection',
      text: { projected: `Estimated ${fd(pj.targetDay || today)} at this rate`, targetReached: 'Target reached', noTarget: 'No target set', notLosing: 'No date while weight is not falling',
        beyondHorizon: `More than ${P.maxProjectionWeeks} weeks at this rate`, needsNewWeighIn: 'Log a weigh-in to check the target', noActivePhase: 'No cut phase is active',
        weighInOverdue: over, rateUnknown: r.rateUnavailable === 'noReadings' ? 'Not measured yet' : r.rateUnavailable === 'singleReading' ? 'Needs a second weigh-in' : `Gap longer than ${P.rateWindowWeeks} weeks` }[pj.status],
      sub: pj.remainingKg > 0 && r.rate && pj.status !== 'needsNewWeighIn' ? `${U.wf(pj.remainingKg)} ${U.w} to go${pj.status === 'projected' ? ` · about ${plural(Math.round(pj.weeksRemaining), 'week')}` : ''}` : '' };
    vm.count = inp.weights.filter(x => x.day <= today).length;
    vm.due = r.started && J && wb(J, today) >= 1 && V.reason !== 'weighInOverdue';
    vm.reached = pj.status === 'targetReached' ? { t: 'Target reached', d: `${U.wf(r.wp[J].value)} ${U.w} on ${fd(r.wp[J].day)} · target ${tgt}` } : null;
    const inDomain = r.weekKeys.filter(w => w >= r.domainStart && r.wp[w]).length, val = r.currentWeightKg == null ? null : U.wf(r.currentWeightKg), r3 = rule('slowLoss');
    vm.card = !ph || !r.started ? { v: null, c: 'Set up your phase' } : val == null ? { v: null, c: 'Log your first weigh-in' }
      : V.reason === 'weighInOverdue' ? { v: val, c: vd.title } : vm.due ? { v: val, c: 'Weigh-in due this week' } : inDomain === 1 ? { v: val, c: 'First weigh-in logged' }
      : vm.reached ? { v: val, c: 'Target reached' } : V.reason === 'recompositionCheckIncomplete' ? { v: val, c: 'Lifts not known this week' }
      : V.reason === 'noRuleEvaluable' ? { v: val, c: `Building: ${r3.consecutiveWeeks} of ${r3.requiredWeeks} weeks` } : { v: val, c: vd.title };
    return vm;
  }

  /* ---------- the scorecard event note (§10.6): one view directly under the verdict ---------- */
  const noteHtml = n => !n ? '' : `<div class="wrap mt12"><div class="card evnote motion">
    ${n.lines.length ? `<div class="evh"><span class="lab">${n.title}</span><span class="chev">›</span></div>${n.lines.map(evLine).join('')}` : ''}
    ${n.earlierTitle ? `<div class="evh${n.lines.length ? ' second' : ''}"><span class="lab">${n.earlierTitle}</span>${n.lines.length ? '' : '<span class="chev">›</span>'}</div>${n.earlierLines.map(evLine).join('')}` : ''}
    ${n.moreText ? `<div class="evmore">${n.moreText}</div>` : ''}<div class="evfoot">${n.footnote}</div></div></div>`;

  /* ---------- scorecard screen: round 6's layout, plus the note and the marks ---------- */
  const AMB = vm => { const m = vm.sig.filter(x => x.s === 'met').length, n = vm.sig.filter(x => x.s === 'notMet').length, a = [];
    if (m) a.push(['--recovery', 70, 0, 150 + 45 * m, +(.10 + .06 * m).toFixed(2)]); if (n) a.push(['--rec-mid', 350, 30, 140 + 50 * n, +(.10 + .07 * n).toFixed(2)]);
    return `data-ambient='${JSON.stringify(a)}' data-ambh="520"`; };
  const kvCell = ([k, v, u]) => `<div><div class="k">${k}</div><div class="v num${v == null ? ' none' : ''}">${v == null ? '—' : v}${v != null && u ? `<small>${u}</small>` : ''}</div></div>`;
  function curve(title, unit, c, kv, tail, o) {
    const many = c.v.length > 1, w = o.ax ? 330 : 332;
    return `<div class="card cv"><div class="lab">${title}</div><div class="big num">${c.cur}<small>${unit}</small></div><div class="src" style="margin-top:8px"><i></i>${c.src}</div>
      ${plot({ type: 'points', v: c.v, w, ph: (many ? 120 : 74) + (o.ax ? 4 : 0), fs: o.ax ? 24 : 11, l0: c.l0, l1: c.l1, marks: o.marks })}${o.cap || ''}
      <div class="kv">${kv.map(kvCell).join('')}</div>${tail}</div>`;
  }
  const emptyCurves = `<div class="card cv"><div class="lab">Weight and waist</div><div class="big num none" style="margin-top:6px">—</div><div class="lab" style="margin-top:8px">Not measured yet</div></div>`;
  const sigRows = sig => sig.map(x => `<div class="sig">${glyph(x.s)}<div class="grow1"><div class="k">${x.k}</div><div class="n n1">${x.reason}</div>${x.detail ? `<div class="n">${x.detail}</div>` : ''}</div><div class="w" style="color:var(${ST[x.s].c})">${ST[x.s].w}</div></div>`).join('<div class="sep"></div>');
  const ruleRows = rules => rules.map(x => `<div class="rrow">${ruleDot(x.state)}<div class="grow1"><div class="rk">${x.name}</div>${x.sub ? `<div class="rs">${x.sub}</div>` : ''}</div><div class="rw ${x.state}">${x.word}</div></div>`).join('');
  /** sc: M.scorecardDay(...). o: { ax, ends (mark option), list, captions: 'each' | 'once' | 'none' } */
  function scorecard(sc, o = {}) {
    const vm = present1(sc.result), vd = vm.verdict, met = vm.sig.filter(x => x.s === 'met').length, known = vm.sig.filter(x => x.s !== 'unknown').length, showRules = !!vm.phase && vm.r.started;
    const w = o.ax ? 330 : 332, marks = o.ends ? ends(o.list, M.weekSlots(sc.weeks), 'points', w) : dots(sc.marked, 'points', w), cap = captionHtml(sc.caption), mode = o.captions || 'each';
    return `<div class="sb"></div>${navbar('Scorecard')}
    ${vm.phase ? `<div class="phase motion"><div class="lab">${vm.phase.lab}</div><div class="nm">${vm.phase.nm}</div><div class="meta">${vm.phase.meta}</div></div>` : ''}
    ${vm.due ? `<div class="wrap mt16"><div class="banner motion"><div><div class="bt">Weigh-in due this week</div><div class="bd">The verdict below is from the ${vd.week}.</div></div><span class="cta">Log weigh-in</span></div></div>` : ''}
    ${vm.reached ? `<div class="wrap mt16"><div class="banner motion"><div><div class="bt">${vm.reached.t}</div><div class="bd">${vm.reached.d}</div></div></div></div>` : ''}
    <div class="wrap mt16"><div class="card verdict">
      <div class="row1"><span class="lab">Verdict${vd.week ? ` · ${vd.week}` : ''}</span><span class="lab">${known ? `${met} of 4 signals met` : ''}</span></div>
      <div class="vt${vd.none ? ' none' : ''}${vd.title.length > 22 ? ' long' : ''}">${vd.title}</div>
      ${vd.lines.map(l => `<div class="rt">${l}</div>`).join('')}
      ${vd.uneval.map(l => `<div class="une">${ruleDot('unknown')}<span>${l}</span></div>`).join('')}
      ${vd.advice ? `<div class="rt t2 own">This is your own rule applied to your own numbers. Nothing has been changed.</div>` : ''}
      ${showRules ? `<div class="sep" style="margin:14px 0 6px"></div><div class="lab" style="margin-bottom:2px">Your three rules, in order</div>${ruleRows(vm.rules)}` : ''}
    </div></div>
    ${noteHtml(sc.note)}
    <div class="sec"><h3>Four signals</h3>${vd.week ? `<a>${vd.week}</a>` : ''}</div>
    <div class="wrap"><div class="card" style="padding:14px 18px">${sigRows(vm.sig)}</div></div>
    <div class="foottext" style="padding-top:8px">Compares the heaviest working set of each exercise with the week before.</div>
    <div class="sec"><h3>Weekly curves</h3><a>History<span class="chev">›</span></a></div>
    ${vm.weight ? `<div class="wrap">${curve('Weight', U.w, vm.weight, [[vm.weight.gain ? 'Rate of gain' : 'Rate of loss', vm.weight.rate, `${U.w}/week`], ['Of bodyweight', vm.weight.pct, '%/week']], `<div class="lab" style="margin-top:6px">${vm.weight.note}</div>`, { ax: o.ax, marks, cap: mode === 'none' ? '' : cap })}</div>` : `<div class="wrap">${emptyCurves}</div>`}
    ${vm.waist ? `<div class="wrap mt12">${curve('Waist', U.l, vm.waist, [vm.waist.a, vm.waist.b], '', { ax: o.ax, marks, cap: mode === 'each' ? cap : '' })}</div>` : ''}
    <div class="wrap mt12"><div class="card proj" style="margin-top:0"><div class="lab">${vm.proj.lab}${vm.proj.est ? '<span class="est">Estimate</span>' : ''}</div><div class="t${vm.proj.est ? '' : ' none'}">${vm.proj.text}</div>${vm.proj.sub ? `<div class="lab" style="margin-top:2px">${vm.proj.sub}</div>` : ''}</div></div>
    <div class="wrap mt16"><div class="btn ${vm.due || !vm.weight || vm.r.verdict.reason === 'weighInOverdue' ? 'primary' : 'secondary'}">Log weigh-in</div></div>
    <div class="wrap mt16"><div class="card" style="padding:4px 18px">${nrow('History', plural(vm.count, 'weigh-in'))}<div class="sep"></div>${nrow('Phase and rules', vm.phase ? vm.phase.nm : 'Not set up')}</div></div>
    <div class="home"></div>`;
  }
  /** The weight curve card alone, for the mark frames. */
  function weightCard(sc, o = {}) {
    const vm = present1(sc.result), w = o.ax ? 330 : 332, marks = o.ends ? ends(o.list, M.weekSlots(sc.weeks), 'points', w) : dots(sc.marked, 'points', w);
    return curve('Weight', U.w, vm.weight, [[vm.weight.gain ? 'Rate of gain' : 'Rate of loss', vm.weight.rate, `${U.w}/week`], ['Of bodyweight', vm.weight.pct, '%/week']], '', { ax: o.ax, marks, cap: captionHtml(sc.caption) });
  }

  /* ---------- Health tab: the "More health" card. Order per the rulings addendum A1; the combined frame set is the authority. ---------- */
  function healthScreen(today, list, flagOn) {
    const vm = present1(M.scorecardDay(today, list).result), pres = M.present(list, today);
    const rows = [nrow('Scorecard', `${vm.card.c} · ${vm.card.v} ${U.w}`), nrow('Body record', '')].concat(flagOn ? [nrow(STR.healthRow, pres.healthRowValue || '')] : [], [nrow('Niggle log', '')]);
    return `<div class="sb"></div><div class="hdr"><div><div class="lt">Health</div><div class="sub">${fd(today).replace(' ', ', ')}</div></div><div class="ibtn" data-ic="person" data-s="22"></div></div>
      <div class="sec"><h3>More health</h3></div>${grp(rows)}<div class="tabbar" data-on="3"></div><div class="home"></div>`;
  }

  /* ---------- Events screen (§10.2) ---------- */
  const erow = r => `<div class="erow"><div class="grow1"><div class="et1"><span>${r.title}</span>${r.isPrivate ? `<span class="ptag">${STR.tag}</span>` : ''}</div>${r.noteFirstLine ? `<div class="en">${r.noteFirstLine}</div>` : ''}</div>
    <div class="er"><div class="edt num">${r.dateText}</div>${r.offersEndToday ? `<span class="cta quiet endt">${STR.endToday}</span>` : ''}</div></div>`;
  const swiped = r => `<div class="swipe">${erow(r)}<div class="act e"><span data-ic="pencil" data-s="20"></span>${PROPOSED.edit}</div><div class="act x"><span data-ic="trash" data-s="20"></span>${STR.del}</div></div>`;
  const evTop = `<div class="sb"></div>${navbar(STR.screen, 'plus')}`;
  function evSections(pres, o = {}) {
    return [[STR.now, pres.now], [STR.upcoming, pres.upcoming], [STR.earlier, pres.earlier]].filter(([, rows]) => rows.length).map(([t, rows], i) =>
      `${gh(t, i === 0)}<div class="wrap"><div class="card" style="padding:4px 18px">${rows.map(r => r.id === o.swipe ? swiped(r) : erow(r)).join('<div class="sep"></div>')}</div></div>`).join('') +
      (pres.unreadableEntriesText ? `<div class="foottext">${pres.unreadableEntriesText}</div>` : '');
  }
  const UNREADABLE = `<div class="wrap" style="margin-top:28px"><div class="card empty"><div class="et">${STR.storeTitle}</div><div class="ed">${STR.storeBody}</div>
      <div class="btn secondary">${STR.copyStored}</div><div class="btn secondary" style="margin-top:10px">${STR.startAgain}</div></div></div>`;
  function eventsScreen(pres, o = {}) {
    if (pres.state === 'storeUnreadable') return `${evTop}${UNREADABLE}<div class="home"></div>`;
    if (pres.state === 'empty') return `${evTop}<div class="wrap" style="margin-top:28px"><div class="card empty"><div style="color:var(--t2);display:grid;place-items:center" data-ic="cal" data-s="36"></div><div class="et">${STR.emptyTitle}</div>
      <div class="ed">${STR.emptyBody}</div><div class="btn primary">${STR.add}</div></div></div><div class="home"></div>`;
    return `${evTop}${evSections(pres, o)}<div class="home"></div>`;
  }
  const eventsLoading = `${evTop}${gh('<span class="skb" style="display:inline-block;width:60px;height:13px"></span>', 1)}<div class="wrap"><div class="card" style="padding:4px 18px">${[0, 1, 2, 3, 4].map(i =>
    `<div class="erow"><div class="grow1"><div class="skb" style="width:${[96, 128, 74, 110, 88][i]}px;height:15px"></div><div class="skb" style="width:${[140, 90, 120, 70, 130][i]}px;height:11px;margin-top:7px"></div></div><div class="skb" style="width:${[78, 52, 84, 60, 78][i]}px;height:14px"></div></div>`).join('<div class="sep"></div>')}</div></div><div class="home"></div>`;
  /** A bottom sheet that asks once, over the dimmed list. */
  const ask = (behind, title, detail, warning, confirm) => `<div class="sb"></div><div class="dim">${behind}</div>
    <div class="sheet wsheet"><div class="grabber"></div><div class="at">${title}</div>${detail ? `<div class="ad">${detail}</div>` : ''}${warning ? `<div class="ad">${warning}</div>` : ''}
      <div class="btn danger" style="margin-top:18px"><span data-ic="trash" data-s="20"></span>${confirm}</div><div class="btn secondary" style="margin-top:10px">${STR.cancel}</div></div>`;
  const askDelete = (list, id, today) => { const c = M.deleteConfirmation(list.find(e => e.id === id), today); return ask(navbar(STR.screen, 'plus') + evSections(M.present(list, today)), c.title, c.detail, c.warning, c.confirmTitle); };

  /* ---------- event sheet (§10.3): one sheet for add and edit ---------- */
  function calendar(day, o = {}) {
    const m = M.month(day);
    return `<div class="cal"><div class="mh">${m.title}<span><span>‹</span><span>›</span></span></div><div class="g">${['M', 'T', 'W', 'T', 'F', 'S', 'S'].map(x => `<i>${x}</i>`).join('')}${m.cells.map(c =>
      `<span class="${!c.inMonth ? 'o' : c.day === day ? 'sel' : o.notBefore && c.day < o.notBefore ? 'f' : ''}">${c.day === day ? `<b>${c.n}</b>` : c.n}</span>`).join('')}</div></div>`;
  }
  /** d: M.draft(...). o: { today, phase: 'saving' | 'failed' | 'failedStore', menu, cal, packet, ax } */
  function sheet(d, o = {}) {
    const busy = o.phase === 'saving', bad = k => d.issues.includes(k), custom = d.kind === 'custom', chip = (day, err) => `<span class="datechip${err ? ' bad' : ''}"><span data-ic="cal" data-s="16"></span>${fdy(day)}</span>`;
    const seg = [['oneDay', STR.oneDay], ['until', STR.until], ['ongoing', STR.ongoing]].map(([k, t]) => `<span${d.length === k ? ' class="on"' : ''}>${t}</span>`).join('');
    const field = (v, ph) => v ? `<span class="fin">${v}<i class="caret"></i></span>` : `<span class="fin ph"><i class="caret"></i>${ph}</span>`;
    const menu = !o.menu ? '' : `<div class="kmenu">${M.KINDS.map(k => `<div class="${k === d.kind ? 'on' : ''}"><span>${M.kindName(k)}</span><b>${k === d.kind ? '✓' : ''}</b></div>`).join('')}</div>`;
    return `<div class="sb"></div><div class="dim">${navbar(STR.screen, 'plus')}</div>
    <div class="sheet wsheet flow esheet"><div class="grabber"></div>
      <div class="sbar"><span${busy ? ' class="t3"' : ''}>${STR.cancel}</span><span class="t">${d.isEdit ? STR.editEvent : STR.newEvent}</span><span class="sv${d.canSave && !busy ? '' : ' t3'}">${STR.save}</span></div>
      ${o.phase === 'failed' ? `<div class="fail"><b>${STR.saveFailed}</b></div>` : ''}
      ${o.phase === 'failedStore' ? `<div class="fail"><b>${STR.storeTitle}</b> ${STR.storeBody}<div class="lnk">${STR.screen}<span class="chev">›</span></div></div>` : ''}
      <div class="frm${busy ? ' busy' : ''}">
        <div class="frow"><span class="fk">${STR.kindLabel}</span><span class="fv">${M.kindName(d.kind)}<span class="ud">⌄</span></span></div>
        ${custom ? `<div class="frow"><span class="fk">${STR.name}</span>${field(d.label, bad('missingLabel') ? STR.nameNeeded : '')}</div>` : ''}
      </div>${menu}
      <div class="frm${busy ? ' busy' : ''}">
        <div class="frow"><span class="fk">${STR.starts}</span>${chip(d.start)}</div>
        ${o.cal === 'start' ? calendar(d.start) : ''}
        <div class="frow stack"><span class="fk">${STR.length}</span><div class="seg">${seg}</div></div>
        ${d.length === 'until' ? `<div class="frow"><span class="fk">${STR.ends}</span>${chip(d.end, bad('endBeforeStart'))}</div>${bad('endBeforeStart') ? `<div class="ferr">${STR.endRule}</div>` : ''}${o.cal === 'end' ? calendar(d.end, { notBefore: d.start }) : ''}` : ''}
      </div>
      ${d.isPlanned ? `<div class="ffoot">${STR.planned}</div>` : ''}
      <div class="frm${busy ? ' busy' : ''}"><div class="frow stack"><span class="fk">${STR.note}</span><div class="fnotebox${d.note ? '' : ' ph'}">${d.note || ''}</div>${d.noteRemaining != null ? `<div class="fcount num">${fill(PROPOSED.noteLeft, d.noteRemaining)}</div>` : ''}</div></div>
      <div class="frm${busy ? ' busy' : ''}"><div class="frow"><span class="fk">${STR.privateSwitch}</span><div class="toggle${d.isPrivate ? ' on' : ''}"></div></div></div>
      <div class="ffoot">${STR.privateFoot}</div>${o.packet ? `<div class="ffoot">${STR.packetSheetLine}</div>` : ''}
      ${d.isEdit ? `<div class="btn danger${busy ? ' off' : ''}" style="margin-top:22px"><span data-ic="trash" data-s="20"></span>${STR.del}</div>` : ''}
    </div>`;
  }

  /* ---------- Settings (§10.7). Neighbouring cards belong to other stages and are placeholders that show position only. ---------- */
  const stub = name => `${gh(name)}<div class="wrap dim"><div class="card" style="padding:17px 18px"><div class="stubbar"></div></div></div>`;
  const settings = (on, packet) => `<div class="sb"></div>${navbar('Settings', null)}
    ${stub('Body record').replace('class="gh"', 'class="gh" style="padding-top:10px"')}
    ${gh(STR.settingsCard)}${grp([tog(STR.settingsSwitch, on)].concat(packet === undefined ? [] : [tog(STR.packetSwitch, packet)]))}
    ${packet === undefined ? '' : gf(STR.packetFoot)}
    ${stub('Niggle log')}<div class="home"></div>`;

  /* ---------- frames ---------- */
  const G = []; let cur;
  const group = (title, note) => { cur = { title, note, frames: [] }; G.push(cur); };
  const frame = (name, html, o = {}) => cur.frames.push({ name, html, ...o });
  const STILL = { attrs: 'data-nomotion' }, SHEET = { attrs: 'data-nomotion', style: 'padding-bottom:0' }, SHORT = 'min-height:0;padding-bottom:44px';
  const day = (today, list = EVENTS, o) => M.scorecardDay(today, list, o);
  const sc = (name, today, list, o = {}, note) => { const s = day(today, list, o); frame(name, scorecard(s, { ...o, list }), { attrs: AMB(present1(s.result)), cls: o.ax ? 'ax' : '', note }); };
  const chart = (name, title, cards, o = {}) => frame(name, chartFrame(title, cards), { style: SHORT, ...o });
  const NONE = Array.from({ length: 22 }, (_, i) => i + 1);

  group('H · Health tab row (§10.1)', 'One row, "Events", in the "More health" card, present only while Personal events is on. Its value is the count of events overlapping today, or nothing. The order of the card is the rulings addendum\'s (A1): Events sits after Body record and before Niggle log. The other rows belong to other stages and are drawn to show position only; the combined frame set is the authority for the card.');
  frame('H1 Health row · one event now', healthScreen('2031-03-12', EVENTS, true), { note: 'Wed 12 Mar 2031: the fixture trip (10 – 16 Mar) overlaps today.' });
  frame('H2 Health row · nothing now', healthScreen('2031-01-29', EVENTS, true), { note: 'Wed 29 Jan 2031: no event overlaps today, so the row has no value. It is never "0 now".' });
  frame('H3 Health row · Personal events off', healthScreen('2031-03-12', EVENTS, false), { note: 'The setting is off by default. No row, and nothing else on this screen moves.' });

  group('L · Events screen (§10.2)', 'Newest start first, in up to three sections: Now (overlapping today), Upcoming, Earlier. This is the one screen where a private event shows its own name and note. Rows are neutral: an event has no colour.');
  frame('L1 Events · rows in three sections', eventsScreen(M.present(EVENTS, '2031-03-12')), { note: 'Wed 12 Mar 2031. A planned ongoing event reads "From 19 May".' });
  frame('L2 Events · ongoing, with End today', eventsScreen(M.present(EVENTS, '2031-05-28')), { note: 'Wed 28 May 2031.' });
  frame('L3 Events · after End today', eventsScreen(M.present(M.endToday(EVENTS, 'e5', '2031-05-28'), '2031-05-28')), { note: 'The end day is today, so the event is still under Now, with its dates and no action.' });
  frame('L4 Events · only future events', eventsScreen(M.present(VARIANTS.DUpcoming, '2031-01-08')), { note: 'Wed 8 Jan 2031, with three planned events stored.' });
  frame('L5 Events · empty', eventsScreen(M.present([], '2031-03-12')));
  frame('L6 Events · loading', eventsLoading, STILL);
  frame('L7 Events · some entries unreadable', eventsScreen(M.present(EVENTS, '2031-03-12', { unreadableEntryCount: 1 })), { note: 'Variant V6: one stored entry of a kind this version does not know. It is kept and nothing offers to remove it.' });
  frame('L8 Events · store unreadable', eventsScreen(M.present([], '2031-03-12', { needsAttention: true })), { note: 'Variant V7.' });
  frame('L9 Events · Start again asks once', ask(navbar(STR.screen, 'plus') + UNREADABLE, STR.startAgainAsk, '', STR.deleteWarning, STR.startAgain), STILL);
  frame('L10 Events · swipe to edit or delete', eventsScreen(M.present(EVENTS, '2031-03-12'), { swipe: 'e8' }), STILL);
  frame('L11 Events · AX5', eventsScreen(M.present(EVENTS, '2031-05-28')), { cls: 'ax' });

  group('D · Delete confirmation (§10.4)', 'Asks once. Deleting is immediate and has no undo; the sheet says so.');
  frame('D1 Delete · asks once', askDelete(EVENTS, 'e1', '2031-03-12'), STILL);
  frame('D2 Delete · a private event', askDelete(EVENTS, 'e6', '2031-03-28'), { attrs: 'data-nomotion', note: 'Inside the Events screen, so the owner\'s own name for the event is shown.' });

  group('S · Event sheet (§10.3)', 'One sheet for add and edit: kind, start, length (one day, until a date, or ongoing), note, and the Private switch. The Private switch starts at the kind\'s default and follows a change of kind until the owner touches it. In these frames "today" is Wed 12 Mar 2031 unless the note says otherwise.');
  const T = '2031-03-12', D = (a, e, today = T) => M.draft(today, a, e);
  frame('S1 New event · first open', sheet(D()), SHEET);
  frame('S2 New event · choosing the kind', sheet(D(), { menu: 1 }), SHEET);
  frame('S3 New event · Illness, Private follows the kind', sheet(D([['kind', 'illness']])), SHEET);
  frame('S4 New event · Private kept as the owner set it', sheet(D([['private', true], ['kind', 'deload']])), { ...SHEET, note: 'The owner switched Private on, then changed the kind to Deload. The switch stays where the owner put it.' });
  frame('S5 New event · Something else, name needed', sheet(D([['kind', 'custom']])), { ...SHEET, note: 'Save is disabled. The field says what is needed; nothing is coloured as an error.' });
  frame('S6 New event · Something else, named', sheet(D([['kind', 'custom'], ['label', E('e6').label], ['start', E('e6').startDay], ['note', E('e6').note]])), SHEET);
  frame('S7 New event · Until, with an end date', sheet(D([['start', E('e1').startDay], ['length', 'until'], ['end', E('e1').endDay], ['note', E('e1').note]])), SHEET);
  frame('S8 New event · picking the end date', sheet(D([['start', E('e1').startDay], ['length', 'until'], ['end', E('e1').endDay]]), { cal: 'end' }), { ...SHEET, note: 'Days before the start are dimmed.' });
  frame('S9 New event · end before start', sheet(D([['start', E('e1').startDay], ['length', 'until'], ['end', M.add(E('e1').startDay, -1)]])), { ...SHEET, note: 'Variant V3. Save is disabled.' });
  frame('S10 New event · Ongoing', sheet(D([['kind', 'illness'], ['length', 'ongoing']], null, E('e5').startDay)), { ...SHEET, note: 'Today is Mon 19 May 2031.' });
  frame('S11 New event · planned', sheet(D([['kind', 'dietBreak'], ['start', E('e3').startDay], ['length', 'until'], ['end', E('e3').endDay]])), SHEET);
  frame('S12 New event · note near its limit', sheet(D([['note', M.LONG_NOTE]])), { ...SHEET, note: 'The count appears from 240 characters on. The note is invented filler text.' });
  frame('S13 Edit event', sheet(D([], E('e1'))), SHEET);
  frame('S14 Edit event · saving', sheet(D([], E('e1')), { phase: 'saving' }), SHEET);
  frame('S15 Edit event · save failed', sheet(D([], E('e1')), { phase: 'failed' }), { ...SHEET, note: 'The values are intact and Save is the retry.' });
  frame('S16 New event · save failed, store unreadable', sheet(D(), { phase: 'failedStore' }), SHEET);
  frame('S17 New event · with the coach packet sentence (packet v2 change)', sheet(D([['kind', 'illness']]), { packet: 1 }), { ...SHEET, note: 'Not part of this stage\'s milestone. The second sentence arrives with the packet v2 change and shows only while the Coach packet is on (§9.6).' });
  frame('S18 New event · AX5', sheet(D([['start', E('e1').startDay], ['length', 'until'], ['end', E('e1').endDay], ['note', E('e1').note]])), { ...SHEET, cls: 'ax' });

  group('M · Marks on the time axis (§10.5)', 'An event is a small grey dot in a thin row under the plot, above the date labels: one dot per covered day or week. No band, no rule, no line joining the dots, no label on the plot. With no event in view the row is absent and the chart is exactly today\'s chart. The caption beneath says what the dots are. The three host charts are sketches of existing charts: the scorecard weight curve, a thirty-day bar chart (Recovery) and a line chart (Sleep); their daily values are invented by the model.');
  chart('M1 Weight curve · no event', 'Scorecard', weightCard(day('2031-01-29', VARIANTS.V1)), { note: 'Variant V1: nothing stored. No row, no caption.' });
  chart('M2 Weight curve · one event', 'Scorecard', weightCard(day('2031-01-29')), { note: 'Week 4. The one-day event of 22 Jan marks week 3.' });
  chart('M3 Weight curve · dense run', 'Scorecard', weightCard(day('2031-06-04')), { note: 'Week 22: marks at weeks 3, 5, 7, 8, 10, 12, 15, 16, 20, 21 and 22.' });
  chart('M4 Weight curve · missed week', 'Scorecard', weightCard(day('2031-03-19')), { note: 'Week 11. The curve breaks at week 10; the ring is the missed week and the dot under it is the trip.' });
  chart('M5 Recovery bars · no event', 'Recovery', dayCard('recovery', '2031-01-20', 30, EVENTS));
  chart('M6 Recovery bars · one event', 'Recovery', dayCard('recovery', '2031-01-29', 30, EVENTS));
  chart('M7 Recovery bars · dense run', 'Recovery', dayCard('recovery', '2031-04-28', 30, EVENTS), { note: 'Fourteen consecutive days. No band is drawn behind the bars.' });
  chart('M8 Recovery bars · days not measured', 'Recovery', dayCard('recovery', '2031-03-19', 30, EVENTS), { note: 'Two days with no recovery (the model takes the strap as not worn on 13 and 14 Mar). They have no bar, not a zero bar.' });
  chart('M9 Sleep line · no event', 'Sleep', dayCard('sleep', '2031-01-20', 30, EVENTS));
  chart('M10 Sleep line · one event', 'Sleep', dayCard('sleep', '2031-01-29', 30, EVENTS));
  chart('M11 Sleep line · dense run, thinned', 'Sleep', dayCard('sleep', '2031-04-28', 90, EVENTS), { note: 'Ninety days in 332 points: dots closer than 6 points are thinned; the first and last of each run are kept.' });
  chart('M12 Sleep line · days not measured', 'Sleep', dayCard('sleep', '2031-03-19', 30, EVENTS), { note: 'The line breaks at the days not measured.' });
  chart('M13 Steps bars · seven days', 'Training', dayCard('steps', '2031-03-12', 7, EVENTS));
  chart('M14 Marks · AX5', 'Recovery', dayCard('recovery', '2031-03-19', 30, EVENTS, { ax: 1 }), { cls: 'ax' });

  group('C · Chart caption (§10.5)', 'A dot has no text, so the caption names it. At most two lines, the two with the latest start, then a count. A private event never shows its name or note here.');
  chart('C1 Caption · one event', 'Recovery', dayCard('recovery', '2031-01-29', 30, EVENTS));
  chart('C2 Caption · two events', 'Recovery', dayCard('recovery', '2031-02-05', 30, EVENTS));
  chart('C3 Caption · more than two', 'Sleep', dayCard('sleep', '2031-03-26', 90, EVENTS));
  chart('C4 Caption · a private event', 'Training', dayCard('steps', '2031-03-28', 7, EVENTS), { note: 'Stored as "Fixture change" with a note. Outside the Events screen it is "Private event".' });
  chart('C5 Caption · ongoing', 'Training', dayCard('steps', '2031-05-28', 7, VARIANTS.DOpen), { note: 'Design variant: the owner switched Private off on the ongoing illness event.' });
  chart('C6 Caption · ongoing and private', 'Training', dayCard('steps', '2031-05-28', 7, EVENTS));
  chart('C7 Caption · AX5', 'Sleep', dayCard('sleep', '2031-03-26', 90, EVENTS, { ax: 1 }), { cls: 'ax' });
  chart('C8 Caption · spoken summary', 'Recovery', dayCard('recovery', '2031-03-19', 30, EVENTS, { tail: `<div class="note" style="margin-top:14px"><b>VoiceOver, after the chart's own summary:</b> ${M.dayWindow('recovery', '2031-03-19', 30, EVENTS).caption.spokenText}</div>` }), { note: 'The dashed box is an annotation, not part of the screen.' });

  group('O · Options for the owner', 'Each pair draws the same data two ways. The first of each pair is the specification\'s recommendation and is what every other frame uses.');
  const optCards = o => [weightCard(day('2031-04-23'), { ...o, list: EVENTS }), dayCard('recovery', '2031-04-28', 30, EVENTS, o), dayCard('sleep', '2031-04-28', 90, EVENTS, o)];
  chart('O1 Marks · a dot per covered position (recommended)', 'Marks', optCards({}));
  chart('O2 Marks · a dot at the start and an open dot at the end', 'Marks', optCards({ ends: 1 }), { note: 'One filled dot where an event starts and one open dot where it ends. Lighter on a long event, but a week inside a long event has no mark of its own.' });
  sc('O3 Scorecard · caption under each curve (as specified)', '2031-03-26', EVENTS, { captions: 'each' }, 'The specification gives every adopting chart its caption, so the scorecard names the events three times: the note, the weight curve and the waist curve.');
  sc('O4 Scorecard · one caption, under the weight curve', '2031-03-26', EVENTS, { captions: 'once' });
  sc('O5 Scorecard · marks only, the note names the events', '2031-03-26', EVENTS, { captions: 'none' }, 'The dots stay on both curves. The note under the verdict is the only text.');
  sc('O6 Scorecard note · judged week only (the other answer to S7)', '2031-03-26', EVENTS, { captions: 'once', judgedWeekOnly: true }, 'Compare with O4, which shows both sections (the recommendation).');

  group('N · Scorecard annotation (§10.6)', 'A note directly under the verdict names the events of the judged week and, in a second short section, of the earlier weeks the rules looked back over. The verdict, rules, signals, rate and projection are the stage 1 fixture\'s, unchanged in every frame. Captions are drawn once, under the weight curve (option O4), pending the owner\'s choice.');
  const N = (name, today, list, o, note) => sc(name, today, list, { captions: 'once', ...(o || {}) }, note);
  N('N1 Scorecard · no events stored', '2031-01-29', VARIANTS.V1, {}, 'Variant V1, week 4. Nothing is added: this is the stage 1 screen.');
  N('N2 Scorecard · an event in the judged week', '2031-01-22', EVENTS, {}, 'Week 3.');
  N('N3 Scorecard · weigh-in due, in a week with an event', '2031-03-12', EVENTS, {}, 'Week 10, no reading yet. The verdict is week 9\'s, so the note lists only the weeks behind it. The trip shows on the curves, under the open ring of week 10.');
  N('N4 Scorecard · after a missed week', '2031-03-19', EVENTS, {}, 'Week 11. The gap explains itself: ring, dot, and the trip named in the note\'s earlier section.');
  N('N5 Scorecard · a private event', '2031-03-26', EVENTS, {}, 'Week 12.');
  N('N6 Scorecard · during a deload', '2031-02-05', EVENTS, {}, 'Week 5. The scorecard keeps reporting; the deload is noted and nothing else changes.');
  N('N7 Scorecard · during a diet break', '2031-04-23', EVENTS, {}, 'Week 16. A diet break is an event, not a phase: the phase, the judged week and the verdict are the fixture\'s.');
  N('N8 Scorecard · an ongoing private event', '2031-05-28', EVENTS, {}, 'Week 21.');
  N('N9 Scorecard · more than three events', '2031-04-20', VARIANTS.DMany, {}, 'Design variant: three more events added to week 15. Three lines, then the count.');
  N('N10 Scorecard · private deload', '2031-02-05', VARIANTS.V9, {}, 'Variant V9.');
  N('N11 Scorecard · no readings', '2031-01-08', EVENTS, { fixture: { without: NONE } }, 'No judged week, so no note.');
  N('N12 Scorecard · weigh-in overdue', '2031-03-19', EVENTS, { fixture: { without: [11] } }, 'No note while the verdict has lapsed. The curves still carry their marks.');
  N('N13 Scorecard · AX5', '2031-03-26', EVENTS, { ax: 1 });
  { const vm = present1(day('2031-03-12').result);
    frame('N14 Today card · unchanged', `<div class="sb"></div><div class="navbar"><div style="width:40px"></div><div class="ttl">Today</div><div style="width:40px"></div></div><div class="sec" style="padding-top:12px"><h3>Your cards</h3><a>Edit<span class="chev">›</span></a></div>
      <div class="wrap"><div class="ycgrid">${tile('scale', '--t1', 'Scorecard', vm.card.v, U.w, vm.card.c)}${tile('scale', '--t1', 'Weight', vm.card.v, U.w, 'Lab Book')}</div></div><div class="home"></div>`, { style: SHORT, note: 'Wed 12 Mar 2031, during the fixture trip. Events never reach the Today card: it is the stage 1 card in every state.' }); }

  group('G · Settings (§10.7)', 'One card, "Events", with one switch. The card is always drawn on iPhone because it holds the switch; the feature is off until the owner turns it on. Its place is fifth in the one order: after Body record, before Niggle log. Those two cards belong to other stages and are placeholders here.');
  frame('G1 Settings · Personal events off', settings(false), STILL);
  frame('G2 Settings · Personal events on', settings(true), STILL);
  frame('G3 Settings · with the packet switch, off (packet v2 change)', settings(true, false), { ...STILL, note: 'Not part of this stage\'s milestone (§9.6). Mounted only while both Personal events and the Coach packet are on.' });
  frame('G4 Settings · with the packet switch, on (packet v2 change)', settings(true, true), STILL);
  frame('G5 Settings · AX5', settings(true), { cls: 'ax', attrs: 'data-nomotion' });

  group('W · Notifications and widgets (§10.8)', 'This stage adds none.');
  frame('W1 Notifications and widgets · none', `<div class="sb"></div><div class="navbar"><div style="width:40px"></div><div class="ttl">Notifications and widgets</div><div style="width:40px"></div></div>
    <div class="wrap mt16"><div class="note"><b>No notification is sent by this stage and no notification text exists.</b> No widget, widget field or Live Activity field is added. No event, private or not, appears on the lock screen, in a widget or on the watch. Nothing prompts the owner to log an event.</div></div><div class="home"></div>`, { style: SHORT, attrs: 'data-nomotion', note: 'An annotation frame: there is nothing to draw.' });

  const PREFIX = 'S5 / ';
  if (NODE) { module.exports = { groups: G, frames: G.flatMap(g => g.frames.map(f => ({ ...f, name: PREFIX + f.name, group: g.title }))) }; return; }

  // ?only=N (or ?only=N4) shows just the frames whose id starts with that text. Handy for review; not used for export.
  const ONLY = new URLSearchParams(location.search).get('only');
  if (ONLY) { G.forEach(g => g.frames = g.frames.filter(f => f.name.startsWith(ONLY))); for (let i = G.length - 1; i >= 0; i--) if (!G[i].frames.length) G.splice(i, 1); }
  document.getElementById('boards').innerHTML = G.map(g => `<h2 class="grp-title">${g.title}</h2><p class="grp-note">${g.note}</p><div class="board">${g.frames.map(f =>
    `<section><div class="board-title">${PREFIX}${f.name}</div><div class="screen${f.cls ? ' ' + f.cls : ''}" ${f.attrs || ''} style="${f.style || ''}">${f.html}</div>${f.note ? `<p class="fnote">${f.note}</p>` : ''}</section>`).join('')}</div>`).join('');
  boot();
  // ?static=1&export=s5-frames.json: write the frames file for the Figma plugin (design/tools/serve.py --export).
  const EXPORT_NAME = new URLSearchParams(location.search).get('export');
  if (EXPORT_NAME) window.addEventListener('load', () => setTimeout(() => exportSvgFrames(EXPORT_NAME).then(r => { document.title = `exported ${r.frames.length} frames`; }), 400));
})();
