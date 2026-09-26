#!/usr/bin/env python3
# make-crashmap.py -- builds CrashMap.txt, the crash guard's "what can be turned off" map (step 1b, common/CrashStep.h). Run at package time
# (Makefile, internal-stage) on the Mac, from the unstripped debug symbols (.dSYM) the build leaves in the obj folder; the shipped dylibs stay
# stripped. Rules: tools/crashmap-rules.txt.
#
# Usage: make-crashmap.py <rules> <obj dir> <staged part dir> <source root> <out file>
#   <obj dir>/<arch>/<Image>.dylib.dSYM  the symbols (one per arch slice)
#   <staged part dir>/<Image>.dylib       the binary that ships (its per-slice LC_UUIDs key the map)
# The build fails when a slice has no matching dSYM or a rule matches no function at all (a renamed section header, a renamed function).
#
# Output (plain text, read by loader/CrashFeatureHelper.m only after a crash that counted against us):
#   T <target> pref <domain> <key> <off 0|1> <default 0|1> <row title>|<where>   a switch: set to <off>; <default> = its value when never set
#   T <target> part                                          the part (image) is not loaded any more (loader skip list)
#   P <Image> <target>                                       an image's own target (a small part; or a big one's fallback)
#   N <Image> <where>|<what>                                 the part in words ("the Dock|MacDock"), for the guard's explanation
#   U <Image> <uuid> <arch>                                  a function map follows for this slice ...
#   R <start hex> <target>                                   ... address ranges (image offsets), each up to the next R line; "-" = nothing
import os, re, subprocess, sys

def run(args):
    return subprocess.run(args, check=True, capture_output=True, text=True).stdout

def load_rules(path):
    targets, images, rules, titles = {}, {}, [], {}
    for raw in open(path):
        line = re.split(r'\s+#', raw, 1)[0].strip()   # (a comment: a whole line, or after a space)
        if not line or line.startswith('#'):
            continue
        f = line.split()
        kind = f[0]
        if kind == 'target':
            targets[f[1]] = f[2:]
        elif kind == 'title':
            titles[f[1]] = ' '.join(f[2:])
        elif kind == 'image':
            images[f[1]] = {'target': f[2], 'map': len(f) > 3 and f[3] == 'map'}
        elif kind in ('sym', 'sec', 'file'):
            rules.append((kind, f[1], re.compile(f[2]), f[3]))
        else:
            sys.exit('crashmap rules: unknown line: ' + line)
    for name, im in images.items():
        if im['target'] not in targets:
            sys.exit('crashmap rules: unknown target %s for %s' % (im['target'], name))
    for r in rules:
        if r[3] not in targets:
            sys.exit('crashmap rules: unknown target ' + r[3])
    return targets, images, rules, titles

def uuids(binary):   # {arch: uuid}
    out = {}
    for m in re.finditer(r'UUID: ([0-9A-Fa-f-]+) \((\w+)\)', run(['dwarfdump', '--uuid', binary])):
        out[m.group(2)] = m.group(1).lower()
    return out

def line_rows(dsym):   # {address: (file name, line)} for the first row at each address
    rows, files = {}, {}
    for l in run(['dwarfdump', '--debug-line', dsym]).splitlines():
        if l.startswith('debug_line['):
            files = {}; cur = None
            continue
        m = re.match(r'file_names\[\s*(\d+)\]:', l)
        if m:
            cur = int(m.group(1)); continue
        m = re.match(r'\s+name: "(.*)"', l)
        if m and cur is not None:
            files[cur] = os.path.basename(m.group(1)); cur = None; continue
        m = re.match(r'0x([0-9a-f]{16})\s+(\d+)\s+\d+\s+(\d+)', l)
        if m:
            a = int(m.group(1), 16)
            if a not in rows and int(m.group(2)) > 0:
                rows[a] = (files.get(int(m.group(3)), '?'), int(m.group(2)))
    return rows

def functions(dsym):   # [(start, name)], plus the end of __text
    syms = []
    for l in run(['nm', '-n', '-s', '__TEXT', '__text', dsym]).splitlines():
        m = re.match(r'([0-9a-f]{16}) [tT] (.*)', l)
        if m and not m.group(2).startswith(('ltmp', 'l_')):
            syms.append((int(m.group(1), 16), m.group(2)))
    sect = run(['otool', '-l', dsym])
    m = re.search(r'sectname __text\n\s+segname __TEXT\n\s+addr 0x([0-9a-f]+)\n\s+size 0x([0-9a-f]+)', sect)
    end = int(m.group(1), 16) + int(m.group(2), 16) if m else (syms[-1][0] + 4 if syms else 0)
    return syms, end

