#!/usr/bin/env python3
# crashmap-keys-check.py -- part of tools/test-crashstep.sh (no build needed): Window Tiling Shortcuts and Custom Shortcuts in the crash map's rules
# (review of 1.8.7: on for new installs since defaults v5, and no rule named them, so a crash in their code took Stock status bar mode).
# Usage: crashmap-keys-check.py <rules> <source root>. Exit 0 when every check passes.
import re, sys, os
rules, root = sys.argv[1], sys.argv[2]
src = lambda f: open(os.path.join(root, f), errors='replace').read()
wk, cs, sb = src('statusbar/WindowKeys.h'), src('statusbar/CustomShortcuts.h'), src('statusbar/StatusBar.x')
targets, sym, sec, fil = {}, [], [], []
for raw in open(rules):
    line = re.split(r'\s+#', raw, 1)[0].strip()
    if not line or line.startswith('#'): continue
    f = line.split()
    if f[0] == 'target': targets[f[1]] = f[2:]
    elif len(f) == 4 and f[0] in ('sym', 'sec', 'file') and f[1] == 'MacStatusBarCore': {'sym': sym, 'sec': sec, 'file': fil}[f[0]].append((re.compile(f[2]), f[3]))
def first(rs, name):
    for rx, t in rs:
        if rx.search(name): return t
    return None
def by(name, fname):   # (as make-crashmap.py: sym, then file -- no section header of these files matches a sec rule, checked below -- then the image's)
    return first(sym, name) or first(fil, fname) or 'stock'
bad = 0
def check(ok, what):
    global bad
    print(('PASS  ' if ok else 'FAIL  ') + what)
    if not ok: bad += 1

# the two switches, as Settings and SpringBoard name them
d = {m.group(1): m.group(2) for f in ('common/ModifierTap.h', 'common/CustomShortcutsRule.h') for m in re.finditer(r'^#define (\w+) +"([^"]+)"', src(f), re.M)}
wt, ct = targets.get('windowTilingKeys', []), targets.get('customShortcuts', [])
check(wt[:5] == ['pref', d.get('kMSBDWindowKeysDomain'), d.get('kMSBDWindowKeysKey'), '0', '1'] and 'Window Tiling Shortcuts|the window tiling shortcuts' in ' '.join(wt),
      'Window Tiling Shortcuts: its own switch (%s %s), set off (0), on when never set (1)' % (d.get('kMSBDWindowKeysDomain'), d.get('kMSBDWindowKeysKey')))
check(ct[:5] == ['pref', d.get('kMSBDCSDomain'), d.get('kMSBDCSEnabled'), '0', '1'] and 'Custom Shortcuts|your own keyboard shortcuts' in ' '.join(ct),
      'Custom Shortcuts: its own switch (%s %s), set off (0), on when never set (1)' % (d.get('kMSBDCSDomain'), d.get('kMSBDCSEnabled')))
check('BOOL fill = NO, keys = YES;' in sb and 'if (kr) { if (CFGetTypeID(kr) == CFBooleanGetTypeID()) keys = CFBooleanGetValue(kr); CFRelease(kr); }' in sb
      and 'gCSSwitch = sw ? (CFGetTypeID(sw) == CFBooleanGetTypeID() && CFBooleanGetValue(sw)) : YES;' in cs,
      '  ... as SpringBoard reads them: never set is on, the false the guard writes is off')

# what each switch stops: these run only while it is on (the gates below), so a frame of theirs is that switch's
tiling = ['DMWinKeyRun', 'DMWinKeyInput', 'DMWinKeysPressesBegan', 'DMWinKeysKeyCommands', 'DMWinKeyCommandFired', 'DMWindowKeysInstall', 'DMWindowKeysRegister',
          'DMWindowBackFromTile', 'DMCenterFrontWindow', 'DMArrangeWindows', 'DMWinPrevNoteView', 'DMWinPrevNoteNative', 'DMWinPrevNoteSM', 'DMWinPrevNoteActive', 'DMWinPrevPruneSM']
