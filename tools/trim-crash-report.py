#!/usr/bin/env python3
# trim-crash-report.py -- a test fixture from a REAL SpringBoard crash report (.ips: a header line, then a JSON body), for the crash guard's Mac
# tests (1.8.7.7, GitHub #14: the reports users sent and our own iPads' are the cases the guard must judge right).
#
#   trim-crash-report.py <in.ips> <out.ips> [--pid <n>] [--keep-names <name>,...]
#
# Kept: what the classifier and the guard read -- usedImages / binaryImages (or legacyInfo.imageExtraInfo), the threads' frames,
# lastExceptionBacktrace, faultingThread, exception, asi, termination, exceptionReason, pid, procName, procLaunch, captureTime, osVersion; for a
# watchdog report the stackshot's SpringBoard process (all its threads) and its binaryImages (UUIDs and kinds only, no names in them anyway).
# Dropped: everything that identifies the device or its owner (crashReporterKey, incident ids, userID, storeInfo, bundleInfo, vmSummary, uptime,
# trialInfo, the model, the paths' preboot hashes) and everything not read.
# Other tweaks: never named in a fixture -- each library that is not Apple's, not ours, not a window engine we drive and not jailbreak
# infrastructure becomes OtherTweakA.dylib, OtherTweakB.dylib, ... (in the order first seen; a framework or bundle keeps its kind of path), its frames'
# symbols and its threads' and queues' names go, and app paths become /var/containers/Bundle/Application/X/App.app. --keep-names keeps a name (none
# by default). --pid sets the body's pid (a report without one).
import json, re, sys

OURS = re.compile(r'/MacStatusBarAndDock/|/(TweakInject|DynamicLibraries)/(MacStatusBar|MacDock)\.dylib$')
ENGINES = {'Aerial.dylib', 'Zetsu.dylib', 'MilkyWay4.dylib', 'MilkyWay3SubModule.dylib'}
INFRA = {'libellekit.dylib', 'ellekit', 'systemhook.dylib', 'TweakLoader.dylib', 'TweakInject.dylib', 'libinjector.dylib', 'CydiaSubstrate',
         'libsubstrate.dylib', 'libsubstitute.dylib', 'libhooker.dylib', 'libblackjack.dylib', 'libroot.dylib', 'dyld', 'libjailbreak.dylib',
         'libchoma.dylib', 'rootlesshooks.dylib', 'MobileSafety.dylib', 'universalhooks.dylib'}
APPLE = ('/System/', '/usr/lib/', '/usr/libexec/', '/usr/sbin/', '/usr/bin/', '/Developer/', '/private/preboot/Cryptexes/', '/Library/Apple/', '/AppleInternal/')

def clean_path(p):
    p = re.sub(r'^/private/preboot/[0-9A-Fa-f]{16,}/', '/private/preboot/X/', p)
    p = re.sub(r'/(dopamine|jb)-[A-Za-z0-9]+/', r'/\1-X/', p)
    p = re.sub(r'^/private/var/containers/Bundle/Application/[^/]+/', '/private/var/containers/Bundle/Application/X/', p)
    p = re.sub(r'^/var/containers/Bundle/Application/[^/]+/', '/var/containers/Bundle/Application/X/', p)
    return p

class Names:
    def __init__(self, keep):
        self.map, self.keep = {}, set(keep)
    def other(self, path, name):
        n = (name or path.rsplit('/', 1)[-1]).strip()
        if not path or OURS.search(path) or n in ENGINES or n in INFRA or n in self.keep or n.startswith('MSBD'):
            return None
        if path.startswith(APPLE) or '/basebin/' in path or '/usr/lib/ellekit/' in path or path.startswith('/cores/binpack/') or 'choicy' in n.lower():
            return None
        if n not in self.map:
            k = len(self.map)
            self.map[n] = 'OtherTweak' + (chr(65 + k) if k < 26 else 'Z%d' % k)
        return self.map[n]
    def rename(self, img):
        path, name = img.get('path') or '', img.get('name') or ''
        new = self.other(path, name)
        out = {k: img[k] for k in ('source', 'arch', 'base', 'size', 'uuid') if k in img}
        if new is None:
            if path: out['path'] = clean_path(path)
            if name: out['name'] = name
            return out, False
        if '.framework/' in path: out['path'], out['name'] = '/var/jb/Library/Frameworks/%s.framework/%s' % (new, new), new
        elif '.bundle/' in path: out['path'], out['name'] = '/var/jb/Library/%s.bundle/%s' % (new, new), new
        elif '/TweakInject/' in path or '/DynamicLibraries/' in path: out['path'], out['name'] = '/var/jb/usr/lib/TweakInject/%s.dylib' % new, new + '.dylib'
        else: out['path'], out['name'] = '/var/jb/usr/lib/%s.dylib' % new, new + '.dylib'
        return out, True

