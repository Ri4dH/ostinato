# Build Plan: Ostinato — Music Practice Log (iPhone + Apple Watch)

> **Audience:** a coding agent building this app from scratch.
> **App name:** **Ostinato** (decided). App Store name: **"Ostinato: Music Practice Log"**. Home-screen display name: "Ostinato". Keep the display name in one place (Info.plist / String Catalog). Xcode project and app target: `Ostinato`; shared package stays `PracticeKit`. Bundle ID: `com.<developer>.ostinato` (owner fills in `<developer>`); watch and widget bundle IDs are suffixes of it (`.watchkitapp`, `.widgets`). App Group: `group.com.<developer>.ostinato`; iCloud container: `iCloud.com.<developer>.ostinato`.
> **Status:** spec v1.1, 2026-11-23 (owner decisions applied — see section 16).

---

## 1. What we are building (one paragraph)

A **completely free, private, offline-first practice journal for musicians**. A musician starts a timer when they practice, splits the session into what they actually worked on (scales, piece A, piece B…), optionally records themselves, and ends with a quick rating and note. Over time the app shows how much time went into each piece, tempo progress, streaks, and weekly trends. It runs entirely on the user's devices — **no accounts, no servers, no ads, no analytics, no in-app purchases**. Data syncs between the user's own devices through their private iCloud (CloudKit) only. Apple Watch support is first-class so musicians can control the timer without touching the phone.

**Tagline idea:** "The practice journal that stays out of your way."

---

## 2. Why this app (context for design decisions)

Research on the US App Store (Nov 2026) found:

- **Andante** (4.9★, ~3.1k ratings) is the leader, but users' top requests are unmet:
  - **Time per piece within a session** ("10 min scales, 20 on piece A, 30 on piece B" + per-piece stats) — most repeated request.
  - **Apple Watch app** (none exists).
  - Multiple instruments without paying, multiple tags per session, timestamps on recordings.
- **Modacity** redesigned in Jan 2026 and moved basic stats/lists behind a ~$14.99/mo paywall; reviews complain about sync losing data and **the timer dying when switching apps**.
- **Mujo**: timer stops in background unless metronome is on.
- Only 1 of the main competitors has a Watch app (subscription-only).
- Users repeatedly praise "no subscription" and "simple, no fluff".

**Therefore our differentiators (must be excellent):**
1. **Segmented sessions** — time tracked per piece/exercise, with per-piece stats.
2. **Rock-solid timer** — never loses time when backgrounded, killed, or interrupted.
3. **Apple Watch app** — start/switch/stop from the wrist.
4. **Everything free**, unlimited instruments, no paywall anywhere.
5. **Private by design** — "Data Not Collected" privacy label.
6. Deep system integration: Live Activity, widgets, Siri/Shortcuts, Control Center.
7. (Later) on-device audio analysis of recordings and on-device AI weekly summaries.

---

## 3. Goals and non-goals

### Goals
- Logging a practice session takes **≤ 2 taps to start**, **1 tap to switch piece**, **≤ 3 taps to finish & save**.
- Timer accuracy is **never wrong** after background, app kill, device lock, or phone call.
- Works 100% offline. iCloud sync is a bonus, not a requirement.
- Usable at music-stand distance: huge timer digits, big touch targets.
- Fully accessible (VoiceOver, Dynamic Type, Reduce Motion).

### Non-goals (do NOT build)
- Accounts, login, social feeds, friends, leaderboards (would need a server).
- Ads, analytics SDKs, crash-reporting SDKs, any third-party SDK that phones home.
- In-app purchases, tip jar, subscriptions, paywalls.
- Lesson content, courses, sheet-music display/scanning.
- Android, web, or a custom backend of any kind.

---

## 4. Platforms and technical baseline

