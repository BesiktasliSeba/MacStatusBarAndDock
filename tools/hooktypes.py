"""hooktypes.py -- the types our Logos hooks are written for, against iPadOS's own (test-hooktypes.sh; 1.8.9, after a test build's Lock Screen
crash: a hook declared a double where iPadOS passes an NSNumber).

  hooktypes.py gen OUT.m FILE...            an Objective-C probe: every hook declaration of FILE's %hook blocks, compiled into a class of its own,
                                            prints "file<TAB>group<TAB>class<TAB>selector<TAB>types" with the types as common/HookTypes.h reduces
                                            them (the runtime's string of the compiled declaration)
  hooktypes.py check PROBE_OUT DATA FILE... the checks (PASS / FAIL lines; exit 1 on a FAIL):
     1. every %group with a kHookSigs_<group> table, and every group named by --guarded, has one listing exactly the group's methods, with
        the types its declarations compile to;
     2. every hook declaration of FILE has the types iPadOS's method has on every version DATA reads it on (DATA: hooktypes-ipados.txt);
        a hooked method DATA does not have on any version fails ("not read"), except in a group named by --unread-ok (published before
        1.8.9 and unchanged: said as SKIP).
Reads only the files it is given; runs nothing."""
import re
import sys


def bare(enc):
    """common/HookTypes.h's MSBDHookBareTypes, in Python (for DATA's strings)."""
    out = []
    i = 0
    array_length = False   # (the digits right after '[' are the array's length, kept)
    while i < len(enc):
        ch = enc[i]
        if ch.isdigit() and not array_length:
            i += 1
            continue
        if not ch.isdigit():
            array_length = ch == "["
        if ch in "rnNoORV":
            i += 1
            continue
        if ch == '"':
            j = enc.find('"', i + 1)
            if j < 0:
                break
            i = j + 1
            continue
        if ch == "?" and out and out[-1] == "@":
            i += 1
            continue
        out.append(ch)
        if ch in "{(":
            j = i + 1
            while j < len(enc) and enc[j] not in "=}){(":
                j += 1
            if j < len(enc) and enc[j] == "=":
                i = j
        i += 1
    return "".join(out)


def selector(decl):
    body = re.sub(r"^[-+]\s*\((?:[^()]|\([^()]*\))*\)\s*", "", decl)
    parts = re.findall(r"(\w+)\s*:\s*\((?:[^()]|\([^()]*\))*\)\s*\w+", body)
    return "".join(p + ":" for p in parts) if parts else body.split()[0]


def hooks(fn):
    """[(group, class, sign, selector, declaration)] of FILE's %hook blocks; a method line whose '{' is not on it: selector None (a FAIL)."""
    out = []
    group, cls = "-", None
    for line in open(fn, encoding="utf-8", errors="replace"):
        s = line.strip()
        m = re.match(r"%group\s+(\w+)", s)
        if m:
            group = m.group(1)
            continue
        m = re.match(r"%hook\s+(\w+)", s)
        if m:
            cls = m.group(1)
            continue
        if s.startswith("%end"):
            if cls:
                cls = None
            else:
                group = "-"
            continue
        if cls and re.match(r"^[-+]\s*\(", line):
            if "{" in line:
                decl = line[:line.index("{")].strip()
                out.append((group, cls, decl[0], selector(decl), decl))
            else:
                out.append((group, cls, s[0], None, s))
    return out


def tables(fn):
    """{group: [(class, selector, types)]} from FILE's kHookSigs_<group>[] tables."""
    src = open(fn, encoding="utf-8", errors="replace").read()
    out = {}
    for m in re.finditer(r"static const MSBDHookSig kHookSigs_(\w+)\[\]\s*=\s*\{(.*?)\n\};", src, re.S):
        out[m.group(1)] = re.findall(r'\{\s*"([^"]+)"\s*,\s*"([^"]+)"\s*,\s*"([^"]+)"\s*\}', m.group(2))
    return out


