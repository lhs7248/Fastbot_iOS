# Source iOS Explorer Implementation Plan

> For agentic workers: use subagent-driven-development for engine implementation and independent review.

**Goal:** Build and validate a source-only XCTest runner using the Android ModelReusableAgent C++ implementation, without linking the three original frameworks.

**Architecture:** Vendor a pinned internal-use copy of the Android native core, exclude JNI and FlatBuffers compiler tools, expose a narrow Objective-C++ bridge. XCTest snapshots become Android-compatible XML. Execution maps returned bounds to fresh hittable elements and rejects unsupported actions. Existing Python collection/report workflow remains usable.

**Tech Stack:** C++14, Objective-C++, XCTest, local CocoaPods subspec, Python unittest.

## Global constraints
Preserve upstream license/copyright; internal use only; no push. Do not claim binary equivalence to NStepQAgent. No target App modifications or SDK injection. No root/jailbreak. Retain legacy build path only as explicit opt-in. Never use coordinates from an obsolete snapshot without revalidation. Do not treat every hittable node as clickable. Do not claim UIViewController or business coverage from accessibility states. Keep source and legacy artifacts in separate build caches.

## Task 1 — portable C++ engine
- [x] Vendor native sources and license with upstream commit and SHA manifest.
- [x] Add a host test that feeds valid UI XML, validates operation JSON, exercises sequential transitions, rejects malformed XML and tests isolated persistence paths. Observe test fail before bridge implementation.
- [x] Implement create/next/reset/close boundary, exclude JNI and unsupported Android mutation. Use explicit per-run sandbox storage; no detached model writer; save at controlled teardown.
- [x] Compile host tests and iOS arm64 static archive with SDK clang. Preserve algorithm, document portability patches.

## Task 2 — source XCTest explorer
- [x] Add tests for snapshot normalization, secure text redaction, editable/clickable/scrollable mapping, stable page keys, offscreen/disabled exclusion, action target rejection and no-target behavior.
- [x] Implement snapshot adapter and source explorer, run existing deadline/throttle settings, permission monitor, fresh element execution, supported action allowlist, bounded no-action recovery, explicit audit logs.
- [x] Source pod subspec compiles local core and Objective-C++; source Runner imports no old headers. Build source runner by default, preserve explicit legacy runner/subspec in separate cache.

## Task 3 — integration and verification
- [x] Extend CLI tests for engine selection, dry-run and separate caches. Run existing 48 Python tests and new host tests.
- [x] Build/sign source Runner; inspect linked images and embedded Frameworks to prove old Fastbot binaries absent.
- [x] If device ready, run bounded smoke and record real snapshot/action outcomes. Otherwise explicitly report hardware verification outstanding.
- [x] Add internal-use build/run guide and update report metadata to identify engine and tree source. Independent review before final result.

## Completed evidence

Final signed source build and 1-minute device integration: `.fastbot/results/20261023-113023-91c78d`. XCTest exit0; 38 dispatched operations,1 rejected BACK,3 internal graph states. JS monitor exit0; memory incompleteness yields aggregate6. Host adapter/engine tests and Python tests pass. Original frameworks absent from linked images and embedded payload. Review identified disabled-editable overrides and clipped-frame validation; regressions added and fixes re-reviewed. User did not request publication; no commit/push.
