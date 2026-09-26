#!/usr/bin/env python3
# make-crash-fixture.py -- writes a synthetic SpringBoard crash report (.ips, iOS 15/16 layout: header line + JSON body) whose crash sits at a
# chosen place in one of our parts. For the Mac tests of the crash guard's step 1b (tools/test-crashstep.sh) and for device tests (copied to
# /tmp/msb-fakecrash-report on a test build, see common/CrashGuard.h). No real data: every value is made up.
#
#   make-crash-fixture.py <out.ips> <Image> <uuid> <offset hex> [--exception] [--loader]
#   make-crash-fixture.py <out.ips> --map <CrashMap.txt> <Image> <arch> <target> [--exception]
#        the first function range of <target> in <Image>'s <arch> slice of a built map (e.g. MacStatusBarCore arm64e macBanners)
#   make-crash-fixture.py <out.ips> --symbol <dSYM DWARF file> <Image> <regex> [--exception]
#        inside the first function whose name matches <regex> (the UUID is the dSYM's, i.e. the build's)
# --exception: the crash is an uncaught exception: our frame is in the last exception backtrace (the faulting thread only has Apple's abort).
# --loader: our frame is in the loader (MacStatusBar.dylib), which the guard cannot turn off on its own.
import json, re, subprocess, sys

def pick_from_map(path, image, arch, target):
    uuid, inblock, prev = None, False, None
    for line in open(path):
        f = line.split()
        if not f:
            continue
        if f[0] == 'U':
            if inblock:
                break
            inblock = f[1] == image and f[3] == arch
            if inblock:
                uuid = f[2]
        elif f[0] == 'R' and inblock:
            start = int(f[1], 16)
            if prev and prev[1] == target and start - prev[0] >= 8:
                return uuid, prev[0] + 4
            prev = (start, f[2])
    sys.exit('fixture: no %s range in %s %s' % (target, image, arch))

def pick_from_symbol(dsym, regex):
    out = subprocess.run(['dwarfdump', '--uuid', dsym], check=True, capture_output=True, text=True).stdout
    uuid = re.search(r'UUID: ([0-9A-Fa-f-]+)', out).group(1).lower()
    syms = subprocess.run(['nm', '-n', '-s', '__TEXT', '__text', dsym], check=True, capture_output=True, text=True).stdout.splitlines()
    for i, l in enumerate(syms):
        m = re.match(r'([0-9a-f]{16}) [tT] (.*)', l)
        if m and re.search(regex, m.group(2)):
            return uuid, int(m.group(1), 16) + 4, m.group(2)
    sys.exit('fixture: no symbol matching ' + regex)

def main():
    a = sys.argv[1:]
    exc = '--exception' in a; loader = '--loader' in a
    a = [x for x in a if x not in ('--exception', '--loader')]
    out = a[0]; note = ''
    if a[1] == '--map':
        image = a[3]; uuid, offset = pick_from_map(a[2], image, a[4], a[5]); note = 'map target ' + a[5]
    elif a[1] == '--symbol':
        image = a[3]; uuid, offset, sym = pick_from_symbol(a[2], a[4]); note = 'symbol ' + sym
    else:
        image, uuid, offset = a[1], a[2].lower(), int(a[3], 16)
    images = [
        {"source": "P", "arch": "arm64e", "base": 4294967296, "size": 16384, "uuid": "00000000-0000-0000-0000-00000000aaaa",
         "path": "/System/Library/CoreServices/SpringBoard.app/SpringBoard", "name": "SpringBoard"},
        {"source": "P", "arch": "arm64e", "base": 6000000000, "size": 200000, "uuid": "00000000-0000-0000-0000-00000000bbbb",
         "path": "/usr/lib/system/libsystem_kernel.dylib", "name": "libsystem_kernel.dylib"},
        {"source": "P", "arch": "arm64e", "base": 7000000000, "size": 4000000, "uuid": uuid,
         "path": "/private/preboot/SYNTHETIC/jb-SYNTHETIC/procursus/usr/lib/MacStatusBarAndDock/%s.dylib" % image, "name": image + ".dylib"},
        {"source": "P", "arch": "arm64e", "base": 6100000000, "size": 30000000, "uuid": "00000000-0000-0000-0000-00000000cccc",
         "path": "/System/Library/PrivateFrameworks/UIKitCore.framework/UIKitCore", "name": "UIKitCore"},
        {"source": "P", "arch": "arm64e", "base": 6200000000, "size": 5000000, "uuid": "00000000-0000-0000-0000-00000000dddd",
         "path": "/System/Library/Frameworks/CoreFoundation.framework/CoreFoundation", "name": "CoreFoundation"},
        {"source": "P", "arch": "arm64e", "base": 8000000000, "size": 100000, "uuid": "00000000-0000-0000-0000-00000000eeee",
         "path": "/private/preboot/SYNTHETIC/jb-SYNTHETIC/procursus/usr/lib/TweakInject/MacStatusBar.dylib", "name": "MacStatusBar.dylib"},
    ]
    ours = {"imageOffset": offset, "imageIndex": 5 if loader else 2}
    if exc:
        fault = [{"imageOffset": 1000, "symbol": "__pthread_kill", "imageIndex": 1}, {"imageOffset": 2000, "symbol": "objc_exception_rethrow", "imageIndex": 4}]
        backtrace = [{"imageOffset": 3000, "symbol": "__exceptionPreprocess", "imageIndex": 4}, ours, {"imageOffset": 4000, "imageIndex": 3}]
    else:
        fault = [ours, {"imageOffset": 4000, "imageIndex": 3}, {"imageOffset": 5000, "imageIndex": 0}]
        backtrace = None
    body = {"uptime": 100, "procRole": "Foreground", "incident": "SYNTHETIC-TEST-FIXTURE", "note": note,
            "exception": {"type": "EXC_CRASH" if exc else "EXC_BAD_ACCESS", "signal": "SIGABRT" if exc else "SIGSEGV"},
            "faultingThread": 1,
            "threads": [{"id": 1, "frames": [{"imageOffset": 1234, "symbol": "mach_msg_trap", "imageIndex": 1}]},
                        {"id": 2, "triggered": True, "queue": "com.apple.main-thread", "frames": fault}],
            "usedImages": images}
    if backtrace:
        body["lastExceptionBacktrace"] = backtrace
        body["asi"] = {"CoreFoundation": ["*** Terminating app due to uncaught exception 'NSInvalidArgumentException', reason: 'synthetic test'"]}
    header = {"app_name": "SpringBoard", "timestamp": "2026-09-26 10:00:00.00 +0200", "bug_type": "309", "os_version": "iPhone OS 16.5 (20F66)",
              "incident_id": "SYNTHETIC-TEST-FIXTURE", "name": "SpringBoard", "bundleID": "com.apple.springboard"}
    with open(out, 'w') as f:
        f.write(json.dumps(header) + '\n' + json.dumps(body, indent=1) + '\n')
    print('%s: %s+0x%x uuid %s%s' % (out, image, offset, uuid, (' (' + note + ')') if note else ''))

main()
