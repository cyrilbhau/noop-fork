/* Round S6 · Niggle log, recovery context, checkpoint timeline (Stage 6).
   Every frame is drawn from model.js (the §13 fixture run through a design model of §7) and worded through strings.js.
   Nothing below types a result or a sentence by hand. EVERY VALUE IS SYNTHETIC ("Fixture Person" does not exist).
   The frame list is built as plain HTML strings, so this file also runs under Node (see check.js); only the last block needs a browser. */
const S6_NODE = typeof document === 'undefined';
if (S6_NODE) Object.assign(globalThis, require('./model.js'), require('./strings.js'));
const DY = S6Day, FXT = S6FX;

/* ---------- formatting ---------- */
const MON = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'], DOW = ['Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat'];
const sd = d => `${+d.slice(8)} ${MON[+d.slice(5, 7) - 1]}`;
const fd = d => `${DOW[new Date(DY.number(d) * 864e5).getUTCDay()]} ${sd(d)}`;
const kg = v => `${v.toFixed(1)} kg`;
const one = v => v.toFixed(1);
const signed = v => (v > 0 ? '+' : v < 0 ? '−' : '') + Math.abs(v).toFixed(1);
const whenIs = (day, today) => day === today ? `${t('today')} · ${fd(day)}` : fd(day);

/* ---------- shared pieces (the shapes of round 6: navbar, grouped rows, headers, footers, skeleton blocks) ---------- */
const navbar = (title, right = 'plus') => `<div class="sb"></div><div class="navbar"><div class="ibtn" data-ic="chev-l" data-s="22"></div><div class="ttl">${title}</div>${right ? `<div class="ibtn" data-ic="${right}" data-s="22"></div>` : '<div style="width:40px"></div>'}</div>`;
const modalBar = (title, o = {}) => `<div class="sb"></div><div class="navbar"><div class="lnk nb${o.busy ? ' t3' : ''}">${t('cancel')}</div><div class="ttl">${title}</div><div class="lnk nb${o.off || o.busy ? ' t3' : ''}">${o.busy ? t('saving') : t('save')}</div></div>`;
const sec = (title, right) => `<div class="sec"><h3>${title}</h3>${right ? `<a>${right}</a>` : ''}</div>`;
const card = (rows, pad = '4px 18px') => `<div class="wrap"><div class="card" style="padding:${pad}">${rows.join('<div class="sep"></div>')}</div></div>`;
const gh = (s, first) => `<div class="gh"${first ? ' style="padding-top:10px"' : ''}>${s}</div>`;
const gf = (s, bad) => `<div class="gf${bad ? ' bad' : ''}">${s}</div>`;
const prow = (label, value, o = {}) => `<div class="nrow${o.bad ? ' bad' : ''}"><div class="t">${label}</div><div class="val${o.strong ? ' strong' : ''}">${value}</div>${o.chev ? '<span class="chev">›</span>' : ''}</div>`;
const tog = (label, on) => `<div class="nrow"><div class="t">${label}</div><div class="toggle${on ? ' on' : ''}"></div></div>`;
const btn = (label, kind = 'secondary', off) => `<div class="wrap mt12"><div class="btn ${kind}${off ? ' off' : ''}">${label}</div></div>`;
const link = label => `<div class="lnk">${label}<span class="chev">›</span></div>`;
const banner = (text, action) => `<div class="wrap mt16"><div class="banner col"><div class="bt">${text}</div>${action ? `<span class="cta quiet">${action}</span>` : ''}</div></div>`;
const fail = reason => `<div class="wrap mt12"><div class="fail"><b>${t('couldNotSave')}</b> <span>${reason}</span></div></div>`;
const RADIO = on => on ? '<svg width="22" height="22" viewBox="0 0 22 22"><circle cx="11" cy="11" r="10" fill="#F5F5F7"/><polyline points="6.6,11.4 9.6,14.4 15.4,8" fill="none" stroke="#000" stroke-width="2.2" stroke-linecap="round" stroke-linejoin="round"/></svg>'
  : '<svg width="22" height="22" viewBox="0 0 22 22"><circle cx="11" cy="11" r="9.2" fill="none" stroke="#FFFFFF" stroke-opacity=".3" stroke-width="1.6"/></svg>';
const choice = (labels, on) => card(labels.map((l, i) => `<div class="nrow"><div class="t">${l}</div>${RADIO(Array.isArray(on) ? on.includes(i) : i === on)}</div>`));
const seg = (labels, on) => `<div class="wrap"><div class="seg">${labels.map((l, i) => `<span${i === on ? ' class="on"' : ''}>${l}</span>`).join('')}</div></div>`;
const field = (label, value, o = {}) => `<div class="wrap"><div class="fld2${o.bad ? ' bad' : ''}" data-label="${label}"><div class="v">${value ? `<span>${value}</span>` : o.ph ? `<span class="ph">${o.ph}</span>` : ''}${o.focus ? '<i class="caret"></i>' : ''}</div></div></div>${o.err ? gf(o.err, 1) : ''}`;
const skb = (w, h, mt = 0) => `<div class="skb" style="width:${w};height:${h}px${mt ? `;margin-top:${mt}px` : ''}"></div>`;
const skCard = n => `<div class="wrap"><div class="card" style="padding:14px 18px">${Array.from({ length: n }, (_, i) => `<div style="padding:10px 0">${skb(['58%', '46%', '64%'][i % 3], 15)}${skb(['82%', '70%', '76%'][i % 3], 12, 8)}</div>`).join('<div class="sep"></div>')}</div></div>`;
const confirmSheet = (title, detail) => `<div class="sheet wsheet"><div class="grabber"></div><div class="at">${title}</div><div class="ad">${detail}</div>
  <div class="btn danger" style="margin-top:18px"><span data-ic="trash" data-s="20"></span>${t('del')}</div><div class="btn secondary" style="margin-top:10px">${t('cancel')}</div></div>`;
const HOME = '<div class="home"></div>';

/* ---------- weekly chart: a smooth line, a gradient area, one point per week with a mean. No rule, band or target line.
   A week without a mean breaks the line and is an open ring on the time axis; it is never drawn across. Built as a string. ---------- */
let S6_GID = 0;
function smoothPath(p) { let d = `M${p[0][0]},${p[0][1]}`;
  for (let i = 0; i < p.length - 1; i++) { const a = p[i - 1] || p[i], b = p[i], c = p[i + 1], e = p[i + 2] || c;
    d += ` C${(b[0] + (c[0] - a[0]) / 6).toFixed(2)},${(b[1] + (c[1] - a[1]) / 6).toFixed(2)} ${(c[0] - (e[0] - b[0]) / 6).toFixed(2)},${(c[1] - (e[1] - b[1]) / 6).toFixed(2)} ${c[0]},${c[1]}`; }
  return d; }
function weekChart(v, l0, l1, o = {}) {
  const w = o.w || 332, fs = o.fs || 11, H = (o.h || 120) + (o.fs ? 14 : 0), h = H - fs - 11, n = v.length, c = '#F5F5F7', id = 'k' + (S6_GID++);
  const real = v.filter(x => x != null); let mn = Math.min(...real), mx = Math.max(...real); const span = (mx - mn) || 1; mn -= span * .14; mx += span * .14;
  const X = i => +(8 + i * (w - 16) / Math.max(1, n - 1)).toFixed(2), Y = x => +(12 + (1 - (x - mn) / (mx - mn)) * (h - 20)).toFixed(2);
  const runs = []; let cur = null; v.forEach((x, i) => { if (x == null) { cur = null; return; } if (!cur) runs.push(cur = []); cur.push([X(i), Y(x)]); });
  let s = `<defs><linearGradient id="a${id}" x1="0" y1="12" x2="0" y2="${h}" gradientUnits="userSpaceOnUse"><stop offset="0" stop-color="${c}" stop-opacity=".28"/><stop offset="1" stop-color="${c}" stop-opacity="0"/></linearGradient>`
    + `<linearGradient id="s${id}" x1="0" y1="0" x2="${w}" y2="0" gradientUnits="userSpaceOnUse"><stop offset="0" stop-color="${c}" stop-opacity=".35"/><stop offset="1" stop-color="${c}" stop-opacity="1"/></linearGradient></defs>`;
  runs.forEach(p => { if (p.length < 2) return; const line = smoothPath(p), a = p[0], b = p[p.length - 1];
    s += `<path class="area" d="${line} L${b[0]},${h} L${a[0]},${h} Z" fill="url(#a${id})"/><path class="stroke" d="${line}" fill="none" stroke="url(#s${id})" stroke-width="2.5" stroke-linecap="round" stroke-linejoin="round"/>`; });
  const all = runs.flat();
  all.forEach((p, i) => { const last = i === all.length - 1;
    if (last) s += `<circle cx="${p[0]}" cy="${p[1]}" r="8" fill="${c}" opacity=".22"/>`;
    s += `<circle cx="${p[0]}" cy="${p[1]}" r="${last ? 4 : 2.6}" fill="${c}" stroke="#0B0B0D" stroke-width="${last ? 1.5 : 1.2}"/>`; });
  v.forEach((x, i) => { if (x == null) s += `<circle cx="${X(i)}" cy="${h + 3}" r="2.6" fill="none" stroke="#FFFFFF" stroke-opacity=".4" stroke-width="1.2"/>`; });
  const text = (x, str, anchor) => `<text x="${x}" y="${H - 3}" text-anchor="${anchor}" fill="#9B9BA3" font-size="${fs}" font-weight="500" font-family="-apple-system,system-ui">${str}</text>`;
  s += text(X(0) - 4, l0, 'start') + (n > 1 ? text(X(n - 1) + 4, l1, 'end') : '');
  return `<svg class="wk" width="${w}" height="${H}" viewBox="0 0 ${w} ${H}">${s}</svg>`;
}

