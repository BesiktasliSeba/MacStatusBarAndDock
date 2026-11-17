#!/usr/bin/env python3
# ctornouikit-walk.py <tree> [-v]: tools/test-ctornouikit.sh's static half (GitHub #16). Every constructor of ours that runs in SpringBoard -- each
# part loader/Loader.c loads there (kSpringBoard, kUIKit: SpringBoard is a bundled UIKit process), the loaders themselves and the guard's notice --
# is walked through the calls it makes at once: C functions and macros of its part (its files from the Makefiles, with their quoted includes),
# blocks too, except a block handed to something that runs it later (dispatch_async / _after, a notify or notification handler, a timer, a
# completion). A constructor runs inside dyld's loading of its part, dyld's loader lock held: UIKit's first screen set-up there waited on
# FrontBoard's listener thread, which waited on that lock, and SpringBoard hung at every start (+[UIScreen screens] from Finder's Trash). Nothing
# reached may ask UIScreen anything, ask DMDispScreens, make a window or ask UIWindow for its windows.
# What the walk knows of the start: gDMInCtor is YES (StatusBar.x and Dock.x set it first thing in their %ctor): "if (gDMInCtor) ... return"
# ends a function there, "!gDMInCtor && f(" never calls f. And the guards of START below: each is a line that must still be in its function
# (else the walk fails: look again), with what keeps the code after it from running at the start.
# Prints each constructor with the number of functions it reaches and every hit with its call path; exits with the number of problems.
import os, re, sys, bisect

ROOT = os.path.abspath(sys.argv[1]); VERBOSE = '-v' in sys.argv

# ---- the guards that stop a function at the start (kind, function, the guard's text, the callee kept out, what at the start makes it so) ----
# kind "ret": the function returns at this line at the start -- nothing after it is walked; kind "cut": the callee named is not called at the
# start through this line (the rest of the function is walked).
START = [
    ('ret', 'DMLAApplyPrefs', 'if (age < 8.0) {', None,
     'Live Activities apply 8 s after SpringBoard\'s exec at the earliest (DMProcessAge): the constructor runs well before (and a very late one '
     'finds no bar copy or card to draw, where the screen is asked)'),
    ('ret', 'DMControlCenterActive', 'if (!gCCWindowSeen) return NO;', None,
     'gCCWindowSeen is set only by our hooks once SpringBoard has made Control Center\'s window'),
    ('ret', 'DMSysTouchN', 'if (phase == DMTouchWarm) { DMTouchscreenSenderID(sysClient); return; }', None,
     'the constructor\'s only call (DMTouchFixInit) is the warm-up: DMSysTouch(CGPointZero, DMTouchWarm)'),
    ('cut', 'DMCCPApplyStyle', 'UIViewController *ov = gCCPInConstructor ? nil : DMCCPFindOverlay();', 'DMCCPFindOverlay',
     'DMCCPanelInit sets gCCPInConstructor around its apply: no overlay looked for'),
    ('cut', 'DMCCPApplyStyle', 'if (ov.isViewLoaded) DMCCPBuildLive(ov);', 'DMCCPBuildLive', 'ov is nil there (above)'),
    ('cut', 'DMCCPApplyStyle', 'if (want == gCCPOn) { gCCPPending = NO; return; }', 'DMCCPGiveBack',
     'the give-back runs only when ours was on (gCCPOn), never at the start'),
    ('cut', 'DMCC18ApplyStyle', 'UIViewController *m = gCC18InConstructor ? nil : DMCC18FindMain();', 'DMCC18FindMain',
     'DMCC18Init sets gCC18InConstructor around its apply'),
    ('cut', 'DMCC18ApplyStyle', 'if (m.isViewLoaded) DMCC18Relayout(', 'DMCC18Relayout', 'm is nil there (above)'),
    ('cut', 'DMBarSizeInstall', 'if (late && DMTVBarDisplayKey()) gDMTVBarSize = MSBDMenuBarSmall;', 'DMTVBarDisplayKey',
     'the constructor installs with late NO (DMBarSizeInit: DMBarSizeInstall(want, NO)); late YES only from a notify handler'),
    ('cut', 'DMFinderApplyPref', '    if (on) return;', 'DMNativeSetActive',
     'Finder switched off: at the start gFinderOn is NO, so the first apply returns at "on == gFinderOn" or at "if (on) return;"'),
    ('cut', 'DMFinderApplyPref', '    if (on) return;', 'DMNativeApplyLevel', 'the same'),
    ('cut', 'DMAMApply', 'else if (gDMAMStarted) {', 'DMAMRunningSync',
     'at the start DMALApplyPref calls it only to switch on (on != gDMALOn, which starts NO), and gDMAMStarted is set 3 s later (DMAMStartLook)'),
    ('cut', 'DMAMApply', 'else if (gDMAMStarted) {', 'DMAMDockCheck', 'the same'),
    ('cut', 'DMDockAutoHideSetOn', 'if ([UIApplication sharedApplication]) DMAutoHideApplyNow(', 'DMAutoHideApplyNow',
     'UIApplication\'s shared instance is nil until SpringBoard\'s main: the Dock\'s hooks answer its first layout (review 1.8.4 Pass 4 H1)'),
    ('cut', 'DMStartRunningIndicatorPoll', 'if (passNow && !blank) RIResyncDock();', 'RIResyncDock',
     'the constructor\'s pass is apply(NO): no resync then; the timer and the notify handlers resync later'),
]
# the start-time facts the guards above rest on, each a line that must be in that function
FACTS = [
    ('DMBarSizeInit', 'DMBarSizeInstall(want, NO);'),
    ('DMTouchFixInit', 'DMSysTouch(CGPointZero, DMTouchWarm);'),
    ('DMCCPanelInit', 'gCCPInConstructor = YES;'),
    ('DMCC18Init', 'gCC18InConstructor = YES;'),
    ('DMFinderApplyPref', 'if (on == gFinderOn) return;'),
    ('DMALApplyPref', 'if (on == gDMALOn) return;'),
    ('DMStartRunningIndicatorPoll', '    apply(NO);'),
]

