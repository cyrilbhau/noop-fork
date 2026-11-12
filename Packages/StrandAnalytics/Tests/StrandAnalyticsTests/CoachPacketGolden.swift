import Foundation

// API ASSUMED BY THESE TESTS
//
// This file calls no product API. It holds the golden packet texts as Swift string literals
// (stage-2 specification §7.9 and §13.3; the test target has no resources) and pure string helpers
// that cut a golden into its blank-line-separated blocks. The API the goldens are compared against
// is listed at the top of `CoachPacketTests.swift`.

/// Golden packet texts for `docs/personal/superapp/specs/stage-2.md`.
///
/// Every value belongs to the synthetic Fixture Person of stage 1 §13 and stage 2 §13. Nothing here was
/// produced by an implementation: `g1` is §7.9 copied byte for byte, and `g2` was written by hand from
/// the templates of §7 for the "no data at all" input of §13.3.
enum CoachPacketGolden {

    /// Golden G1: the full fixture with every section on (§7.9). 6,221 UTF-8 bytes with its final
    /// newline, as the specification states.
    static let g1 = """
NOOP-COACH-PACKET v1
generated: 2031-03-16T07:42:10+01:00
range: 2031-03-03..2031-03-16 (14 days; the last day is today and is partial)
sections: scorecard, weigh-ins, recovery-sleep, trends, activity
switched-off: none
not-recorded-by-app: intake, events
units: kg, cm, hours (h), ms, bpm, steps, kcal, km; dates are YYYY-MM-DD in the phone's time zone
missing: "—" means NOT MEASURED, never zero

== SCORECARD ==
phase: "Fixture cut" (cut), started 2031-01-06, target 94.0 kg, band 0.40 to 1.20 %/week
judged-week: 2031-03-03
verdict: reduceCarbs; reason ruleFired; rule slowLoss; calorie-change -250 kcal; overridden none; could-not-check none
rule liftsHoldingWaistShrinking: notFired, 0 of 1 weeks
rule liftsDropping: notFired, 0 of 3 weeks
rule slowLoss: fired, 5 of 3 weeks
signal waist: notMet (notShrinking); now 97.0 cm; reference 97.0 cm in week 2031-02-17; change +0.0 cm
signal lifts: met (holding); 2 exercises in common: 0 dropped, 0 climbed, 2 held; days 2031-02-26..2031-03-04
signal protein: unknown (noProteinData); 0 of 5 days at or above floor; 0 days logged; floor 100 g
signal rate-band: notMet (belowBand); 0.10 %/week; band 0.40 to 1.20 %/week
rate: losing 0.10 kg/week (0.10 %/week of 97.3 kg); fitted over 5 weigh-ins, weeks 2031-02-03..2031-03-03
projection: 2031-10-08 (estimate), 31.0 weeks, 3.1 kg remaining

== WEIGH-INS ==
current weight: 97.1 kg (lab-book, 2031-03-05)
current waist: 97.0 cm (lab-book, 2031-03-05)
weekly, weeks start Monday, the latest reading of a week represents it, last 8 of 10 weeks:
  2031-01-20: weight 98.4 kg (2031-01-22), waist 99.0 cm (2031-01-22), change -0.8 kg
  2031-01-27: weight 97.6 kg (2031-01-29), waist 98.5 cm (2031-01-29), change -0.8 kg
  2031-02-03: weight 97.5 kg (2031-02-05), waist 98.0 cm (2031-02-05), change -0.1 kg
  2031-02-10: weight 97.4 kg (2031-02-12), waist 97.5 cm (2031-02-12), change -0.1 kg
  2031-02-17: weight 97.3 kg (2031-02-19), waist 97.0 cm (2031-02-19), change -0.1 kg
  2031-02-24: weight 97.2 kg (2031-02-26), waist 97.0 cm (2031-02-26), change -0.1 kg
  2031-03-03: weight 97.1 kg (2031-03-05), waist 97.0 cm (2031-03-05), change -0.1 kg
  2031-03-10: weight —, waist —, change —

== RECOVERY AND SLEEP ==
per day, oldest first: recovery (0-100), strain (0-21 scale), sleep (h), deep/REM/light (h), eff (%), HRV (ms), RHR (bpm)
  2031-03-03: recovery 62, strain 9.9, sleep 7.4h, deep 1.3h, REM 1.7h, light 4.4h, eff 91%, HRV 58ms, RHR 54bpm
  2031-03-04: recovery 71, strain 8.0, sleep 7.7h, deep 1.4h, REM 1.8h, light 4.5h, eff 93%, HRV 63ms, RHR 52bpm
  2031-03-05: recovery 55, strain 13.0, sleep 6.7h, deep 1.1h, REM 1.5h, light 4.1h, eff 88%, HRV 52ms, RHR 56bpm
  2031-03-06: recovery 48, strain 6.3, sleep 6.3h, deep 1.0h, REM 1.4h, light 3.9h, eff 86%, HRV 47ms, RHR 58bpm
  2031-03-07: recovery —, strain —, sleep —, deep —, REM —, light —, eff —, HRV —, RHR —
  2031-03-08: recovery 66, strain 9.2, sleep 7.5h, deep 1.4h, REM 1.8h, light 4.4h, eff 92%, HRV 60ms, RHR 53bpm
  2031-03-09: recovery 74, strain 5.2, sleep 8.0h, deep 1.5h, REM 1.9h, light 4.6h, eff 94%, HRV 66ms, RHR 51bpm
  2031-03-10: recovery 60, strain 10.5, sleep 7.2h, deep 1.2h, REM 1.6h, light 4.3h, eff 90%, HRV 57ms, RHR 54bpm
  2031-03-11: recovery 58, strain 8.6, sleep 7.0h, deep —, REM —, light —, eff —, HRV 55ms, RHR 55bpm [sleep staged from heart rate only]
  2031-03-12: recovery 64, strain 12.2, sleep 7.3h, deep 1.3h, REM 1.6h, light 4.4h, eff 91%, HRV 59ms, RHR 54bpm
  2031-03-13: recovery —, strain 7.3, sleep —, deep —, REM —, light —, eff —, HRV —, RHR —
  2031-03-14: recovery 69, strain 9.7, sleep 7.6h, deep 1.4h, REM 1.7h, light 4.5h, eff 92%, HRV 62ms, RHR 52bpm
  2031-03-15: recovery 72, strain 6.9, sleep 7.8h, deep 1.4h, REM 1.8h, light 4.5h, eff 93%, HRV 64ms, RHR 52bpm
  2031-03-16: recovery 67, strain 1.3, sleep 7.5h, deep 1.4h, REM 1.7h, light 4.5h, eff 92%, HRV 61ms, RHR 53bpm
averages over 13 of 14 days with data: recovery: 64, strain: 8.3, sleep: 7.3h, HRV: 59 ms, RHR: 54 bpm

== TRENDS ==
baseline is the app's personal baseline behind the recovery score; typical is baseline plus or minus one sigma
HRV: baseline 57 ms (typical 51 to 64, trusted, 21 nights); range mean 59 ms over 12 nights (+2 vs baseline); last 7 days mean 60 ms over 6 nights (+3 vs baseline); outside typical: 1 below, 2 above
RHR: baseline 54 bpm (typical 52 to 56, trusted, 21 nights); range mean 54 bpm over 12 nights (+0 vs baseline); last 7 days mean 53 bpm over 6 nights (-1 vs baseline); outside typical: 1 below, 1 above

== ACTIVITY ==
steps per day; "strap-estimate" is an estimate from strap motion, not a count:
  2031-03-03: 9120 apple-health
  2031-03-04: 11240 apple-health
  2031-03-05: 8460 apple-health
  2031-03-06: ~7300 strap-estimate
  2031-03-07: —
  2031-03-08: 12080 apple-health
  2031-03-09: 6540 apple-health
  2031-03-10: 9870 apple-health
  2031-03-11: 10310 apple-health
  2031-03-12: 8890 apple-health
  2031-03-13: ~5200 strap-estimate
  2031-03-14: 9640 apple-health
  2031-03-15: 13020 apple-health
  2031-03-16: 1480 apple-health (today so far)
steps average: 9306 over 12 of 13 full days (apple-health 10, strap-estimate 2)
workouts in range, oldest first, summaries only:
  2031-03-03 18:10 strength, 62 min, avg HR 108 bpm, 380 kcal [lift-log]
  2031-03-05 07:05 cycling, 45 min, avg HR 132 bpm, 410 kcal, 18.40 km [apple-health]
  2031-03-08 09:30 hiking, 95 min, avg HR —, — kcal [manual]
  2031-03-10 06:50 walking, 40 min, avg HR 96 bpm, 170 kcal, 3.60 km [detected]
  2031-03-12 18:05 rowing, 30 min, avg HR 128 bpm, 300 kcal [whoop]

== NOTES ==
measured: weight and waist as entered, heart rate, HRV and resting heart rate from the strap, steps marked apple-health or strap.
estimated by the app: recovery and strain scores (not WHOOP's scores), sleep duration and stages, steps marked strap-estimate, calories, the projection date.
the app cannot know: food intake, lifting loads beyond imported sessions, anything on a day the strap was not worn, how the owner feels.
the verdict is the owner's own rule applied to the owner's own numbers; the app changed nothing and makes no medical claim.
end of NOOP-COACH-PACKET v1
""" + "\n"