/* ================= (a) NIGGLE LOG ================= */
const sameSpot = (a, b) => a.location.trim().toLowerCase() === b.location.trim().toLowerCase() && a.side === b.side;
/** o: { today, only: [ids], rules, prof, paused, rulesAttention, asStored, opt }. The store as it stood on `today`. */
function logVM(o) {
  const today = o.today, rules = o.rules || FXT.rules, ruleBy = id => rules.find(r => r.id === id);
  const visible = FXT.entries.filter(e => e.onsetDay <= today && (!o.only || o.only.includes(e.id)));
  const rows = visible.filter(e => e.kind === 'complaint').map(e => {
    const c = s6Complaint(e);
    if (!o.asStored) { c.updates = c.updates.filter(u => u.day <= today); if (c.resolvedDay != null && c.resolvedDay > today) c.resolvedDay = null; }
    const r = s6Triage({ complaint: c, rules: o.rulesAttention ? [] : rules, today }, o.opt);
    return { e, c, r, rule: ruleBy(r.ruleId), nextRule: r.nextChange ? ruleBy(r.nextChange.ruleId) : null, also: r.matchedRuleIds.filter(id => id !== r.ruleId).map(ruleBy),
      before: visible.filter(p => p.kind === 'complaint' && p.onsetDay < e.onsetDay && sameSpot(p, e)).length };
  });
  const sev = x => x.r.action ? S6_SEVERITY[x.r.action] : -1;
  const paused = (o.paused || FXT.paused).filter(p => p.pausedDay <= today), isBack = p => p.resumedDay != null && p.resumedDay <= today;
  return { today, rules, prof: o.prof === undefined ? FXT.professionalRule : o.prof, rows,
    open: rows.filter(x => x.r.isOpen).sort((a, b) => (sev(b) - sev(a)) || (b.r.dayCount - a.r.dayCount) || (a.e.location < b.e.location ? -1 : 1)),
    resolved: rows.filter(x => x.r.status === 'resolved'), obs: visible.filter(e => e.kind === 'observation'),
    paused: paused.filter(p => !isBack(p)), resumed: paused.filter(isBack) };
}
function labelLines(x, o = {}) {
  const r = x.r, L = [];
  if (o.rulesAttention) L.push(`<div class="lb none">${t('rulesAttention')}</div>`);
  else if (r.status === 'matched') L.push(`<div class="lb">${x.rule.label}</div><div class="ac">${t('act.' + r.action)}</div>`);
  else if (r.status === 'noRuleMatches') L.push(`<div class="lb none">${t('noneCovers')}</div>`);
  else if (r.status === 'noRulesEntered') L.push(`<div class="lb none">${t('noRules')}</div>`);
  if (r.nextChange) L.push(`<div class="nx">${r.nextChange.ruleId ? t('nextRule', r.nextChange.dayCount, x.nextRule.label) : t('nextNone', r.nextChange.dayCount)}</div>`);
  if (x.before) L.push(`<div class="nx">${x.before === 1 ? t('before1', 1) : t('before', x.before)}</div>`);
  return L.join('');
}
const where = e => `${t('side.' + e.side)}${e.kind === 'complaint' ? ` · ${t('char.' + e.character)}` : ''}`;
const ngRow = (x, o) => `<div class="ng"><div class="top"><div class="grow1"><div class="k">${x.e.location}</div><div class="m">${where(x.e)}</div></div><div class="dc num">${t('day', x.r.dayCount)}</div></div>${labelLines(x, o)}</div>`;
const resolvedAfter = n => n === 1 ? t('resolvedAfter1', n) : t('resolvedAfter', n);
const resolvedRow = x => `<div class="ng"><div class="k">${x.e.location}</div><div class="m">${where(x.e)}</div><div class="ac">${resolvedAfter(x.r.dayCount)}</div><div class="m">${t('range', sd(x.e.onsetDay), sd(x.c.resolvedDay))}</div></div>`;
const pausedRow = p => `<div class="ng"><div class="k">${p.exercise}</div><div class="ac">${p.reason}</div><div class="m">${t('since', sd(p.pausedDay))}</div>${p.until ? `<div class="m">${p.until}</div>` : ''}</div>`;
const resumedRow = p => `<div class="ng"><div class="k">${p.exercise}</div><div class="ac">${p.reason}</div><div class="m">${t('resumed', sd(p.resumedDay))}</div></div>`;
const obsRow = e => `<div class="ng"><div class="k">${e.location}</div><div class="m">${where(e)}</div>${e.note ? `<div class="ac">${e.note}</div>` : ''}<div class="m">${t('noted', sd(e.onsetDay))}</div></div>`;
const disc = (label, n, open) => `<div class="disc"><span class="t">${label}</span><span class="val num">${n}</span><span data-ic="${open ? 'chev-d' : 'chev-r'}" data-s="16" class="dchev"></span></div>`;
/** The owner's own rule for seeing a professional, verbatim, and its three empty forms. */
function profBlock(vm, o = {}) {
  if (o.rulesAttention) return banner(t('attnRules'), t('discard'));
  if (!vm.rules.length) return card([`<div class="quiet">${t('noRules')}</div>${link(t('setUpRules'))}`], '16px 18px');
  if (!vm.prof) return card([`<div class="quiet">${t('profEmpty')}</div>${link(t('setUpRules'))}`], '16px 18px');
  return card([`<div class="own">${vm.prof}</div>`], '16px 18px');
}
function logScreen(o) {
  const top = navbar(t('niggleLog'), o.entriesAttention || o.limit ? null : 'plus');
  if (o.loading) return `${top}${sec(t('secProf'))}<div class="wrap"><div class="card">${skb('84%', 15)}${skb('56%', 15, 9)}</div></div>${sec(t('secOpen'))}${skCard(2)}${sec(t('secPaused'))}${skCard(1)}${sec(t('secObs'))}${skCard(1)}${HOME}`;
  if (o.firstUse) return `${top}<div class="wrap" style="margin-top:28px"><div class="card empty"><div class="ed" style="margin:0">${t('firstUse')}</div></div></div>${btn(t('logNiggle'), 'primary')}${btn(t('setUpRules'))}${HOME}`;
  const vm = logVM(o);
  const body = o.entriesAttention ? banner(t('attnLog'), t('discard')) : `
    ${vm.open.length ? `${sec(t('secOpen'), String(vm.open.length))}${card(vm.open.map(x => ngRow(x, o)), '6px 18px')}` : ''}`;
  const rest = o.entriesAttention ? '' : `
    ${vm.obs.length ? `${sec(t('secObs'))}${card(vm.obs.map(obsRow), '6px 18px')}` : ''}
    ${vm.resolved.length ? `<div class="wrap mt24"><div class="card" style="padding:4px 18px">${disc(t('secResolved'), vm.resolved.length, o.showResolved)}${o.showResolved ? vm.resolved.map(x => `<div class="sep"></div>${resolvedRow(x)}`).join('') : ''}</div></div>` : ''}`;
  const pausedBlock = vm.paused.length || vm.resumed.length ? `${sec(t('secPaused'))}${card(vm.paused.map(pausedRow).concat(vm.resumed.length ? [disc(t('resumedDisc'), vm.resumed.length, o.showResumed) + (o.showResumed ? vm.resumed.map(p => `<div class="sep"></div>${resumedRow(p)}`).join('') : '')] : []), '6px 18px')}` : '';
  return `${top}${sec(t('secProf'), vm.prof && vm.rules.length && !o.rulesAttention ? t('edit') : '')}${profBlock(vm, o)}${body}${pausedBlock}${rest}
    <div style="height:14px"></div>${btn(t('logNiggle'), 'secondary', o.entriesAttention || o.limit)}${o.limit ? gf(t('limitLog', 500)) : ''}${btn(t('pauseExercise'))}${HOME}`;
}

