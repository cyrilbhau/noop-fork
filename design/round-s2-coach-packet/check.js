/* Round S2 checks that need no browser.  Run:  node design/round-s2-coach-packet/check.js
   They prove the model and the frame builders execute, that the packet text is the specification's, and that
   every piece of text in every frame is a specification string, a named proposal, context from another surface,
   or a line of the packet. They do NOT prove anything about how a frame looks: nothing here renders. */
const fs = require('fs'), path = require('path');
const M = require('./model.js'), F = require('./frames.js');
const spec = fs.readFileSync(path.join(__dirname, '../../docs/personal/superapp/specs/stage-2.md'), 'utf8');
let failed = 0;
const ok = (name, pass, detail = '') => { if (!pass) failed++; console.log(`${pass ? 'ok  ' : 'FAIL'}  ${name}${detail ? `  ${detail}` : ''}`); };
const between = (a, b) => spec.slice(spec.indexOf(a), spec.indexOf(b));

/* 1. the model against the specification's own example (§7.9, golden G1) */
const ex = between('### 7.9 Complete example', '### 7.10 Size budget'), gold = ex.slice(ex.indexOf('```\n') + 4, ex.lastIndexOf('\n```')) + '\n';
const g1 = M.assemble();
ok('G1: model text equals §7.9 byte for byte', g1.text === gold, `${g1.bytes} bytes, specification says 6,221`);
if (g1.text !== gold) { const a = g1.text.split('\n'), b = gold.split('\n'); a.forEach((l, i) => { if (l !== b[i]) console.log(`      line ${i + 1}\n      model: ${l}\n      spec:  ${b[i]}`); }); }
ok('G1: 6,221 UTF-8 bytes', g1.bytes === 6221 && Buffer.byteLength(gold) === 6221);
ok('G1: size line reads as the §10.2 example', `${M.sizeLabel(g1.bytes)} · ${g1.rangeDays} days` === '6.2 kB · 14 days', `${M.sizeLabel(g1.bytes)} · ${g1.rangeDays} days`);
ok('G1: copied 20 s after generation expires at the §10.2 example time', M.copyPlan(g1, 20).expiresAt === '07:52', M.copyPlan(g1, 20).expiresAt);
ok('G1: privacy scan finds nothing', M.privacyViolations(g1.text, M.IDENTIFIERS).length === 0);

/* 2. the other documents the frames use */
const g2 = M.assemble({ data: 'none' }), t2 = g2.text;
ok('G2: the §13.3 lines for no data', ['averages: no data in range', 'HRV: baseline not available; range mean — over 0 nights', 'RHR: baseline not available; range mean — over 0 nights',
  'steps average: — (no step data in range)', 'workouts: none recorded in range', 'weekly: no weigh-ins yet', 'current weight: —'].every(l => t2.split('\n').includes(l)) && g2.nothingMeasured);
ok('G2: no measured value is printed as zero', !/(recovery|strain|sleep|HRV|RHR|weight|waist) 0\b/.test(t2));
const off = M.assemble({ scorecardOff: true }).text;
ok('scorecard off: both sections say so', off.includes('not available: the scorecard is switched off in the app') && off.includes('weekly: not available (the scorecard is switched off in the app)'));
const act = M.assemble({ off: ['activity'] }).text;
ok('a section off: header names it and the section is gone', act.includes('\nswitched-off: activity\n') && !act.includes('== ACTIVITY =='));
const none = M.assemble({ off: M.SECTIONS.slice() });
ok('every section off: header and notes only', none.text.includes('\nsections: none\n') && (none.text.match(/^== .* ==$/gm) || []).join() === '== NOTES ==');
ok('blocked: an account address in the phase name fails closed', M.assemble({ phaseName: M.IDENTIFIERS[3] }).state === 'blocked');
ok('unavailable', M.assemble({ storeUnreadable: true }).state === 'unavailable');
[7, 14, 28].forEach(n => { const d = M.assemble({ rangeDays: n }); ok(`${n} days: under the §7.10 budget`, d.bytes < d.budget, `${d.bytes} of ${d.budget} bytes`); });
[g1, g2].forEach((d, i) => ok(`G${i + 1}: no tab, no trailing space, one trailing newline`, !/\t| \n/.test(d.text) && /[^\n]\n$/.test(d.text)));

/* 3. the frames */
const names = F.frames.map(f => `S2 / ${f.name}`);
ok('frame count', F.frames.length === 33, String(F.frames.length));
ok('frame names are unique and of the form "S2 / <id> <title>"', new Set(names).size === names.length && names.every(n => /^S2 \/ [A-Z]\d+ \S/.test(n)));
ok('no chart is drawn in this round', F.frames.every(f => !/svg class="(line|wk|cbars|arc)"/.test(f.html)));

