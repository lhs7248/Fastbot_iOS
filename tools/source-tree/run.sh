#!/bin/sh
set -eu
ROOT=$(CDPATH= cd -- "$(dirname "$0")/../.." && pwd)
BIN=$(mktemp /tmp/fastbot-tree.XXXXXX)
trap 'rm -f "$BIN"' EXIT
clang -fobjc-arc -framework Foundation -I "$ROOT/Fastbot-iOS/SourceEngine" "$ROOT/tools/source-tree/test.m" "$ROOT/Fastbot-iOS/SourceEngine/FBTreeAdapter.m" -o "$BIN"
"$BIN"
