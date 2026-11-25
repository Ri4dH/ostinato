# App Review notes

Ostinato is a practice journal for musicians. No account or sign-in is needed;
all features are available immediately and free. There are no in-app purchases.

## How to try the main features

1. Skip or complete onboarding (pick an instrument, e.g. Violin).
2. Repertoire tab → + → add a piece (e.g. "Scales") and another item.
3. Practice tab → Start Practice. Tap an item in "Working on" to switch; the
   lower timer shows time on the current item.
4. Lock the device to see the Live Activity with Pause and Next.
5. Tap Finish to review time per item, rate the session, and Save.
6. Stats and History show the result.

Apple Watch: open Ostinato on the paired watch and tap Start. Sessions recorded
on the watch appear on iPhone after it reconnects.

## Permissions

- **Microphone**: only requested when the user taps Record or opens the Tuner.
  Tuner audio is analyzed live and never stored. Recordings stay on the device
  or in the user's own iCloud Drive.
- **Notifications**: only requested when the user turns on daily reminders or
  watch interval taps.

## Background modes

- `audio`: the metronome, drone and recording keep playing when the app is in
  the background, which musicians need while reading from a stand. The session
  timer itself doesn't use background time; it is computed from timestamps.
- `remote-notification`: required by CloudKit to sync the user's private database.

## Data and privacy

No data is collected. There are no third-party SDKs and no network requests
other than the user's private iCloud (CloudKit and iCloud Drive), which can be
turned off in Settings → iCloud. Settings → Your Data → Delete All Data removes
everything.

## How Ostinato differs from other practice apps (Guideline 4.3)

- Time is tracked per piece within a session, with per-piece statistics.
- A full Apple Watch app that works offline.
- Live Activity, interactive widgets, Control Center control and App Intents.
- Built-in metronome, tuner, drone and on-device recording analysis, all free.
