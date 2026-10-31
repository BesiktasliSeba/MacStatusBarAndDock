#!/bin/bash
# Mac test of Settings > Pointer's Hide in Virtual Mac row (1.7.2 item 22): shown only on iPads that can run VirtualMac (kern.hv_support, M1/M2 up to
# 16.3.1), with the same check as About This iPad (common/Hypervisor.h); the stored switch and the pointer's behaviour are left as they are.
set -e
cd "$(dirname "$0")"
W=$(mktemp -d); trap 'rm -rf "$W"' EXIT
printf '#include <stdio.h>\n#include "%s/../common/Hypervisor.h"\nint main(void) { int v = MSBDHypervisorCapable(); return v == 0 || v == 1 ? 0 : 1; }\n' "$PWD" > "$W/t.c"
clang -Wall -o "$W/t" "$W/t.c" && "$W/t" && echo "PASS  common/Hypervisor.h builds on its own and answers 0 or 1" || { echo "FAIL  common/Hypervisor.h"; exit 1; }
P=../macsettings/PointerSettings.x; S=../statusbar/StatusBar.x
fails=0
check() { if eval "$2"; then echo "PASS  $1"; else echo "FAIL  $1"; fails=1; fi; }
check "the check is the kernel's kern.hv_support == 1" \
  "grep -q 'sysctlbyname(\"kern.hv_support\", &hv, &len, NULL, 0) == 0 && hv == 1;' ../common/Hypervisor.h"
check "Settings adds Hide in Virtual Mac (and its footer group) only when MSBDHypervisorCapable()" \
  "awk '/if \\(MSBDHypervisorCapable\\(\\)\\) \\{/{f=1} f && /Virtual Mac draws its own pointer/{g=1} f && g && /Hide in Virtual Mac/{print \"ok\"; exit}' $P | grep -q ok && [ \$(grep -c 'Hide in Virtual Mac\" target' $P) = 1 ]"
check "  ... its stored switch is still read by SpringBoard as before (no change to the pointer's behaviour)" \
  "grep -q 'CFPreferencesCopyValue(CFSTR(\"macPointerHideInVirtualMac\")' $S"
check "About This iPad asks the same check (after its debug override)" \
  "awk '/^static BOOL DMHypervisorCapable\\(void\\) \\{/{f=1} f && /return MSBDHypervisorCapable\\(\\);/{print \"ok\"; exit}' $S | grep -q ok"
[ $fails = 0 ] && echo "test-hvrow: all checks pass" || { echo "test-hvrow: FAILED"; exit 1; }
