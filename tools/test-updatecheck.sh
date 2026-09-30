#!/bin/bash
# test-updatecheck.sh -- builds and runs tools/test-updatecheck.m on the Mac.
cd "$(dirname "$0")" && clang -fobjc-arc -framework Foundation -o /tmp/test-updatecheck test-updatecheck.m && /tmp/test-updatecheck
