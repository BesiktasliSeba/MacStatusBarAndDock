#!/usr/bin/env python3
# make-setsearch-fixture.py <build> <class-dump -V file>... > tools/setsearch-fixtures/<build>.txt
# The classes behind the Settings sidebar's search field (macsettings/SidebarSearch.x) as Apple's binaries of one iPadOS build have them, for
# tools/test-setsearch.m: one line per instance method, "<class> <superclass> <selector> <type shape>". Input: `ipsw class-dump <dyld cache> <image>
# --class '^(...)$' -V` of PSUIPrefsListController (PreferencesUI), PSListController / PSKeyboardNavigationSearchController /
# SUIKSearchResultsCollectionViewController (Preferences) and UISearchController / UICollectionViewController (UIKitCore), from the dyld shared
# cache in Apple's own IPSW for that build. The dump writes each method's ObjC types as a declaration; the shape (the ObjC type letters without
# offsets, as SidebarSearchCheck.h's MSSShape) is rebuilt from it. Unknown types become '?' (none of the methods the check needs has one).
import re, sys

SIMPLE = {
    'void': 'v', 'id': '@', '_Bool': 'B', 'BOOL': 'B', 'bool': 'B', 'char': 'c', 'unsigned char': 'C', 'short': 's', 'unsigned short': 'S',
    'int': 'i', 'unsigned int': 'I', 'long': 'q', 'unsigned long': 'Q', 'long long': 'q', 'unsigned long long': 'Q', 'float': 'f',
    'double': 'd', 'SEL': ':', 'Class': '#', 'char *': '*', 'const char *': '*',
}

def shape(t):
    t = re.sub(r'/\*.*?\*/', '', t).strip()          # (id /* block */) -> id
    t = re.sub(r'\b(const|oneway|in|out|inout|bycopy|byref)\b', '', t).strip()
    t = re.sub(r'\s+', ' ', t)
    if t in SIMPLE: return SIMPLE[t]
    m = re.match(r'struct\s+(\w+)?\s*\{(.*)\}$', t)
    if m:                                              # a struct written out with its members: their letters inside {}
        members = [x.strip() for x in m.group(2).split(';') if x.strip()]
        inner = ''
        for mem in members:
            mm = re.match(r'(.*?)\s*\b(x\d+|\w+)$', mem)
            inner += shape(mm.group(1) if mm else mem)
        return '{' + inner + '}'
    if t.endswith('*'):
        base = t[:-1].strip()
        if re.match(r'^[A-Z_]\w*(\s*<.*>)?$', base) or base.startswith('NSObject<') or base.startswith('id<'): return '@'   # an object
        return '^' + (shape(base) if base else 'v')
    if re.match(r'^id\s*<.*>$', t) or re.match(r'^NSObject\s*<.*>$', t): return '@'
    return '?'

def parse(path):
    out, cls, sup = [], None, None
    for line in open(path, errors='replace'):
        line = re.sub(r'\s+', ' ', line).strip()
        m = re.match(r'@interface (\w+) : (\w+)', line)
        if m: cls, sup = m.group(1), m.group(2); continue
        if line.startswith('@end'): cls = None; continue
        if not cls or not line.startswith('- ('): continue
        m = re.match(r'- \((.*?)\)(.*);$', line)
        if not m: continue
        ret, rest = m.group(1), m.group(2)
        parts = re.findall(r'(\w+):\((.*?)\)\s*\w+', rest)
        if parts:
            sel = ''.join(p[0] + ':' for p in parts)
            sig = shape(ret) + '@:' + ''.join(shape(p[1]) for p in parts)
        else:
            sel = rest.strip()
            if not re.match(r'^[A-Za-z_][\w]*$', sel): continue
            sig = shape(ret) + '@:'
        out.append((cls, sup, sel, sig))
    return out

if __name__ == '__main__':
    build, files = sys.argv[1], sys.argv[2:]
    seen, rows = set(), []
    for f in files:
        for r in parse(f):
            if (r[0], r[2]) in seen: continue
            seen.add((r[0], r[2])); rows.append(r)
    print('# setsearch fixture for iPadOS build %s (tools/make-setsearch-fixture.py, from Apple\'s IPSW dyld cache): class superclass selector shape' % build)
    for r in sorted(rows): print(' '.join(r))
