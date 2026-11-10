/* Round 6 · Cut scorecard (Stage 1). Builds every frame from the fixture below, then boots noop.js.
   EVERY VALUE IS SYNTHETIC. "Fixture Person" is fictional: 88.5 kg on Fri 4 Sep 2026, target 80.0 kg,
   losing about half a kilogram a week. The rule values (0.4–0.8 kg/week band, 150 g protein floor,
   two-week windows) are placeholders for the picture, not the owner's parameters. */

/* ---------- local icons (noop.js ICONS is not edited; ic('tape') resolves #i-tape) ---------- */
document.body.insertAdjacentHTML('afterbegin', `<svg width="0" height="0" style="position:absolute"><defs>
<symbol id="i-tape" viewBox="0 0 24 24"><circle cx="9" cy="10" r="5.5" fill="none" stroke="currentColor" stroke-width="1.9"/><circle cx="9" cy="10" r="1.5" fill="currentColor"/><path d="M9 15.5h11.5V19H15" fill="none" stroke="currentColor" stroke-width="1.9" stroke-linecap="round" stroke-linejoin="round"/></symbol>
<symbol id="i-cal" viewBox="0 0 24 24"><rect x="4" y="5.5" width="16" height="15" rx="3.5" fill="none" stroke="currentColor" stroke-width="1.9"/><path d="M4 10.5h16M8.5 3.5v4M15.5 3.5v4" fill="none" stroke="currentColor" stroke-width="1.9" stroke-linecap="round"/></symbol>
<symbol id="i-trash" viewBox="0 0 24 24"><path d="M5 7h14M10 4h4M7 7l1 12.5h8L17 7M10.5 11v5M13.5 11v5" fill="none" stroke="currentColor" stroke-width="1.9" stroke-linecap="round" stroke-linejoin="round"/></symbol>
<symbol id="i-pencil" viewBox="0 0 24 24"><path d="M5 19l1-4L16.5 4.5l3 3L9 18zM14.5 6.5l3 3" fill="none" stroke="currentColor" stroke-width="1.9" stroke-linecap="round" stroke-linejoin="round"/></symbol>
</defs></svg>`);

/* ---------- signal states: met / not met / unknown. Shape and word carry the state; colour repeats it. ---------- */
const ST = { met: { c: '--sig-met', w: 'Met' }, not: { c: '--sig-not', w: 'Not met' }, unk: { c: '--sig-unk', w: 'Unknown' } };
function glyph(s, z = 24) {
  const c = C(ST[s].c);
  if (s === 'unk') return `<svg width="${z}" height="${z}" viewBox="0 0 24 24"><circle cx="12" cy="12" r="9.6" fill="none" stroke="#FFFFFF" stroke-opacity=".34" stroke-width="1.7" stroke-dasharray="3 3.3"/></svg>`;
  const mark = s === 'met' ? '<polyline points="7.4,12.4 10.6,15.6 16.8,8.9"' : '<path d="M8.2 8.2l7.6 7.6M15.8 8.2l-7.6 7.6"';
  return `<svg width="${z}" height="${z}" viewBox="0 0 24 24"><circle cx="12" cy="12" r="11" fill="${c}" fill-opacity=".18"/>${mark} fill="none" stroke="${c}" stroke-width="2.2" stroke-linecap="round" stroke-linejoin="round"/></svg>`;
}

/* ---------- weekly chart: smooth line, gradient area, one point per weekly reading. No rules, bands or target lines.
   <svg class="wk" data-v="88.5,88,x,87" (x = week with no reading) data-ext="8" (empty future weeks)
        data-l0 data-l1 (first / last date) data-mark="17|1 Jan · 80.0 kg" (quiet tick on the time axis)> ---------- */
function weekChart(svg) {
  const d = svg.dataset, v = d.v.split(',').map(x => x === 'x' ? null : +x), c = C(d.c || '--t1');
  const fs = +(d.fs || 11), w = +svg.getAttribute('width'), H = +svg.getAttribute('height'), h = H - fs - 11, n = v.length, ext = +(d.ext || 0);
  const real = v.filter(x => x !== null); let mn = Math.min(...real), mx = Math.max(...real); const span = (mx - mn) || 1; mn -= span * .14; mx += span * .14;
  const X = i => +(8 + i * (w - 16) / Math.max(1, n - 1 + ext)).toFixed(2), Y = x => +(12 + (1 - (x - mn) / (mx - mn)) * (h - 20)).toFixed(2);
  const pts = []; v.forEach((x, i) => { if (x !== null) pts.push([X(i), Y(x)]); });
  const id = 'wk' + (gid++), df = el('defs', {}, svg);
  const ga = el('linearGradient', { id: 'a' + id, x1: 0, y1: 0, x2: 0, y2: 1 }, df); el('stop', { offset: 0, 'stop-color': c, 'stop-opacity': .30 }, ga); el('stop', { offset: 1, 'stop-color': c, 'stop-opacity': 0 }, ga);
  const gs = el('linearGradient', { id: 's' + id, x1: 0, y1: 0, x2: 1, y2: 0 }, df); el('stop', { offset: 0, 'stop-color': c, 'stop-opacity': .35 }, gs); el('stop', { offset: 1, 'stop-color': c, 'stop-opacity': 1 }, gs);
  if (pts.length > 1) {
    const line = smooth(pts), a = pts[0], b = pts[pts.length - 1];
    el('path', { class: 'area', d: `${line} L${b[0]},${h} L${a[0]},${h} Z`, fill: `url(#a${id})` }, svg);
    el('path', { class: 'stroke', d: line, fill: 'none', stroke: `url(#s${id})`, 'stroke-width': 2.5, 'stroke-linecap': 'round', 'stroke-linejoin': 'round' }, svg);
  }
  pts.forEach((p, i) => {
    const last = i === pts.length - 1;
    if (last) el('circle', { class: 'halo', cx: p[0], cy: p[1], r: 8, fill: c, opacity: .22 }, svg);
    el('circle', { class: 'pt', cx: p[0], cy: p[1], r: last ? 4 : 2.6, fill: c, stroke: '#0B0B0D', 'stroke-width': last ? 1.5 : 1.2 }, svg);
  });
  // A week with no reading: an open ring on the time axis. Nothing is drawn on the curve for it.
  v.forEach((x, i) => { if (x === null) el('circle', { cx: X(i), cy: h + 3, r: 2.6, fill: 'none', stroke: '#FFFFFF', 'stroke-opacity': .4, 'stroke-width': 1.2 }, svg); });
  const text = (x, s, anchor) => { const t = el('text', { x, y: H - 3, 'text-anchor': anchor, fill: '#9B9BA3', 'font-size': fs, 'font-weight': 500, 'font-family': '-apple-system,system-ui' }, svg); t.textContent = s; };
  const lastIdx = v.reduce((k, x, i) => x !== null ? i : k, 0);
  if (d.l0) text(X(0) - 4, d.l0, 'start');
  if (d.l1 && n > 1) text(X(lastIdx) + (ext ? 0 : 4), d.l1, ext ? 'middle' : 'end');
  if (d.mark) { const [i, s] = d.mark.split('|'); const x = X(+i);
    el('line', { x1: x, x2: x, y1: h - 3, y2: h + 6, stroke: '#FFFFFF', 'stroke-opacity': .55, 'stroke-width': 1.5, 'stroke-linecap': 'round' }, svg); text(x + 4, s, 'end'); }
}

