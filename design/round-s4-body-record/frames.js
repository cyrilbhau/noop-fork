/* Round S4 · Body record (Stage 4). Every frame is built here from model.js: the §13 fixture is run through
   a design model of the specification's §7 and worded with its §10 and §11 strings. No number is typed by hand.
   EVERY VALUE IS SYNTHETIC (the one Fixture Person of stage 1 §13).

   The builders are pure strings, so this file also loads under Node (see check.js). Every piece of wording
   passes through one of four recorders, which is what check.js audits:
     S(...)  a string of the stage 4 specification (§10, §11); "%@" marks a value
     P(...)  a string the specification lacks: a PROPOSAL, listed in the README
     X(...)  a string the app or the approved stage 1 round already has
     N(...)  a name: a catalogue display name or a fixture name
   The DOM part at the end runs only in a browser. */
var S4FRAMES = (function (M) {
  const USED = { spec: new Map(), prop: new Map(), app: new Map(), name: new Map() };
  const mk = kind => (t, ...a) => { let i = 0; const s = t.replace(/%@/g, () => a[i++]); USED[kind].set(s, t); return s; };
  const S = mk('spec'), P = mk('prop'), X = mk('app'), N = mk('name');

  /* ---------- formatting ---------- */
  const MON = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'], DOW = ['Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat'];
  const fds = d => `${DOW[new Date(M.dayNum(d) * 864e5).getUTCDay()]} ${+d.slice(8)} ${MON[+d.slice(5, 7) - 1]}`;
  const fd = d => `${fds(d)} ${d.slice(0, 4)}`;
  const minus = s => String(s).replace(/^-/, '−');
  const num = (v, dec) => minus(M.displayString(v, dec));
  const signed = (v, dec) => (v > 0 ? '+' : '') + num(v, dec);
  const unitOf = f => f.stored === 'ratio' ? '' : f.stored;
  const val = (v, u) => `<span class="num">${v}</span>${u ? `<small>${u}</small>` : ''}`;
  const TODAY = '2031-06-04';                                   // Wed, stage 1 week 22

  /* ---------- fixture and its variants (§13.4) ---------- */
  const A = M.SCAN_A, B = M.SCAN_B, C3 = M.SCAN_C, ALL = [A, B, C3];
  const patch = (s, p) => ({ ...s, values: Object.fromEntries(Object.entries({ ...s.values, ...p }).filter(([, v]) => v != null)) });
  const V9 = { ...A, unreadable: ['fatMass'] };                 // fat-mass row rewritten with the unit "stone"
  const V16 = { ...A, conflicting: ['fatMass'] };               // a second fat-mass row holding another value
  const V10 = { ...A, source: M.CSV_SOURCE };                   // the same rows imported by CSV in the wide scope
  const BENCH_ALL = ['bench_dead_hang_s', 'bench_pushup_reps', 'custom_bench_fixture_carry'];
  const SCREEN_NOTE = () => S('These are your own figures shown back to you. NOOP does not decide whether any value is normal, high or low.');

  /* ---------- chrome ---------- */
  const navbar = (title, right) => `<div class="navbar"><div class="ibtn" data-ic="chev-l" data-s="22"></div><div class="ttl">${title}</div>${right === 'plus' ? '<div class="ibtn" data-ic="plus" data-s="22"></div>' : right ? `<div class="nbtn strong">${right}</div>` : '<div style="width:40px"></div>'}</div>`;
  const modalBar = (title, save = 'on') => `<div class="navbar mbar"><div class="nbtn${save === 'busy' ? ' off' : ''}">${S('Cancel')}</div><div class="ttl">${title}</div><div class="nbtn strong${save !== 'on' ? ' off' : ''}">${S('Save')}</div></div>`;
  const gh = (t, first) => `<div class="gh"${first ? ' style="padding-top:10px"' : ''}>${t}</div>`;
  const gf = (t, bad) => `<div class="gf${bad ? ' bad' : ''}">${t}</div>`;
  const SEP = '<div class="sep"></div>';
  const grp = rows => `<div class="wrap"><div class="card" style="padding:4px 18px">${rows.join(SEP)}</div></div>`;
  const nrow = (t, v, sub) => `<div class="nrow"><div class="grow1"><div class="t">${t}</div>${sub ? `<div class="rs">${sub}</div>` : ''}</div>${v ? `<div class="val">${v}</div>` : ''}<span class="chev">›</span></div>`;
  const sec = t => `<div class="sec"><h3>${t}</h3></div>`;
  const foot = () => `<div class="foottext">${SCREEN_NOTE()}</div>`;
  const HOME = '<div class="home"></div>';
  const confirmSheet = (text, sub) => `<div class="sheet wsheet"><div class="grabber"></div><div class="at">${text}</div>${sub ? `<div class="ad">${sub}</div>` : ''}
    <div class="btn danger" style="margin-top:18px"><span data-ic="trash" data-s="20"></span><span>${S('Delete')}</span></div><div class="btn secondary" style="margin-top:10px">${S('Cancel')}</div></div>`;

  /* ---------- shared wording ---------- */
  // G5, G5b, I5, I5b, J10b. §11 gives the plural only; the singular is a proposal.
  function issues(rs, named) {
    const out = [], names = ids => ids.map(id => S(M.field(id).label)).join(', ');
    if (rs.unreadable.length) { out.push(rs.unreadable.length === 1 ? P('1 value in this scan could not be read. It remains in Lab Book.') : S('%@ values in this scan could not be read. They remain in Lab Book.', rs.unreadable.length));
      if (named) out.push(P('Could not be read: %@', names(rs.unreadable))); }
    if (rs.conflicting.length) { out.push(rs.conflicting.length === 1 ? P('1 figure in this scan has two different stored values. Open Lab Book to delete the one that is wrong.') : S('%@ figures in this scan have two different stored values. Open Lab Book to delete the one that is wrong.', rs.conflicting.length));
      if (named) out.push(P('Two stored values: %@', names(rs.conflicting))); }
    return out.map(t => `<div class="issue">${t}</div>`).join('');
  }
  const sideText = d => d.value != null ? (d.value === 0 ? S('Equal') : d.value > 0 ? S('Left %@% more', num(Math.abs(d.value), 1)) : S('Right %@% more', num(Math.abs(d.value), 1)))
    : d.gap === 'invalidComponent' ? S('Not available. A figure it needs could not be used.') : S('Not available. Enter both sides.');
  // A change: a signed figure, its unit, and a direction word. Never a colour.
  function changeHtml(c, unit, o = {}) {
    if (!c || c.kind !== 'both') return '';
    if (c.direction === 'same') return `<span class="nc">${S('No change')}</span>`;
    const figure = o.points ? `<span class="num">${S('%@ points', signed(c.delta, c.decimals))}</span>` : val(signed(c.delta, c.decimals), unit);
    return `<span class="cfig">${figure}</span><span class="cdir"><i>${S(c.direction)}</i>${o.pct && c.percent != null ? `<i class="num">${signed(c.percent, 1)}%</i>` : ''}</span>`;
  }

  /* ---------- §10.1 Body record screen ---------- */
  function scanCard(rs) {
    const whole = M.SECTIONS[0].fields.filter(f => rs.values[f.id] != null), d = rs.derived.armToLegLeanPercent;
    return `<div class="card scard"><div class="shead"><div><div class="sdate">${fd(rs.day)}</div>${rs.imported ? `<div class="lab">${S('Imported from CSV')}</div>` : ''}</div><span class="chev">›</span></div>
      <div class="kv3">${whole.map(f => `<div><div class="k">${S(f.label)}</div><div class="v">${val(num(rs.values[f.id], f.dec), unitOf(f))}</div></div>`).join('')}</div>
      ${d.value != null ? `<div class="dline"><span class="k">${S('Arms to legs')}</span><span class="dv">${S('%@% of legs lean mass', num(d.value, 1))}</span></div>` : ''}${issues(rs)}</div>`;
  }
  const scanRow = rs => `<div class="nrow"><div class="grow1"><div class="t">${fd(rs.day)}</div>${rs.imported ? `<div class="rs">${S('Imported from CSV')}</div>` : ''}</div>${rs.values.totalMass != null ? `<div class="val tv">${val(num(rs.values.totalMass, 1), 'kg')}</div>` : ''}<span class="chev">›</span></div>`;
  function benchRow(b) {
    const u = b.def.unit, line = (k, c) => `<div class="chg"><span class="ck">${k}</span>${changeHtml(c, u)}</div>`;
    return `<div class="brow"><div class="grow1"><div class="t">${N(b.def.name)}</div><div class="rs">${fd(b.latest.day)}</div>
      ${b.sincePrevious ? line(S('Since the previous reading'), b.sincePrevious) + line(S('Since the first reading'), b.sinceFirst) : ''}</div>
      <div class="bv">${val(num(b.latest.value, b.def.dec), u)}</div><span class="chev">›</span></div>`;
  }
  const brTop = () => `<div class="sb"></div>${navbar(S('Body record'))}`;
  function bodyRecord(o) {
    if (o.failed) return `${brTop()}<div class="plainmsg">${S("Couldn't open the local store.")}</div>${HOME}`;
    const rs = M.ordered(o.scans).map(M.read), latest = rs[rs.length - 1], prev = rs[rs.length - 2];
    const bench = (o.bench || []).map(k => M.benchmark(k));
    const scans = !rs.length ? `<div class="wrap"><div class="card empty"><div class="et">${S('No scans yet')}</div><div class="btn primary" style="margin-top:16px">${S('Add a scan')}</div></div></div>`
      : `<div class="wrap">${scanCard(latest)}</div>
        ${prev ? `<div style="height:12px"></div>${grp([nrow(S('Compare with %@', fd(prev.day)))])}<div style="height:12px"></div>${grp(rs.slice().reverse().map(scanRow))}` : `<div class="hintline">${S('Add a second scan to compare')}</div>`}
        <div class="wrap mt12"><div class="btn secondary">${S('Add a scan')}</div></div>`;
    const benches = !bench.length ? `<div class="wrap"><div class="card empty"><div class="et">${S('No benchmarks yet')}</div><div class="btn secondary" style="margin-top:16px">${S('Add a benchmark')}</div></div></div>`
      : `${grp(bench.map(benchRow))}<div class="wrap mt12"><div class="btn secondary">${S('Add a benchmark')}</div></div>`;
    return `${brTop()}${sec(S('Scans'))}${scans}${sec(S('Benchmarks'))}${benches}${sec(S('Blood results'))}${grp([nrow(S('Open Lab Book'))])}${foot()}${HOME}`;
  }
  const skb = (w, h, extra = '') => `<div class="skb" style="width:${w};height:${h}px;${extra}"></div>`;
  const brSkeleton = () => `${brTop()}<div class="sec">${skb('90px', 20)}</div>
    <div class="wrap"><div class="card">${skb('150px', 20)}<div class="kv3" style="margin-top:16px">${[0, 1, 2, 3, 4, 5].map(() => `<div>${skb('70%', 12)}${skb('56%', 20, 'margin-top:8px')}</div>`).join('')}</div>${skb('82%', 14, 'margin-top:18px')}</div></div>
    <div style="height:12px"></div><div class="wrap"><div class="card" style="padding:4px 18px">${[0, 1, 2].map(() => `<div class="nrow">${skb('150px', 16)}<span style="flex:1"></span>${skb('64px', 16)}</div>`).join(SEP)}</div></div>
    <div class="sec">${skb('130px', 20)}</div>
    <div class="wrap"><div class="card" style="padding:4px 18px">${[0, 1].map(() => `<div class="brow"><div class="grow1">${skb('72%', 16)}${skb('40%', 12, 'margin-top:8px')}${skb('84%', 12, 'margin-top:8px')}</div>${skb('54px', 20)}</div>`).join(SEP)}</div></div>
    <div class="sec">${skb('140px', 20)}</div><div class="wrap"><div class="card" style="padding:4px 18px"><div class="nrow">${skb('130px', 16)}</div></div></div>${HOME}`;

  /* ---------- §10.2 Scan sheet. Validity, messages and the Save state are worked out here from what is typed. ---------- */
  const typedFrom = (s, over = {}) => { const t = {}; M.FIELDS.forEach(f => { const v = s.values[f.id]; if (v != null) t[f.id] = [M.displayString(Math.abs(v), f.dec), f.stored]; }); return { ...t, ...over }; };
  function scanSheet(o) {
    const sys = o.sys || 'kg', typed = o.typed || {}, sign = o.sign || {}, msgs = {}, stored = {}; let bad = false;
    const add = (id, text, isBad) => (msgs[id] = msgs[id] || []).push([text, isBad]);
    M.FIELDS.forEach(f => { const t = typed[f.id]; if (!t || t[0] === '') return;
      const p = M.parseEntry(t[0], '.'); if (p == null) { add(f.id, S('Use digits and one decimal separator.'), 1); bad = true; return; }
      const sv = M.fieldToStored(f, sign[f.id] === '−' ? -p : p, t[1]);
      if (!M.inRange(f, sv)) { add(f.id, S('Enter a value between %@ and %@ %@.', minus(String(f.lo)), minus(String(f.hi)), f.stored), 1); bad = true; return; }
      stored[f.id] = sv; if (t[1] !== f.stored) add(f.id, S('Stored as %@ %@.', num(sv, f.dec), f.stored), 0); });
    const entered = Object.keys(stored), tooLittle = !bad && entered.length === 1 && entered[0] === 'totalMass';
    if (tooLittle) add('totalMass', S('Add at least one scan figure besides total mass.'), 0);
    if (M.weighInOutranksDraft({ day: o.day, totalTyped: stored.totalMass != null }, o.weighIns || [], o.today || o.day)) add('totalMass', S('You have a weigh-in this week. It stays this week\'s weight; the scan keeps its own total.'), 0);
    const mm = M.mismatches(stored), secMsg = new Set(mm.map(c => M.CHECK_SECTION[c]));
    const occupied = (o.others || []).some(s => s.takenAt === M.noonUtc(o.day));
    const save = o.busy ? 'busy' : (bad || tooLittle || occupied || !entered.length || (o.blockMismatch && mm.length)) ? 'off' : 'on';
    const row = f => { const t = typed[f.id], unit = t ? t[1] : (f.stored === 'kg' ? sys : f.stored), m = msgs[f.id] || [], neg = sign[f.id] === '−';
      return `<div class="frow${m.some(x => x[1]) ? ' bad' : ''}"><div class="fl">${S(f.label)}</div>${f.signed ? `<div class="sgn"><span${neg ? '' : ' class="on"'}>+</span><span${neg ? ' class="on"' : ''}>−</span></div>` : ''}<div class="fv num">${t ? t[0] : ''}</div>${unit === 'ratio' ? '' : `<div class="fu"><span>${unit}</span>${f.units.length > 1 ? '<span class="car">▾</span>' : ''}</div>`}</div>${m.map(x => `<div class="fmsg${x[1] ? ' bad' : ''}">${x[0]}</div>`).join('')}${f.id === 'rmr' ? `<div class="fmsg">${S('Laboratory estimate. Not used by NOOP\'s calorie figures.')}</div>` : ''}`; };
    const body = `<div class="intro">${S('Type the figures as your report prints them. Leave out anything it does not give.')}</div>
      <div class="wrap daterow"><div class="datechip"><span data-ic="cal" data-s="16"></span><span>${fd(o.day)}</span></div><div class="seg useg"><span${sys === 'kg' ? ' class="on"' : ''}>kg</span><span${sys === 'lb' ? ' class="on"' : ''}>lb</span></div></div>
      ${occupied ? gf(S('Another scan is already recorded at that time.'), 1) : ''}
      ${o.fail ? `<div class="wrap mt12"><div class="fail">${S("Couldn't save the scan. Nothing was changed.")}</div></div>` : ''}
      ${M.SECTIONS.map(s => `${gh(S(s.name))}<div class="wrap"><div class="card fcard">${s.fields.map(row).join(SEP)}</div></div>${secMsg.has(s.name) ? gf(S('These figures do not add up as typed. Check them against the report.')) : ''}`).join('')}
      ${gh(S('Note'))}<div class="wrap"><div class="field notef">${o.note ? N(o.note) : ''}</div></div>
      ${o.del ? `<div class="wrap mt24"><div class="btn danger"><span data-ic="trash" data-s="20"></span><span>${S('Delete')}</span></div></div>` : ''}`;
    return `<div class="sb"></div>${modalBar(o.title, save)}${o.busy || o.confirm ? `<div class="dim">${body}</div>` : body}${o.confirm ? confirmSheet(S('Delete this scan? Its total mass is removed from your weight history too.')) : ''}${HOME}`;
  }
  const NEW = () => S('Add a scan'), EDITT = () => P('Edit scan');
  const signsOf = s => ({ tScore: s.values.tScore < 0 ? '−' : '+', zScore: s.values.zScore < 0 ? '−' : '+' });
  const sheetA = (extra = {}) => ({ title: NEW(), day: A.day, today: A.day, typed: typedFrom(A), sign: signsOf(A), note: A.note, weighIns: [], ...extra });

  /* ---------- §10.3 Scan detail ---------- */
  function sectionCards(rs) {
    return M.SECTIONS.map(s => { const fs = s.fields.filter(f => rs.values[f.id] != null); if (!fs.length) return '';
      return `${gh(S(s.name))}<div class="wrap"><div class="card fcard">${fs.map(f => `<div class="drow"><div class="dl">${S(f.label)}</div><div class="dvv">${val(num(rs.values[f.id], f.dec), unitOf(f))}</div></div>${f.id === 'rmr' ? `<div class="fmsg">${S('Laboratory estimate. Not used by NOOP\'s calorie figures.')}</div>` : ''}`).join(SEP)}</div></div>`; }).join('');
  }
  function derivedCard(rs) {
    const d = rs.derived, v = rs.values;
    if (!['armsLean', 'armLeftLean', 'armRightLean', 'legsLean', 'legLeftLean', 'legRightLean'].some(k => v[k] != null) && !rs.unreadable.length && !rs.conflicting.length) return '';
    const r = d.armToLegLeanPercent, from = [d.armsSource === 'sumOfSides' ? S('From left and right arm.') : '', d.legsSource === 'sumOfSides' ? S('From left and right leg.') : ''].filter(Boolean);
    const ratio = r.value != null ? `<div class="drow"><div class="dl">${S('Arms to legs')}</div><div class="dvv dt">${S('%@% of legs lean mass', num(r.value, 1))}</div></div>${from.map(t => `<div class="fmsg">${t}</div>`).join('')}`
      : `<div class="drow stack"><div class="dl">${S('Arms to legs')}</div><div class="dna">${r.gap === 'invalidComponent' ? S('Not available. A figure it needs could not be used.') : S('Not available. Enter arms and legs lean mass.')}</div></div>`;
    const side = (label, x) => x.value != null ? `<div class="drow"><div class="dl">${S(label)}</div><div class="dvv dt">${sideText(x)}</div></div>` : `<div class="drow stack"><div class="dl">${S(label)}</div><div class="dna">${sideText(x)}</div></div>`;
    return `${gh(P('Derived'))}<div class="wrap"><div class="card fcard">${[ratio, side('Left and right arm', d.armSideDifferencePercent), side('Left and right leg', d.legSideDifferencePercent)].join(SEP)}</div></div>`;
  }
  function scanDetail(raw) {
    const rs = M.read(raw), iss = issues(rs, true);
    return `<div class="sb"></div>${navbar(fd(rs.day), rs.editable ? S('Edit') : null)}
      ${rs.imported ? `<div class="wrap mt12"><div class="card icard"><div class="issue">${S('Imported from CSV. Edit or delete its readings in Lab Book.')}</div></div></div>` : ''}
      ${iss ? `<div class="wrap mt12"><div class="card icard">${iss}</div></div>` : ''}
      ${sectionCards(rs)}${derivedCard(rs)}
      ${rs.note ? `${gh(S('Note'))}<div class="wrap"><div class="card notec">${N(rs.note)}</div></div>` : ''}
      ${rs.imported || rs.conflicting.length ? `<div style="height:16px"></div>${grp([nrow(S('Open Lab Book'))])}` : ''}
      ${!rs.imported && rs.conflicting.length ? `<div class="wrap mt16"><div class="btn danger"><span data-ic="trash" data-s="20"></span><span>${S('Delete')}</span></div></div>` : ''}
      ${foot()}${HOME}`;
  }

  /* ---------- §10.4 Scan comparison ---------- */
  function compareScreen(o) {
    const rs = M.ordered(o.scans).map(M.read), top = `<div class="sb"></div>${navbar(S('Compare scans'))}`;
    if (!rs.length) return `${top}<div class="wrap" style="margin-top:28px"><div class="card empty"><div class="et">${S('No scans yet')}</div><div class="btn primary" style="margin-top:16px">${S('Add a scan')}</div></div></div>${HOME}`;
    if (rs.length === 1) return `${top}<div class="wrap mt12"><div class="card icard"><div class="sdate">${fd(rs[0].day)}</div><div class="issue">${S('One scan so far. A second scan makes a comparison.')}</div></div></div>
      ${sectionCards(rs[0])}${derivedCard(rs[0])}<div class="wrap mt16"><div class="btn primary">${S('Add a scan')}</div></div>${foot()}${HOME}`;
    // Nil ids mean the two newest. Whatever is chosen, the smaller takenAt is the left column.
    const pick = n => rs.find(x => x.name === n), two = M.ordered([o.earlier ? pick(o.earlier) : rs[rs.length - 2], o.later ? pick(o.later) : rs[rs.length - 1]]), e = two[0], l = two[1];
    const cmp = M.comparison(e, l), show = n => !o.sections || o.sections.includes(n);
    const em = k => `<em>${S(k)}</em>`;
    const cellV = (v, dec, u, na) => `<div class="cc">${na}${v == null ? '' : `<span class="cval">${val(num(v, dec), u)}</span>`}</div>`;
    const ne = () => `<span class="ne">${S('not entered')}</span>`, nav = () => `<span class="ne">${S('not available')}</span>`;
    const crow = ({ field: f, change: c }) => { const u = unitOf(f), ev = c.kind === 'both' ? c.earlier : c.kind === 'onlyEarlier' ? c.value : null, lv = c.kind === 'both' ? c.later : c.kind === 'onlyLater' ? c.value : null;
      return `<div class="crow"><div class="cl">${S(f.label)}</div><div class="cg">${cellV(ev, c.decimals, u, em('Earlier') + (ev == null ? ne() : ''))}${cellV(lv, c.decimals, u, em('Later') + (lv == null ? ne() : ''))}<div class="cc ch">${c.kind === 'both' ? em('Change') + changeHtml(c, u, { points: f.points, pct: f.pct }) : ''}</div></div></div>`; };
    const tables = M.SECTIONS.filter(s => show(s.name)).map(s => { const rows = cmp.rows.filter(r => r.field.section === s.name); return rows.length ? `${gh(S(s.name))}<div class="wrap"><div class="card fcard">${rows.map(crow).join(SEP)}</div></div>` : ''; }).join('');
    // Derived rows. Arms to legs is compared; a side difference is shown for each scan with no change figure.
    const a2l = cmp.armToLeg, av = x => x.derived.armToLegLeanPercent.value;
    const ratioRow = a2l.kind === 'neither' ? '' : `<div class="crow"><div class="cl">${S('Arms to legs')}</div><div class="cg">${cellV(av(e), 1, '%', em('Earlier') + (av(e) == null ? nav() : ''))}${cellV(av(l), 1, '%', em('Later') + (av(l) == null ? nav() : ''))}<div class="cc ch">${a2l.kind === 'both' ? em('Change') + changeHtml(a2l, '', { points: true }) : ''}</div></div></div>`;
    const sideRow = (label, k) => { const x = e.derived[k], y = l.derived[k]; if (x.value == null && y.value == null) return '';
      const c = (d, w) => `<div class="cc">${em(w)}${d.value != null ? `<span class="cval st">${sideText(d)}</span>` : nav()}</div>`;
      return `<div class="crow"><div class="cl">${S(label)}</div><div class="cg">${c(x, 'Earlier')}${c(y, 'Later')}<div class="cc ch"></div></div></div>`; };
    const dRows = [ratioRow, sideRow('Left and right arm', 'armSideDifferencePercent'), sideRow('Left and right leg', 'legSideDifferencePercent')].filter(Boolean);
    const derived = show('Derived') && dRows.length ? `${gh(P('Derived'))}<div class="wrap"><div class="card fcard">${dRows.join(SEP)}</div></div>` : '';
    const under = [e, l].map(x => { const t = issues(x); return t ? `<div class="wrap mt12"><div class="card icard"><div class="lab">${fd(x.day)}</div>${t}</div></div>` : ''; }).join('');
    const menu = (k, x, open) => `<div class="menu${open ? ' open' : ''}"><div class="mk">${S(k)}</div><div class="mv"><span>${fd(x.day)}</span><span class="car">▾</span></div></div>`;
    // J8: each menu leaves out the other menu's choice, so one scan cannot be picked twice.
    const pop = o.menu ? `<div class="wrap"><div class="pop">${rs.filter(x => x !== (o.menu === 'earlier' ? l : e)).map(x => `<div class="prow"><span>${fd(x.day)}</span>${x === (o.menu === 'earlier' ? e : l) ? '<span class="tick" data-ic="check" data-s="18"></span>' : ''}</div>`).join(SEP)}</div></div>` : '';
    return `${top}<div class="wrap menus">${menu('Earlier', e, o.menu === 'earlier')}${menu('Later', l, o.menu === 'later')}</div>${pop}
      <div class="chead"><span>${S('Earlier')}</span><span>${S('Later')}</span><span>${S('Change')}</span></div>
      ${tables}${derived}${under}${o.sections ? '' : foot()}${HOME}`;
  }

  /* ---------- §10.5 Benchmarks ---------- */
  function parseBench(text, unit) {                               // seconds accept "45" or "1:30"; reps are whole numbers
    const t = String(text).trim(); if (t === '') return { empty: true };
    if (unit === 's' && /^[0-9]+:[0-5][0-9]$/.test(t)) { const [m, s] = t.split(':').map(Number); return { value: m * 60 + s }; }
    const v = M.parseEntry(t, '.'); if (v == null) return { msg: S('Use digits and one decimal separator.') };
    if (unit === 'reps' && !Number.isInteger(v)) return { msg: S('Enter a whole number.') };
    const [lo, hi] = M.BENCH_RANGE[unit]; if (v < lo || v > hi) return { msg: S('Enter a value between %@ and %@ %@.', String(lo), String(hi), unit) };
    return { value: v };
  }
  function benchSheet(o) {
    const def = o.key ? M.benchDef(o.key) : null, custom = o.custom, unit = custom ? o.unit : def ? def.unit : null;
    const p = unit ? parseBench(o.value || '', unit) : { empty: true }, save = p.value != null && (!custom || o.name) ? 'on' : 'off';
    const names = M.BENCHMARKS.map(b => [b.key, N(b.name)]).concat([['custom', S('Custom benchmark')]]), chosen = custom ? 'custom' : o.key;
    const picker = o.open ? `<div class="wrap"><div class="card" style="padding:4px 18px">${names.map(([k, n]) => `<div class="nrow"><div class="t">${n}</div>${k === chosen ? '<span class="tick" data-ic="check" data-s="18"></span>' : ''}</div>`).join(SEP)}</div></div>`
      : grp([`<div class="nrow"><div class="t">${names.find(x => x[0] === chosen)[1]}</div><span class="car">▾</span></div>`]);
    return `<div class="sb"></div>${modalBar(S('Add a benchmark'), save)}${gh(P('Benchmark'), 1)}${picker}
      ${custom ? `${gh(X('Name'))}<div class="wrap"><div class="field notef one">${o.name ? N(o.name) : ''}</div></div>${gh(X('Unit'))}<div class="wrap"><div class="seg">${M.CUSTOM_UNITS.map(u => `<span${u === unit ? ' class="on"' : ''}>${u}</span>`).join('')}</div></div>` : ''}
      ${gh(X('Value'))}<div class="wrap"><div class="card fcard"><div class="frow${p.msg ? ' bad' : ''}"><div class="fl"></div><div class="fv num big">${o.value || ''}</div>${unit ? `<div class="fu"><span>${unit}</span></div>` : ''}</div>${p.msg ? `<div class="fmsg bad">${p.msg}</div>` : ''}</div></div>
      ${o.hint ? gf(o.hint) : ''}
      ${gh(X('Date taken'))}<div class="wrap daterow"><div class="datechip"><span data-ic="cal" data-s="16"></span><span>${fd(o.day)}</span></div><div class="datechip"><span>12:00</span></div></div>
      ${gh(S('Condition (optional)'))}<div class="wrap"><div class="field notef one">${o.note ? N(o.note) : `<span class="ph">${S('e.g. surface height or grip')}</span>`}</div></div>${HOME}`;
  }
  function benchDetail(o) {
    const b = M.benchmark(o.key, o.keep), u = b.def.unit, top = b.rows[0];
    const kv = (k, c) => `<div><div class="k">${k}</div><div class="v chgv">${changeHtml(c, u)}</div></div>`;
    const rrow = r => `<div class="rrow2"><div class="grow1"><div class="rv">${val(num(r.value, b.def.dec), u)}</div><div class="rs">${fd(r.day)}</div>${r.note ? `<div class="rs">${N(r.note)}</div>` : ''}</div><div class="rchg">${changeHtml(r.change, u)}</div><span class="trash" data-ic="trash" data-s="18"></span></div>`;
    const body = `<div class="wrap mt12"><div class="card"><div class="big num"><span>${num(top.value, b.def.dec)}</span><small>${u}</small></div><div class="src" style="margin-top:8px"><i></i><span>${fd(top.day)}</span></div>
        ${b.sincePrevious ? `<div class="kv">${kv(S('Since the previous reading'), b.sincePrevious)}${kv(S('Since the first reading'), b.sinceFirst)}</div>` : `<div class="issue" style="margin-top:14px">${S('One reading so far.')}</div>`}</div></div>
      ${gh(X('History'))}${grp(b.rows.map(rrow))}${foot()}`;
    return `<div class="sb"></div>${navbar(N(b.def.name), 'plus')}${o.confirm ? `<div class="dim">${body}</div>${confirmSheet(S('Delete this reading?'), `<span class="num">${num(top.value, b.def.dec)}</span> <span>${u}</span> <span>·</span> <span>${fd(top.day)}</span>`)}` : body}${HOME}`;
  }

  /* ---------- §10.6 Lab Book editor (4B). The frame of the existing editor, with the lines stage 4 adds. ---------- */
  function editor(o) {
    const m = M.MARKERS[o.key], on = o.flag !== false, opts = M.options(o.key, on ? 'extended' : 'legacy').map(x => x[0]), unit = o.unit || m.stored;
    const p = o.typed == null || o.typed === '' ? null : M.parseEntry(o.typed, o.sep || '.'), nan = o.typed && p == null, stored = p == null ? null : M.toStored(p, o.key, unit), kind = M.optionKind(o.key, unit);
    const lines = [];
    if (nan && on) lines.push([S('Use digits and one decimal separator.'), 1]);
    else if (on && unit !== m.stored && kind === 'identity') lines.push([S('Same number, stored as %@.', m.stored), 0]);
    else if (on && unit !== m.stored && stored != null) { lines.push([S('Stored as %@ %@.', num(stored, m.dec), m.stored), 0]); if (kind === 'affine') lines.push([S('mmol/mol = (percent − 2.152) ÷ 0.09148'), 0]); }
    else if (!on && opts.length > 1) lines.push([X('Stored as %@. %@', m.stored, X('× %@ on save.', String(Number((1 / 38.67).toPrecision(5))))), 0]);
    const ok = p != null;
    return `<div class="sb"></div><div class="navbar"><div style="width:40px"></div><div class="ttl">${X('Add a reading')}</div><div style="width:40px"></div></div>
      <div class="wrap mt12"><div class="card"><div class="sdate">${N(m.name)}</div><div class="lab">${X('Blood panel')}</div></div></div>
      ${gh(X('Reading'))}<div class="wrap"><div class="card">
        <div class="vhead"><span class="ovl">${X('Value')}</span>${opts.length > 1 ? `<div class="seg vseg">${opts.map(u => `<span${u === unit ? ' class="on"' : ''}>${u}</span>`).join('')}</div>` : ''}</div>
        <div class="field vbox${nan ? ' bad' : ''}"><span class="num vt">${o.typed || ''}</span><span class="vu">${unit}</span></div>
        ${lines.map(x => `<div class="fmsg in${x[1] ? ' bad' : ''}">${x[0]}</div>`).join('')}
        <div class="ovl" style="margin-top:16px">${X('Date taken')}</div><div class="daterow in"><div class="datechip"><span data-ic="cal" data-s="16"></span><span>${fd(M.BLOOD_DAY)}</span></div><div class="datechip"><span>12:00</span></div></div>
        <div class="ovl" style="margin-top:16px">${X('Note (optional)')}</div><div class="field notef one"></div></div></div>
      <div class="wrap efoot"><div class="nbtn">${S('Cancel')}</div>${on ? `<div class="btn secondary sm${ok ? '' : ' off'}">${S('Save and add another')}</div>` : ''}<div class="btn primary sm${ok ? '' : ' off'}">${S('Save')}</div></div>${HOME}`;
  }
  const UNIT_OF = k => M.MARKERS[k].stored;
  const editorSaved = key => `<div class="sb"></div><div class="navbar"><div style="width:40px"></div><div class="ttl">${X('Add a reading')}</div><div style="width:40px"></div></div>
    <div class="wrap mt12"><div class="banner"><div class="bt">${S('Saved %@.', N(M.MARKERS[key].name))}</div></div></div>
    ${gh(X('Date taken'))}<div class="wrap daterow"><div class="datechip"><span data-ic="cal" data-s="16"></span><span>${fd(M.BLOOD_DAY)}</span></div><div class="datechip"><span>12:00</span></div></div>
    <div class="wrap mt16"><div class="field"><span class="ph">${X('Search markers (e.g. LDL, ferritin)')}</span></div></div>
    <div style="height:12px"></div>${grp(['total_cholesterol', 'ldl', 'hdl', 'triglycerides', 'fasting_glucose', 'hba1c', 'ferritin', 'tsh'].map(k => `<div class="nrow"><div class="grow1"><div class="t">${N(M.MARKERS[k].name)}</div><div class="rs">${X('Blood panel')}</div></div><div class="val">${UNIT_OF(k)}</div></div>`))}
    <div class="wrap mt12"><div class="btn secondary"><span data-ic="plus" data-s="20"></span><span>${X('Add a custom marker')}</span></div></div>${HOME}`;
  // L6. swap = the option of open question O9: the typed unit first, the stored unit second.
  function markerHistory(key, swap) {
    const b = M.blood(key), first = swap && b.annotation ? `<span>${b.annotation}</span>` : val(b.shown, b.storedUnit);
    const second = !b.annotation ? '' : swap ? S('Stored as %@ %@.', b.shown, b.storedUnit) : S('Entered as %@', b.annotation);
    return `<div class="sb"></div>${navbar(N(b.name), 'plus')}<div class="wrap"><div class="lab" style="padding:0 2px">${X('1 reading · your own entries')}</div></div>
      ${gh(X('History'))}${grp([`<div class="rrow2"><div class="grow1"><div class="rv">${first}</div>${second ? `<div class="rs ea">${second}</div>` : ''}<div class="rs">${fd(b.day)}</div></div><span class="trash" data-ic="trash" data-s="18"></span></div>`])}${foot()}${HOME}`;
  }

  /* ---------- Lab Book lists: scan rows under "Imaging", benchmark rows under "Custom" (§4.4, O4) ---------- */
  const CAT_NAME = { fatMass: 'Fat mass (scan)', leanMass: 'Lean mass (scan)', boneMass: 'Bone mineral content (scan)', fatFreeMass: 'Fat-free mass (scan)', visceralFatMass: 'Visceral fat mass (scan)',
    visceralFatArea: 'Visceral fat area (scan)', androidFatPercent: 'Android fat (scan)', gynoidFatPercent: 'Gynoid fat (scan)', androidGynoidRatio: 'Android to gynoid ratio (scan)',
    armsLean: 'Arms lean mass, total (scan)', armLeftLean: 'Left arm lean mass (scan)', armRightLean: 'Right arm lean mass (scan)', legsLean: 'Legs lean mass, total (scan)',
    legLeftLean: 'Left leg lean mass (scan)', legRightLean: 'Right leg lean mass (scan)', trunkLean: 'Trunk lean mass (scan)', bmd: 'Bone mineral density (scan)',
    tScore: 'Bone density T-score (scan)', zScore: 'Bone density Z-score (scan)', rmr: 'Resting metabolic rate (laboratory estimate)' };
  const humanise = key => key.split('_').map(w => w.charAt(0).toUpperCase() + w.slice(1)).join(' ');   // LabBookView.humanise: a key with no catalogue entry
  function labBookLists() {
    const rs = M.ordered(ALL).map(M.read).reverse(), latest = id => rs.find(x => x.values[id] != null);
    const card = (name, day, value) => `<div class="card lbrow"><div class="grow1"><div class="t">${name}</div><div class="rs">${X('last taken %@', fd(day))}</div></div><div class="lv">${value}</div><span class="chev">›</span></div>`;
    const img = M.FIELDS.filter(f => CAT_NAME[f.id] && latest(f.id)).map(f => { const x = latest(f.id); return [N(CAT_NAME[f.id]), card(N(CAT_NAME[f.id]), x.day, val(num(x.values[f.id], f.dec), f.stored))]; });
    const noted = rs.find(x => x.note); if (noted) img.push([N('Scan note'), card(N('Scan note'), noted.day, `<span class="nt">${N(noted.note)}</span>`)]);
    const cus = BENCH_ALL.map(k => M.benchmark(k)).map(b => [N(b.def.custom ? humanise(b.def.key) : b.def.name), b]).map(([n, b]) => [n, card(n, b.latest.day, val(num(b.latest.value, b.def.dec), b.def.unit))]);
    const list = (title, items) => { items.sort((p, q) => p[0] < q[0] ? -1 : 1);       // alphabetised by display name, as Lab Book does today
      return `<div class="sec lbsec"><h3>${title}</h3><a>${X('%@ markers', items.length)}</a></div><div class="wrap lblist">${items.map(x => x[1]).join('')}</div>`; };
    return `<div class="sb"></div>${navbar(X('Lab Book'), 'plus')}${list(X('Imaging'), img)}${list(X('Custom'), cus)}${HOME}`;
  }

  /* ---------- §10.7 Weigh-in history (stage 1 screen), on Wed 15 Jan 2031 ---------- */
  function history(flagOn) {
    const w2 = M.weighInOn('2031-01-15'), w1 = M.weighInOn(A.day), rs = M.read(A), DOT = `<svg width="8" height="8" viewBox="0 0 8 8" style="margin-right:6px"><circle cx="4" cy="4" r="3.5" fill="#F5F5F7"/></svg>`;
    const cap = (rep, src) => `<div class="m"><span>${rep ? X('Represents its week') : X('Not the weekly point')}</span><span> · </span><span>${src}</span></div>`;
    const wrow = w => `<div class="hrow"><div><div class="d">${DOT}<span>${fds(w.day)}</span></div>${cap(1, X('Lab Book'))}</div><div class="x">${val(num(w.weightKg, 1), 'kg')}</div><div class="x">${val(num(w.waistCm, 1), 'cm')}</div></div>`;
    const srow = `<div class="hrow off"><div><div class="d"><span>${fds(rs.day)}</span>${flagOn ? '<span class="chev">›</span>' : ''}</div>${cap(0, flagOn ? S('Lab Book · body scan') : X('Lab Book'))}</div><div class="x">${val(num(rs.values.totalMass, 1), 'kg')}</div><div class="x none">${X('not measured')}</div></div>`;
    return `<div class="sb"></div>${navbar(X('History'), 'plus')}<div class="colh"><span></span><span>${X('Weight')}</span><span>${X('Waist')}</span></div>
      <div class="wrap" style="margin-top:8px"><div class="card" style="padding:4px 18px">${[wrow(w2), srow, wrow(w1)].join(SEP)}</div></div>${HOME}`;
  }

  /* ---------- Health row (§10.1) and Settings card (§10.8). The combined frame set is the authority for both. ---------- */
  const lrow = (icon, title, detail) => `<div class="nrow"><span class="lic" data-ic="${icon}" data-s="20"></span><div class="grow1"><div class="t">${title}</div>${detail ? `<div class="rs">${detail}</div>` : ''}</div><span class="chev">›</span></div>`;
  const healthRow = scans => { const rs = M.ordered(scans).map(M.read), last = rs[rs.length - 1];
    return `<div class="sb"></div><div class="hdr"><div><div class="lt">${X('Health')}</div></div><div class="ibtn" data-ic="person" data-s="22"></div></div>
      ${sec(X('More health'))}${grp([lrow('scale', X('Scorecard')), lrow('doc', S('Body record'), last ? S('Last scan %@', fd(last.day)) : S('No scans yet')), lrow('heart', X('Live heart rate')), lrow('chart', X('All metrics')), lrow('thermo', X('Skin temperature'))])}
      <div class="tabbar" data-on="3"></div>${HOME}`; };
  const trow = (t, sub, on) => `<div class="nrow"><div class="grow1"><div class="t">${t}</div><div class="rs">${sub}</div></div><div class="toggle${on ? ' on' : ''}"></div></div>`;
  const settings = (units, body, one) => `<div class="sb"></div>${navbar(X('Settings'))}${gh(S('Body record'), 1)}
    ${grp(one ? [trow(S('Body record'), P('Scans, benchmarks, and blood results typed in the unit your report prints.'), body)]
      : [trow(S('Report units in Lab Book'), S('Type blood results in the unit your report prints.'), units), trow(S('Body record'), S('Scans and benchmarks, entered as printed and compared.'), body)])}
    ${gf(one ? P('Switching it off hides its screens and deletes nothing.') : P('Switching either off hides its screens and deletes nothing.'))}${HOME}`;

  /* ---------- frames ---------- */
  const G = []; let cur;
  const group = (title, note) => { cur = { title, note, frames: [] }; G.push(cur); };
  // Sheets, the skeleton and the option frames are still; the pushed screens play round 6's entrance.
  const frame = (name, html, o = {}) => cur.frames.push({ name, html, attrs: /^(G1 |H|K[1-47] |L|O)/.test(name) ? 'data-nomotion' : '', ...o });
  const AX = { cls: 'ax' }, VIEW = { style: 'height:874px;padding-bottom:0' };

  group('G · Body record screen (§10.1)', 'Three sections: Scans, Benchmarks, Blood results. The scan card shows the latest scan\'s date, the whole-body figures that were entered and the derived line. There is no "current weight" here: a total mass always sits with its scan\'s date. Figures are in the primary text colour; nothing is coloured as good or bad.');
  frame('G1 Body record · loading', brSkeleton());
  frame('G2 Body record · nothing recorded', bodyRecord({ scans: [] }), { note: 'Variant V1, with no benchmarks.' });
  frame('G3 Body record · one scan', bodyRecord({ scans: [A], bench: BENCH_ALL }), { note: 'Variant V2: scan A only.' });
  frame('G4 Body record · two or more scans', bodyRecord({ scans: ALL, bench: BENCH_ALL }), { note: 'The fixture: scans A, B and C. The latest is C, a sparse scan; its arms figure is the sum of the two sides.' });
  frame('G5 Body record · a scan with unreadable rows', bodyRecord({ scans: [V9], bench: BENCH_ALL }), { note: 'Variant V9 on scan A alone: the fat-mass row carries a unit that is not recognised. It is not shown as a number or as zero.' });
  frame('G5b Body record · a scan with a conflicting key', bodyRecord({ scans: [V16], bench: BENCH_ALL }), { note: 'Variant V16 on scan A alone: two different stored fat-mass values.' });
  frame('G6 Body record · an imported scan', bodyRecord({ scans: [V10], bench: BENCH_ALL }), { note: 'Variant V10.' });
  frame('G7 Body record · benchmarks', bodyRecord({ scans: ALL, bench: ['bench_dead_hang_s', 'bench_pushup_reps'] }), { note: 'The two fixture benchmarks with more than one reading.' });
  frame('G8 Body record · a benchmark with one reading', bodyRecord({ scans: ALL, bench: ['custom_bench_fixture_carry'] }), { note: 'The fixture\'s custom benchmark: no change line.' });
  frame('G9 Body record · store could not be opened', bodyRecord({ failed: 1 }));
  frame('G10 Body record · largest text size', bodyRecord({ scans: ALL, bench: BENCH_ALL }), AX);

  group('H · Scan sheet (§10.2)', 'One sitting, top to bottom in the order a report prints. Every field is optional and an empty field is "not entered", never zero. The sheet-wide kg / lb control follows the unit setting; a mass field can also be switched on its own (kg, lb, g). H3 to H8 and H10 to H13 are drawn at the height of the phone screen, scrolled to the top.');
  frame('H1 Scan sheet · new, empty', scanSheet({ title: NEW(), day: TODAY, today: TODAY, weighIns: M.WEIGH_INS }));
  frame('H2 Scan sheet · filled, valid', scanSheet(sheetA()), { note: 'Scan A typed on its own day, seeded without stage 1\'s weigh-ins so that H8 does not apply.' });
  frame('H3 Scan sheet · a field in another unit', scanSheet(sheetA({ typed: typedFrom(A, { totalMass: [M.displayString(A.values.totalMass * M.LB, 1), 'lb'], boneMass: [M.displayString(A.values.boneMass * 1000, 0), 'g'] }) })), { ...VIEW, note: 'Variant V6: the total typed in pounds. Bone mineral content typed in grams.' });
  frame('H4 Scan sheet · a field out of range', scanSheet(sheetA({ typed: typedFrom(A, { fatMass: [M.displayString(A.values.fatMass * 10, 0), 'kg'] }) })), { ...VIEW, note: 'A slipped decimal point: ten times scan A\'s fat mass.' });
  frame('H5 Scan sheet · not a number', scanSheet(sheetA({ typed: typedFrom(A, { fatMass: [`${M.displayString(A.values.fatMass, 1)}.0`, 'kg'] }) })), VIEW);
  frame('H6 Scan sheet · figures that do not add up', scanSheet({ title: NEW(), day: B.day, today: B.day, typed: typedFrom(B, { fatFreeMass: [M.displayString(M.V3_FAT_FREE_TYPED, 1), 'kg'] }), weighIns: [] }), { ...VIEW, note: 'Variant V3: scan B with fat-free mass typed 96.0. Save stays enabled.' });
  frame('H7 Scan sheet · only the total mass entered', scanSheet({ title: NEW(), day: A.day, today: A.day, typed: { totalMass: typedFrom(A).totalMass }, weighIns: [] }), VIEW);
  frame('H8 Scan sheet · a weigh-in in the chosen day\'s week', scanSheet(sheetA({ weighIns: M.WEIGH_INS })), { ...VIEW, note: 'The combined seed: stage 1\'s weigh-in of the same day. A neutral line, not a warning.' });
  frame('H9 Scan sheet · editing', scanSheet(sheetA({ title: EDITT(), today: TODAY, weighIns: M.WEIGH_INS, del: 1 })), { note: 'Scan A in the combined seed, so the H8 line shows here too.' });
  frame('H10 Scan sheet · editing, day already holds a scan', scanSheet({ title: EDITT(), day: A.day, today: TODAY, typed: typedFrom(B), weighIns: M.WEIGH_INS, others: [A, C3], del: 1 }), { ...VIEW, note: 'Variant V12: scan B moved to scan A\'s day. Nothing is written.' });
  frame('H11 Scan sheet · saving', scanSheet(sheetA({ busy: 1 })), VIEW);
  frame('H12 Scan sheet · save failed', scanSheet(sheetA({ fail: 1 })), VIEW);
  frame('H13 Scan sheet · delete confirmation', scanSheet(sheetA({ title: EDITT(), today: TODAY, weighIns: M.WEIGH_INS, del: 1, confirm: 1 })), VIEW);
  frame('H14 Scan sheet · largest text size', scanSheet(sheetA()), AX);

  group('I · Scan detail (§10.3)', 'Sections in report order, each entered figure with its unit, then the derived block and the note. A section with nothing entered is absent.');
  frame('I1 Scan detail · a full scan', scanDetail(A), { note: 'Scan A.' });
  frame('I2 Scan detail · a sparse scan', scanDetail(C3), { note: 'Scan C: seven figures. No field is shown as zero or as a dash with a unit.' });
  frame('I3 Scan detail · derived figure not available', scanDetail(patch(A, { legsLean: null, legLeftLean: null, legRightLean: null })), { note: '§13.2: scan A with its legs total removed and no leg sides.' });
  frame('I4 Scan detail · derived figure from the two sides', scanDetail(patch(A, { armsLean: null })), { note: 'Scan A with its arms total removed: the arms figure is left plus right.' });
  frame('I5 Scan detail · unreadable rows', scanDetail(V9), { note: 'Variant V9.' });
  frame('I5b Scan detail · conflicting keys', scanDetail(V16), { note: 'Variant V16. No Edit; Delete stays because the scan was typed.' });
  frame('I6 Scan detail · imported scan', scanDetail(V10), { note: 'Variant V10. No Edit, no Delete.' });
  frame('I7 Scan detail · the scan no longer exists', bodyRecord({ scans: [A, B], bench: BENCH_ALL }), { note: 'There is nothing to draw for the detail: it leaves the stack. This is the Body record screen the owner lands on after scan C is deleted.' });
  frame('I8 Scan detail · largest text size', scanDetail(A), AX);

  group('J · Scan comparison (§10.4)', 'Two menus choose the scans; the earlier one is always the left column. Each row: earlier value, later value, change with its sign, unit and a direction word, and a percentage where the specification allows one. Percentages of percentages are not shown: those changes are in points.');
  frame('J1 Compare · two scans', compareScreen({ scans: ALL, earlier: 'A', later: 'B' }), { note: 'Scans A and B: the table of §13.3. The fixture\'s A and B do not hold exactly the same fields, so this frame also contains J2 rows (bone density) and a J3 row (visceral fat area).' });
  frame('J2 Compare · a marker only in the earlier scan', compareScreen({ scans: ALL }), { note: 'The two newest, B and C. C is sparse.' });
  frame('J3 Compare · a marker only in the later scan', compareScreen({ scans: ALL, earlier: 'A', later: 'B', sections: ['Fat distribution'] }), { note: 'A and B, scrolled to Fat distribution: visceral fat area is only in B.' });
  frame('J4 Compare · a marker in neither', compareScreen({ scans: ALL, earlier: 'A', later: 'C' }), { note: 'A and C: neither holds a visceral fat area, so that row is absent.' });
  frame('J5 Compare · no change', compareScreen({ scans: ALL, sections: ['Whole body'] }), { note: 'B and C, scrolled to Whole body: lean mass and bone mineral content are unchanged.' });
  frame('J6 Compare · one scan only', compareScreen({ scans: [A] }), { note: 'Variant V2.' });
  frame('J7 Compare · no scans', compareScreen({ scans: [] }), { note: 'Variant V1.' });
  frame('J8 Compare · the same scan cannot be chosen twice', compareScreen({ scans: ALL, menu: 'earlier', sections: ['Whole body'] }), { note: 'The Earlier menu, open: the Later menu\'s choice is absent from it.' });
  frame('J9 Compare · scans entered out of order', compareScreen({ scans: [A, C3, B], earlier: 'A', later: 'B' }), { note: 'Entered A, then C, then B. Identical to J1 (check.js asserts it).' });
  frame('J10 Compare · a derived figure in one scan only', compareScreen({ scans: ALL, sections: ['Derived'] }), { note: 'B and C, scrolled to the derived rows: the leg sides are in B only.' });
  frame('J10b Compare · a field unreadable in one scan', compareScreen({ scans: [V9, B, C3], earlier: 'A', later: 'B', sections: ['Whole body'] }), { note: 'Variant V9: fat mass is treated as not entered in scan A, with the line under the table.' });
  frame('J11 Compare · largest text size', compareScreen({ scans: ALL, earlier: 'A', later: 'B' }), AX);

  group('K · Benchmarks (§10.5)', 'A benchmark is a dated reading with an optional condition note. The app shows the note beside the reading and compares nothing across notes differently.');
  frame('K1 Benchmark sheet · new', benchSheet({ open: 1, day: TODAY }));
  frame('K2 Benchmark sheet · a timed benchmark', benchSheet({ key: 'bench_dead_hang_s', value: num(M.BENCH_READINGS.bench_dead_hang_s[2].value, 0), day: '2031-03-31', note: M.BENCH_READINGS.bench_dead_hang_s[2].note, hint: P('Seconds, or minutes and seconds: %@ or %@', num(M.BENCH_READINGS.bench_dead_hang_s[2].value, 0), '1:30') }));
  frame('K3 Benchmark sheet · custom', benchSheet({ custom: 1, name: M.CUSTOM_BENCH.name, unit: M.CUSTOM_BENCH.unit, value: num(M.BENCH_READINGS.custom_bench_fixture_carry[0].value, 0), day: '2031-01-06' }));
  frame('K4 Benchmark sheet · invalid value', benchSheet({ key: 'bench_pushup_reps', value: `${num(M.BENCH_READINGS.bench_pushup_reps[1].value, 0)}.5`, day: '2031-02-17' }), { note: 'A repetition count with a decimal part.' });
  frame('K5 Benchmark detail · several readings', benchDetail({ key: 'bench_dead_hang_s' }));
  frame('K6 Benchmark detail · one reading', benchDetail({ key: 'custom_bench_fixture_carry' }));
  frame('K7 Benchmark detail · delete confirmation', benchDetail({ key: 'bench_dead_hang_s', confirm: 1 }), VIEW);
  frame('K8 Benchmark detail · largest text size', benchDetail({ key: 'bench_dead_hang_s' }), AX);

  group('L · Lab Book editor, report units (§10.6)', 'The existing editor with the lines stage 4B adds: every unit a report prints, and the conversion written out before saving. The stored number is always shown.');
  frame('L1 Lab Book editor · a marker with several options', editor({ key: 'vitamin_b12' }));
  frame('L2 Lab Book editor · typed in a unit that is not the stored one', editor({ key: 'ldl', unit: 'mg/dL', typed: M.blood('ldl').typed }));
  frame('L2 Lab Book editor · HbA1c typed in percent, formula shown', editor({ key: 'hba1c', unit: '%', typed: M.blood('hba1c').typed }));
  frame('L3 Lab Book editor · an identity option', editor({ key: 'ferritin', unit: 'ng/mL', typed: M.blood('ferritin').typed }));
  frame('L4 Lab Book editor · not a number', editor({ key: 'hba1c', unit: '%', typed: M.blood('hba1c').typed.replace('.', ',') }), { note: 'A comma typed on a device whose decimal separator is a full stop.' });
  frame('L5 Lab Book editor · after Save and add another', editorSaved('ldl'));
  frame('L6 Lab Book · history row of an annotated reading', markerHistory('hba1c'));
  frame('L7 Lab Book editor · flag off', editor({ key: 'ldl', unit: 'mg/dL', typed: M.blood('ldl').typed, flag: false }), { note: 'The editor as it is today: the legacy switcher and its existing line, no "Save and add another".' });

  group('M · Lab Book lists (§4.4, open question O4)', 'Scan figures appear in Lab Book as cards under the existing "Imaging" header and benchmarks under "Custom", with their catalogue names.');
  frame('M1 Lab Book · Imaging and Custom', labBookLists());

  group('W · Weigh-in history (§10.7)', 'Stage 1\'s screen. With the body record on, a scan\'s total mass is captioned "Lab Book · body scan", has no edit or delete here, and opens the scan.');
  frame('W1 Weigh-in history · a scan row, body record on', history(true), { note: 'Wed 15 Jan 2031. The weigh-in of 8 Jan represents its week; the scan of the same day does not (stage 1 ruling R44).' });
  frame('W2 Weigh-in history · a scan row, body record off', history(false), { note: 'An ordinary Lab Book row.' });

  group('P · Health row and Settings card (§10.1, §10.8)', 'Drawn here for context only. The combined frame set is the authority for the Health tab\'s "More health" card and the Settings section; Body record is the fourth entry of the shared order (Scorecard, Coach packet, Intake, Body record, Events, Niggle log, Recovery context, Timeline). A Health row is present only while its flag is on; the Settings card is always drawn.');
  frame('P1 Health row · with scans', healthRow(ALL));
  frame('P2 Health row · no scans', healthRow([]));
  frame('P3 Settings card · both off (the default)', settings(0, 0));
  frame('P4 Settings card · both on', settings(1, 1));

  group('O · Options the owner is asked to choose between', 'Each is the alternative to a recommendation that is in force in the frames above.');
  frame('O7 Scan sheet · figures that do not add up, Save blocked (open question O7)', scanSheet({ title: NEW(), day: B.day, today: B.day, typed: typedFrom(B, { fatFreeMass: [M.displayString(M.V3_FAT_FREE_TYPED, 1), 'kg'] }), weighIns: [], blockMismatch: 1 }), { ...VIEW, note: 'The alternative to H6.' });
  frame('O9 Lab Book · history row, typed unit first (open question O9)', markerHistory('hba1c', true), { note: 'The alternative to L6.' });
  frame('O13 Settings card · one switch (open question O13)', settings(0, 0, true), { note: 'The alternative to P3.' });

  return { G, USED, frames: () => G.flatMap(g => g.frames) };
})(typeof module !== 'undefined' ? require('./model.js') : S4);
if (typeof module !== 'undefined') module.exports = S4FRAMES;