/* ---------- niggle detail (§10.3) ---------- */
function detailScreen(o) {
  const vm = logVM({ ...o, only: null }), x = vm.rows.find(r => r.e.id === o.id), e = x ? x.e : FXT.entries.find(n => n.id === o.id), r = x && x.r;
  const head = lab => `${navbar('', null)}<div class="phase"><div class="lab">${lab}</div><div class="nm">${e.location}</div><div class="meta">${where(e)}</div></div>`;
  const actions = (...b) => `<div style="height:8px"></div>${b.join('')}<div class="wrap mt12"><div class="two"><div class="btn secondary">${t('edit')}</div><div class="btn danger">${t('del')}</div></div></div>`;
  let html;
  if (e.kind === 'observation') html = `${head(t('observation'))}<div class="wrap mt16"><div class="card"><div class="own">${e.note}</div><div class="lab" style="margin-top:8px">${t('noted', fd(e.onsetDay))}</div></div></div>${actions()}${HOME}`;
  else {
    const upd = (x.e.updates || []).slice().sort((a, b) => a.day < b.day ? 1 : -1).map(u => { const used = u.day >= x.c.onsetDay && u.day <= vm.today && (x.c.resolvedDay == null || u.day <= x.c.resolvedDay);
      if (!used && !o.asStored) return '';
      return `<div class="up${used ? '' : ' off'}"><div class="grow1"><div class="k">${t('trend.' + u.trend)}</div><div class="m">${u.weakness ? t('pvWith') : t('pvWithout')}</div>${u.note ? `<div class="m">${u.note}</div>` : ''}</div><div class="dt"><div class="d num">${fd(u.day)}</div>${used ? '' : `<div class="est">${t('notUsed')}</div>`}</div></div>`; }).filter(Boolean);
    upd.push(`<div class="up"><div class="grow1"><div class="k">${t('trend.' + e.trend)}</div><div class="m">${e.weakness ? t('pvWith') : t('pvWithout')}</div>${e.note ? `<div class="m">${e.note}</div>` : ''}</div><div class="dt"><div class="d num">${fd(e.onsetDay)}</div><div class="est">${t('onset')}</div></div></div>`);
    const updates = `${sec(t('secUpdates'))}${card(upd, '6px 18px')}${r.ignoredUpdates ? gf(r.ignoredUpdates === 1 ? t('ignored1', 1) : t('ignored', r.ignoredUpdates)) : ''}`;
    const linked = vm.paused.filter(p => p.niggleId === e.id);
    if (r.status === 'resolved') html = `${head(t('secResolved'))}<div class="wrap mt16"><div class="card tri"><div class="dcbig">${resolvedAfter(r.dayCount)}</div><div class="lab" style="margin-top:6px">${t('range', fd(e.onsetDay), fd(x.c.resolvedDay))}</div></div></div>${updates}${actions(btn(t('reopen')))}${HOME}`;
    else html = `${head(t('secOpen'))}<div class="wrap mt16"><div class="card tri"><div class="lab">${t('secRule')}</div><div class="dcbig num">${t('day', r.dayCount)}</div>
        ${o.rulesAttention ? `<div class="lbbig none">${t('rulesAttention')}</div>` : r.status === 'matched' ? `<div class="lbbig">${x.rule.label}</div><div class="acbig">${t('act.' + r.action)}</div>${x.rule.note ? `<div class="rt">${x.rule.note}</div>` : ''}<div class="rt t2 own2">${t('disclaimer')}</div>${x.also.length ? `<div class="rt t2">${t('also', x.also.map(a => a.label).join(', '))}</div>` : ''}`
          : `<div class="lbbig none">${t(r.status === 'noRulesEntered' ? 'noRules' : 'noneCovers')}</div>`}
        ${r.nextChange ? `<div class="sep" style="margin:14px 0 10px"></div><div class="lab">${t('next')}</div><div class="rt" style="margin-top:2px">${r.nextChange.ruleId ? t('nextRule', r.nextChange.dayCount, x.nextRule.label) : t('nextNone', r.nextChange.dayCount)}</div><div class="lab">${fd(r.nextChange.day)}</div>` : ''}
        ${x.before ? `<div class="rt t2">${x.before === 1 ? t('before1', 1) : t('before', x.before)}</div>` : ''}</div></div>
      ${updates}${linked.length ? `${sec(t('secPaused'))}${card(linked.map(pausedRow), '6px 18px')}` : ''}
      ${sec(t('secProf'))}${profBlock(vm, o)}${actions(btn(t('addUpdate'), 'primary'), btn(t('markResolved')))}${HOME}`;
  }
  return o.confirmDelete ? `<div class="dim">${html}</div>${confirmSheet(t('delEntryT'), t('delEntryD'))}` : html;
}

/* ---------- niggle sheet (§10.4) ---------- */
const CHARS = ['diffuse', 'localised', 'positional', 'other'], TRENDS = ['easing', 'unchanged', 'worsening', 'notRecorded'], SIDES = ['left', 'right', 'both', 'notApplicable'], ACTIONS = ['watch', 'modify', 'seeProfessional'];
const changeBlock = (trend, weakness) => `${gh(t('changing'))}${choice(TRENDS.map(k => t('trend.' + k)), TRENDS.indexOf(trend))}<div style="height:10px"></div>${card([tog(t('anyWeakness'), weakness)])}`;
function niggleSheet(o) {
  const e = o.e, today = o.today, locErr = o.loc === '' ? t('locEmpty') : (o.loc || e.location).trim().length > 60 ? t('locLong') : null, loc = o.loc == null ? e.location : o.loc;
  const tail = `${o.fail ? fail(o.fail) : ''}${HOME}`;
  if (o.mode === 'update') { const u = o.u; return `${modalBar(t('addUpdate'), o)}${gh(e.location, 1)}${card([prow(t('date'), whenIs(u.day, today), { chev: 1 })])}${gf(t('onsetToToday', fd(e.onsetDay)))}${changeBlock(u.trend, u.weakness)}
    ${gh(t('note'))}${field(t('note'), u.note, { ph: t('optional') })}${tail}`; }
  if (o.mode === 'resolve') return `${modalBar(t('markResolved'), o)}${gh(e.location, 1)}${card([prow(t('resolvedOn'), whenIs(o.day, today), { chev: 1 })])}${gf(t('onsetToToday', fd(e.onsetDay)))}${tail}`;
  const obs = e.kind === 'observation';
  return `${modalBar(o.mode === 'edit' ? t('editNiggle') : t('logNiggle'), { ...o, off: !!locErr })}${gh(t('kind'), 1)}${seg([t('complaint'), t('observation')], obs ? 1 : 0)}
    ${gh(t('location'))}${field(t('location'), loc, { focus: o.mode === 'add', bad: !!locErr, err: locErr })}
    ${gh(t('side'))}${seg(SIDES.map(k => t('side.' + k)), SIDES.indexOf(e.side))}
    ${obs ? '' : `${gh(t('character'))}${choice(CHARS.map(k => t('char.' + k)), CHARS.indexOf(e.character))}${changeBlock(e.trend, e.weakness)}`}
    ${gh(obs ? t('notedOn') : t('startedOn'))}${card([prow(t('date'), whenIs(e.onsetDay, today), { chev: 1 })])}${gf(o.mode === 'edit' && !obs ? t('editOnsetNote') : t('noFuture'))}
    ${gh(t('note'))}${field(t('note'), e.note, { ph: t('optional') })}${tail}`;
}

