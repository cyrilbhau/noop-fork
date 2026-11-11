/* Round S3 strings. Every word a frame shows goes through t(), d() or a(), so check.js can prove where each
   came from:
     SPEC      docs/personal/superapp/specs/stage-3.md §11, verbatim (check.js compares them with the file)
     PROPOSED  not in §11: written for this round and listed in the README for the owner
     EXISTING  already in the app, or approved in the stage 1 round (design/round6-scorecard)
     SYSTEM    drawn by iOS, not by NOOP
   d() registers a value that came from the model (a number, a time, a date, a fixture name).
   a() registers an annotation: a label on a states sheet that is not part of the app. */
const IntakeStrings = (() => {
  const SPEC = {
    'card.title': 'Protein', 'card.subtitle': 'Today against your floor',
    'p.toFloor': '%lld g to your floor', 'p.met': 'Floor met', 'p.over': '+%lld g over your floor', 'p.noFloor': 'No floor set',
    'p.nothing': 'Nothing logged today', 'p.dayTotal': 'Day total', 'p.notMeasured': 'Not measured',
    'e.title': 'Calories eaten',
    'e.soFar': '%lld kcal so far', 'e.toLow': '%lld kcal to the bottom of your range', 'e.inRange': 'In your range of %lld to %lld kcal',
    'e.above': '%lld kcal above your range', 'e.belowRange': 'Below your range of %lld to %lld kcal', 'e.belowFloor': 'Below your floor of %lld kcal',
    'e.noRange': 'No range set', 'e.notMeasured': 'Not measured',
    'f.read': 'Read %@', 'f.lastRead': 'Last read %@', 'f.entered': 'Entered %@', 'f.imported': 'imported', 'f.readAgain': 'Read again',
    's.health': 'Apple Health', 's.here': 'Entered here', 's.csv': 'CSV import', 's.several': 'Several sources', 's.from': 'From %@',
    's.two': 'Two apps wrote today: %@ and %@. Both are counted.', 's.chooseOne': 'Choose one',
    'r.could': 'Could not read Apple Health', 'r.failedAt': 'Apple Health could not be read at %@. Showing the last figures.',
    'r.empty': 'Apple Health returned no food entries. If you log in %@, check that it is allowed to write to Health.',
    'c.editIn': 'Edit this in %@. NOOP reads it again when you return.', 'c.editEntry': 'Edit entry', 'c.deleteEntry': 'Delete entry',
    'c.restored': 'Restored total', 'c.replace': 'Replace',
    'q.add': 'Add food', 'q.protein': 'Protein', 'q.calories': 'Calories', 'q.label': 'Label (optional)', 'q.invalid': 'Enter a number from 0 to 100000',
    'q.addPreset': 'Add a preset', 'q.failed': 'Could not save. Nothing was changed.',
    'setup.choose': 'Choose where intake comes from', 'setup.health': 'Apple Health: read what your food app writes',
    'setup.here': 'Enter here: add protein and calories yourself', 'setup.none': 'None: supplements and the cutoff reminder only',
    'set.intake': 'Intake', 'set.source': 'Source', 'set.floor': 'Protein floor', 'set.range': 'Calorie range', 'set.hard': 'Hard floor',
    'set.apps': 'Apps to count', 'set.sups': 'Supplements', 'set.addSup': 'Add a supplement', 'set.cutoff': 'Cutoff time', 'set.reminder': 'Cutoff reminder',
    'set.silent': 'Silent on days when it falls within 30 minutes of your wind-down reminder.', 'set.attention': 'Your targets need attention',
    'sup.title': 'Supplements', 'sup.notTaken': 'Marked not taken in Journal', 'sup.coach': 'Supplements listed here are left out of the Coach.',
    'floor.whole': 'Enter whole grams',
    'chart.more': 'More days will appear here',
    'n.title': 'Food cutoff', 'n.body': 'Your cutoff time is now.',
    'w.protein': 'Protein', 'w.toGo': '%lld g to go', 'w.met': 'Floor met', 'w.over': '+%lld g over', 'w.asOf': 'as of %@', 'w.lastRead': 'Last read %@',
    'w.nothing': 'Nothing logged today', 'w.noFloor': 'No floor set', 'w.setup': 'Set up in NOOP', 'w.refresh': 'Open NOOP to refresh',
    'perm': 'NOOP reads your steps, workout summaries and, if you turn on Intake, the protein and energy your food app logs, from Apple Health on-device. Nothing leaves your device.',
  };
  // [text, why it is needed]. Each is a proposal for the owner.
  const PROPOSED = {
    'x.setFloor': ['Set your protein floor', '§10.2 names this row; §11 has no entry for it'],
    'x.srcNone': ['None', '§10.5 names the three source choices; §11 lists only "Apple Health"'],
    'x.srcHere': ['Enter here', '§10.5 names the three source choices; §11 lists only "Apple Health"'],
    'x.switch': ['Protein and intake', 'the feature switch needs a label; the card title "Intake" is directly above it'],
    'x.sentence': ['Shows protein against your floor and calories against your range. Off until you turn it on.', '§10.5 asks for one sentence beside the switch and gives none'],
    'x.noSource': ['With no source, the card and the widget have nothing to show.', '§10.5 asks for this caption and gives no wording'],
    'x.hkUnavailable': ['Apple Health is not available on this device.', '§10.5: the row reverts "and says why"; replace with the bridge screen\'s existing wording at implementation'],
    'x.hkEntitlement': ['This build cannot read Apple Health.', '§10.5: the row reverts "and says why"; replace with the bridge screen\'s existing wording at implementation'],
    'x.lowAboveHigh': ['The low end is above the high end. Nothing was saved.', '§10.5 marks the field; a marked field with no reason is hard to fix'],
    'x.hardAboveLow': ['The hard floor is above the low end. Nothing was saved.', '§10.5 marks the field; a marked field with no reason is hard to fix'],
    'x.floorMax': ['Enter %@ g or less.', 'a stored floor above stage 1\'s maximum opens marked; follows round 6\'s "Enter 250 kg or less."'],
    'x.ofG': ['of %lld g', 'the ring\'s "grams of floor" (§10.8 medium widget, §10.2 numbers)'],
    'x.g': ['%@ g', 'an amount with its unit'], 'x.kcal': ['%@ kcal', 'an amount with its unit'],
    'x.gUnit': ['g', 'unit beside a figure'], 'x.kcalUnit': ['kcal', 'unit beside a figure'],
    'x.last28': ['Last 28 days', 'title of the history chart (§10.2 describes it and gives no title)'],
    'x.atOrAbove': ['At or above your floor', 'legend for the point style that marks a day at or above the floor'],
    'x.belowFloor': ['Below your floor', 'legend for the other point style'],
    'x.entries': ['Entries', 'title of the Path B entry list'],
    'x.day': ['Day', 'label of the quick-add day picker'],
    'x.presets': ['Presets', 'label above the preset chips'],
    'x.reminderNote': ['One notification a day at your cutoff time. It never contains an amount, a floor or a supplement name.', 'caption under the reminder switch; follows round 6\'s reminder caption'],
    'x.reminderOff': ['The reminder is off unless you turn it on. The cutoff time still closes the day for the calories line.', 'caption with the reminder off; states §7.5\'s rule'],
    'x.looks': ['What it looks like', 'approved in round 6 for the weigh-in reminder; reused as the heading above the preview'],
  };
  // [text, where it already exists]
  const EXISTING = {
    'a.today': ['Today', 'Today tab'], 'a.yourCards': ['Your cards', 'Today'], 'a.edit': ['Edit', 'Today'], 'a.stress': ['Stress', 'Today tile'], 'a.fitness': ['Fitness age', 'Today tile'],
    'a.settings': ['Settings', 'Settings'], 'a.cancel': ['Cancel', 'sheets'], 'a.save': ['Save', 'sheets'], 'a.shown': ['Shown', 'Your cards editor'], 'a.more': ['More cards', 'Your cards editor'],
    'a.coupled': ['Coupled view', 'Your cards editor'], 'a.coach': ['Coach', 'Your cards editor'], 'a.hydration': ['Hydration', 'Your cards editor'],
    'a.vitality': ['Vitality', 'Your cards editor'], 'a.vo2': ['VO₂ max', 'Your cards editor'], 'a.dataSources': ['Data Sources', 'Strand/Resources/Localizable.xcstrings'],
    'a.asOf': ['as of %@', 'Today tile caption'],
    'a.notifOff': ['Notifications are off for NOOP', 'stage 1 §10.6'], 'a.notifBody': ['The reminder cannot be delivered until they are allowed.', 'round 6 frame F3'],
    'a.openSettings': ['Open Settings', 'round 6 frame F3'],
  };
  const SYSTEM = {
    'sys.hkTitle': 'Health Access', 'sys.hkRead': 'Allow “NOOP” to Read:', 'sys.hkEnergy': 'Dietary Energy', 'sys.hkProtein': 'Protein',
    'sys.hkAllow': 'Allow', 'sys.hkDeny': 'Don’t Allow', 'sys.now': 'now', 'sys.ago': '%@m ago', 'sys.noop': 'NOOP',
  };
  const TABLES = [['spec', SPEC], ['proposed', PROPOSED], ['existing', EXISTING], ['system', SYSTEM]];
  const REG = new Set(), used = { spec: new Set(), proposed: new Set(), existing: new Set(), system: new Set(), data: new Set(), note: new Set() };
  const esc = s => String(s).replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;');
  const reg = (kind, text) => { REG.add(text); used[kind].add(text); return esc(text); };
  function t(key, ...args) {
    for (const [kind, table] of TABLES) if (key in table) {
      const raw = Array.isArray(table[key]) ? table[key][0] : table[key];
      let i = 0; const text = raw.replace(/%lld|%@/g, () => String(args[i++]));
      if (i !== args.length || (raw.match(/%lld|%@/g) || []).length !== args.length) throw new Error(`wrong argument count for ${key}`);
      used[kind].add(raw);
      REG.add(text); return esc(text);
    }
    throw new Error(`no string for key ${key}`);
  }
  const d = text => reg('data', String(text));
  const a = text => reg('note', String(text));
  const dot = (...parts) => parts.filter(p => p != null && p !== '').join(' · ');
  const api = { SPEC, PROPOSED, EXISTING, SYSTEM, REG, used, t, d, a, dot, esc };
  if (typeof module !== 'undefined' && module.exports) module.exports = api;
  return api;
})();