def gen(outm, files):
    names = set()
    rows = []
    for fn in files:
        for i, (g, c, sign, sel, decl) in enumerate(hooks(fn)):
            if sel is None:
                continue
            rows.append((fn, g, c, sign, sel, decl))
            for t in re.findall(r"\b([A-Z]\w+)\s*\*", decl):
                names.add(t)
    known = {"NSString", "NSDate", "NSNumber", "NSArray", "NSDictionary", "NSSet", "NSObject"}
    with open(outm, "w") as f:
        f.write("#import <Foundation/Foundation.h>\n#import <CoreGraphics/CoreGraphics.h>\n#include HT_HEADER\n")
        fw = sorted(n for n in names if n not in known)
        if fw:
            f.write("@class %s;\n" % ", ".join(fw))
        for k, (fn, g, c, sign, sel, decl) in enumerate(rows):
            if sign != "-":
                continue
            f.write("@interface HTProbe%d : NSObject @end\n@implementation HTProbe%d\n#pragma clang diagnostic push\n"
                    "#pragma clang diagnostic ignored \"-Wreturn-type\"\n%s {}\n#pragma clang diagnostic pop\n@end\n" % (k, k, decl))
        f.write("int main(void) { @autoreleasepool {\n")
        f.write('    if (strcmp(@encode(BOOL), "B") != 0) { printf("!! BOOL is not B here\\n"); return 2; }\n')
        for k, (fn, g, c, sign, sel, decl) in enumerate(rows):
            if sign != "-":
                continue
            f.write('    { Method m = class_getInstanceMethod([HTProbe%d class], sel_registerName("%s")); char b[160]; '
                    'if (!m || !MSBDHookBareTypes(method_getTypeEncoding(m), b, sizeof b)) { printf("!! %s %s\\n"); return 3; } '
                    'printf("%s\\t%s\\t%s\\t%s\\t%%s\\n", b); }\n' % (k, sel, c, sel, fn, g, c, sel))
        f.write("    return 0;\n} }\n")


def check(probe_out, data, files, guarded, unread_ok=()):
    fails = 0

    def res(ok, what):
        nonlocal fails
        if not ok:
            fails += 1
        print("%s  %s" % ("PASS" if ok else "FAIL", what))
    compiled = {}
    for line in open(probe_out):
        p = line.rstrip("\n").split("\t")
        if len(p) == 5:
            compiled[(p[0], p[1], p[2], p[3])] = p[4]
    real = {}   # "-[C s]" -> [(version, bare, note)]
    for line in open(data):
        if not line.strip() or line.startswith("#"):
            continue
        p = line.rstrip("\n").split("\t")
        real.setdefault(p[1], []).append((p[0], bare(p[2]), p[3] if len(p) > 3 else ""))
    for fn in files:
        hs = hooks(fn)
        for g, c, sign, sel, decl in hs:
            if sel is None:
                res(False, "%s %s: -[%s ...] declaration not read (its '{' is not on its line): %s" % (fn, g, c, decl[:100]))
        hs = [h for h in hs if h[3] is not None]
        ts = tables(fn)
        groups = sorted(set(g for g, *_ in hs))
        for g in groups:
            mine = [(c, sel) for gg, c, sign, sel, _ in hs if gg == g]
            if g in ts or g in guarded.get(fn, ()):
                t = ts.get(g)
                if t is None:
                    res(False, "%s %s: no kHookSigs_%s table (a guarded group)" % (fn, g, g))
                    continue
                same = sorted(mine) == sorted((c, s) for c, s, _ in t)
                res(same, "%s %s: its table lists exactly its %d hooked methods" % (fn, g, len(mine)) + ("" if same else " (group %s, table %s)" % (sorted(mine), sorted((c, s) for c, s, _ in t))))
                for c, s, ty in t:
                    got = compiled.get((fn, g, c, s))
                    res(got == ty, "%s %s: -[%s %s] table %s = the declaration's %s" % (fn, g, c, s, ty, got))
        for g, c, sign, sel, decl in hs:
            key = "%s[%s %s]" % (sign, c, sel)
            got = compiled.get((fn, g, c, sel))
            rows = real.get(key)
            if not rows:
                if g in unread_ok:
                    print("SKIP  %s %s: %s not read (a group published before 1.8.9, its declaration unchanged)" % (fn, g, key))
                else:
                    res(False, "%s %s: %s is not read on any version (hooktypes-ipados.txt)" % (fn, g, key))
                continue
            bad = [(v, b) for v, b, _ in rows if b != got]
            res(not bad, "%s %s: %s declared %s = iPadOS's on %s" % (fn, g, key, got, ", ".join(v for v, _, _ in rows)) + ("" if not bad else " -- NOT on %s" % bad))
    for fn, gs in guarded.items():
        for g in gs:
            if g not in tables(fn):
                res(False, "%s: the guarded group %s has no table" % (fn, g))
    return fails


def main():
    if sys.argv[1] == "gen":
        gen(sys.argv[2], sys.argv[3:])
        return 0
    if sys.argv[1] == "check":
        args = sys.argv[2:]
        guarded = {}
        unread_ok = []
        files = []
        i = 2
        while i < len(args):
            if args[i] == "--unread-ok":
                unread_ok += args[i + 1].split(",")
                i += 2
                continue
            if args[i] == "--guarded":
                fn, gs = args[i + 1].split("=", 1)
                guarded[fn] = gs.split(",")
                i += 2
                continue
            files.append(args[i])
            i += 1
        return 1 if check(args[0], args[1], files, guarded, unread_ok) else 0
    return 2


if __name__ == "__main__":
    sys.exit(main())