| Item | Choice |
|---|---|
| Platforms (v1) | iPhone, iPad (same universal app), Apple Watch (companion watchOS app) |
| Platforms (later) | Mac via "Designed for iPad" or native macOS target (v2, optional) |
| Minimum OS | **iOS/iPadOS 27.0, watchOS 27.0** (decided — see section 16). No `#available` gating needed for iOS 27 APIs; only Apple Intelligence features are gated by device capability |
| Xcode / SDK | Latest stable Xcode (Xcode 27 at time of writing). App Store requires at least the iOS 26 SDK. |
| Language | Swift 6, strict concurrency enabled |
| UI | SwiftUI only (UIKit only where unavoidable) |
| Persistence | SwiftData |
| Sync | SwiftData + CloudKit **private database** (user's own iCloud) |
| Charts | Swift Charts |
| Audio | AVFoundation / AVAudioEngine |
| Tests | Swift Testing (unit), XCTest UI tests |
| Third-party dependencies | **None.** Use Apple frameworks only. |

> ⚠️ **iOS 27 APIs are new (Sept 2026).** For Music Understanding, Foundation Models updates, and new App Intents features, **check Apple's current documentation before writing code**. Do not guess API names. If an API differs from this spec, follow the docs and note the difference.

---

## 5. Project structure

```
Ostinato/
├── Ostinato.xcodeproj
├── Packages/
│   └── PracticeKit/                 # Local Swift package — all shared logic, fully unit-tested
│       ├── Sources/PracticeKit/
│       │   ├── Models/              # SwiftData @Model types
│       │   ├── Timer/               # Session engine (timestamp-based)
│       │   ├── Stats/               # Aggregations, streaks, goals
│       │   ├── Export/              # CSV / JSON export & import
│       │   ├── Audio/               # Metronome engine, recorder wrappers
│       │   └── Intelligence/        # Audio analysis + AI summaries (gated)
│       └── Tests/PracticeKitTests/
├── App/                             # iOS/iPadOS app target (SwiftUI views, navigation)
├── WatchApp/                        # watchOS app target
├── Widgets/                         # Widget extension: widgets, Live Activity, Control Center controls
└── Shared/                          # App Group constants, Intents shared between targets
```

- Use an **App Group** so the app, widgets, and Live Activity can read the same store and state.
- Keep files under ~500 lines. One view per file for non-trivial views.
- Business logic lives in `PracticeKit`, not in views. Views stay thin.

---

## 6. Data model (SwiftData)

> **CloudKit rules for SwiftData (must follow, or sync silently breaks):** every property must be optional **or** have a default value; **no `@Attribute(.unique)`**; all relationships optional; set inverse relationships explicitly; no ordered relationships (store a `sortIndex` instead).

### `Instrument`
| Field | Type | Notes |
|---|---|---|
| id | UUID | default `UUID()` |
| name | String | "Violin", "Piano", custom |
| presetKey | String? | key into the preset list (section 8.0); nil for custom |
| symbolName | String | bundled custom symbol or SF Symbol name |
| colorHex | String | user color |
| transposition | Int | semitones, default 0 (e.g. B♭ clarinet = −2, E♭ alto sax = −9, F horn = −7). Used by tuner and drone |
| sortIndex | Int | |
| isArchived | Bool | default false |
| createdAt | Date | |
| items | [PracticeItem]? | inverse |
| sessions | [PracticeSession]? | inverse |

### `PracticeItem` (repertoire entry: piece, exercise, scale, technique)
| Field | Type | Notes |
|---|---|---|
| id | UUID | |
| title | String | "Bach Partita No. 2 – Chaconne" |
| composer | String? | |
| category | String (enum raw) | `piece`, `exercise`, `scale`, `technique`, `sightReading`, `improv`, `other` |
| status | String (enum raw) | `learning`, `polishing`, `performanceReady`, `maintaining`, `archived` |
| targetTempo | Int? | BPM goal |
| lastTempo | Int? | last BPM used / recorded |
| notes | String | default "" |
| sortIndex | Int | |
| createdAt / updatedAt | Date | |
| instrument | Instrument? | |
| segments | [SessionSegment]? | inverse |
| recordings | [Recording]? | inverse |
| tempoLog | [TempoEntry]? | inverse |

### `PracticeSession`
| Field | Type | Notes |
|---|---|---|
| id | UUID | |
| startDate | Date | wall-clock start |
| endDate | Date? | nil while active |
| activeDuration | TimeInterval | total minus pauses, computed and stored on finish |
| source | String (enum raw) | `phone`, `watch`, `manual`, `siri` |
| rating | Int? | 1–5 "how did it go" |
| focus | Int? | 1–5 |
| notes | String | default "" |
| tags | [String] | default [] (multiple tags allowed) |
| instrument | Instrument? | |
| segments | [SessionSegment]? | inverse |
| pauses | [PauseInterval]? | inverse |
| recordings | [Recording]? | inverse |

### `SessionSegment` (the key feature: time per piece)
| Field | Type | Notes |
|---|---|---|
| id | UUID | |
| startDate | Date | |
| endDate | Date? | |
| activeDuration | TimeInterval | excludes pauses that overlap it |
| label | String? | used when no item selected ("Warm-up") |
| sortIndex | Int | |
| session | PracticeSession? | |
| item | PracticeItem? | nil = general / unlabeled |

### `PauseInterval`
`id`, `startDate`, `endDate?`, `session`.

### `Recording`
| Field | Type | Notes |
|---|---|---|
| id | UUID | |
| createdAt | Date | |
| duration | TimeInterval | |
| audioFileName | String | file name only (e.g. `<uuid>.m4a`), never an absolute path. AAC `.m4a`, mono, 64 kbps. See "Recording storage" below |
| fileLocation | String (enum raw) | `local`, `iCloud` — where the audio file currently lives |
| offsetInSession | TimeInterval? | timestamp within session |
| title | String | default "" |
| analysisJSON | Data? | cached audio analysis result (v1.2) |
| session / segment / item | optional relationships | |

### Recording storage (audio files are NOT stored inside SwiftData)
- Recording **metadata** (`Recording` model) lives in SwiftData like everything else.
- The **audio file** lives on disk, in one of two places:
  - **Local:** `Application Support/Recordings/` in the App Group container (included in normal device backups).
  - **iCloud:** the app's iCloud Drive ubiquity container `Recordings/` folder (system syncs it; use `NSFileCoordinator` and handle not-yet-downloaded files with a "Download" state in the UI).
- The **"Sync recordings to iCloud"** setting (section 8.16) moves files between the two locations in the background and updates `fileLocation`. Moving is resumable and safe to interrupt.
- If metadata syncs to a device but the file is local-only on another device, show the recording as "Stored on another device" (not as an error).
- Always build file URLs as `baseDirectory(for: fileLocation).appending(path: audioFileName)`; validate that `audioFileName` contains no path separators.

### `TempoEntry`
`id`, `date`, `bpm: Int`, `source` (`manual`, `metronome`, `analysis`), `item`.

### `Goal` (singleton-ish; or store in UserDefaults via App Group)
`dailyMinutes: Int` (default 30), `daysPerWeek: Int` (default 5), `streakFreezeEnabled: Bool`.

---

## 7. The session engine (most critical component)

The timer must **never** drift or lose time. Rules:

1. **Never count ticks.** Store timestamps (`startDate`, pause start/end) and compute elapsed as `now − start − totalPausedTime`. UI refreshes with `TimelineView` / `Text(timerInterval:)`.
2. **Persist the active session immediately** on start, on every segment switch, and on pause/resume. If the app is killed, on next launch it shows "You have a session in progress (started 14:02). Resume / Finish / Discard".
3. **Only one active session at a time** across phone + watch. If the watch starts a session, the phone shows it as active (and vice versa) via WatchConnectivity.
4. **Segment switching** closes the current segment (`endDate = now`) and opens a new one in the same transaction.
5. **Pauses** are intervals. Segment `activeDuration` = segment wall time minus overlapping pauses.
6. **Interruptions** (phone call, Siri, other app playing audio): timer keeps running (it's timestamp-based). Recording and metronome stop gracefully on `AVAudioSession.interruptionNotification`. Do NOT auto-pause the timer. Show a banner: "Recording stopped due to interruption".
7. **Sessions crossing midnight** count toward the day they **started**.
8. **Auto-stop safety:** if a session has been running > 4 hours, send a local notification: "Still practicing?" Do not auto-delete.
9. Implement `SessionEngine` in `PracticeKit` as a pure, testable type (inject a `Clock`/`now` provider for tests).

### Unit tests required for the engine
- Elapsed time correct across pause/resume sequences.
- Segment durations sum to session active duration (± 1s).
- Restore after simulated kill.
- Session spanning midnight / DST change / timezone change.
- Concurrent start from watch and phone → one session wins (earliest `startDate`), the other is merged into it as segments or discarded with a user prompt.

---

## 8. Features — v1.0 (MVP, ship this first)

### 8.0 Instrument presets and icons (decided)

**Preset list** (grouped in the picker; user can always add a custom instrument with any name, icon and color):

| Group | Instruments (transposition in semitones, for tuner/drone) |
|---|---|
| Keyboard | Piano, Keyboard/Synth, Organ, Harpsichord, Accordion |
| Strings | Violin, Viola, Cello, Double Bass, Harp |
| Guitar family | Acoustic Guitar, Classical Guitar, Electric Guitar, Bass Guitar, Ukulele, Mandolin, Banjo |
| Woodwinds | Flute, Piccolo, Recorder, Oboe, Bassoon, Clarinet in B♭ (−2), Bass Clarinet (−14), Alto Sax (−9), Tenor Sax (−14), Baritone Sax (−21), Soprano Sax (−2) |
| Brass | Trumpet in B♭ (−2), Cornet (−2), French Horn in F (−7), Trombone, Euphonium, Tuba |
| Percussion | Drum Kit, Snare, Mallets/Marimba, Timpani, Hand Percussion |
| Voice | Voice / Singing |
| Other | Music Theory, Ear Training, Composition, Conducting, Other |

- Store presets in code as a static list (`InstrumentPreset` with `key`, localized name, group, default `symbolName`, default color, default transposition). Users can edit name/color/transposition after adding.
- Percussion, theory, ear training etc. have no tuner (hide tuner/drone for them).

**Icon style:**
- **Monoline icons matching SF Symbols** (same stroke weights, template-rendered so they take the instrument's tint color, work in light/dark and at all Dynamic Type sizes).
- Ship them as **custom SF Symbols** in the asset catalog (`.symbolset`), one per preset family (piano keys, organ pipes, violin, cello, guitar, electric guitar, bass, ukulele, flute, clarinet, saxophone, trumpet, horn, trombone, tuba, drum kit, mallets, microphone/voice, harp, accordion, generic note).
- **Placeholder plan:** until the custom symbols are drawn, use the closest built-in SF Symbols (`pianokeys`, `guitars`, `music.mic`, `music.note`, `music.quarternote.3`, `metronome`, etc.) via the same `symbolName` field, so swapping in final art requires no code change.
- Each instrument also has a **color**; offer a curated palette of ~12 colors with good contrast in light and dark mode.

### 8.1 Onboarding (skippable, ≤ 3 screens)
- Pick one or more instruments (preset list + custom).
- Optional daily goal (minutes) and days per week.
- Optional reminder time (asks notification permission only if they choose a time).
- **Do not** ask for microphone permission here — ask on first recording / metronome-with-mic use.

### 8.2 Practice tab (home)
- Big **Start Practice** button. If more than one instrument, the last-used one is preselected (tap to change).
- Today summary: minutes today vs goal (ring), current streak.
- "Continue with…" quick chips: the 3–5 most recently practiced items.
- "Log past session" button for manual entry.

### 8.3 Active session screen
- **Huge timer** (total), plus smaller timer for the current segment.
- **Current item** shown prominently; a horizontal row / sheet of repertoire items to **switch with one tap**. "+ New item" inline.
- Buttons: Pause/Resume, Record, Metronome, Note, Finish.
- Keep screen awake while active (`isIdleTimerDisabled`), with a setting to turn this off.
- Starts a **Live Activity** (see 8.9).

### 8.4 Finish sheet
- Summary: total time, segment breakdown (editable: rename, reassign item, adjust minutes, delete segment).
- Rating 1–5 ("How did it go?"), focus 1–5, notes, tags (multi-select + create new).
- Save / Discard (discard requires confirmation).

### 8.5 Manual log
- Date, start time, duration, instrument, one or more segments (item + minutes), rating, notes, tags.

### 8.6 Repertoire tab
- Grouped by instrument, filter by status/category, search.
- Item detail:
  - Total time all-time / this week / this month.
  - Chart: minutes per week on this item.
  - Tempo history chart (target vs logged BPM).
  - Recordings list for this item (play, rename, delete, share).
  - Notes (free text), status picker, target tempo.
- Archive instead of delete by default; delete requires confirmation and explains that history segments keep the time but lose the link.

### 8.7 Stats tab (Swift Charts)
- Time range picker: week / month / year / all.
- Total minutes per day (bar), per instrument (stacked), per item (top 10 horizontal bar), per category (scales vs pieces…).
- Calendar heatmap of practice days.
- Streak (current / longest), goal completion rate.
- Rating & focus averages over time.
- All charts must have accessible audio graph / text summaries (`accessibilityChartDescriptor`).

### 8.8 History
- Reverse-chronological session list grouped by day. Tap → full session detail; edit everything; delete.

### 8.9 Live Activity + Dynamic Island
- Shows instrument, current item, total elapsed (`Text(timerInterval:)` — no updates needed for the clock).
- Buttons (App Intents, iOS 17+ interactive Live Activities): Pause/Resume, Next item (cycles recent items), Finish (opens app to finish sheet).
- Update the activity only on state change (segment switch, pause), never every second.

### 8.10 Widgets (WidgetKit)
- Small: today's minutes + goal ring. Medium: + streak + this week's bars.
- Interactive "Start practice" button (App Intent).
- Lock Screen widgets (circular ring, inline "24 min today · 🔥 12").
- Control Center control (iOS 18+): Start/Stop practice.

### 8.11 Siri / Shortcuts (App Intents)
Implement as `AppIntent`s and expose via `AppShortcutsProvider`:
- `StartPracticeIntent(instrument?, item?)`
- `SwitchItemIntent(item)`
- `PausePracticeIntent`, `ResumePracticeIntent`, `FinishPracticeIntent`
- `LogPracticeIntent(minutes, item?, instrument?, date?)` — e.g. "Log 20 minutes of scales in Ostinato"
- `GetPracticeSummaryIntent(range)` → returns spoken/text summary ("You practiced 3 h 20 min this week")
- Make `PracticeItem` and `Instrument` `AppEntity`s with `EntityQuery` so Siri/Spotlight can resolve them by name.
- iOS 27: adopt the new App Intents capabilities (schemas / on-screen content) where they fit — **verify in docs first**.

### 8.12 Metronome (built in, simple but sample-accurate)
- `AVAudioEngine` with scheduled buffers (sample-accurate; no `Timer`-based clicks).
- 20–300 BPM, tap tempo, time signatures (2/4–12/8, custom), accent first beat, subdivisions (8ths, triplets, 16ths), volume.
- Keeps running when the app is backgrounded (audio background mode) and alongside the session timer.
- "Save tempo to current item" → creates `TempoEntry`.
- Compact overlay in active session + full-screen mode.

### 8.13 Recording
- Record from active session (attaches to session + current segment/item + timestamp).
- AAC m4a mono 64 kbps. Show level meter and elapsed time.
- Playback with scrubbing; playback speed 0.5×–1.0× (pitch-preserved via `AVAudioUnitTimePitch`) is nice-to-have for v1.
- Share via share sheet (e.g., to a teacher).
- Settings show total recording storage used; option to delete recordings older than N days.

### 8.13b Tuner (v1.0 — decided)
- Chromatic tuner using on-device pitch detection (YIN or autocorrelation) on an `AVAudioEngine` input tap. Target accuracy ±1 cent for sustained tones; stable, non-jittery needle (smooth with a short median/low-pass filter).
- Reference A4 adjustable **415–466 Hz** (default 440; baroque players use 415).
- Shows note name + octave + cents, **respecting the instrument's transposition** (a B♭ clarinet playing concert B♭ shows "C"). Toggle to show concert pitch.
- Optional string-by-string mode for guitar family / bowed strings using standard tunings (custom tunings nice-to-have).
- Available as a full screen and as a compact panel inside the active session. Hidden for instruments without pitch (drum kit, theory, etc.).
- Mic permission requested on first use with a clear explanation. Audio is processed live and never stored.

### 8.13c Drone (v1.0 — decided)
- Sustained tone on **any of the 12 notes**, octave selector, volume, waveform/timbre (sine, soft organ-like, cello-like) — users explicitly asked for drones in more keys.
- Optional fifth (root + 5th) and root + 5th + octave.
- Respects A4 reference and instrument transposition (toggle concert/written pitch).
- Generated with `AVAudioSourceNode` (no audio files needed), smooth fade-in/out (no clicks), keeps playing in background and alongside the session timer and metronome (mix both).

### 8.14 Reminders
- Optional daily local notification at chosen time; skipped automatically if goal already met that day.
- Gentle copy, never guilt-trippy. Max one per day.

### 8.15 Export / import / backup
- Export **CSV** (one row per segment: date, start, end, minutes, instrument, item, category, session rating, focus, tags, notes) — teachers use this.
- Export **JSON** full backup (all entities, recordings optional as a zip).
- Import JSON backup (merge by UUID; never duplicate).
- "Weekly report" shareable image/PDF: minutes per day, per item, notes — for sending to a teacher.

### 8.16 Settings
- Instruments (add/edit/reorder/archive), goals, reminders, keep-screen-awake, metronome/tuner defaults (A4 reference).
- **iCloud section (required toggles):**
  - **"Sync with iCloud"** (master toggle, default **on** when the user is signed in to iCloud). Controls syncing of all journal data (sessions, items, instruments, notes, goals).
    - Implementation: build the SwiftData `ModelContainer` with `cloudKitDatabase: .private(...)` when on and `.none` when off. Changing it rebuilds the container at the app root (or asks for a relaunch if a session is active). Local data is **never deleted** when turning sync off; turning it back on merges by UUID.
    - Explain clearly: "Uses your own iCloud. We never see your data."
  - **"Sync recordings to iCloud"** (sub-toggle, default **on**, disabled when master toggle is off). Moves audio files between local storage and the iCloud Drive container (see "Recording storage" in section 6). Show iCloud storage used by recordings.
  - Status line: "Up to date", "Syncing…", "iCloud unavailable — signed out", "iCloud storage full". Never block the app on sync.
  - If the user isn't signed in to iCloud, both toggles are disabled with a short explanation; the app works fully offline.
- The watch always syncs through the iPhone (section 9), independent of these toggles.
- Export / import, storage usage, **Delete all data** (double confirmation).
- About: version, "No accounts. No tracking. Your data stays on your devices and your iCloud.", link to privacy policy (static page; can be a GitHub Pages / simple hosted text — no backend).

---

## 9. Apple Watch app (v1.0 — required, it's a differentiator)

### Features
- **Start** practice (instrument picker if > 1; defaults to last used).
- Active screen: big elapsed time, current item name, **Next item** (Digital Crown scrolls a list of recent/active-repertoire items), Pause/Resume, Finish (with quick 1–5 rating via crown).
- Optional **interval haptics**: tap every N minutes (e.g., 10 min) to prompt switching.
- Complications / Smart Stack widget: today's minutes vs goal, streak; tap to start.
- Works when the phone is not nearby; syncs when it reconnects.

### Sync design (keep it simple and reliable)
- The **iPhone is the source of truth** for the SwiftData store.
- Watch → phone: completed or in-progress sessions sent with `WCSession.transferUserInfo` (queued, guaranteed delivery). Watch keeps a small local queue until the phone acknowledges.
- Phone → watch: instruments + active repertoire list + goal + today's totals via `updateApplicationContext` (latest-state-wins).
- Live state (session currently active on the other device): `sendMessage` when reachable, falling back to application context.
- Do **not** run a separate CloudKit store on the watch in v1.

### Watch-specific tests
- Session recorded entirely offline on watch arrives on phone exactly once.
- Session started on phone can be switched/finished from watch and vice versa.

---

## 10. Smart features (v1.2, optional, all on-device)

> These must degrade gracefully. The app must be fully useful on devices that don't support them. Never show a broken or empty state — hide the feature or show a short "Not available on this device" note in Settings.

### 10.1 Recording analysis — Music Understanding framework (iOS 27, all supported devices)
- On-device analysis of a recording: **tempo/BPM, key, rhythm stability, loudness, structure** (per Apple's WWDC26 session 253; entry point `MusicUnderstandingSession` — **verify current API in docs**).
- UI: after recording, show "≈ 96 BPM · D minor · tempo stability: steady/drifting". Offer "Save 96 BPM to item" → `TempoEntry(source: .analysis)`.
- Item detail: tempo-over-time chart combining manual, metronome and analyzed tempos.
- Run analysis off the main thread, cache results in `Recording.analysisJSON`, allow cancel. Only analyze the types we display (reduces compute).

### 10.2 Weekly summary — Foundation Models framework (Apple Intelligence devices)
- Check `SystemLanguageModel.default.availability`; if unavailable, show a **rules-based summary** instead (always implement the fallback first).
- Never send raw logs. Pre-aggregate in `PracticeKit` into a compact struct (totals per item, per category, streak, rating/focus averages, notable notes truncated) — must fit comfortably within the ~4,096-token context.
- Use guided generation (`@Generable` struct) for output, e.g.:
  - `headline: String` ("Strong week on the Chaconne")
  - `observations: [String]` (max 3)
  - `suggestion: String` ("Scales dropped to 5% — add 10 min warm-up")
- Label clearly as generated on-device. Never present as teacher advice.


---

## 11. Design guidelines

- Follow current Apple HIG and system **Liquid Glass** styling by using standard SwiftUI components; don't fight the system look.
- **Glanceable from a music stand:** active-session timer ≥ 72pt, monospaced digits; primary buttons ≥ 60pt tall.
- Dark mode first-class (practice rooms, stage). Support tinted/clear icons.
- Instrument color used as accent throughout a session.
- Haptics on start/switch/finish.
- No streak guilt: streak freezes / "rest days" built in (days-per-week goal, not daily-or-fail).
- Empty states teach the app ("Add the pieces you're working on to track time per piece").
- iPad: two-column layout (sidebar + detail); stats and repertoire benefit from width. Support Stage Manager / multiple windows minimally (no crash, sensible layout).

### Accessibility (required)
- All controls labeled for VoiceOver; timers read as "12 minutes 30 seconds".
- Dynamic Type up to AX5 without truncating critical info.
- Respect Reduce Motion and Increase Contrast.
- Don't rely on color alone for status.

### Localization
- Use String Catalogs from day one. Ship English; structure must allow adding languages without code changes. Use `Duration`/`Date` formatters, never hand-formatted strings.

---

## 12. Privacy, permissions & App Store compliance

- **No network calls** other than CloudKit (handled by the system). No third-party SDKs.
- App Store privacy label: **Data Not Collected**.
- `PrivacyInfo.xcprivacy` in every target: declare required-reason APIs actually used (e.g., `UserDefaults` → `CA92.1`; file timestamp APIs if used). Tracking = false. No tracking domains.
- Permissions (with clear usage strings):
  - Microphone — "Used to record your practice and, if you choose, analyze tempo. Recordings never leave your devices except through your own iCloud."
  - Notifications — only when the user enables reminders.
- No account → no account-deletion requirement, but provide "Delete all data".
- Age rating: 4+ (complete the updated age-rating questionnaire).
- **Guideline 4.3 (spam / undifferentiated apps):** our differentiation is segmented sessions, the Watch app, Live Activity/Siri integration — make these prominent in screenshots and review notes.
- **Guideline 2.3 (accurate metadata):** screenshots must show real app UI; no pricing claims in images.
- Background modes: `audio` (metronome/recording only). Do not abuse background modes for the timer — the timer doesn't need them.
- Privacy policy URL: static page stating no data is collected.

---

## 13. Milestones (build in this order; each ends in a runnable, tested build)

| # | Milestone | Done when |
|---|---|---|
| M0 | Project setup | Targets (app, watch, widgets), App Group, CloudKit container, `PracticeKit` package, CI-able test scheme, privacy manifests |
| M1 | Data model + session engine | All models; `SessionEngine` with full unit tests (section 7) passing |
| M2 | Core session flow | Start → switch items → pause → finish sheet → saved; manual log; restore-after-kill works |
| M3 | Repertoire + history | CRUD items/instruments, item detail with per-item totals, session history + edit |
| M4 | Stats | All charts in 8.7, streak/goal logic unit-tested (timezone/DST cases) |
| M5 | Metronome, recording, tuner, drone | Sample-accurate metronome; recording attached to segment; playback; tuner (±1 cent, transposition-aware); drone in all 12 keys; metronome + drone mix; interruptions handled |
| M6 | System integration | Live Activity, widgets, Control Center control, App Intents/Siri shortcuts |
| M7 | Apple Watch | Watch app + complications + WatchConnectivity sync with tests in section 9 |
| M8 | Export, settings, reminders, onboarding | CSV/JSON export & import, weekly report, delete-all, reminders |
| M9 | Polish & compliance | Accessibility audit, iPad layout, empty states, App Store assets, privacy label, review notes |
| — | **Ship v1.0** | |
| v1.1 | Playback speed control, custom tunings, final custom instrument symbols (if not done) | |
| v1.2 | Music Understanding analysis + on-device AI weekly summary | Gated, with fallbacks |
| v2 | Mac app, teacher-friendly shared reports (export only, no server) | |

---

## 14. Testing requirements

- **Unit (Swift Testing) in `PracticeKit`:** session engine, segment math, streaks & goals (timezones, DST, midnight), stats aggregation, CSV/JSON round-trip, import merge-by-UUID (no duplicates), watch-session merge logic, AI-summary input aggregation stays under a token budget (estimate ~4 chars/token, keep < 2,000 tokens).
- **UI tests:** onboarding skip, full session flow, manual log, edit session, export.
- **Performance:** seed 10,000 sessions / 50,000 segments; stats screen loads < 500 ms on an iPhone 13-class device; scrolling history is smooth.
- **Manual test checklist:** background 30 min then return; force-quit mid-session; phone call during recording; airplane mode on watch; iCloud signed out; two devices editing the same item.
- Run all tests after every milestone; do not proceed with failing tests.

---

## 15. Definition of done (v1.0)

- [ ] All v1.0 features in section 8 and 9 implemented and tested.
- [ ] No third-party dependencies; no network calls except CloudKit.
- [ ] Timer verified accurate across background/kill/interruption scenarios.
- [ ] Watch ↔ phone sync verified with no duplicate or lost sessions.
- [ ] VoiceOver walkthrough of every screen passes; Dynamic Type AX5 usable.
- [ ] Privacy manifests complete; privacy label = Data Not Collected.
- [ ] App icon, launch experience, App Store screenshots (iPhone, iPad, Watch), description, keywords, review notes drafted.
- [ ] Zero crashes in a 1-week personal dogfood period.

---

## 16. Owner decisions

| # | Decision | Status |
|---|---|---|
| 1 | **App name** | **Decided: Ostinato.** App Store name "Ostinato: Music Practice Log". Shortlist kept below for reference. |
| 2 | Minimum OS | **Decided: iOS/iPadOS 27, watchOS 27.** Reason: iOS 27 runs on the same iPhones as iOS 26 (iPhone 11 and later), most users will be on it by the time we ship, and it removes `#available` branches for Music Understanding and new App Intents features. ⚠️ Confirm the watchOS 27 device list in Apple's docs at project setup; if it drops watches many musicians still use, drop the watch target to watchOS 26. |
| 3 | iCloud sync | **Decided:** Settings toggles for "Sync with iCloud" (all data) and "Sync recordings to iCloud" (audio files). Details in 8.16 and section 6. |
| 4 | Instrument presets & icons | **Decided (by spec author, owner may revise):** preset list and monoline custom SF Symbol style in 8.0. |
| 5 | Tuner & drone | **Decided: included in v1.0** (8.13b, 8.13c, milestone M5). |

### Name shortlist (checked against US App Store search on 2026-11-23)

| Name | App Store collisions found | Notes |
|---|---|---|
| **Ostinato** ⭐ | None | A repeated musical pattern — fits daily practice. Distinctive, musician-friendly. |
| **Opus Log** | None | "Opus" = a musical work; clear what the app does. |
| **Practicely** | None | Plain-English, easy to remember and search for. |
| **Encore** | None as "Encore Practice" | Positive, well known; "Encore" alone may be crowded — use with a subtitle. |
| **Fermata** | 2 tiny music apps (≤ 5 ratings) | Nice word, but small collision risk. |

Rejected: Woodshed (several music apps already use it), Etude (piano app), Cadenza (metronome/tuner app), Tempo (Tempo metronome app, 4.9k ratings), Rubato, Practice Room.

- App Store listing format: **"<Name>: Music Practice Log"** — the subtitle carries search keywords (practice journal, timer, tuner, metronome).
- Before committing: reserve the name in App Store Connect (only that confirms availability) and do a quick trademark search (USPTO / EUIPO) in class 9 (software).