/* ---------- rules sheet (§10.5) ---------- */
const orJoin = list => list.join(` ${t('or')} `);
/** The read-back sentence, one <span> per §11 part. */
function preview(r) {
  const p = [r.characters.length ? t('pvChars', orJoin(r.characters.map(c => t('char.' + c)))) : t('pvAny')];
  if (r.trends.length) p.push(t('pvThatIs', orJoin(r.trends.map(c => t('trend.' + c)))));
  if (r.weakness != null) p.push(r.weakness ? t('pvWith') : t('pvWithout'));
  if (r.fromDay != null) p.push(t('pvFrom', r.fromDay));
  if (r.throughDay != null) p.push(t('pvThrough', r.throughDay));
  p.push(t('pvLabelled', r.label));
  return `<div class="pv">${p.map(s => `<span>${s}</span>`).join(' ')}</div>`;
}
const ruleIssue = r => !r.label.trim() ? 'labelEmpty' : r.fromDay != null && r.fromDay < 1 ? 'fromLow' : r.throughDay != null && r.throughDay < (r.fromDay == null ? 1 : r.fromDay) ? 'throughLow' : null;
const ruleCard = (r, drag) => `<div class="wrap mt8"><div class="card rc${drag ? ' drag' : ''}"><div class="top"><div class="grow1"><div class="k">${r.label}</div><div class="ac">${t('act.' + r.action)}</div></div><span data-ic="grip" data-s="20" class="grip"></span></div>${preview(r)}</div></div>`;
function rulesSheet(o) {
  const rules = o.rules || FXT.rules, prof = o.prof === undefined ? FXT.professionalRule : o.prof, full = rules.length >= 20;
  const html = `${modalBar(t('yourRules'))}${gh(t('secProf'), 1)}${field(t('secProf'), prof, { focus: !prof })}${gf(t('rulesCaption'))}
    ${gh(t('yourRules'))}${rules.map((r, i) => ruleCard(r, i === o.drag)).join('')}${rules.length > 1 ? gf(t('tie')) : ''}
    ${btn(t('addRule'), 'secondary', full)}${full ? gf(t('limitRules', 20)) : ''}${HOME}`;
  return o.confirmDelete ? `<div class="dim">${html}</div>${confirmSheet(t('delRuleT'), t('delRuleD'))}` : html;
}
function ruleEditor(r) {
  const issue = ruleIssue(r), valid = s6RulesAreValid([r]) && !issue;
  return `${modalBar(t('rule'), { off: !valid })}${gh(t('label'), 1)}${field(t('label'), r.label, { bad: issue === 'labelEmpty', err: issue === 'labelEmpty' ? t(issue) : null })}
    ${gh(t('action'))}${choice(ACTIONS.map(k => t('act.' + k)), ACTIONS.indexOf(r.action))}
    ${gh(t('whichChars'))}${choice(CHARS.map(k => t('char.' + k)), r.characters.map(c => CHARS.indexOf(c)))}${r.characters.length ? '' : gf(t('any'))}
    ${gh(t('whichTrends'))}${choice(TRENDS.map(k => t('trend.' + k)), r.trends.map(c => TRENDS.indexOf(c)))}${r.trends.length ? '' : gf(t('any'))}
    ${gh(t('weakness'))}${seg([t('either'), t('withW'), t('withoutW')], r.weakness == null ? 0 : r.weakness ? 1 : 2)}
    <div style="height:14px"></div>${card([prow(t('fromDay'), String(r.fromDay == null ? 1 : r.fromDay), { bad: issue === 'fromLow', strong: 1 }), prow(t('throughDay'), r.throughDay == null ? t('noEnd') : String(r.throughDay), { bad: issue === 'throughLow', strong: r.throughDay != null })])}
    ${issue && issue !== 'labelEmpty' ? gf(t(issue), 1) : ''}
    ${gh(t('note'))}${field(t('note'), r.note, { ph: t('optional') })}
    ${gh(t('reads'))}<div class="wrap"><div class="card" style="padding:14px 18px">${preview(r)}</div></div>
    <div class="wrap mt24"><div class="btn danger">${t('del')}</div></div>${HOME}`;
}

/* ---------- paused exercise sheet (§10.6) ---------- */
function pausedSheet(o) {
  const p = o.p, today = o.today, n = FXT.entries.find(e => e.id === p.niggleId), exErr = !p.exercise.trim() ? t('exEmpty') : null, rsErr = !p.reason.trim() ? t('reasonEmpty') : null;
  const html = `${modalBar(o.edit ? t('editPause') : t('pauseExercise'), { off: !!(exErr || rsErr) })}${gh(t('exercise'), 1)}${field(t('exercise'), p.exercise, { bad: !!exErr, err: exErr, focus: !p.exercise })}
    ${gh(t('reason'))}${field(t('reason'), p.reason, { bad: !!rsErr, err: rsErr })}
    ${gh(t('until'))}${field(t('until'), p.until, { ph: t('optional') })}
    <div style="height:14px"></div>${card([prow(t('pausedOn'), whenIs(p.pausedDay, today), { chev: 1 }), prow(t('linkedNiggle'), n ? n.location : t('none'), { chev: 1 })])}
    ${o.edit ? `<div style="height:14px"></div>${card(p.resumedDay ? [tog(t('markResumed'), 1), prow(t('resumedOn'), whenIs(p.resumedDay, today), { chev: 1 })] : [tog(t('markResumed'), 0)])}<div class="wrap mt24"><div class="btn danger">${t('del')}</div></div>` : ''}${HOME}`;
  return o.confirmDelete ? `<div class="dim">${html}</div>${confirmSheet(t('delPauseT'), t('delPauseD'))}` : html;
}

/* ================= (b) RECOVERY CONTEXT ================= */
const METRICS = [{ title: 'rhr', mean: 'restingHrMean', n: 'restingHrNights', change: 'restingHrChange', unit: 'bpm', key: 'restingHr' },
  { title: 'hrv', mean: 'hrvMean', n: 'hrvNights', change: 'hrvChange', unit: 'ms', key: 'hrv' }];
const val = (v, unit) => `<span class="num">${v}</span><small>${t(unit)}</small>`;
function metricCard(res, m, o) {
  const W = res.weeks, has = W.filter(w => w[m.mean] != null), cur = W[W.length - 1], any = W.some(w => w[m.n] > 0), ch = res[m.change];
  const typical = o.calibrating || !any ? `<div class="lab mt12">${t('calibrating')}</div>` : `<div class="kvr mt12"><span class="lab">${t('typical')}</span><span class="tv">${val(t('range', FXT.typical[m.key][0], FXT.typical[m.key][1]), m.unit)}</span></div>`;
  const head = `<div class="lab">${t(m.title)}</div>`;
  if (!any) return `<div class="card cv">${head}<div class="big num none" style="margin-top:6px">—</div><div class="lab" style="margin-top:8px">${t('notMeasuredStrap')}</div></div>`;
  const soFar = cur && cur.isCurrentWeek && cur[m.mean] == null && cur[m.n] > 0 ? `<div class="lab mt12">${t('soFarNights', cur[m.n], 4)}</div>` : '';
  const weekRows = list => list.map(w => `<div class="kvr"><span class="lab">${t('weekOfCap', sd(w.weekStart))}</span><span class="lab">${w[m.n] ? t('nights', w[m.n]) : t('notMeasuredLower')}</span></div>`).join('');
  if (!has.length) return `<div class="card cv">${head}<div class="big num none" style="margin-top:6px">—</div><div class="lab" style="margin:8px 0 10px">${t('notMeasured')}</div>${weekRows(W)}${typical}</div>`;
  const latest = has[has.length - 1], first = has[0], series = W.map(w => w[m.mean]);
  if (cur.isCurrentWeek && cur[m.mean] == null && cur[m.n] > 0) series.pop();          // the curve ends at the last full week
  const later = W.filter(w => w.weekStart > latest.weekStart && w[m.n] === 0);            // nights stopped arriving: said, never drawn as a value
  const shown = W.slice(0, series.length);
  return `<div class="card cv">${head}<div class="lab l2">${t('latest')}${latest.isCurrentWeek ? `<span class="est">${t('soFar')}</span>` : ''}</div>
    <div class="big">${val(one(latest[m.mean]), m.unit)}</div><div class="src" style="margin-top:8px"><i></i>${t('weekOf', sd(latest.weekStart))} · ${t('nights', latest[m.n])}</div>
    ${has.length > 1 ? weekChart(series, sd(shown[0].weekStart), sd(shown[shown.length - 1].weekStart), o.ax ? { w: 330, fs: 24 } : {}) : ''}
    <div class="kv">${has.length > 1 ? `<div><div class="k">${t('firstWeek')}</div><div class="v">${val(one(first[m.mean]), m.unit)}</div><div class="k">${t('weekOf', sd(first.weekStart))}</div></div>` : ''}
      <div><div class="k">${t('change')}</div>${ch ? `<div class="v">${val(signed(ch.delta), m.unit)}</div>` : `<div class="v none sm">${t('needsSecond')}</div>`}</div></div>
    ${soFar}${later.length ? `<div class="mt12">${weekRows(later)}</div>` : ''}${typical}</div>`;
}
/** o: { today, first: firstWeekStart or null (no cut phase started), nights, calibrating, ax } */
function stressScreen(o) {
  const top = navbar(t('recoveryContext'), null), first = o.first === undefined ? '2031-01-06' : o.first;
  if (o.loading) return `${top}<div class="phase">${skb('90px', 13)}${skb('100%', 13, 12)}${skb('100%', 13, 7)}${skb('62%', 13, 7)}</div>
    ${[0, 1].map(() => `<div class="wrap mt16"><div class="card">${skb('130px', 13)}${skb('120px', 40, 12)}${skb('170px', 12, 10)}${skb('100%', 110, 16)}${skb('70%', 14, 16)}</div></div>`).join('')}${HOME}`;
  const res = s6Weekly({ nights: o.nights || FXT.nights, firstWeekStart: first, today: o.today, minNightsPerWeek: 4, maxWeeks: first ? 26 : 12 });
  return `${top}<div class="phase"><div class="lab">${first ? t('sinceCap', sd(first)) : t('last12')}</div><div class="meta fr">${t('framing')}</div></div>
    ${METRICS.map(m => `<div class="wrap mt16">${metricCard(res, m, o)}</div>`).join('')}${HOME}`;
}

