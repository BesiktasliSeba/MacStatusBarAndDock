#!/bin/bash
# Source check of the status bar items' colour (1.7.1 item 8, KT: some items white, some black): every item of ours is coloured in one place
# (StatusBar.x DMApplyBarItemColor) from one decision (DMBarItemColor), at every layout, at every restyle of the time label (an app asking for the
# other style) and by the Lock Screen's layout; no item is coloured anywhere else (before: each where it was laid out, and a restyle reached only
# some of them). Run from anywhere; reads ../statusbar/StatusBar.x and ../statusbar/WiFiMenu.h.
set -e
cd "$(dirname "$0")"
python3 -I - ../statusbar/StatusBar.x ../statusbar/WiFiMenu.h <<'PY'
import re, sys
sb = open(sys.argv[1], encoding='utf-8').read(); wf = open(sys.argv[2], encoding='utf-8').read()
fails = 0
def check(ok, what):
    global fails
    print(("PASS  " if ok else "FAIL  ") + what)
    if not ok: fails += 1
def body(src, start):   # the text of the function whose definition starts with `start`, up to its closing brace at column 0
    i = src.find(start); j = src.find('\n}\n', i)
    return src[i:j] if i >= 0 and j > i else ''
apply = body(sb, 'static void DMApplyBarItemColor(UIView *fg, UIColor *c, BOOL background) {')
check(bool(apply), 'DMApplyBarItemColor is there')
labels = re.search(r'const void \*labels\[\] = \{([^}]*)\}', apply); icons = re.search(r'const void \*icons\[\] = \{([^}]*)\}', apply)
L = set(k.strip() for k in labels.group(1).split(',')) if labels else set(); I = set(k.strip() for k in icons.group(1).split(',')) if icons else set()
for k in ['kLogoKey', 'kDateProxyKey']: check(k in L, f'{k} is coloured there')
for k in ['kSpotIconKey', 'kWiFiIconKey', 'kVPNIconKey', 'kMuteIconKey', 'kSSHIconKey']: check(k in I, f'{k} is coloured there')
titles = set(re.findall(r'DMLayoutTitle\(fg, rtl, (k\w+LabelKey),', sb))
check(len(titles) >= 7, f'{len(titles)} menu titles laid out by DMLayoutTitle')
for k in sorted(titles): check(k in L, f'the title {k} is coloured there')
made = set(re.findall(r'objc_setAssociatedObject\(fg, (k\w+(?:Icon|Proxy)Key), \w+, OBJC_ASSOCIATION', sb + wf)) - {'kTimeProxyKey'}
for k in sorted(made): check(k in (L | I), f'the item {k} the bar makes is coloured there')
check('DMApplyBackground(fg, c)' in apply, 'the background follows the same colour')
check(re.search(r'DMApplyBarItemColor\(fg, barColor, YES\);', sb) is not None, 'the layout colours every item at its end')
check(sb.count('UIColor *barColor = DMBarItemColor(fg, timeLabel);') == 1, 'the layout decides the colour once (DMBarItemColor)')
hook = body(sb, '- (void)setTextColor:(UIColor *)color {')
check('DMApplyBarItemColor(fg, DMBarItemColor(fg, me), YES);' in hook, 'a restyle of the time label colours every item (setTextColor:)')
check('DMApplyBarItemColor(fg, DMBarItemColor(fg, nil), NO);' in body(sb, 'static BOOL DMLayoutWithoutClock(UIView *fg) {'), 'the Lock Screen layout colours every item, from the status icons')
decide = body(sb, 'static UIColor *DMBarItemColor(UIView *fg, UIView *timeLabel) {')
check('DMLabelDrawnColor((UILabel *)timeLabel)' in decide, 'the decision reads the time as drawn (its tint when its text follows the tint: ColorBar15), not only its text colour')
check('_textColorFollowsTintColor' in body(sb, 'static UIColor *DMLabelDrawnColor(UILabel *l) {'), 'the drawn colour follows UIKit\'s text-follows-tint switch')
check('DMLabelDrawnColor((UILabel *)v)' in body(sb, 'static UIColor *DMTrailingIconColor(UIView *trailing) {'), 'the status icons\' colour (the Lock Screen copy) is read as drawn too')
check('DMApplyBarItemColor(fg, DMBarItemColor(fg, me), YES);' in body(sb, '- (void)tintColorDidChange {'), 'a tint-only restyle of the time (ColorBar15) colours every item')
# nothing coloured elsewhere: no item assignment outside DMApplyBarItemColor (debug-only before/after code aside)
nodebug = re.sub(r'#if DEBUG.*?#endif', '', sb, flags=re.S)
rest = nodebug.replace(apply, '')
bad = re.findall(r'\b(logo|dateProxy|spotIcon|vpnIcon|muteIcon|sshIcon|label)\.(?:textColor|tintColor) = (?!c;)[^;\n]*(?:timeColor|final|tint)\b', rest)
check(not bad, 'no item coloured anywhere else ' + (str(bad) if bad else ''))
check('timeColor' not in nodebug, 'no per-item timeColor left')
check('UIColor *tint' not in body(wf, 'static CGSize DMWiFiApplyIconState(UIView *icon) {') and 'DMWiFiApplyIconState(UIView *icon) {' in wf, "the Wi-Fi icon's state carries no colour of its own")
print(f'{fails} failed'); sys.exit(1 if fails else 0)
PY