def frames(fr, hidden):
    out = []
    for f in fr or []:
        if not isinstance(f, dict): continue
        g = {k: f[k] for k in ('imageOffset', 'imageIndex', 'symbol', 'symbolLocation') if k in f}
        if g.get('imageIndex') in hidden: g.pop('symbol', None); g.pop('symbolLocation', None)
        out.append(g)
    return out

def main():
    a = sys.argv[1:]
    pid = None; keep = []
    if '--pid' in a: i = a.index('--pid'); pid = int(a[i + 1]); del a[i:i + 2]
    if '--keep-names' in a: i = a.index('--keep-names'); keep = a[i + 1].split(','); del a[i:i + 2]
    src, dst = a
    raw = open(src, 'rb').read()
    nl = raw.find(b'\n')
    head = json.loads(raw[:nl])
    try: body = json.loads(raw[nl + 1:])
    except ValueError: body, _ = json.JSONDecoder().raw_decode(raw[nl + 1:].decode('utf8', 'replace').lstrip())
    names = Names(keep)
    out = {}
    for k in ('procName', 'pid', 'procLaunch', 'captureTime', 'faultingThread', 'exception', 'asi', 'termination', 'exceptionReason', 'osVersion'):
        if k in body: out[k] = body[k]
    if pid is not None: out['pid'] = pid
    hidden = set()
    for key in ('usedImages', 'binaryImages'):
        if isinstance(body.get(key), list) and body[key] and isinstance(body[key][0], dict):
            imgs = []
            for i, img in enumerate(body[key]):
                if not isinstance(img, dict): imgs.append(img); continue
                r, h = names.rename(img)
                if h: hidden.add(i)
                imgs.append(r)
            out[key] = imgs
    li = body.get('legacyInfo')
    if isinstance(li, dict) and isinstance(li.get('imageExtraInfo'), list) and 'usedImages' not in out:
        out['legacyInfo'] = {'imageExtraInfo': [names.rename(x)[0] if isinstance(x, dict) else x for x in li['imageExtraInfo']]}
    if isinstance(body.get('threads'), list):
        th = []
        for t in body['threads']:
            if not isinstance(t, dict): continue
            u = {k: t[k] for k in ('id', 'triggered') if k in t}
            for k in ('queue', 'name'):   # (Apple's queue names stay; a reverse-DNS name of anyone else's goes)
                if k in t: u[k] = t[k] if str(t[k]).startswith('com.apple.') or not re.match(r'^[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+\.', str(t[k])) else 'other.' + k
            u['frames'] = frames(t.get('frames'), hidden)
            th.append(u)
        out['threads'] = th
    if isinstance(body.get('lastExceptionBacktrace'), list): out['lastExceptionBacktrace'] = frames(body['lastExceptionBacktrace'], hidden)
    ss = body.get('stackshot')
    if isinstance(ss, dict):   # (a watchdog report: SpringBoard's process only, every thread's user frames)
        want = body.get('procName', 'SpringBoard')
        procs = {p: v for p, v in (ss.get('processByPid') or {}).items() if isinstance(v, dict) and v.get('procname') == want}
        keepp = {}
        for p, v in procs.items():
            keepp[p] = {'procname': v.get('procname'), 'threadById': {tid: {k: t[k] for k in ('id', 'dispatch_queue_label', 'userFrames') if k in t and (k != 'dispatch_queue_label' or str(t[k]).startswith('com.apple.'))}
                                                                      for tid, t in (v.get('threadById') or {}).items() if isinstance(t, dict)}}
        out['stackshot'] = {'processByPid': keepp, 'binaryImages': ss.get('binaryImages')}
    hdr = {k: head[k] for k in ('bug_type', 'os_version', 'name', 'timestamp') if k in head}
    hdr['note'] = 'a real report, trimmed by tools/trim-crash-report.py (other tweaks renamed, nothing that identifies the device)'
    with open(dst, 'w') as f:
        f.write(json.dumps(hdr) + '\n' + json.dumps(out, indent=0, separators=(',', ':')) + '\n')
    print('%s -> %s: %d other tweak(s) renamed' % (src.rsplit('/', 1)[-1], dst.rsplit('/', 1)[-1], len(names.map)))

main()
