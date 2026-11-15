# menubarsizeguard-cut.py <MSBRootListController.m> <StatusBar.x> <domain> <stored out> <branch out> <SpringBoard's reader out> <LineSwitch.h>
# <page refresh out>: for tools/test-menubarsizeguard.sh (L62, 1.8.7.5). Cuts out of the real files Settings' MSBMenuBarSizeStored and the Menu Bar
# Size branch of -[MSBRootListController setPreferenceValue:specifier:], and SpringBoard's DMBarSizeStored, with Mac Status Bar's domain made the
# test's (kMSBBarDomain, MSB_DOMAIN and the branch's own literal), so the test never writes com.besiktasliseba.macstatusbar; and (its review) the
# pages' -msbd_guardNoteMaybeGone out of LineSwitch.h's MSBD_LINE_SWITCH_METHODS, as a plain method. Exit 1 if any is not found.
import sys
src, sb, dom = open(sys.argv[1]).read().split('\n'), open(sys.argv[2], errors='replace').read().split('\n'), sys.argv[3]
ls = open(sys.argv[7]).read().split('\n')
def cut(lines, first, last):
    a = next(i for i, l in enumerate(lines) if l.startswith(first))
    return lines[a:next(i for i in range(a, len(lines)) if lines[i] == last) + 1]
try:
    stored = '\n'.join(cut(src, 'static int MSBMenuBarSizeStored(void) {', '}')).replace('kMSBBarDomain', 'CFSTR("%s")' % dom)
    branch = '\n'.join(cut(src, '\tif ([[specifier propertyForKey:@"key"] isEqual:@(kMSBDMenuBarSizeKey)]) {   // Small / Medium / Large', '\t}'))
    sbs = '\n'.join(cut(sb, 'static int DMBarSizeStored(void) {', '}')).replace('MSB_DOMAIN', 'CFSTR("%s")' % dom)
    refresh = '\n'.join(l[:-2] if l.endswith(' \\') else l for l in cut(ls, '- (void)msbd_guardNoteMaybeGone { \\', '} \\'))
except StopIteration:
    sys.exit(1)
branch = branch.replace('@"com.besiktasliseba.macstatusbar"', '@"%s"' % dom)
if 'com.besiktasliseba.macstatusbar' in stored + branch + sbs:
    sys.exit(1)
for path, text in ((sys.argv[4], stored), (sys.argv[5], branch), (sys.argv[6], sbs), (sys.argv[8], refresh)):
    open(path, 'w').write(text + '\n')
