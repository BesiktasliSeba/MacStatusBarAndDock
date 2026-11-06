#!/bin/bash
# Mac test of when the Dock goes under our own on-screen keyboard (statusbar/KeyboardDock.h, test-kbdock.m): the frames iPadOS announced on the
# A12Z (18.5) and the iPad 2 (16), and the decision with the keyboard drawn in SpringBoard's keyboard windows.
set -e
cd "$(dirname "$0")"
W=$(mktemp -d); trap 'rm -rf "$W"' EXIT
clang -O2 -Wall -Wno-unused-function -framework CoreGraphics -o "$W/tkd" test-kbdock.m
"$W/tkd"
fails=0
check() { if eval "$2"; then echo "PASS  $1"; else echo "FAIL  $1"; fails=1; fi; }
check "1.8.2.2 A12Z F9 / code review 4: the Downloads panel reads a keyboard frame in the space that shows a keyboard -- across the bottom (only its part on the screen), else a floating one wider than tall -- (18.5's hardware keyboard bar comes in the interface's: read as the fixed space it was 342 pt above the screen; a floating keyboard sent in the fixed space must not be turned a quarter)" \
  "grep -qF 'CGRect k = MSBDKeyboardPanelFrame([window convertRect:end fromCoordinateSpace:scr.coordinateSpace], [window convertRect:end fromCoordinateSpace:scr.fixedCoordinateSpace], window.bounds.size);' ../dock/Downloads.m \
   && ! grep -qF 'CGRect k = [window convertRect:end fromCoordinateSpace:window.screen.fixedCoordinateSpace];' ../dock/Downloads.m && ! grep -q 'MSBDKeyboardNoteOnScreen' ../dock/Downloads.m \
   && grep -qF 'MSBDKeyboardNoteOnScreen(f, g, scr);' ../statusbar/Desktop.h && grep -qF 'return MSBDKeyboardNoteOnScreen(f, g, screen.bounds.size).size.height;' ../statusbar/StatusBar.x"
[ $fails = 0 ] && echo "test-kbdock: site checks pass" || { echo "test-kbdock: site checks FAILED"; exit 1; }
