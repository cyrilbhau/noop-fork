# Coach packet version 2: the Claude-side text

This is the one revision of stage 2 §16 that packet v2 makes (stage 2 §7.12, G-10; §14.5 V2-4). It
replaces both version 1 blocks. The owner pastes each block once: the first into the training
document, in place of the version 1 "Reading the packet" section, and the second into the coaching
skill, in place of the version 1 paragraph. Neither block contains anything personal.

The end-to-end check of §12.8 moves with it: after pasting, the owner pastes one real version 2
packet into Claude and confirms that each section, the intake rows and the events rows are read
correctly.

## 1. For the training document: "Reading the packet"

```
## Reading the packet

The app can produce a text block that starts with the line "NOOP-COACH-PACKET v2" and ends with
"end of NOOP-COACH-PACKET v2". When I paste one, read it by these rules.

1. Check the first and last lines. If the last line is missing, the paste was cut short: say so and
   ask for it again. If the version is higher than 2, read the sections you recognise and tell me
   which lines you did not recognise. Do not guess at them. A block marked v1 is an older format:
   it has no INTAKE or EVENTS section, and its "not-recorded-by-app" line names them.
2. The header says what is in the block. "sections" lists what is included. "switched-off" lists
   what I chose to leave out. "not-recorded-by-app" lists what the app does not hold at all; in
   version 2 it reads "none". A section that is not in the block tells you nothing: it does not
   mean zero, and it does not mean nothing happened.
3. A section that says "not available: ... is switched off in the app" means that feature is off
   on my phone. It is not a zero and not a gap in my logging.
4. A long dash means NOT MEASURED (for intake: not logged). Never read it as zero, and never average
   across it as if it were a value.
5. Dates are YYYY-MM-DD. Units are metric; protein is in grams (g). Rows run oldest first. The last
   day of the range is today and is incomplete.
6. SCORECARD is the app applying my own written rules to my own weigh-ins. Words such as
   "holdSteady" or "liftSignalUnknown" are fixed identifiers. A rule marked "unknown" was not
   evaluated: name it and say what would be needed to evaluate it. "could-not-check" lists rules
   that might have changed the verdict. Treat the verdict as the output of my rules and not as your
   own conclusion; if you disagree with it, say why.
7. WEIGH-INS gives one point per week, starting Monday. "change" is against the week before, and a
   negative change means lighter. Expect noise week to week.
8. INTAKE has one row per day: protein in grams and energy in kcal, as I logged them. The token in
   square brackets is where the day's values came from: "apple-health" (a food app through Apple
   Health), "quick-add" (entered in the app), "nutrition-file" (an imported file), or "mixed"
   (protein and energy came from different sources). Sources are never added together. A day of
   dashes was not logged; do not treat it as a fast. A day with only one of the two values logged
   tells you nothing about the other. Today's row is incomplete.
9. RECOVERY AND SLEEP: recovery and strain are the app's own scores, not WHOOP's, and the first line
   of the section names the strain scale. Sleep stages are estimates. A line tagged "sleep staged
   from heart rate only" is a weaker estimate.
10. TRENDS compares the range with the app's own baseline. It gives numbers and no judgement.
11. ACTIVITY names the source of each day's steps. A value with "~" and "strap-estimate" is an
    estimate from strap motion and is not a count. Workouts are summaries. Heart rate and calories
    are the wrong instruments for a lifting session; use the lifting log I paste for loads.
12. EVENTS lists things I entered myself (travel, illness, dietBreak, deload, supplementChange, or a
    custom name in quotes), as whole local days, oldest first. "start..end" is a span, a single
    date is one day, and "start..ongoing" has no end yet. Dates are printed whole even when they
    run outside the range. A line "(N earlier events in range not shown)" means only the latest
    twelve are listed. "events: none listed in range" means nothing is listed; I may keep some
    events private, and the packet neither shows nor counts them, so do not assume nothing
    happened and do not ask what was left out. Use events as context for the numbers, never as
    proof of a cause.
13. NOTES says what is measured, what is estimated, what I logged and what the app cannot know.
    Keep those distinctions in everything you say back to me.
14. Do not ask me to retype a number that is in the packet. Do ask for anything the packet says it
    cannot know when you need it.
```

## 2. For the coaching skill

Replace the version 1 paragraph with this one:

```
When the conversation contains a block beginning "NOOP-COACH-PACKET v", treat it as the source of
truth for the period it covers and read it by the "Reading the packet" section of the training
document. Before anything else, state in one line the range it covers and which sections are
included, switched off, or switched off in the app. Use its numbers exactly as printed. Keep
measured values, estimates, logged intake and unknowns apart; never turn a dash, an unlogged
intake day, "not available" or a missing section into a zero. Read the intake rows with their
source tokens, and read the events as context entered by me, not as causes. Never speculate about
private events the packet does not list. Say plainly when a question cannot be answered from the
packet. If the version is higher than the one the training document describes, say so and continue
with the sections you recognise.
```

## What changed from version 1

- The version on the first and last lines is 2.
- The header names seven sections in this fixed order: scorecard, weigh-ins, intake, recovery-sleep,
  trends, activity, events. `not-recorded-by-app` reads `none`. The units line adds grams.
- New INTAKE section (after WEIGH-INS) and EVENTS section (after ACTIVITY), each on by default and
  each switchable in the packet sheet.
- A feature switched off in the app prints its heading and one `not available` line.
- Private events stay out unless the owner switches on "Include private events in the coach packet"
  in Settings; no count of private events is printed anywhere.
- The notes add a "logged by the owner" line, name workout calories, and say the app cannot know
  food intake that was not logged.
- Niggles, scan markers, benchmarks and other Lab Book markers are still not in the packet.
