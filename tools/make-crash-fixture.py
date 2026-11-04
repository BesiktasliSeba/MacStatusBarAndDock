#!/usr/bin/env python3
# make-crash-fixture.py -- writes a synthetic SpringBoard crash report (.ips, iOS 15/16 layout: header line + JSON body) whose crash sits at a
# chosen place in one of our parts. For the Mac tests of the crash guard's step 1b (tools/test-crashstep.sh) and for device tests (copied to
# /tmp/msb-fakecrash-report on a test build, see common/CrashGuard.h). No real data: every value is made up.
#
#   make-crash-fixture.py <out.ips> <Image> <uuid> <offset hex>[,<offset hex>...] [--exception] [--loader] [--apple-top]
#        several offsets: as many frames of ours, the first one on top (each the caller of the one above it)
#   make-crash-fixture.py <out.ips> --map <CrashMap.txt> <Image> <arch> <target> [--exception]
#        the first function range of <target> in <Image>'s <arch> slice of a built map (e.g. MacStatusBarCore arm64e macBanners)
#   make-crash-fixture.py <out.ips> --symbol <dSYM DWARF file> <Image> <regex> [--then <regex>]... [--exception] [--apple-top]
#        inside the first function whose name matches <regex> (the UUID is the dSYM's, i.e. the build's); each --then adds a frame of ours below
#        the ones before it, inside the first function matching that regex (its caller)
# --exception: the crash is an uncaught exception: our frames are in the last exception backtrace (the faulting thread only has Apple's abort).
# --loader: our frame is in the loader (MacStatusBar.dylib), which the guard cannot turn off on its own.
# --apple-top: the crash is in Apple code our top frame called (a trap in libdispatch under a SpringBoard method, as a dispatch_once entered
#        again), so Apple's frames are above ours on the crashing stack.
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

_syms = {}
def pick_from_symbol(dsym, regex):
    if dsym not in _syms:   # (read once: --then asks the same symbols again)
        out = subprocess.run(['dwarfdump', '--uuid', dsym], check=True, capture_output=True, text=True).stdout
        _syms[dsym] = (re.search(r'UUID: ([0-9A-Fa-f-]+)', out).group(1).lower(),
                       subprocess.run(['nm', '-n', '-s', '__TEXT', '__text', dsym], check=True, capture_output=True, text=True).stdout.splitlines())
    uuid, syms = _syms[dsym]
    for i, l in enumerate(syms):
        m = re.match(r'([0-9a-f]{16}) [tT] (.*)', l)
        if m and re.search(regex, m.group(2)):
            return uuid, int(m.group(1), 16) + 4, m.group(2)
    sys.exit('fixture: no symbol matching ' + regex)

def main():
    a = sys.argv[1:]
    exc = '--exception' in a; loader = '--loader' in a; appletop = '--apple-top' in a
    a = [x for x in a if x not in ('--exception', '--loader', '--apple-top')]
    then = []   # (--then <regex>: the callers below the top frame, in order)
    while '--then' in a:
        i = a.index('--then'); then.append(a[i + 1]); del a[i:i + 2]
    out = a[0]; note = ''
    if a[1] == '--map':
        image = a[3]; uuid, offset = pick_from_map(a[2], image, a[4], a[5]); note = 'map target ' + a[5]; offsets = [offset]
    elif a[1] == '--symbol':
        image = a[3]; uuid, offset, sym = pick_from_symbol(a[2], a[4]); note = 'symbol ' + sym; offsets = [offset]
        for rx in then:
            _, o2, s2 = pick_from_symbol(a[2], rx); offsets.append(o2); note += ' <- ' + s2
    else:
        image, uuid, offsets = a[1], a[2].lower(), [int(x, 16) for x in a[3].split(',')]
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
        {"source": "P", "arch": "arm64e", "base": 6300000000, "size": 300000, "uuid": "00000000-0000-0000-0000-00000000ffff",
         "path": "/usr/lib/system/libdispatch.dylib", "name": "libdispatch.dylib"},
    ]
    ours = [{"imageOffset": o, "imageIndex": 5 if loader else 2} for o in offsets]
    top = [{"imageOffset": 6000, "symbol": "_dispatch_once_wait", "imageIndex": 6}, {"imageOffset": 7000, "imageIndex": 0}] if appletop else []
    if exc:
        fault = [{"imageOffset": 1000, "symbol": "__pthread_kill", "imageIndex": 1}, {"imageOffset": 2000, "symbol": "objc_exception_rethrow", "imageIndex": 4}]
        backtrace = [{"imageOffset": 3000, "symbol": "__exceptionPreprocess", "imageIndex": 4}] + top + ours + [{"imageOffset": 4000, "imageIndex": 3}]
    else:
        fault = top + ours + [{"imageOffset": 4000, "imageIndex": 3}, {"imageOffset": 5000, "imageIndex": 0}]
        backtrace = None
    body = {"uptime": 100, "procRole": "Foreground", "incident": "SYNTHETIC-TEST-FIXTURE", "note": note,
            "exception": {"type": "EXC_CRASH" if exc else "EXC_BREAKPOINT" if appletop else "EXC_BAD_ACCESS", "signal": "SIGABRT" if exc else "SIGTRAP" if appletop else "SIGSEGV"},
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
    print('%s: %s+%s uuid %s%s' % (out, image, ', +'.join('0x%x' % o for o in offsets), uuid, (' (' + note + ')') if note else ''))

main()
