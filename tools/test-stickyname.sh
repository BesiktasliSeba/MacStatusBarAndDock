#!/bin/bash
# Mac test of a sticky note's name (1.8.8.2 F37): the rules (common/StickyNotes.h, test-stickyname.m) and site checks: the name in the top bar of the
# idle note and of the one typed in, the rename (a double click or tap on the bar, Rename in its menu: a field in the bar; Return or a click
# elsewhere keeps it, Esc keeps the old one), hidden while the keyboard has lifted the note, the Trash file named after it and its own name kept
# for Put Back, and the privacy rule (a name is never logged). MSB_DN, MSB_N, MSB_D point it at copies of DesktopNotes.h, StickyNotes.h, Desktop.h.
set -e
cd "$(dirname "$0")"
W=$(mktemp -d); trap 'rm -rf "$W"' EXIT
fails=0
check() { if eval "$2"; then echo "PASS  $1"; else echo "FAIL  $1"; fails=1; fi; }
fnf() { awk -v s="$1" 'index($0, s) == 1 {f=1} f {print} f && /^}/ {exit}' "$2"; }
DN=${MSB_DN:-../statusbar/DesktopNotes.h}; N=${MSB_N:-../common/StickyNotes.h}; D=${MSB_D:-../statusbar/Desktop.h}; FI=../statusbar/Finder.h
mkdir -p "$W/common" "$W/tools"; cp "$N" "$W/common/StickyNotes.h"; cp test-stickyname.m "$W/tools/"
clang -O2 -fobjc-arc -Wall -Wno-unused-function -framework Foundation -o "$W/tsn" "$W/tools/test-stickyname.m"
"$W/tsn" || fails=1
cls() { awk -v c="@implementation $1" 'index($0, c) == 1 {f=1} f && /^@end/ {exit} f' "$DN"; }
# ---- the name in the top bar ----
check "the idle note draws its name in its bar (DMStickyDrawName); every store pass gives it the name shown (its own, else its text's first line, else Sticky Note)" \
  "cls DMNoteView | grep -qF 'DMStickyDrawName(_name, MSBDStickyBarRect(b));' && fnf '- (void)dm_noteStoreChanged {' '$DN' | grep -qF '[v dm_setName:MSBDStickyNameShown(e[@\"name\"], e[@\"text\"])];'"
check "  ... the name: 12 pt semibold in the ink at 75 %, centred, cut with an ellipsis, inside the bar (8 pt in), the same on every colour" \
  "fnf '__attribute__((noinline)) static UIFont *DMStickyNameFont(void) {' '$DN' | grep -qF '[UIFont systemFontOfSize:12.0 weight:UIFontWeightSemibold]' \
   && fnf '__attribute__((noinline)) static void DMStickyDrawName(NSString *name, CGRect bar) {' '$DN' | grep -qF 'ps.alignment = NSTextAlignmentCenter; ps.lineBreakMode = NSLineBreakByTruncatingTail;' \
   && fnf '__attribute__((noinline)) static void DMStickyDrawName(NSString *name, CGRect bar) {' '$DN' | grep -qF 'NSForegroundColorAttributeName: [DMStickyInk() colorWithAlphaComponent:0.75]' \
   && fnf '__attribute__((noinline)) static void DMStickyDrawName(NSString *name, CGRect bar) {' '$DN' | grep -qF 'CGRect r = CGRectMake(bar.origin.x + 8.0, bar.origin.y + floor((bar.size.height - lh) / 2.0), bar.size.width - 16.0, lh);'"
check "  ... the note typed in: its bar is a DMNoteBar with the name (given at the typing's begin), following the first line as it is typed" \
  "grep -qF '_band = [DMNoteBar new]; _band.backgroundColor = DMStickyColor(color, YES); [_band dm_setName:name];' '$DN' \
   && fnf '- (void)dm_noteBegin:(DMNoteView *)nv at:(CGPoint)sp {' '$DN' | grep -qF 'name:MSBDStickyNameShown(e[@\"name\"], e[@\"text\"]) target:self];' \
   && fnf '- (void)textViewDidChange:(UITextView *)tv {' '$DN' | grep -qF 'if (e) [_notes.editor.band dm_setName:MSBDStickyNameShown(e[@\"name\"], e[@\"text\"])];' \
   && cls DMNoteBar | grep -qF -e '- (void)drawRect:(CGRect)rect { if (!_nameHidden) DMStickyDrawName(_name, self.bounds); }'"
