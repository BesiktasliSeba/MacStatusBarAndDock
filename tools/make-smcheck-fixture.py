#!/usr/bin/env python3
# make-smcheck-fixture.py -- one iPadOS build's API table for the Stage Manager engine's self-check test (tools/test-smcheck16.sh).
# Input: the ObjC headers of that build's SpringBoard side, typed (`ipsw class-dump -V` of SpringBoard, SpringBoardFoundation, SpringBoardHome and
# UIKitCore's UIView/UIResponder/UIApplication/UIButton/UIControl/UIViewController, libobjc's NSObject, from the build's dyld_shared_cache; ipsw:
# github.com/blacktop/ipsw, `ipsw download ipsw --device <iPad> --build <build> --dyld` pulls only the cache from Apple's IPSW) plus UIKitCore's
# category symbols (`ipsw dyld symaddr <cache> --image UIKitCore`, the NSObject/UIView/UIResponder/UIApplication category lines).
# Output: for every row of kSMNeeds (statusbar/SMEngineAPI.h) the class chain from the row's class up to NSObject, the method on the class that
# defines it, with its type encoding written back from the header's types (struct names kept, offsets left out: the check compares shapes), and
# ivar rows with the ivar's encoding. A row whose class or method the build lacks is simply not in the table -- that is what the test checks.
# usage: make-smcheck-fixture.py <SMEngineAPI.h> <dump dir> "<title line>" > tools/smcheck-fixtures/<build>.txt
import os, re, sys

QUAL = {'const', 'in', 'out', 'inout', 'bycopy', 'byref', 'oneway', 'volatile'}
BASE = {'void': 'v', '_Bool': 'B', 'bool': 'B', 'BOOL': 'B', 'char': 'c', 'short': 's', 'int': 'i', 'float': 'f', 'double': 'd', 'id': '@',
        'Class': '#', 'SEL': ':'}

def tokenize(s):
    s = re.sub(r'/\*\s*block\s*\*/', ' __BLOCK__ ', s)
    s = re.sub(r'/\*.*?\*/', ' ', s)
    return re.findall(r'[A-Za-z_][A-Za-z0-9_]*|\d+|[{}();*\[\]:,<>^?]', s)

class Toks:
    def __init__(self, t): self.t, self.i = t, 0
    def peek(self, k=0): return self.t[self.i + k] if self.i + k < len(self.t) else None
    def take(self): x = self.peek(); self.i += 1; return x

def enc_type(p):
    """an ObjC type encoding (struct names kept) for the type text at p"""
    while p.peek() in QUAL: p.take()
    tok = p.peek()
    if tok in ('struct', 'union'):
        p.take()
        name = p.take() if p.peek() not in ('{', None) else '?'
        body = None
        if p.peek() == '{':
            p.take(); body = ''
            while p.peek() not in ('}', None):
                t = enc_type(p)
                if p.peek() and re.match(r'[A-Za-z_]', p.peek()): p.take()   # field name
                if p.peek() == ':': p.take(); p.take(); t = 'b'           # bit field
                while p.peek() == '[':
                    p.take(); n = p.take() if p.peek() != ']' else ''
                    if p.peek() == ']': p.take()
                    t = '[%s%s]' % (n, t)
                if p.peek() == ';': p.take()
                body += t
            p.take()
        o, c = ('{', '}') if tok == 'struct' else ('(', ')')
        e = o + name + ('=' + body if body is not None else '') + c
    elif tok in ('unsigned', 'signed'):
        p.take(); words = []
        while p.peek() in ('char', 'short', 'int', 'long'): words.append(p.take())
        w = ' '.join(words) or 'int'
        e = {'char': 'C', 'short': 'S', 'int': 'I', 'long': 'L', 'long long': 'Q', 'long long int': 'Q', 'long int': 'L'}.get(w, 'I') if tok == 'unsigned' else \
            {'char': 'c', 'short': 's', 'int': 'i', 'long': 'l', 'long long': 'q'}.get(w, 'i')
    elif tok == 'long':
        p.take()
        if p.peek() == 'long': p.take(); e = 'q'
        elif p.peek() == 'double': p.take(); e = 'D'
        else: e = 'l'
        if p.peek() == 'int': p.take()
    elif tok == 'id':
        p.take()
        if p.peek() == '__BLOCK__': p.take(); e = '@?'
        else:
            e = '@'
            if p.peek() == '<':
                while p.peek() not in ('>', None): p.take()
                p.take()
    elif tok == '__BLOCK__':
        p.take(); e = '@?'
    elif tok and re.match(r'[A-Za-z_]', tok):
        p.take()
        if tok in BASE: e = BASE[tok]
        else:   # a class name: "NSString *" is an object
            if p.peek() == '<':
                while p.peek() not in ('>', None): p.take()
                p.take()
            if p.peek() == '*': p.take(); e = '@'
            else: e = '?'
    else:
        p.take(); e = '?'
    while p.peek() == '*':
        p.take(); e = '*' if e == 'c' else '^' + e
    if p.peek() == '(' and p.peek(1) == '*':   # function pointer
        depth = 0
        while p.peek() is not None:
            x = p.take()
            if x == '(': depth += 1
            elif x == ')':
                depth -= 1
                if depth == 0 and p.peek() != '(': break
        e = '^?'
    return e

