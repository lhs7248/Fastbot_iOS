#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/../.."
CORE="$PWD/Fastbot-iOS/SourceEngine/core"
ADAPTER="$PWD/Fastbot-iOS/SourceEngine"
RUN="$(mktemp -d /tmp/fastbot-policy.XXXXXX)"
trap 'rm -rf "$RUN"' EXIT
INCLUDES=(-I"$ADAPTER" -I"$CORE")
for dir in agent desc desc/reuse model events storage thirdpart thirdpart/json thirdpart/tinyxml2; do INCLUDES+=(-I"$CORE/$dir"); done
SOURCES=("$CORE/Base.cpp" "$CORE/PortableEngine.cpp" "$CORE"/agent/*.cpp "$CORE"/desc/*.cpp "$CORE"/desc/reuse/*.cpp "$CORE"/model/*.cpp "$CORE"/events/*.cpp "$CORE/thirdpart/tinyxml2/tinyxml2.cpp")
for file in FBTreeAdapter FBExplorationGuard; do
 clang -fobjc-arc -I"$ADAPTER" -c "$ADAPTER/$file.m" -o "$RUN/$file.o"
done
clang++ -std=c++14 -fobjc-arc -framework Foundation -Wno-deprecated-literal-operator -Wno-format -Wno-deprecated-declarations "${INCLUDES[@]}" "${SOURCES[@]}" tools/source-engine/policy_test.mm "$RUN/FBTreeAdapter.o" "$RUN/FBExplorationGuard.o" -o "$RUN/policy_test"
if ! "$RUN/policy_test" "$RUN" "$@" > "$RUN/test.log" 2>&1; then tail -50 "$RUN/test.log";exit 1;fi
rg 'dense page candidates=|policy integration tests passed' "$RUN/test.log"