check "  ... hidden while the on-screen keyboard has lifted the note, as the grips (the bar's taps off too); a name being edited keeps its field" \
  "fnf '- (void)dm_noteFit {' '$DN' | grep -qF 'ed.barTap.enabled = !lifted; ed.band.nameHidden = lifted || _notes.nameField != nil;'"
# ---- the rename ----
check "the note's menu has Rename (beside Color, before Move to Trash), greyed where it cannot be typed in" \
  "fnf '- (UIMenu *)dm_noteMenuFor:(DMNoteView *)v {' '$DN' | grep -qF 'UIAction *rename = [UIAction actionWithTitle:@\"Rename\" image:[UIImage systemImageNamed:@\"pencil\"] identifier:nil handler:^(UIAction *x) { [ws dm_noteRename:noteId]; }];' \
   && fnf '- (UIMenu *)dm_noteMenuFor:(DMNoteView *)v {' '$DN' | grep -qF 'NSMutableArray *first = [NSMutableArray arrayWithObjects:color, rename, nil];' && fnf '- (UIMenu *)dm_noteMenuFor:(DMNoteView *)v {' '$DN' | grep -qF 'if (!DMStickyCanType()) rename.attributes = UIMenuElementAttributesDisabled;'"
RN=$(fnf '- (void)dm_noteRename:(NSString *)noteId {' "$DN")
check "  ... Rename: an idle note's typing begins first; a field over the bar with the name shown, selected, the notes' state its delegate" \
  "printf '%s\n' \"\$RN\" | grep -qF '[self dm_noteBegin:v at:CGPointMake(NAN, NAN)];' && printf '%s\n' \"\$RN\" | grep -qF 'tf.text = MSBDStickyNameShown(e[@\"name\"], ed.textView.text ?: e[@\"text\"]);' \
   && printf '%s\n' \"\$RN\" | grep -qF 'tf.delegate = _notes;' && printf '%s\n' \"\$RN\" | grep -qF '[ed.band addSubview:tf];' && printf '%s\n' \"\$RN\" | grep -qF '[tf selectAll:nil];' \
   && printf '%s\n' \"\$RN\" | grep -qF 'DMNoteNameField *tf = [[DMNoteNameField alloc] initWithFrame:DMStickyFrame(MSBDStickyNameFieldRect(ed.band.bounds), \"the name field made\")];'"   # (its frame's rule: test-stickygeometry)
RE=$(fnf '- (void)dm_noteRenameEnd:(BOOL)keep refocus:(BOOL)refocus {' "$DN")
check "  ... its end: the typed name is the note's own (blank: back to the default; the same as shown: no change), saved; the text has the typing again" \
  "printf '%s\n' \"\$RE\" | grep -qF 'NSString *now = !typed ? nil : [typed isEqualToString:MSBDStickyNameShown(own, text)] ? own : typed;' \
   && printf '%s\n' \"\$RE\" | grep -qF 'if (now) e[@\"name\"] = now; else [e removeObjectForKey:@\"name\"];' && printf '%s\n' \"\$RE\" | grep -qF 'DMStickyChanged(0.3);' \
   && printf '%s\n' \"\$RE\" | grep -qF 'if (refocus && ed.superview && !ed.textView.isFirstResponder) [ed.textView becomeFirstResponder];' && printf '%s\n' \"\$RE\" | grep -qF '_notes.nameField = nil; tf.delegate = nil;'"
