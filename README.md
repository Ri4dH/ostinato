# Ostinato

A free, private practice journal for musicians on iPhone, iPad and Apple Watch.

Start a session, then tap whatever you're working on. Ostinato times each piece
or exercise separately, so a session reads "10 min scales, 20 on the étude, 30 on
the Chaconne", and you can see how that adds up over weeks.

<p>
  <img src="docs/app-store/screenshots/iPhone%2017%20Pro%20Max/1-session.png" width="200" alt="Running session with one-tap item switching">
  <img src="docs/app-store/screenshots/iPhone%2017%20Pro%20Max/2-finish.png" width="200" alt="Finish sheet with time per item">
  <img src="docs/app-store/screenshots/iPhone%2017%20Pro%20Max/3-stats.png" width="200" alt="Stats with weekly summary">
  <img src="docs/app-store/screenshots/Apple%20Watch%20Ultra%203%20(49mm)/1-active.png" width="170" alt="Apple Watch session">
</p>

## Features

- **Time per piece.** Switch items with one tap while the timer runs. Per-item totals, minutes per week and tempo history.
- **A timer you can trust.** Time comes from timestamps, never ticks, so it stays right through backgrounding, phone calls, app kills, midnight, DST and clock changes.
- **Apple Watch.** Start, switch, pause and finish from the wrist. Works offline; sessions reach the iPhone exactly once when it reconnects.
- **System integration.** Live Activity and Dynamic Island, Home and Lock Screen widgets, a Control Center control, and Siri / Shortcuts ("Log 20 minutes of scales in Ostinato").
- **Tools.** Sample-accurate metronome, chromatic tuner (±1 cent, transposing instruments, custom tunings), drone in all 12 keys, recording with on-device tempo and key estimates.
- **Stats.** Minutes per day, instrument, item and category; streaks with rest days; a weekly summary (generated on device when Apple Intelligence is available, rules-based otherwise).
- **Export.** CSV for spreadsheets, a PDF report for your teacher, and a full JSON backup that imports without duplicates.

## Privacy

No account, no analytics, no ads, no third-party SDKs. Data stays on your devices
and, if you leave sync on, in your own private iCloud.
[Privacy policy](https://ri4dh.github.io/ostinato/privacy/)

## Building

Requirements: Xcode 26.6 or later, [XcodeGen](https://github.com/yonaskolb/XcodeGen), iOS / iPadOS / watchOS 26.

```sh
brew install xcodegen
xcodegen generate
open Ostinato.xcodeproj
```

The simulator works out of the box. To run on a device, set your reverse-DNS
prefix and team in `Config/Shared.xcconfig` (the only place bundle IDs, the App
Group and the iCloud container are defined), then run `xcodegen generate` again:

```
OSTINATO_BUNDLE_PREFIX = com.yourname
DEVELOPMENT_TEAM = ABCDE12345
```

`Ostinato.xcodeproj` is generated from `project.yml`; edit the YAML, not the project.

## Project layout

```
Packages/PracticeKit   Shared logic as a Swift package (models, session engine, stats,
                       export, audio, watch sync, analysis), unit-tested on the Mac
App                    iOS / iPadOS app (SwiftUI)
Shared                 App Intents and Live Activity attributes, used by app and widgets
Widgets                Widgets, Live Activity, Control Center control
WatchApp               watchOS app
WatchWidgets           Watch complications
UITests, WatchUITests  UI tests, accessibility audits, screenshot capture
docs                   App Store listing, review notes, privacy page (GitHub Pages)
```

## How it works

- **Session engine.** `SessionEngine` is a pure value type with an injected clock.
  The running session is a small `ActiveSession` snapshot written to the App Group
  after every change, so widgets, intents, the Live Activity and the watch all read
  the same file, and a killed app resumes where it left off.
- **Storage.** SwiftData with the CloudKit private database (every property
  optional or defaulted, no unique constraints). Sync can be turned off; the local
  store is kept.
- **Stats at scale.** Statistics run on lightweight `SessionRecord` values cached
  to a file, updated per session and rebuilt on a background `ModelActor` after
  imports or iCloud changes. Covered by a 10,000-session / 50,000-segment test.
- **Watch sync.** The iPhone owns the store. Finished watch sessions go through
  `transferUserInfo` with a persisted outbox and acknowledgements; live state uses
  messages with application context as fallback. If both devices start a session,
  the earlier one wins and the user chooses whether to merge.
- **Audio.** The metronome renders each bar into a buffer at exact sample offsets.
  The drone is an `AVAudioSourceNode` oscillator bank with click-free fades. The
  tuner uses YIN pitch detection. Recording analysis uses spectral-flux
  autocorrelation for tempo and chroma with Krumhansl–Schmuckler profiles for key.

## Testing

```sh
# Unit tests for PracticeKit (fast, runs on the Mac)
cd Packages/PracticeKit && swift test

# Everything, including UI tests and accessibility audits
xcodebuild test -project Ostinato.xcodeproj -scheme Ostinato \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro'

# App Store screenshots for iPhone, iPad and Apple Watch
scripts/screenshots.sh
```

The accessibility audit policy is described in [docs/accessibility.md](docs/accessibility.md).

## Status

Version 1.0 is feature-complete in the simulator. Still to do before release:

- Testing on real devices, including iCloud sync and phone/watch sync on paired hardware
- Final custom instrument symbols (built-in SF Symbols stand in for now)
- Apple's Music Understanding framework for recording analysis (needs the iOS 27 SDK);
  the on-device analyzer in `PracticeKit` covers it until then

The full specification is in [practice-journal-build-plan.md](practice-journal-build-plan.md).

## Acknowledgements

Built with help from these agent skills, bundled in `.claude/skills` under their MIT
licenses: [MobileBuildMCP](https://github.com/getsentry/MobileBuildMCP),
[SwiftUI Agent Skill](https://github.com/AvdLee/SwiftUI-Agent-Skill),
[Dimillian/Skills](https://github.com/Dimillian/Skills) and
[writing-for-interfaces](https://github.com/andrewgleave/skills/tree/main/writing-for-interfaces).

## License

[MIT](LICENSE). The bundled agent skills in `.claude/skills` keep their own MIT
licenses and copyright notices.
