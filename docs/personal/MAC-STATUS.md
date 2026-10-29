# Mac build status — 21 October 2026, IST

> Historical record. By 28 October the signed iPhone app/widget build and installation succeeded;
> the owner confirmed the final app opens, Coach replies and saved sign-in work, and workout imports
> work. The Processing blocker below is resolved. Start with [current context](CONTEXT.md).

The owner's Mac completed the baseline and personal build work. **The app is not installed or
launched on the physical iPhone.** The owner confirmed that Apple Developer lists the phone as
**Processing**, which excludes it from development provisioning until Apple enables it.

This record is based on the owner's handoff and the existing **Install Noop on iPhone** task's
command results, build summaries and final diff. The cloud did not rerun Xcode or contact the
phone. Private local signing configuration, profiles, device identifiers and app inventory were
not copied into this repository.

## Completed on the Mac

| Check | Recorded result |
|---|---|
| Mac setup | Apple Silicon, macOS 27.0.1; Xcode 27.1 (27A9275), XcodeGen 2.45.4 and required SDKs installed. License/first launch completed by the owner. No further sudo operation is currently needed. |
| Developer-directory selection | Per-command `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer`; machine-wide selection preserved. |
| Immutable original baseline | Pinned `8e4b0c16e7640607600fa6bde5424095eba6034e` built successfully from a temporary Git archive, signing off, arm64 and x86_64 Simulator architectures. This historical run included upstream watch targets before the scope changed; do not repeat watch work. |
| Personal Simulator build | Passed after making the shared `FormRow` accessible to the goal view. Personal widget SwiftUI views compiled. |
| Relevant macOS tests | **94 passed, zero failures**: personal widget metrics, snapshots, settings disclosure defaults, HR/stress traces and widget telemetry. |
| Build-helper tests | 12 passed; these mock Apple tooling and do not establish device readiness. |
| Simulator first launch | Personal app installed and launched on an isolated iPhone simulator; first-run agreement screen visually checked. No agreement accepted or permissions granted. Simulator later shut down with its data retained. This launch preceded watch removal. |
| Final iPhone-only unsigned build | **Passed using the iPhoneOS SDK.** App graph contained `NOOPiOS` and `NOOPiOSWidgets`; widget embedded, no watch app built or embedded. This was compilation for iPhone hardware, not execution on a phone. |
| Static capabilities | Personal bundle IDs, matching runtime App Group, display names, Bluetooth background mode and HealthKit/background delivery declarations checked. Signed entitlements remain pending. |
| Phone preparation | Wired connection, trust/developer pairing, Developer Mode and device services verified. Complete local app inventory had no personal bundle-ID collision. Recheck before first installation. |

The final unsigned iPhone-only build was recorded at **19:24 IST**. None of the successful unsigned
builds establishes a signed development profile, physical launch, Bluetooth collection or sensor accuracy.

## Source synchronized from the exact Mac diff

The Mac checkout started at `398af6155ebbe5cf4cae1acdc5e45bc029b9f8d3` on
`personal/iphone-baseline`. At handoff it had exactly these four tracked modifications, uncommitted.
The cloud applied the same diff; Git blob prefixes match the local task's recorded diff:

| File | Resulting Git blob prefix | Change |
|---|---|---|
| `Strand/Screens/SettingsView.swift` | `8103a08b` | `FormRow` is internal to the app module instead of private to one file. |
| `project.yml` | `279494c3` | App/widget display name **NOOP Cyril**; remove the `NOOPiOS → NOOPWatch` dependency; preserve the iPhone widget. |
| `StrandiOS/Resources/Info.plist` | `3c2cc7fb` | Generated display name plus the existing `.stalebattery` background identifier from the project source. |
| `StrandiOSWidgets/Info.plist` | `5347b66f` | Generated widget display name. |

Cloud checks confirmed that the personal application's transitive target dependencies contain only
`NOOPiOS` and `NOOPiOSWidgets`; project/plist display names, App Group placeholders and background
task declarations agree, and HealthKit declarations remain present. The standalone upstream watch
source/targets remain in the repository but are not dependencies of the personal iPhone build.

**The owner has no Apple Watch and requested iPhone-only work.** Do not restore watch embedding,
ask for watch provisioning, install watch runtimes or spend more time building watch targets.

## Provisioning blocker

Two signed-build attempts were blocked: one reported an existing team device, another reported that
the phone was not registered/included in a usable profile. The owner then confirmed **Processing**
in the correct Apple Developer team, and the inspected profiles excluded the phone. This is a
provisioning prerequisite, not evidence of another Swift compiler failure or a missing cloud secret.

[Apple's device-registration guidance](https://developer.apple.com/help/account/reference/device-registration-updates/)
explains Processing. Its published 24–72-hour window for the affected registration category is not
a guarantee for this phone; no completion time has been established here. Elapsed time alone is
not an Enabled status. Do not repeatedly register the phone, revoke certificates, disable devices,
change accounts or create a paid build workaround.

No background polling or automatic signing/install retry is scheduled. The next prerequisite is
the owner's confirmation that the phone shows **Enabled**, followed by a fresh provisioning check
on the Mac. The phone need not remain attached while waiting.

## Resume without losing local work

Use the existing local task and checkout at `/Users/cyrilbhau/Documents/Noop/noop-fork`.
Follow [MAC-CONTINUE.md](MAC-CONTINUE.md): preserve/commit the four local source changes before
merging the cloud branch, retain the ignored signing configuration and build evidence, and never
reset the checkout to discard them. Do not request the developer account or team choice again.

After **Enabled**, reconnect the unlocked iPhone, recheck the app inventory, refresh development
provisioning and sign only the iPhone app/widget. Verify signed identity, team, App Group, HealthKit,
device inclusion and absence of a watch bundle before installing and launching. Let the owner
review first-run agreements and permissions; keep Health writes off.

Local evidence is retained under ignored `build/personal/`: `mac-progress.json`,
`iphone-only-build-result.json` and `logs/{baseline-ios,personal-ios,mac-widget-settings-tests,iphone-only-unsigned,iphone-build}.log`.
These are Mac-local paths, not files available in the cloud. Device identifiers remain local and
must not be printed or committed. No certificate/private key was exported.

## Still unverified

Successful signed physical build, installation and launch; live WHOOP pairing; HR/R-R/motion
collection; reconnect/backfill; overnight accuracy; widget refresh; HealthKit writes; step accuracy;
real imports and backup restore. Follow [DEVICE-TESTING.md](DEVICE-TESTING.md) after installation.
Agreed step limits remain ≤10% on each counted 500–1,000-step walk and ≤20 false steps in
30 seated minutes. No app was published and no firmware or health data was changed.
