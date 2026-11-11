/* Round S3 · Protein and intake (Stage 3). Frame builders.
   Every frame is a scenario from model.js (the Fixture Person at a stated moment), worded with strings.js.
   Nothing below types a result or a sentence by hand: numbers go through d(), words through t(), and labels
   that are not part of the app through a(). This file touches no DOM, so `node check.js` can build every
   frame and read its text. intake.js mounts the result in the page.
   EVERY VALUE IS SYNTHETIC ("Fixture Person" does not exist). */
if (typeof module !== 'undefined' && module.exports) { globalThis.IntakeModel = require('./model.js'); globalThis.IntakeStrings = require('./strings.js'); }
const IntakeFrames = (() => {
  // eslint-disable-next-line no-undef
  const M = IntakeModel, { t, d, a, dot } = IntakeStrings;
  const FX = M.FIXTURE, q = M.quantize, S = o => M.scenario(o);

  /* ---------- formatting ---------- */
  const MON = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'], DOW = ['Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat'];
  const MONL = ['January', 'February', 'March', 'April', 'May', 'June', 'July', 'August', 'September', 'October', 'November', 'December'];
  const DOWL = ['Sunday', 'Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday'];
  const wd = day => new Date(Date.UTC(+day.slice(0, 4), +day.slice(5, 7) - 1, +day.slice(8))).getUTCDay();
  const sdR = day => `${+day.slice(8)} ${MON[+day.slice(5, 7) - 1]}`, fdR = day => `${DOW[wd(day)]} ${sdR(day)}`;
  const sd = day => d(sdR(day)), fd = day => d(fdR(day));
  const longDate = day => d(`${DOWL[wd(day)]} ${+day.slice(8)} ${MONL[+day.slice(5, 7) - 1]}`);
  const N = n => Number(n).toLocaleString('en-US');      // %lld in a localised string groups thousands
  const hm = M.hhmm;
  const TODAY_DAY = M.NOW.afternoon.slice(0, 10), YESTERDAY = M.addDays(TODAY_DAY, -1);
  const FIRST_DAY = M.NOW.firstDay.slice(0, 10), GAP_DAY = M.NOW.gapDay.slice(0, 10);

  /* ---------- shared pieces (round 6's components, same classes) ---------- */
  const CHEV = '<span class="chev">›</span>';
  const navbar = (title, right) => `<div class="navbar"><div class="ibtn" data-ic="chev-l" data-s="22"></div><div class="ttl">${title}</div>${right ? `<div class="ibtn" data-ic="${right}" data-s="22"></div>` : '<div style="width:40px"></div>'}</div>`;
  const nrow = (title, val, ch = 1) => `<div class="nrow"><div class="t">${title}</div>${val ? `<div class="val">${val}</div>` : ''}${ch ? CHEV : ''}</div>`;
  const grp = rows => `<div class="wrap"><div class="card" style="padding:4px 18px">${rows.join('<div class="sep"></div>')}</div></div>`;
  const gh = (title, first) => `<div class="gh"${first ? ' style="padding-top:10px"' : ''}>${title}</div>`;
  const gf = (text, bad) => `<div class="gf${bad ? ' bad' : ''}">${text}</div>`;
  const tog = (title, on) => `<div class="nrow"><div class="t">${title}</div><div class="toggle${on ? ' on' : ''}"></div></div>`;
  const lab = (l, body) => `<div><div class="lab slab">${a(l)}</div>${body}</div>`;
  const KEYS = sepr => `<div class="keys">${['1', '2', '3', '4', '5', '6', '7', '8', '9', sepr, '0', '⌫'].map(k => `<span${k === sepr || k === '⌫' ? ' class="fn"' : ''}>${k === '' || k === '⌫' ? k : d(k)}</span>`).join('')}</div>`;
  const SK = (w, h, extra = '') => `<div class="skb" style="width:${w};height:${h}px${extra}"></div>`;
  // The ring is noop.js's .ring. It is neutral (the palette has no colour for intake) and it never changes
  // colour at the floor (§7.4). `green` is used by option frame O3 only.
  const ringEl = (frac, size, sw, o = {}) => {
    const extra = `${o.label != null ? ` data-label="${o.label}" data-fs="${o.fs || 30}" data-fw="500"` : ''}${o.icon ? ` data-icon="${o.icon}"` : ''}${o.style ? ` style="${o.style}"` : ''}`;
    return frac === 'empty' ? `<div class="ring" data-size="${size}" data-sw="${sw}" data-empty${extra}></div>`
      : `<div class="ring" data-size="${size}" data-sw="${sw}" data-p="${+(Math.min(1, frac) * 100).toFixed(3)}" data-c="${o.c || '--t1'}"${extra}></div>`;
  };

  /* ---------- §10.1 protein card ---------- */
  // Which caption wins when two apply is not in the specification; the order below is listed in the README.
  function cardVM(sc) {
    const p = sc.progress, v = p.shownGrams, P = sc.protein, ring = p.ringFraction;
    const time = !P ? null : P.source === 'nutritionCsv' ? t('f.imported') : sc.readAt != null ? d(hm(sc.readAt)) : null;
    if (sc.source == null) return { v: null, ring: null, c: t('setup.choose') };
    if (!sc.isToday) return P ? { v, ring, c: dot(t('p.dayTotal'), P.source === 'nutritionCsv' ? time : null) } : { v: null, ring: null, c: t('p.notMeasured') };
    if (!P && sc.health.outcome === 'failedRead') return { v: null, ring: null, c: t('r.could') };
    if (sc.targetsUnreadable) return { v, ring, c: t('set.attention') };
    if (p.state === 'noFloor') return { v, ring: null, c: t('p.noFloor') };
    if (p.state === 'notMeasured') return { v: null, ring: 'empty', c: t('p.nothing') };
    if (sc.stale) return { v, ring, tert: 1, c: t('f.lastRead', hm(sc.readAt)) };
    return { v, ring, c: dot(p.state === 'below' ? t('p.toFloor', N(p.remainingGrams)) : p.state === 'atFloor' ? t('p.met') : t('p.over', N(p.overGrams)), time) };
  }
  const SK_TILE = `<div class="yc">${SK('62%', 13)}${SK('54%', 24, ';margin-top:auto')}${SK('80%', 12)}</div>`;
  function proteinTile(sc, o = {}) {
    if (sc.loading) return SK_TILE;
    const c = cardVM(sc);
    const ring = c.ring == null ? '' : ringEl(c.ring, o.ax ? 64 : 34, 13, { c: o.green && c.ring === 1 ? '--recovery' : c.tert ? '--t3a' : '--t1' });
    return `<div class="yc motion"><div class="hd" style="color:var(--t1)"><span data-ic="fork" data-s="16"></span><b>${t('card.title')}</b>${CHEV}</div>
      <div class="pv"><div class="v num${c.v == null ? ' none' : c.tert ? ' tert' : ''}">${c.v == null ? '—' : `${d(N(c.v))}<small>${t('x.gUnit')}</small>`}</div>${ring}</div><div class="c">${c.c}</div></div>`;
  }
  const tile = (icon, tint, title, val, unit, cap) => `<div class="yc motion"><div class="hd" style="color:var(${tint})"><span data-ic="${icon}" data-s="16"></span><b>${title}</b>${CHEV}</div><div class="v num">${val}<small>${unit}</small></div><div class="c">${cap}</div></div>`;
  const C = M.CHROME;
  const STRESS = () => tile('bolt', '--stress', t('a.stress'), d(C.stress), d(C.stressOf), d(C.stressWord));
  const FIT = () => tile('run', '--recovery', t('a.fitness'), d(C.fitnessAge), d(C.fitnessUnit), t('a.asOf', sdR(C.fitnessAsOf)));
  const TODAY_AMB = `data-ambient="today:${C.sleep},${C.recovery},${C.strain}"`;
  const todayFrame = (sc, cards) => `<div class="sb"></div>
    <div class="hdr"><div><div class="lt">${t('a.today')}</div><div class="sub">${fd(sc.clock.today)}</div></div><div class="row gap10"><div class="pill"><span class="dot" style="background:var(--recovery)"></span><span class="num">${d(`${C.recovery}%`)}</span></div><div class="ibtn" data-ic="person" data-s="22"></div></div></div>
    <div class="wrap" style="margin-top:20px"><div class="card" style="padding:18px 14px 16px"><div class="rings" data-s="${C.sleep}" data-r="${C.recovery}" data-st="${C.strain}"></div></div></div>
    <div class="sec"><h3>${t('a.yourCards')}</h3><a>${t('a.edit')}${CHEV}</a></div>
    <div class="wrap"><div class="ycgrid">${cards}</div></div>
    <div class="tabbar" data-on="0"></div><div class="home"></div>`;
  const er = (sign, title, sub) => `<div class="nrow"><span class="pm ${sign}">${sign === 'add' ? '+' : '−'}</span><div class="grow1"><div class="t">${title}</div>${sub ? `<div class="rs">${sub}</div>` : ''}</div></div>`;
  const editor = () => `<div class="sb"></div><div class="navbar"><div class="lnk" style="margin:0;font-weight:500">${t('a.cancel')}</div><div class="ttl">${t('a.yourCards')}</div><div class="lnk" style="margin:0">${t('a.save')}</div></div>
    ${gh(t('a.shown'), 1)}${grp([er('rem', t('a.stress')), er('rem', t('a.fitness')), er('rem', t('a.vitality')), er('rem', t('a.vo2'))])}
    ${gh(t('a.more'))}${grp([er('add', t('card.title'), t('card.subtitle')), er('add', t('a.coupled')), er('add', t('a.coach')), er('add', t('a.hydration'))])}<div class="home"></div>`;

  /* ---------- §10.2 intake screen ---------- */
  const dayLine = sc => `<div class="dayline">${sc.isToday ? dot(t('a.today'), fd(sc.day)) : fd(sc.day)}</div>`;
  function proteinCard(sc, o = {}) {
    const p = sc.progress, shown = p.shownGrams, size = o.ax ? 170 : 104;
    const ring = p.ringFraction != null ? ringEl(p.ringFraction, size, 9, { c: o.green && p.ringFraction === 1 ? '--recovery' : '--t1' }) : p.state === 'notMeasured' ? ringEl('empty', size, 9) : '';
    const line = !sc.isToday ? (sc.protein ? t('p.dayTotal') : t('p.notMeasured'))
      : p.state === 'below' ? t('p.toFloor', N(p.remainingGrams)) : p.state === 'atFloor' ? t('p.met') : p.state === 'above' ? t('p.over', N(p.overGrams))
      : p.state === 'noFloor' ? t('p.noFloor') : t('p.nothing');
    const big = shown != null ? `<div class="big num"><span data-count="${shown}">${d(N(shown))}</span><small>${t('x.gUnit')}</small></div>` : `<div class="big num none">—</div>`;
    return `<div class="wrap mt12"><div class="card pc"><div class="lab">${t('card.title')}</div>
      <div class="prow">${ring}<div class="grow1">${big}${p.shownFloorGrams != null ? `<div class="lab of">${t('x.ofG', N(p.shownFloorGrams))}</div>` : ''}<div class="pl${shown == null ? ' none' : ''}">${line}</div></div></div>
      ${p.state === 'noFloor' ? `<div class="sep" style="margin-top:14px"></div>${nrow(t('x.setFloor'), '')}` : ''}</div></div>`;
  }
  // §7.5 and §11. No gauge, band or bar: the range is words. The note below the hard floor is one plain line.
  function energyBody(e, targets, unreadable) {
    const T = targets || {};
    const head = e.state === 'notMeasured' ? `<div class="eh none">—</div>` : e.state === 'soFar' ? `<div class="eh num">${t('e.soFar', N(e.shownKcal))}</div>` : `<div class="eh num">${t('x.kcal', N(e.shownKcal))}</div>`;
    const line = { notMeasured: () => t('e.notMeasured'), noRange: () => unreadable ? '' : t('e.noRange'), soFar: () => t('e.toLow', N(e.toLowEndKcal)),
      inRange: () => t('e.inRange', N(T.energyLowKcal), N(T.energyHighKcal)), aboveRange: () => t('e.above', N(e.overHighEndKcal)),
      belowRange: () => t('e.belowRange', N(T.energyLowKcal), N(T.energyHighKcal)), belowHardFloor: () => t('e.belowFloor', N(T.energyHardFloorKcal)) }[e.state]();
    return `<div class="lab">${t('e.title')}</div>${head}${line ? `<div class="el">${line}</div>` : ''}`;
  }
  const energyCard = sc => `<div class="wrap mt12"><div class="card ec">${energyBody(sc.energyState, sc.targets, sc.targetsUnreadable)}</div></div>`;
  const BOX = on => on ? '<svg width="24" height="24" viewBox="0 0 24 24"><rect x="2" y="2" width="20" height="20" rx="6" fill="#F5F5F7"/><polyline points="7.2,12.4 10.6,15.6 16.8,8.8" fill="none" stroke="#000000" stroke-width="2.3" stroke-linecap="round" stroke-linejoin="round"/></svg>'
    : '<svg width="24" height="24" viewBox="0 0 24 24"><rect x="2.9" y="2.9" width="18.2" height="18.2" rx="5.4" fill="none" stroke="#FFFFFF" stroke-opacity=".34" stroke-width="1.8"/></svg>';
  const supCard = sups => `<div class="wrap"><div class="card" style="padding:4px 18px">${sups.map(s => `<div class="sup">${BOX(s.state === 'ticked')}<div class="grow1"><div class="t">${d(s.name)}</div>${s.state === 'no' ? `<div class="rs">${t('sup.notTaken')}</div>` : ''}</div></div>`).join('<div class="sep"></div>')}</div></div>`;
  const supSection = sc => sc.supplements.length ? `<div class="sec"><h3>${t('sup.title')}</h3></div>${supCard(sc.supplements)}` : '';
  const PT = on => on ? '<svg width="10" height="10" viewBox="0 0 10 10"><circle cx="5" cy="5" r="3.4" fill="#F5F5F7"/></svg>' : '<svg width="10" height="10" viewBox="0 0 10 10"><circle cx="5" cy="5" r="3" fill="none" stroke="#F5F5F7" stroke-width="1.4"/></svg>';
  // 28 days: a smooth line with a gradient fill. No floor line, no band. A day at or above the floor is a
  // filled point, a day below it an open point, a day not measured breaks the line.
  function chartSection(sc, o = {}) {
    const h = sc.history, measured = h.filter(x => x.grams != null);
    let body;
    if (measured.length < 2) body = `<div class="lab">${t('chart.more')}</div>`;
    else {
      const v = h.map(x => x.grams == null ? 'x' : Math.floor(q(x.grams))).join(',');
      const m = h.map(x => x.grams == null ? 'x' : sc.floor == null ? 'n' : M.meetsFloor(x.grams, sc.floor) ? 1 : 0).join(',');
      body = `<svg class="dc" width="${o.ax ? 330 : 332}" height="${o.ax ? 176 : 150}" data-v="${v}" data-m="${m}" data-l0="${sd(h[0].day)}" data-l1="${sd(h[h.length - 1].day)}"${o.ax ? ' data-fs="24"' : ''}></svg>
        ${sc.floor == null ? '' : `<div class="lg"><span>${PT(1)}${t('x.atOrAbove')}</span><span>${PT(0)}${t('x.belowFloor')}</span></div>`}`;
    }
    return `<div class="sec"><h3>${t('x.last28')}</h3></div><div class="wrap"><div class="card cv">${body}</div></div>`;
  }
  function sourceSection(sc) {
    const P = sc.protein || sc.energy, H = sc.health, food = FX.foodApp.name, rows = [];
    const two = (l, r, cls = '') => `<div class="srcrow"><div class="sl">${l}</div>${r ? `<div class="sr${cls}">${r}</div>` : ''}</div>`;
    const msg = text => `<div class="smsg">${text}</div>`;
    const src = P ? P.source : sc.source === 'quickAdd' ? 'quickAdd' : 'appleHealth';
    if (src === 'nutritionCsv') rows.push(two(t('s.csv'), t('f.imported')), nrow(t('a.dataSources'), ''));
    else if (src === 'quickAdd') rows.push(two(t('s.here'), sc.readAt != null ? t('f.entered', hm(sc.readAt)) : ''));
    else {
      const time = P && sc.readAt != null ? (sc.stale ? t('f.lastRead', hm(sc.readAt)) : t('f.read', hm(sc.readAt))) : '';
      const both = P && sc.isToday && H.apps.length >= 2 && !H.admitted;
      if (both) rows.push(msg(t('s.two', H.apps[0].name, H.apps[1].name)) + two(t('s.health'), time, sc.stale ? ' stale' : ''), nrow(t('s.chooseOne'), ''));
      else rows.push(two(P ? t('s.from', food) : t('s.health'), time, sc.stale ? ' stale' : ''));
      if (!both && H.admitted) rows.push(nrow(t('set.apps'), d(H.apps.filter(x => H.admitted.includes(x.id)).map(x => x.name).join(', '))));
      if (H.outcome === 'failedRead') rows.push(msg(P ? t('r.failedAt', hm(H.attemptMinute)) : t('r.could')));
      if (H.outcome === 'preserved') rows.push(msg(t('r.empty', food)));
      rows.push(`<div class="srcrow"><div class="sl note">${t('c.editIn', food)}</div><div class="cta quiet">${t('f.readAgain')}</div></div>`);
    }
    return `<div class="sec"><h3>${t('set.source')}</h3></div>${grp(rows)}`;
  }
  function entriesSection(sc) {
    if (sc.source !== 'quickAdd') return '';
    const amt = (g, k) => `<div class="ex num">${g != null ? t('x.g', N(g)) : '—'}</div><div class="ex num">${k != null ? t('x.kcal', N(k)) : '—'}</div>`;
    const rows = sc.entries.map(e => `<div class="erow"><div class="et num">${d(hm(e.minute))}</div>${amt(e.proteinGrams, e.energyKcal)}${CHEV}</div>`);
    if (sc.restored && sc.protein) rows.push(`<div class="erow"><div class="et">${t('c.restored')}</div>${amt(sc.protein.value, sc.energy ? sc.energy.value : null)}<span class="cta quiet">${t('c.replace')}</span></div>`);
    return `<div class="sec"><h3>${t('x.entries')}</h3></div>${rows.length ? grp(rows) : ''}<div class="wrap mt12"><div class="btn primary">${t('q.add')}</div></div>`;
  }
  const attention = sc => sc.targetsUnreadable ? `<div class="wrap mt12"><div class="banner motion"><div><div class="bt">${t('set.attention')}</div></div><span class="cta">${t('a.settings')}</span></div></div>` : '';
  const screenTop = sc => `<div class="sb"></div>${navbar(t('set.intake'), sc.source === 'quickAdd' ? 'plus' : null)}`;
  const SKELETON = () => `<div class="sb"></div>${navbar(t('set.intake'), null)}<div class="dayline">${SK('120px', 13)}</div>
    <div class="wrap mt12"><div class="card">${SK('70px', 13)}<div class="prow"><div class="skb" style="width:104px;height:104px;border-radius:50%;flex:none"></div><div class="grow1">${SK('110px', 40)}${SK('80px', 13, ';margin-top:10px')}${SK('150px', 16, ';margin-top:10px')}</div></div></div></div>
    <div class="wrap mt12"><div class="card">${SK('110px', 13)}${SK('190px', 26, ';margin-top:10px')}${SK('240px', 13, ';margin-top:10px')}</div></div>
    <div class="sec">${SK('130px', 20)}</div><div class="wrap"><div class="card">${SK('100%', 130, ';border-radius:14px')}</div></div>
    <div class="sec">${SK('90px', 20)}</div><div class="wrap"><div class="card">${SK('70%', 14)}${SK('88%', 12, ';margin-top:10px')}</div></div><div class="home"></div>`;
  function intakeScreen(sc, o = {}) {
    if (sc.loading) return SKELETON();
    const top = screenTop(sc);
    if (sc.source == null) return `${top}<div class="wrap mt16"><div class="card"><div class="h2">${t('setup.choose')}</div><div style="height:6px"></div>
      ${[t('setup.health'), t('setup.here'), t('setup.none')].map(x => nrow(x, '')).join('<div class="sep"></div>')}</div></div><div class="home"></div>`;
    if (sc.source === 'none') return `${top}${dayLine(sc)}${supSection(sc)}<div style="height:16px"></div>${grp([nrow(t('set.cutoff'), d(hm(FX.cutoffMinuteOfDay)))])}<div class="home"></div>`;
    return `${top}${dayLine(sc)}${attention(sc)}${proteinCard(sc, o)}${energyCard(sc)}${supSection(sc)}${chartSection(sc, o)}${sourceSection(sc)}${entriesSection(sc)}<div class="home"></div>`;
  }

  /* ---------- §10.3 quick-add sheet. "Now" is the afternoon scenario; the sheet sits over the Path B screen. ---------- */
  function quickAdd(o = {}) {
    const sc = S({ source: 'quickAdd' }), day = o.day || sc.clock.today;
    const fld = (label, val, unit, k) => `<div class="fld${o.bad === k ? ' bad' : ''}"><span class="k">${label}</span><span class="v num">${val != null ? d(String(val)) : ''}${o.focus === k ? '<i class="caret"></i>' : ''}<small>${unit}</small></span></div>${o.bad === k ? `<div class="hint bad">${t('q.invalid')}</div>` : ''}`;
    const dayText = dd => dd === sc.clock.today ? dot(t('a.today'), fd(dd)) : fd(dd);
    const picker = o.picker ? `<div class="dayl">${Array.from({ length: FX.entryReachDays + 1 }, (_, i) => M.addDays(sc.clock.today, -i)).map(dd => `<div class="dr${dd === day ? ' on' : ''}"><span>${dayText(dd)}</span>${dd === day ? '<span data-ic="check" data-s="18"></span>' : ''}</div>`).join('')}</div>` : '';
    const presets = o.presets || [];
    const chips = presets.length ? `<div class="lab" style="margin-top:14px">${t('x.presets')}</div><div class="chips">${presets.map((p, i) => `<span class="chipx${o.presetOn === i ? ' on' : ''}"><b>${d(p.label)}</b><small>${dot(t('x.g', N(p.proteinGrams)), t('x.kcal', N(p.energyKcal)))}</small></span>`).join('')}<span class="chipx plus" data-ic="plus" data-s="16"></span></div>`
      : `<div class="addp"><span data-ic="plus" data-s="18"></span>${t('q.addPreset')}</div>`;
    return `<div class="sb"></div><div class="dim">${navbar(t('set.intake'), 'plus')}${dayLine(sc)}</div>
      <div class="sheet wsheet"${o.tall ? ' style="top:64px"' : ''}><div class="grabber"></div>
      <div class="sbar"><span>${t('a.cancel')}</span><span class="t">${t(o.title || 'q.add')}</span><span></span></div>
      <div class="lab" style="margin-top:4px">${t('x.day')}</div><div class="datechip${o.picker ? ' on' : ''}"><span data-ic="cal" data-s="16"></span>${dayText(day)}${CHEV}</div>${picker}
      ${fld(t('q.protein'), o.pro, t('x.gUnit'), 'pro')}${fld(t('q.calories'), o.kcal, t('x.kcalUnit'), 'kcal')}
      <div class="fld"><span class="k${o.label ? '' : ' ph'}">${o.label ? d(o.label) : t('q.label')}</span></div>
      ${o.picker ? '' : chips}
      ${o.fail ? `<div class="fail" style="margin-top:14px">${t('q.failed')}</div>` : ''}
      <div class="btn primary${o.off ? ' off' : ''}" style="margin-top:16px">${t(o.primary || 'a.save')}</div>
      ${o.del ? `<div class="btn danger" style="margin-top:10px"><span data-ic="trash" data-s="20"></span>${t('c.deleteEntry')}</div>` : ''}
      ${o.picker || o.nokeys ? '' : KEYS('.')}</div>`;
  }

  /* ---------- §10.5 settings card, §10.7 reminder rows ---------- */
  const NOTIF = () => `<div class="notif"><div class="ai" data-ic="today" data-s="22"></div><div class="grow1"><div class="row gap8"><div class="nt">${t('n.title')}</div><div class="nw">${d(hm(FX.cutoffMinuteOfDay))}</div></div><div class="nb">${t('n.body')}</div></div></div>`;
  // o: flag, source, why, floor {val, bad, focus, msg}, range {low, high, hard, bad: 'range' | 'hard'}, apps, sups, reminder ('off' | 'on' | 'denied'), windDown, keys
  function settings(o = {}) {
    const flag = o.flag !== false, source = o.source || 'appleHealth', T = { ...FX.targets, ...(o.range || {}) }, R = o.range || {}, fl = o.floor || {};
    const head = `<div class="sb"></div>${navbar(t('a.settings'), null)}${gh(t('set.intake'), 1)}${grp([tog(t('x.switch'), flag)])}${gf(t('x.sentence'))}`;
    if (!flag) return `${head}<div class="home"></div>`;
    if (o.range && M.targetsValid(T)) throw new Error('this frame needs an invalid range');
    const fbox = (val, cls) => `<span class="fbox num${cls ? ` ${cls}` : ''}">${d(String(val))}${cls && cls.includes('on') ? '<i class="caret"></i>' : ''}</span>`;
    const seg = `<div class="srow"><div class="t">${t('set.source')}</div><div class="seg">${[['none', t('x.srcNone')], ['appleHealth', t('s.health')], ['quickAdd', t('x.srcHere')]].map(([k, l]) => `<span${k === source ? ' class="on"' : ''}>${l}</span>`).join('')}</div>${o.why ? `<div class="rs" style="margin-top:8px">${t(o.why)}</div>` : ''}</div>`;
    const floorVal = fl.val != null ? fl.val : FX.proteinFloorGrams;
    const targets = [
      `<div class="nrow"><div class="t">${t('set.floor')}</div>${fbox(floorVal, `${fl.bad ? 'bad' : ''}${fl.focus ? ' on' : ''}`)}<span class="un">${t('x.gUnit')}</span></div>`,
      `<div class="nrow"><div class="t">${t('set.range')}</div>${fbox(T.energyLowKcal, R.bad === 'range' ? 'bad' : '')}<span class="un">–</span>${fbox(T.energyHighKcal, R.bad === 'range' ? 'bad' : '')}<span class="un">${t('x.kcalUnit')}</span></div>`,
      `<div class="nrow"><div class="t">${t('set.hard')}</div>${fbox(T.energyHardFloorKcal, R.bad === 'hard' ? 'bad' : '')}<span class="un">${t('x.kcalUnit')}</span></div>`];
    const sups = o.sups === undefined ? [FX.supplement.name] : o.sups;
    const supRows = sups.map(n => nrow(d(n), '')).concat(sups.length < FX.maxSupplements ? [`<div class="nrow"><span class="pm add">+</span><div class="t">${t('set.addSup')}</div></div>`] : []);
    const rem = o.reminder || 'off';
    const triggers = M.cutoffTriggers(FX.cutoffMinuteOfDay, o.windDown || {});
    const silent = triggers.some(x => !x.playsSound);
    return `${head}
      ${grp([seg])}${source === 'none' ? gf(t('x.noSource')) : ''}
      <div style="height:12px"></div>${grp(targets)}${fl.msg ? gf(fl.msg, 1) : ''}${R.bad === 'range' ? gf(t('x.lowAboveHigh'), 1) : ''}${R.bad === 'hard' ? gf(t('x.hardAboveLow'), 1) : ''}
      ${source === 'appleHealth' && o.apps ? `<div style="height:12px"></div>${grp([nrow(t('set.apps'), d(o.apps.map(x => x.name).join(', ')))])}` : ''}
      ${gh(t('set.sups'))}${grp(supRows)}${gf(t('sup.coach'))}
      <div style="height:20px"></div>${grp([nrow(t('set.cutoff'), d(hm(FX.cutoffMinuteOfDay))), tog(t('set.reminder'), rem === 'on')])}
      ${rem === 'on' ? gf(silent ? t('set.silent') : t('x.reminderNote')) : rem === 'off' ? gf(t('x.reminderOff')) : ''}
      ${rem === 'denied' ? `<div class="wrap mt12"><div class="banner"><div><div class="bt">${t('a.notifOff')}</div><div class="bd">${t('a.notifBody')}</div></div><span class="cta">${t('a.openSettings')}</span></div></div>` : ''}
      ${rem === 'on' && !o.keys ? `${gh(t('x.looks'))}<div class="wrap">${NOTIF()}</div>` : ''}
      ${o.keys ? `<div class="kb">${KEYS('')}</div>` : ''}<div class="home"></div>`;
  }
  // iOS draws this sheet. Only the sentence in the middle is NOOP's (§11, last row).
  const NO_HOME = html => html.replace('<div class="home"></div>', '');
  const healthSheet = () => `<div class="dim">${NO_HOME(settings({ source: 'none' }))}</div><div class="sheet wsheet" style="top:64px"><div class="grabber"></div>
    <div class="sbar"><span></span><span class="t">${t('sys.hkTitle')}</span><span></span></div>
    <div class="hkapp"><div class="ai" data-ic="today" data-s="26"></div><div class="h2">${t('sys.noop')}</div></div>
    <div class="hkp">${t('perm')}</div>
    <div class="lab" style="margin:18px 2px 8px">${t('sys.hkRead')}</div>
    <div class="card" style="padding:4px 18px">${tog(t('sys.hkEnergy'), 1)}<div class="sep"></div>${tog(t('sys.hkProtein'), 1)}</div>
    <div class="btn primary" style="margin-top:22px">${t('sys.hkAllow')}</div><div class="btn secondary" style="margin-top:10px">${t('sys.hkDeny')}</div></div>`;

  /* ---------- §10.7 the notification, on the Lock Screen ---------- */
  const lock = (day, clockMinute, when) => `<div style="height:54px"></div><div class="lockdate">${longDate(day)}</div><div class="lockclock">${d(hm(clockMinute))}</div>
    <div class="lnwrap"><div class="lnotif"><div class="appicon" data-ic="today" data-s="22"></div><div class="grow1"><div class="row sp"><span class="t">${t('n.title')}</span><span class="tm">${when}</span></div><div class="b">${t('n.body')}</div></div></div></div><div class="home"></div>`;

  /* ---------- §10.8 widget: four families ---------- */
  const srcName = s => s === 'quickAdd' ? t('s.here') : t('s.health');
  function widgets(ws, o = {}) {
    const k = ws.kind, has = k === 'below' || k === 'met' || k === 'above', dim = ws.stale ? ' dimmed' : '';
    const tint = ws.stale ? '--t3a' : o.green && ws.fraction === 1 ? '--recovery' : '#FFFFFF';
    const time = has || k === 'noFloor' ? (ws.stale ? t('w.lastRead', hm(ws.readAtMinute)) : t('w.asOf', hm(ws.readAtMinute))) : '';
    const word = k === 'below' ? t('w.toGo', N(ws.toGo)) : has ? t('w.met') : k === 'nothing' ? t('w.nothing') : k === 'notSetUp' ? t('w.setup') : t('w.noFloor');
    const head = `<span class="wh">${t('w.protein')}</span>`;
    const g = n => `${d(N(n))}<small>${t('x.gUnit')}</small>`;
    let small, medium, rect, circ;
    if (k === 'placeholder') {
      const bar = (w, h) => `<i class="rd" style="width:${w}px;height:${h}px"></i>`;
      small = `<div class="row sp" style="align-items:flex-start">${bar(58, 12)}<i class="rd rdc" style="width:44px;height:44px"></i></div><div>${bar(96, 20)}<div style="height:8px"></div>${bar(70, 11)}</div>`;
      medium = `<div class="wm"><i class="rd rdc" style="width:96px;height:96px"></i><div class="grow1">${bar(58, 12)}<div style="height:14px"></div>${bar(120, 30)}<div style="height:12px"></div>${bar(96, 16)}<div style="height:10px"></div>${bar(150, 11)}</div></div>`;
      rect = `${bar(64, 12)}<div style="height:8px"></div>${bar(110, 11)}`; circ = '<i class="rd rdc" style="width:40px;height:40px"></i>';
    } else {
      const sRing = has ? ringEl(ws.fraction, 44, 11, { c: tint }) : k === 'nothing' ? ringEl('empty', 44, 11) : '';
      small = `<div class="row sp" style="align-items:flex-start">${head}${sRing}</div>
        <div>${k === 'noFloor' ? `<div class="n${dim}" style="font-size:40px">${g(ws.grams)}</div>` : ''}<div class="${k === 'noFloor' ? 'c' : `wt${dim}`}">${word}</div>${time ? `<div class="c">${time}</div>` : ''}</div>`;
      const mRing = has ? ringEl(ws.fraction, 96, 8, { c: tint }) : k === 'nothing' ? ringEl('empty', 96, 8) : '';
      const figure = has ? `<div class="n${dim}" style="font-size:40px">${d(N(ws.grams))}<small>${t('x.ofG', N(ws.floorGrams))}</small></div>` : k === 'noFloor' ? `<div class="n${dim}" style="font-size:40px">${g(ws.grams)}</div>`
        : k === 'nothing' && ws.floorGrams != null ? `<div class="n none" style="font-size:40px">—<small>${t('x.ofG', N(ws.floorGrams))}</small></div>` : '';
      medium = `<div class="wm">${mRing}<div class="grow1">${head}${figure}<div class="wt2${dim}">${k === 'above' ? dot(word, t('w.over', N(ws.over))) : word}</div>
        ${time ? `<div class="c">${dot(srcName(ws.source), time)}</div>` : ''}${ws.stale ? `<div class="c">${t('w.refresh')}</div>` : ''}</div></div>`;
      const short = has || k === 'noFloor' ? d(hm(ws.readAtMinute)) : '';
      rect = `<b>${t('w.protein')}</b><span>${ws.stale ? t('w.lastRead', hm(ws.readAtMinute)) : k === 'noFloor' ? dot(t('x.g', N(ws.grams)), short) : dot(word, short)}</span>`;
      const cs = ws.stale ? 'opacity:.45' : '';
      circ = k === 'below' ? ringEl(ws.fraction, 48, 9, { c: '#FFFFFF', label: d(N(ws.toGo)), style: cs }) : has ? ringEl(1, 48, 9, { c: '#FFFFFF', icon: 'tick', style: cs })
        : k === 'noFloor' ? `<span class="cg num"${cs ? ` style="${cs}"` : ''}>${d(N(ws.grams))}</span>` : k === 'nothing' ? ringEl('empty', 48, 9, { label: '—', fs: 30 }) : '<span class="cg">—</span>';
    }
    return `<div style="height:26px"></div><div class="wfam">
      <div><div class="wg m">${medium}</div><div class="wlabel">${a('Medium')}</div></div>
      <div class="wrow"><div><div class="wg s">${small}</div><div class="wlabel">${a('Small')}</div></div>
        <div class="wlock"><div class="acc"><div class="rect">${rect}</div></div><div class="wlabel">${a('Rectangular, Lock Screen')}</div>
          <div class="acc" style="margin-top:18px"><div class="circ">${circ}</div></div><div class="wlabel">${a('Circular, Lock Screen')}</div></div></div></div>`;
  }
  const widgetOf = (o, extra) => { const sc = S(o); return widgets(M.widgetState(M.widgetReading(sc), sc.clock.minuteOfDay), extra); };

  /* ---------- frames ---------- */
  const G = []; let cur;
  const group = (title, note) => { cur = { title, note, frames: [] }; G.push(cur); };
  // `clock` is the scenario's "now"; intake.js writes it into the status bar so a frame shows one time of day.
  const AFTERNOON = hm(M.clock(M.NOW.afternoon).minuteOfDay);
  const frame = (id, title, html, o = {}) => cur.frames.push({ id, name: `${id} ${title}`, html, clock: AFTERNOON, ...o });
  const STILL = { attrs: 'data-nomotion' };
  const scr = (id, title, o, note, extra = {}) => { const sc = S(o); frame(id, title, intakeScreen(sc, extra), { note, cls: extra.ax ? 'ax' : '', clock: hm(sc.clock.minuteOfDay) }); };
  const tdy = (id, title, o, note) => { const sc = S(o); frame(id, title, todayFrame(sc, proteinTile(sc) + STRESS() + FIT()), { attrs: TODAY_AMB, note, clock: hm(sc.clock.minuteOfDay) }); };
  const set = (id, title, o, note, extra = {}) => frame(id, title, settings(o), { note, ...STILL, ...extra });
  const wdg = (id, title, html, note) => frame(id, title, html, { cls: 'wall', attrs: 'data-nomotion', style: 'min-height:0;padding:0 0 36px', note });
  const STATE_WORDS = { soFar: 'under the range', aboveRange: 'above the range', belowHardFloor: 'below the hard floor', belowRange: 'below the range, not below the hard floor', inRange: 'in the range' };
  const stale = FX.staleMinutesAgo, both = [FX.foodApp, FX.otherApp];
  const foodOnly = M.aggregate(M.SAMPLES, { admitted: [FX.foodApp.id] }).days[FIRST_DAY].proteinGrams;

  group('A · Protein card in Your cards (§10.1)', 'A value card like the other tiles: grams so far, a small ring to the floor and one caption with its time. It is <b>not in the default selection</b> and exists only while Intake is on. The ring and the figure are in the primary text colour: the palette has no colour for intake and none is invented. The ring completes at the floor and stays complete; the figure keeps counting.');
  tdy('A1', 'Today · below the floor', {}, 'The Fixture Person on Wed 29 Jan 2031 at 15:20, Apple Health read at 15:10 (§13.6: fresh is ten minutes before now).');
  tdy('A2', 'Today · at the floor', { grams: M.TODAY.atFloor }, 'The §13.3 edit row: exactly at the floor. The ring is complete; nothing else changes.');
  tdy('A3', 'Today · above the floor', { grams: M.TODAY.above }, 'The ring stays complete and the figure keeps counting. No second lap, no colour change.');
  tdy('A4', 'Today · stale', { readMinutesAgo: stale }, 'Apple Health last read four hours ago (§13.6). The figure and ring go to the tertiary colour and the caption gives the time.');
  frame('A5', 'Card · every state', `<div class="sb"></div><div class="navbar"><div style="width:40px"></div><div class="ttl">${a('Card states')}</div><div style="width:40px"></div></div>
    <div class="wrap"><div class="ycgrid" style="row-gap:6px">${[
      ['Loading', { loading: 1 }], ['No source chosen', { source: null }], ['No floor set', { floor: null }], ['Not measured today', { now: M.NOW.gapDay, grams: null, kcal: null }],
      ['Below the floor', {}], ['At the floor', { grams: M.TODAY.atFloor }], ['Above the floor', { grams: M.TODAY.above }], ['Stale: read more than three hours ago', { readMinutesAgo: stale }],
      ['Apple Health read failed, nothing stored for today', { grams: null, kcal: null, outcome: 'failedRead' }], ['A past day selected, measured', { day: YESTERDAY }],
      ['A past day selected, not measured', { now: M.NOW.gapDay, day: M.addDays(GAP_DAY, -1), grams: null }], ['Targets unreadable', { targets: null }],
      ['Entered here: the time of the last entry', { source: 'quickAdd' }], ['A value from a CSV import has no time', { valueSource: 'nutritionCsv' }],
    ].map(([l, o]) => lab(l, proteinTile(S(o)))).join('')}</div></div><div class="home"></div>`, STILL);
  frame('A6', 'Card · AX5', `<div class="sb"></div><div class="navbar"><div style="width:40px"></div><div class="ttl">${t('a.today')}</div><div style="width:40px"></div></div>
    <div class="sec" style="padding-top:12px"><h3>${t('a.yourCards')}</h3><a>${t('a.edit')}${CHEV}</a></div>
    <div class="wrap"><div class="ycgrid">${[{}, { grams: M.TODAY.above }, { readMinutesAgo: stale }, { now: M.NOW.gapDay, grams: null, kcal: null }].map(o => proteinTile(S(o), { ax: 1 })).join('')}</div></div><div class="home"></div>`, { cls: 'ax', ...STILL });
  frame('A7', 'Your cards editor · adding the card', editor(), { ...STILL, note: 'Protein sits under "More cards" with its subtitle. The editor lists it only while Intake is on.' });

  group('B · Intake screen (§10.2)', 'Top to bottom: protein ring and numbers, calories line, supplements, the last 28 days, source and freshness, then entries (Path B) or the Apple Health note (Path A). The calories card has no gauge and no band: the range is words. The chart is a line with a gradient fill; a day at or above the floor is a filled point, a day below it an open point, and a day that was not measured breaks the line. There is no floor line.');
  scr('B1', 'Intake · below the floor, calories so far', {}, 'Path A. Wed 29 Jan 2031, 15:20. The day is open, so the calories line makes no judgement (§7.5).');
  scr('B2', 'Intake · at the floor', { grams: M.TODAY.atFloor });
  scr('B3', 'Intake · above the floor', { grams: M.TODAY.above }, 'The figure keeps counting and a second line gives the amount over.');
  frame('B4', 'Intake · loading', intakeScreen(S({ loading: 1 })), STILL);
  // (B5 onward use scr(), which also sets the status-bar time from the scenario.)
  scr('B5', 'Intake · no source chosen', { source: null }, 'Flag on, nothing chosen yet: the three choices of §10.5, each with its sentence.');
  scr('B6', 'Intake · source None kept (Path C)', { source: 'none' }, 'Only the supplements section and a row to the cutoff setting. No ring, no chart.');
  scr('B7', 'Intake · no floor set', { floor: null }, 'The numbers without a ring, and a row to set the floor. Chart points carry no floor mark.');
  scr('B8', 'Intake · nothing logged today', { now: M.NOW.gapDay, grams: null, kcal: null }, 'Wed 12 Feb 2031, 08:10. Stage 1\'s week 6 has four days with no protein figure: the line breaks there and is never drawn across. No read time is shown because a day with no row has none.');
  scr('B9', 'Intake · calories not measured', { kcal: null }, 'Protein was logged without energy. "Not measured", never 0.');
  scr('B10', 'Intake · no calorie range set', { targets: {} }, 'The amount is shown alone.');
  scr('B11', 'Intake · calories above the range', { kcal: M.energyCase('aboveRange').kcal }, 'Reported while the day is open, since more food cannot lower it (§7.5).');
  scr('B12', 'Intake · a past day, calories in the range', { day: YESTERDAY }, 'Tue 28 Jan selected. A closed day: "Day total", no remaining.');
  scr('B13', 'Intake · a past day, calories below the range', { day: M.addDays(TODAY_DAY, -2) }, 'Mon 27 Jan selected. 2,100 kcal is the hard floor itself, so it is below the range and not below the floor.');
  scr('B14', 'Intake · after the cutoff, calories below the hard floor', { now: M.NOW.evening, grams: M.storedProtein(TODAY_DAY), kcal: M.energyCase('belowHardFloor').kcal }, '20:40, after the 20:00 cutoff, so the day is closed. One plain line, in the same colour as every other state. It never appears while the day is open.');
  frame('B15', 'Intake · calories line, every state', `<div class="sb"></div><div class="navbar"><div style="width:40px"></div><div class="ttl">${a('Calories line states')}</div><div style="width:40px"></div></div>
    <div class="wrap"><div class="stack">${M.ENERGY_CASES.map(c => [c.kcal == null ? 'Not measured' : `Day ${c.open ? 'open' : 'closed'}, ${STATE_WORDS[c.state]}`, M.energy(c.kcal, FX.targets, c.open), FX.targets])
      .concat([['No range set', M.energy(M.TODAY.kcal, {}, true), {}]]).map(([l, e, tg]) => lab(l, `<div class="card ec">${energyBody(e, tg, false)}</div>`)).join('')}</div></div><div class="home"></div>`, { ...STILL, note: 'The eight rows of §13.4 plus "No range set", each run through the model.' });
  scr('B16', 'Intake · two apps wrote today', { now: M.NOW.firstDay, grams: M.TODAY.above, apps: both }, 'Mon 9 Dec 2030, the §13.3 row "s1 to s9, all sources": 105 g. Both are counted and named, with the choice offered.');
  scr('B17', 'Intake · stale', { readMinutesAgo: stale }, 'The time in the secondary colour, and "Read again".');
  scr('B18', 'Intake · Apple Health could not be read', { readMinutesAgo: stale, outcome: 'failedRead' }, 'The last figures stay. The failed attempt has its own time.');
  scr('B19', 'Intake · Apple Health returned no food entries', { now: M.NOW.firstDay, grams: null, kcal: null, outcome: 'preserved' }, 'No claim that access was denied: the app cannot know.');
  scr('B20', 'Intake · first day, fewer than two days of history', { now: M.NOW.firstDay }, 'Mon 9 Dec 2030, the §13.3 row "s1 to s8".');
  scr('B21', 'Intake · a value from a CSV import', { day: '2031-01-08', valueSource: 'nutritionCsv' }, 'Wed 8 Jan selected; its only value is an older CSV import. The caption names the source and the row leads to Data Sources.');
  scr('B22', 'Intake · targets need attention', { targets: null }, 'The stored calorie targets could not be read. The amount is shown alone and a row leads to Settings. The protein floor is stored elsewhere and is unaffected.');
  scr('B23', 'Intake · entered here (Path B)', { source: 'quickAdd' }, 'The same day by quick-add. The time is the last entry\'s. Every entry opens for edit or delete.');
  scr('B24', 'Intake · entered here, a restored total', { source: 'quickAdd', day: YESTERDAY, restored: 1 }, 'After a restore the database carries totals and no entry list: one row, which can be replaced.');
  scr('B25', 'Intake · a past day, not measured', { now: M.NOW.gapDay, day: M.addDays(GAP_DAY, -1), grams: null, kcal: null }, 'Tue 11 Feb selected.');
  scr('B26', 'Intake · AX5', {}, 'Ring above the numbers, one column.', { ax: 1 });

  const one = FX.supplement.name, four = Array.from({ length: FX.maxSupplements }, (_, i) => i ? `${one} ${i + 1}` : one);
  group('C · Supplement tick (§10.6)', 'A tick is a Journal answer. An unticked box is "not recorded", never a recorded "no". No time is shown (the Journal stores none) and no count of days appears anywhere.');
  frame('C1', 'Supplements · every state', `<div class="sb"></div><div class="navbar"><div style="width:40px"></div><div class="ttl">${a('Supplement states')}</div><div style="width:40px"></div></div>
    <div class="stack">${[['Not recorded today', [{ name: one, state: 'notRecorded' }]], ['Ticked', [{ name: one, state: 'ticked' }]], ['Answered "no" in the Journal', [{ name: one, state: 'no' }]],
      ['A past day selected: that day\'s state, editable within the Journal\'s reach', [{ name: one, state: 'ticked' }]],
      ['Four configured (the add row in Settings is hidden)', four.map((name, i) => ({ name, state: ['ticked', 'notRecorded', 'no', 'ticked'][i] }))]].map(([l, sups]) => `<div><div class="lab slab" style="padding-left:18px">${a(l)}</div>${supCard(sups)}</div>`).join('')}
      <div><div class="lab slab" style="padding-left:18px">${a('No supplement configured: the section is absent')}</div></div></div><div class="home"></div>`, { ...STILL, note: 'The second, third and fourth names in the last card are the fixture name with a number; the fixture defines one supplement.' });

  const preset = [FX.preset], e2 = M.entriesFor(M.TODAY.below)[1];
  group('D · Quick-add sheet (§10.3, Path B)', 'Protein and calories, either may be left empty. In these frames "now" is Wed 29 Jan 2031, 15:20. The keypad is a drawing of the system decimal pad.');
  frame('D1', 'Quick-add · default, nothing entered', quickAdd({ focus: 'pro', presets: preset, off: 1 }), { ...STILL, note: 'Save is disabled until an amount is entered.' });
  frame('D2', 'Quick-add · preset tapped', quickAdd({ pro: FX.preset.proteinGrams, kcal: FX.preset.energyKcal, label: FX.preset.label, presets: preset, presetOn: 0 }), STILL);
  frame('D3', 'Quick-add · one amount entered', quickAdd({ pro: M.sample('s9').amount, focus: 'pro', presets: preset }), { ...STILL, note: 'Calories left empty: this entry says nothing about energy.' });
  frame('D4', 'Quick-add · invalid amount', quickAdd({ pro: FX.preset.proteinGrams, kcal: FX.quickAddMaximum + 1, bad: 'kcal', focus: 'kcal', presets: preset, off: 1 }), STILL);
  frame('D5', 'Quick-add · backdating', quickAdd({ pro: FX.preset.proteinGrams, kcal: FX.preset.energyKcal, picker: 1, day: M.addDays(TODAY_DAY, -2) }), { ...STILL, note: 'Today and the seven days before it, the reach the Journal has.' });
  frame('D6', 'Quick-add · editing an entry', quickAdd({ title: 'c.editEntry', pro: e2.proteinGrams, kcal: e2.energyKcal, del: 1, nokeys: 1 }), { ...STILL, note: 'The 13:00 entry of B23.' });
  frame('D7', 'Quick-add · restored total', quickAdd({ title: 'c.restored', primary: 'c.replace', day: YESTERDAY, pro: M.storedProtein(YESTERDAY), kcal: M.storedEnergy(YESTERDAY), nokeys: 1 }), { ...STILL, note: 'Opened from the row in B24. Replacing writes one real entry holding the old amounts.' });
  frame('D8', 'Quick-add · save failed', quickAdd({ pro: FX.preset.proteinGrams, kcal: FX.preset.energyKcal, label: FX.preset.label, presets: preset, presetOn: 0, fail: 1, tall: 1 }), STILL);
  frame('D9', 'Quick-add · no presets yet', quickAdd({ focus: 'pro', off: 1 }), STILL);
  frame('D10', 'Quick-add · AX5', quickAdd({ pro: FX.preset.proteinGrams, kcal: FX.preset.energyKcal, focus: 'kcal', presets: preset, presetOn: 0, tall: 1 }), { cls: 'ax', attrs: 'data-nomotion', style: 'min-height:1500px' });

  const posNote = 'Third in Settings: below Coach packet, above Body record (rulings addendum A1). The combined frame set is the authority for the position.';
  group('E · Settings card (§10.5) and the reminder rows (§10.7)', 'The card holds the feature switch, so the switch and one sentence show with the flag off; every other row needs the flag on. The protein floor here is the same stored value as the rules sheet\'s "Daily floor".');
  set('E1', 'Settings · Intake off', { flag: false }, posNote);
  set('E2', 'Settings · on, source None', { source: 'none' }, 'The card and the widget have nothing to show. Supplements and the cutoff still work (Path C).');
  frame('E3', 'Settings · choosing Apple Health', healthSheet(), { ...STILL, note: 'HealthKit\'s own sheet, once, for the two types. iOS draws it; its wording here is approximate. Only the sentence is NOOP\'s.' });
  set('E4', 'Settings · Apple Health, every row', { apps: both }, '"Apps to count" appears when more than one app is known.');
  set('E5', 'Settings · Apple Health not available', { source: 'none', why: 'x.hkUnavailable' }, 'The row reverts to None and says why.');
  set('E6', 'Settings · this build cannot read Apple Health', { source: 'none', why: 'x.hkEntitlement' }, 'The entitlement-missing state of the bridge.');
  set('E7', 'Settings · range invalid, low above high', { range: { energyLowKcal: M.energyCase('aboveRange').kcal, bad: 'range' } }, 'The fields are marked and nothing is saved.');
  set('E8', 'Settings · hard floor above the low end', { range: { energyHardFloorKcal: FX.targets.energyHighKcal, bad: 'hard' } });
  set('E9', 'Settings · protein floor field opened', { floor: { focus: 1 }, keys: 1 }, 'The stored floor as a whole number with its unit. Whole-number keypad.');
  set('E10', 'Settings · enter whole grams', { floor: { val: FX.proteinFloorGrams - 0.5, bad: 1, focus: 1, msg: t('floor.whole') }, keys: 1 }, 'Stage 1 ruling R45: the entry is refused and nothing is saved.');
  set('E11', 'Settings · stored floor above the maximum', { floor: { val: FX.proteinFloorMaximumGrams + 1, bad: 1, focus: 1, msg: t('x.floorMax', FX.proteinFloorMaximumGrams) }, keys: 1 }, 'A hand-edited settings string. The field opens marked, as in the rules sheet.');
  set('E12', 'Settings · Enter here, no supplement configured', { source: 'quickAdd', sups: [] }, 'Path B. With no supplement the section on the intake screen is absent.');
  set('E13', 'Settings · four supplements', { sups: four }, 'The add row is hidden at four.');
  set('E14', 'Settings · reminder on, with the notification', { reminder: 'on' });
  set('E15', 'Settings · reminder, notifications denied', { reminder: 'denied' }, 'The switch has reverted. The row leads to system Settings.');
  set('E16', 'Settings · reminder near the wind-down reminder', { reminder: 'on', windDown: M.CUTOFF_CASES[1].windDown }, '§13.5 row 2: wind-down at 20:20 every day, so all seven cutoff notifications are silent.');
  set('E17', 'Settings · AX5', { apps: both, reminder: 'on' }, '', { cls: 'ax' });

  const near = M.CUTOFF_CASES[1], nearMinute = near.windDown[1];
  if (M.cutoffTriggers(near.cutoff, near.windDown).some(x => x.playsSound)) throw new Error('F2 needs a silent trigger');
  group('F · The notification (§10.7)', 'One a day at most, opt-in, off by default. Title and body are fixed text: no amount, no floor, no judgement and no supplement name.');
  frame('F1', 'Notification · at the cutoff time', lock(TODAY_DAY, FX.cutoffMinuteOfDay, t('sys.now')), { cls: 'wall', ...STILL });
  frame('F2', 'Notification · delivered silently near the wind-down reminder', lock(TODAY_DAY, nearMinute, t('sys.ago', nearMinute - near.cutoff)), { cls: 'wall', ...STILL, note: 'Same text. Delivered with no sound and at the passive level because the wind-down reminder fires at 20:20; it still appears in the list.' });

  group('W · Widget (§10.8)', 'Kind "Protein", four families. A value is never drawn without its time. The payload holds only the day, the grams, the floor, the source and the read time: no calories, no supplement name, no entry label, no app name. Widgets do not scale to the accessibility sizes.');
  wdg('W1', 'Widget · below the floor', widgetOf({}));
  wdg('W2', 'Widget · at the floor', widgetOf({ grams: M.TODAY.atFloor }));
  wdg('W3', 'Widget · above the floor', widgetOf({ grams: M.TODAY.above }), 'Only the medium family adds the amount over.');
  wdg('W4', 'Widget · no floor set', widgetOf({ floor: null }));
  wdg('W5', 'Widget · nothing logged today', widgetOf({ now: M.NOW.gapDay, grams: null, kcal: null }));
  wdg('W6', 'Widget · stale', widgetOf({ readMinutesAgo: stale }), 'Apple Health figure older than three hours. The timeline switches to this state without the app running.');
  wdg('W7', 'Widget · not set up', widgetOf({ flag: false }), 'Intake off, source None, or never published. Also what the gallery\'s new kind draws while Intake is off (question I6).');
  wdg('W8', 'Widget · gallery placeholder', widgets({ kind: 'placeholder' }), 'No sample figure, as the other personal widgets do.');
  wdg('W9', 'Widget · entered here', widgetOf({ source: 'quickAdd' }), 'Path B: the medium family names the source; the time is the last entry\'s.');

  group('O · Options for the owner', 'Each is a choice the specification leaves to the owner or one this round had to make. The recommendation is named in the README.');
  frame('O1', 'Option · apps to count, the choice', `<div class="dim">${NO_HOME(intakeScreen(S({ now: M.NOW.firstDay, grams: M.TODAY.above, apps: both })))}</div><div class="sheet wsheet"><div class="grabber"></div>
    <div class="sbar"><span>${t('a.cancel')}</span><span class="t">${t('set.apps')}</span><span></span></div>
    <div class="card" style="padding:4px 18px;margin-top:8px">${both.map(x => `<div class="nrow"><div class="t">${d(x.name)}</div><span data-ic="check" data-s="20"></span></div>`).join('<div class="sep"></div>')}</div>
    <div class="btn primary" style="margin-top:18px">${t('a.save')}</div></div>`, { ...STILL, note: 'Question I4. Opened by "Choose one" in B16. Both are counted by default, as the Health app does.' });
  scr('O2', 'Option · one app counted', { now: M.NOW.firstDay, grams: foodOnly, apps: both, admitted: [FX.foodApp.id] }, 'The §13.3 row "admitted app.fixture.food": 95 g. B16 is the other option (both counted, 105 g).');
  scr('O3', 'Option · ring in Recovery green at the floor (not the specification)', { grams: M.TODAY.atFloor }, 'The specification says the ring never changes colour (§7.4), and B2 draws that. This is the alternative: stage 1\'s "met" green once the floor is met. It would apply to the card and the widget as well.', { green: 1 });
  scr('O4', 'Option · the 28-day curve ends yesterday', { historyEndsYesterday: 1 }, 'B1 includes today\'s running figure as the last point, where it reads as a low day until the evening. This option leaves today to the ring.');

  const frames = G.flatMap(g => g.frames);
  const api = { G, frames, PREFIX: 'S3 / ' };
  if (typeof module !== 'undefined' && module.exports) module.exports = api;
  return api;
})();