/* ---------- fixture ---------- */
const W = [88.5, 88.0, 87.6, 87.0, 86.4, 86.0, 85.4, 85.0, 84.6, 84.0];      // Fridays, 4 Sep – 6 Nov 2026
const WA = [96.0, 95.5, 95.0, 95.0, 94.5, 94.0, 93.5, 93.0, 92.5, 92.0];
const K = ['Waist shrinking', 'Working weights holding or climbing', 'Protein floor hit on most days', 'Rate of loss inside the expected band'];
const SHORT = ['Waist', 'Lifts', 'Protein', 'Rate'];
const sigs = (...rows) => rows.map(([s, n], i) => ({ k: K[i], s, n }));
const PH = { lab: 'Phase · week 10', nm: 'Autumn cut', meta: 'Target 80.0 kg · started Fri 4 Sep · expected 0.4–0.8 kg/week' };

const S = {
  def: {
    phase: PH, wk: 'week of 2 Nov',
    vt: 'Hold steady', rule: 'Loss of 0.50 kg/week is inside your 0.4–0.8 band and working weights are holding. No change this week.',
    sig: sigs(['met', '−1.0 cm in 2 weeks · 93.0 → 92.0 cm'], ['met', '4 of 4 tracked lifts held or rose in 2 weeks · 6 imported sessions'], ['met', '6 of 7 days at or above 150 g · logged intake'], ['met', '−0.50 kg/week · band 0.4–0.8 kg/week']),
    weight: { cur: '84.0', src: 'Weighed Fri 6 Nov · manual', v: W.join(','), ext: 8, l0: '4 Sep', l1: '6 Nov', mark: '17|1 Jan · 80.0 kg', rate: '−0.50', pct: '−0.60', win: 'Last 4 weeks · 86.0 → 84.0 kg', proj: 'On this trend: 80.0 kg around Fri 1 Jan' },
    waist: { cur: '92.0', src: 'Measured Fri 6 Nov · manual', v: WA.join(','), l0: '4 Sep', l1: '6 Nov', a: ['2-week change', '−1.0', 'cm'], b: ['Since phase start', '−4.0', 'cm'] },
  },
};
S.liftunk = { ...S.def, tag: '1 rule not evaluated',
  rule: 'Loss of 0.50 kg/week is inside your 0.4–0.8 band.',
  noeval: 'The working-weights rule. No lift sessions are imported for 24 Oct – 6 Nov, so the app cannot tell whether working weights held or fell.', link: 'Import lift sessions',
  sig: sigs(['met', '−1.0 cm in 2 weeks · 93.0 → 92.0 cm'], ['unk', 'No lift sessions imported for 24 Oct – 6 Nov'], ['met', '6 of 7 days at or above 150 g · logged intake'], ['met', '−0.50 kg/week · band 0.4–0.8 kg/week']) };
S.missed = { ...S.def,
  rule: 'Loss of 0.50 kg/week is inside your 0.4–0.8 band and working weights are holding. No change this week.',
  extra: 'The week of 26 Oct has no weigh-in. The rate is measured across it.',
  sig: sigs(['met', '−1.0 cm since Fri 23 Oct · 93.0 → 92.0 cm · 1 week without a reading'], ['met', '4 of 4 tracked lifts held or rose in 2 weeks · 6 imported sessions'], ['met', '6 of 7 days at or above 150 g · logged intake'], ['met', '−0.50 kg/week · band 0.4–0.8 kg/week · 4 of 5 weekly readings']),
  weight: { ...S.def.weight, v: '88.5,88,87.6,87,86.4,86,85.4,85,x,84', win: 'Last 4 weeks · 86.0 → 84.0 kg · 1 week without a reading' },
  waist: { ...S.def.waist, v: '96,95.5,95,95,94.5,94,93.5,93,x,92', a: ['Since Fri 23 Oct', '−1.0', 'cm'] } };
S.one = { phase: { ...PH, lab: 'Phase · week 1' }, wk: 'week of 31 Aug',
  vt: 'Not enough data', none: 1, rule: null, need: 'The rules compare one week with the next. 2 more weekly weigh-ins are needed before they can run.',
  sig: sigs(['unk', '1 reading · needs 3 weekly readings'], ['met', '3 of 3 tracked lifts held or rose in 2 weeks · 4 imported sessions'], ['unk', 'No intake source connected'], ['unk', '1 reading · needs 3 weekly readings']),
  weight: { cur: '88.5', src: 'Weighed Fri 4 Sep · manual', v: '88.5', l0: '4 Sep', rate: null, rateNote: 'Not measured yet. A rate needs 2 weigh-ins a week apart.', noproj: 'No projection: one reading is not a trend' },
  waist: { cur: '96.0', src: 'Measured Fri 4 Sep · manual', v: '96', l0: '4 Sep', a: ['2-week change', null], b: ['Since phase start', null] } };
S.few = { phase: { ...PH, lab: 'Phase · week 2' }, wk: 'week of 7 Sep',
  vt: 'Not enough data', none: 1, rule: null, need: 'The rules look at two weekly changes in a row. 1 more weekly weigh-in is needed.',
  sig: sigs(['unk', '−0.5 cm in 1 week · the signal needs 2 weeks'], ['met', '3 of 3 tracked lifts held or rose in 2 weeks · 4 imported sessions'], ['unk', 'No intake source connected'], ['unk', '−0.50 kg in 1 week · the signal needs 2 weeks']),
  weight: { cur: '88.0', src: 'Weighed Fri 11 Sep · manual', v: '88.5,88', l0: '4 Sep', l1: '11 Sep', rate: '−0.50', pct: '−0.57', win: '1 week only · 88.5 → 88.0 kg', noproj: 'No projection yet: needs 3 weekly weigh-ins' },
  waist: { cur: '95.5', src: 'Measured Fri 11 Sep · manual', v: '96,95.5', l0: '4 Sep', l1: '11 Sep', a: ['2-week change', null], b: ['Since phase start', '−0.5', 'cm'] } };