/* ---------- browser only ---------- */
if (typeof document !== 'undefined') {
  // Local icons (noop.js ICONS is not edited; ic('cal') resolves #i-cal). Copied from round 6.
  document.body.insertAdjacentHTML('afterbegin', `<svg width="0" height="0" style="position:absolute"><defs>
<symbol id="i-cal" viewBox="0 0 24 24"><rect x="4" y="5.5" width="16" height="15" rx="3.5" fill="none" stroke="currentColor" stroke-width="1.9"/><path d="M4 10.5h16M8.5 3.5v4M15.5 3.5v4" fill="none" stroke="currentColor" stroke-width="1.9" stroke-linecap="round"/></symbol>
<symbol id="i-trash" viewBox="0 0 24 24"><path d="M5 7h14M10 4h4M7 7l1 12.5h8L17 7M10.5 11v5M13.5 11v5" fill="none" stroke="currentColor" stroke-width="1.9" stroke-linecap="round" stroke-linejoin="round"/></symbol>
</defs></svg>`);
  // ?only=J (or ?only=J1) shows just the frames whose id starts with that text. For review; not used for export.
  const ONLY = new URLSearchParams(location.search).get('only');
  const GROUPS = S4FRAMES.G.map(g => ({ ...g, frames: ONLY ? g.frames.filter(f => f.name.startsWith(ONLY)) : g.frames })).filter(g => g.frames.length);
  document.getElementById('boards').innerHTML = GROUPS.map(g => `<h2 class="grp-title">${g.title}</h2><p class="grp-note">${g.note}</p><div class="board">${g.frames.map(f =>
    `<section><div class="board-title">S4 / ${f.name}</div><div class="screen${f.cls ? ' ' + f.cls : ''}" ${f.attrs || ''} style="${f.style || ''}">${f.html}</div>${f.note ? `<p class="fnote">${f.note}</p>` : ''}</section>`).join('')}</div>`).join('');
  boot();
  // ?static=1&export=s4-frames.json: write the frames file for the Figma plugin (design/tools/serve.py --export).
  const EXPORT_NAME = new URLSearchParams(location.search).get('export');
  if (EXPORT_NAME) window.addEventListener('load', () => setTimeout(() => exportSvgFrames(EXPORT_NAME).then(r => { document.title = `exported ${r.frames.length} frames`; }), 400));
}