# ---- what may not be reached ----
BAD = re.compile(r'\[\s*UIScreen\s+\w+|\bUIScreen\s*\.\s*\w+|\bDMDispScreens\s*\(|\[\s*\[?\s*UIWindow\s+\w+|initWithWindowScene\s*:|\bMSBDMakeAlertWindow\s*\(')
BAD_STR = re.compile(r'(NSSelectorFromString\s*\(\s*|sel_registerName\s*\(\s*|DMCall\s*\([^,;]*,\s*)@?"(mainScreen|screens|initWithRole:debugName:|allWindowsIncludingInternalWindows:onlyVisibleWindows:)"')
# a block handed to one of these runs later, not in the constructor
ASYNC = re.compile(r'(dispatch_async|dispatch_after|dispatch_barrier_async|dispatch_group_notify|notify_register_dispatch|addObserverForName:[^;]*usingBlock:|'
                   r'Timer\w*:[^;]*block:|dispatch_source_set_\w+_handler|completion(Handler)?:|CompletionHandler:|DMMSWAsync\w*|DMMSWAfter|'
                   r'CFRunLoopPerformBlock|performBlock:)\s*\(?[^;]*$')
KEYWORDS = {'if', 'for', 'while', 'switch', 'return', 'sizeof', 'do', 'else', 'catch', '__attribute__', 'defined', 'typeof', '__typeof__', 'case', 'alignof'}
problems = []

def expand(path, seen, out):
    path = os.path.normpath(path)
    if path in seen or not os.path.exists(path): return
    seen.add(path)
    with open(path, errors='replace') as f:
        for i, line in enumerate(f, 1):
            m = re.match(r'\s*#\s*(?:include|import)\s+"([^"]+)"', line)
            if m and os.path.exists(os.path.join(os.path.dirname(path), m.group(1))):
                out.append((path, i, '\n')); expand(os.path.join(os.path.dirname(path), m.group(1)), seen, out); continue
            out.append((path, i, line))

def strip(text, keep_strings):
    # comments out; string contents kept (keep_strings) or blanked; newlines kept, so offsets map to lines
    res = []; i = 0; n = len(text)
    while i < n:
        c = text[i]
        if text.startswith('//', i):
            j = text.find('\n', i); j = n if j < 0 else j; res.append(' ' * (j - i)); i = j; continue
        if text.startswith('/*', i):
            j = text.find('*/', i + 2); j = n if j < 0 else j + 2
            res.append(''.join('\n' if ch == '\n' else ' ' for ch in text[i:j])); i = j; continue
        if c in '"\'':
            j = i + 1
            while j < n and text[j] != c and text[j] != '\n':
                if text[j] == '\\': j += 1
                j += 1
            seg = text[i + 1:j]
            seg = ''.join(' ' if ch in '{}()^;[]' else ch for ch in seg) if (keep_strings and c == '"') else ' ' * len(seg)
            res.append(c + seg + (c if j < n else '')); i = j + 1; continue
        res.append(c); i += 1
    return ''.join(res)