S.target = { phase: { ...PH, lab: 'Phase · week 18' }, wk: 'week of 28 Dec',
  banner: { t: 'Target reached', d: '79.9 kg on Fri 1 Jan. The rules keep running until you end this phase or set the next one.', cta: 'Phase' },
  vt: 'Hold steady', rule: 'Loss of 0.50 kg/week is inside your 0.4–0.8 band and working weights are holding. No change this week.',
  sig: sigs(['met', '−1.0 cm in 2 weeks · 89.5 → 88.5 cm'], ['met', '4 of 4 tracked lifts held or rose in 2 weeks · 5 imported sessions'], ['met', '5 of 7 days at or above 150 g · logged intake'], ['met', '−0.50 kg/week · band 0.4–0.8 kg/week']),
  weight: { cur: '79.9', src: 'Weighed Fri 1 Jan · manual', v: W.concat([83.5, 83.0, 82.5, 81.9, 81.4, 80.9, 80.4, 79.9]).join(','), l0: '4 Sep', l1: '1 Jan', rate: '−0.50', pct: '−0.63', win: 'Last 4 weeks · 81.9 → 79.9 kg', noproj: 'No projection: the target is reached' },
  waist: { cur: '88.5', src: 'Measured Fri 1 Jan · manual', v: WA.concat([91.5, 91.0, 90.5, 90.5, 90.0, 89.5, 89.0, 88.5]).join(','), l0: '4 Sep', l1: '1 Jan', a: ['2-week change', '−1.0', 'cm'], b: ['Since phase start', '−7.5', 'cm'] } };
S.rising = { phase: { ...PH, lab: 'Phase · week 12' }, wk: 'week of 16 Nov',
  vt: 'Reduce carbohydrate', rule: 'Loss has been under 0.4 kg/week for 2 weeks in a row and waist is not shrinking.',
  sig: sigs(['not', '+0.5 cm in 2 weeks · 93.5 → 94.0 cm'], ['met', '4 of 4 tracked lifts held or rose in 2 weeks · 6 imported sessions'], ['not', '3 of 7 days at or above 150 g · logged intake'], ['not', '+0.40 kg/week · band is a loss of 0.4–0.8 kg/week']),
  weight: { cur: '86.6', src: 'Weighed Fri 20 Nov · manual', v: '88.5,88,87.6,87,86.4,86,85.4,85,85.2,85.6,86.2,86.6', l0: '4 Sep', l1: '20 Nov', rate: '+0.40', pct: '+0.46', win: 'Last 4 weeks · 85.0 → 86.6 kg', noproj: 'No projection: weight is not falling' },
  waist: { cur: '94.0', src: 'Measured Fri 20 Nov · manual', v: '96,95.5,95,95,94.5,94,93.5,93,93,93.5,93.5,94', l0: '4 Sep', l1: '20 Nov', a: ['2-week change', '+0.5', 'cm'], b: ['Since phase start', '−2.0', 'cm'] } };
S.recomp = { phase: PH, wk: 'week of 2 Nov',
  vt: 'Hold steady', rule: 'The scale is flat at −0.05 kg/week, but waist is down 1.5 cm in 2 weeks and working weights rose. Your rules count that pattern as progress, so the low-loss rule does not fire. No change this week.',
  sig: sigs(['met', '−1.5 cm in 2 weeks · 92.5 → 91.0 cm'], ['met', '3 of 4 tracked lifts rose, 1 held in 2 weeks · 6 imported sessions'], ['met', '6 of 7 days at or above 150 g · logged intake'], ['not', '−0.05 kg/week · below the 0.4–0.8 kg/week band']),
  weight: { cur: '85.0', src: 'Weighed Fri 6 Nov · manual', v: '88.5,88,87.4,86.8,86.2,85.2,85.2,85,85.2,85', l0: '4 Sep', l1: '6 Nov', rate: '−0.05', pct: '−0.06', win: 'Last 4 weeks · 85.2 → 85.0 kg', noproj: 'No projection: weight is close to flat on this trend' },
  waist: { cur: '91.0', src: 'Measured Fri 6 Nov · manual', v: '96,95.5,95,94.5,94,93.5,93,92.5,92,91', l0: '4 Sep', l1: '6 Nov', a: ['2-week change', '−1.5', 'cm'], b: ['Since phase start', '−5.0', 'cm'] } };

/* ---------- Today pieces ---------- */
const todayTop = date => `<div class="sb"></div>
  <div class="hdr"><div><div class="lt">Today</div><div class="sub">${date}</div></div><div class="row gap10"><div class="pill"><span class="dot" style="background:var(--recovery)"></span><span class="num">84%</span></div><div class="ibtn" data-ic="person" data-s="22"></div></div></div>
  <div class="wrap" style="margin-top:20px"><div class="card" style="padding:18px 14px 16px"><div class="rings" data-s="86" data-r="68" data-st="11.4"></div></div></div>`;
