#!/bin/bash
# test-updatecheck.sh -- builds and runs tools/test-updatecheck.m on the Mac (in a folder of its own: a fixed name in /tmp is shared with the
# iPad itself on an iPad's test lane).
W=$(mktemp -d "${TMPDIR:-/tmp}/msbd-updatecheck.XXXXXX"); trap 'rm -rf "$W"' EXIT
cd "$(dirname "$0")" && clang -fobjc-arc -framework Foundation -o "$W/t" test-updatecheck.m && "$W/t"