_headers, _paths = {}, None
def section_of(srcroot, fname, line):   # the header text governing a source line ('' if none, or after an "end" header)
    global _paths
    if _paths is None:   # (every source file of the tree by name: the tree's file names are unique)
        _paths = {}
        for root, dirs, names in os.walk(srcroot):
            dirs[:] = [d for d in dirs if not d.startswith('.') and d != 'packages']
            for n in names:
                _paths.setdefault(n, os.path.join(root, n))
    if fname not in _headers:
        hs = []
        if fname in _paths:
            cur, stack = '', []   # (a %group's section ends with its %end: what came before it goes on)
            for i, t in enumerate(open(_paths[fname], errors='replace'), 1):
                if re.match(r'//\s?(====|----)', t):
                    cur = '' if re.match(r'//\s*=+\s*end\b', t) else t.strip()
                elif t.startswith('%group '):
                    stack.append(cur); cur = t.strip()
                elif re.match(r'\s*%(hook|subclass)\b', t):
                    stack.append(None); continue
                elif re.match(r'\s*%end\b', t) and stack:
                    prev = stack.pop()
                    if prev is None:
                        continue
                    cur = prev; i += 1
                else:
                    continue
                hs.append((i, cur))
        _headers[fname] = hs
    text = ''
    for i, t in _headers[fname]:
        if i > line:
            break
        text = t
    return text

def classify(image, name, fname, sec, rules, default, hits):
    found = default
    for kind in ('sym', 'sec', 'file'):
        for n, (k, im, rx, tgt) in enumerate(rules):
            if k != kind or im != image:
                continue
            subject = name if kind == 'sym' else sec if kind == 'sec' else fname
            if subject and rx.search(subject):
                hits[n] += 1   # (every rule that matches is counted, also one an earlier rule wins over: only a rule matching nothing is broken)
                if found is default:
                    found = tgt
    return found

def main():
    rules_path, objdir, partdir, srcroot, out = sys.argv[1:6]
    report = os.environ.get('CRASHMAP_REPORT')   # (optional: a file listing every function and its target, for review)
    targets, images, rules, titles = load_rules(rules_path)
    lines = ['# MacStatusBar&Dock crash map v1 (generated by tools/make-crashmap.py; see common/CrashStep.h)']
    for t, spec in sorted(targets.items()):
        lines.append('T %s %s' % (t, ' '.join(spec)))
    for image, im in sorted(images.items()):
        lines.append('P %s %s' % (image, im['target']))
    for image, t in sorted(titles.items()):
        lines.append('N %s %s' % (image, t))
    rep = []
    hits = [0] * len(rules)   # (functions each rule matches, over every slice)
    problems = []
    for image, im in sorted(images.items()):
        if not im['map']:
            continue
        binary = os.path.join(partdir, image + '.dylib')
        if not os.path.exists(binary):
            sys.exit('crashmap: missing ' + binary)
        for arch, uuid in sorted(uuids(binary).items()):
            dsym = os.path.join(objdir, arch, image + '.dylib.dSYM', 'Contents', 'Resources', 'DWARF', image + '.dylib')
            if not os.path.exists(dsym) or uuids(dsym).get(arch) != uuid:
                problems.append('no matching symbols for %s (%s): no function map for this slice' % (image, arch))
                continue
            rows = line_rows(dsym)
            syms, end = functions(dsym)
            ranges = []
            for i, (start, name) in enumerate(syms):
                fname, line = rows.get(start, ('', 0))
                sec = section_of(srcroot, fname, line) if fname else ''
                tgt = classify(image, name, fname, sec, rules, im['target'], hits)
                rep.append('%s %s %06x %-18s %s:%d [%s] %s' % (image, arch, start, tgt, fname, line, sec[:60], name))
                if not ranges or ranges[-1][1] != tgt:
                    ranges.append((start, tgt))
            lines.append('U %s %s %s' % (image, uuid, arch))
            for start, tgt in ranges:
                lines.append('R %x %s' % (start, tgt))
            lines.append('R %x -' % end)
    # A rule that matches no function at all is a broken rule (most often a section header that a comment edit renamed or removed): the whole
    # feature would fall back to the part's default without a word. So the build stops, as it does for a slice without a map.
    for n, (k, im, rx, tgt) in enumerate(rules):
        if not hits[n] and images.get(im, {}).get('map'):
            problems.append('rule "%s %s %s %s" matches no function (a renamed section header or function?)' % (k, im, rx.pattern, tgt))
    if problems and not os.environ.get('CRASHMAP_LENIENT'):
        sys.exit('crashmap: ' + '\ncrashmap: '.join(problems) + '\n(tools/crashmap-rules.txt; CRASHMAP_LENIENT=1 builds anyway, for a quick test only)')
    for p in problems:
        print('crashmap: ' + p, file=sys.stderr)
    with open(out, 'w') as f:
        f.write('\n'.join(lines) + '\n')
    if report:
        with open(report, 'w') as f:
            f.write('\n'.join(rep) + '\n')

main()