const tile = (icon, tint, title, val, unit, cap) => `<div class="yc motion"><div class="hd" style="color:var(${tint})"><span data-ic="${icon}" data-s="16"></span><b>${title}</b><span class="chev">›</span></div><div class="v num">${val}${unit ? `<small>${unit}</small>` : ''}</div><div class="c">${cap}</div></div>`;
const OTHER = tile('bolt', '--stress', 'Stress', '1.4', 'of 3', 'Moderate') + tile('run', '--recovery', 'Fitness age', '≤ 34', 'yrs', 'as of 1 Nov');
const ALL = s => SHORT.map((l, i) => [l, Array.isArray(s) ? s[i] : s]);
const CARD = {
  def: { vd: 'Hold steady', vs: '4 of 4 signals met · week of 2 Nov', spark: W.join(','), sig: ALL('met'), cap: '84.0 kg · −0.50 kg/week · weighed Fri 6 Nov' },
  first: { vd: 'No weigh-ins yet', none: 1, vs: 'Weight and waist once a week give four signals and a verdict from your own rules.', cap: 'Two numbers, under 30 seconds', cta: 'Add first weigh-in' },
  due: { vd: 'Hold steady', vs: 'Last verdict · week of 2 Nov', spark: W.join(','), sig: ALL('met'), cap: 'Weigh-in due this week · last weighed Fri 6 Nov', cta: 'Weigh in' },
  liftunk: { vd: 'Hold steady', vs: '1 rule not evaluated · week of 2 Nov', spark: W.join(','), sig: ALL(['met', 'unk', 'met', 'met']), cap: 'Lifts unknown: no sessions imported for 24 Oct – 6 Nov' },
  one: { vd: 'Not enough data', none: 1, vs: '2 more weekly weigh-ins needed', sig: ALL(['unk', 'met', 'unk', 'unk']), cap: '88.5 kg · weighed Fri 4 Sep' },
  few: { vd: 'Not enough data', none: 1, vs: '1 more weekly weigh-in needed', spark: '88.5,88', sig: ALL(['unk', 'met', 'unk', 'unk']), cap: '88.0 kg · weighed Fri 11 Sep' },
  missed: { vd: 'Hold steady', vs: '4 of 4 signals met · week of 2 Nov', spark: '88.5,88,87.6,87,86.4,86,85.4,85,84', sig: ALL('met'), cap: '84.0 kg · −0.50 kg/week · no weigh-in in the week of 26 Oct' },
  target: { vd: 'Hold steady', vs: 'Target reached · 79.9 kg, target 80.0 kg', spark: S.target.weight.v, sig: ALL('met'), cap: '79.9 kg · −0.50 kg/week · weighed Fri 1 Jan' },
  rising: { vd: 'Reduce carbohydrate', vs: '1 of 4 signals met · week of 16 Nov', spark: S.rising.weight.v, sig: ALL(['not', 'met', 'not', 'not']), cap: '86.6 kg · +0.40 kg/week · weighed Fri 20 Nov' },
  recomp: { vd: 'Hold steady', vs: '3 of 4 signals met · flat scale, waist and lifts moving', spark: S.recomp.weight.v, sig: ALL(['met', 'met', 'met', 'not']), cap: '85.0 kg · −0.05 kg/week · weighed Fri 6 Nov' },
};
function scCard(st, compact) {
  const head = `<div class="hd"><span data-ic="scale" data-s="16"></span><b>Cut scorecard</b><span class="chev">›</span></div>`;
  if (compact) return `<div class="yc motion">${head}<div class="v" style="font-size:20px;line-height:24px">${st.vd}</div><div class="c">${st.vs.split(' · ')[0]}</div></div>`;
  const sig = st.sig ? `<div class="sigs">${st.sig.map(([l, s]) => `<span class="sg ${s}">${glyph(s, 16)}${l}</span>`).join('')}</div>` : '';
  return `<div class="yc wide scc motion">${head}
    <div class="top"><div><div class="vd${st.none ? ' none' : ''}">${st.vd}</div><div class="vs">${st.vs}</div></div>${st.spark && st.spark.includes(',') ? `<svg class="line" data-c="--t1" data-v="${st.spark}" width="84" height="34"></svg>` : ''}</div>
    ${sig}<div class="foot"><div class="c">${st.cap}</div>${st.cta ? `<span class="cta">${st.cta}</span>` : ''}</div></div>`;
}
const skCard = `<div class="yc wide scc" style="gap:12px"><div class="skb" style="width:38%;height:13px"></div><div class="skb" style="width:54%;height:24px;margin-top:6px"></div><div class="skb" style="width:100%;height:14px"></div><div class="skb" style="width:72%;height:12px"></div></div>`;
const todayFrame = (date, st) => `${todayTop(date)}
  <div class="sec"><h3>Your cards</h3><a>Edit<span class="chev">›</span></a></div>
  <div class="wrap"><div class="ycgrid">${scCard(st)}${OTHER}</div></div>
  <div class="tabbar" data-on="0"></div><div class="home"></div>`;

/* ---------- scorecard screen ---------- */
const AMB = s => { const m = s.sig.filter(x => x.s === 'met').length, n = s.sig.filter(x => x.s === 'not').length, a = [];
  if (m) a.push(['--recovery', 70, 0, 150 + 45 * m, +(.10 + .06 * m).toFixed(2)]); if (n) a.push(['--rec-mid', 350, 30, 140 + 50 * n, +(.10 + .07 * n).toFixed(2)]);
  return `data-ambient='${JSON.stringify(a)}' data-ambh="520"`; };
const count = v => `<span data-count="${v}" data-dec="1">${v}</span>`;
const kvCell = ([k, v, u]) => `<div><div class="k">${k}</div><div class="v num${v == null ? ' none' : ''}">${v == null ? '—' : v}${v != null && u ? `<small>${u}</small>` : ''}</div></div>`;
function curve(title, unit, c, kv, tail, ax) {
  return `<div class="card cv"><div class="lab">${title}</div><div class="big num">${count(c.cur)}<small>${unit}</small></div><div class="src" style="margin-top:8px"><i></i>${c.src}</div>
    <svg class="wk" width="${ax ? 330 : 332}" height="${(c.v.includes(',') ? 142 : 96) + (ax ? 14 : 0)}" data-v="${c.v}"${ax ? ' data-fs="24"' : ''}${c.ext && !ax ? ` data-ext="${c.ext}"` : ''}${c.l0 ? ` data-l0="${c.l0}"` : ''}${c.l1 ? ` data-l1="${c.l1}"` : ''}${c.mark && !ax ? ` data-mark="${c.mark}"` : ''}></svg>
    <div class="kv">${kv.map(kvCell).join('')}</div>${tail}</div>`;
}
function weightCard(c, ax) {
  const kv = [['Rate', c.rate, 'kg/week'], ['Of bodyweight', c.pct, '%/week']];
  const tail = `<div class="lab" style="margin-top:6px">${c.rate == null ? c.rateNote : c.win}</div><div class="sep" style="margin-top:14px"></div>
    <div class="proj"><div class="lab">Projection${c.proj ? '<span class="est">Estimate</span>' : ''}</div><div class="t${c.proj ? '' : ' none'}">${c.proj || c.noproj}</div></div>`;
  return curve('Weight', 'kg', c, kv, tail, ax);
}
const sigRows = sig => sig.map(x => `<div class="sig">${glyph(x.s)}<div class="grow1"><div class="k">${x.k}</div><div class="n">${x.n}</div></div><div class="w" style="color:var(${ST[x.s].c})">${ST[x.s].w}</div></div>`).join('<div class="sep"></div>');
const navbar = (title, right = 'plus') => `<div class="navbar"><div class="ibtn" data-ic="chev-l" data-s="22"></div><div class="ttl">${title}</div>${right ? (right.length > 6 ? `<div class="lnk" style="margin:0">${right}</div>` : `<div class="ibtn" data-ic="${right}" data-s="22"></div>`) : '<div style="width:40px"></div>'}</div>`;
const links = n => `<div class="wrap mt16"><div class="card" style="padding:4px 18px"><div class="nrow"><div class="t">History</div><div class="val">${n} weigh-in${n === 1 ? '' : 's'}</div><span class="chev">›</span></div><div class="sep"></div><div class="nrow"><div class="t">Phase and reminder</div><div class="val">Reminder off</div><span class="chev">›</span></div></div></div>
  <div class="foottext">Verdicts come only from the rules and numbers shown here. NOOP does not change any target for you.</div>`;
