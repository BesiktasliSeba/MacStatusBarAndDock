#!/bin/bash
# Source check of the keyboard gate's threads (1.7.1 item 9): SpringBoard's keyboard arbiter works on its own serial queue
# (com.apple.UIKit.keyboard-arbiter), not the main thread, so its hooks (StatusBar.x DMKBArbiterRequest / DMKBArbiterStatus) and the main thread's
# policy (DMKeyboardFocusBehindWindows) share their state only under gKBGateLock, the arbiter's clients are read on its queue only, and the
# originals are set before the hooks go in. Run from anywhere; reads ../statusbar/StatusBar.x.
set -e
cd "$(dirname "$0")"
python3 -I - ../statusbar/StatusBar.x <<'PY'
import re, sys
lines = open(sys.argv[1], encoding='utf-8').read().split('\n')
src = '\n'.join(lines)
fails = 0
def check(ok, what):
    global fails
    print(("PASS  " if ok else "FAIL  ") + what)
    if not ok: fails += 1
def body(start):   # the text of the function whose definition starts with `start`, up to its closing brace at column 0
    i = src.find(start); j = src.find('\n}\n', i)
    return src[i:j] if i >= 0 and j > i else ''
# 1. the shared state: touched only between the lock and its unlock (its declarations aside)
shared = re.compile(r'\b(gKBHeldBack|gKBBehindBundles|gKBActiveBundle)\b')
locked, bad, uses = False, [], 0
for n, l in enumerate(lines, 1):
    if 'os_unfair_lock_lock(&gKBGateLock)' in l: locked = True
    if shared.search(l) and not re.match(r'static (NSSet|NSString|NSMutableSet)\b', l):
        uses += 1
        if not locked: bad.append(n)
    if 'os_unfair_lock_unlock(&gKBGateLock)' in l: locked = False
check(uses >= 6, f'the gate\'s shared state is used ({uses} places)')
check(not bad, 'the gate\'s shared state is touched only under gKBGateLock ' + (f'(not at lines {bad})' if bad else ''))
for hook in ['static void DMKBArbiterRequest(id self, SEL _cmd, id handler, BOOL steal) {', 'static void DMKBArbiterStatus(id self, SEL _cmd, id status, id handler) {']:
    b = body(hook)
    check(bool(b) and 'DMKBGateList(&behind, &active);' in b, f'{hook.split("(")[0][12:]} reads the list under the lock (DMKBGateList)')
    check(bool(b) and 'DMKBHoldBack(b);' in b, f'{hook.split("(")[0][12:]} notes a held-back app under the lock (DMKBHoldBack)')
# 2. the arbiter's clients: read on its queue only
check(src.count('handlerForBundleID:') == 1 and '@"handlerForBundleID:"' in body('static BOOL DMKBClientWantsKeys(id arb, NSString *bundle) {'),
      'the arbiter\'s clients are looked up in one place (DMKBClientWantsKeys)')
calls = [n for n, l in enumerate(lines, 1) if 'DMKBClientWantsKeys(' in l and not l.startswith('static BOOL DMKBClientWantsKeys')]
check(len(calls) >= 1 and all(any('dispatch_async(q, ^{' in lines[k - 1] for k in range(max(1, c - 2), c)) for c in calls),
      'DMKBClientWantsKeys runs only in a block on the arbiter\'s queue')
check('dispatch_queue_t q = DMKBArbiterQueue(arb);' in src and '"_queue"' in body('static dispatch_queue_t DMKBArbiterQueue(id arb) {'), 'that queue is the arbiter\'s own (its _queue)')
policy = body('static void DMKeyboardFocusBehindWindows(void) {')
check(bool(policy) and 'wantedState' not in policy and 'handlerFor' not in policy, 'the main thread\'s policy does not read the arbiter\'s clients itself')
# 3. the originals before the hooks
init = body('static void DMKBArbiterGateInit(void) {')
for o, h in [('o_KBArbiterRequest', 'DMKBArbiterRequest'), ('o_KBArbiterStatus', 'DMKBArbiterStatus')]:
    i, j = init.find(f'{o} = '), init.find(f'(IMP){h}, (IMP *)&{o}')
    check(0 <= i < j, f'{o} is set before {h} is hooked (the arbiter\'s queue may call it meanwhile)')
# 4. the gate off (the engine changed, Stage Manager, the debug switch): the pass stops early only when nothing of it is left -- no assertion, no
#    list, no app held back (code review, 30 Oct: a list set with no assertion taken stayed, and the arbiter dropped those apps' requests until a
#    respring); otherwise it runs through, which empties the list and the held-back set
early = [l.strip() for l in policy.split('\n') if l.strip().startswith('if (!can') and l.strip().endswith('return;')]
check(len(early) == 1 and all(x in early[0] for x in ('!gKBBehind.count', '!DMKBGateHolds()')),
      'with the gate off the pass stops early only when no assertion, list or held-back app is left ' + (f'({early})' if len(early) != 1 else ''))
holds = body('static BOOL DMKBGateHolds(void) {')
check(bool(holds) and 'gKBBehindBundles.count' in holds and 'gKBHeldBack.count' in holds, 'DMKBGateHolds asks for both the list and the held-back set')
check('if (can) for (NSString *b in behind) if (scenesOf[b].count) [gate addObject:b];' in policy and 'DMKBSetGateList(gate.count ? [gate copy] : nil, [active copy]);' in policy
      and 'if (!can) DMKBClearHeldBack();' in policy, 'a pass with the gate off sets an empty list and empties the held-back set')
print(f'{fails} failed'); sys.exit(1 if fails else 0)
PY
