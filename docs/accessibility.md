# Accessibility audit

`UITests/AccessibilityAuditTests.swift` runs `performAccessibilityAudit()` on every
tab, the active session and the finish sheet, using `-demoData`.

**Fails the test:** hit areas under 44 pt, missing labels or descriptions,
wrong traits, undetectable elements, and clipped text (except system
navigation titles).

**Logged, verified by hand:**

| Audit type | Why it isn't automated | How it's checked |
|---|---|---|
| Contrast | The audit samples Liquid Glass buttons and rows under the floating tab bar incorrectly. It flags black text on light glass. | Screenshots in light and dark mode. Instrument colors come from a palette validated for lightness, chroma and colorblind separation. |
| Dynamic Type | Flags system toolbar buttons, navigation titles and Form footers that the app doesn't control. | Screenshots at AX5 (`xcrun simctl ui <id> content_size accessibility-extra-extra-extra-large`). Layouts switch to single columns at accessibility sizes. |

Fixes made from the first audit run:

- Tool buttons and item chips use primary text on glass instead of tinted text.
- "Paused" badge uses primary text with an orange icon.
- Stat tiles, the Today card and tool grids reflow at accessibility sizes instead
  of scaling text down.
- "Discard Session" has a 44 pt hit area.
- Running timers stop redrawing while paused.
