// API ASSUMED BY THESE TESTS
//
// None. This file holds recorded text and calls nothing.

// Stage 2 (coach packet), specification §12.2: what the in-app Coach was told BEFORE the
// shared-formatter extraction, for every store state `CoachContextByteIdentityTests.stateNames`
// lists.
//
// HOW THESE WERE MADE. Each literal is the output of the untouched code (`AICoachEngine` at commit
// 2353b02d, the tree after the Lab Book ownership change merged and before the stage 2
// extraction), captured by a throwaway test that ran each state and printed its text. They were
// written into this file by a script and not typed or edited by hand. The throwaway test is not
// in the tree.
//
// `{D-n}` and `{W-n}` stand for a day that moves with the real clock (see the note on day tokens
// at the top of CoachContextByteIdentityTests.swift). Everything else is verbatim.
//
// NEVER EDIT A LITERAL TO MAKE A TEST PASS. A difference here means the Coach is being told
// something else, which stage 2 must not cause.
//
// Synthetic values only: the one Fixture Person.
enum CoachContextRecorded {
    static let texts: [String: String] = [
        "no-days": """
        USER BIOMETRIC SUMMARY:
        No wearable data is available yet. Acknowledge this and give general, encouraging guidance while inviting the user to sync their device so future advice can reference real numbers.
        """,
        "fixture": """
        USER BIOMETRIC SUMMARY (the user's own wearable data):

        Recent days (newest first) — charge(0-100), effort(0-100), rest/sleep(h), deep/REM/light(h), eff(%), HRV(ms), RHR(bpm). A dash means NOT MEASURED, not zero:
          2031-03-16:, charge 67, effort 6.0, rest 7.5h, deep 1.4h, REM 1.7h, light 4.5h, eff 92%, HRV 61ms, RHR 53bpm
          2031-03-15:, charge 72, effort 33.0, rest 7.8h, deep 1.4h, REM 1.8h, light 4.5h, eff 93%, HRV 64ms, RHR 52bpm
          2031-03-14:, charge 69, effort 46.0, rest 7.6h, deep 1.4h, REM 1.7h, light 4.5h, eff 92%, HRV 62ms, RHR 52bpm
          2031-03-13:, charge —, effort 35.0, rest —, deep —, REM —, light —, eff —, HRV —, RHR —
          2031-03-12:, charge 64, effort 58.0, rest 7.3h, deep 1.3h, REM 1.6h, light 4.4h, eff 91%, HRV 59ms, RHR 54bpm
          2031-03-11:, charge 58, effort 41.0, rest 7.0h, deep —, REM —, light —, eff —, HRV 55ms, RHR 55bpm
          2031-03-10:, charge 60, effort 50.0, rest 7.2h, deep 1.2h, REM 1.6h, light 4.3h, eff 90%, HRV 57ms, RHR 54bpm
          2031-03-09:, charge 74, effort 25.0, rest 8.0h, deep 1.5h, REM 1.9h, light 4.6h, eff 94%, HRV 66ms, RHR 51bpm
          2031-03-08:, charge 66, effort 44.0, rest 7.5h, deep 1.4h, REM 1.8h, light 4.4h, eff 92%, HRV 60ms, RHR 53bpm
          2031-03-06:, charge 48, effort 30.0, rest 6.3h, deep 1.0h, REM 1.4h, light 3.9h, eff 86%, HRV 47ms, RHR 58bpm
          2031-03-05:, charge 55, effort 62.0, rest 6.7h, deep 1.1h, REM 1.5h, light 4.1h, eff 88%, HRV 52ms, RHR 56bpm
          2031-03-04:, charge 71, effort 38.0, rest 7.7h, deep 1.4h, REM 1.8h, light 4.5h, eff 93%, HRV 63ms, RHR 52bpm
          2031-03-03:, charge 62, effort 47.0, rest 7.4h, deep 1.3h, REM 1.7h, light 4.4h, eff 91%, HRV 58ms, RHR 54bpm

        30-day averages:
          charge: 64, effort: 39.6, sleep: 7.3h, HRV: 59 ms, RHR: 54 bpm
          SpO2: —%, respiration: —/min, skin-temp deviation: —°C, steps: —/day, active energy: —kcal/day
        """,
        "one-row-every-field-absent": """
        USER BIOMETRIC SUMMARY (the user's own wearable data):

        Recent days (newest first) — charge(0-100), effort(0-100), rest/sleep(h), deep/REM/light(h), eff(%), HRV(ms), RHR(bpm). A dash means NOT MEASURED, not zero:
          2031-03-07:, charge —, effort —, rest —, deep —, REM —, light —, eff —, HRV —, RHR —

        30-day averages:
          charge: —, effort: —, sleep: —h, HRV: — ms, RHR: — bpm
          SpO2: —%, respiration: —/min, skin-temp deviation: —°C, steps: —/day, active energy: —kcal/day
        """,
        "day-line-every-field-absent": """
        2031-03-07:, charge —, effort —, rest —, deep —, REM —, light —, eff —, HRV —, RHR —
        """,
        "day-lines-fixture": """
        2031-03-03:, charge 62, effort 47.0, rest 7.4h, deep 1.3h, REM 1.7h, light 4.4h, eff 91%, HRV 58ms, RHR 54bpm
        2031-03-04:, charge 71, effort 38.0, rest 7.7h, deep 1.4h, REM 1.8h, light 4.5h, eff 93%, HRV 63ms, RHR 52bpm
        2031-03-05:, charge 55, effort 62.0, rest 6.7h, deep 1.1h, REM 1.5h, light 4.1h, eff 88%, HRV 52ms, RHR 56bpm
        2031-03-06:, charge 48, effort 30.0, rest 6.3h, deep 1.0h, REM 1.4h, light 3.9h, eff 86%, HRV 47ms, RHR 58bpm
        2031-03-08:, charge 66, effort 44.0, rest 7.5h, deep 1.4h, REM 1.8h, light 4.4h, eff 92%, HRV 60ms, RHR 53bpm
        2031-03-09:, charge 74, effort 25.0, rest 8.0h, deep 1.5h, REM 1.9h, light 4.6h, eff 94%, HRV 66ms, RHR 51bpm
        2031-03-10:, charge 60, effort 50.0, rest 7.2h, deep 1.2h, REM 1.6h, light 4.3h, eff 90%, HRV 57ms, RHR 54bpm
        2031-03-11:, charge 58, effort 41.0, rest 7.0h, deep —, REM —, light —, eff —, HRV 55ms, RHR 55bpm
        2031-03-12:, charge 64, effort 58.0, rest 7.3h, deep 1.3h, REM 1.6h, light 4.4h, eff 91%, HRV 59ms, RHR 54bpm
        2031-03-13:, charge —, effort 35.0, rest —, deep —, REM —, light —, eff —, HRV —, RHR —
        2031-03-14:, charge 69, effort 46.0, rest 7.6h, deep 1.4h, REM 1.7h, light 4.5h, eff 92%, HRV 62ms, RHR 52bpm
        2031-03-15:, charge 72, effort 33.0, rest 7.8h, deep 1.4h, REM 1.8h, light 4.5h, eff 93%, HRV 64ms, RHR 52bpm
        2031-03-16:, charge 67, effort 6.0, rest 7.5h, deep 1.4h, REM 1.7h, light 4.5h, eff 92%, HRV 61ms, RHR 53bpm
        """,
        "more-than-thirty-rows": """
        USER BIOMETRIC SUMMARY (the user's own wearable data):

        Recent days (newest first) — charge(0-100), effort(0-100), rest/sleep(h), deep/REM/light(h), eff(%), HRV(ms), RHR(bpm). A dash means NOT MEASURED, not zero:
          2031-01-08:, charge 53, effort 42.2, rest 8.1h, deep 1.4h, REM 1.5h, light 4.5h, eff 89%, HRV 69ms, RHR 52bpm
          2031-01-07:, charge 46, effort 29.2, rest 7.8h, deep 1.3h, REM 1.4h, light 4.3h, eff 88%, HRV 58ms, RHR 59bpm
          2031-01-06:, charge 84, effort 16.2, rest 7.6h, deep 1.3h, REM 1.3h, light 4.2h, eff 87%, HRV 47ms, RHR 56bpm
          2031-01-05:, charge 77, effort 3.2, rest 7.3h, deep 1.2h, REM 1.9h, light 4.1h, eff 86%, HRV 61ms, RHR 53bpm
          2031-01-04:, charge 71, effort 90.2, rest 7.0h, deep 1.2h, REM 1.8h, light 4.0h, eff 85%, HRV 50ms, RHR 50bpm
          2031-01-03:, charge —, effort 77.2, rest —, deep 1.1h, REM 1.8h, light 3.9h, eff 94%, HRV 64ms, RHR 57bpm
          2031-01-02:, charge 56, effort 64.2, rest 6.4h, deep 1.1h, REM 1.7h, light 4.6h, eff 93%, HRV 53ms, RHR 54bpm
          2031-01-01:, charge 49, effort 51.2, rest 6.2h, deep 1.0h, REM 1.6h, light 4.5h, eff 92%, HRV 67ms, RHR 51bpm
          2030-12-31:, charge 42, effort 38.2, rest 8.4h, deep 1.6h, REM 1.5h, light 4.4h, eff 91%, HRV 56ms, RHR 58bpm
          2030-12-30:, charge 81, effort 25.2, rest 8.1h, deep 1.6h, REM 1.4h, light 4.2h, eff 90%, HRV 45ms, RHR 55bpm
          2030-12-29:, charge 73, effort 12.2, rest 7.8h, deep 1.5h, REM 1.3h, light 4.1h, eff 89%, HRV 59ms, RHR 52bpm
          2030-12-28:, charge —, effort 99.2, rest —, deep 1.5h, REM 1.9h, light 4.0h, eff 88%, HRV 48ms, RHR 59bpm
          2030-12-27:, charge 59, effort 86.2, rest 7.2h, deep 1.4h, REM 1.8h, light 3.9h, eff 87%, HRV 62ms, RHR 56bpm
          2030-12-26:, charge 52, effort 73.2, rest 7.0h, deep 1.4h, REM 1.8h, light 4.6h, eff 86%, HRV 51ms, RHR 53bpm

        30-day averages:
          charge: 61, effort: 50.4, sleep: 7.3h, HRV: 57 ms, RHR: 55 bpm
          SpO2: 97%, respiration: 14.5/min, skin-temp deviation: 0.0°C, steps: 10672/day, active energy: 576kcal/day
        """,
        "month-boundary": """
        USER BIOMETRIC SUMMARY (the user's own wearable data):

        Recent days (newest first) — charge(0-100), effort(0-100), rest/sleep(h), deep/REM/light(h), eff(%), HRV(ms), RHR(bpm). A dash means NOT MEASURED, not zero:
          2031-03-04:, charge 44, effort 91.2, rest 8.0h, deep 1.4h, REM 1.9h, light 4.7h, eff 92%, HRV 47ms, RHR 51bpm
          2031-03-03:, charge 82, effort 78.2, rest 7.7h, deep 1.3h, REM 1.8h, light 4.5h, eff 91%, HRV 61ms, RHR 58bpm
          2031-03-02:, charge —, effort 65.2, rest —, deep 1.2h, REM 1.8h, light 4.4h, eff 90%, HRV 50ms, RHR 55bpm
          2031-03-01:, charge 68, effort 52.2, rest 7.1h, deep 1.2h, REM 1.7h, light 4.3h, eff 89%, HRV 64ms, RHR 52bpm
          2031-02-28:, charge 61, effort 39.2, rest 6.8h, deep 1.1h, REM 1.6h, light 4.2h, eff 88%, HRV 53ms, RHR 59bpm
          2031-02-27:, charge 54, effort 26.2, rest 6.6h, deep 1.1h, REM 1.5h, light 4.1h, eff 87%, HRV 67ms, RHR 56bpm
          2031-02-26:, charge 47, effort 13.2, rest 6.3h, deep 1.1h, REM 1.4h, light 4.0h, eff 86%, HRV 56ms, RHR 53bpm
          2031-02-25:, charge 41, effort 0.2, rest 6.0h, deep 1.0h, REM 1.3h, light 3.8h, eff 85%, HRV 45ms, RHR 50bpm

        30-day averages:
          charge: 57, effort: 45.8, sleep: 6.9h, HRV: 55 ms, RHR: 54 bpm
          SpO2: 97%, respiration: 14.3/min, skin-temp deviation: 0.0°C, steps: 8411/day, active energy: 427kcal/day
        """,
        "year-boundary": """
        USER BIOMETRIC SUMMARY (the user's own wearable data):

        Recent days (newest first) — charge(0-100), effort(0-100), rest/sleep(h), deep/REM/light(h), eff(%), HRV(ms), RHR(bpm). A dash means NOT MEASURED, not zero:
          2031-01-07:, charge 41, effort 69.2, rest 7.2h, deep 1.6h, REM 1.8h, light 4.5h, eff 88%, HRV 63ms, RHR 59bpm
          2031-01-06:, charge 79, effort 56.2, rest 6.9h, deep 1.6h, REM 1.7h, light 4.4h, eff 87%, HRV 52ms, RHR 56bpm
          2031-01-05:, charge —, effort 43.2, rest —, deep 1.6h, REM 1.6h, light 4.3h, eff 86%, HRV 66ms, RHR 53bpm
          2031-01-04:, charge 66, effort 30.2, rest 6.3h, deep 1.5h, REM 1.5h, light 4.2h, eff 85%, HRV 55ms, RHR 50bpm
          2031-01-03:, charge 58, effort 17.2, rest 6.0h, deep 1.4h, REM 1.4h, light 4.0h, eff 94%, HRV 69ms, RHR 57bpm
          2031-01-02:, charge 51, effort 4.2, rest 8.3h, deep 1.4h, REM 1.3h, light 3.9h, eff 93%, HRV 58ms, RHR 54bpm
          2031-01-01:, charge 44, effort 91.2, rest 8.0h, deep 1.4h, REM 1.9h, light 4.7h, eff 92%, HRV 47ms, RHR 51bpm
          2030-12-31:, charge 82, effort 78.2, rest 7.7h, deep 1.3h, REM 1.8h, light 4.5h, eff 91%, HRV 61ms, RHR 58bpm
          2030-12-30:, charge —, effort 65.2, rest —, deep 1.2h, REM 1.8h, light 4.4h, eff 90%, HRV 50ms, RHR 55bpm
          2030-12-29:, charge 68, effort 52.2, rest 7.1h, deep 1.2h, REM 1.7h, light 4.3h, eff 89%, HRV 64ms, RHR 52bpm
          2030-12-28:, charge 61, effort 39.2, rest 6.8h, deep 1.1h, REM 1.6h, light 4.2h, eff 88%, HRV 53ms, RHR 59bpm
          2030-12-27:, charge 54, effort 26.2, rest 6.6h, deep 1.1h, REM 1.5h, light 4.1h, eff 87%, HRV 67ms, RHR 56bpm
          2030-12-26:, charge 47, effort 13.2, rest 6.3h, deep 1.1h, REM 1.4h, light 4.0h, eff 86%, HRV 56ms, RHR 53bpm
          2030-12-25:, charge 41, effort 0.2, rest 6.0h, deep 1.0h, REM 1.3h, light 3.8h, eff 85%, HRV 45ms, RHR 50bpm

        30-day averages:
          charge: 58, effort: 41.9, sleep: 6.9h, HRV: 58 ms, RHR: 55 bpm
          SpO2: 96%, respiration: 14.5/min, skin-temp deviation: 0.0°C, steps: 8822/day, active energy: 454kcal/day
        """,
        "leap-february": """
        USER BIOMETRIC SUMMARY (the user's own wearable data):

        Recent days (newest first) — charge(0-100), effort(0-100), rest/sleep(h), deep/REM/light(h), eff(%), HRV(ms), RHR(bpm). A dash means NOT MEASURED, not zero:
          2032-03-02:, charge —, effort 65.2, rest —, deep 1.2h, REM 1.8h, light 4.4h, eff 90%, HRV 50ms, RHR 55bpm
          2032-03-01:, charge 68, effort 52.2, rest 7.1h, deep 1.2h, REM 1.7h, light 4.3h, eff 89%, HRV 64ms, RHR 52bpm
          2032-02-29:, charge 61, effort 39.2, rest 6.8h, deep 1.1h, REM 1.6h, light 4.2h, eff 88%, HRV 53ms, RHR 59bpm
          2032-02-28:, charge 54, effort 26.2, rest 6.6h, deep 1.1h, REM 1.5h, light 4.1h, eff 87%, HRV 67ms, RHR 56bpm
          2032-02-27:, charge 47, effort 13.2, rest 6.3h, deep 1.1h, REM 1.4h, light 4.0h, eff 86%, HRV 56ms, RHR 53bpm
          2032-02-26:, charge 41, effort 0.2, rest 6.0h, deep 1.0h, REM 1.3h, light 3.8h, eff 85%, HRV 45ms, RHR 50bpm

        30-day averages:
          charge: 54, effort: 32.8, sleep: 6.6h, HRV: 56 ms, RHR: 54 bpm
          SpO2: 97%, respiration: 14.4/min, skin-temp deviation: -0.1°C, steps: 8206/day, active energy: 414kcal/day
        """,
        "absent-recovery": """
        USER BIOMETRIC SUMMARY (the user's own wearable data):

        Recent days (newest first) — charge(0-100), effort(0-100), rest/sleep(h), deep/REM/light(h), eff(%), HRV(ms), RHR(bpm). A dash means NOT MEASURED, not zero:
          2031-03-16:, charge 62, effort 47.0, rest 7.4h, deep 1.3h, REM 1.7h, light 4.4h, eff 91%, HRV 58ms, RHR 54bpm
          2031-03-15:, charge —, effort 47.0, rest 7.4h, deep 1.3h, REM 1.7h, light 4.4h, eff 91%, HRV 58ms, RHR 54bpm
          2031-03-14:, charge 62, effort 47.0, rest 7.4h, deep 1.3h, REM 1.7h, light 4.4h, eff 91%, HRV 58ms, RHR 54bpm

        30-day averages:
          charge: 62, effort: 47.0, sleep: 7.4h, HRV: 58 ms, RHR: 54 bpm
          SpO2: —%, respiration: —/min, skin-temp deviation: —°C, steps: —/day, active energy: —kcal/day
        """,
        "absent-strain": """
        USER BIOMETRIC SUMMARY (the user's own wearable data):

        Recent days (newest first) — charge(0-100), effort(0-100), rest/sleep(h), deep/REM/light(h), eff(%), HRV(ms), RHR(bpm). A dash means NOT MEASURED, not zero:
          2031-03-16:, charge 62, effort 47.0, rest 7.4h, deep 1.3h, REM 1.7h, light 4.4h, eff 91%, HRV 58ms, RHR 54bpm
          2031-03-15:, charge 62, effort —, rest 7.4h, deep 1.3h, REM 1.7h, light 4.4h, eff 91%, HRV 58ms, RHR 54bpm
          2031-03-14:, charge 62, effort 47.0, rest 7.4h, deep 1.3h, REM 1.7h, light 4.4h, eff 91%, HRV 58ms, RHR 54bpm

        30-day averages:
          charge: 62, effort: 47.0, sleep: 7.4h, HRV: 58 ms, RHR: 54 bpm
          SpO2: —%, respiration: —/min, skin-temp deviation: —°C, steps: —/day, active energy: —kcal/day
        """,
        "absent-sleep": """
        USER BIOMETRIC SUMMARY (the user's own wearable data):

        Recent days (newest first) — charge(0-100), effort(0-100), rest/sleep(h), deep/REM/light(h), eff(%), HRV(ms), RHR(bpm). A dash means NOT MEASURED, not zero:
          2031-03-16:, charge 62, effort 47.0, rest 7.4h, deep 1.3h, REM 1.7h, light 4.4h, eff 91%, HRV 58ms, RHR 54bpm
          2031-03-15:, charge 62, effort 47.0, rest —, deep 1.3h, REM 1.7h, light 4.4h, eff 91%, HRV 58ms, RHR 54bpm
          2031-03-14:, charge 62, effort 47.0, rest 7.4h, deep 1.3h, REM 1.7h, light 4.4h, eff 91%, HRV 58ms, RHR 54bpm

        30-day averages:
          charge: 62, effort: 47.0, sleep: 7.4h, HRV: 58 ms, RHR: 54 bpm
          SpO2: —%, respiration: —/min, skin-temp deviation: —°C, steps: —/day, active energy: —kcal/day
        """,
        "absent-deep": """
        USER BIOMETRIC SUMMARY (the user's own wearable data):

        Recent days (newest first) — charge(0-100), effort(0-100), rest/sleep(h), deep/REM/light(h), eff(%), HRV(ms), RHR(bpm). A dash means NOT MEASURED, not zero:
          2031-03-16:, charge 62, effort 47.0, rest 7.4h, deep 1.3h, REM 1.7h, light 4.4h, eff 91%, HRV 58ms, RHR 54bpm
          2031-03-15:, charge 62, effort 47.0, rest 7.4h, deep —, REM 1.7h, light 4.4h, eff 91%, HRV 58ms, RHR 54bpm
          2031-03-14:, charge 62, effort 47.0, rest 7.4h, deep 1.3h, REM 1.7h, light 4.4h, eff 91%, HRV 58ms, RHR 54bpm

        30-day averages:
          charge: 62, effort: 47.0, sleep: 7.4h, HRV: 58 ms, RHR: 54 bpm
          SpO2: —%, respiration: —/min, skin-temp deviation: —°C, steps: —/day, active energy: —kcal/day
        """,
        "absent-rem": """
        USER BIOMETRIC SUMMARY (the user's own wearable data):

        Recent days (newest first) — charge(0-100), effort(0-100), rest/sleep(h), deep/REM/light(h), eff(%), HRV(ms), RHR(bpm). A dash means NOT MEASURED, not zero:
          2031-03-16:, charge 62, effort 47.0, rest 7.4h, deep 1.3h, REM 1.7h, light 4.4h, eff 91%, HRV 58ms, RHR 54bpm
          2031-03-15:, charge 62, effort 47.0, rest 7.4h, deep 1.3h, REM —, light 4.4h, eff 91%, HRV 58ms, RHR 54bpm
          2031-03-14:, charge 62, effort 47.0, rest 7.4h, deep 1.3h, REM 1.7h, light 4.4h, eff 91%, HRV 58ms, RHR 54bpm

        30-day averages:
          charge: 62, effort: 47.0, sleep: 7.4h, HRV: 58 ms, RHR: 54 bpm
          SpO2: —%, respiration: —/min, skin-temp deviation: —°C, steps: —/day, active energy: —kcal/day
        """,
        "absent-light": """
        USER BIOMETRIC SUMMARY (the user's own wearable data):

        Recent days (newest first) — charge(0-100), effort(0-100), rest/sleep(h), deep/REM/light(h), eff(%), HRV(ms), RHR(bpm). A dash means NOT MEASURED, not zero:
          2031-03-16:, charge 62, effort 47.0, rest 7.4h, deep 1.3h, REM 1.7h, light 4.4h, eff 91%, HRV 58ms, RHR 54bpm
          2031-03-15:, charge 62, effort 47.0, rest 7.4h, deep 1.3h, REM 1.7h, light —, eff 91%, HRV 58ms, RHR 54bpm
          2031-03-14:, charge 62, effort 47.0, rest 7.4h, deep 1.3h, REM 1.7h, light 4.4h, eff 91%, HRV 58ms, RHR 54bpm

        30-day averages:
          charge: 62, effort: 47.0, sleep: 7.4h, HRV: 58 ms, RHR: 54 bpm
          SpO2: —%, respiration: —/min, skin-temp deviation: —°C, steps: —/day, active energy: —kcal/day
        """,
        "absent-efficiency": """
        USER BIOMETRIC SUMMARY (the user's own wearable data):

        Recent days (newest first) — charge(0-100), effort(0-100), rest/sleep(h), deep/REM/light(h), eff(%), HRV(ms), RHR(bpm). A dash means NOT MEASURED, not zero:
          2031-03-16:, charge 62, effort 47.0, rest 7.4h, deep 1.3h, REM 1.7h, light 4.4h, eff 91%, HRV 58ms, RHR 54bpm
          2031-03-15:, charge 62, effort 47.0, rest 7.4h, deep 1.3h, REM 1.7h, light 4.4h, eff —, HRV 58ms, RHR 54bpm
          2031-03-14:, charge 62, effort 47.0, rest 7.4h, deep 1.3h, REM 1.7h, light 4.4h, eff 91%, HRV 58ms, RHR 54bpm

        30-day averages:
          charge: 62, effort: 47.0, sleep: 7.4h, HRV: 58 ms, RHR: 54 bpm
          SpO2: —%, respiration: —/min, skin-temp deviation: —°C, steps: —/day, active energy: —kcal/day
        """,
        "absent-hrv": """
        USER BIOMETRIC SUMMARY (the user's own wearable data):

        Recent days (newest first) — charge(0-100), effort(0-100), rest/sleep(h), deep/REM/light(h), eff(%), HRV(ms), RHR(bpm). A dash means NOT MEASURED, not zero:
          2031-03-16:, charge 62, effort 47.0, rest 7.4h, deep 1.3h, REM 1.7h, light 4.4h, eff 91%, HRV 58ms, RHR 54bpm
          2031-03-15:, charge 62, effort 47.0, rest 7.4h, deep 1.3h, REM 1.7h, light 4.4h, eff 91%, HRV —, RHR 54bpm
          2031-03-14:, charge 62, effort 47.0, rest 7.4h, deep 1.3h, REM 1.7h, light 4.4h, eff 91%, HRV 58ms, RHR 54bpm

        30-day averages:
          charge: 62, effort: 47.0, sleep: 7.4h, HRV: 58 ms, RHR: 54 bpm
          SpO2: —%, respiration: —/min, skin-temp deviation: —°C, steps: —/day, active energy: —kcal/day
        """,
        "absent-restingHr": """
        USER BIOMETRIC SUMMARY (the user's own wearable data):

        Recent days (newest first) — charge(0-100), effort(0-100), rest/sleep(h), deep/REM/light(h), eff(%), HRV(ms), RHR(bpm). A dash means NOT MEASURED, not zero:
          2031-03-16:, charge 62, effort 47.0, rest 7.4h, deep 1.3h, REM 1.7h, light 4.4h, eff 91%, HRV 58ms, RHR 54bpm
          2031-03-15:, charge 62, effort 47.0, rest 7.4h, deep 1.3h, REM 1.7h, light 4.4h, eff 91%, HRV 58ms, RHR —
          2031-03-14:, charge 62, effort 47.0, rest 7.4h, deep 1.3h, REM 1.7h, light 4.4h, eff 91%, HRV 58ms, RHR 54bpm

        30-day averages:
          charge: 62, effort: 47.0, sleep: 7.4h, HRV: 58 ms, RHR: 54 bpm
          SpO2: —%, respiration: —/min, skin-temp deviation: —°C, steps: —/day, active energy: —kcal/day
        """,
        "strain-on-the-stored-scale": """
        USER BIOMETRIC SUMMARY (the user's own wearable data):

        Recent days (newest first) — charge(0-100), effort(0-100), rest/sleep(h), deep/REM/light(h), eff(%), HRV(ms), RHR(bpm). A dash means NOT MEASURED, not zero:
          2031-03-16:, charge 67, effort 6.0, rest 7.5h, deep 1.4h, REM 1.7h, light 4.5h, eff 92%, HRV 61ms, RHR 53bpm
          2031-03-15:, charge 72, effort 33.0, rest 7.8h, deep 1.4h, REM 1.8h, light 4.5h, eff 93%, HRV 64ms, RHR 52bpm
          2031-03-14:, charge 69, effort 46.0, rest 7.6h, deep 1.4h, REM 1.7h, light 4.5h, eff 92%, HRV 62ms, RHR 52bpm
          2031-03-13:, charge —, effort 35.0, rest —, deep —, REM —, light —, eff —, HRV —, RHR —
          2031-03-12:, charge 64, effort 58.0, rest 7.3h, deep 1.3h, REM 1.6h, light 4.4h, eff 91%, HRV 59ms, RHR 54bpm
          2031-03-11:, charge 58, effort 41.0, rest 7.0h, deep —, REM —, light —, eff —, HRV 55ms, RHR 55bpm
          2031-03-10:, charge 60, effort 50.0, rest 7.2h, deep 1.2h, REM 1.6h, light 4.3h, eff 90%, HRV 57ms, RHR 54bpm
          2031-03-09:, charge 74, effort 25.0, rest 8.0h, deep 1.5h, REM 1.9h, light 4.6h, eff 94%, HRV 66ms, RHR 51bpm
          2031-03-08:, charge 66, effort 44.0, rest 7.5h, deep 1.4h, REM 1.8h, light 4.4h, eff 92%, HRV 60ms, RHR 53bpm
          2031-03-06:, charge 48, effort 30.0, rest 6.3h, deep 1.0h, REM 1.4h, light 3.9h, eff 86%, HRV 47ms, RHR 58bpm
          2031-03-05:, charge 55, effort 62.0, rest 6.7h, deep 1.1h, REM 1.5h, light 4.1h, eff 88%, HRV 52ms, RHR 56bpm
          2031-03-04:, charge 71, effort 38.0, rest 7.7h, deep 1.4h, REM 1.8h, light 4.5h, eff 93%, HRV 63ms, RHR 52bpm
          2031-03-03:, charge 62, effort 47.0, rest 7.4h, deep 1.3h, REM 1.7h, light 4.4h, eff 91%, HRV 58ms, RHR 54bpm

        30-day averages:
          charge: 64, effort: 39.6, sleep: 7.3h, HRV: 59 ms, RHR: 54 bpm
          SpO2: —%, respiration: —/min, skin-temp deviation: —°C, steps: —/day, active energy: —kcal/day
        """,
        "efficiency-as-a-percentage": """
        USER BIOMETRIC SUMMARY (the user's own wearable data):

        Recent days (newest first) — charge(0-100), effort(0-100), rest/sleep(h), deep/REM/light(h), eff(%), HRV(ms), RHR(bpm). A dash means NOT MEASURED, not zero:
          2031-03-10:, charge 62, effort 47.0, rest 7.4h, deep 1.3h, REM 1.7h, light 4.4h, eff 0%, HRV 58ms, RHR 54bpm
          2031-03-09:, charge 62, effort 47.0, rest 7.4h, deep 1.3h, REM 1.7h, light 4.4h, eff 100%, HRV 58ms, RHR 54bpm
          2031-03-08:, charge 62, effort 47.0, rest 7.4h, deep 1.3h, REM 1.7h, light 4.4h, eff 100%, HRV 58ms, RHR 54bpm
          2031-03-07:, charge 62, effort 47.0, rest 7.4h, deep 1.3h, REM 1.7h, light 4.4h, eff —, HRV 58ms, RHR 54bpm
          2031-03-06:, charge 62, effort 47.0, rest 7.4h, deep 1.3h, REM 1.7h, light 4.4h, eff —, HRV 58ms, RHR 54bpm
          2031-03-05:, charge 62, effort 47.0, rest 7.4h, deep 1.3h, REM 1.7h, light 4.4h, eff —, HRV 58ms, RHR 54bpm
          2031-03-04:, charge 62, effort 47.0, rest 7.4h, deep 1.3h, REM 1.7h, light 4.4h, eff —, HRV 58ms, RHR 54bpm
          2031-03-03:, charge 62, effort 47.0, rest 7.4h, deep 1.3h, REM 1.7h, light 4.4h, eff —, HRV 58ms, RHR 54bpm
          2031-03-02:, charge 62, effort 47.0, rest 7.4h, deep 1.3h, REM 1.7h, light 4.4h, eff 94%, HRV 58ms, RHR 54bpm
          2031-03-01:, charge 62, effort 47.0, rest 7.4h, deep 1.3h, REM 1.7h, light 4.4h, eff 94%, HRV 58ms, RHR 54bpm

        30-day averages:
          charge: 62, effort: 47.0, sleep: 7.4h, HRV: 58 ms, RHR: 54 bpm
          SpO2: —%, respiration: —/min, skin-temp deviation: —°C, steps: —/day, active energy: —kcal/day
        """,
        "vitals-and-steps": """
        USER BIOMETRIC SUMMARY (the user's own wearable data):

        Recent days (newest first) — charge(0-100), effort(0-100), rest/sleep(h), deep/REM/light(h), eff(%), HRV(ms), RHR(bpm). A dash means NOT MEASURED, not zero:
          2031-03-16:, charge 67, effort 6.0, rest 7.5h, deep 1.4h, REM 1.7h, light 4.5h, eff 92%, HRV 61ms, RHR 53bpm
          2031-03-15:, charge 72, effort 33.0, rest 7.8h, deep 1.4h, REM 1.8h, light 4.5h, eff 93%, HRV 64ms, RHR 52bpm
          2031-03-14:, charge 69, effort 46.0, rest 7.6h, deep 1.4h, REM 1.7h, light 4.5h, eff 92%, HRV 62ms, RHR 52bpm

        30-day averages:
          charge: 69, effort: 28.3, sleep: 7.6h, HRV: 62 ms, RHR: 52 bpm
          SpO2: 97%, respiration: 14.8/min, skin-temp deviation: -0.1°C, steps: 8047/day, active energy: 600kcal/day
        """,
        "fifteen-rows": """
        USER BIOMETRIC SUMMARY (the user's own wearable data):

        Recent days (newest first) — charge(0-100), effort(0-100), rest/sleep(h), deep/REM/light(h), eff(%), HRV(ms), RHR(bpm). A dash means NOT MEASURED, not zero:
          2031-03-16:, charge 48, effort 82.2, rest 7.5h, deep 1.0h, REM 1.8h, light 4.6h, eff 89%, HRV 49ms, RHR 52bpm
          2031-03-15:, charge 41, effort 69.2, rest 7.2h, deep 1.6h, REM 1.8h, light 4.5h, eff 88%, HRV 63ms, RHR 59bpm
          2031-03-14:, charge 79, effort 56.2, rest 6.9h, deep 1.6h, REM 1.7h, light 4.4h, eff 87%, HRV 52ms, RHR 56bpm
          2031-03-13:, charge —, effort 43.2, rest —, deep 1.6h, REM 1.6h, light 4.3h, eff 86%, HRV 66ms, RHR 53bpm
          2031-03-12:, charge 66, effort 30.2, rest 6.3h, deep 1.5h, REM 1.5h, light 4.2h, eff 85%, HRV 55ms, RHR 50bpm
          2031-03-11:, charge 58, effort 17.2, rest 6.0h, deep 1.4h, REM 1.4h, light 4.0h, eff 94%, HRV 69ms, RHR 57bpm
          2031-03-10:, charge 51, effort 4.2, rest 8.3h, deep 1.4h, REM 1.3h, light 3.9h, eff 93%, HRV 58ms, RHR 54bpm
          2031-03-09:, charge 44, effort 91.2, rest 8.0h, deep 1.4h, REM 1.9h, light 4.7h, eff 92%, HRV 47ms, RHR 51bpm
          2031-03-08:, charge 82, effort 78.2, rest 7.7h, deep 1.3h, REM 1.8h, light 4.5h, eff 91%, HRV 61ms, RHR 58bpm
          2031-03-07:, charge —, effort 65.2, rest —, deep 1.2h, REM 1.8h, light 4.4h, eff 90%, HRV 50ms, RHR 55bpm
          2031-03-06:, charge 68, effort 52.2, rest 7.1h, deep 1.2h, REM 1.7h, light 4.3h, eff 89%, HRV 64ms, RHR 52bpm
          2031-03-05:, charge 61, effort 39.2, rest 6.8h, deep 1.1h, REM 1.6h, light 4.2h, eff 88%, HRV 53ms, RHR 59bpm
          2031-03-04:, charge 54, effort 26.2, rest 6.6h, deep 1.1h, REM 1.5h, light 4.1h, eff 87%, HRV 67ms, RHR 56bpm
          2031-03-03:, charge 47, effort 13.2, rest 6.3h, deep 1.1h, REM 1.4h, light 4.0h, eff 86%, HRV 56ms, RHR 53bpm

        30-day averages:
          charge: 57, effort: 44.6, sleep: 7.0h, HRV: 57 ms, RHR: 54 bpm
          SpO2: 96%, respiration: 14.5/min, skin-temp deviation: 0.0°C, steps: 8822/day, active energy: 454kcal/day
        """,
        "thirty-one-rows": """
        USER BIOMETRIC SUMMARY (the user's own wearable data):

        Recent days (newest first) — charge(0-100), effort(0-100), rest/sleep(h), deep/REM/light(h), eff(%), HRV(ms), RHR(bpm). A dash means NOT MEASURED, not zero:
          2031-03-16:, charge 71, effort 90.2, rest 7.0h, deep 1.2h, REM 1.8h, light 4.0h, eff 85%, HRV 50ms, RHR 50bpm
          2031-03-15:, charge —, effort 77.2, rest —, deep 1.1h, REM 1.8h, light 3.9h, eff 94%, HRV 64ms, RHR 57bpm
          2031-03-14:, charge 56, effort 64.2, rest 6.4h, deep 1.1h, REM 1.7h, light 4.6h, eff 93%, HRV 53ms, RHR 54bpm
          2031-03-13:, charge 49, effort 51.2, rest 6.2h, deep 1.0h, REM 1.6h, light 4.5h, eff 92%, HRV 67ms, RHR 51bpm
          2031-03-12:, charge 42, effort 38.2, rest 8.4h, deep 1.6h, REM 1.5h, light 4.4h, eff 91%, HRV 56ms, RHR 58bpm
          2031-03-11:, charge 81, effort 25.2, rest 8.1h, deep 1.6h, REM 1.4h, light 4.2h, eff 90%, HRV 45ms, RHR 55bpm
          2031-03-10:, charge 73, effort 12.2, rest 7.8h, deep 1.5h, REM 1.3h, light 4.1h, eff 89%, HRV 59ms, RHR 52bpm
          2031-03-09:, charge —, effort 99.2, rest —, deep 1.5h, REM 1.9h, light 4.0h, eff 88%, HRV 48ms, RHR 59bpm
          2031-03-08:, charge 59, effort 86.2, rest 7.2h, deep 1.4h, REM 1.8h, light 3.9h, eff 87%, HRV 62ms, RHR 56bpm
          2031-03-07:, charge 52, effort 73.2, rest 7.0h, deep 1.4h, REM 1.8h, light 4.6h, eff 86%, HRV 51ms, RHR 53bpm
          2031-03-06:, charge 46, effort 60.2, rest 6.7h, deep 1.3h, REM 1.7h, light 4.5h, eff 85%, HRV 65ms, RHR 50bpm
          2031-03-05:, charge 83, effort 47.2, rest 6.4h, deep 1.3h, REM 1.6h, light 4.4h, eff 94%, HRV 54ms, RHR 57bpm
          2031-03-04:, charge 76, effort 34.2, rest 6.1h, deep 1.2h, REM 1.5h, light 4.3h, eff 93%, HRV 68ms, RHR 54bpm
          2031-03-03:, charge —, effort 21.2, rest —, deep 1.2h, REM 1.4h, light 4.2h, eff 92%, HRV 57ms, RHR 51bpm

        30-day averages:
          charge: 60, effort: 51.8, sleep: 7.1h, HRV: 57 ms, RHR: 55 bpm
          SpO2: 97%, respiration: 14.5/min, skin-temp deviation: 0.0°C, steps: 10261/day, active energy: 549kcal/day
        """,
        "gaps-in-wear": """
        USER BIOMETRIC SUMMARY (the user's own wearable data):

        Recent days (newest first) — charge(0-100), effort(0-100), rest/sleep(h), deep/REM/light(h), eff(%), HRV(ms), RHR(bpm). A dash means NOT MEASURED, not zero:
          2031-03-01:, charge —, effort 67.2, rest —, deep 1.3h, REM 1.6h, light 4.0h, eff 94%, HRV 69ms, RHR 57bpm
          2031-02-28:, charge 41, effort 54.2, rest 7.4h, deep 1.2h, REM 1.5h, light 3.9h, eff 93%, HRV 58ms, RHR 54bpm
          2031-02-27:, charge 79, effort 41.2, rest 7.2h, deep 1.2h, REM 1.4h, light 4.7h, eff 92%, HRV 47ms, RHR 51bpm
          2031-02-26:, charge 72, effort 28.2, rest 6.9h, deep 1.1h, REM 1.3h, light 4.5h, eff 91%, HRV 61ms, RHR 58bpm
          2031-02-22:, charge 44, effort 76.2, rest 8.2h, deep 1.6h, REM 1.7h, light 4.1h, eff 87%, HRV 67ms, RHR 56bpm
          2031-02-18:, charge 61, effort 24.2, rest 7.1h, deep 1.4h, REM 1.3h, light 4.4h, eff 93%, HRV 48ms, RHR 54bpm
          2031-02-14:, charge 78, effort 72.2, rest 8.5h, deep 1.2h, REM 1.7h, light 4.0h, eff 89%, HRV 54ms, RHR 52bpm
          2031-02-10:, charge 51, effort 20.2, rest 7.3h, deep 1.0h, REM 1.3h, light 4.3h, eff 85%, HRV 60ms, RHR 50bpm
          2031-02-06:, charge 67, effort 68.2, rest 6.2h, deep 1.5h, REM 1.7h, light 3.9h, eff 91%, HRV 66ms, RHR 58bpm
          2031-02-02:, charge 84, effort 16.2, rest 7.6h, deep 1.3h, REM 1.3h, light 4.2h, eff 87%, HRV 47ms, RHR 56bpm
          2031-01-29:, charge 56, effort 64.2, rest 6.4h, deep 1.1h, REM 1.7h, light 4.6h, eff 93%, HRV 53ms, RHR 54bpm
          2031-01-25:, charge 73, effort 12.2, rest 7.8h, deep 1.5h, REM 1.3h, light 4.1h, eff 89%, HRV 59ms, RHR 52bpm
          2031-01-21:, charge 46, effort 60.2, rest 6.7h, deep 1.3h, REM 1.7h, light 4.5h, eff 85%, HRV 65ms, RHR 50bpm
          2031-01-17:, charge 62, effort 8.2, rest 8.0h, deep 1.1h, REM 1.3h, light 4.0h, eff 91%, HRV 46ms, RHR 58bpm

        30-day averages:
          charge: 62, effort: 40.4, sleep: 7.3h, HRV: 57 ms, RHR: 54 bpm
          SpO2: 95%, respiration: 14.5/min, skin-temp deviation: -0.0°C, steps: 12042/day, active energy: 666kcal/day
        """,
        "rounding-ties": """
        USER BIOMETRIC SUMMARY (the user's own wearable data):

        Recent days (newest first) — charge(0-100), effort(0-100), rest/sleep(h), deep/REM/light(h), eff(%), HRV(ms), RHR(bpm). A dash means NOT MEASURED, not zero:
          2031-03-16:, charge 1, effort 0.1, rest 0.1h, deep 0.1h, REM 0.2h, light 0.3h, eff 100%, HRV 1ms, RHR 53bpm
          2031-03-15:, charge 64, effort 5.3, rest 1.8h, deep 2.2h, REM 2.8h, light 3.2h, eff 92%, HRV 59ms, RHR 55bpm
          2031-03-14:, charge 63, effort 5.2, rest 1.2h, deep 0.8h, REM 0.2h, light 1.8h, eff 91%, HRV 58ms, RHR 54bpm

        30-day averages:
          charge: 42, effort: 3.6, sleep: 1.0h, HRV: 39 ms, RHR: 54 bpm
          SpO2: —%, respiration: —/min, skin-temp deviation: —°C, steps: —/day, active energy: —kcal/day
        """,
        "full-empty-store": """
        USER BIOMETRIC SUMMARY:
        No wearable data is available yet. Acknowledge this and give general, encouraging guidance while inviting the user to sync their device so future advice can reference real numbers.

        Recent workouts: none recorded in the last 30 days.
        """,
        "full-workouts-metric": """
        USER BIOMETRIC SUMMARY (the user's own wearable data):

        Recent days (newest first) — charge(0-100), effort(0-100), rest/sleep(h), deep/REM/light(h), eff(%), HRV(ms), RHR(bpm). A dash means NOT MEASURED, not zero:
          2031-03-16:, charge 67, effort 6.0, rest 7.5h, deep 1.4h, REM 1.7h, light 4.5h, eff 92%, HRV 61ms, RHR 53bpm
          2031-03-15:, charge 72, effort 33.0, rest 7.8h, deep 1.4h, REM 1.8h, light 4.5h, eff 93%, HRV 64ms, RHR 52bpm
          2031-03-14:, charge 69, effort 46.0, rest 7.6h, deep 1.4h, REM 1.7h, light 4.5h, eff 92%, HRV 62ms, RHR 52bpm
          2031-03-13:, charge —, effort 35.0, rest —, deep —, REM —, light —, eff —, HRV —, RHR —
          2031-03-12:, charge 64, effort 58.0, rest 7.3h, deep 1.3h, REM 1.6h, light 4.4h, eff 91%, HRV 59ms, RHR 54bpm
          2031-03-11:, charge 58, effort 41.0, rest 7.0h, deep —, REM —, light —, eff —, HRV 55ms, RHR 55bpm
          2031-03-10:, charge 60, effort 50.0, rest 7.2h, deep 1.2h, REM 1.6h, light 4.3h, eff 90%, HRV 57ms, RHR 54bpm
          2031-03-09:, charge 74, effort 25.0, rest 8.0h, deep 1.5h, REM 1.9h, light 4.6h, eff 94%, HRV 66ms, RHR 51bpm
          2031-03-08:, charge 66, effort 44.0, rest 7.5h, deep 1.4h, REM 1.8h, light 4.4h, eff 92%, HRV 60ms, RHR 53bpm
          2031-03-06:, charge 48, effort 30.0, rest 6.3h, deep 1.0h, REM 1.4h, light 3.9h, eff 86%, HRV 47ms, RHR 58bpm
          2031-03-05:, charge 55, effort 62.0, rest 6.7h, deep 1.1h, REM 1.5h, light 4.1h, eff 88%, HRV 52ms, RHR 56bpm
          2031-03-04:, charge 71, effort 38.0, rest 7.7h, deep 1.4h, REM 1.8h, light 4.5h, eff 93%, HRV 63ms, RHR 52bpm
          2031-03-03:, charge 62, effort 47.0, rest 7.4h, deep 1.3h, REM 1.7h, light 4.4h, eff 91%, HRV 58ms, RHR 54bpm

        30-day averages:
          charge: 64, effort: 39.6, sleep: 7.3h, HRV: 59 ms, RHR: 54 bpm
          SpO2: —%, respiration: —/min, skin-temp deviation: —°C, steps: —/day, active energy: —kcal/day

        Recent workouts (newest first):
          {W-2} swimming, 20 min, avg HR 118, 151 kcal, 640 m
          {W-4} rowing, 30 min, effort 41.2, avg HR 128, 300 kcal
          {W-6} walking, 40 min, effort 12.0, avg HR 96, 170 kcal, 3.6 km
          {W-8} hiking, 95 min
          {W-11} cycling, 45 min, avg HR 132, 410 kcal, 18.4 km
          {W-13} strength, 62 min, avg HR 108, 380 kcal
        """,
        "full-workouts-imperial": """
        USER BIOMETRIC SUMMARY (the user's own wearable data):

        Recent days (newest first) — charge(0-100), effort(0-100), rest/sleep(h), deep/REM/light(h), eff(%), HRV(ms), RHR(bpm). A dash means NOT MEASURED, not zero:
          2031-03-16:, charge 67, effort 6.0, rest 7.5h, deep 1.4h, REM 1.7h, light 4.5h, eff 92%, HRV 61ms, RHR 53bpm
          2031-03-15:, charge 72, effort 33.0, rest 7.8h, deep 1.4h, REM 1.8h, light 4.5h, eff 93%, HRV 64ms, RHR 52bpm
          2031-03-14:, charge 69, effort 46.0, rest 7.6h, deep 1.4h, REM 1.7h, light 4.5h, eff 92%, HRV 62ms, RHR 52bpm
          2031-03-13:, charge —, effort 35.0, rest —, deep —, REM —, light —, eff —, HRV —, RHR —
          2031-03-12:, charge 64, effort 58.0, rest 7.3h, deep 1.3h, REM 1.6h, light 4.4h, eff 91%, HRV 59ms, RHR 54bpm
          2031-03-11:, charge 58, effort 41.0, rest 7.0h, deep —, REM —, light —, eff —, HRV 55ms, RHR 55bpm
          2031-03-10:, charge 60, effort 50.0, rest 7.2h, deep 1.2h, REM 1.6h, light 4.3h, eff 90%, HRV 57ms, RHR 54bpm
          2031-03-09:, charge 74, effort 25.0, rest 8.0h, deep 1.5h, REM 1.9h, light 4.6h, eff 94%, HRV 66ms, RHR 51bpm
          2031-03-08:, charge 66, effort 44.0, rest 7.5h, deep 1.4h, REM 1.8h, light 4.4h, eff 92%, HRV 60ms, RHR 53bpm
          2031-03-06:, charge 48, effort 30.0, rest 6.3h, deep 1.0h, REM 1.4h, light 3.9h, eff 86%, HRV 47ms, RHR 58bpm
          2031-03-05:, charge 55, effort 62.0, rest 6.7h, deep 1.1h, REM 1.5h, light 4.1h, eff 88%, HRV 52ms, RHR 56bpm
          2031-03-04:, charge 71, effort 38.0, rest 7.7h, deep 1.4h, REM 1.8h, light 4.5h, eff 93%, HRV 63ms, RHR 52bpm
          2031-03-03:, charge 62, effort 47.0, rest 7.4h, deep 1.3h, REM 1.7h, light 4.4h, eff 91%, HRV 58ms, RHR 54bpm

        30-day averages:
          charge: 64, effort: 39.6, sleep: 7.3h, HRV: 59 ms, RHR: 54 bpm
          SpO2: —%, respiration: —/min, skin-temp deviation: —°C, steps: —/day, active energy: —kcal/day

        Recent workouts (newest first):
          {W-2} swimming, 20 min, avg HR 118, 151 kcal, 0.4 mi
          {W-4} rowing, 30 min, effort 41.2, avg HR 128, 300 kcal
          {W-6} walking, 40 min, effort 12.0, avg HR 96, 170 kcal, 2.2 mi
          {W-8} hiking, 95 min
          {W-11} cycling, 45 min, avg HR 132, 410 kcal, 11.4 mi
          {W-13} strength, 62 min, avg HR 108, 380 kcal
        """,
        "full-more-than-six-workouts": """
        USER BIOMETRIC SUMMARY (the user's own wearable data):

        Recent days (newest first) — charge(0-100), effort(0-100), rest/sleep(h), deep/REM/light(h), eff(%), HRV(ms), RHR(bpm). A dash means NOT MEASURED, not zero:
          2031-03-16:, charge 67, effort 6.0, rest 7.5h, deep 1.4h, REM 1.7h, light 4.5h, eff 92%, HRV 61ms, RHR 53bpm
          2031-03-15:, charge 72, effort 33.0, rest 7.8h, deep 1.4h, REM 1.8h, light 4.5h, eff 93%, HRV 64ms, RHR 52bpm
          2031-03-14:, charge 69, effort 46.0, rest 7.6h, deep 1.4h, REM 1.7h, light 4.5h, eff 92%, HRV 62ms, RHR 52bpm
          2031-03-13:, charge —, effort 35.0, rest —, deep —, REM —, light —, eff —, HRV —, RHR —
          2031-03-12:, charge 64, effort 58.0, rest 7.3h, deep 1.3h, REM 1.6h, light 4.4h, eff 91%, HRV 59ms, RHR 54bpm
          2031-03-11:, charge 58, effort 41.0, rest 7.0h, deep —, REM —, light —, eff —, HRV 55ms, RHR 55bpm
          2031-03-10:, charge 60, effort 50.0, rest 7.2h, deep 1.2h, REM 1.6h, light 4.3h, eff 90%, HRV 57ms, RHR 54bpm
          2031-03-09:, charge 74, effort 25.0, rest 8.0h, deep 1.5h, REM 1.9h, light 4.6h, eff 94%, HRV 66ms, RHR 51bpm
          2031-03-08:, charge 66, effort 44.0, rest 7.5h, deep 1.4h, REM 1.8h, light 4.4h, eff 92%, HRV 60ms, RHR 53bpm
          2031-03-06:, charge 48, effort 30.0, rest 6.3h, deep 1.0h, REM 1.4h, light 3.9h, eff 86%, HRV 47ms, RHR 58bpm
          2031-03-05:, charge 55, effort 62.0, rest 6.7h, deep 1.1h, REM 1.5h, light 4.1h, eff 88%, HRV 52ms, RHR 56bpm
          2031-03-04:, charge 71, effort 38.0, rest 7.7h, deep 1.4h, REM 1.8h, light 4.5h, eff 93%, HRV 63ms, RHR 52bpm
          2031-03-03:, charge 62, effort 47.0, rest 7.4h, deep 1.3h, REM 1.7h, light 4.4h, eff 91%, HRV 58ms, RHR 54bpm

        30-day averages:
          charge: 64, effort: 39.6, sleep: 7.3h, HRV: 59 ms, RHR: 54 bpm
          SpO2: —%, respiration: —/min, skin-temp deviation: —°C, steps: —/day, active energy: —kcal/day

        Recent workouts (newest first):
          {W-1} running, 30 min, effort 30.5, avg HR 140, 250 kcal, 5.0 km
          {W-2} swimming, 20 min, avg HR 118, 151 kcal, 640 m
          {W-3} running, 31 min, effort 30.5, avg HR 140, 250 kcal, 5.0 km
          {W-4} rowing, 30 min, effort 41.2, avg HR 128, 300 kcal
          {W-5} running, 32 min, effort 30.5, avg HR 140, 250 kcal, 5.0 km
          {W-6} walking, 40 min, effort 12.0, avg HR 96, 170 kcal, 3.6 km
        """,
        "full-body-line-scorecard-on": """
        USER BIOMETRIC SUMMARY (the user's own wearable data):

        Recent days (newest first) — charge(0-100), effort(0-100), rest/sleep(h), deep/REM/light(h), eff(%), HRV(ms), RHR(bpm). A dash means NOT MEASURED, not zero:
          2031-03-16:, charge 67, effort 6.0, rest 7.5h, deep 1.4h, REM 1.7h, light 4.5h, eff 92%, HRV 61ms, RHR 53bpm
          2031-03-15:, charge 72, effort 33.0, rest 7.8h, deep 1.4h, REM 1.8h, light 4.5h, eff 93%, HRV 64ms, RHR 52bpm
          2031-03-14:, charge 69, effort 46.0, rest 7.6h, deep 1.4h, REM 1.7h, light 4.5h, eff 92%, HRV 62ms, RHR 52bpm
          2031-03-13:, charge —, effort 35.0, rest —, deep —, REM —, light —, eff —, HRV —, RHR —
          2031-03-12:, charge 64, effort 58.0, rest 7.3h, deep 1.3h, REM 1.6h, light 4.4h, eff 91%, HRV 59ms, RHR 54bpm
          2031-03-11:, charge 58, effort 41.0, rest 7.0h, deep —, REM —, light —, eff —, HRV 55ms, RHR 55bpm
          2031-03-10:, charge 60, effort 50.0, rest 7.2h, deep 1.2h, REM 1.6h, light 4.3h, eff 90%, HRV 57ms, RHR 54bpm
          2031-03-09:, charge 74, effort 25.0, rest 8.0h, deep 1.5h, REM 1.9h, light 4.6h, eff 94%, HRV 66ms, RHR 51bpm
          2031-03-08:, charge 66, effort 44.0, rest 7.5h, deep 1.4h, REM 1.8h, light 4.4h, eff 92%, HRV 60ms, RHR 53bpm
          2031-03-06:, charge 48, effort 30.0, rest 6.3h, deep 1.0h, REM 1.4h, light 3.9h, eff 86%, HRV 47ms, RHR 58bpm
          2031-03-05:, charge 55, effort 62.0, rest 6.7h, deep 1.1h, REM 1.5h, light 4.1h, eff 88%, HRV 52ms, RHR 56bpm
          2031-03-04:, charge 71, effort 38.0, rest 7.7h, deep 1.4h, REM 1.8h, light 4.5h, eff 93%, HRV 63ms, RHR 52bpm
          2031-03-03:, charge 62, effort 47.0, rest 7.4h, deep 1.3h, REM 1.7h, light 4.4h, eff 91%, HRV 58ms, RHR 54bpm

        30-day averages:
          charge: 64, effort: 39.6, sleep: 7.3h, HRV: 59 ms, RHR: 54 bpm
          SpO2: —%, respiration: —/min, skin-temp deviation: —°C, steps: —/day, active energy: —kcal/day

        Recent workouts: none recorded in the last 30 days.


        LAB BOOK (the user's own logged health numbers — not medical advice; do not interpret as clinical findings):
          zz-custom-marker 3.1 mmol/L

        BODY MEASUREMENTS (the values the app shows as the user's own; kilograms and centimetres):
          Weight 97.1 kg (Lab Book, {D-0})
          Waist 97.0 cm (Lab Book, {D-0})
        """,
        "full-body-line-scorecard-off": """
        USER BIOMETRIC SUMMARY (the user's own wearable data):

        Recent days (newest first) — charge(0-100), effort(0-100), rest/sleep(h), deep/REM/light(h), eff(%), HRV(ms), RHR(bpm). A dash means NOT MEASURED, not zero:
          2031-03-16:, charge 67, effort 6.0, rest 7.5h, deep 1.4h, REM 1.7h, light 4.5h, eff 92%, HRV 61ms, RHR 53bpm
          2031-03-15:, charge 72, effort 33.0, rest 7.8h, deep 1.4h, REM 1.8h, light 4.5h, eff 93%, HRV 64ms, RHR 52bpm
          2031-03-14:, charge 69, effort 46.0, rest 7.6h, deep 1.4h, REM 1.7h, light 4.5h, eff 92%, HRV 62ms, RHR 52bpm
          2031-03-13:, charge —, effort 35.0, rest —, deep —, REM —, light —, eff —, HRV —, RHR —
          2031-03-12:, charge 64, effort 58.0, rest 7.3h, deep 1.3h, REM 1.6h, light 4.4h, eff 91%, HRV 59ms, RHR 54bpm
          2031-03-11:, charge 58, effort 41.0, rest 7.0h, deep —, REM —, light —, eff —, HRV 55ms, RHR 55bpm
          2031-03-10:, charge 60, effort 50.0, rest 7.2h, deep 1.2h, REM 1.6h, light 4.3h, eff 90%, HRV 57ms, RHR 54bpm
          2031-03-09:, charge 74, effort 25.0, rest 8.0h, deep 1.5h, REM 1.9h, light 4.6h, eff 94%, HRV 66ms, RHR 51bpm
          2031-03-08:, charge 66, effort 44.0, rest 7.5h, deep 1.4h, REM 1.8h, light 4.4h, eff 92%, HRV 60ms, RHR 53bpm
          2031-03-06:, charge 48, effort 30.0, rest 6.3h, deep 1.0h, REM 1.4h, light 3.9h, eff 86%, HRV 47ms, RHR 58bpm
          2031-03-05:, charge 55, effort 62.0, rest 6.7h, deep 1.1h, REM 1.5h, light 4.1h, eff 88%, HRV 52ms, RHR 56bpm
          2031-03-04:, charge 71, effort 38.0, rest 7.7h, deep 1.4h, REM 1.8h, light 4.5h, eff 93%, HRV 63ms, RHR 52bpm
          2031-03-03:, charge 62, effort 47.0, rest 7.4h, deep 1.3h, REM 1.7h, light 4.4h, eff 91%, HRV 58ms, RHR 54bpm

        30-day averages:
          charge: 64, effort: 39.6, sleep: 7.3h, HRV: 59 ms, RHR: 54 bpm
          SpO2: —%, respiration: —/min, skin-temp deviation: —°C, steps: —/day, active energy: —kcal/day

        Recent workouts: none recorded in the last 30 days.


        LAB BOOK (the user's own logged health numbers — not medical advice; do not interpret as clinical findings):
          zz-custom-marker 3.1 mmol/L, Weight 97.1 kg
        """,
        "full-signals-off": """
        USER BIOMETRIC SUMMARY (the user's own wearable data):

        Recent days (newest first) — charge(0-100), effort(0-100), rest/sleep(h), deep/REM/light(h), eff(%), HRV(ms), RHR(bpm). A dash means NOT MEASURED, not zero:
          2031-03-16:, charge 67, effort 6.0, rest 7.5h, deep 1.4h, REM 1.7h, light 4.5h, eff 92%, HRV 61ms, RHR 53bpm
          2031-03-15:, charge 72, effort 33.0, rest 7.8h, deep 1.4h, REM 1.8h, light 4.5h, eff 93%, HRV 64ms, RHR 52bpm
          2031-03-14:, charge 69, effort 46.0, rest 7.6h, deep 1.4h, REM 1.7h, light 4.5h, eff 92%, HRV 62ms, RHR 52bpm
          2031-03-13:, charge —, effort 35.0, rest —, deep —, REM —, light —, eff —, HRV —, RHR —
          2031-03-12:, charge 64, effort 58.0, rest 7.3h, deep 1.3h, REM 1.6h, light 4.4h, eff 91%, HRV 59ms, RHR 54bpm
          2031-03-11:, charge 58, effort 41.0, rest 7.0h, deep —, REM —, light —, eff —, HRV 55ms, RHR 55bpm
          2031-03-10:, charge 60, effort 50.0, rest 7.2h, deep 1.2h, REM 1.6h, light 4.3h, eff 90%, HRV 57ms, RHR 54bpm
          2031-03-09:, charge 74, effort 25.0, rest 8.0h, deep 1.5h, REM 1.9h, light 4.6h, eff 94%, HRV 66ms, RHR 51bpm
          2031-03-08:, charge 66, effort 44.0, rest 7.5h, deep 1.4h, REM 1.8h, light 4.4h, eff 92%, HRV 60ms, RHR 53bpm
          2031-03-06:, charge 48, effort 30.0, rest 6.3h, deep 1.0h, REM 1.4h, light 3.9h, eff 86%, HRV 47ms, RHR 58bpm
          2031-03-05:, charge 55, effort 62.0, rest 6.7h, deep 1.1h, REM 1.5h, light 4.1h, eff 88%, HRV 52ms, RHR 56bpm
          2031-03-04:, charge 71, effort 38.0, rest 7.7h, deep 1.4h, REM 1.8h, light 4.5h, eff 93%, HRV 63ms, RHR 52bpm
          2031-03-03:, charge 62, effort 47.0, rest 7.4h, deep 1.3h, REM 1.7h, light 4.4h, eff 91%, HRV 58ms, RHR 54bpm

        30-day averages:
          charge: 64, effort: 39.6, sleep: 7.3h, HRV: 59 ms, RHR: 54 bpm
          SpO2: —%, respiration: —/min, skin-temp deviation: —°C, steps: —/day, active energy: —kcal/day

        Recent workouts: none recorded in the last 30 days.
        """,
        "refreshed-steps-strap": """
        USER BIOMETRIC SUMMARY (the user's own wearable data):

        Recent days (newest first) — charge(0-100), effort(0-100), rest/sleep(h), deep/REM/light(h), eff(%), HRV(ms), RHR(bpm). A dash means NOT MEASURED, not zero:
          {D-1}:, charge 62, effort 47.0, rest 7.4h, deep 1.3h, REM 1.7h, light 4.4h, eff 91%, HRV 58ms, RHR 54bpm
          {D-2}:, charge 62, effort 47.0, rest 7.4h, deep 1.3h, REM 1.7h, light 4.4h, eff 91%, HRV 58ms, RHR 54bpm
          {D-3}:, charge 62, effort 47.0, rest 7.4h, deep 1.3h, REM 1.7h, light 4.4h, eff 91%, HRV 58ms, RHR 54bpm

        30-day averages:
          charge: 62, effort: 47.0, sleep: 7.4h, HRV: 58 ms, RHR: 54 bpm
          SpO2: —%, respiration: —/min, skin-temp deviation: —°C, steps: 9607/day, active energy: —kcal/day
        """,
        "refreshed-steps-apple-health": """
        USER BIOMETRIC SUMMARY (the user's own wearable data):

        Recent days (newest first) — charge(0-100), effort(0-100), rest/sleep(h), deep/REM/light(h), eff(%), HRV(ms), RHR(bpm). A dash means NOT MEASURED, not zero:
          {D-1}:, charge 62, effort 47.0, rest 7.4h, deep 1.3h, REM 1.7h, light 4.4h, eff 91%, HRV 58ms, RHR 54bpm
          {D-2}:, charge 62, effort 47.0, rest 7.4h, deep 1.3h, REM 1.7h, light 4.4h, eff 91%, HRV 58ms, RHR 54bpm
          {D-3}:, charge 62, effort 47.0, rest 7.4h, deep 1.3h, REM 1.7h, light 4.4h, eff 91%, HRV 58ms, RHR 54bpm

        30-day averages:
          charge: 62, effort: 47.0, sleep: 7.4h, HRV: 58 ms, RHR: 54 bpm
          SpO2: —%, respiration: —/min, skin-temp deviation: —°C, steps: —/day, active energy: —kcal/day
        """,
        "refreshed-steps-estimate": """
        USER BIOMETRIC SUMMARY (the user's own wearable data):

        Recent days (newest first) — charge(0-100), effort(0-100), rest/sleep(h), deep/REM/light(h), eff(%), HRV(ms), RHR(bpm). A dash means NOT MEASURED, not zero:
          {D-1}:, charge 62, effort 47.0, rest 7.4h, deep 1.3h, REM 1.7h, light 4.4h, eff 91%, HRV 58ms, RHR 54bpm
          {D-2}:, charge 62, effort 47.0, rest 7.4h, deep 1.3h, REM 1.7h, light 4.4h, eff 91%, HRV 58ms, RHR 54bpm
          {D-3}:, charge 62, effort 47.0, rest 7.4h, deep 1.3h, REM 1.7h, light 4.4h, eff 91%, HRV 58ms, RHR 54bpm

        30-day averages:
          charge: 62, effort: 47.0, sleep: 7.4h, HRV: 58 ms, RHR: 54 bpm
          SpO2: —%, respiration: —/min, skin-temp deviation: —°C, steps: —/day, active energy: —kcal/day
        """,
    ]
}
