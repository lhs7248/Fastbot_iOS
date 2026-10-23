#!/bin/sh
set -eu
ROOT=$(CDPATH= cd -- "$(dirname "$0")/../.." && pwd)
BIN=$(mktemp /tmp/fastbot-guard.XXXXXX)
trap 'rm -f "$BIN"' EXIT
clang -fobjc-arc -framework Foundation -I "$ROOT/Fastbot-iOS/SourceEngine" "$ROOT/tools/source-guard/test.m" "$ROOT/Fastbot-iOS/SourceEngine/FBExplorationGuard.m" -o "$BIN"
"$BIN"
