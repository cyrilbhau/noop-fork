/* Round S6 strings. Every word drawn in a frame comes from one of three tables:
   SPEC   — copied character for character from docs/personal/superapp/specs/stage-6.md §11 (check.js verifies each against that file);
   QUOTED — wording stage-6.md §10 gives in quotation marks but §11 does not list (check.js verifies each against the file);
   PROP   — proposals: the specification gives no string. Listed in README.md for the owner.
   Placeholders are %@ and %lld, as in the String Catalog. */
const S6_SPEC = {
  niggleLog: 'Niggle log', timeline: 'Timeline', recoveryContext: 'Recovery context',
  secProf: 'Your rule for seeing a professional', secOpen: 'Open', secPaused: 'Paused by your coach', secObs: 'Observations', secResolved: 'Resolved',
  day: 'Day %lld', resolvedAfter: 'Resolved after %lld days', noted: 'noted %@', since: 'since %@', resumed: 'Resumed %@',
  'act.watch': 'Watch', 'act.modify': 'Modify training', 'act.seeProfessional': 'See a professional',
  noneCovers: 'None of your rules covers this', noRules: 'No rules entered yet', rulesAttention: 'Your rules need attention',
  nextRule: 'Day %lld: your rule “%@” applies', nextNone: 'Day %lld: no rule of yours applies', also: 'Also matches: %@', before: 'Logged before: %lld times',
  disclaimer: 'Your rule, applied to what you logged. This is not a diagnosis.',
  profEmpty: 'You have not written a rule for seeing a professional',
  rulesCaption: 'Write it in your own words. The app shows it back to you and does nothing else with it.',
  pvAny: 'Any complaint', pvChars: '%@ complaints', pvThatIs: 'that is %@', pvWith: 'with weakness', pvWithout: 'without weakness',
  pvFrom: 'from day %lld', pvThrough: 'through day %lld', pvLabelled: 'is labelled “%@”',
  tie: 'When two rules with the same action both apply, the higher one in this list is shown.',
  'char.diffuse': 'Spread over an area', 'char.localised': 'One spot', 'char.positional': 'Only in one position or movement', 'char.other': 'Something else',
  'trend.easing': 'Easing', 'trend.unchanged': 'No change', 'trend.worsening': 'Getting worse', 'trend.notRecorded': 'Not recorded',
  'side.left': 'Left', 'side.right': 'Right', 'side.both': 'Both', 'side.notApplicable': 'Not applicable',
  logNiggle: 'Log a niggle', setUpRules: 'Set up your rules', addUpdate: 'Add update', markResolved: 'Mark resolved', reopen: 'Reopen', addRule: 'Add a rule',
  pauseExercise: 'Pause an exercise', markResumed: 'Mark resumed', addCheckpoint: 'Add a checkpoint', discard: 'Discard unreadable data',
  attnLog: 'Your log could not be read. Nothing has been changed.', attnRules: 'Your rules could not be read. Nothing has been changed.',
  attnCheckpoints: 'Your checkpoints could not be read. Nothing has been changed.',
  ignored: '%lld updates are dated outside this complaint and were not used',
  limitLog: 'The log holds up to %lld entries',
  framing: 'Weekly averages of your nightly resting heart rate and HRV, as context for your coach. They are not a score and no score uses them.',
  rhr: 'Resting heart rate', hrv: 'HRV', latest: 'Latest week average', soFar: 'this week so far', firstWeek: 'First week shown', change: 'Change',
  nights: '%lld of 7 nights', typical: 'Your typical range', range: '%@ to %@', calibrating: 'Typical range: still calibrating', needsSecond: 'Needs a second week',
  notMeasured: 'Not measured yet', notMeasuredStrap: 'Not measured yet. These come from nights recorded by your strap.',
  soFarNights: 'This week so far: %lld nights. A weekly average needs %lld.', last12: 'Last 12 weeks', sinceCap: 'Since %@',
  earlier: 'Earlier', today: 'Today', ahead: 'Ahead',
  started: '%@ started %@', starts: '%@ starts %@', target: 'Target %@', waypoint: 'Waypoint %@', targetDateFor: 'Target date for %@', targetDate: 'Target date',
  around: 'around %@', scan: 'Scan', dietBreak: 'Diet break', deload: 'Deload', now: 'now', estimated: 'Estimated %@ at this rate', estimate: 'estimate',
  notDone: 'Not marked done', done: 'Done',
  'cat.scan': 'Scan', 'cat.bloodPanel': 'Blood panel', 'cat.benchmark': 'Benchmark', 'cat.weightWaypoint': 'Weight waypoint', 'cat.targetDate': 'Target date',
  'cat.appointment': 'Appointment', 'cat.other': 'Other',
  wpCaption: 'A waypoint on the way. Your target weight is set in your phase.', wpShort: 'A waypoint has to be short of your target (%@).', editPhase: 'Edit phase',
  phaseFirst: 'Set up your phase first', afterStart: 'Choose a date after the phase starts', hasTargetDate: 'This phase already has a target date',
  fnScans: 'Scans are not shown while the body record is off', fnEvents: 'Breaks and deloads are not shown while events are off',
  fnEstimate: 'No estimate while the scorecard is off', fnWaypoint: 'A waypoint at or past your target weight is not shown', nothingYet: 'Nothing on your timeline yet',
};
const S6_QUOTED = {            // in quotation marks in §10, absent from §11
  anyWeakness: 'Any weakness', setUpPhase: 'Set up your phase', notMeasuredLower: 'not measured',
};
const S6_PROP = {
  // system and stage 1 words already in the app
  cancel: 'Cancel', save: 'Save', edit: 'Edit', del: 'Delete', saving: 'Saving…', couldNotSave: 'Could not save.',
  // niggle log
  firstUse: 'A dated record of a complaint: where, what kind, and how it changes. Labels come only from rules you write.',
  resumedDisc: 'Resumed', before1: 'Logged before: %lld time', ignored1: '%lld update is dated outside this complaint and was not used',
  resolvedAfter1: 'Resolved after %lld day', notUsed: 'not used', onset: 'Started', secUpdates: 'Updates', secRule: 'Your rule',
  next: 'Next',
  delEntryT: 'Delete this entry?', delEntryD: 'Paused exercises linked to it stay in your list, without the link.',
  // niggle sheet
  kind: 'Kind', complaint: 'Complaint', observation: 'Observation', location: 'Location', side: 'Side', character: 'Character', changing: 'How it is changing',
  startedOn: 'Started', notedOn: 'Noted', note: 'Note', date: 'Date', resolvedOn: 'Resolved on', editNiggle: 'Edit niggle', optional: 'Optional',
  locEmpty: 'Enter a location.', locLong: 'A location can be up to 60 characters.', noFuture: 'Future dates cannot be picked.',
  onsetToToday: 'From %@ to today.', editOnsetNote: 'An update dated before the new start is kept and not used.',
  // rules sheet
  yourRules: 'Your rules', rule: 'Rule', label: 'Label', action: 'Action', whichChars: 'Which complaints', whichTrends: 'Which changes', weakness: 'Weakness',
  either: 'Either', withW: 'With', withoutW: 'Without', fromDay: 'From day', throughDay: 'Through day', noEnd: 'No end', any: 'Any', reads: 'Reads as',
  labelEmpty: 'Enter a label.', fromLow: 'From day starts at 1.', throughLow: 'Through day cannot be before from day.',
  delRuleT: 'Delete this rule?', delRuleD: 'Complaints are labelled again without it.', limitRules: 'The list holds up to %lld rules', or: 'or',
  // paused exercise sheet
  exercise: 'Exercise', reason: 'Reason', until: 'Until', pausedOn: 'Paused on', linkedNiggle: 'Linked niggle', none: 'None', resumedOn: 'Resumed on',
  editPause: 'Edit pause', exEmpty: 'Enter an exercise.', reasonEmpty: 'Enter a reason.', delPauseT: 'Delete this pause?', delPauseD: 'The niggle it is linked to is not changed.',
  // recovery context
  weekOf: 'week of %@', weekOfCap: 'Week of %@', bpm: 'bpm', ms: 'ms',
  // timeline
  openCheckpoint: 'Open checkpoint', attnPhases: 'Your phases could not be read. Target dates are shown without a phase.',
  openPhase: 'Open phase and rules',
  // checkpoint sheet
  title: 'Title', category: 'Category', approximate: 'Approximate date', weight: 'Weight', phase: 'Phase', editCheckpoint: 'Edit checkpoint',
  titleEmpty: 'Enter a title.', titleLong: 'A title can be up to 60 characters.', weightMissing: 'Enter a weight.', weightRange: 'Enter 30 to 250 kg.',
  openThat: 'Open that checkpoint', delCpT: 'Delete this checkpoint?', delCpD: 'Nothing else on the timeline changes.',
  limitCheckpoints: 'The timeline holds up to %lld checkpoints',
};
const S6_ALL = { ...S6_PROP, ...S6_QUOTED, ...S6_SPEC };
const s6Used = new Set();
/** t('day', 20) -> "Day 20". Placeholders are filled in order. Throws on an unknown key so no string can be typed around the tables. */
function t(key, ...args) {
  if (!(key in S6_ALL)) throw new Error('unknown string key: ' + key);
  s6Used.add(key); let i = 0;
  return S6_ALL[key].replace(/%@|%lld/g, () => String(args[i++]));
}
if (typeof module !== 'undefined') module.exports = { S6_SPEC, S6_QUOTED, S6_PROP, S6_ALL, s6Used, t };
