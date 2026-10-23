#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/../.."
CORE="$PWD/Fastbot-iOS/SourceEngine/core"
BUILD="${TMPDIR:-/tmp}/fastbot-source-engine-${UID}"
mkdir -p "$BUILD"
RUN="$(mktemp -d "$BUILD/run.XXXXXX")"
mkdir -p "$RUN/isolated"
INCLUDES=(-I"$CORE")
for dir in agent desc desc/reuse model events storage thirdpart thirdpart/json thirdpart/tinyxml2; do INCLUDES+=(-I"$CORE/$dir"); done
SOURCES=("$CORE/Base.cpp" "$CORE/PortableEngine.cpp" "$CORE"/agent/*.cpp "$CORE"/desc/*.cpp "$CORE"/desc/reuse/*.cpp "$CORE"/model/*.cpp "$CORE"/events/*.cpp "$CORE/thirdpart/tinyxml2/tinyxml2.cpp")
clang++ -std=c++14 -Wno-deprecated-literal-operator -Wno-format -Wno-deprecated-declarations "${INCLUDES[@]}" "${SOURCES[@]}" tools/source-engine/engine_test.cpp -o "$BUILD/engine_test"
"$BUILD/engine_test" "$RUN" > "$BUILD/test.log" 2>&1
 tail -1 "$BUILD/test.log"

if [[ "${1:-}" == "--ios" ]]; then
 SDK="$(xcrun --sdk iphoneos --show-sdk-path)"
 mkdir -p "$BUILD/ios"
 OBJECTS=()
 for source in "${SOURCES[@]}"; do
  name="${source#$CORE/}"; name="${name//\//_}"; object="$BUILD/ios/$name.o"
  xcrun --sdk iphoneos clang++ -std=c++14 -arch arm64 -isysroot "$SDK" -miphoneos-version-min=13.0 -Wno-deprecated-literal-operator -Wno-format "${INCLUDES[@]}" -c "$source" -o "$object"
  OBJECTS+=("$object")
 done
 xcrun --sdk iphoneos clang++ -std=c++14 -arch arm64 -isysroot "$SDK" -miphoneos-version-min=13.0 -fobjc-arc "${INCLUDES[@]}" -c Fastbot-iOS/SourceEngine/FBSourceEngine.mm -o "$BUILD/ios/FBSourceEngine.o"
 xcrun libtool -static -o "$BUILD/libFBSourceEngine-arm64.a" "${OBJECTS[@]}" "$BUILD/ios/FBSourceEngine.o"
 file "$BUILD/libFBSourceEngine-arm64.a"
fi