function scorecard(s, o = {}) {
  const met = s.sig.filter(x => x.s === 'met').length;
  const top = o.root ? `<div class="sb"></div><div class="hdr"><div><div class="lt">Cut</div><div class="sub">Scorecard</div></div><div class="ibtn" data-ic="plus" data-s="22"></div></div>` : `<div class="sb"></div>${navbar('Cut scorecard')}`;
  return `${top}
  <div class="phase motion"><div class="lab">${s.phase.lab}</div><div class="nm">${s.phase.nm}</div><div class="meta">${s.phase.meta}</div></div>
  ${s.banner ? `<div class="wrap mt16"><div class="banner motion"><div><div class="bt">${s.banner.t}</div><div class="bd">${s.banner.d}</div></div><span class="cta">${s.banner.cta}</span></div></div>` : ''}
  <div class="wrap mt16"><div class="card verdict">
    <div class="row1"><span class="lab">Verdict · ${s.wk}</span><span class="lab">${met} of 4 signals met</span></div>
    <div class="vt${s.none ? ' none' : ''}">${s.vt}</div>${s.tag ? `<div class="tag">${glyph('unk', 16)}${s.tag}</div>` : ''}
    ${s.rule ? `<div class="rl">Rule that fired</div><div class="rt">${s.rule}</div>` : `<div class="rl">Why</div><div class="rt">${s.need}</div>`}
    ${s.noeval ? `<div class="rl">Not evaluated</div><div class="rt">${s.noeval}</div><div class="lnk">${s.link}<span class="chev">›</span></div>` : ''}
    ${s.extra ? `<div class="rl">Note</div><div class="rt t2">${s.extra}</div>` : ''}
  </div></div>
  <div class="sec"><h3>Four signals</h3><a>This week</a></div>
  <div class="wrap"><div class="card" style="padding:14px 18px">${sigRows(s.sig)}</div></div>
  <div class="sec"><h3>Weekly curves</h3><a>History<span class="chev">›</span></a></div>
  <div class="wrap">${weightCard(s.weight, o.ax)}</div>
  <div class="wrap mt12">${curve('Waist', 'cm', s.waist, [s.waist.a, s.waist.b], '', o.ax)}</div>
  ${links(s.weight.v.split(',').filter(x => x !== 'x').length)}
  ${o.tab != null ? `<div class="tabbar" data-on="${o.tab}"${o.five ? ' data-five="1"' : ''}></div>` : ''}<div class="home"></div>`;
}
const firstUse = `<div class="sb"></div>${navbar('Cut scorecard')}
  <div class="wrap" style="margin-top:28px"><div class="card empty"><div style="color:var(--t2);display:grid;place-items:center" data-ic="scale" data-s="36"></div>
    <div class="et">No weigh-ins yet</div><div class="ed">Record weight and waist once a week. After 3 weekly weigh-ins the scorecard shows four signals and a verdict from your own rules.</div>
    <div class="btn primary">Add first weigh-in</div><div class="btn secondary" style="margin-top:10px">Set phase and target</div></div></div>
  <div class="sec"><h3>Four signals</h3><a>Not measured yet</a></div>
  <div class="wrap"><div class="card" style="padding:14px 18px">${sigRows(sigs(['unk', 'Needs waist readings from 3 weeks'], ['unk', 'No lift sessions imported'], ['unk', 'No intake source connected'], ['unk', 'Needs weigh-ins from 3 weeks']))}</div></div>
  <div class="foottext">Weight and waist curves appear with the first weigh-in. Nothing is shown as zero before then.</div><div class="home"></div>`;
const skeleton = `<div class="sb"></div>${navbar('Cut scorecard')}
  <div class="phase"><div class="skb" style="width:110px;height:13px"></div><div class="skb" style="width:190px;height:30px;margin-top:8px"></div><div class="skb" style="width:280px;height:13px;margin-top:10px"></div></div>
  <div class="wrap mt16"><div class="card"><div class="skb" style="width:150px;height:13px"></div><div class="skb" style="width:210px;height:34px;margin-top:12px"></div><div class="skb" style="width:100%;height:14px;margin-top:18px"></div><div class="skb" style="width:78%;height:14px;margin-top:8px"></div></div></div>
  <div class="sec"><div class="skb" style="width:130px;height:20px"></div></div>
  <div class="wrap"><div class="card" style="padding:14px 18px">${[0, 1, 2, 3].map(i => `<div class="sig" style="align-items:center"><div class="skb" style="width:24px;height:24px;border-radius:50%;flex:none"></div><div class="grow1"><div class="skb" style="width:${[52, 78, 70, 82][i]}%;height:14px"></div><div class="skb" style="width:${[64, 58, 50, 60][i]}%;height:12px;margin-top:8px"></div></div></div>`).join('<div class="sep"></div>')}</div></div>
  <div class="sec"><div class="skb" style="width:150px;height:20px"></div></div>
  <div class="wrap"><div class="card"><div class="skb" style="width:60px;height:13px"></div><div class="skb" style="width:130px;height:40px;margin-top:10px"></div><div class="skb" style="width:100%;height:120px;margin-top:16px;border-radius:14px"></div></div></div><div class="home"></div>`;

