/* Round combined · the frames. ONE layout for the three surfaces every stage shares (rulings addendum A1):
   the Health tab's "More health" card, the Settings cards and the scorecard screen, plus Today's Your cards.
   Every frame is built here from model.js (the Fixture Person) and worded with the specifications' §11 strings
   through the STR table below. Nothing in this file types a result by hand, and nothing in it touches the DOM:
   it returns strings, so Node can run it (check.js). combined.js puts the result on the page.
   EVERY VALUE IS SYNTHETIC. Declares one global, SCF. */
(function (root) {
  const NODE = typeof module !== 'undefined' && module.exports;
  const M = NODE ? require('./model.js') : root.SCM;
  const P = NODE ? require('./r6-presenter.js') : root.SCP;
  const { sd, fd, plural, ST, glyph, ruleDot, FX, tile, scTile, skTile, AMB, count, kvCell, emptyCurves, ruleRows, nrow, gh, gf, tog } = P;
  const { weighDay, addDays, FIXTURE_PARAMS, FIXTURE_PHASE } = M.R6;

  /* ---------- strings. [text as the source prints it, where it comes from]. "proposal" = not in any specification. ---------- */
  const S1 = 'stage-1.md', S2 = 'stage-2.md', S3 = 'stage-3.md', S4 = 'stage-4.md', S5 = 'stage-5.md', S6 = 'stage-6.md';
  const APP_P = 'Strand/Data/CutScorecardPresenter.swift', APP_S = 'Strand/Screens/SettingsView.swift', APP_H = 'StrandiOS/Redesign/RedesignHealthView.swift';
  const PROPOSAL = 'proposal';
  const STR = {
    // stage 1 (shipped strings, read from the app source; the verdict, signal and curve strings come through r6-presenter.js)
    scTitle: ['Scorecard', APP_S], scBlurb: ['A weekly weigh-in and one verdict from the rules you set. Off by default. Everything stays on this iPhone.', APP_S],
    scSwitch: ['Weekly weigh-in and scorecard', APP_P], scReminder: ['Weekly reminder', APP_P], day: ['Day', APP_S], time: ['Time', APP_S],
    scRemOff: ['The reminder is off unless you turn it on. One notification a week, on the day and at the time you choose.', APP_P],
    scRemOn: ['One notification a week. It never contains a measurement, a verdict or the phase name.', APP_P], looks: ['What it looks like', APP_S],
    n1Title: ['Weekly weigh-in', S1], n1Body: ['Weight, then waist. It takes under a minute.', S1],
    denied: ['Notifications are off for NOOP', APP_P], deniedD: ['The reminder cannot be delivered until they are allowed.', APP_P], openSettings: ['Open Settings', APP_P],
    labBook: ['Lab Book', S1],
    // stage 2
    pkTitle: ['Coach packet', S2], pkBlurb: ['One block of text with your recent numbers, for pasting to your coach. Off by default. NOOP sends it nowhere.', S2],
    pkDetail: ['Copy your numbers for your coach', S2],
    // stage 3
    inTitle: ['Intake', S3], inSource: ['Source', S3], inFloor: ['Protein floor', S3], inRange: ['Calorie range', S3], inHard: ['Hard floor', S3], inApps: ['Apps to count', S3],
    inSupp: ['Supplements', S3], inAddSupp: ['Add a supplement', S3], inCutoff: ['Cutoff time', S3], inReminder: ['Cutoff reminder', S3],
    inSilent: ['Silent on days when it falls within 30 minutes of your wind-down reminder.', S3], inSuppCap: ['Supplements listed here are left out of the Coach.', S3],
    inWhole: ['Enter whole grams', S3], inAttention: ['Your targets need attention', S3],
    srcNone: ['None', S3], srcHealth: ['Apple Health', S3], srcHere: ['Enter here', S3],
    prTitle: ['Protein', S3], prSub: ['Today against your floor', S3], prTo: ['%lld g to your floor', S3], prMet: ['Floor met', S3], prOver: ['+%lld g over your floor', S3],
    prNoFloor: ['No floor set', S3], prNothing: ['Nothing logged today', S3], prDay: ['Day total', S3], prNot: ['Not measured', S3], prChoose: ['Choose where intake comes from', S3],
    prLast: ['Last read %@', S3], prFail: ['Could not read Apple Health', S3], prImported: ['imported', S3],
    capHealth: ['Apple Health', S3], capHere: ['Entered here', S3], capCsv: ['CSV import', S3], capSeveral: ['Several sources', S3],
    n2Title: ['Food cutoff', S3], n2Body: ['Your cutoff time is now.', S3],
    // stage 4
    brTitle: ['Body record', S4], brNone: ['No scans yet', S4], brLast: ['Last scan <date>', S4], brUnits: ['Report units in Lab Book', S4],
    brUnitsD: ['Type blood results in the unit your report prints.', S4], brD: ['Scans and benchmarks, entered as printed and compared.', S4],
    // stage 5
    evTitle: ['Events', S5], evNow: ['%lld now', S5], evSwitch: ['Personal events', S5], evPrivate: ['Private event', S5], evWeek: ['Events this week', S5],
    evEarlier: ['Earlier in the weeks behind this verdict', S5], evFoot: ['Shown for context. Events do not change the verdict.', S5], evMore: ['and %lld more', S5],
    evLine: ['%@ · %@', S5], evSince: ['since %@', S5], evRange: ['%@ – %@', S5],
    kTravel: ['Travel', S5], kIllness: ['Illness', S5], kDietBreak: ['Diet break', S5], kDeload: ['Deload', S5], kSupplementChange: ['Supplement change', S5],
    evPacket: ['Include private events in the coach packet', S5], evPacketD: ['Private events and their notes stay out of the packet unless this is on.', S5],
    // stage 6
    ngTitle: ['Niggle log', S6], ngBlurb: ['Record a complaint and see it against your own rules. Off by default.', S6], ngOpen: ['%lld open', S6],
    rcTitle: ['Recovery context', S6], rcBlurb: ['Weekly resting heart rate and HRV beside the scorecard. Not a score.', S6],
    tlTitle: ['Timeline', S6], tlBlurb: ['Phases, checkpoints and your estimate in one list.', S6], tlNext: ['Next: %@', S6],
    // the Health tab as it ships
    hLive: ['Live heart rate', APP_H], hAll: ['All metrics', APP_H], hSkin: ['Skin temperature', APP_H], hVital: ['Vitality', APP_H], hContrib: ['Contributors', APP_H],
    hSync: ['Strap sync', APP_H], hLab: ['Lab Book', APP_H], hFused: ['Your Data, Fused', APP_H], hMore: ['More', APP_H],
    yourCards: ['Your cards', 'StrandiOS/Redesign/YourCardsSection.swift'],
    // proposals: strings the specifications do not give. Listed in the README; nothing here is final.
    pInBlurb: ['Protein and calories against your own floor and range. Off by default. Everything stays on this iPhone.', PROPOSAL],
    pEvBlurb: ['Mark travel, illness, a diet break or a deload, and charts show when it happened. Off by default.', PROPOSAL],
    pRcNeeds: ['Opens from the scorecard, so it shows once the scorecard is on.', PROPOSAL],
    pInNone: ['With no source, the Protein card and widget have nothing to show.', PROPOSAL],
    pInUnavailable: ['Apple Health is not available on this iPhone. Source is back to None.', PROPOSAL],
    pInLowHigh: ['The low end is above the high end. Nothing was saved.', PROPOSAL],
    pInRemOff: ['The reminder is off unless you turn it on. One notification a day, at your cutoff time.', PROPOSAL],
    pInRemOn: ['One notification a day. It never contains an amount, a floor or a supplement name.', PROPOSAL],
    pRangeValue: ['%lld to %lld kcal', PROPOSAL], pKcal: ['%lld kcal', PROPOSAL], pGrams: ['%lld g', S1],
    pScCardSub: ['Weight and this week\'s verdict', PROPOSAL],
  };
  const used = new Set();
  /** The string for a key, its placeholders (%lld, %@, <date>) filled in order. Records the key for check.js. */
  const t = (key, ...args) => { used.add(key); let i = 0; return STR[key][0].replace(/%lld|%@|<date>/g, () => args[i++]); };

  /* ---------- small pieces ---------- */
  const U = P.METRIC, floor = M.INTAKE.floorGrams, ALL_WEEKS = Array.from({ length: 22 }, (_, i) => i + 1);
  const anno = (l, body) => `<div><div class="lab anno" style="padding:0 2px 6px;min-height:42px;display:flex;align-items:flex-end">${l}</div>${body}</div>`;
  const annoRow = l => `<div class="lab anno" style="padding:22px calc(var(--gutter) + 2px) 8px">${l}</div>`;
  const chev = '<span class="chev">›</span>';
  const skb = (w, h, extra = '') => `<div class="skb" style="width:${w};height:${h}px${extra}"></div>`;
  const navbar = (title, o = {}) => `<div class="navbar"><div class="nbl">${o.back === 0 ? '' : '<div class="ibtn" data-ic="chev-l" data-s="22"></div>'}</div><div class="ttl">${title}</div><div class="nbr">${o.packet ? `<div class="ibtn" data-ic="${o.packetIcon || 'doc'}" data-s="20"></div>` : ''}${o.plus === 0 ? '' : '<div class="ibtn" data-ic="plus" data-s="22"></div>'}</div></div>`;

  /* ---------- events (stage 5 §10.5, §10.6, §11) ---------- */
  const KIND = { travel: 'kTravel', illness: 'kIllness', dietBreak: 'kDietBreak', deload: 'kDeload', supplementChange: 'kSupplementChange' };
  // Outside the Events screen a sensitive event is "Private event": never its kind, label or note.
  const evName = e => e.sensitive ? t('evPrivate') : e.kind === 'custom' ? e.label : t(KIND[e.kind]);
  const evDates = e => e.end == null ? t('evSince', sd(e.start)) : e.end === e.start ? sd(e.start)
    : t('evRange', e.start.slice(0, 7) === e.end.slice(0, 7) ? String(+e.start.slice(8)) : sd(e.start), sd(e.end));
  const evLine = e => t('evLine', evName(e), evDates(e));
  const evRow = e => `<div class="evl"><i></i><span>${evLine(e)}</span></div>`;
  function noteBody(n) {
    return `${n.inWeek.length ? `<div class="lab">${t('evWeek')}</div>${n.inWeek.map(evRow).join('')}` : ''}
      ${n.earlier.length ? `<div class="lab${n.inWeek.length ? ' evgap' : ''}">${t('evEarlier')}</div>${n.earlier.map(evRow).join('')}` : ''}
      ${n.more ? `<div class="evmore">${t('evMore', n.more)}</div>` : ''}<div class="evfoot">${t('evFoot')}</div>`;
  }
  const noteCard = n => `<div class="wrap mt12"><div class="card evnote"><span class="evgo">${chev}</span>${noteBody(n)}</div></div>`;
  /** The chart caption of stage 5 §10.5: the two events with the latest start in the window, then "and n more". */
  function chartCaption(weeks, events, today) {
    if (!weeks.length) return '';
    const inWin = events.filter(e => e.start <= today && M.overlaps(e, weeks[0], addDays(weeks[weeks.length - 1], 6))).sort((a, b) => a.start < b.start ? 1 : -1);
    if (!inWin.length) return '';
    return `<div class="evcap">${inWin.slice(0, 2).map(e => `<div>${evLine(e)}</div>`).join('')}${inWin.length > 2 ? `<div>${t('evMore', inWin.length - 2)}</div>` : ''}</div>`;
  }

  /* ---------- weekly chart: line, gradient area, one point per weekly reading. No rules, bands or target lines.
     Round 6's weekChart, restated as data so Node can run it, plus stage 5's mark row: a quiet dot on the time
     axis under a week an event covers. With no mark the output is round 6's, value for value. ---------- */
  const MARK_ROW = 8, MARK_R = 2, MARK_FILL = '#8A8A93';   // proposed NoopTheme.Layout.chartAxisMarkRow 8, chartAxisMark 4; textTertiary
  function smooth(pts) { let d = `M${pts[0][0]},${pts[0][1]}`; for (let i = 0; i < pts.length - 1; i++) { const p0 = pts[i - 1] || pts[i], p1 = pts[i], p2 = pts[i + 1], p3 = pts[i + 2] || p2;
    d += ` C${(p1[0] + (p2[0] - p0[0]) / 6).toFixed(2)},${(p1[1] + (p2[1] - p0[1]) / 6).toFixed(2)} ${(p2[0] - (p3[0] - p1[0]) / 6).toFixed(2)},${(p2[1] - (p3[1] - p1[1]) / 6).toFixed(2)} ${p2[0]},${p2[1]}`; } return d; }
  /** d: { v: "100,99.2,x,98.4", m: "0,0,1,0" (optional), fs, l0, l1 }. Returns a tree of { t, a, x, k } nodes. */
  function weekChartSpec(d, w, H, c, id) {
    const v = d.v.split(',').map(x => x === 'x' ? null : +x), m = d.m ? d.m.split(',').map(x => x === '1') : [];
    const fs = +(d.fs || 11), row = m.some(Boolean) ? MARK_ROW : 0, h = H - fs - 11 - row, n = v.length, out = [];
    const real = v.filter(x => x !== null); let mn = Math.min(...real), mx = Math.max(...real); const span = (mx - mn) || 1; mn -= span * .14; mx += span * .14;
    const X = i => +(8 + i * (w - 16) / Math.max(1, n - 1)).toFixed(2), Y = x => +(12 + (1 - (x - mn) / (mx - mn)) * (h - 20)).toFixed(2);
    out.push({ t: 'defs', a: {}, k: [
      { t: 'linearGradient', a: { id: 'a' + id, x1: 0, y1: 12, x2: 0, y2: h, gradientUnits: 'userSpaceOnUse' }, k: [{ t: 'stop', a: { offset: 0, 'stop-color': c, 'stop-opacity': .28 } }, { t: 'stop', a: { offset: 1, 'stop-color': c, 'stop-opacity': 0 } }] },
      { t: 'linearGradient', a: { id: 's' + id, x1: 0, y1: 0, x2: w, y2: 0, gradientUnits: 'userSpaceOnUse' }, k: [{ t: 'stop', a: { offset: 0, 'stop-color': c, 'stop-opacity': .35 } }, { t: 'stop', a: { offset: 1, 'stop-color': c, 'stop-opacity': 1 } }] }] });
    const runs = []; let cur = null; v.forEach((x, i) => { if (x === null) { cur = null; return; } if (!cur) runs.push(cur = []); cur.push([X(i), Y(x)]); });
    // A week with no reading breaks the line; it is never drawn across.
    runs.forEach(pts => { if (pts.length < 2) return; const line = smooth(pts), a = pts[0], b = pts[pts.length - 1];
      out.push({ t: 'path', a: { class: 'area', d: `${line} L${b[0]},${h} L${a[0]},${h} Z`, fill: `url(#a${id})` } });
      out.push({ t: 'path', a: { class: 'stroke', d: line, fill: 'none', stroke: `url(#s${id})`, 'stroke-width': 2.5, 'stroke-linecap': 'round', 'stroke-linejoin': 'round' } }); });
    const all = runs.flat();
    all.forEach((p, i) => { const last = i === all.length - 1;
      if (last) out.push({ t: 'circle', a: { class: 'halo', cx: p[0], cy: p[1], r: 8, fill: c, opacity: .22 } });
      out.push({ t: 'circle', a: { class: 'pt', cx: p[0], cy: p[1], r: last ? 4 : 2.6, fill: c, stroke: '#0B0B0D', 'stroke-width': last ? 1.5 : 1.2 } }); });
    // A week with no reading: an open ring on the time axis.
    v.forEach((x, i) => { if (x === null) out.push({ t: 'circle', a: { class: 'missed', cx: X(i), cy: h + 3, r: 2.6, fill: 'none', stroke: '#FFFFFF', 'stroke-opacity': .4, 'stroke-width': 1.2 } }); });
    // A week an event covers: a small filled dot in the row beneath. No line joins dots; no band, rule or label.
    m.forEach((on, i) => { if (on && i < n) out.push({ t: 'circle', a: { class: 'evmark', cx: X(i), cy: h + 11, r: MARK_R, fill: MARK_FILL } }); });
    const text = (x, s, anchor) => out.push({ t: 'text', a: { x, y: H - 3, 'text-anchor': anchor, fill: '#9B9BA3', 'font-size': fs, 'font-weight': 500, 'font-family': '-apple-system,system-ui' }, x: s });
    if (d.l0) text(X(0) - 4, d.l0, 'start');
    if (d.l1 && n > 1) text(X(n - 1) + 4, d.l1, 'end');
    return out;
  }

  /* ---------- scorecard screen: round 6's layout with each stage's addition in its place ---------- */
  function curve(title, unit, c, kv, tail, o) {
    const marks = o.marks && o.marks.includes('1') ? o.marks : null;
    return `<div class="card cv"><div class="lab">${title}</div><div class="big num">${count(c.cur)}<small>${unit}</small></div><div class="src" style="margin-top:8px"><i></i>${c.src}</div>
      <svg class="wk" width="${o.ax ? 330 : 332}" height="${(c.v.includes(',') ? 142 : 96) + (o.ax ? 14 : 0) + (marks ? MARK_ROW : 0)}" data-v="${c.v}"${marks ? ` data-m="${marks}"` : ''}${o.ax ? ' data-fs="24"' : ''} data-l0="${c.l0}" data-l1="${c.l1}"></svg>
      ${o.caption || ''}<div class="kv">${kv.map(kvCell).join('')}</div>${tail}</div>`;
  }
  const sigRows = sig => sig.map(x => `<div class="sig">${glyph(x.s)}<div class="grow1"><div class="k">${x.k}</div><div class="n n1">${x.reason}</div>${x.detail ? `<div class="n">${x.detail}</div>` : ''}${x.src ? `<div class="src sgsrc"><i></i>${x.src}</div>` : ''}</div><div class="w" style="color:var(${ST[x.s].c})">${ST[x.s].w}${x.link ? chev : ''}</div></div>`).join('<div class="sep"></div>');
  const CAP = { appleHealth: 'capHealth', quickAdd: 'capHere', csv: 'capCsv', several: 'capSeveral' };
  /** Stage 3 §10.4: with the intake flag on the protein row names its source and opens the intake screen. */
  function withIntake(vm, srcKey) {
    return vm.sig.map((x, i) => { if (i !== 2) return x; const logged = vm.r.signals.protein.daysLogged || 0;
      const key = logged ? M.proteinSource(M.SOURCE_DAYS[srcKey].slice(0, logged)) : null;
      return { ...x, src: key ? t(CAP[key]) : null, link: true }; });
  }
  const linksCard = (vm, f) => `<div class="wrap mt16"><div class="card" style="padding:4px 18px">${[nrow('History', plural(vm.count, 'weigh-in')), nrow('Phase and rules', vm.phase ? vm.phase.nm : 'Not set up')]
    .concat(f.recovery ? [nrow(t('rcTitle'), '')] : [], f.timeline ? [nrow(t('tlTitle'), '')] : []).join('<div class="sep"></div>')}</div></div>`;
  function scorecard(vm, o) {
    const f = o.f, vd = vm.verdict, met = vm.sig.filter(x => x.s === 'met').length, known = vm.sig.filter(x => x.s !== 'unknown').length, showRules = !!vm.phase && vm.r.started;
    const today = vm.today, events = o.events || M.EVENTS;
    const weeks = vm.r.weekKeys.filter(w => w >= (vm.r.started ? vm.r.domainStart : vm.r.weekKeys[0]));
    const note = f.events ? M.eventNote(vm.r, events, today) : null;
    const marks = f.events ? M.marked(weeks, events, today).map(b => b ? 1 : 0).join(',') : '';
    const caption = f.events && o.captions ? chartCaption(weeks, events, today) : '';
    const sig = f.intake ? withIntake(vm, o.src || 'appleHealth') : vm.sig;
    return `<div class="sb"></div>${navbar(t('scTitle'), { packet: f.packet, packetIcon: o.packetIcon })}
    ${vm.phase ? `<div class="phase motion"><div class="lab">${vm.phase.lab}</div><div class="nm">${vm.phase.nm}</div><div class="meta">${vm.phase.meta}</div></div>` : ''}
    ${vm.due ? `<div class="wrap mt16"><div class="banner motion"><div><div class="bt">Weigh-in due this week</div><div class="bd">The verdict below is from the ${vd.week}.</div></div><span class="cta">Log weigh-in</span></div></div>` : ''}
    ${vm.reached ? `<div class="wrap mt16"><div class="banner motion"><div><div class="bt">${vm.reached.t}</div><div class="bd">${vm.reached.d}</div></div></div></div>` : ''}
    <div class="wrap mt16"><div class="card verdict">
      <div class="row1"><span class="lab">Verdict${vd.week ? ` · ${vd.week}` : ''}</span><span class="lab">${known ? `${met} of 4 signals met` : ''}</span></div>
      <div class="vt${vd.none ? ' none' : ''}${vd.title.length > 22 ? ' long' : ''}">${vd.title}</div>
      ${vd.lines.map(l => `<div class="rt">${l}</div>`).join('')}
      ${vd.uneval.map(l => `<div class="une">${ruleDot('unknown')}<span>${l}</span></div>`).join('')}
      ${vd.advice ? `<div class="rt t2 own">This is your own rule applied to your own numbers. Nothing has been changed.</div>` : ''}
      ${note && o.noteIn === 'card' ? `<div class="sep" style="margin:14px 0 12px"></div><div class="evnote in">${noteBody(note)}</div>` : ''}
      ${showRules ? `<div class="sep" style="margin:14px 0 6px"></div><div class="lab" style="margin-bottom:2px">Your three rules, in order</div>${ruleRows(vm.rules)}` : ''}
    </div></div>
    ${note && o.noteIn !== 'card' ? noteCard(note) : ''}
    <div class="sec"><h3>Four signals</h3>${vd.week ? `<a>${vd.week}</a>` : ''}</div>
    <div class="wrap"><div class="card" style="padding:14px 18px">${sigRows(sig)}</div></div>
    <div class="foottext" style="padding-top:8px">Compares the heaviest working set of each exercise with the week before.</div>
    <div class="sec"><h3>Weekly curves</h3><a>History${chev}</a></div>
    ${vm.weight ? `<div class="wrap">${curve('Weight', U.w, vm.weight, [[vm.weight.gain ? 'Rate of gain' : 'Rate of loss', vm.weight.rate, `${U.w}/week`], ['Of bodyweight', vm.weight.pct, '%/week']], `<div class="lab" style="margin-top:6px">${vm.weight.note}</div>`, { ax: o.ax, marks, caption })}</div>` : `<div class="wrap">${emptyCurves}</div>`}
    ${vm.waist ? `<div class="wrap mt12">${curve('Waist', U.l, vm.waist, [vm.waist.a, vm.waist.b], '', { ax: o.ax, marks, caption })}</div>` : ''}
    <div class="wrap mt12"><div class="card proj" style="margin-top:0"><div class="lab">${vm.proj.lab}${vm.proj.est ? '<span class="est">Estimate</span>' : ''}</div><div class="t${vm.proj.est ? '' : ' none'}">${vm.proj.text}</div>${vm.proj.sub ? `<div class="lab" style="margin-top:2px">${vm.proj.sub}</div>` : ''}</div></div>
    <div class="wrap mt16"><div class="btn ${vm.due || !vm.weight || vm.r.verdict.reason === 'weighInOverdue' ? 'primary' : 'secondary'}">Log weigh-in</div></div>
    ${linksCard(vm, f)}<div class="home"></div>`;
  }
  const scSkeleton = f => `<div class="sb"></div>${navbar(t('scTitle'), { packet: f.packet })}
    <div class="phase">${skb('110px', 13)}${skb('190px', 30, ';margin-top:8px')}${skb('280px', 13, ';margin-top:10px')}</div>
    <div class="wrap mt16"><div class="card">${skb('150px', 13)}${skb('210px', 34, ';margin-top:12px')}${skb('100%', 14, ';margin-top:18px')}${skb('78%', 14, ';margin-top:8px')}</div></div>
    ${f.events ? `<div class="wrap mt12"><div class="card">${skb('130px', 13)}${skb('180px', 14, ';margin-top:10px')}</div></div>` : ''}
    <div class="sec">${skb('130px', 20)}</div>
    <div class="wrap"><div class="card" style="padding:14px 18px">${[0, 1, 2, 3].map(i => `<div class="sig" style="align-items:center">${skb('24px', 24, ';border-radius:50%;flex:none')}<div class="grow1">${skb([52, 78, 70, 82][i] + '%', 14)}${skb([64, 58, 50, 60][i] + '%', 12, ';margin-top:8px')}</div></div>`).join('<div class="sep"></div>')}</div></div>
    <div class="sec">${skb('150px', 20)}</div>
    <div class="wrap"><div class="card">${skb('60px', 13)}${skb('130px', 40, ';margin-top:10px')}${skb('100%', 120, ';margin-top:16px;border-radius:14px')}</div></div>
    <div class="wrap mt12"><div class="card">${skb('150px', 13)}${skb('230px', 18, ';margin-top:10px')}</div></div><div class="home"></div>`;

  /* ---------- Health tab: the "More health" card (ruling A1) ---------- */
  const lrow = (icon, tint, title, detail) => `<div class="lrow hr"><span class="lic" style="color:var(${tint})" data-ic="${icon}" data-s="20"></span><div class="t grow1">${title}</div>${detail ? `<div class="val">${detail}</div>` : ''}${chev}</div>`;
  const EXISTING = [['heart', '--heart', 'hLive'], ['chart', '--hrv', 'hAll'], ['thermo', '--temp', 'hSkin'], ['spark', '--recovery', 'hVital'], ['chart', '--recovery', 'hContrib'],
    ['refresh', '--breath', 'hSync'], ['book', '--hrv', 'hLab'], ['folder', '--coach', 'hFused']];
  const ICON = { scorecard: 'scale', packet: 'doc', intake: 'fork', bodyRecord: 'flask', events: 'cal', niggle: 'pencil', recovery: 'trend', timeline: 'timeline' };
  /** One stage row: [title, detail]. Each detail is computed from the model for the day; none is typed. */
  function stageRow(id, c) {
    const loading = c.loading ? skb('96px', 13) : null;
    if (id === 'scorecard') { const card = c.vm.card, parts = [card.c, card.v ? `${card.v} ${U.w}` : null].filter(Boolean); return [t('scTitle'), loading || parts.join(' · ')]; }
    if (id === 'packet') return [t('pkTitle'), t('pkDetail')];
    if (id === 'intake') return [t('inTitle'), null];                        // no value and no caption (stage 3 §10.9)
    if (id === 'bodyRecord') { const d = c.empty ? null : M.lastScan(c.today); return [t('brTitle'), loading || (d ? t('brLast', sd(d)) : t('brNone'))]; }
    if (id === 'events') { const n = M.eventsNow(c.events, c.today); return [t('evTitle'), loading || (n ? t('evNow', n) : null)]; }
    if (id === 'niggle') { const n = c.empty ? 0 : M.openNiggles(c.today); return [t('ngTitle'), loading || (n ? t('ngOpen', n) : null)]; }
    if (id === 'recovery') return [t('rcTitle'), null];
    const next = c.empty ? null : M.nextTimelineDay(c.today, c.f, c.vm.r, c.events);
    return [t('tlTitle'), loading || (next ? t('tlNext', sd(next)) : null)];
  }
  /** The rows present, in the one order. recoveryRow: the option that gives Recovery context a Health row; it then
      needs the scorecard on as well, because its screen is unreachable without it (stage 6 §10.7). */
  function healthRows(f, o) {
    return M.present(f).filter(id => id !== 'recovery' || (o.recoveryRow && f.scorecard));
  }
  function healthTab(f, o = {}) {
    const today = o.today || M.TODAY, events = o.empty ? [] : M.EVENTS;
    const vm = FX(o.empty ? { today, without: ALL_WEEKS } : { today });
    const c = { f, today, events, vm, empty: o.empty, loading: o.loading }, night = o.empty ? null : M.lastNight(today);
    const rows = healthRows(f, o).map(id => { const [title, detail] = stageRow(id, c); return lrow(ICON[id], '--t1', title, detail); })
      .concat(EXISTING.map(([ic, tint, key]) => lrow(ic, tint, t(key), null)));
    const vital = (icon, tint, title, v, unit) => o.loading ? skTile : tile(icon, tint, title, v, unit, v == null ? t('prNot') : 'Last night');
    return `<div class="sb"></div><div class="hdr"><div><div class="lt">Health</div><div class="sub">${fd(today).replace(' ', ', ')}</div></div><div class="ibtn" data-ic="person" data-s="22"></div></div>
      <div class="sec"><h3>Vitals</h3><a>All${chev}</a></div>
      <div class="wrap"><div class="ycgrid">${vital('trend', '--hrv', 'HRV', night ? night.hrv : null, 'ms')}${vital('heart', '--heart', 'Resting heart rate', night ? night.rhr : null, 'bpm')}</div></div>
      <div class="sec"><h3>${t('hMore')}</h3></div>
      <div class="wrap"><div class="card flush">${rows.join('')}</div></div>
      <div class="tabbar" data-on="3"></div><div class="home"></div>`;
  }
  const HEALTH_AMB = `data-ambient='[["--heart",350,20,190,0.2],["--hrv",50,0,200,0.2]]'`;

  /* ---------- Settings: eight cards in the one order, each holding its switch (ruling A1) ---------- */
  const cap = (text, cls = '') => `<div class="scap${cls ? ' ' + cls : ''}">${text}</div>`;
  const vrow = (title, v, o = {}) => `<div class="nrow${o.bad ? ' bad' : ''}"><div class="t">${title}</div><div class="val">${v}</div>${o.plain ? '' : chev}</div>`;
  const scard = (icon, title, blurb, rows) => `<div class="wrap mt12"><div class="card scard"><div class="shd"><span data-ic="${icon}" data-s="18"></span><b>${title}</b></div>${blurb ? `<div class="sbl">${blurb}</div>` : ''}${rows.map(r => `<div class="sep"></div>${r}`).join('')}</div></div>`;
  // The compact option: the switch row leads and carries the icon; the sentence sits beneath it. No separate title.
  const ctog = (icon, label, on) => `<div class="nrow"><span class="lic" data-ic="${icon}" data-s="18"></span><div class="t">${label}</div><div class="toggle${on ? ' on' : ''}"></div></div>`;
  const ccard = parts => `<div class="wrap mt12"><div class="card scard c">${parts.join('<div class="sep"></div>')}</div></div>`;
  const deniedBanner = () => `<div class="banner sban"><div><div class="bt">${t('denied')}</div><div class="bd">${t('deniedD')}</div></div><span class="cta">${t('openSettings')}</span></div>`;
  const notif = (title, body, time) => `<div class="notif"><div class="ai" data-ic="today" data-s="22"></div><div class="grow1"><div class="row gap8"><div class="nt">${title}</div><div class="nw">${time}</div></div><div class="nb">${body}</div></div></div>`;
  const REMINDER_TIME = M.hhmm(M.REMINDER.minute), REMINDER_DAY = M.REMINDER.day;
  const CARD = {
    scorecard(on, f, o) {
      const r = o.scReminder || 'off', rows = [tog(t('scSwitch'), on)];
      if (on) { rows.push(tog(t('scReminder'), r === 'on') + (r === 'off' ? cap(t('scRemOff')) : ''));
        if (r === 'on') rows.push(vrow(t('day'), REMINDER_DAY), vrow(t('time'), REMINDER_TIME) + cap(t('scRemOn')), `<div class="scap lead">${t('looks')}</div>${notif(t('n1Title'), t('n1Body'), REMINDER_TIME)}`);
        if (r === 'denied') rows.push(deniedBanner()); }
      return scard(ICON.scorecard, t('scTitle'), t('scBlurb'), rows);
    },
    packet: on => scard(ICON.packet, t('pkTitle'), t('pkBlurb'), [tog(t('pkTitle'), on)]),
    intake(on, f, o) {
      const I = M.INTAKE, s = o.intake || {}, src = s.source || 'health', r = s.reminder || 'off', rows = [tog(t('inTitle'), on)];
      if (on) {
        rows.push(vrow(t('inSource'), t({ none: 'srcNone', health: 'srcHealth', here: 'srcHere' }[src])) + (s.unavailable ? cap(t('pInUnavailable')) : src === 'none' ? cap(t('pInNone')) : ''));
        rows.push(vrow(t('inFloor'), s.badFloor ? `${I.refusedFloorEntry} g` : t('pGrams', floor), { bad: s.badFloor }) + (s.badFloor ? cap(t('inWhole'), 'bad') : ''));
        rows.push(vrow(t('inRange'), t('pRangeValue', s.badRange ? I.rangeHighKcal : I.rangeLowKcal, s.badRange ? I.rangeLowKcal : I.rangeHighKcal), { bad: s.badRange }) + (s.badRange ? cap(t('pInLowHigh'), 'bad') : ''));
        rows.push(vrow(t('inHard'), t('pKcal', I.hardFloorKcal)));
        if (src === 'health') rows.push(vrow(t('inApps'), `${I.foodApp}, ${I.otherApp}`));
        rows.push(vrow(t('inSupp'), I.supplement) + cap(t('inSuppCap')), vrow(t('inAddSupp'), ''), vrow(t('inCutoff'), M.hhmm(I.cutoffMinute)));
        rows.push(tog(t('inReminder'), r === 'on') + (r === 'off' ? cap(t('pInRemOff')) : r === 'on' ? cap(t('pInRemOn')) + (s.nearWindDown ? cap(t('inSilent')) : '') : ''));
        if (r === 'on') rows.push(`<div class="scap lead">${t('looks')}</div>${notif(t('n2Title'), t('n2Body'), M.hhmm(I.cutoffMinute))}`);
        if (r === 'denied') rows.push(deniedBanner());
      }
      return scard(ICON.intake, t('inTitle'), t('pInBlurb'), rows);
    },
    bodyRecord: (on, f, o) => scard(ICON.bodyRecord, t('brTitle'), null, [tog(t('brUnits'), o.labUnits != null ? o.labUnits : on) + cap(t('brUnitsD')), tog(t('brTitle'), on) + cap(t('brD'))]),
    events: (on, f, o) => scard(ICON.events, t('evTitle'), t('pEvBlurb'), [tog(t('evSwitch'), on)].concat(on && f.packet ? [tog(t('evPacket'), !!o.packetPrivate) + cap(t('evPacketD'))] : [])),
    niggle: on => scard(ICON.niggle, t('ngTitle'), t('ngBlurb'), [tog(t('ngTitle'), on)]),
    recovery: (on, f) => scard(ICON.recovery, t('rcTitle'), t('rcBlurb'), [tog(t('rcTitle'), on) + (on && !f.scorecard ? cap(t('pRcNeeds')) : '')]),
    timeline: on => scard(ICON.timeline, t('tlTitle'), t('tlBlurb'), [tog(t('tlTitle'), on)]),
  };
  const COMPACT = {
    scorecard: on => ccard([ctog(ICON.scorecard, t('scSwitch'), on) + cap(t('scBlurb'))]),
    packet: on => ccard([ctog(ICON.packet, t('pkTitle'), on) + cap(t('pkBlurb'))]),
    intake: on => ccard([ctog(ICON.intake, t('inTitle'), on) + cap(t('pInBlurb'))]),
    bodyRecord: on => ccard([ctog(ICON.bodyRecord, t('brUnits'), on) + cap(t('brUnitsD')), ctog(ICON.bodyRecord, t('brTitle'), on) + cap(t('brD'))]),
    events: on => ccard([ctog(ICON.events, t('evSwitch'), on) + cap(t('pEvBlurb'))]),
    niggle: on => ccard([ctog(ICON.niggle, t('ngTitle'), on) + cap(t('ngBlurb'))]),
    recovery: on => ccard([ctog(ICON.recovery, t('rcTitle'), on) + cap(t('rcBlurb'))]),
    timeline: on => ccard([ctog(ICON.timeline, t('tlTitle'), on) + cap(t('tlBlurb'))]),
  };
  /** o.only: draw just these cards (state frames). o.compact: the compact option. */
  const settings = (f, o = {}) => `<div class="sb"></div>${navbar('Settings', { plus: 0 })}
    ${M.IDS.filter(id => !o.only || o.only.includes(id)).map(id => (o.compact ? COMPACT : CARD)[id](f[id], f, o)).join('')}<div class="home"></div>`;

  /* ---------- Today: Your cards (stage 1 §10.1, stage 3 §10.1) ---------- */
  function ring(p, o = {}) {                                  // p: 0…1, or null for no ring. Drawn as a path, so the export needs no rewrite.
    if (p == null) return '';
    const z = o.z || 34, r = z / 2 - 3.5, cx = z / 2, a = Math.min(p, .9999) * 2 * Math.PI, x = (cx + r * Math.sin(a)).toFixed(2), y = (cx - r * Math.cos(a)).toFixed(2);
    return `<svg class="pring" width="${z}" height="${z}" viewBox="0 0 ${z} ${z}"><circle cx="${cx}" cy="${cx}" r="${r}" fill="none" stroke="#FFFFFF" stroke-opacity=".1" stroke-width="4"/>${p > 0 ? `<path d="M${cx},${(cx - r).toFixed(2)} A${r},${r} 0 ${a > Math.PI ? 1 : 0} 1 ${x},${y}" fill="none" stroke="${o.dim ? '#8A8A93' : '#F5F5F7'}" stroke-width="4" stroke-linecap="round"/>` : ''}</svg>`;
  }
  const proteinTile = (s, o = {}) => `<div class="yc motion"><div class="hd" style="color:var(--t1)"><span data-ic="fork" data-s="16"></span><b>${t('prTitle')}</b>${o.nolink ? '' : chev}</div><div class="pv"><div class="v num${s.v == null ? ' none' : s.dim ? ' tert' : ''}">${s.v == null ? '—' : s.v}${s.v != null ? '<small>g</small>' : ''}</div>${ring(s.ring, { dim: s.dim })}</div><div class="c">${s.c}</div></div>`;
  /** A card state from grams, the floor and where the figure came from. Wording per stage 3 §10.1 and §11. */
  function proteinCard(grams, o = {}) {
    const p = M.proteinProgress(grams, o.noFloor ? null : floor), stale = !!o.stale, at = o.imported ? t('prImported') : M.hhmm(M.readAt(stale)), tail = ` · ${at}`;
    if (p.state === 'notMeasured') return { v: null, ring: o.noFloor ? null : 0, c: t('prNothing') };
    if (stale && M.isStale(M.readAt(true))) return { v: p.shown, ring: p.ring, dim: 1, c: t('prLast', at) };
    if (p.state === 'noFloor') return { v: p.shown, ring: null, c: t('prNoFloor') };
    return { v: p.shown, ring: p.ring, c: (p.state === 'below' ? t('prTo', p.remaining) : p.state === 'atFloor' ? t('prMet') : t('prOver', p.over)) + tail };
  }
  const G_ = M.INTAKE.todayGrams;
  const proteinStates = () => [
    ['Loading', skTile], ['No source chosen', proteinTile({ v: null, ring: null, c: t('prChoose') })], ['No floor set', proteinTile(proteinCard(G_.below, { noFloor: 1 }))],
    ['Not measured today', proteinTile(proteinCard(G_.notMeasured))], ['Below the floor', proteinTile(proteinCard(G_.below))], ['At the floor', proteinTile(proteinCard(G_.atFloor))],
    ['Above the floor', proteinTile(proteinCard(G_.above))], ['Stale: read more than three hours ago', proteinTile(proteinCard(G_.below, { stale: 1 }))],
    ['Health read failed, nothing stored', proteinTile({ v: null, ring: null, c: t('prFail') })], ['A CSV value: no time', proteinTile(proteinCard(G_.below, { imported: 1 }))],
    ['A past day, measured', proteinTile({ ...proteinCard(M.INTAKE.pastDayGrams), c: t('prDay') })], ['A past day, not measured', proteinTile({ v: null, ring: null, c: t('prNot') })],
    ['Targets unreadable', proteinTile({ v: M.proteinProgress(G_.below, null).shown, ring: null, c: t('inAttention') })],
  ];
  const noLiftsLate = { today: '2031-02-19', noLifts: true, phase: { ...FIXTURE_PHASE, startDay: '2031-02-03' } };
  const scStates = () => [['Loading', skTile], ['No cut phase', scTile(FX({ today: '2031-01-29', phase: null }).card)], ['No readings', scTile(FX({ today: '2031-01-08', without: ALL_WEEKS }).card)],
    ['One reading', scTile(P.wk(1).card)], ['Fewer readings than the rules need', scTile(FX(noLiftsLate).card)], ['Weigh-in due this week', scTile(FX({ today: '2031-03-12' }).card)],
    ['Overdue', scTile(FX({ today: '2031-03-19', without: [11] }).card)], ['Lifts unknown, verdict withheld', scTile(P.wk(15).card)], ['Target reached', scTile(P.wk(21).card)], ['Weight rising', scTile(P.wk(20).card)],
    ['Your rule: add', scTile(P.wk(19).card)], ['A past day selected', tile('scale', '--t1', t('scTitle'), null, '', 'Shown for today only', { nolink: 1 })]];
  const stateSheet = (title, states) => `<div class="sb"></div><div class="navbar"><div style="width:40px"></div><div class="ttl anno">${title}</div><div style="width:40px"></div></div>
    <div class="wrap"><div class="ycgrid" style="row-gap:6px">${states.map(([l, tl]) => anno(l, tl)).join('')}</div></div><div class="home"></div>`;
  function todayCards(f, o = {}) {
    const today = o.today || M.TODAY, vm = FX({ today }), night = M.lastNight(today);
    if (o.loading) return [f.scorecard, f.intake, 1, 1].filter(Boolean).map(() => skTile).join('');
    return (f.scorecard && o.added !== 0 ? scTile(vm.card) : '') + (f.intake && o.added !== 0 ? proteinTile(proteinCard(G_.below)) : '')
      + tile('scale', '--t1', 'Weight', vm.weight ? vm.weight.cur : null, U.w, t('labBook')) + tile('heart', '--heart', 'Resting heart rate', night ? night.rhr : null, 'bpm', night ? 'Last night' : t('prNot'));
  }
  const todayFrame = (f, o = {}) => `<div class="sb"></div><div class="hdr"><div><div class="lt">Today</div><div class="sub">${fd(o.today || M.TODAY).replace(' ', ', ')}</div></div><div class="ibtn" data-ic="person" data-s="22"></div></div>
    <div class="sec"><h3>${t('yourCards')}</h3><a>Edit${chev}</a></div>
    <div class="wrap"><div class="ycgrid">${todayCards(f, o)}</div></div>
    <div class="tabbar" data-on="0"></div><div class="home"></div>`;
  const er = P.er;
  const customize = f => `<div class="sb"></div><div class="navbar"><div class="lnk" style="margin:0;font-weight:500">Cancel</div><div class="ttl">${t('yourCards')}</div><div class="lnk" style="margin:0">Save</div></div>
    ${gh('Shown', 1)}${P.grp([er('rem', 'Weight'), er('rem', 'Resting heart rate'), er('rem', 'Stress'), er('rem', 'Fitness age')])}
    ${gh('More cards')}${P.grp((f.scorecard ? [er('add', t('scTitle'), t('pScCardSub'))] : []).concat(f.intake ? [er('add', t('prTitle'), t('prSub'))] : [], [er('add', 'Coupled view'), er('add', 'Coach'), er('add', 'Hydration')]))}<div class="home"></div>`;

  /* ---------- notifications: every one the workstream can send, written out ---------- */
  const notifications = () => `<div class="sb"></div><div class="navbar"><div style="width:40px"></div><div class="ttl anno">Notifications, written out</div><div style="width:40px"></div></div>
    ${annoRow('Stage 1 · weekly weigh-in reminder · off by default · one a week')}<div class="wrap">${notif(t('n1Title'), t('n1Body'), REMINDER_TIME)}</div>
    ${annoRow('Stage 3 · food cutoff reminder · off by default · one a day at most')}<div class="wrap">${notif(t('n2Title'), t('n2Body'), M.hhmm(M.INTAKE.cutoffMinute))}</div>
    ${annoRow('Stages 2, 4, 5 and 6 send no notification. No stage adds a notification to the scorecard, the packet, the body record, events, the niggle log, recovery context or the timeline.')}<div class="home"></div>`;

  /* ---------- frames ---------- */
  const G = []; let cur;
  const group = (title, note) => { cur = { title, note, frames: [] }; G.push(cur); };
  const frame = (name, html, o = {}) => cur.frames.push({ name, html, ...o });
  const STILL = { attrs: 'data-nomotion' };
  const { ALL_ON, ALL_OFF, SOME_ON, flags } = M;
  const scFrame = (name, o, note) => { const vm = FX({ today: o.today || M.TODAY, ...(o.fx || {}) }); frame(name, scorecard(vm, o), { attrs: AMB(vm), cls: o.ax ? 'ax' : '', note }); };

  group('H · Health tab: the "More health" card', 'The card under the Health tab\'s "More" header. The stage rows lead the card in the one order (ruling A1), each present only while its own switch is on; the rows the card already had follow, unchanged. A stage row is neutral: the palette has no colour for these, and none is invented. A detail is a fact for the day (a count, a date, the scorecard card\'s caption and weight), never a judgement.');
  frame('H1 Health · every switch on', healthTab(ALL_ON, { recoveryRow: 1 }), { attrs: HEALTH_AMB, note: 'Wed 5 Feb 2031, fixture week 5. Eight rows in the order of ruling A1. The Recovery context row is the open point: see H2.' });
  frame('H2 Health · every switch on, Recovery context reached from the scorecard only (option)', healthTab(ALL_ON), { attrs: HEALTH_AMB, note: 'Stage 6 §10.1 as written: seven rows; Recovery context has no Health row and opens from the scorecard\'s links.' });
  frame('H3 Health · some switches on', healthTab(SOME_ON, { recoveryRow: 1 }), { attrs: HEALTH_AMB, note: 'Coach packet, Events, Recovery context and Timeline on; the scorecard off. Coach packet is then the first stage row. Recovery context has no row even in option H1, because its screen opens from the scorecard.' });
  frame('H4 Health · one switch on', healthTab(flags('intake')), { attrs: HEALTH_AMB, note: 'Intake alone. Its row carries no value and no caption.' });
  frame('H5 Health · every switch off', healthTab(ALL_OFF), { attrs: HEALTH_AMB, note: 'The card exactly as it is today.' });
  frame('H6 Health · every switch on, nothing recorded yet', healthTab(ALL_ON, { recoveryRow: 1, empty: 1, today: '2031-01-06' }), { note: 'First use, Mon 6 Jan 2031: no weigh-in, scan, event, complaint, checkpoint or recorded night. A row with nothing to report shows no detail; nothing reads 0.' });
  frame('H7 Health · loading', healthTab(ALL_ON, { recoveryRow: 1, loading: 1 }), STILL);
  frame('H8 Health · AX5', healthTab(ALL_ON, { recoveryRow: 1 }), { cls: 'ax', attrs: HEALTH_AMB });

  group('S · Settings: the eight cards', 'Top to bottom in the one order (ruling A1). Each card is always drawn on iPhone because it holds its own switch; every switch is off by default. A card is the shipped scorecard card\'s shape: title, one sentence, the switch, then that stage\'s rows while it is on.');
  frame('S1 Settings · every switch off', settings(ALL_OFF), STILL);
  frame('S2 Settings · every switch on', settings(ALL_ON), { attrs: 'data-nomotion', note: 'Both reminders are still off: each is its own opt-in. Intake reads Apple Health.' });
  frame('S3 Settings · some switches on', settings(SOME_ON), { attrs: 'data-nomotion', note: 'Coach packet, Events, Recovery context and Timeline on. The second Events switch shows because the packet is on too.' });
  frame('S4 Settings · compact cards (option)', settings(ALL_OFF, { compact: 1 }), { attrs: 'data-nomotion', note: 'The same eight cards and order, denser: the switch row leads each card and the sentence sits under it.' });
  frame('S5 Settings · Scorecard card, weekly reminder on', settings(ALL_ON, { only: ['scorecard'], scReminder: 'on' }), STILL);
  frame('S6 Settings · Intake card, source None', settings(ALL_ON, { only: ['intake'], intake: { source: 'none' } }), STILL);
  frame('S7 Settings · Intake card, cutoff reminder on', settings(ALL_ON, { only: ['intake'], intake: { reminder: 'on', nearWindDown: 1 } }), { attrs: 'data-nomotion', note: `The wind-down reminder is at ${M.hhmm(M.INTAKE.windDownMinute)} in this frame, within 30 minutes of the ${M.hhmm(M.INTAKE.cutoffMinute)} cutoff (stage 3 §13.5).` });
  frame('S8 Settings · Intake card, Apple Health not available', settings(ALL_ON, { only: ['intake'], intake: { source: 'none', unavailable: 1 } }), STILL);
  frame('S9 Settings · Intake card, values that cannot be saved', settings(ALL_ON, { only: ['intake'], intake: { source: 'here', badFloor: 1, badRange: 1 } }), { attrs: 'data-nomotion', note: 'Source "Enter here". A floor that is not whole grams, and a range typed with its ends the wrong way round. Nothing is saved.' });
  frame('S10 Settings · notifications denied', settings(ALL_ON, { only: ['scorecard', 'intake'], scReminder: 'denied', intake: { reminder: 'denied' } }), STILL);
  frame('S11 Settings · AX5', settings(ALL_OFF), { cls: 'ax', attrs: 'data-nomotion' });

  group('B · Scorecard screen with every stage\'s addition', 'Round 6\'s approved screen, with nothing of stage 1 moved. Added: the Coach packet button in the toolbar (stage 2); a source caption on the protein row, which opens Intake (stage 3); the event note directly under the verdict and a quiet dot on the time axis of both curves (stage 5); the Recovery context and Timeline links (stage 6). The verdict, rules, signals, rate and projection are computed before and without the events.');
  scFrame('B1 Scorecard · every switch on', { f: ALL_ON }, 'Wed 5 Feb 2031, fixture week 5. A deload (E2) covers the judged week; a supplement change (E4) is earlier in the evidence window.');
  scFrame('B2 Scorecard · only the scorecard on', { f: flags('scorecard') }, 'The same day. Field for field the screen round 6 approved.');
  scFrame('B3 Scorecard · some switches on', { f: flags('scorecard', 'packet', 'events') }, 'Coach packet and Events on; Intake, Recovery context and Timeline off.');
  scFrame('B4 Scorecard · events only earlier in the evidence window', { f: ALL_ON, today: weighDay(4) }, 'Fixture week 4, Wed 29 Jan: nothing overlaps the judged week; the supplement change of 22 Jan is behind it.');
  scFrame('B5 Scorecard · an event in a week with no weigh-in', { f: ALL_ON, today: weighDay(11) }, 'Fixture week 11, Wed 19 Mar. Week 10 has no weigh-in: the curves break, the ring sits on the axis and the dot beneath it says an event covered that week. The note names it.');
  scFrame('B6 Scorecard · a private event', { f: ALL_ON, today: weighDay(12) }, 'Fixture week 12, Wed 26 Mar. E6 is private: its line reads "Private event" with the date, never its label or note.');
  scFrame('B7 Scorecard · an ongoing private event', { f: ALL_ON, today: weighDay(20) }, 'Fixture week 20, Wed 21 May. E5 is ongoing and private.');
  scFrame('B8 Scorecard · more than three events in a list', { f: ALL_ON, today: weighDay(11), events: M.EVENTS.concat(M.EXTRA_EVENTS) }, 'Fixture week 11 with three one-day travel events added for this frame only (3, 5 and 7 Mar; they are in no specification\'s fixture).');
  scFrame('B9 Scorecard · every switch on, no readings', { f: ALL_ON, today: '2031-01-08', fx: { without: ALL_WEEKS } }, 'No judged week: no event note and no marks. The protein row has no source to name.');
  scFrame('B10 Scorecard · events on, none stored', { f: ALL_ON, events: [] }, 'The same day as B1 with no event stored (stage 5 variant V1): no note, no mark and no height taken. Everything else is B1.');
  scFrame('B11 Scorecard · weigh-in due while an event is running', { f: ALL_ON, today: '2031-03-12' }, 'Wed 12 Mar, before this week\'s weigh-in. The verdict is week 9\'s. The trip (E1) covers the current week, which is marked on the axis; the note lists what lies in the judged week and behind it.');
  frame('B12 Scorecard · protein row, every source caption', (() => { const base = FX({ today: M.TODAY }); const one = (l, sig) => `${annoRow(l)}<div class="wrap"><div class="card" style="padding:14px 18px">${sigRows([sig[2]])}</div></div>`;
    return `<div class="sb"></div>${navbar(t('scTitle'), { packet: 1 })}${one('Intake off: stage 1\'s row, unchanged', base.sig)}${['appleHealth', 'quickAdd', 'csv', 'several'].map(k => one(`Intake on · ${t(CAP[k])}`, withIntake(base, k))).join('')}
      ${one('Intake on · no protein data: nothing to name', withIntake(FX({ today: weighDay(9) }), 'appleHealth'))}${one('Intake on · no floor set', withIntake(FX({ today: M.TODAY, params: { ...FIXTURE_PARAMS, proteinFloorGrams: null } }), 'appleHealth'))}<div class="home"></div>`; })(), STILL);
  frame('B13 Scorecard · links card, each combination', (() => { const vm = FX({ today: M.TODAY });
    return `<div class="sb"></div>${navbar(t('scTitle'))}${[['Recovery context and Timeline off', flags()], ['Recovery context on', flags('recovery')], ['Timeline on', flags('timeline')], ['Both on', flags('recovery', 'timeline')]].map(([l, f]) => `${annoRow(l)}${linksCard(vm, f).replace('mt16', '')}`).join('')}<div class="home"></div>`; })(), STILL);
  frame('B14 Scorecard · loading', scSkeleton(ALL_ON), STILL);
  scFrame('B15 Scorecard · AX5', { f: ALL_ON, ax: 1 });
  scFrame('B16 Scorecard · event note inside the verdict card (option)', { f: ALL_ON, noteIn: 'card' }, 'The same day as B1. The note sits inside the verdict card, above the rules, in place of its own card.');
  scFrame('B17 Scorecard · event captions under the curves as well (option)', { f: ALL_ON, captions: 1 }, 'Stage 5 §10.5 as written: each curve also carries the chart caption. B1 leaves it out because the note already names the events.');
  frame('B18 Scorecard · toolbar, packet button options', `<div class="sb"></div>${annoRow('A · document icon, left of the weigh-in button (as B1)')}${navbar(t('scTitle'), { packet: 1 })}${annoRow('B · clipboard icon')}${navbar(t('scTitle'), { packet: 1, packetIcon: 'paste' })}${annoRow('C · share icon')}${navbar(t('scTitle'), { packet: 1, packetIcon: 'upload' })}${annoRow('Coach packet off: the toolbar round 6 approved')}${navbar(t('scTitle'))}<div class="home"></div>`, STILL);

  group('T · Today: Your cards', 'The Scorecard and Protein cards are value cards outside the default selection; each renders only while its own switch is on and only once the owner adds it. The frames show the Your cards section alone: the Fixture Person has no Sleep, Recovery or Strain score for this day, so no ring and no score glow is drawn. Weight is the one resolved value on both the Scorecard and Weight tiles.');
  frame('T1 Today · Scorecard and Protein cards', todayFrame(ALL_ON), { note: `Wed 5 Feb 2031, 09:41. Protein was read ten minutes earlier (stage 3 §13.6).` });
  frame('T2 Today · Protein card, every state', stateSheet('Protein card states', proteinStates()), STILL);
  frame('T3 Today · Scorecard card, every state', stateSheet('Scorecard card states', scStates()), STILL);
  frame('T4 Today · only the scorecard on', todayFrame(flags('scorecard')));
  frame('T5 Today · only Intake on', todayFrame(flags('intake')));
  frame('T6 Today · every switch off', todayFrame(ALL_OFF), { note: 'Neither card renders, whatever the owner added earlier.' });
  frame('T7 Today · adding the cards', customize(ALL_ON), { attrs: 'data-nomotion', note: 'Both cards wait under "More cards". The editor hides each while its switch is off.' });
  frame('T8 Today · loading', todayFrame(ALL_ON, { loading: 1 }), STILL);
  frame('T9 Today · AX5', todayFrame(ALL_ON), { cls: 'ax' });

  group('N · Notifications', 'Two notifications exist across all six stages, both opt-in. Neither carries a measurement, a verdict, a phase name, an amount, a floor or a supplement name.');
  frame('N1 Notifications · every notification, written out', notifications(), STILL);

  const PREFIX = 'SC / ';
  const frames = G.flatMap(g => g.frames.map(f => ({ ...f, title: PREFIX + f.name, group: g.title })));
  const api = { G, frames, PREFIX, STR, used, weekChartSpec, t };
  if (NODE) module.exports = api; else root.SCF = api;
})(typeof window !== 'undefined' ? window : globalThis);
