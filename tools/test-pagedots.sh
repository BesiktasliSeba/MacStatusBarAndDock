#!/bin/bash
# Mac test of whose page dots Hide Page Dots hides (common/PageDotsOwner.h, test-pagedots.c): the Home Screen's, not iPadOS 18's Control Center's,
# and what -setHidden: stores when iPadOS shows them again (1.8.1).
set -e
cd "$(dirname "$0")"
W=$(mktemp -d); trap 'rm -rf "$W"' EXIT
clang -Wall -Wextra -Wno-unused-function -o "$W/tpd" test-pagedots.c
"$W/tpd"