    /// Golden G2: the same clock and range with no data at all (§13.3).
    static let g2 = """
NOOP-COACH-PACKET v1
generated: 2031-03-16T07:42:10+01:00
range: 2031-03-03..2031-03-16 (14 days; the last day is today and is partial)
sections: scorecard, weigh-ins, recovery-sleep, trends, activity
switched-off: none
not-recorded-by-app: intake, events
units: kg, cm, hours (h), ms, bpm, steps, kcal, km; dates are YYYY-MM-DD in the phone's time zone
missing: "—" means NOT MEASURED, never zero

== SCORECARD ==
phase: none active
judged-week: none
verdict: insufficientData; reason noActivePhase; rule none; calorie-change none; overridden none; could-not-check none
rule liftsHoldingWaistShrinking: unknown (noActivePhase), 0 of 1 weeks
rule liftsDropping: unknown (noActivePhase), 0 of 3 weeks
rule slowLoss: unknown (noActivePhase), 0 of 3 weeks
signal waist: unknown (noReadings)
signal lifts: unknown (noReadings)
signal protein: unknown (noReadings); 0 of 5 days at or above floor; 0 days logged; floor 100 g
signal rate-band: unknown (noActivePhase)
rate: not available (noReadings)
projection: none (noActivePhase)

== WEIGH-INS ==
current weight: —
current waist: —
weekly: no weigh-ins yet

== RECOVERY AND SLEEP ==
per day, oldest first: recovery (0-100), strain (0-21 scale), sleep (h), deep/REM/light (h), eff (%), HRV (ms), RHR (bpm)
  2031-03-03: recovery —, strain —, sleep —, deep —, REM —, light —, eff —, HRV —, RHR —
  2031-03-04: recovery —, strain —, sleep —, deep —, REM —, light —, eff —, HRV —, RHR —
  2031-03-05: recovery —, strain —, sleep —, deep —, REM —, light —, eff —, HRV —, RHR —
  2031-03-06: recovery —, strain —, sleep —, deep —, REM —, light —, eff —, HRV —, RHR —
  2031-03-07: recovery —, strain —, sleep —, deep —, REM —, light —, eff —, HRV —, RHR —
  2031-03-08: recovery —, strain —, sleep —, deep —, REM —, light —, eff —, HRV —, RHR —
  2031-03-09: recovery —, strain —, sleep —, deep —, REM —, light —, eff —, HRV —, RHR —
  2031-03-10: recovery —, strain —, sleep —, deep —, REM —, light —, eff —, HRV —, RHR —
  2031-03-11: recovery —, strain —, sleep —, deep —, REM —, light —, eff —, HRV —, RHR —
  2031-03-12: recovery —, strain —, sleep —, deep —, REM —, light —, eff —, HRV —, RHR —
  2031-03-13: recovery —, strain —, sleep —, deep —, REM —, light —, eff —, HRV —, RHR —
  2031-03-14: recovery —, strain —, sleep —, deep —, REM —, light —, eff —, HRV —, RHR —
  2031-03-15: recovery —, strain —, sleep —, deep —, REM —, light —, eff —, HRV —, RHR —
  2031-03-16: recovery —, strain —, sleep —, deep —, REM —, light —, eff —, HRV —, RHR —
averages: no data in range

== TRENDS ==
baseline is the app's personal baseline behind the recovery score; typical is baseline plus or minus one sigma
HRV: baseline not available; range mean — over 0 nights
RHR: baseline not available; range mean — over 0 nights

== ACTIVITY ==
steps per day; "strap-estimate" is an estimate from strap motion, not a count:
  2031-03-03: —
  2031-03-04: —
  2031-03-05: —
  2031-03-06: —
  2031-03-07: —
  2031-03-08: —
  2031-03-09: —
  2031-03-10: —
  2031-03-11: —
  2031-03-12: —
  2031-03-13: —
  2031-03-14: —
  2031-03-15: —
  2031-03-16: —
steps average: — (no step data in range)
workouts: none recorded in range

== NOTES ==
measured: weight and waist as entered, heart rate, HRV and resting heart rate from the strap, steps marked apple-health or strap.
estimated by the app: recovery and strain scores (not WHOOP's scores), sleep duration and stages, steps marked strap-estimate, calories, the projection date.
the app cannot know: food intake, lifting loads beyond imported sessions, anything on a day the strap was not worn, how the owner feels.
the verdict is the owner's own rule applied to the owner's own numbers; the app changed nothing and makes no medical claim.
end of NOOP-COACH-PACKET v1
""" + "\n"