/* ---------- weigh-in sheet ---------- */
const KEYS = `<div class="keys">${['1', '2', '3', '4', '5', '6', '7', '8', '9', '.', '0', '⌫'].map(k => `<span${k === '.' || k === '⌫' ? ' class="fn"' : ''}>${k}</span>`).join('')}</div>`;
const backdrop = tall => `<div class="sb"></div><div class="dim">${navbar('Cut scorecard')}${tall ? '' : `<div class="phase"><div class="lab">${PH.lab}</div><div class="nm">${PH.nm}</div></div>`}</div>`;
function calendar() { // November 2026, Monday first. Today is Fri 13 Nov; Wed 4 Nov is selected; dots mark days that already hold a reading.
  const cells = ['26', '27', '28', '29', '30', '31'].map(d => `<span class="o${d === '30' ? ' has' : ''}">${d}</span>`);
  for (let d = 1; d <= 30; d++) cells.push(`<span class="${d === 4 ? 'sel' : d === 13 ? 'td' : d > 13 ? 'f' : ''}${d === 6 ? ' has' : ''}">${d === 4 ? `<b>${d}</b>` : d}</span>`);
  return `<div class="cal"><div class="mh">November 2026<span><span>‹</span><span>›</span></span></div><div class="g">${['M', 'T', 'W', 'T', 'F', 'S', 'S'].map(x => `<i>${x}</i>`).join('')}${cells.join('')}</div></div>`;
}
function sheet(o) {
  return `${backdrop(o.cal || o.full)}<div class="sheet wsheet"${o.full ? ' style="top:64px"' : ''}><div class="grabber"></div>
    <div class="sbar"><span>Cancel</span><span class="t">Weigh-in</span><span class="stp">Step ${o.step} of 2</span></div>
    <div class="datechip${o.cal ? ' on' : ''}"><span data-ic="cal" data-s="16"></span>${o.date}<span class="chev" style="margin-left:0">›</span></div>
    ${o.cal ? calendar() : ''}${o.dateNote ? `<div class="datenote">${o.dateNote}</div>` : ''}
    ${o.done ? `<div class="donerow">${glyph('met', 18)}<span>Weight <b class="num">${o.done}</b></span><span class="ed">Edit</span></div>` : ''}
    <div class="entry"><div class="lab">${o.label}</div><div class="bigin num${o.ghost ? ' ghost' : ''}">${o.ghost ? '<i class="caret"></i>' : ''}${o.val}${o.ghost ? '' : '<i class="caret"></i>'}<small>${o.unit}</small></div><div class="hint">${o.hint}</div></div>
    <div class="btn primary">${o.primary}</div>
    ${o.skip ? `<div class="skip">Skip waist this week</div><div class="skipnote">Saves the weight. Waist is stored as not taken, never as 0.</div>` : ''}
    ${o.cal ? '' : KEYS}</div>`;
}

/* ---------- history ---------- */
const H = [
  ['Week of 9 Nov', [['Fri 13 Nov', 'Weekly point', '83.5', '91.5']]],
  ['Week of 2 Nov', [['Fri 6 Nov', 'Weekly point · latest reading in the week', '84.0', '92.0'], ['Wed 4 Nov', 'Backdated · added Fri 13 Nov · not the weekly point', '84.4', null, 1]], '2 readings'],
  ['Week of 26 Oct', [['Fri 30 Oct', 'Weekly point', '84.6', '92.5']]],
  ['Week of 19 Oct', [['Fri 23 Oct', 'Weekly point', '85.0', '93.0']]],
  ['Week of 12 Oct', [['Fri 16 Oct', 'Weekly point', '85.4', null]]],
  ['Week of 5 Oct', [['Fri 9 Oct', 'Weekly point', '86.0', '94.0']]],
];
const hrow = ([d, m, w, wa, off]) => `<div class="hrow${off ? ' off' : ''}"><div><div class="d">${d}</div><div class="m">${m}</div></div><div class="x num">${w}<small>kg</small></div>${wa ? `<div class="x num">${wa}<small>cm</small></div>` : '<div class="x none">Not taken</div>'}</div>`;
const swiped = ([d, m]) => `<div class="swipe"><div class="hrow"><div><div class="d">${d}</div><div class="m">${m}</div></div></div><div class="act e"><span data-ic="pencil" data-s="20"></span>Edit</div><div class="act x"><span data-ic="trash" data-s="20"></span>Delete</div></div>`;
const history = swipe => `<div class="sb"></div>${navbar('History', 'plus')}
  <div class="colh"><span></span><span>Weight</span><span>Waist</span></div>
  ${H.map(([wk, rows, extra], gi) => `<div class="wkh"${gi ? '' : ' style="padding-top:6px"'}><b>${wk}</b><span>${extra || ''}</span></div><div class="wrap"><div class="card" style="padding:4px 18px">${rows.map((r, ri) => swipe && gi === 1 && ri === 1 ? swiped(r) : hrow(r)).join('<div class="sep"></div>')}</div></div>`).join('')}
  <div class="foottext">Swipe a row to edit or delete it. When a week has two readings, the later one is the weekly point; the other stays in history. The same readings appear in Lab Book.</div><div class="home"></div>`;
const editSheet = `<div class="sb"></div><div class="dim">${navbar('History', 'plus')}</div>
  <div class="sheet wsheet"><div class="grabber"></div>
    <div class="sbar"><span>Cancel</span><span class="t">Edit weigh-in</span><span class="stp" style="font-size:17px;font-weight:600;color:var(--t1)">Save</span></div>
    <div class="datechip"><span data-ic="cal" data-s="16"></span>Wed 4 Nov<span class="chev" style="margin-left:0">›</span></div>
    <div class="datenote">Backdated. Added Fri 13 Nov. Counts for the week of 2–8 Nov.</div>
    <div class="fld"><span class="k">Weight</span><span class="v num">84.4<small>kg</small></span></div>
    <div class="fld"><span class="k">Waist</span><span class="v none">Not taken · Add</span></div>
    <div class="btn danger" style="margin-top:22px"><span data-ic="trash" data-s="20"></span>Delete weigh-in</div>
    <div class="skipnote" style="margin-top:10px">Deleting removes this reading from the weekly series and the scorecard. It cannot be undone.</div></div>`;