def match_brace(s, b):
    d = 0
    for j in range(b, len(s)):
        if s[j] == '{': d += 1
        elif s[j] == '}':
            d -= 1
            if d == 0: return j
    return len(s) - 1

def find_functions(s, funcs):
    i = 0; n = len(s); last = 0
    while i < n:
        c = s[i]
        if c == '{':
            head = s[last:i].strip()
            j = match_brace(s, i)
            m = re.search(r'\b([A-Za-z_]\w*)\s*\(([^()]*(?:\([^()]*\)[^()]*)*)\)\s*(?:__attribute__\s*\(\([^)]*\)\)\s*)*$', head)
            lastline = head.split('\n')[-1].strip() if head else ''
            if m and m.group(1) not in KEYWORDS and not re.search(r'(^|\n)\s*[-+]\s*\(', head) and not lastline.startswith(('@', '%')) and not head.endswith('='):
                funcs.setdefault(m.group(1), []).append((i, j + 1))
            i = j + 1; last = i; continue
        if c in ';}': last = i + 1
        elif c == '\n':
            k = s.find('\n', i + 1); k = n if k < 0 else k
            if s[i + 1:k].lstrip().startswith(('#', '%', '@')): last = k
        i += 1

def blocks(body):
    out = []
    for m in re.finditer(r'\^\s*(?:[A-Za-z_][\w\s\*]*)?\s*(\([^()]*\))?\s*\{', body):
        b = body.index('{', m.start()); e = match_brace(body, b)
        pre = body[max(0, m.start() - 600):m.start()]
        pre = pre[max(pre.rfind(';'), pre.rfind('{'), pre.rfind('}')) + 1:]
        out.append((m.start(), e + 1, pre))
    return out

def sync_part(name, body, base, s):
    # the body as it runs at the start: async blocks blanked; "if (gDMInCtor) ... return" ends it; START's guards applied
    keep = list(body)
    for st, en, pre in blocks(body):
        if ASYNC.search(pre):
            for k in range(st, en):
                if keep[k] != '\n': keep[k] = ' '
    t = ''.join(keep)
    cut = set()
    m = re.search(r'\n\s*if\s*\(\s*gDMInCtor\s*\)\s*(\{|return\b)', t)
    if m:
        e = match_brace(t, t.index('{', m.start())) if m.group(1) == '{' else t.index(';', m.start())
        if re.search(r'\breturn\b', t[m.start():e + 1]): t = t[:e + 1]
    for g in re.finditer(r'!\s*gDMInCtor\s*&&\s*([A-Za-z_]\w*)\s*\(', t): cut.add(g.group(1))
    for kind, fn, guard, callee, why in START:
        if fn != name: continue
        raw = s[base:base + len(body)]
        k = raw.find(guard)
        if k < 0: problems.append('the start guard of %s is gone (%r): %s -- look again' % (name, guard, why)); continue
        if kind == 'ret': t = t[:k + len(guard)]
        else: cut.add(callee)
    return t, cut

def parts():
    # SpringBoard's parts: Loader.c's tables (both lines), entries with kSpringBoard or kUIKit
    src = open(os.path.join(ROOT, 'loader/Loader.c')).read()
    names = set()
    for m in re.finditer(r'\{\s*"(\w+)",\s*([^}]*)\}', src):
        if re.search(r'\bk(SpringBoard|UIKit)\b', m.group(2)): names.add(m.group(1))
    files = {}
    for dp, dn, fn in os.walk(ROOT):
        if '/third_party' in dp or '/tools' in dp or '/.git' in dp: continue
        if 'Makefile' not in fn: continue
        mk = open(os.path.join(dp, 'Makefile')).read().replace('\\\n', ' ')
        for m in re.finditer(r'(?m)^(\w+)_FILES\s*\+?=\s*(.*)$', mk):
            if m.group(1) in names: files.setdefault(m.group(1), []).extend(os.path.join(dp, x) for x in m.group(2).split())
    missing = sorted(names - set(files))
    if missing: problems.append('no source files found for the SpringBoard part(s) %s' % ', '.join(missing))
    out = sorted(files.items())
    out.append(('MacStatusBar/MacDock (loader)', [os.path.join(ROOT, 'loader/Loader.c')]))
    out.append(('MacCrashNotice (the guard\'s notice)', [os.path.join(ROOT, 'loader/CrashNotice.m')]))
    out.append(('MacPerfProbe (debug builds)', [os.path.join(ROOT, 'loader/PerfProbe.m')]))
    return out