check "  ... Return keeps it, a tap in the text or the typing's end keeps it, Esc keeps the old one (the desktop's keys come first)" \
  "cls DMNotesState | grep -qF 'textFieldShouldReturn:(UITextField *)tf { if (tf == _nameField) [_desk dm_noteRenameEnd:YES refocus:YES]; return NO; }' \
   && cls DMNotesState | grep -qF 'textFieldDidEndEditing:(UITextField *)tf { if (tf == _nameField) [_desk dm_noteRenameEnd:YES refocus:NO]; }' \
   && fnf '- (void)dm_noteEnd:(NSString *)why {' '$DN' | awk '/if \\(!ed\\) return;/{a=NR} /\\[self dm_noteRenameEnd:YES refocus:NO\\];/{b=NR} /_notes.editor = nil;/{c=NR} END{exit !(a && b == a + 1 && c == b + 1)}' \
   && fnf '- (BOOL)dm_noteKey:(UIKey *)key {' '$DN' | grep -qF 'if (key.keyCode == UIKeyboardHIDUsageKeyboardEscape && m == 0) { [self dm_noteRenameEnd:NO refocus:YES]; return YES; }' \
   && fnf '- (BOOL)dm_noteKey:(UIKey *)key {' '$DN' | awk '/if \\(_notes.nameField\\) \\{/{a=NR} /\\[self dm_noteEnd:@\"Esc\"\\]/{b=NR} END{exit !(a && b > a)}'"
check "  ... a double click or tap on the bar of the note typed in: a tap on the editor's bar within the double tap time of the one before" \
  "grep -qF '_barTap = [[UITapGestureRecognizer alloc] initWithTarget:target action:@selector(dm_noteBarTap:)];' '$DN' && grep -qF '_barTap.name = @\"dm.note.bartap\";' '$DN' \
   && fnf '- (void)dm_noteBarTap:(UITapGestureRecognizer *)g {' '$DN' | grep -qF 'BOOL twice = MSBDStickyBarTwice(_notes.barTapId, ed.noteId, now - _notes.barTapAt);' \
   && fnf '- (void)dm_noteBarTap:(UITapGestureRecognizer *)g {' '$DN' | grep -qF 'if (twice) [self dm_noteRename:ed.noteId];' && ! grep -qE 'barTapAt < 0\.[0-9]' '$DN'"
IB=$(fnf '- (void)dm_noteIdleBarTap:(DMNoteView *)v {' "$DN"); BO=$(fnf '- (void)dm_noteBarOnce:(NSString *)noteId at:(CFTimeInterval)at front:(NSString *)front {' "$DN")
check "  ... and of an idle note: a tap on its bar does not begin the typing (-dm_noteIdleBarTap:, after the press's own checks); the second within the time renames it" \
  "fnf '- (void)dm_noteTap:(UITapGestureRecognizer *)g {' '$DN' | grep -qF 'if (MSBDStickyOnBar(v.frame, [v.superview convertPoint:p fromView:other ? g.view : self])) { [self dm_noteIdleBarTap:v]; return; }' \
   && fnf '- (void)dm_noteTap:(UITapGestureRecognizer *)g {' '$DN' | awk '/if \\(!MSBDStickyPressTypes\\(/{a=NR} /dm_noteIdleBarTap:v\\]; return; \\}/{b=NR} /\\[self dm_noteBegin:v at:up\\];/{c=NR} END{exit !(a && b > a && c == b + 1)}' \
   && printf '%s\n' \"\$IB\" | grep -qF 'if (MSBDStickyBarTwice(_notes.barTapId, v.noteId, now - _notes.barTapAt)) {' && printf '%s\n' \"\$IB\" | grep -qF '[self dm_noteRename:v.noteId];' \
   && ! printf '%s\n' \"\$IB\" | grep -qF 'dm_noteBegin'"
check "  ... a single one: the typing begins after MSBD_NOTE_BAR_TWICE, only by MSBDStickyBarOnceTypes (still the last bar tap, no touch since, the same app in front, no typing yet)" \
  "printf '%s\n' \"\$IB\" | grep -qF '_notes.barTapId = v.noteId; _notes.barTapAt = now;' && printf '%s\n' \"\$IB\" | grep -qF '(int64_t)(MSBD_NOTE_BAR_TWICE * NSEC_PER_SEC)' \
   && printf '%s\n' \"\$IB\" | grep -qF '[ws dm_noteBarOnce:noteId at:now front:front];' \
   && printf '%s\n' \"\$BO\" | grep -qF 'BOOL mine = _notes.barTapAt == at && [_notes.barTapId isEqualToString:noteId];' \
   && printf '%s\n' \"\$BO\" | grep -qF 'if (!MSBDStickyBarOnceTypes(mine, _touchBeganAt > at, [[DMActiveApp() bundleIdentifier] ?: @\"\" isEqualToString:front], _notes.editor != nil)) {' \
   && printf '%s\n' \"\$BO\" | grep -qF 'if (v) [self dm_noteBegin:v at:CGPointMake(NAN, NAN)];' \
   && grep -qF '            _touchBeganAt = CACurrentMediaTime();' '$D' && grep -qF 'CFTimeInterval _touchBeganAt;' '$D'"
