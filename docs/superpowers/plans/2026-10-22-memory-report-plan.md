# iOS memory collection and report implementation plan

Goal: extend the approved default Fastbot workflow with read-only physical-footprint sampling, PID segments, quality assessment and an offline HTML report; do not modify the tested App.

Architecture: an independently owned collector streams Instruments process metrics through the installed pymobiledevice3 userspace transport, writes source JSONL and normalized samples, and is stopped with the same run. An offline report combines memory, existing JS monitor results, and Fastbot actions. Test outcome and collection quality are separate.

Constraints: Python 3.9 standard library; current pinned pymobiledevice3 11.40.2; default interval 5 seconds; bytes persisted and MiB displayed; no RSS substitution; no native crash claims without evidence; no interpolation across missing data or PID restart; no runtime artifacts/config in git.

- [x] Probe real iPhone metric names and transport. Read footprint=175179296 and resident=322338816 independently; userspace channel works without root.
- [x] Add failing collector tests for byte units, missing primary field, invalid values/PID, process generations, no stale repetition and missing samples.
- [x] Implement `tools/performance/collect.py` with CLI stream, target selection on each snapshot, bounded retries, graceful cleanup, samples and collector metadata.
- [x] Implement `tools/performance/report.py` and tests: quality, per-segment statistics, byte-preserving CSV, escaped SVG/HTML, separate issue outcomes and time-aligned timeline.
- [x] Extend `tools/run_fastbot.py` and tests with sample interval validation and owned collection lifecycle before/after monitoring; write final report on errors and interrupts.
- [x] Document schema, first-run configuration, exit codes and report regeneration.
- [x] Run all targeted tests, dry-run, then a complete real-device run with parallel Instruments/XCTest collection and inspect artifacts.
- [x] Independently review and repair significant issues; report results with residual limits. Do not push unless requested.

## Validation evidence

- Final targeted checks: collector, report, lifecycle and JS monitoring tests passed.
- Real iPhone 13 Pro, iOS 26.6.1: userspace Instruments + XCTest + syslog ran concurrently.
- Initial 2-second run: 37 valid samples, PID restart recorded, missing data preserved.
- Final default 5-second run: 12 valid / 17 expected samples, five missing records; test/log monitor completed with code0, memory quality incomplete and aggregate code6. HTML final metadata matches JSON.
- Real artifacts: `.fastbot/results/20261022-104740-dcb50f/`. Runtime data remain ignored.
- Growth thresholds are opt-in; no Android default is blindly applied to iOS. Native crash diagnostics remain explicitly unverified.
- Independent review repaired phase-based sample counting, source timestamp handling, PID generation timeline and cooperative shutdown budget.
- No tested-App source changes. No push performed for this task.