def type_text_enc(text): return enc_type(Toks(tokenize(text)))

def balanced(s, i):
    depth = 0
    for j in range(i, len(s)):
        if s[j] == '(': depth += 1
        elif s[j] == ')':
            depth -= 1
            if depth == 0: return s[i + 1:j], j + 1
    return s[i + 1:], len(s)

def parse_method(line):
    kind = line[0]
    ret, i = balanced(line, line.index('('))
    rest = line[i:].rstrip(';').strip()
    if '(' not in rest: return kind, rest, type_text_enc(ret) + '@:'
    sel, args, j = '', [], 0
    while j < len(rest):
        m = re.match(r'\s*([A-Za-z0-9_]*):', rest[j:])
        if not m: break
        sel += m.group(1) + ':'; j += m.end()
        while j < len(rest) and rest[j] == ' ': j += 1
        if j < len(rest) and rest[j] == '(':
            t, j = balanced(rest, j); args.append(type_text_enc(t))
        else: args.append('@')
        m2 = re.match(r'\s*[A-Za-z0-9_]+', rest[j:])
        if m2: j += m2.end()
    return kind, sel, type_text_enc(ret) + '@:' + ''.join(args)

def parse_dumps(d):
    classes = {}
    for fn in sorted(os.listdir(d)):
        if not fn.endswith('.h'): continue
        cur, in_ivars = None, False
        for line in open(os.path.join(d, fn), errors='replace'):
            if line.startswith('@interface '):
                m = re.match(r'@interface ([A-Za-z0-9_]+)\s*(?:\(([^)]*)\))?\s*(?::\s*([A-Za-z0-9_]+))?', line)
                c = classes.setdefault(m.group(1), {'super': None, 'i': {}, 'c': {}, 'ivars': {}})
                if m.group(3) and m.group(2) is None: c['super'] = m.group(3)
                cur, in_ivars = c, line.rstrip().endswith('{')
                continue
            if cur is None: continue
            if line.startswith('@end'): cur, in_ivars = None, False; continue
            s = line.strip()
            if in_ivars:
                if s.startswith('}'): in_ivars = False; continue
                m = re.search(r'([A-Za-z0-9_]+);\s*(?://.*)?$', s)
                if m and not s.startswith('/*'): cur['ivars'][m.group(1)] = type_text_enc(s[:m.start()])
                continue
            if s.startswith('- (') or s.startswith('+ ('):
                try: kind, sel, e = parse_method(s)
                except Exception: continue
                (cur['i'] if kind == '-' else cur['c']).setdefault(sel, e)
    # UIKit's categories on NSObject / UIView / ...: names from the symbols; the public UIKit methods among them have fixed signatures
    public = {'setAccessibilityIdentifier:': 'v@:@', 'setAlpha:': 'v@:d', 'didMoveToWindow': 'v@:', 'layoutSubviews': 'v@:', 'sendEvent:': 'v@:@'}
    sp = os.path.join(d, 'UIKitCore-cats.syms')
    if os.path.exists(sp):
        for line in open(sp, errors='replace'):
            m = re.search(r'([-+])\[([A-Za-z0-9_]+)\(([^)]*)\) ([^\]]+)\]', line)
            if m and m.group(4) in public:
                c = classes.setdefault(m.group(2), {'super': None, 'i': {}, 'c': {}, 'ivars': {}})
                (c['i'] if m.group(1) == '-' else c['c']).setdefault(m.group(4), public[m.group(4)])
    # (SpringBoard, the app's principal class, is in the executable, not in the cache: its methods come from UIApplication)
    classes.setdefault('SpringBoard', {'super': 'UIApplication', 'i': {}, 'c': {}, 'ivars': {}})['super'] = 'UIApplication'
    return classes

