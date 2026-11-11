/* Round S2 · Coach packet (Stage 2). Presenter and frame builders. Pure string building: no DOM, so it also
   runs under node (check.js). Every interface string goes through say() (the specification's §11, or a named
   proposal) or ctx() (text that belongs to another surface: the Health tab, stage 1's scorecard, iOS itself).
   Every number comes from model.js. EVERY VALUE IS SYNTHETIC ("Fixture Person" does not exist). */
const S2Frames = (() => {
  const M = typeof require !== 'undefined' ? require('./model.js') : S2Model;

  /* ---------- §11, word for word ---------- */
  const SPEC = {
    settingsTitle: 'Coach packet',
    blurb: 'One block of text with your recent numbers, for pasting to your coach. Off by default. NOOP sends it nowhere.',
    title: 'Coach packet',
    rowDetail: 'Copy your numbers for your coach',
    toolbarLabel: 'Coach packet',
    range: 'Range', days: '%lld days',
    'sec.scorecard': 'Scorecard', 'sec.weigh-ins': 'Weigh-ins', 'sec.recovery-sleep': 'Recovery and sleep', 'sec.trends': 'Trends', 'sec.activity': 'Activity',
    size: '%@ · %lld days',
    copy: 'Copy', share: 'Share', tryAgain: 'Try again',
    copied: 'Copied to this iPhone only. It leaves the clipboard at %@.',
    stale: 'The clipboard still holds the earlier packet',
    nothing: 'Nothing was measured in this range',
    scOff: 'The scorecard is off, so these sections say so',
    allOff: 'Switch on at least one section',
    blocked: 'The packet was not created because it contained something that identifies a device or an account.',
    unavailable: 'Your data could not be read. Try again.',
    intentTitle: 'Get Coach Packet',
    intentDesc: 'Returns the coach packet as text, using the sections and range chosen in NOOP.',
    errOff: 'Coach packet is switched off in NOOP.',
    errStarting: 'NOOP is still starting. Run the shortcut again.',
    errStore: 'NOOP could not read your data.',
  };
  /* ---------- not in §11: proposals, listed in the README ---------- */
  const PROPOSED = {
    done: 'Done',
    sizeOver: '%@ · %lld days · larger than expected',
    sizeTime: '%@ · %lld days · %@',
  };

  const SAID = new Set(), USED = new Set(), PREVIEWS = {};
  const esc = s => String(s).replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;').replace(/"/g, '&quot;');
  const fill = (tpl, args) => { let i = 0; return tpl.replace(/%lld|%@/g, () => args[i++]); };
  const say = (key, ...args) => { const tpl = key in SPEC ? SPEC[key] : PROPOSED[key]; if (tpl == null) throw new Error(`no string "${key}"`); USED.add(key); const s = fill(tpl, args); SAID.add(s); return esc(s); };
  const ctx = s => { SAID.add(String(s)); return esc(s); };

  /* ---------- dates, as round 6 writes them ---------- */
  const MON = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'], DOW = ['Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat'];
  const sd = d => `${+d.slice(8)} ${MON[+d.slice(5, 7) - 1]}`;
  const dow = d => DOW[new Date(M.dnum(d) * 864e5).getUTCDay()];
  const fd = d => `${dow(d)} ${sd(d)}`;

  /* ---------- the one clock. Every frame is the Fixture Person at the packet's own generated time. ---------- */
  const TODAY = M.CLOCK.today, NOW = M.clockPlus(M.CLOCK.generatedAt, 0);
  // Design inputs, not results: Copy is tapped 20 s after the packet appears; a later change regenerates at 07:43:05.
  const COPIED_AFTER_SECONDS = 20, REGENERATED_AT = '2031-03-16T07:43:05+01:00';
  const sb = (t = NOW) => `<div class="sb" data-t="${t}"></div>`;

  /* ---------- shared pieces (round 6's components, same classes) ---------- */
  const tile = (icon, tint, title, val, unit, cap) => `<div class="yc motion"><div class="hd" style="color:var(${tint})"><span data-ic="${icon}" data-s="16"></span><b>${ctx(title)}</b><span class="chev">›</span></div><div class="v num">${ctx(val)}<small>${ctx(unit)}</small></div><div class="c">${ctx(cap)}</div></div>`;
  const lrow = (icon, tint, title, detail) => `<div class="lr"><div class="icon sm" style="color:var(${tint})" data-ic="${icon}" data-s="18"></div><div class="grow1"><div class="t">${title}</div>${detail ? `<div class="d">${detail}</div>` : ''}</div><span class="chev">›</span></div>`;
  const SEP = '<div class="sep"></div>';
  const gh = (t, first) => `<div class="gh"${first ? ' style="padding-top:10px"' : ''}>${t}</div>`;
  const gf = t => `<div class="gf">${t}</div>`;
  const tog = (t, on) => `<div class="nrow"><div class="t">${t}</div><div class="toggle${on ? ' on' : ''}"></div></div>`;
  const grp = rows => `<div class="wrap"><div class="card" style="padding:4px 18px">${rows.join(SEP)}</div></div>`;

  /* ---------- stage 1's scorecard on this day, worded as round 6 words it (context for the entry points) ---------- */
  function stage1() {
    const r = M.assemble().result, ph = r.input.phase, P = r.input.parameters, V = r.verdict, J = r.judgedWeekStart;
    if (V.kind !== 'reduceCarbs' || M.S1.weeksBetween(J, TODAY) !== 1) throw new Error('the scorecard context is written for the fixture read on 2031-03-16 only');
    const slow = r.rules.find(x => x.rule === 'slowLoss'), met = Object.values(r.signals).filter(s => s.state === 'met').length;
    return { weight: `${M.fx(r.currentWeightKg, 1)} kg`, due: 'Weigh-in due this week', week: `week of ${sd(J)}`,
      phaseLab: `Phase · week ${M.S1.weeksBetween(ph.startDay, TODAY) + 1}`, phaseName: ph.name,
      phaseMeta: `Target ${M.fx(ph.targetWeightKg, 1)} kg · started ${fd(ph.startDay)} · band ${M.fx(ph.rateLowPercentPerWeek, 2)}–${M.fx(ph.rateHighPercentPerWeek, 2)}% per week`,
      title: `Your rule: take ${-V.calorieChangeKcal} kcal from carbohydrate`, line: `Loss was under ${+P.slowLossThresholdKgPerWeek.toFixed(2)} kg per week for ${slow.consecutiveWeeks} weeks.`,
      met: `${met} of 4 signals met` };
  }

  /* ---------- A · entry points ---------- */
  const moreRows = (scorecard, packet) => { const s1 = stage1(); return [
    scorecard ? lrow('scale', '--t1', ctx('Scorecard'), ctx(`${s1.due} · ${s1.weight}`)) : null,
    packet ? lrow('doc', '--t1', say('title'), say('rowDetail')) : null,
    lrow('heart', '--heart', ctx('Live heart rate')), lrow('chart', '--hrv', ctx('All metrics')), lrow('thermo', '--temp', ctx('Skin temperature')),
    lrow('spark', '--recovery', ctx('Vitality')), lrow('chart', '--recovery', ctx('Contributors')), lrow('refresh', '--breath', ctx('Strap sync')), lrow('book', '--hrv', ctx('Lab Book'))].filter(Boolean); };
  function healthTab(scorecard, packet) {
    const last = M.DAILY.find(r => r.day === TODAY);
    return `${sb()}<div class="hdr"><div><div class="lt">${ctx('Health')}</div><div class="sub">${ctx(`${dow(TODAY)}, ${sd(TODAY)}`)}</div></div><div class="ibtn" data-ic="person" data-s="22"></div></div>
    <div class="sec"><h3>${ctx('Vitals')}</h3><a>${ctx('All metrics')}<span class="chev">›</span></a></div>
    <div class="wrap"><div class="ycgrid">${tile('trend', '--hrv', 'HRV', M.int(last.hrv), 'ms', 'Last night')}${tile('heart', '--heart', 'Resting heart rate', String(last.rhr), 'bpm', 'Last night')}</div></div>
    <div class="sec"><h3>${ctx('More')}</h3></div>
    <div class="wrap"><div class="card" style="padding:4px 18px">${moreRows(scorecard, packet).join(SEP)}</div></div>
    <div class="tabbar" data-on="3"></div><div class="home"></div>`;
  }
  const healthAx = `${sb()}<div class="hdr"><div><div class="lt">${ctx('Health')}</div></div></div>
    <div class="sec"><h3>${ctx('More')}</h3></div>
    <div class="wrap"><div class="card" style="padding:4px 18px">${moreRows(true, true).slice(0, 4).join(SEP)}</div></div><div class="home"></div>`;
  function scorecardTop(icon) {
    const s = stage1();
    return `${sb()}<div class="navbar three"><div class="ibtn" data-ic="chev-l" data-s="22"></div><div class="ttl">${ctx('Scorecard')}</div><div class="row gap8 end"><div class="ibtn" data-ic="${icon}" data-s="20"></div><div class="ibtn" data-ic="plus" data-s="22"></div></div></div>
    <div class="dim"><div class="phase"><div class="lab">${ctx(s.phaseLab)}</div><div class="nm">${ctx(s.phaseName)}</div><div class="meta">${ctx(s.phaseMeta)}</div></div>
    <div class="wrap mt16"><div class="banner"><div><div class="bt">${ctx(s.due)}</div><div class="bd">${ctx(`The verdict below is from the ${s.week}.`)}</div></div><span class="cta">${ctx('Log weigh-in')}</span></div></div>
    <div class="wrap mt16"><div class="card verdict"><div class="row1"><span class="lab">${ctx(`Verdict · ${s.week}`)}</span><span class="lab">${ctx(s.met)}</span></div>
      <div class="vt long">${ctx(s.title)}</div><div class="rt">${ctx(s.line)}</div><div class="rt t2 own">${ctx('This is your own rule applied to your own numbers. Nothing has been changed.')}</div></div></div>
    <div class="sec"><h3>${ctx('Four signals')}</h3><a>${ctx(s.week)}</a></div></div><div class="home"></div>`;
  }

  /* ---------- B · the packet sheet ----------
     o: { id, scene: assemble options, mode: 'loading' | 'regen', prev: assemble options of the text still on screen,
          copied, stale, share, over, withTime, wrap, compact, skipTo, ax } */
  const skLines = [62, 74, 88, 70, 46, 64, 92, 78, 0, 38, 90, 44, 96, 72, 68, 60].map(w => w ? `<div class="skb" style="width:${w}%;height:9px;margin:3px 0"></div>` : '<div style="height:15px"></div>').join('');
  function preview(o, doc, lines) {
    PREVIEWS[o.id] = lines.join('\n');
    return `<div class="pv${o.wrap ? ' wrap' : ''}${o.mode === 'regen' ? ' dimmed' : ''}">${lines.map(l => { const ind = l.startsWith('  '); return `<div class="pl${ind ? ' in' : ''}">${esc(ind ? l.slice(2) : l)}</div>`; }).join('')}</div>`;
  }
  function shareSheet(doc) {
    const app = (icon, name) => `<div class="shapp"><i data-ic="${icon}" data-s="26"></i>${ctx(name)}</div>`;
    return `<div class="sheet shsheet"><div class="grabber"></div>
      <div class="shhead"><div class="icon" data-ic="doc" data-s="22"></div><div class="grow1"><div class="t">${esc(doc.lines[0])}</div><div class="d">${ctx(`Plain Text · ${M.sizeLabel(doc.bytes)}`)}</div></div><div class="ibtn" data-ic="x" data-s="18"></div></div>
      <div class="shapps">${app('upload', 'AirDrop')}${app('chat', 'Messages')}${app('send', 'Mail')}${app('doc', 'Notes')}</div>
      <div class="card" style="padding:4px 18px"><div class="nrow"><div class="t">${ctx('Save to Files')}</div><span data-ic="folder" data-s="20"></span></div></div></div>`;
  }
  function packetSheet(o) {
    const scene = o.scene || {}, rangeDays = scene.rangeDays || M.DEFAULT_RANGE, on = M.SECTIONS.filter(s => !(scene.off || []).includes(s));
    const out = o.mode === 'loading' ? null : M.assemble(o.mode === 'regen' ? o.prev : scene), ready = out && out.state === 'ready', allOff = on.length === 0;
    const busy = o.mode === 'loading' || o.mode === 'regen';
    const secRow = s => `<div class="srow"><span>${say(`sec.${s}`)}</span><div class="toggle${on.includes(s) ? ' on' : ''}"></div></div>${s === 'weigh-ins' && scene.scorecardOff ? `<div class="scap">${say('scOff')}</div>` : ''}`;
    const controls = `<div class="prange"><span class="k">${say('range')}</span><div class="seg">${M.RANGES.map(n => `<span${n === rangeDays ? ' class="on"' : ''}>${say('days', n)}</span>`).join('')}</div></div>`
      + (o.compact ? `<div class="chips">${M.SECTIONS.map(s => `<span class="pchip${on.includes(s) ? ' on' : ''}">${on.includes(s) ? '<i data-ic="check" data-s="14"></i>' : ''}${say(`sec.${s}`)}</span>`).join('')}</div>${scene.scorecardOff ? `<div class="pcap">${say('scOff')}</div>` : ''}`
        : `<div class="psec">${M.SECTIONS.map(secRow).join('')}</div>`);
    let meta = '', body = '', actions = '';
    if (o.mode === 'loading') { meta = '<div class="pmeta"><div class="skb" style="width:118px;height:12px;margin:3px 0"></div></div>'; body = `<div class="pv">${skLines}</div>`; }
    else if (ready) {
      const size = M.sizeLabel(o.over ? out.budget + 1 : out.bytes);
      meta = o.copied ? `<div class="pmeta ok"><i data-ic="check" data-s="16"></i><span>${say('copied', M.copyPlan(out, COPIED_AFTER_SECONDS).expiresAt)}</span></div>`
        : `<div class="pmeta${o.mode === 'regen' ? ' dimmed' : ''}"><span class="num">${o.over ? say('sizeOver', size, out.rangeDays) : o.withTime ? say('sizeTime', size, out.rangeDays, M.clockPlus(out.generatedAt, 0)) : say('size', size, out.rangeDays)}</span></div>`;
      const cap = o.stale ? 'stale' : allOff ? 'allOff' : out.nothingMeasured ? 'nothing' : null;
      if (cap) meta += `<div class="pcap">${say(cap)}</div>`;
      const from = o.skipTo ? out.lines.indexOf(o.skipTo) : 0; if (from < 0) throw new Error(`no line "${o.skipTo}"`);
      body = preview(o, out, out.lines.slice(from));
    } else body = `<div class="pmsg"><span data-ic="${out.state === 'blocked' ? 'shield' : 'info'}" data-s="30"></span><div class="mt">${say(out.state)}</div></div>`;
    const off = busy || allOff ? ' off' : '';
    actions = ready || o.mode === 'loading'
      ? `<div class="pact${o.compact ? ' sidebyside' : ''}"><div class="btn primary${off}"><span data-ic="paste" data-s="20"></span>${say('copy')}</div><div class="btn secondary${off}"><span data-ic="upload" data-s="20"></span>${say('share')}</div></div>`
      : `<div class="pact"><div class="btn primary"><span data-ic="refresh" data-s="20"></span>${say('tryAgain')}</div></div>`;
    return `${sb(M.clockPlus((ready && out.generatedAt) || M.CLOCK.generatedAt, 0))}<div class="sheet psheet${o.share ? ' under' : ''}"><div class="grabber"></div>
      <div class="sbar"><span>${say('done')}</span><span class="t">${say('title')}</span><span></span></div>
      ${controls}${meta}${body}${actions}</div>${o.share ? shareSheet(out) : ''}`;
  }

  /* ---------- C · Settings ---------- */
  const settings = on => `${sb()}<div class="navbar"><div class="ibtn" data-ic="chev-l" data-s="22"></div><div class="ttl">${ctx('Settings')}</div><div style="width:40px"></div></div>
    ${gh(ctx('Scorecard'), 1)}${grp([tog(ctx('Weekly weigh-in and scorecard'), 1), tog(ctx('Weekly reminder'), 0)])}
    ${gf(ctx('A weekly weigh-in and one verdict from the rules you set. Off by default. Everything stays on this iPhone.'))}
    ${gh(say('settingsTitle'))}${grp([tog(say('settingsTitle'), on)])}${gf(say('blurb'))}<div class="home"></div>`;

  /* ---------- D · the Shortcuts action (§10.4). The Shortcuts app is drawn, not designed. ---------- */
  function shortcutOk() {
    const doc = M.assemble(); PREVIEWS.D1 = doc.lines.join('\n');
    return `${sb()}<div class="navbar"><div class="lnk" style="margin:0;font-weight:500">${ctx('Cancel')}</div><div class="ttl">${ctx('New Shortcut')}</div><div class="lnk" style="margin:0">${ctx('Done')}</div></div>
    <div class="wrap mt12"><div class="card"><div class="row gap12"><div class="icon" style="background:#000;border:1px solid rgba(255,255,255,.14)" data-ic="today" data-s="22"></div><div class="grow1"><div class="lbl">${say('intentTitle')}</div><div class="src" style="margin-top:2px">${ctx('NOOP')}</div></div></div>
      <div class="lab" style="margin-top:12px">${say('intentDesc')}</div></div></div>
    ${gh(ctx('Result · text'))}<div class="wrap"><div class="pv fixed">${doc.lines.map(l => { const ind = l.startsWith('  '); return `<div class="pl${ind ? ' in' : ''}">${esc(ind ? l.slice(2) : l)}</div>`; }).join('')}</div></div><div class="home"></div>`;
  }
  const shortcutFail = () => `${sb()}<div class="navbar"><div style="width:40px"></div><div class="ttl">${ctx('Shortcut results')}</div><div style="width:40px"></div></div>
    ${[['Flag on, data loaded', null, 'The text'], ['Flag off', 'errOff'], ['App still starting after eight seconds', 'errStarting'], ['Blocked by the scan', 'blocked'], ['Store unreadable', 'errStore'], ['Phone locked', null, 'The system asks for unlock first']]
    .map(([state, key, plain], i) => `${gh(ctx(state), i === 0)}<div class="wrap"><div class="card${key ? '' : ' quiet'}" style="padding:14px 18px"><div class="${key ? 'fmsg' : 'lab'}">${key ? say(key) : ctx(plain)}</div></div></div>`).join('')}<div class="home"></div>`;

  /* ---------- R · the complete text ---------- */
  function fullText(id, scene) {
    const doc = M.assemble(scene); PREVIEWS[id] = doc.lines.join('\n');
    return `<div class="lab">${ctx(`${M.sizeLabel(doc.bytes)} · ${doc.bytes} bytes · budget ${doc.budget} bytes`)}</div>
      <div class="pv full">${doc.lines.map(l => { const ind = l.startsWith('  '); return `<div class="pl${ind ? ' in' : ''}">${esc(ind ? l.slice(2) : l)}</div>`; }).join('')}</div>`;
  }

  /* ---------- frames ---------- */
  const G = []; let cur;
  const group = (title, note) => { cur = { title, note, frames: [] }; G.push(cur); };
  const frame = (id, title, html, o = {}) => cur.frames.push({ id, title, name: `${id} ${title}`, html, ...o });
  const STILL = { attrs: 'data-nomotion' };
  const HEALTH_AMB = { attrs: `data-ambient='[["--heart",350,20,190,0.2],["--hrv",50,0,200,0.2]]'` };
  const sheet = (id, title, o = {}, note) => frame(id, title, packetSheet({ id, ...o }), { attrs: 'data-nomotion', cls: o.ax ? 'ax flow' : '', style: o.ax ? 'padding-bottom:0' : '', note });
  const ALL_OFF = { off: M.SECTIONS.slice() };

  group('A · Entry points (§10.1)', 'Present only while "Coach packet" is on in Settings. Both open the same sheet. There is no Today card (P1, P15).');
  frame('A1', 'Health tab · Coach packet row', healthTab(true, true), { ...HEALTH_AMB, note: 'Second in the one order of ruling A1: directly beneath Scorecard, above the rows the tab already has.' });
  frame('A2', 'Health tab · scorecard off, packet row first', healthTab(false, true), HEALTH_AMB);
  frame('A3', 'Health tab · Coach packet off', healthTab(true, false), { ...HEALTH_AMB, note: 'The default. No row; the tab is exactly as stage 1 left it.' });
  frame('A4', 'Scorecard · toolbar item, document icon (option 1)', scorecardTop('doc'), { attrs: 'data-nomotion', note: 'The second toolbar item beside the weigh-in button. The screen beneath is dimmed here only to point at the toolbar; its layout is round 6 frame B12. Accessibility label: "Coach packet".' });
  frame('A5', 'Scorecard · toolbar item, share icon (option 2)', scorecardTop('upload'), { attrs: 'data-nomotion', note: 'The same item with the system share mark. It reads as "send this somewhere", but the sheet\'s primary action is Copy.' });
  frame('A6', 'Health tab · AX5', healthAx, { cls: 'ax', attrs: 'data-nomotion' });

  group('B · Packet sheet (§10.2)', 'Top to bottom: title, range, five section switches, the size line, the preview, Copy, Share. The preview is the exact text that will leave, in the monospaced token, and is not selectable. Each preview is produced by <code>model.js</code> from the Fixture Person; the whole text is in group R.');
  sheet('B1', 'Packet sheet · loading', { mode: 'loading' }, 'Controls visible, actions disabled, skeleton where the preview will be.');
  sheet('B2', 'Packet sheet · ready', {}, 'The §13 fixture: 14 days, every section on. Long lines run off the right edge; the preview scrolls both ways.');
  sheet('B3', 'Packet sheet · ready, 7 days', { scene: { rangeDays: 7 } });
  sheet('B4', 'Packet sheet · nothing measured in the range', { scene: { data: 'none' }, skipTo: '== WEIGH-INS ==' }, 'Golden G2: no rows, no baselines, no readings. The packet is still valid and shows its dashes. The preview is drawn scrolled to the weigh-ins.');
  sheet('B5', 'Packet sheet · scorecard off in the app', { scene: { scorecardOff: true }, skipTo: '== SCORECARD ==' }, 'Both switches stay usable. The preview is drawn scrolled to the scorecard section.');
  sheet('B6', 'Packet sheet · a section switched off', { scene: { off: ['activity'] } }, 'Activity is off. The header\'s switched-off line names it.');
  sheet('B7', 'Packet sheet · every section off', { scene: ALL_OFF }, 'The preview is the header and the notes. Copy and Share are disabled.');
  sheet('B8', 'Packet sheet · regenerating after a change', { mode: 'regen', scene: { rangeDays: 7 }, prev: {} }, 'The range has just been changed to 7 days. The 14-day text stays, dimmed, until the new one arrives.');
  sheet('B9', 'Packet sheet · copied', { copied: 1 }, 'The confirmation replaces the size line. The time is the copy time plus ten minutes, the one value also given to the system.');
  sheet('B10', 'Packet sheet · copied, then a control changed', { scene: { off: ['trends'], generatedAt: REGENERATED_AT }, stale: 1 }, 'Trends was switched off after copying. The confirmation has cleared and the new text is on screen.');
  sheet('B11', 'Packet sheet · share', { share: 1 }, 'The system share sheet over this sheet. It has no Copy of its own (P8). Its rows are iOS\'s, drawn for position only.');
  sheet('B12', 'Packet sheet · blocked', { scene: { phaseName: M.IDENTIFIERS[3] } }, 'Reached here by naming the phase with the fixture\'s invented account address. No text exists, so there is nothing to copy or share.');
  sheet('B13', 'Packet sheet · unavailable', { scene: { storeUnreadable: true } });
  sheet('B14', 'Packet sheet · larger than the budget', { over: 1 }, 'Not reachable by construction. Drawn at one byte over the 14-day budget. The actions stay enabled.');
  sheet('B15', 'Packet sheet · AX5', { ax: 1 }, 'Controls stack. The preview keeps its size and scrolls both ways.');
  sheet('B16', 'Packet sheet · copied, AX5', { ax: 1, copied: 1 });
  sheet('B17', 'Packet sheet · blocked, AX5', { ax: 1, scene: { phaseName: M.IDENTIFIERS[3] } });

  group('O · Options for the owner', 'Three places where the specification leaves room or disagrees with itself. B2 is the specification as written; each frame here changes one thing.');
  sheet('O1', 'Packet sheet · long lines wrap (proposal)', { wrap: 1 }, 'Every character is visible without scrolling sideways. The text that leaves is unchanged: wrapping is on screen only.');
  sheet('O2', 'Packet sheet · size line with the generated time (proposal)', { withTime: 1 }, '§10.2 asks for "a line with the size and the generated time"; §11 gives the size and the days only.');
  sheet('O3', 'Packet sheet · compact controls (proposal)', { compact: 1 }, 'Sections as five toggling chips and the two actions side by side, so the preview gets about twice the height.');

  group('C · Settings (§10.3)', 'One card, one switch, off by default. No reminder and no notification. Second in the one order, directly after Scorecard. The cards of later stages follow it and are not drawn in this round.');
  frame('C1', 'Settings · Coach packet off', settings(false));
  frame('C2', 'Settings · Coach packet on', settings(true));
  frame('C3', 'Settings · AX5', settings(true), { cls: 'ax' });

  group('D · Shortcuts action (§10.4)', 'The action returns the same text as the sheet. It has no parameters, no dialog, no Siri phrase, and needs an unlocked phone. The Shortcuts app is iOS\'s own; only the strings are this stage\'s.');
  frame('D1', 'Shortcuts · the action and its result', shortcutOk(), STILL);
  frame('D2', 'Shortcuts · every result', shortcutFail(), STILL);

  group('R · The text that leaves (§7)', 'The complete packet, every line unwrapped, as the model renders it. R1 is the specification\'s §7.9 example; check.js compares the two byte for byte.');
  frame('R1', 'Packet text · complete, 14 days', fullText('R1', {}), { attrs: 'data-nomotion', cls: 'text', style: 'width:1480px;min-height:0' });
  frame('R2', 'Packet text · nothing measured', fullText('R2', { data: 'none' }), { attrs: 'data-nomotion', cls: 'text', style: 'width:1480px;min-height:0' });

  const frames = G.flatMap(g => g.frames);
  return { groups: G, frames, SPEC, PROPOSED, SAID, USED, PREVIEWS, model: M };
})();
if (typeof module !== 'undefined') module.exports = S2Frames;
