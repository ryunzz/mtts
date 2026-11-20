#!/usr/bin/env bash
# Runs the test suite. With only the Command Line Tools installed (no Xcode), SwiftPM
# doesn't find the Swift Testing framework on its own, so point it there.
set -euo pipefail
cd "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

DEV_DIR="$(xcode-select -p 2>/dev/null || true)"
FRAMEWORKS="$DEV_DIR/Library/Developer/Frameworks"
LIBS="$DEV_DIR/Library/Developer/usr/lib"

if [[ "$DEV_DIR" == *CommandLineTools* && -d "$FRAMEWORKS/Testing.framework" ]]; then
  exec swift test \
    -Xswiftc -F -Xswiftc "$FRAMEWORKS" \
    -Xlinker -F -Xlinker "$FRAMEWORKS" \
    -Xlinker -rpath -Xlinker "$FRAMEWORKS" \
    -Xlinker -rpath -Xlinker "$LIBS" \
    "$@"
fi
exec swift test "$@"