/* ================= (c) CHECKPOINT TIMELINE ================= */
// Quiet marks: neutral greys only. An estimate is a dashed ring, the same vocabulary as "unknown" in round 6.
const BG = '<circle cx="10" cy="10" r="9.5" fill="#151518"/>';
const MARK = {
  phaseStart: `${BG}<rect x="5.6" y="5.6" width="8.8" height="8.8" rx="2" transform="rotate(45 10 10)" fill="#F5F5F7"/>`,
  scan: `${BG}<rect x="5" y="5" width="10" height="10" rx="2.6" fill="none" stroke="#9B9BA3" stroke-width="1.7"/>`,
  checkpoint: `${BG}<circle cx="10" cy="10" r="5" fill="none" stroke="#9B9BA3" stroke-width="1.7"/>`,
  done: `${BG}<circle cx="10" cy="10" r="6.4" fill="#F5F5F7" fill-opacity=".9"/><polyline points="7.1,10.2 9.2,12.3 13,8" fill="none" stroke="#000" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round"/>`,
  span: `${BG}<rect x="7.4" y="3.6" width="5.2" height="12.8" rx="2.6" fill="none" stroke="#9B9BA3" stroke-width="1.7"/>`,
  spanNow: `${BG}<rect x="7.4" y="3.6" width="5.2" height="12.8" rx="2.6" fill="#F5F5F7"/>`,
  projection: `${BG}<circle cx="10" cy="10" r="5.4" fill="none" stroke="#FFFFFF" stroke-opacity=".5" stroke-width="1.6" stroke-dasharray="2.6 2.6"/>`,
};
const mark = k => `<svg class="mk" width="20" height="20" viewBox="0 0 20 20">${MARK[k]}</svg>`;
function tlRow(it, inp, o) {
  const ph = inp.phases, cp = it.kind === 'checkpoint' ? inp.checkpoints[it.sourceIndex] : null, L = [], tags = [];
  let mk = it.kind, title, date = '';
  if (it.kind === 'phaseStart') { const p = ph[it.sourceIndex]; title = t(it.position === 'upcoming' ? 'starts' : 'started', p.name, fd(it.day)); if (it.targetWeightKg != null) L.push(`<div class="m lk">${t('target', kg(it.targetWeightKg))}</div>`); }
  else if (it.kind === 'scan') { title = t('scan'); date = fd(it.day); }
  else if (it.kind === 'dietBreak' || it.kind === 'deload') { title = t(it.kind); mk = it.position === 'current' ? 'spanNow' : 'span';
    L.push(`<div class="m">${it.isOpenEnded ? t('sinceCap', sd(it.day)) : t('range', sd(it.day), sd(it.endDay))}</div>`); if (it.position === 'current') tags.push(t('now')); }
  else if (it.kind === 'projection') { const g = s6GoverningPhaseIndex(inp.today, ph); title = t('estimated', fd(it.day)); tags.push(t('estimate'));
    if (g != null && ph[g].targetWeightKg != null) L.push(`<div class="m">${t('target', kg(ph[g].targetWeightKg))}</div>`); }
  else {
    date = it.isApproximate ? t('around', fd(it.day)) : fd(it.day); mk = it.isDone && it.position !== 'upcoming' ? 'done' : 'checkpoint';
    if (it.category === 'targetDate' && it.phaseIndex != null) { title = t('targetDateFor', ph[it.phaseIndex].name); if (ph[it.phaseIndex].targetWeightKg != null) L.push(`<div class="m lk">${t('target', kg(ph[it.phaseIndex].targetWeightKg))}</div>`); }
    else if (it.category === 'targetDate') { title = t('targetDate'); L.push(`<div class="m">${cp.title}</div>`); }
    else { title = cp.title; L.push(`<div class="m">${t('cat.' + it.category)}</div>`); }
    if (it.waypointWeightKg != null) L.push(`<div class="m w">${t('waypoint', kg(it.waypointWeightKg))}</div>`);
    const done = it.isDone && it.position !== 'upcoming';   // §9.3: done may be set only on or after its day
    if (done) L.push(`<div class="m">${t('done')}</div>`); else if (it.position === 'past') L.push(`<div class="m">${t('notDone')}</div>`);
  }
  return `<div class="tl">${mark(mk)}<div class="grow1"><div class="k">${title}</div>${L.join('')}</div>${date || tags.length ? `<div class="dt">${date ? `<div class="d num">${date}</div>` : ''}${tags.map(g => `<div class="est">${g}</div>`).join('')}</div>` : ''}</div>`;
}
/** o: timeline input overrides plus { phasesAttention, cpAttention, scorecardOff, rail, loading, limit } */
function timelineScreen(o) {
  const top = navbar(t('timeline'), o.cpAttention || o.limit ? null : 'plus');
  if (o.loading) return `${top}${sec(t('earlier'))}${skCard(3)}${sec(t('today'))}${sec(t('ahead'))}${skCard(4)}${HOME}`;
  const inp = s6TimelineInput({ ...o, phases: o.phasesAttention ? [] : o.phases, checkpoints: o.cpAttention ? [] : o.checkpoints, projection: o.scorecardOff || o.phasesAttention ? null : o.projection });
  const res = s6Timeline(inp), items = res.items, ti = res.todayIndex;
  const before = items.slice(0, ti), lastPast = before.map(i => i.position).lastIndexOf('past');
  const earlier = before.slice(0, lastPast + 1), now = before.slice(lastPast + 1), ahead = items.slice(ti + 1);
  const block = list => list.length ? `<div class="wrap"><div class="card tlc${o.rail ? ' rail' : ''}" style="padding:6px 18px">${o.rail ? '<i class="railine"></i>' : ''}${list.map(i => tlRow(i, inp, o)).join(o.rail ? '' : '<div class="sep"></div>')}</div></div>` : '';
  const notes = [];
  if (o.cpAttention) notes.push(banner(t('attnCheckpoints'), t('discard')));
  if (res.rejections.waypointBeyondTarget) notes.push(`${gf(t('fnWaypoint'))}<div class="wrap">${link(t('openCheckpoint'))}</div>`);
  if (res.scans === 'off') notes.push(gf(t('fnScans')));
  if (res.events === 'off') notes.push(gf(t('fnEvents')));
  if (o.scorecardOff) notes.push(gf(t('fnEstimate')));
  if (o.phasesAttention) notes.push(`${gf(t('attnPhases'))}<div class="wrap">${link(t('openPhase'))}</div>`);
  if (items.length === 1) return `${top}<div class="wrap" style="margin-top:28px"><div class="card empty"><div class="et" style="margin-top:0">${t('nothingYet')}</div></div></div>${btn(t('addCheckpoint'), 'primary')}${!inp.phases.length && !o.scorecardOff ? btn(t('setUpPhase')) : ''}${notes.join('')}${HOME}`;
  return `${top}${earlier.length ? `${sec(t('earlier'))}${block(earlier)}` : ''}${sec(t('today'), fd(inp.today))}${block(now)}${ahead.length ? `${sec(t('ahead'))}${block(ahead)}` : ''}
    ${notes.join('')}<div style="height:8px"></div>${btn(t('addCheckpoint'), 'secondary', o.cpAttention || o.limit)}${o.limit ? gf(t('limitCheckpoints', 200)) : ''}${HOME}`;
}