# ---- the Trash ----
TR=$(fnf '__attribute__((noinline)) static void DMStickyTrash(NSMutableDictionary *e) {' "$DN")
check "Move to Trash: the file is named after the note (MSBDStickyTrashFileName, numbered by Finder's Trash), its own name as an attribute, none for a default name" \
  "printf '%s\n' \"\$TR\" | grep -qF 'NSString *fileName = MSBDStickyTrashFileName(MSBDStickyNameShown(e[@\"name\"], text)), *own = MSBDStickyNameClean(e[@\"name\"])' \
   && printf '%s\n' \"\$TR\" | grep -qF 'dst = DMFinderFreeName(kFinderTrash, fileName, @\"\");' \
   && printf '%s\n' \"\$TR\" | grep -qF 'if (ok && own) ok = setxattr(tmp.fileSystemRepresentation, MSBD_NOTE_TRASH_NAME_ATTR, own.UTF8String, strlen(own.UTF8String), 0, XATTR_NOFOLLOW) == 0;' \
   && grep -qxF '#define MSBD_NOTE_TRASH_NAME_ATTR \"com.besiktasliseba.stickynote.name\"   // (... and a note'\"'\"'s own name, 1.8.8.2 F37: Put Back gives it back; never its text)' '$N'"
PB=$(fnf '__attribute__((noinline)) static void DMStickyPutBack(NSString *path, void (^done)(NSError *e)) {' "$DN")
check "  ... Put Back and Undo give the note its own name back (read as a typed name is kept); a 1.8.8.1 file has none: the default" \
  "printf '%s\n' \"\$PB\" | grep -qF 'NSString *ownName = nn > 0 ? MSBDStickyNameClean([[NSString alloc] initWithBytes:nb length:(NSUInteger)nn encoding:NSUTF8StringEncoding]) : nil;' \
   && printf '%s\n' \"\$PB\" | grep -qF 'if (ownName) e[@\"name\"] = ownName;'"
check "  ... Get Info of that file: its name, from the desktop (sticky note), as before; the debug purge finds test notes' files by the origin marker" \
  "grep -qF '[origin isEqualToString:MSBD_NOTE_TRASH_ORIGIN] ? @\"the desktop (sticky note)\"' '$FI' && fnf '- (void)dm_noteDebug:(NSString *)arg {' '$DN' | grep -qF 'if (![DMFinderOrigin(p) isEqualToString:MSBD_NOTE_TRASH_ORIGIN]) continue;'"
# ---- privacy: a name is user content, as the text ----
python3 - "$DN" > "$W/namelog.txt" 2>&1 <<'PY' || true
import re, sys
bad = []
for n, l in enumerate(open(sys.argv[1]), 1):
    if 'DMLog(' not in l: continue
    x = l.replace('[nm hasPrefix:@"MSB-TEST"]', '').replace('[NSString stringWithFormat:@", name \\"%@\\", text %@", nm, t]', '')   # (the debug state: test notes only)
    x = re.sub(r'@"(\\.|[^"\\])*"', '@""', x)   # (string literals: constant words)
    x = x.replace('.text.length', '').replace('e[@"name"] ? @"" : @""', '').replace('now ? @"" : @""', '')
    if re.search(r'\b(nm|own|ownName|typed|now|name|_name|shown)\b|e\[@"name"\]|tf\.text\b|MSBDStickyNameShown\(', x): bad.append('%d: %s' % (n, l.strip()[:160]))
if bad: print('\n'.join(bad))
sys.exit(1 if bad else 0)
PY
check "no log line prints a note's name (lengths only; the debug state names MSB-TEST notes only)" "[ ! -s '$W/namelog.txt' ]"
[ -s "$W/namelog.txt" ] && sed 's/^/        /' "$W/namelog.txt"
[ $fails = 0 ] && echo "test-stickyname: all passed" || echo "test-stickyname: FAILED"
exit $fails