/* ---------- phase and reminder ---------- */
const nrow = (t, v, ch = 1) => `<div class="nrow"><div class="t">${t}</div><div class="val">${v}</div>${ch ? '<span class="chev">›</span>' : ''}</div>`;
const grp = rows => `<div class="wrap"><div class="card" style="padding:4px 18px">${rows.join('<div class="sep"></div>')}</div></div>`;
const phaseScreen = on => `<div class="sb"></div>${navbar('Phase and reminder', null)}
  <div class="gh" style="padding-top:10px">Phase</div>${grp([nrow('Name', 'Autumn cut'), nrow('Start date', 'Fri 4 Sep 2026'), nrow('Target weight', '80.0 kg')])}
  <div class="gh">Expected rate of loss</div>${grp([nrow('At least', '0.4 kg/week'), nrow('At most', '0.8 kg/week')])}
  <div class="gf">At 84.0 kg that is 0.48–0.95% of bodyweight a week. The rate signal is met inside this band.</div>
  <div class="gh">Reminder</div>${grp([`<div class="nrow"><div class="t">Weekly weigh-in reminder</div><div class="toggle${on ? ' on' : ''}"></div></div>`].concat(on ? [nrow('Day', 'Friday'), nrow('Time', '07:30')] : []))}
  <div class="gf">${on ? 'One notification a week, at this time. It is not sent if the week already has a weigh-in, and it is never repeated.' : 'Off by default. When on, you get one notification a week at a time you choose. No follow-ups.'}</div>
  ${on ? `<div class="gh">What it looks like</div><div class="wrap"><div class="notif"><div class="ai" data-ic="today" data-s="22"></div><div class="grow1"><div class="row gap8"><div class="nt">Weekly weigh-in</div><div class="nw">07:30</div></div><div class="nb">Record this week's weight and waist.</div></div></div></div>` : ''}
  <div class="home"></div>`;

/* ---------- Health tab (placement P2) ---------- */
const healthTab = `<div class="sb"></div><div class="hdr"><div><div class="lt">Health</div><div class="sub">Sat, 7 Nov</div></div><div class="ibtn" data-ic="person" data-s="22"></div></div>
  <div class="sec"><h3>Vitals</h3><a>All<span class="chev">›</span></a></div>
  <div class="wrap"><div class="ycgrid">${tile('trend', '--hrv', 'HRV', '62', 'ms', 'Last night')}${tile('heart', '--heart', 'Resting heart rate', '52', 'bpm', 'Last night')}</div></div>
  <div class="sec"><h3>Body</h3><a>History<span class="chev">›</span></a></div>
  <div class="wrap"><div class="ycgrid">${scCard(CARD.def)}</div></div>
  <div class="sec"><h3>More</h3></div>
  ${grp([nrow('Lab Book', '14 markers'), nrow('Fitness age', '≤ 34 yrs'), nrow('Steps', 'Apple Health')])}
  <div class="tabbar" data-on="3"></div><div class="home"></div>`;

/* ---------- frames ---------- */
const G = []; let cur;
const group = (title, note) => { cur = { title, note, frames: [] }; G.push(cur); };
const frame = (name, html, o = {}) => cur.frames.push({ name, html, ...o });
const TODAY_AMB = 'data-ambient="today:86,68,11.4"';
const sc = (key, o = {}) => ({ attrs: AMB(S[key]), ...o });

group('A · Entry point on Today', 'A full-width tile in <b>Your cards</b>: the verdict, the four signals by name, and the last weigh-in. It never shows a number it does not have. The header stays neutral: body composition has no semantic colour in the palette, so none is invented.');
frame('A1 Today card · default', todayFrame('Sat, 7 Nov', CARD.def), { attrs: TODAY_AMB });
frame('A2 Today card · first use (no readings)', todayFrame('Sat, 5 Sep', CARD.first), { attrs: TODAY_AMB });
frame('A3 Today card · weigh-in due this week', todayFrame('Thu, 12 Nov', CARD.due), { attrs: TODAY_AMB, note: 'Shown once the current week has no weigh-in. Neutral, no amber: it is a fact, not a warning. The button opens the sheet directly.' });
frame('A4 Today card · lift signal unknown', todayFrame('Sat, 7 Nov', CARD.liftunk), { attrs: TODAY_AMB, note: 'The Lifts mark is the dashed ring used for "not measured" rings elsewhere. The card says a rule was not evaluated; it does not count lifts as holding.' });
frame('A5 Today card · other states', `<div class="sb"></div><div class="navbar"><div style="width:40px"></div><div class="ttl">Card states</div><div style="width:40px"></div></div>
  ${[['One reading', 'one'], ['Fewer readings than the rules need', 'few'], ['A missed week', 'missed'], ['Target reached', 'target'], ['Weight rising', 'rising'], ['Flat scale, waist shrinking, lifts climbing', 'recomp']].map(([l, k]) => `<div class="wrap" style="margin-top:14px"><div class="lab" style="padding:0 2px 6px">${l}</div><div class="ycgrid">${scCard(CARD[k])}</div></div>`).join('')}
  <div class="wrap" style="margin-top:14px"><div class="lab" style="padding:0 2px 6px">Loading</div><div class="ycgrid">${skCard}</div></div><div class="home"></div>`, { attrs: 'data-nomotion' });
frame('A6 Today card · AX5', `<div class="sb"></div><div class="navbar"><div style="width:40px"></div><div class="ttl">Today</div><div style="width:40px"></div></div>
  <div class="sec" style="padding-top:12px"><h3>Your cards</h3><a>Edit<span class="chev">›</span></a></div>
  <div class="wrap"><div class="ycgrid">${scCard(CARD.due)}${scCard(CARD.liftunk)}</div></div><div class="home"></div>`, { cls: 'ax', note: 'Largest accessibility size. One column; the sparkline is dropped, the four signals stack, the button wraps.' });

group('B · Scorecard screen', 'Phase and target, the verdict with the rule that fired, the four signals with their numbers, then the weekly weight and waist curves. Curves are a smooth line with a gradient fill and one point per weekly reading: no rules, bands or target lines. The target is text, plus one quiet tick on the time axis when the projected date is near enough to draw.');
frame('B1 Scorecard · default', scorecard(S.def), sc('def'));
frame('B2 Scorecard · first use (no readings)', firstUse, { attrs: 'data-ambient="[]" data-ambh="520"' });
frame('B3 Scorecard · one reading', scorecard(S.one), sc('one'));
frame('B4 Scorecard · fewer readings than the rules need', scorecard(S.few), sc('few'));
frame('B5 Scorecard · a missed week', scorecard(S.missed), sc('missed', { note: 'The week with no reading is an open ring on the time axis. The curve passes across it with no point.' }));
frame('B6 Scorecard · target reached', scorecard(S.target), sc('target'));
frame('B7 Scorecard · weight rising', scorecard(S.rising), sc('rising'));
frame('B8 Scorecard · lift signal unknown', scorecard(S.liftunk), sc('liftunk'));
frame('B9 Scorecard · flat scale, waist shrinking, lifts climbing', scorecard(S.recomp), sc('recomp'));
frame('B10 Scorecard · loading skeleton', skeleton, { attrs: 'data-nomotion' });
frame('B11 Scorecard · AX5', scorecard(S.liftunk, { ax: 1 }), sc('liftunk', { cls: 'ax' }));

group('C · Weigh-in sheet', 'Two steps, two numbers. The system decimal keypad is up from the start; the last value sits in the field as a grey hint and typing replaces it. Units follow the profile (kg/cm or lb/in); storage stays metric. The date chip opens a calendar for backdating.');
frame('C1 Weigh-in · step 1 weight', sheet({ step: 1, date: 'Today · Fri 13 Nov', label: 'Weight', val: '84.0', ghost: 1, unit: 'kg', hint: 'Last: 84.0 kg · Fri 6 Nov. Type to replace.', primary: 'Next: waist' }), { attrs: 'data-nomotion' });
frame('C2 Weigh-in · step 2 waist', sheet({ step: 2, date: 'Today · Fri 13 Nov', done: '83.5 kg', label: 'Waist', val: '91.5', unit: 'cm', hint: 'Last: 92.0 cm · Fri 6 Nov', primary: 'Save weigh-in', skip: 1 }), { attrs: 'data-nomotion' });
frame('C3 Weigh-in · backdating', sheet({ step: 1, date: 'Wed 4 Nov', cal: 1, dateNote: 'Backdated. Counts for the week of 2–8 Nov, which already has a reading on Fri 6 Nov. The later reading stays the weekly point. Future dates cannot be picked.', label: 'Weight', val: '84.4', unit: 'kg', hint: 'Nearest earlier reading: 84.6 kg · Fri 30 Oct', primary: 'Next: waist' }), { attrs: 'data-nomotion' });
frame('C4 Weigh-in · lb and in profile units', sheet({ step: 2, date: 'Today · Fri 13 Nov', done: '184.1 lb', label: 'Waist', val: '36.2', ghost: 1, unit: 'in', hint: 'Last: 36.2 in · Fri 6 Nov. Type to replace.', primary: 'Save weigh-in', skip: 1 }), { attrs: 'data-nomotion' });
frame('C5 Weigh-in · AX5', sheet({ step: 1, full: 1, date: 'Today · Fri 13 Nov', label: 'Weight', val: '84.0', ghost: 1, unit: 'kg', hint: 'Last: 84.0 kg · Fri 6 Nov. Type to replace.', primary: 'Next: waist' }), { cls: 'ax', attrs: 'data-nomotion', style: 'min-height:1180px' });

group('D · History', 'Grouped by week, newest first, with weight and waist per entry. A waist that was skipped reads "Not taken". Backdated entries say so. Where a week has two readings the list states which one is the weekly point.');
frame('D1 History · list', history(false));
frame('D2 History · swipe to edit or delete', history(true), { attrs: 'data-nomotion' });
frame('D3 History · edit entry', editSheet, { attrs: 'data-nomotion' });

group('E · Phase and reminder', 'Phase name, start date, target weight and the expected rate band. The weekly reminder is off by default.');
frame('E1 Phase · reminder off (default)', phaseScreen(false));
frame('E2 Phase · reminder on, with the notification', phaseScreen(true));

group('P1 · Placement: Today card opens a detail screen', 'The scorecard lives behind its Your cards tile. Back returns to Today; the tab bar stays on Today.');
frame('P1.1 Placement P1 · Today card', todayFrame('Sat, 7 Nov', CARD.def), { attrs: TODAY_AMB });
frame('P1.2 Placement P1 · detail pushed from Today', scorecard(S.def, { tab: 0 }), sc('def'));
group('P2 · Placement: a Body section under Health', 'The scorecard is a destination in the Health tab. The Today tile is optional and, if kept, is the compact half-width version.');
frame('P2.1 Placement P2 · Health tab, Body section', healthTab, { attrs: `data-ambient='[["--heart",350,20,190,0.2],["--hrv",50,0,200,0.2]]'` });
frame('P2.2 Placement P2 · scorecard under Health', scorecard(S.def, { tab: 3 }), sc('def'));
frame('P2.3 Placement P2 · optional compact Today tile', `${todayTop('Sat, 7 Nov')}
  <div class="sec"><h3>Your cards</h3><a>Edit<span class="chev">›</span></a></div>
  <div class="wrap"><div class="ycgrid">${scCard(CARD.def, true)}${tile('bolt', '--stress', 'Stress', '1.4', 'of 3', 'Moderate')}</div></div>
  <div class="tabbar" data-on="0"></div><div class="home"></div>`, { attrs: TODAY_AMB });
group('P3 · Placement: a fifth tab (not recommended)', 'Cheap to draw, so it is here for comparison. Not recommended: the scorecard changes once a week and would hold a permanent daily slot; five tabs plus Coach crowd the bar and its labels at larger text sizes; and it would be the only tab named after a temporary phase.');
frame('P3.1 Placement P3 · Cut tab', scorecard(S.def, { tab: 4, five: 1, root: 1 }), sc('def'));

// ?only=B (or ?only=B1) shows just the frames whose id starts with that text. Handy for review; not used for export.
const ONLY = new URLSearchParams(location.search).get('only');
if (ONLY) { G.forEach(g => g.frames = g.frames.filter(f => f.name.startsWith(ONLY))); for (let i = G.length - 1; i >= 0; i--) if (!G[i].frames.length) G.splice(i, 1); }
document.getElementById('boards').innerHTML = G.map(g => `<h2 class="grp-title">${g.title}</h2><p class="grp-note">${g.note}</p><div class="board">${g.frames.map(f =>
  `<section><div class="board-title">R6 / ${f.name}</div><div class="screen${f.cls ? ' ' + f.cls : ''}" ${f.attrs || ''} style="${f.style || ''}">${f.html}</div>${f.note ? `<p class="fnote">${f.note}</p>` : ''}</section>`).join('')}</div>`).join('');

boot(() => {
  document.querySelectorAll('svg.wk').forEach(weekChart);
  // Placement P3 only: a five-item bar. noop.js tabbar() draws the shipped four.
  document.querySelectorAll('.tabbar[data-five]').forEach(t => {
    const items = [['today', 'Today'], ['moon', 'Sleep'], ['dumbbell', 'Training'], ['heart', 'Health'], ['scale', 'Cut']];
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