def walk_part(pname, files):
    lines = []; seen = set()
    for f in files: expand(f, seen, lines)
    text = ''.join(l for _, _, l in lines)
    s = strip(text, True)
    starts = []; pos = 0
    for _, _, l in lines: starts.append(pos); pos += len(l)
    def where(off):
        k = bisect.bisect_right(starts, off) - 1
        return '%s:%d' % (os.path.relpath(lines[k][0], ROOT), lines[k][1])
    funcs = {}; find_functions(s, funcs)
    for m in re.finditer(r'(?m)^[ \t]*#[ \t]*define[ \t]+([A-Za-z_]\w*)\(([^)]*)\)[ \t]*((?:.*\\\n)*.*)$', s):
        funcs.setdefault(m.group(1), []).append((m.start(3), m.end(3)))
    ctors = [m for m in re.finditer(r'(%ctor\s*\{|__attribute__\s*\(\(\s*constructor\s*\)\)[^{;]*\{)', s)]
    total = 0
    for cm in ctors:
        b = s.index('{', cm.start()); e = match_brace(s, b)
        label = '%s %s' % (pname, where(cm.start()))
        seen_fn = {}; todo = [('<ctor>', b, e + 1, [])]; hits = []
        while todo:
            name, a, z, path = todo.pop(0)
            key = (name, a)
            if key in seen_fn: continue
            seen_fn[key] = path
            body = s[a:z]
            t, cut = sync_part(name, body, a, s)
            tb = re.sub(r'(?<!@)"[^"\n]*"', lambda q: '"' + ' ' * (len(q.group(0)) - 2) + '"', t)
            for mm in BAD.finditer(tb): hits.append((name, where(a + mm.start()), mm.group(0), path))
            for mm in BAD_STR.finditer(t): hits.append((name, where(a + mm.start()), mm.group(0), path))
            for cmm in re.finditer(r'\b([A-Za-z_]\w*)\s*\(', tb):
                callee = cmm.group(1)
                if callee == name or callee in cut or callee not in funcs: continue
                for (fa, fz) in funcs[callee]:
                    if (callee, fa) not in seen_fn: todo.append((callee, fa, fz, path + [name]))
        print('%s: %d function(s) reached at once' % (label, len(seen_fn)))
        if VERBOSE:
            for (fn, _), p in sorted(seen_fn.items()): print('    reached %s <- %s' % (fn, ' > '.join(p[-3:]) or '-'))
        for name, loc, what, path in hits:
            print('FAIL  %s reaches %s at %s (%s)' % (label, what.strip(), loc, ' > '.join(path + [name])))
        total += len(hits)
    return total, len(ctors), funcs, s

n = 0; nctor = 0; allfuncs = {}
for pname, files in parts():
    h, c, funcs, s = walk_part(pname, files)
    n += h; nctor += c
    for name in funcs:
        allfuncs.setdefault(name, []).extend(s[a:z] for a, z in funcs[name])
for fn, fact in FACTS:
    if not any(fact in b for b in allfuncs.get(fn, [])): problems.append('the start fact "%s" is not in %s: a START guard rests on it -- look again' % (fact, fn))
# the flag itself: set first thing in StatusBar.x's and Dock.x's %ctor, cleared at every way out of them (cleanup), read where the walk reads it
for f in ('statusbar/StatusBar.x', 'dock/Dock.x'):
    src = strip(open(os.path.join(ROOT, f)).read(), True)
    m = re.search(r'%ctor\s*\{\s*BOOL inCtor __attribute__\(\(cleanup\(DMCtorOver\), unused\)\) = gDMInCtor = YES;', src)
    if not m: problems.append('%s: its %%ctor does not set gDMInCtor first thing (BOOL inCtor __attribute__((cleanup(DMCtorOver), unused)) = gDMInCtor = YES;)' % f)
    if not re.search(r'static void DMCtorOver\(BOOL \*inCtor\) \{ gDMInCtor = NO; \}', src): problems.append('%s: no DMCtorOver clearing gDMInCtor' % f)
    if not re.search(r'static BOOL gDMInCtor = NO;', src): problems.append('%s: no gDMInCtor' % f)
for p in problems: print('FAIL  ' + p)
print('ctornouikit-walk: %d constructor(s), %d hit(s), %d other problem(s)' % (nctor, n, len(problems)))
sys.exit(min(n + len(problems), 99))