/* 3b. what can be checked of the markup without rendering it */
const read = f => fs.readFileSync(path.join(__dirname, f), 'utf8');
const balanced = html => { const st = []; for (const m of html.matchAll(/<(\/?)([a-z0-9]+)[^>]*>/g)) { if (!m[1]) st.push(m[2]); else if (st.pop() !== m[2]) return false; } return st.length === 0; };
ok('every frame\'s markup is balanced', F.frames.every(f => balanced(f.html)), F.frames.filter(f => !balanced(f.html)).map(f => f.id).join());
const noop = read('../system/noop.js'), icons = new Set([...noop.slice(noop.indexOf('const ICONS={'), noop.indexOf('const ic=')).matchAll(/^\s*'?([a-z-]+)'?:'<symbol/gm)].map(m => m[1]));
const usedIcons = new Set(F.frames.flatMap(f => [...f.html.matchAll(/data-ic="([^"]+)"/g)].map(m => m[1])));
ok('every icon exists in design/system/noop.js', icons.size > 40 && [...usedIcons].every(i => icons.has(i)), [...usedIcons].filter(i => !icons.has(i)).join() || [...usedIcons].join(' '));
const css = read('../system/noop.css') + read('../round6-scorecard/scorecard.css') + read('packet.css');
const usedClasses = new Set(F.frames.flatMap(f => [...f.html.matchAll(/class="([^"]+)"/g)].flatMap(m => m[1].split(/\s+/))).concat(F.frames.flatMap(f => (f.cls || '').split(/\s+/))).filter(Boolean));
const noRule = [...usedClasses].filter(c => !new RegExp(`\\.${c}(?![\\w-])`).test(css));
ok('every class has a rule in noop.css, round 6\'s scorecard.css or packet.css', noRule.join() === 'motion', `without a rule: ${noRule.join(', ') || 'none'} ("motion" is noop.js's entrance hook)`);
const vars = new Set(F.frames.flatMap(f => [...f.html.matchAll(/var\((--[\w-]+)\)/g)].map(m => m[1])));
ok('every colour is an existing token', [...vars].every(v => css.includes(`${v}:`)), [...vars].join(' '));
ok('packet.css introduces no colour value of its own beyond neutral translucency', !/#[0-9a-f]{3,8}\b/i.test(read('packet.css').replace(/\/\*[\s\S]*?\*\//g, '')));

/* 4. every string of §11 is the specification's, word for word */
const s11 = between('## 11. User-facing strings', '## 12. Test plan');
Object.entries(F.SPEC).forEach(([k, v]) => { if (!s11.includes(`"${v}"`)) ok(`§11 string "${k}"`, false, v); });
ok('every presenter string is in §11 word for word', Object.values(F.SPEC).every(v => s11.includes(`"${v}"`)), `${Object.keys(F.SPEC).length} strings`);
const undrawn = Object.keys(F.SPEC).filter(k => !F.USED.has(k));
ok('every §11 string is drawn in a frame, except the accessibility label', undrawn.join() === 'toolbarLabel', `not drawn: ${undrawn.join(', ') || 'none'}`);

/* 5. every text node of every frame is accounted for */
const unesc = s => s.replace(/&lt;/g, '<').replace(/&gt;/g, '>').replace(/&quot;/g, '"').replace(/&amp;/g, '&');
const packetLines = new Set(); Object.values(F.PREVIEWS).forEach(t => t.split('\n').forEach(l => packetLines.add(l.replace(/^ {2}/, ''))));
let stray = 0;
F.frames.forEach(f => f.html.replace(/<[^>]*>/g, '\u0001').split('\u0001').map(t => unesc(t).trim()).filter(Boolean).forEach(t => {
  if (t === '›' || F.SAID.has(t) || packetLines.has(t)) return; stray++; console.log(`      ${f.id}: unaccounted text "${t}"`); }));
ok('every text node is a §11 string, a proposal, context, or a packet line', stray === 0);
ok('each sheet preview is its document, line for line', ['B2', 'B9', 'B11', 'B14', 'B15', 'B16', 'O1', 'O2', 'O3', 'R1', 'D1'].every(id => F.PREVIEWS[id] + '\n' === gold)
  && F.PREVIEWS.B8 + '\n' === gold && F.PREVIEWS.R2 + '\n' === g2.text && F.PREVIEWS.B7 + '\n' === none.text && F.PREVIEWS.B6 + '\n' === act);
const said = [...F.SAID];
ok('copied confirmation is the §10.2 sentence', said.includes('Copied to this iPhone only. It leaves the clipboard at 07:52.'));
ok('tone: no exclamation, warning, streak or instruction to the owner', !said.some(s => /!|\bwarning\b|\bstreak|\bmust\b|\bshould\b|\bdanger|\bhealthy\b|\bunhealthy\b|\bdiagnos/i.test(s)));

console.log(`\n${F.frames.length} frames`); names.forEach(n => console.log(`  ${n}`));
console.log(`\nproposed strings: ${Object.values(F.PROPOSED).map(s => `"${s}"`).join(', ')}`);
console.log(failed ? `\n${failed} check(s) FAILED` : '\nall checks passed (nothing was rendered or viewed)');
process.exit(failed ? 1 : 0);
