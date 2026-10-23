# Internal-use Fastbot source core

Upstream: local sibling Fastbot_Android, https://github.com/bytedance/Fastbot_Android
Pinned commit: d057b99115caf0c315d2b3bd6950326f3a51045c.

This is the actual native ModelReusableAgent engine, not an implementation of the unavailable iOS NStepQAgent binary. The upstream Fastbot Revised License is preserved in LICENSE.txt. It permits internal use only and prohibits third-party distribution. Do not publish this source copy or resulting binaries.

UPSTREAM_SHA256.json records SHA-256 hashes of the original files before portability changes. JNI/project files, upstream build configuration, flatc executable and all FlatBuffers compiler implementation .cpp files are excluded. Header-only FlatBuffers runtime, TinyXML2 and JSON code retain their original notices.

Portability changes:

- PortableEngine provides explicit create/next/reset/close and isolated graph instances. All engine operations are serialized because upstream has static XML parser state, a preference singleton and C RNG. Caller seed drives each operation; upstream time-based reseeding in selection is disabled. No binary-equivalence claim is made.
- AgentFactory does not start its periodic thread. Agent destructors do not write files. The only active write is synchronous close to the caller's existing absolute storage directory, reuse.fbm. No implicit /sdcard or current-working-directory output. This first version starts a fresh graph/model each run; it writes learned reuse transitions for inspection, but deliberately does not load unverified FlatBuffers from disk.
- Android preference config loading and input fuzzing are disabled. The public boundary exposes no preference, custom action, shell or mutation APIs. Returned actions are restricted to CLICK, LONG_CLICK, BACK, the four cardinal SCROLL actions and NOP. Other selections become NOP; output disables fuzzing and removes custom action payloads.
- The iOS XML path preserves explicit clickable and scrollable attributes. Upstream's fallback making every node clickable and forcing root scrollability is disabled. Editable nodes and clickable parents cannot override explicit clickable/enabled flags; password nodes do not request text input. Disabled nodes generate no widget actions (upstream unvisited-action selection can bypass enabled filtering). The legacy string parser's unnecessary XML logging loop was removed.
- XML is parsed and checked before mutating graph state; malformed/empty XML, embedded NUL and missing page keys throw and become NSError at the Objective-C++ boundary.

Host verification: tools/source-engine/build-test.sh. Add --ios to compile every selected translation unit and the Objective-C++ bridge for iOS arm64 and produce a static archive under the temporary build directory. It requires Xcode's iPhoneOS SDK. The host test verifies sequential graph transitions, real click selection and bounds, operation JSON, malformed-input rejection before state changes, isolated instances, explicit persistence and idempotent close.

Per-call ineffective-action exclusions: the bridge overload accepts dictionaries with act and four integer pos bounds (BACK only needs act). PortableEngine validates records before mutating the graph. Model applies a predicate to fresh resolved candidates before the reusable agent selects, temporarily swapping the canonical state's action vector under an RAII restore guard. Direct unvisited BACK fallback requires membership in that candidate vector. All excluded candidates produce NOP with reason=no_available_action; canonical candidates are restored and snapshot details cleared on that early exit, so subsequent calls can restore eligibility and refresh bounds. Exclusions are never persisted into the state cache.

Merged-peer exclusions search every fresh peer, including the retained representative, and pin an eligible target through selection dispatch. Cache refill rebuilds the peer map and rebinds cached actions to fresh representatives on every snapshot. The boundary predicate also requires an enabled current XML node with matching bounds and action capability; Model rechecks that predicate after resolveNewAction before strategy update, preventing stale cached targets from escaping through selection.