custom = ['DMCSRun', 'DMCSRunOnce', 'DMCSRunFromApp', 'DMCSRuleFor', 'DMCSPressesBegan', 'DMCSKeyCommands', 'DMCSKeyCommandFired', 'DMCSInstall', 'DMCSMakeKeyCommands', 'DMCSKeyInput']
defined = lambda n, t: re.search(r'^static [^(=;]*?\b' + n + r'\(', t, re.M)
gone = [n for n in tiling if not defined(n, wk)] + [n for n in custom if not defined(n, cs)]
check(not gone, 'their functions found in WindowKeys.h and CustomShortcuts.h' + (' -- not found: ' + ', '.join(gone) if gone else ''))
wrong = [v for n in tiling for v in ('_' + n, '___' + n + '_block_invoke', '___' + n + '_block_invoke_2') if by(v, 'WindowKeys.h') != 'windowTilingKeys']
check(not wrong, 'Window Tiling\'s rows and their steps, hooks, key commands and Return to Previous Size\'s records (their blocks too) are Window Tiling Shortcuts\''
      + (' -- not: ' + ', '.join(wrong) if wrong else ''))
wrong = [v for n in custom for v in ('_' + n, '___' + n + '_block_invoke', '___' + n + '_block_invoke_2') if by(v, 'CustomShortcuts.h') != 'customShortcuts']
wrong += [v for v in ('___DMCSPublishStates_block_invoke', '___DMCSPublishStates_block_invoke_3') if by(v, 'CustomShortcuts.h') != 'customShortcuts']
check(not wrong, 'Custom Shortcuts\' run of a rule, a press\'s match, its hooks, key commands and the apps\' run names (DMCSPublishStates\' block) are Custom Shortcuts\''
      + (' -- not: ' + ', '.join(wrong) if wrong else ''))
gates = [('the tiling hooks and key commands only once the switch is on', 'if (gWindowKeysOn) DMWindowKeysInstall();' in wk),
         ('a row runs only while on', 'if (i >= kMSBDWinKeyRowCount || !gWindowKeysOn) return NO;' in wk),
         ('the records taken only while on', wk.count('if (!DMWinPrevWanted()) return;') == 2 and 'if (w && DMWinPrevWanted()) DMWinPrevNoteView(' in wk
          and 'if (!bundleID.length || !DMWinPrevWanted()) return;' in wk and 'static BOOL DMWinPrevWanted(void) { return gWindowKeysOn; }' in wk),
         ('nothing registered while off', 'if (gWinKeyCmds.count != kMSBDWinKeyRowCount) return YES;' in wk),
         ('the shortcuts\' hooks and key commands only while on', 'if (gCSSwitch && usable.count && DMCSInstall()) DMCSMakeKeyCommands();' in cs),
         ('the apps\' run names only while on (none with KeyPilot in)', 'unsigned n = gCSSwitch && !gCSKeyPilot ? (unsigned)MIN(gCSRules.count, (NSUInteger)kMSBDCSMaxRules) : 0;' in cs
          and 'for (; gCSRunNames < n; gCSRunNames++) {' in cs),
         ('a press, a key command and an app\'s post run a rule only while taken', 'if (presses.count && DMCSWanted()) {' in cs and 'if (s.length < 10 || !DMCSWanted()) return;' in cs
          and 'if (!DMCSAppsTaken() || i >= gCSRules.count) return;' in cs)]
bad_g = [g for g, ok in gates if not ok]
check(not bad_g, '  ... each switch stops them: ' + '; '.join(g for g, ok in gates) + (' -- not as read: ' + ', '.join(bad_g) if bad_g else ''))

