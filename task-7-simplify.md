# Task 7 simplify (ponytail full)

**Commit:** `1999302` — `refactor: simplify widget display intent wiring`  
**Delta:** 6 files, −57 net lines (107+/164−)

## What changed

- **UsageTimeline.swift** — `UsageTimelineBuilder.plan()` static holds fallback; provider stays thin
- **WidgetMain.swift** — dropped private `plan()`; snapshot/timeline call builder static
- **ClaudeUsageView.swift** — inlined session-not-started check; shorter `fetchStatusLine`
- **Freshness.swift** — ternary evaluate body; optional `windows` kept
- **WidgetTests** — `makeBuilder`/`makeRecord` helpers; merged record fixtures

## Constraints preserved

- `AppIntentConfiguration` + `UsageDisplayIntent.asOptions()` + all 7 display toggles
- Default session+week / local 80–95 look unchanged

## Tests

- `swift test` (UsageCore) — **137 passed**
- `xcodebuild test -scheme UsageWidgetTests` — **5 passed**