/* ---------- checkpoint sheet (§10.8) ---------- */
const CATS = ['scan', 'bloodPanel', 'benchmark', 'weightWaypoint', 'targetDate', 'appointment', 'other'];
/** o: { d: draft, today, phases, others, edit, allCats, fail, confirmDelete } — every message is the model's CheckpointIssue for that draft. */
function cpSheet(o) {
  const d = o.d, today = o.today, phases = o.phases || FXT.phases, others = o.others || FXT.checkpoints.filter(c => c.id !== d.id);
  const issue = s6CheckpointIssue(d, others, phases), wIssue = s6CheckpointIssue({ ...d, title: d.title || 'x' }, others, phases);
  const wp = d.category === 'weightWaypoint', td = d.category === 'targetDate', sel = phases.find(p => p.startDay === d.phaseStartDay);
  const g = s6GoverningPhaseIndex(d.day, phases), wBad = ['weightMissing', 'weightOutOfRange', 'waypointAtOrBeyondTarget'].includes(wIssue);
  const html = `${modalBar(o.edit ? t('editCheckpoint') : t('addCheckpoint'), { off: !!issue })}${gh(t('title'), 1)}${field(t('title'), d.title, { focus: !d.title, bad: issue === 'emptyTitle' || issue === 'titleTooLong', err: issue === 'emptyTitle' ? t('titleEmpty') : issue === 'titleTooLong' ? t('titleLong') : null })}
    ${o.allCats ? gh(t('category')) + choice(CATS.map(k => t('cat.' + k)), CATS.indexOf(d.category)) : '<div style="height:14px"></div>' + card([prow(t('category'), t('cat.' + d.category), { chev: 1, strong: 1 })])}
    <div style="height:14px"></div>${card([prow(t('date'), whenIs(d.day, today), { chev: 1, bad: issue === 'targetDateNotAfterPhaseStart' }), tog(t('approximate'), d.isApproximate)].concat(d.day <= today ? [tog(t('done'), d.isDone)] : []))}
    ${issue === 'targetDateNotAfterPhaseStart' ? gf(t('afterStart'), 1) : ''}
    ${wp ? `${gh(t('weight'))}${field(t('weight'), d.waypointWeightKg == null ? '' : kg(d.waypointWeightKg), { bad: wBad })}
      ${wIssue === 'waypointAtOrBeyondTarget' ? `${gf(t('wpShort', kg(phases[g].targetWeightKg)), 1)}<div class="wrap">${link(t('editPhase'))}</div>` : wIssue === 'weightOutOfRange' ? gf(t('weightRange'), 1) : wIssue === 'weightMissing' ? gf(t('weightMissing'), 1) : gf(t('wpCaption'))}` : ''}
    ${td ? `${gh(t('phase'))}${phases.length ? `${choice(phases.map(p => p.name), phases.indexOf(sel))}${sel && sel.targetWeightKg != null ? gf(t('target', kg(sel.targetWeightKg))) : ''}<div class="wrap">${link(t('editPhase'))}</div>` : `<div class="wrap"><div class="card" style="padding:14px 18px"><div class="quiet">${t('phaseFirst')}</div>${link(t('setUpPhase'))}</div></div>`}
      ${issue === 'phaseAlreadyHasTargetDate' ? `${gf(t('hasTargetDate'), 1)}<div class="wrap">${link(t('openThat'))}</div>` : ''}` : ''}
    ${o.fail ? fail(o.fail) : ''}${o.edit ? `<div class="wrap mt24"><div class="btn danger">${t('del')}</div></div>` : ''}${HOME}`;
  return o.confirmDelete ? `<div class="dim">${html}</div>${confirmSheet(t('delCpT'), t('delCpD'))}` : html;
}

/* ================= FRAMES ================= */
const G = []; let curGroup;
const group = (title, note) => { curGroup = { title, note, frames: [] }; G.push(curGroup); };
const frame = (id, title, html, o = {}) => curGroup.frames.push({ id, name: `${id} ${title}`, html, ...o });
const AX = { cls: 'ax' };
const E = id => FXT.entries.find(e => e.id === id), CP = id => FXT.checkpoints.find(c => c.id === id), P = id => FXT.paused.find(p => p.id === id);

group('A · Niggle log (§10.2)', 'Sections top to bottom: the owner\'s rule for seeing a professional, open complaints, paused exercises, observations, resolved. Each frame is the §13 fixture as the store stood on the stated day, run through the design model of §7.1. A label is the owner\'s own text; the action is a plain word. No colour carries a label, and nothing here names a cause.');
frame('A1', 'Niggle log · open complaint, rule matched', logScreen({ today: '2031-03-22' }), { note: 'Sat 22 Mar 2031 (fixture row N2d). Two rules match; the more serious action shows. The next change line is what the owner\'s rules say on day 30.' });
frame('A2', 'Niggle log · loading', logScreen({ loading: 1 }), { still: 1 });
frame('A3', 'Niggle log · first use, nothing stored', logScreen({ firstUse: 1 }));
frame('A4', 'Niggle log · no rules entered', logScreen({ today: '2031-03-22', rules: [], prof: '' }), { note: 'No rule ships with the app. Each open row shows its day count and "No rules entered yet".' });
frame('A5', 'Niggle log · rules entered, professional rule empty', logScreen({ today: '2031-03-22', prof: '' }));
frame('A6', 'Niggle log · open complaint, no rule matches', logScreen({ today: '2031-05-14', only: ['N5', 'N4'] }), { note: 'Wed 14 May (fixture row N5).' });
frame('A7', 'Niggle log · next change to no rule', logScreen({ today: '2031-06-11', only: ['N6', 'N4'] }), { note: 'Wed 11 Jun (fixture row N6a). The owner\'s rule A stops at day 10.' });
frame('A8', 'Niggle log · complaint seen again', logScreen({ today: '2031-06-16', only: ['N2', 'N7'], paused: [] }), { note: 'Mon 16 Jun: the second "Fixture location B", right. It is a new entry with its own day count.' });
frame('A9', 'Niggle log · several open', logScreen({ today: '2031-06-11' }), { note: 'Sorted by action severity, then day count, then location.' });
frame('A10', 'Niggle log · resumed exercises shown', logScreen({ today: '2031-03-22', showResumed: 1 }));
frame('A11', 'Niggle log · resolved shown', logScreen({ today: '2031-03-22', showResolved: 1 }), { note: 'Resolved entries carry no label.' });
frame('A12', 'Niggle log · no paused exercises', logScreen({ today: '2031-02-05', paused: [] }), { note: 'Wed 5 Feb. The section is absent.' });
frame('A13', 'Niggle log · entries need attention', logScreen({ today: '2031-03-22', entriesAttention: 1 }), { still: 1 });
frame('A14', 'Niggle log · rules need attention', logScreen({ today: '2031-03-22', rulesAttention: 1 }), { still: 1 });
frame('A15', 'Niggle log · limit reached', logScreen({ today: '2031-06-11', limit: 1 }), { still: 1, note: 'The list is drawn with the fixture\'s entries; the state is the disabled action and the named limit.' });
frame('A16', 'Niggle log · AX5', logScreen({ today: '2031-03-22' }), AX);