    /// The blank-line-separated blocks of a packet text, without the final newline. For G1 these are
    /// the header, the five sections in fixed order, and the notes.
    static func blocks(_ text: String) -> [String] {
        var body = text
        if body.hasSuffix("\n") { body.removeLast() }
        return body.components(separatedBy: "\n\n")
    }

    /// The fixed section order of §7 with each raw section id and its heading. Section `n` of this
    /// list is block `n + 1` of G1.
    static let sectionOrder: [(id: String, heading: String)] = [
        ("scorecard", "== SCORECARD =="),
        ("weigh-ins", "== WEIGH-INS =="),
        ("recovery-sleep", "== RECOVERY AND SLEEP =="),
        ("trends", "== TRENDS =="),
        ("activity", "== ACTIVITY =="),
    ]

    /// G1 with the sections named in `off` (raw ids) removed: their blocks are gone, the header's
    /// `sections:` and `switched-off:` lines say so, and every other line is G1's, unchanged.
    static func g1(withSectionsOff off: Set<String>) -> String {
        let all = blocks(g1)
        var header = all[0].components(separatedBy: "\n")
        let on = sectionOrder.map(\.id).filter { !off.contains($0) }
        let gone = sectionOrder.map(\.id).filter { off.contains($0) }
        header[3] = "sections: " + (on.isEmpty ? "none" : on.joined(separator: ", "))
        header[4] = "switched-off: " + (gone.isEmpty ? "none" : gone.joined(separator: ", "))
        var kept = [header.joined(separator: "\n")]
        for (index, section) in sectionOrder.enumerated() where !off.contains(section.id) {
            kept.append(all[index + 1])
        }
        kept.append(all[6])
        return kept.joined(separator: "\n\n") + "\n"
    }
}
