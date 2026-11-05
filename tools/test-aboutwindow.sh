#!/bin/bash
# Mac test of About This iPad's window against macOS's About This Mac (statusbar/AboutWindow.h, test-aboutwindow.c): size, places, colours, the iPad drawn.
set -e
cd "$(dirname "$0")"
W=$(mktemp -d); trap 'rm -rf "$W"' EXIT
clang -Wall -Wextra -Wno-unused-function -o "$W/taw" test-aboutwindow.c
"$W/taw"
