#!/bin/bash
# Mac test of the screenshot mode (common/ShotMode.h; KT 7 Nov, release-1.8.4.md item 5): in a debug build with the flag file there, About This iPad's
# serial number is a placeholder and Wi-Fi networks and Bluetooth devices go by neutral names; a release build never, and carries no trace of it.
cd "$(dirname "$0")" || exit 1
W=$(mktemp -d); trap 'rm -rf "$W"' EXIT
fails=0
F="$W/shotflag"
for dbg in 1 0; do
  clang -fobjc-arc -Wall -Wno-unused-function -DDEBUG=$dbg -DMSBD_SHOT_FLAG="\"$F\"" -framework Foundation -o "$W/tsm$dbg" test-shotmode.m || { fails=1; continue; }
  rm -f "$F"; "$W/tsm$dbg" || fails=1
  touch "$F"; "$W/tsm$dbg" flag || fails=1
done
rm -f "$F"
S=../statusbar/StatusBar.x; WM=../statusbar/WiFiMenu.h; C=../statusbar/CCTiles.h; H=../common/ShotMode.h
check() { if eval "$2"; then echo "PASS  $1"; else echo "FAIL  $1"; fails=1; fi; }
check "About This iPad's serial number row goes through the screenshot mode" \
  "grep -q '#import \"../common/ShotMode.h\"' $S && grep -q '{@\"Serial number\", MSBDShotSerial(DMMG(@\"SerialNumber\"))},' $S"
check "  ... and the Wi-Fi menu's networks, its password sheet, our Control Center's Wi-Fi line and its Bluetooth devices" \
  "grep -q 'self = \[super initWithTitle:MSBDShotWiFiName(name) enabled:YES handler:handler\];' $WM && grep -q 't.text = MSBDShotWiFiName(sh.ssid);' $WM \
   && grep -q 'w.line.text = wl == 2 ? MSBDShotWiFiName(net) :' $C && grep -q '? MSBDShotBTName(n) : @\"Unnamed Device\"; }' $C"
check "debug builds only: the flag's path is defined between #if DEBUG and #else, nowhere else outside a comment; a release gets the plain values" \
  "l=\$(grep -n '^#define MSBD_SHOT_FLAG \"/tmp/msb-shotmode\"' $H | cut -d: -f1); a=\$(grep -n '^#if DEBUG' $H | head -1 | cut -d: -f1); b=\$(grep -n '^#else' $H | tail -1 | cut -d: -f1); \
   [ -n \"\$l\" ] && [ \"\$a\" -lt \"\$l\" ] && [ \"\$l\" -lt \"\$b\" ] && [ \$(grep -v '^//' $H | grep -c 'msb-shotmode') = 1 ] && grep -q 'static inline BOOL MSBDShotMode(void) { return NO; }' $H"
check "verify-release counts the flag's name as test machinery in a release build" "grep -q \"^PAT='msb-shotmode|\" verify-release.sh"
check "no em dash" "! grep -q \$'\\xe2\\x80\\x94' $H test-shotmode.m test-shotmode.sh"
[ $fails = 0 ] && echo "test-shotmode: all checks pass" || { echo "test-shotmode: checks FAILED"; exit 1; }
