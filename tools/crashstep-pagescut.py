# crashstep-pagescut.py <LineSwitch.h> <MSBRootListController.m> <pages cut out> <picker cut out>: for tools/test-crashstep.sh (L104, 1.8.7.5).
# Cuts out of the real files what the pages do with the crash guard's note: LineSwitch.h from MSBDGuardAction to the end of MSBDNoteSwitch (the
# footers, the rule that ends the note, the note of a switch) plus the condition of Turn Back On in msbd_untestedSpecifiers (as a macro), and the
# lines of the Status Bar Style picker's branch that end the note. Exit 1 if any is not found.
import re, sys
ls, pm = open(sys.argv[1]).read().split('\n'), open(sys.argv[2]).read().split('\n')
try:
    start = next(i for i, l in enumerate(ls) if l.startswith('static int MSBDGuardAction(void)'))
    ns = next(i for i, l in enumerate(ls) if l.startswith('static void MSBDNoteSwitch('))
    end = next(i for i in range(ns, len(ls)) if ls[i] == '}')
    conds = [m.group(1) for m in (re.search(r'if \(!MSBDSafeMode\(\)\) return (.*?) \? @\[group, button, \[self msbd_reportButton\]\]', l) for l in ls) if m]
    b = next(i for i, l in enumerate(pm) if 'isEqual:@"stockStatusBar"]) {' in l)
    s0 = next(i for i in range(b, len(pm)) if 'int guardAction = MSBDGuardAction();' in pm[i] or 'if (!on && ' in pm[i])
    i_if = next(i for i in range(s0, len(pm)) if 'if (!on && ' in pm[i])
    e = next(i for i in range(i_if, len(pm)) if pm[i].strip() == '}')
except StopIteration:
    sys.exit(1)
if len(conds) != 1 or not any('MSBD_GUARD_ACTION_KEY' in l for l in pm[i_if:e]):
    sys.exit(1)
open(sys.argv[3], 'w').write('\n'.join(ls[start:end + 1]) + '\n#define MSBD_TEST_TURNBACKON_COND (%s)\n' % conds[0])
open(sys.argv[4], 'w').write('\n'.join(pm[s0:e + 1]) + '\n')
