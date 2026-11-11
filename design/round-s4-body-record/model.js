/* Round S4 design model of the stage 4 specification (docs/personal/superapp/specs/stage-4.md): the field
   table (§7.7), the unit table (§7.2), displayString / quantize / compare (§6.3, §7.3), derive (§7.4),
   mismatches (§7.5), what a scan is (§7.6) and the §13 fixture. It exists so that every number drawn in a
   frame is computed, not typed. It is a mockup aid: it is NOT the implementation and has no parity twin.
   EVERY VALUE IS SYNTHETIC. "Fixture Person" does not exist; this is the one Fixture Person of stage 1 §13.
   Wrapped in one global (S4) because noop.js shares the page's script scope. Pure; also loadable in Node. */
var S4 = (function () {
  /* ---------- days (day keys are "yyyy-MM-dd"; a week is named by its Monday) ---------- */
  const dayNum = s => { const [y, m, d] = s.split('-').map(Number); return Math.round(Date.UTC(y, m - 1, d) / 864e5); };
  const dayKey = n => new Date(n * 864e5).toISOString().slice(0, 10);
  const addDays = (s, k) => dayKey(dayNum(s) + k);
  const weekStart = s => { const n = dayNum(s); return dayKey(n - (new Date(n * 864e5).getUTCDay() + 6) % 7); };
  const noonUtc = day => dayNum(day) * 86400 + 12 * 3600;      // §13: scans at 12:00 UTC of their day
  const sevenUtc = day => dayNum(day) * 86400 + 7 * 3600;      // stage 1 §13: weigh-ins at 07:00 UTC

  /* ---------- §6.3 displayString and quantize ---------- */
  function displayString(x, decimals) {
    if (!Number.isFinite(x) || Math.abs(x) >= 1e15) return '—';
    const d = Math.max(0, Math.min(6, decimals));
    // decimals == 0: half away from zero. Otherwise "%.<d>f". (Exact binary ties are §18's open point.)
    let s = d === 0 ? String(Math.sign(x) * Math.round(Math.abs(x))) : x.toFixed(d);
    if (/^-0(\.0*)?$/.test(s)) s = s.slice(1);
    return s;
  }
  const quantize = (x, decimals) => (!Number.isFinite(x) || Math.abs(x) >= 1e15) ? x : Number(displayString(x, decimals));

  /* ---------- §7.3 compare. A reading is { value, decimals } in the display unit, or null. ---------- */
  function compare(earlier, later) {
    const ok = r => r != null && Number.isFinite(r.value);
    const e = ok(earlier), l = ok(later);
    if (!e && !l) return { kind: 'neither' };
    if (!l) return { kind: 'onlyEarlier', value: quantize(earlier.value, earlier.decimals), decimals: earlier.decimals };
    if (!e) return { kind: 'onlyLater', value: quantize(later.value, later.decimals), decimals: later.decimals };
    const d = Math.max(earlier.decimals, later.decimals);
    const a = quantize(earlier.value, d), b = quantize(later.value, d), delta = quantize(b - a, d);
    return { kind: 'both', earlier: a, later: b, delta, decimals: d, percent: a > 0 ? quantize(delta / a * 100, 1) : null,
      direction: delta > 0 ? 'up' : delta < 0 ? 'down' : 'same' };
  }

  /* ---------- §7.4 derive. c: { armsLean, armLeftLean, armRightLean, legsLean, legLeftLean, legRightLean } ---------- */
  const usable = v => v != null && Number.isFinite(v) && v > 0;
  function pairTotal(total, left, right) {
    if (usable(total)) return { value: total, source: 'printedTotal' };
    if (total == null && usable(left) && usable(right)) return { value: left + right, source: 'sumOfSides' };
    if ((total != null && !usable(total)) || (total == null && ((left != null && !usable(left)) || (right != null && !usable(right))))) return { gap: 'invalidComponent' };
    return { gap: 'missingComponent' };
  }
  function sideDifference(left, right) {
    if ((left != null && !usable(left)) || (right != null && !usable(right))) return { gap: 'invalidComponent' };
    if (left == null || right == null) return { gap: 'missingComponent' };
    return { value: quantize((left - right) / Math.max(left, right) * 100, 1) };
  }
  function derive(c) {
    const arms = pairTotal(c.armsLean, c.armLeftLean, c.armRightLean), legs = pairTotal(c.legsLean, c.legLeftLean, c.legRightLean);
    let ratio;
    if (arms.gap === 'invalidComponent' || legs.gap === 'invalidComponent') ratio = { gap: 'invalidComponent' };
    else if (arms.gap || legs.gap) ratio = { gap: 'missingComponent' };
    else { const r = arms.value / legs.value * 100; ratio = Number.isFinite(r) ? { value: quantize(r, 1) } : { gap: 'invalidComponent' }; }
    return { armToLegLeanPercent: ratio, armsSource: arms.source || null, legsSource: legs.source || null,
      armSideDifferencePercent: sideDifference(c.armLeftLean, c.armRightLean), legSideDifferencePercent: sideDifference(c.legLeftLean, c.legRightLean) };
  }

  /* ---------- §7.5 mismatches. Masses in kilograms; null: not entered. ---------- */
  const CHECKS = ['totalIsFatLeanBone', 'fatFreeIsLeanBone', 'bodyFatPercentIsFatShare', 'armsIsLeftPlusRight', 'legsIsLeftPlusRight', 'ratioIsAndroidOverGynoid'];
  function mismatches(i) {
    const all = (...v) => v.every(usable), out = [];
    if (all(i.totalMass, i.fatMass, i.leanMass, i.boneMass) && Math.abs(i.totalMass - (i.fatMass + i.leanMass + i.boneMass)) > 0.25) out.push(CHECKS[0]);
    if (all(i.fatFreeMass, i.leanMass, i.boneMass) && Math.abs(i.fatFreeMass - (i.leanMass + i.boneMass)) > 0.25) out.push(CHECKS[1]);
    if (all(i.bodyFatPercent, i.fatMass, i.totalMass) && Math.abs(i.bodyFatPercent - i.fatMass / i.totalMass * 100) > 0.5
      && (!usable(i.leanMass) || Math.abs(i.bodyFatPercent - i.fatMass / (i.fatMass + i.leanMass) * 100) > 0.5)) out.push(CHECKS[2]);
    if (all(i.armsLean, i.armLeftLean, i.armRightLean) && Math.abs(i.armsLean - (i.armLeftLean + i.armRightLean)) > 0.25) out.push(CHECKS[3]);
    if (all(i.legsLean, i.legLeftLean, i.legRightLean) && Math.abs(i.legsLean - (i.legLeftLean + i.legRightLean)) > 0.25) out.push(CHECKS[4]);
    if (all(i.androidGynoidRatio, i.androidFatPercent, i.gynoidFatPercent) && Math.abs(i.androidGynoidRatio - i.androidFatPercent / i.gynoidFatPercent) > 0.02) out.push(CHECKS[5]);
    return out;
  }
  // Which section a mismatch line sits under (§10.2 H6: "one line under the affected section").
  const CHECK_SECTION = { totalIsFatLeanBone: 'Whole body', fatFreeIsLeanBone: 'Whole body', bodyFatPercentIsFatShare: 'Whole body',
    armsIsLeftPlusRight: 'Lean mass by region', legsIsLeftPlusRight: 'Lean mass by region', ratioIsAndroidOverGynoid: 'Fat distribution' };

  /* ---------- §7.2 conversions to the stored unit ---------- */
  const LB = 2.20462, IN = 2.54;
  const conv = { identity: v => v, multiply: f => v => v * f, divide: d => v => v / d, affine: (s, d) => v => (v - s) / d };
  const KG = [['kg', conv.identity, 'identity'], ['lb', conv.divide(LB), 'divide'], ['g', conv.divide(1000), 'divide']];
  const MG38 = [['mmol/L', conv.identity, 'identity'], ['mg/dL', conv.multiply(1 / 38.67), 'multiply']];
  /* Extended tier, for the keys the frames use. [label, toStored, kind]; the stored unit first. */
  const UNITS = {
    weight: KG.slice(0, 2), waist: [['cm', conv.identity, 'identity'], ['in', conv.multiply(IN), 'multiply']],
    total_cholesterol: MG38, ldl: MG38, hdl: MG38,
    triglycerides: [['mmol/L', conv.identity, 'identity'], ['mg/dL', conv.multiply(1 / 88.57), 'multiply']],
    fasting_glucose: [['mmol/L', conv.identity, 'identity'], ['mg/dL', conv.multiply(1 / 18.0), 'multiply']],
    hba1c: [['mmol/mol', conv.identity, 'identity'], ['%', conv.affine(2.152, 0.09148), 'affine']],
    ferritin: [['µg/L', conv.identity, 'identity'], ['ng/mL', conv.identity, 'identity']],
    vitamin_b12: [['ng/L', conv.identity, 'identity'], ['pg/mL', conv.identity, 'identity'], ['pmol/L', conv.multiply(1.355), 'multiply']],
    tsh: [['mIU/L', conv.identity, 'identity'], ['µIU/mL', conv.identity, 'identity']],
    scan_visceral_fat_mass: [['g', conv.identity, 'identity'], ['kg', conv.multiply(1000), 'multiply'], ['lb', conv.multiply(1000.0 / LB), 'multiply']],
    bench_dead_hang_s: [['s', conv.identity, 'identity'], ['min', conv.multiply(60), 'multiply']],
    bench_grip_kg: KG.slice(0, 2),
  };
  // The legacy tier (flag off): exactly today's switcher, five markers with one extra option each.
  const LEGACY_KEYS = ['total_cholesterol', 'ldl', 'hdl', 'triglycerides', 'fasting_glucose'];
  const options = (key, tier = 'extended') => { const o = UNITS[key] || null;
    return tier === 'legacy' && !LEGACY_KEYS.includes(key) ? (o ? [o[0]] : []) : (o || []); };
  function toStored(value, key, label) { const o = options(key).find(x => x[0] === label); if (!o || !Number.isFinite(value)) return null;
    const r = o[1](value); return Number.isFinite(r) ? r : null; }
  const optionKind = (key, label) => (options(key).find(x => x[0] === label) || [])[2] || null;

  /* ---------- §7.7 fields, sections, ranges; decimals and stored units from §5.2 ---------- */
  const mass = (id, label, key, lo, hi, dec) => ({ id, label, key, units: ['kg', 'lb', 'g'], stored: 'kg', lo, hi, dec, pct: true });
  const SECTIONS = [
    { name: 'Whole body', fields: [
      { id: 'totalMass', label: 'Total mass', key: 'weight', units: ['kg', 'lb'], stored: 'kg', lo: 30, hi: 250, dec: 1, pct: true },
      mass('fatMass', 'Fat mass', 'scan_fat_mass', 1, 200, 1), mass('leanMass', 'Lean mass', 'scan_lean_mass', 10, 150, 1),
      mass('boneMass', 'Bone mineral content', 'scan_bone_mass', 0.5, 6, 2), mass('fatFreeMass', 'Fat-free mass', 'scan_fat_free_mass', 10, 160, 1),
      { id: 'bodyFatPercent', label: 'Body fat', key: 'body_fat', units: ['%'], stored: '%', lo: 1, hi: 75, dec: 1, pct: false, points: true } ] },
    { name: 'Fat distribution', fields: [
      { id: 'visceralFatMass', label: 'Visceral fat mass', key: 'scan_visceral_fat_mass', units: ['g', 'kg', 'lb'], stored: 'g', lo: 0, hi: 10000, dec: 0, pct: true },
      { id: 'visceralFatArea', label: 'Visceral fat area', key: 'scan_visceral_fat_area', units: ['cm²'], stored: 'cm²', lo: 0, hi: 1000, dec: 0, pct: true },
      { id: 'androidFatPercent', label: 'Android fat', key: 'scan_android_fat_pct', units: ['%'], stored: '%', lo: 1, hi: 80, dec: 1, pct: false, points: true },
      { id: 'gynoidFatPercent', label: 'Gynoid fat', key: 'scan_gynoid_fat_pct', units: ['%'], stored: '%', lo: 1, hi: 80, dec: 1, pct: false, points: true },
      { id: 'androidGynoidRatio', label: 'Android to gynoid ratio', key: 'scan_android_gynoid_ratio', units: ['ratio'], stored: 'ratio', lo: 0.1, hi: 5, dec: 2, pct: true } ] },
    { name: 'Lean mass by region', fields: [
      mass('armsLean', 'Arms, total', 'scan_arms_lean_mass', 1, 30, 2), mass('armLeftLean', 'Left arm', 'scan_arm_left_lean_mass', 0.5, 15, 2),
      mass('armRightLean', 'Right arm', 'scan_arm_right_lean_mass', 0.5, 15, 2), mass('legsLean', 'Legs, total', 'scan_legs_lean_mass', 5, 60, 2),
      mass('legLeftLean', 'Left leg', 'scan_leg_left_lean_mass', 2, 30, 2), mass('legRightLean', 'Right leg', 'scan_leg_right_lean_mass', 2, 30, 2),
      mass('trunkLean', 'Trunk', 'scan_trunk_lean_mass', 5, 80, 2) ] },
    { name: 'Bone density', fields: [
      { id: 'bmd', label: 'Bone mineral density', key: 'scan_bmd', units: ['g/cm²'], stored: 'g/cm²', lo: 0.3, hi: 2.5, dec: 3, pct: true },
      { id: 'tScore', label: 'T-score', key: 'scan_bmd_t_score', units: ['SD'], stored: 'SD', lo: -8, hi: 8, dec: 1, pct: false, signed: true },
      { id: 'zScore', label: 'Z-score', key: 'scan_bmd_z_score', units: ['SD'], stored: 'SD', lo: -8, hi: 8, dec: 1, pct: false, signed: true } ] },
    { name: 'Energy', fields: [
      { id: 'rmr', label: 'Resting metabolic rate', key: 'scan_rmr_lab_estimate', units: ['kcal/day'], stored: 'kcal/day', lo: 500, hi: 5000, dec: 0, pct: true } ] },
  ];
  const FIELDS = SECTIONS.flatMap(s => s.fields.map(f => ({ ...f, section: s.name })));
  const field = id => FIELDS.find(f => f.id === id);
  // A scan field's typed value in the stored unit. Mass fields share the kg / lb / g options of §7.2.
  function fieldToStored(f, value, unit) {
    if (unit === f.stored) return value;
    const table = f.key === 'scan_visceral_fat_mass' ? UNITS.scan_visceral_fat_mass : f.stored === 'kg' ? KG : [];
    const o = table.find(x => x[0] === unit); return o ? o[1](value) : null;
  }
  const inRange = (f, stored) => stored != null && Number.isFinite(stored) && stored >= f.lo && stored <= f.hi;

  /* §6.2 parseEntry: one optional "-", digits, optionally one separator and digits. */
  function parseEntry(text, sep = '.') { const t = String(text).trim(), s = sep === ',' ? ',' : '.';
    const m = new RegExp(`^-?[0-9]+(\\${s}[0-9]+)?$`).test(t); if (!m) return null; const v = Number(t.replace(s, '.')); return Number.isFinite(v) ? v : null; }

  /* ---------- stage 1 §13: the one Fixture Person. Weigh-ins on Wednesdays from 2031-01-08, 07:00 UTC.
     Copied from design/round6-scorecard/model.js; check.js asserts the two are equal. ---------- */
  const FX_WEIGHT = [100.0, 99.2, 98.4, 97.6, 97.5, 97.4, 97.3, 97.2, 97.1, null, 96.0, 95.2, 95.1, 95.0, 94.9, 94.8, 94.7, 94.6, 94.5, 95.5, 94.0, 93.5];
  const FX_WAIST = [100.0, 99.5, 99.0, 98.5, 98.0, 97.5, 97.0, 97.0, 97.0, null, 96.5, 96.0, 95.5, 95.0, 94.5, 94.5, 94.5, 94.5, 94.5, 94.5, 94.0, 93.5];
  const weighDay = k => addDays('2031-01-08', 7 * (k - 1));
  const WEIGH_INS = FX_WEIGHT.map((v, i) => v == null ? null : { day: weighDay(i + 1), takenAt: sevenUtc(weighDay(i + 1)), weightKg: v, waistCm: FX_WAIST[i], source: 'manual', week: i + 1 }).filter(Boolean);
  const weighInOn = day => WEIGH_INS.find(w => w.day === day) || null;

  /* ---------- §13.1 three scans. A missing key is a field that was not entered. ---------- */
  const SCAN_SOURCE = 'body-scan', CSV_SOURCE = 'lab-csv';
  const scan = (name, day, values, note) => ({ name, day, takenAt: noonUtc(day), source: SCAN_SOURCE, values, note: note || null });
  const SCAN_A = scan('A', '2031-01-08', { totalMass: 100.0, fatMass: 30.0, leanMass: 67.0, boneMass: 3.00, fatFreeMass: 70.0, bodyFatPercent: 30.0,
    visceralFatMass: 1000, androidFatPercent: 36.0, gynoidFatPercent: 30.0, androidGynoidRatio: 1.20,
    armsLean: 10.00, armLeftLean: 4.90, armRightLean: 5.10, legsLean: 20.00, legLeftLean: 10.00, legRightLean: 10.00, trunkLean: 32.00,
    bmd: 1.200, tScore: 0.5, zScore: 0.4, rmr: 1900 }, 'Fixture note');
  const SCAN_B = scan('B', '2031-04-09', { totalMass: 95.0, fatMass: 26.0, leanMass: 66.0, boneMass: 3.00, fatFreeMass: 69.0, bodyFatPercent: 27.4,
    visceralFatMass: 800, visceralFatArea: 80, androidFatPercent: 30.0, gynoidFatPercent: 26.0, androidGynoidRatio: 1.15,
    armsLean: 10.40, armLeftLean: 5.20, armRightLean: 5.20, legsLean: 19.60, legLeftLean: 9.80, legRightLean: 9.80, trunkLean: 31.50, rmr: 1850 });
  const SCAN_C = scan('C', '2031-05-28', { totalMass: 94.0, fatMass: 25.0, leanMass: 66.0, boneMass: 3.00, armLeftLean: 5.30, armRightLean: 5.30, legsLean: 19.50 });
  const V3_FAT_FREE_TYPED = 96.0;                               // §13.4 V3: scan B with fat-free mass typed 96.0
  const scanId = s => `${s.source}\u001F${s.takenAt}`;

  /* §7.6: order by takenAt ascending, then source. The order of entry plays no part. */
  const ordered = scans => scans.slice().sort((a, b) => (a.takenAt - b.takenAt) || (a.source < b.source ? -1 : a.source > b.source ? 1 : 0));

  /* §7.6 reading a scan. `unreadable` and `conflicting` are lists of field ids: such a field is counted and
     named, is never shown as a number and takes no part in a comparison or a derived figure. */
  function read(s) {
    const unreadable = s.unreadable || [], conflicting = s.conflicting || [], values = {};
    FIELDS.forEach(f => { const v = s.values[f.id]; if (v != null && !unreadable.includes(f.id) && !conflicting.includes(f.id)) values[f.id] = v; });
    const derived = derive(values);
    return { id: scanId(s), name: s.name, day: s.day, takenAt: s.takenAt, source: s.source, imported: s.source !== SCAN_SOURCE, values, note: s.note,
      unreadable, conflicting, editable: s.source === SCAN_SOURCE && !conflicting.length, derived };
  }
  const reading = (rs, id) => rs && rs.values[id] != null ? { value: rs.values[id], decimals: field(id).dec } : null;
  /* The rows of a comparison, in field order, plus the derived row. A field in neither scan gives no row (J4). */
  function comparison(earlier, later) {
    const rows = FIELDS.map(f => ({ field: f, change: compare(reading(earlier, f.id), reading(later, f.id)) })).filter(r => r.change.kind !== 'neither');
    const dv = rs => rs.derived.armToLegLeanPercent.value != null ? { value: rs.derived.armToLegLeanPercent.value, decimals: 1 } : null;
    return { rows, armToLeg: compare(dv(earlier), dv(later)) };
  }

  /* H8 (§8.4), as a design model of stage 1's ruling R44: true when a total mass is typed and a manual weigh-in
     dated on or before `today` falls in the Monday week of the draft's day. The app asks the resolver instead. */
  const weighInOutranksDraft = (draft, weighIns, today) => draft.totalTyped && weighIns.some(w => w.source === 'manual' && w.day <= today && weekStart(w.day) === weekStart(draft.day));

  /* ---------- §5.3 benchmarks and §13.5 readings ---------- */
  const BENCHMARKS = [
    { key: 'bench_pushup_reps', name: 'Push-ups, most in one set', unit: 'reps', dec: 0 }, { key: 'bench_incline_pushup_reps', name: 'Incline push-ups, most in one set', unit: 'reps', dec: 0 },
    { key: 'bench_knee_pushup_reps', name: 'Knee push-ups, most in one set', unit: 'reps', dec: 0 }, { key: 'bench_pullup_reps', name: 'Pull-ups, most in one set', unit: 'reps', dec: 0 },
    { key: 'bench_dead_hang_s', name: 'Dead hang, longest hold', unit: 's', dec: 0 }, { key: 'bench_plank_s', name: 'Plank, longest hold', unit: 's', dec: 0 },
    { key: 'bench_wall_sit_s', name: 'Wall sit, longest hold', unit: 's', dec: 0 }, { key: 'bench_grip_kg', name: 'Grip strength', unit: 'kg', dec: 1 },
  ];
  const BENCH_RANGE = { reps: [0, 1000], s: [0, 86400], kg: [1, 150] };
  const CUSTOM_UNITS = ['reps', 's', 'kg'];
  const BENCH_READINGS = {
    bench_dead_hang_s: [{ day: '2031-01-06', value: 20 }, { day: '2031-02-17', value: 30 }, { day: '2031-03-31', value: 45, note: 'Fixture bar' }],
    bench_pushup_reps: [{ day: '2031-01-06', value: 10 }, { day: '2031-02-17', value: 14 }],
    custom_bench_fixture_carry: [{ day: '2031-01-06', value: 60 }],
  };
  const CUSTOM_BENCH = { key: 'custom_bench_fixture_carry', name: 'Fixture carry', unit: 's', dec: 0, custom: true };
  const benchDef = key => BENCHMARKS.find(b => b.key === key) || (key === CUSTOM_BENCH.key ? CUSTOM_BENCH : null);
  /* One benchmark as the screen needs it: readings newest first, each with its change against the one before. */
  function benchmark(key, keep) {
    const def = benchDef(key), asc = (BENCH_READINGS[key] || []).slice().sort((a, b) => a.day < b.day ? -1 : 1).slice(0, keep == null ? undefined : keep);
    const rd = r => ({ value: r.value, decimals: def.dec });
    const rows = asc.map((r, i) => ({ ...r, change: i ? compare(rd(asc[i - 1]), rd(r)) : null })).reverse();
    const latest = asc[asc.length - 1] || null;
    return { def, rows, latest, sincePrevious: asc.length > 1 ? compare(rd(asc[asc.length - 2]), rd(latest)) : null,
      sinceFirst: asc.length > 1 ? compare(rd(asc[0]), rd(latest)) : null };
  }

  /* ---------- §13.5 blood results: typed -> stored -> shown, and the "entered as" annotation (§9.3) ---------- */
  const MARKERS = {
    hba1c: { name: 'HbA1c', stored: 'mmol/mol', dec: 0 }, ldl: { name: 'LDL cholesterol', stored: 'mmol/L', dec: 2 }, hdl: { name: 'HDL cholesterol', stored: 'mmol/L', dec: 2 },
    total_cholesterol: { name: 'Total cholesterol', stored: 'mmol/L', dec: 2 }, triglycerides: { name: 'Triglycerides', stored: 'mmol/L', dec: 2 },
    fasting_glucose: { name: 'Fasting glucose', stored: 'mmol/L', dec: 1 }, ferritin: { name: 'Ferritin', stored: 'µg/L', dec: 0 }, tsh: { name: 'TSH', stored: 'mIU/L', dec: 2 },
    vitamin_b12: { name: 'Vitamin B12', stored: 'ng/L', dec: 0 },
  };
  const BLOOD_TYPED = [['hba1c', '5.5', '%'], ['ldl', '100', 'mg/dL'], ['hdl', '50', 'mg/dL'], ['total_cholesterol', '200', 'mg/dL'], ['triglycerides', '150', 'mg/dL'],
    ['fasting_glucose', '90', 'mg/dL'], ['ferritin', '80', 'ng/mL'], ['tsh', '2.00', 'mIU/L']];
  const BLOOD_DAY = '2031-04-09';
  function blood(key) {
    const [, typed, unit] = BLOOD_TYPED.find(b => b[0] === key), m = MARKERS[key], stored = toStored(parseEntry(typed), key, unit);
    return { key, name: m.name, typed, typedUnit: unit, storedUnit: m.stored, stored, shown: displayString(stored, m.dec), kind: optionKind(key, unit),
      annotation: unit === m.stored ? null : `${typed} ${unit}`, day: BLOOD_DAY };
  }

  return { dayNum, dayKey, addDays, weekStart, noonUtc, displayString, quantize, compare, derive, mismatches, CHECKS, CHECK_SECTION, usable,
    LB, IN, UNITS, options, toStored, optionKind, LEGACY_KEYS, SECTIONS, FIELDS, field, fieldToStored, inRange, parseEntry,
    FX_WEIGHT, FX_WAIST, weighDay, WEIGH_INS, weighInOn, SCAN_SOURCE, CSV_SOURCE, SCAN_A, SCAN_B, SCAN_C, V3_FAT_FREE_TYPED, scanId, ordered, read, reading, comparison, weighInOutranksDraft,
    BENCHMARKS, BENCH_RANGE, CUSTOM_UNITS, BENCH_READINGS, CUSTOM_BENCH, benchDef, benchmark, MARKERS, BLOOD_TYPED, BLOOD_DAY, blood };
})();
if (typeof module !== 'undefined') module.exports = S4;