def rows_of(src):
    body = re.search(r'kSMNeeds\[\]\s*=\s*\{(.*?)\n\};', src, re.S).group(1)
    for line in body.splitlines():
        line = line.strip()
        if not line.startswith('{"'): continue
        parts = [x.strip() for x in re.split(r',(?=(?:[^"]*"[^"]*")*[^"]*$)', line[1:line.index('}')])]
        yield {'cls': parts[0].strip('"'), 'sel': parts[1].strip('"'), 'cm': parts[2] == 'YES', 'alt': parts[5].strip('"') if len(parts) > 5 and parts[5] != 'NULL' else None,
               'ivar': len(parts) > 9 and parts[9] != 'NULL'}

def chain(classes, c):
    out = []
    while c and c in classes and c not in out and c != 'NSObject':
        out.append(c); c = classes[c]['super']
    return out

def main():
    src, d, title = open(sys.argv[1]).read(), sys.argv[2], sys.argv[3]
    C = parse_dumps(d)
    cls_lines, meth_lines, ivar_lines = {}, set(), set()
    def add_chain(c):
        ch = chain(C, c)
        for k in ch:
            sup = C[k]['super'] if C[k]['super'] in C or C[k]['super'] == 'NSObject' else 'NSObject'
            cls_lines[k] = sup or 'NSObject'
    for r in rows_of(src):
        if r['cls'] not in C: continue
        add_chain(r['cls'])
        names = [r['sel']] + ([r['alt']] if r['alt'] else [])
        if r['ivar']:
            k = r['cls']
            while k in C and k != 'NSObject':
                if r['sel'] in C[k]['ivars']: ivar_lines.add('ivar\t%s\t%s\t%s' % (k, r['sel'], C[k]['ivars'][r['sel']])); break
                k = C[k]['super']
            continue
        for name in names:
            k = r['cls']
            while k in C:
                tab = C[k]['c' if r['cm'] else 'i']
                if name in tab:
                    if k == 'NSObject': meth_lines.add('method\tNSObject\t%s\t%s\t%s' % ('+' if r['cm'] else '-', name, tab[name] or 'v@:'))
                    else: add_chain(k); meth_lines.add('method\t%s\t%s\t%s\t%s' % (k, '+' if r['cm'] else '-', name, tab[name] or 'v@:'))
                    break
                k = C[k]['super']
    print('# ' + title)
    print('# generated by tools/make-smcheck-fixture.py from that build\'s ObjC metadata; one line per class, method and ivar the check asks for')
    for k in sorted(cls_lines): print('class\t%s\t%s' % (k, cls_lines[k]))
    for l in sorted(meth_lines): print(l)
    for l in sorted(ivar_lines): print(l)

if __name__ == '__main__':
    main()