group('B · Niggle detail (§10.3)', 'Day count, the owner\'s label and action, the owner\'s rule note, the fixed sentence under every label, the next change, updates newest first, linked paused exercises, the professional rule verbatim.');
frame('B1', 'Niggle detail · open, rule matched', detailScreen({ today: '2031-03-22', id: 'N2' }), { note: 'Fixture row N2d.' });
frame('B2', 'Niggle detail · open, no rule matches', detailScreen({ today: '2031-05-14', id: 'N5' }));
frame('B3', 'Niggle detail · no rules entered', detailScreen({ today: '2031-03-22', id: 'N2', rules: [], prof: '' }));
frame('B4', 'Niggle detail · rules need attention', detailScreen({ today: '2031-03-22', id: 'N2', rulesAttention: 1 }), { still: 1 });
frame('B5', 'Niggle detail · resolved', detailScreen({ today: '2031-03-01', id: 'N1' }), { note: 'Fixture row N1.' });
frame('B6', 'Niggle detail · observation', detailScreen({ today: '2031-03-22', id: 'N4' }));
frame('B7', 'Niggle detail · an update not used', detailScreen({ today: '2031-03-21', id: 'N2', asStored: 1 }), { note: 'Fixture row N2c: the stored update is dated outside the complaint as it stands on Fri 21 Mar, so it is kept, marked and not used.' });
frame('B8', 'Niggle detail · delete asks once', detailScreen({ today: '2031-03-22', id: 'N2', confirmDelete: 1 }), { still: 1 });
frame('B9', 'Niggle detail · AX5', detailScreen({ today: '2031-03-22', id: 'N2' }), AX);

group('C · Niggle sheet (§10.4)', 'Add, edit, update and resolve. Kind, location, side, character, how it is changing, weakness, the date and a note.');
frame('C1', 'Niggle sheet · add a complaint', niggleSheet({ mode: 'add', e: { ...E('N2'), updates: [] }, today: '2031-03-03' }), { still: 1 });
frame('C2', 'Niggle sheet · add an observation', niggleSheet({ mode: 'add', e: E('N4'), today: '2031-01-13' }), { still: 1 });
frame('C3', 'Niggle sheet · location empty', niggleSheet({ mode: 'add', e: E('N2'), loc: '', today: '2031-03-03' }), { still: 1 });
frame('C4', 'Niggle sheet · location too long', niggleSheet({ mode: 'add', e: E('N2'), loc: 'Fixture location ' + 'that keeps going '.repeat(3) + 'well past sixty', today: '2031-03-03' }), { still: 1 });
frame('C5', 'Niggle sheet · edit', niggleSheet({ mode: 'edit', e: E('N2'), today: '2031-03-22' }), { still: 1 });
frame('C6', 'Niggle sheet · add update', niggleSheet({ mode: 'update', e: E('N2'), u: E('N2').updates[0], today: '2031-03-22' }), { still: 1 });
frame('C7', 'Niggle sheet · mark resolved', niggleSheet({ mode: 'resolve', e: E('N1'), day: '2031-02-12', today: '2031-02-12' }), { still: 1 });
frame('C8', 'Niggle sheet · saving', niggleSheet({ mode: 'add', e: E('N2'), today: '2031-03-03', busy: 1 }), { still: 1 });
frame('C9', 'Niggle sheet · save refused', niggleSheet({ mode: 'add', e: E('N2'), today: '2031-03-03', fail: t('limitLog', 500) }), { still: 1 });
frame('C10', 'Niggle sheet · AX5', niggleSheet({ mode: 'add', e: E('N2'), today: '2031-03-03' }), AX);

const moved = FXT.rules.slice(); moved.splice(2, 0, moved.splice(3, 1)[0]);
const filler = 'FGHIJKLMNOPQRST'.split('').map((c, i) => ({ id: 'r-' + c.toLowerCase(), label: 'Fixture label ' + c, action: ACTIONS[i % 3], characters: [], trends: [], weakness: null, fromDay: 40 + 10 * i, throughDay: null, note: '' }));
group('D · Rules sheet (§10.5)', 'The owner writes every rule. The sheet starts empty; each rule is read back as a sentence built from its fields.');
frame('D1', 'Rules sheet · first use', rulesSheet({ rules: [], prof: '' }), { still: 1 });
frame('D2', 'Rules sheet · rules entered', rulesSheet({}), { still: 1, note: 'The five rules of §13.1.' });
frame('D3', 'Rules sheet · a rule', ruleEditor(FXT.rules[1]), { still: 1 });
frame('D4', 'Rules sheet · reorder', rulesSheet({ rules: moved, drag: 2 }), { still: 1 });
frame('D5', 'Rules sheet · a value that cannot be saved', ruleEditor({ ...FXT.rules[0], fromDay: 12 }), { still: 1 });
frame('D6', 'Rules sheet · delete a rule asks once', rulesSheet({ confirmDelete: 1 }), { still: 1 });
frame('D7', 'Rules sheet · limit', rulesSheet({ rules: FXT.rules.concat(filler) }), { still: 1, note: 'Rules F to T are placeholders added to reach the limit of 20; they are not in §13.' });
frame('D8', 'Rules sheet · AX5', rulesSheet({}), AX);

group('E · Paused exercise sheet (§10.6)', 'Exercise, reason (required), until, the date, an optional link to an open niggle.');
frame('E1', 'Paused exercise · add', pausedSheet({ p: P('p1'), today: '2031-03-10' }), { still: 1 });
frame('E2', 'Paused exercise · reason empty', pausedSheet({ p: { ...P('p1'), reason: '' }, today: '2031-03-10' }), { still: 1 });
frame('E3', 'Paused exercise · edit, mark resumed', pausedSheet({ p: P('p2'), edit: 1, today: '2031-02-10' }), { still: 1 });
frame('E4', 'Paused exercise · delete asks once', pausedSheet({ p: P('p1'), edit: 1, today: '2031-03-22', confirmDelete: 1 }), { still: 1 });
frame('E5', 'Paused exercise · AX5', pausedSheet({ p: P('p1'), today: '2031-03-10' }), AX);

const dropRhr = FXT.nights.map(n => ({ ...n, restingHr: null }));
group('F · Recovery context (§10.7)', 'Weekly averages of nightly resting heart rate and HRV on the scorecard\'s Monday weeks. Neutral colour, no adjective, no band, no current value. Each frame is the §13.3 nights on the stated day, run through the design model of §7.2.');
frame('F1', 'Recovery context · default, current week below the minimum', stressScreen({ today: '2031-02-05' }), { note: 'Wed 5 Feb 2031, the §13.3 case. The curve ends at the last full week and breaks at the week of 20 Jan (3 nights).' });
frame('F2', 'Recovery context · loading', stressScreen({ loading: 1 }), { still: 1 });
frame('F3', 'Recovery context · current week at or above the minimum', stressScreen({ today: '2031-01-16' }), { note: 'Thu 16 Jan: four nights this week.' });
frame('F4', 'Recovery context · a week below the minimum in the middle', stressScreen({ today: '2031-02-02' }), { note: 'Sun 2 Feb.' });
frame('F5', 'Recovery context · only one week has a mean', stressScreen({ today: '2031-01-14' }));
frame('F6', 'Recovery context · no week has a mean', stressScreen({ today: '2031-01-08' }));
frame('F7', 'Recovery context · no nights at all', stressScreen({ today: '2031-02-05', nights: [] }));
frame('F8', 'Recovery context · typical range not available', stressScreen({ today: '2031-02-05', calibrating: 1 }));
frame('F9', 'Recovery context · HRV present, resting heart rate absent', stressScreen({ today: '2031-02-05', nights: dropRhr }));
frame('F10', 'Recovery context · no cut phase started', stressScreen({ today: '2031-02-05', first: null }), { note: 'The latest 12 weeks; here the nights begin on 30 Dec.' });
frame('F11', 'Recovery context · strap disconnected or removed', stressScreen({ today: '2031-02-26' }), { note: 'Wed 26 Feb: no night after Sun 9 Feb. Stored weeks stay; later weeks read "not measured".' });
frame('F12', 'Recovery context · AX5', stressScreen({ today: '2031-02-05', ax: 1 }), AX);

