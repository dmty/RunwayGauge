# Task 8 simplify (ponytail full)

**Commit:** `01e3e41` — `refactor: simplify manual usage refresh wiring`  
**Delta:** 4 files, −17 net (29+/46−)

- **HelperSetup** — inlined `runHelper`; `isHelperBinaryAvailable` guard
- **AppMain** — `refreshUsageNow()` reuses `setupOutput` + widget reload
- **SettingsView** — thin button; dropped local refresh state; Edit Widget hint kept
- **README** — shorter jq soft-dep + refresh/Edit Widget line

Tests: `test-helper-setup.sh`, `test-cap-output.sh` — pass