# what they do not stop stays with the status bar: Stock status bar mode stops it (the prefs' read, which installs the tiling keys, and the shortcuts'
# start come after its return in the constructor)
stay = [('_DMTitleRecordView', 'WindowKeys.h'), ('_DMTitleRecordSMAt', 'WindowKeys.h'), ('_DMTitleRecordPair', 'WindowKeys.h'), ('_DMWinTileFor', 'WindowKeys.h'),
        ('_DMWinTiledEngine', 'WindowKeys.h'), ('___DMWinTiledSM_block_invoke', 'WindowKeys.h'), ('_DMWinKeysWanted', 'WindowKeys.h'), ('_DMWindowKeysPublish', 'WindowKeys.h'),
        ('_DMWindowKeysApply', 'WindowKeys.h'), ('_DMWindowKeysYoursChanged', 'WindowKeys.h'), ('_DMWinPrevWanted', 'WindowKeys.h'),
        ('_DMCSLoad', 'CustomShortcuts.h'), ('_DMCSPublish', 'CustomShortcuts.h'), ('_DMCSPublishStates', 'CustomShortcuts.h'), ('___DMCSPublish_block_invoke', 'CustomShortcuts.h'),
        ('_DMCSStateGet', 'CustomShortcuts.h'), ('_DMCSLiveSlot', 'CustomShortcuts.h'), ('_DMCSKeySignature', 'CustomShortcuts.h'), ('_DMCSRecordingCheck', 'CustomShortcuts.h'),
        ('_DMCSKeyboardTick', 'CustomShortcuts.h'), ('_DMCSWanted', 'CustomShortcuts.h'), ('_DMCSKeyPilotInstalled', 'CustomShortcuts.h'), ('_DMCustomShortcutsStart', 'CustomShortcuts.h'),
        ('___DMCustomShortcutsStart_block_invoke_3', 'CustomShortcuts.h'), ('____logosLocalCtor_9bb7c60c_block_invoke_29', 'CustomShortcuts.h'),
        ('_DMKCYoursLoad', 'CustomShortcuts.h'), ('_DMKCKeyPilotRules', 'CustomShortcuts.h'), ('_DMKCYoursPublish', 'CustomShortcuts.h'), ('___DMKCYoursLoad_block_invoke', 'CustomShortcuts.h')]
got = ['%s %s' % (n, by(n, f)) for n, f in stay if by(n, f) != 'stock']
check(not got, 'the rest stays with the status bar: the title bar\'s Fill / Zoom records, the tile test, the keys\' publish on the tick, the shortcuts\' load, states, tick and '
      'Yours over a built-in (KeyPilot\'s too)' + (' -- not: ' + ', '.join(got) if got else ''))
ret = sb.find('if (gStockBar) { DMSpotPublishOff();')
check(ret > 0 and sb.find('DMCustomShortcutsStart();', ret) > ret and sb.rfind('DMCustomShortcutsStart();', 0, ret) < 0 and re.search(r'DMWindowKeysApply\(\);', sb[sb.find('static void DMLoadPrefs('):]) is not None
      and sb.find('DMLoadPrefs()', ret) > ret, '  ... which Stock status bar mode stops (the prefs\' read and the shortcuts\' start come after its return)')
check(first(fil, 'WindowKeys.h') is None and first(fil, 'CustomShortcuts.h') is None,
      '  ... no file rule for WindowKeys.h or CustomShortcuts.h (it would take the title bar\'s records and the code that runs with the switch off)')
heads = [h.strip() for t in (wk, cs, src('common/KeyboardChords.h'), src('statusbar/WindowKeysRule.h'), src('common/CustomShortcutsRule.h'))
         for h in re.findall(r'^//\s?(?:----|====).*$', t, re.M)]
check(not [h for h in heads if first(sec, h)], '  ... and no section header of theirs matches a sec rule' + ''.join(' -- %s: %s' % (h, first(sec, h)) for h in heads if first(sec, h)))
tr = [first(fil, f) for f in ('WindowKeysRule.h', 'CustomShortcutsRule.h', 'KeyboardChords.h')]
check(tr == ['transparent'] * 3 and all(first(sym, n) is None for n in ('_MSBDWinKeyFor', '_MSBDCSRuleUsable', '_MSBDKCYoursTakes')),
      'the rules\' plain functions (WindowKeysRule.h, CustomShortcutsRule.h, KeyboardChords.h) are passed over: the caller decides (got %s)' % tr)
sys.exit(1 if bad else 0)