group('G · Timeline (§10.8)', 'One list, oldest first, built by the design model of §7.3 from the §13.4 inputs. The list is the time axis: each item is a row with a quiet mark; a span is a row, not a bar. An estimate is tagged. A private event has no row.');
frame('G1', 'Timeline · phases, scans, checkpoints, events and the estimate', timelineScreen({ today: '2031-02-05' }), { note: 'Wed 5 Feb 2031, the first §13.4 case.' });
frame('G2', 'Timeline · loading', timelineScreen({ loading: 1 }), { still: 1 });
frame('G3', 'Timeline · nothing but today', timelineScreen({ today: '2031-02-05', phases: [], checkpoints: [], scanDays: [], spans: [], projection: null }));
frame('G4', 'Timeline · past items, a break running now', timelineScreen({ today: '2031-03-24' }), { note: 'Mon 24 Mar, the second §13.4 case: a done and a not-done checkpoint, a past deload, the recorded scan standing for the planned one, an open-ended diet break tagged "now".' });
frame('G5', 'Timeline · a deload running now', timelineScreen({ today: '2031-02-20' }), { note: 'Thu 20 Feb.' });
frame('G6', 'Timeline · waypoint at or past the target', timelineScreen({ today: '2031-02-05', phases: [{ ...FXT.phases[0], targetWeightKg: 96.0 }, FXT.phases[1]] }), { note: 'The §13.4 changed-target variant: the phase target is now 96.0 kg.' });
frame('G7', 'Timeline · target date, phase no longer stored', timelineScreen({ today: '2031-02-05', phases: [FXT.phases[1]], projection: null }));
frame('G8', 'Timeline · events off, scorecard off', timelineScreen({ today: '2031-02-20', events: 'off', scorecardOff: 1 }), { note: 'The third §13.4 case.' });
frame('G9', 'Timeline · body record off', timelineScreen({ today: '2031-02-05', scans: 'off' }));
frame('G10', 'Timeline · later stages not in this build', timelineScreen({ today: '2031-02-05', scans: 'notBuilt', events: 'notBuilt' }), { note: 'No scan, break or deload rows and no mention of them.' });
frame('G11', 'Timeline · no projection', timelineScreen({ today: '2031-02-05', projection: { status: 'notLosing', targetDay: null } }), { note: 'No item and nothing said; the scorecard explains why.' });
frame('G12', 'Timeline · a private event is absent', timelineScreen({ today: '2031-04-10', spans: s6TimelineSpans(FXT.events) }), { note: 'Thu 10 Apr, the §13.4 adapter fixture: the private deload of 7 to 13 Apr and the travel event have no row, placeholder or count.' });
frame('G13', 'Timeline · checkpoints need attention', timelineScreen({ today: '2031-02-05', cpAttention: 1 }), { still: 1 });
frame('G14', 'Timeline · phases need attention', timelineScreen({ today: '2031-02-05', phasesAttention: 1 }), { still: 1 });
frame('G15', 'Timeline · limit reached', timelineScreen({ today: '2031-02-05', limit: 1 }), { still: 1 });
frame('G16', 'Timeline · AX5', timelineScreen({ today: '2031-02-05' }), AX);

group('H · Checkpoint sheet (§10.8)', 'Title, category, date, approximate, done. A weight is a waypoint and never a target; a target date belongs to a phase and carries no weight. Every message is the model\'s answer for the draft shown.');
frame('H1', 'Checkpoint sheet · add, any category', cpSheet({ d: CP('C2'), today: '2031-02-05', allCats: 1 }), { still: 1 });
frame('H2', 'Checkpoint sheet · edit, done', cpSheet({ d: CP('C2'), today: '2031-03-24', edit: 1 }), { still: 1 });
frame('H3', 'Checkpoint sheet · weight waypoint', cpSheet({ d: CP('C1'), today: '2031-02-05' }), { still: 1 });
frame('H4', 'Checkpoint sheet · waypoint at or beyond the target', cpSheet({ d: { ...CP('C1'), waypointWeightKg: 94.0 }, today: '2031-02-05' }), { still: 1 });
frame('H5', 'Checkpoint sheet · target date', cpSheet({ d: CP('C5'), today: '2031-02-05' }), { still: 1 });
frame('H6', 'Checkpoint sheet · target date, no stored phase', cpSheet({ d: CP('C5'), today: '2031-02-05', phases: [] }), { still: 1 });
frame('H7', 'Checkpoint sheet · target date not after the phase start', cpSheet({ d: { ...CP('C5'), day: '2031-01-06' }, today: '2031-02-05' }), { still: 1 });
frame('H8', 'Checkpoint sheet · the phase already has a target date', cpSheet({ d: { ...CP('C5'), id: '', day: '2031-06-09' }, today: '2031-02-05', others: FXT.checkpoints }), { still: 1 });
frame('H9', 'Checkpoint sheet · other invalid input', cpSheet({ d: { ...CP('C1'), title: '', waypointWeightKg: 260 }, today: '2031-02-05' }), { still: 1 });
frame('H10', 'Checkpoint sheet · save refused', cpSheet({ d: CP('C4'), today: '2031-02-05', fail: t('limitCheckpoints', 200) }), { still: 1 });
frame('H11', 'Checkpoint sheet · delete asks once', cpSheet({ d: CP('C4'), today: '2031-02-05', edit: 1, confirmDelete: 1 }), { still: 1 });
frame('H12', 'Checkpoint sheet · AX5', cpSheet({ d: CP('C1'), today: '2031-02-05' }), AX);

group('P1 · Choice: which label shows when several rules fit (Q2)', 'The same complaint on the same day (fixture row N2d): rules B and D both match. P1.1 is the specification\'s default.');
frame('P1.1', 'Label choice · the most serious action (default)', logScreen({ today: '2031-03-22', only: ['N2'], paused: [] }));
frame('P1.2', 'Label choice · the first matching rule in the owner\'s order', logScreen({ today: '2031-03-22', only: ['N2'], paused: [], opt: { firstMatch: true } }));
group('P2 · Choice: the day count on the day it started (Q3)', 'Fixture row N2a, Mon 3 Mar, the onset day. P2.1 is the specification\'s default.');
frame('P2.1', 'Day count · day 1 on the onset day (default)', logScreen({ today: '2031-03-03', only: ['N2'], paused: [] }));
frame('P2.2', 'Day count · day 0 on the onset day', logScreen({ today: '2031-03-03', only: ['N2'], paused: [], opt: { dayZero: true } }));
group('P3 · Choice: how the timeline shows its time axis', 'The specification says the list itself is the axis. P3.1 draws separate rows, each with its own mark. P3.2 joins the marks with one quiet vertical line. Neither draws a horizontal rule, a band or a bar.');
frame('P3.1', 'Timeline axis · separate rows (as specified)', timelineScreen({ today: '2031-02-05' }));
frame('P3.2', 'Timeline axis · marks on one vertical line', timelineScreen({ today: '2031-02-05', rail: 1 }));

if (S6_NODE) module.exports = { G, weekChart, logVM };

/* ================= browser only ================= */
if (!S6_NODE) {
  // Local icon (noop.js ICONS is not edited; ic('trash') resolves #i-trash).
  document.body.insertAdjacentHTML('afterbegin', `<svg width="0" height="0" style="position:absolute"><defs>
<symbol id="i-trash" viewBox="0 0 24 24"><path d="M5 7h14M10 4h4M7 7l1 12.5h8L17 7M10.5 11v5M13.5 11v5" fill="none" stroke="currentColor" stroke-width="1.9" stroke-linecap="round" stroke-linejoin="round"/></symbol></defs></svg>`);
  // ?only=F (or ?only=F1) shows just the frames whose id starts with that text. Handy for review; not used for export.
  const ONLY = new URLSearchParams(location.search).get('only');
  if (ONLY) { G.forEach(g => g.frames = g.frames.filter(f => f.name.startsWith(ONLY))); for (let i = G.length - 1; i >= 0; i--) if (!G[i].frames.length) G.splice(i, 1); }
  document.getElementById('boards').innerHTML = G.map(g => `<h2 class="grp-title">${g.title}</h2><p class="grp-note">${g.note}</p><div class="board">${g.frames.map(f =>
    `<section><div class="board-title">S6 / ${f.name}</div><div class="screen${f.cls ? ' ' + f.cls : ''}"${f.still ? ' data-nomotion' : ''}>${f.html}</div>${f.note ? `<p class="fnote">${f.note}</p>` : ''}</section>`).join('')}</div>`).join('');
  boot();
  if (!STATIC) {
    const draw = () => setTimeout(() => document.querySelectorAll('.screen:not([data-nomotion]) svg.wk').forEach(drawLine), 1150);
    draw(); document.getElementById('replay').addEventListener('click', draw);
  }
  // ?static=1&export=s6-frames.json: write the frames file for the Figma plugin (design/tools/serve.py --export).
  const EXPORT_NAME = new URLSearchParams(location.search).get('export');
  if (EXPORT_NAME) window.addEventListener('load', () => setTimeout(() => exportSvgFrames(EXPORT_NAME).then(r => { document.title = `exported ${r.frames.length} frames`; }), 400));
}
