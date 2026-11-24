// DesktopNotes.h -- Sticky Notes on the desktop (1.8.8.1, sticky-notes.md Design v2 with the check's fixes 1-7), included at the end of Desktop.h.
// The rules (colours, frames, the store's read rule, the caps) are common/StickyNotes.h, tested on the Mac (tools/test-stickynotes.sh).
//  - A note lives on Home Screen page 1, in a layer of the desktop's under every icon: behind the app windows, the app icons, widgets and page dots
//    (it keeps clear of them, they take its touches), on every Mac Switcher desktop, hidden in jiggle mode and Guided Access with the desktop.
//    1.8.8.2 F36: or on another Home Screen page (its "page" key: iPadOS's own page id), in a layer of that page's (DMNotesPageView, made only for a
//    page that holds notes), clear of that page's icons; dragged to the screen's side and held there, it turns the page and goes along; its menu's
//    Move to Page takes it there with no drag, the Home Screen turning to that page. A removed page's notes show on page 1, their key kept; a
//    hidden page's notes hide with it and are back when it is shown again (KT 22 Nov).
//    Desktop icons keep clear of notes (DesktopPlace.h's soft rects) and keep their saved places for when the note moves away.
//  - The empty desktop's menu has New Sticky Note. A tap on a note types in it: it lifts into the desktop's typing window (Desktop.h, the one a name
//    is typed in), above the windows and the Dock, with the keyboard, both bottom-corner resize grips (the windows' maths, NativeWindow.h
//    DMNativeResized) and the Command editing keys (TextWindow.h DMTextViewEditKey). A touch elsewhere, Esc, the screen going off, a lock, the Cover
//    Sheet, another app in front, a native window made active, the Mac Switcher, jiggle mode, page 1 going and the switches end the typing; every
//    way saves, gives back the focus lock and the key window, and shows the note at its own place. The keyboard's hide key leaves it active.
//  - Idle, a finger held 0.3 s then moved drags it like an icon (a pointer at once); held still, or a right click, opens its menu: Color, Move to
//    Trash. (1.8.8.2 B78: its top bar is the handle -- a press there drags at once, also while it is typed in; elsewhere a finger is held 0.2 s,
//    the note lifting to show it; a press that moved never types.) The bar shows the note's name (1.8.8.2 F37: its own, else its text's first line,
//    else "Sticky Note"): a double click or tap on the bar, or Rename in its menu, edits it in the bar. With text, Move to Trash makes "<its name>.txt" in Finder's Trash (0600, data protection class C; 1.8.8.1: "Sticky Note.txt"); Put Back and Undo make it a note again.
//  - The store is SpringBoard's own file on the Data volume, NSHomeDirectory()/Library/Application Support/MacStatusBarAndDock/StickyNotes.plist
//    (folder 0700, file 0600, class C): never CFPreferences, never /var/jb, never On My iPad. It is never written before a read worked or found no
//    file, never over a newer release's store (StickyNotes.h MSBDStickyStoreRead).
//  - Privacy: a note's text is never logged, put in a record, a key, a name, a title or a message. Logs carry a note's short id, counts and lengths.
//    The views never print it: DMNoteView keeps it in an ivar (no -text, which UIView's description reads), DMNoteTextView's descriptions give its
//    length only (UIKit's print "text = '...'", sticky-notes.md Design v2 1.3).
//  - Crash guard: everything here is the stickyNotes target (tools/crashmap-rules.txt: DMSticky..., MSBDSticky..., these classes, this file) -- a
//    crash in note code turns Show Sticky Notes off, never the whole desktop. So every C function here is out of line and named DMSticky..., never
//    DMDesktop... (the desktop's rule) nor DMNote... (DMNoteAppExit and others of that name are not the notes').
#include "../common/StickyNotes.h"

// ---- the store: one per SpringBoard, apart from the desktop view (Finder's Put Back works with the desktop off). Main thread, its file on a queue ----
static NSMutableArray<NSMutableDictionary *> *gNotes;   // (the notes shown, in stacking order: last on top)
static NSArray *gNotesKept;                              // (stored past the cap of 30: written back as they were)
static MSBDStickyStatus gNotesStatus = MSBDStickyUnread;
static BOOL gNotesRead, gNotesReading;
static CFTimeInterval gNotesTriedAt;
static NSUInteger gNotesGen, gNotesWrittenGen;          // (every change: a save waits for its own generation to be the last, DMStickyChanged; the last one written)
static NSMutableArray<void (^)(void)> *gNotesWaiting;   // (asked while a read is on its way)
__attribute__((noinline)) static dispatch_queue_t DMStickyQueue(void) {
    static dispatch_queue_t q; static dispatch_once_t once;
    dispatch_once(&once, ^{ q = dispatch_queue_create("com.besiktasliseba.stickynotes", DISPATCH_QUEUE_SERIAL); });
    return q;
}
__attribute__((noinline)) static NSString *DMStickyFolder(void) { return [NSHomeDirectory() stringByAppendingPathComponent:@"Library/Application Support/MacStatusBarAndDock"]; }
__attribute__((noinline)) static NSString *DMStickyPath(void) { return [DMStickyFolder() stringByAppendingPathComponent:@"StickyNotes.plist"]; }
__attribute__((noinline)) static NSMutableDictionary *DMStickyEntry(NSString *noteId) {
    if (!noteId) return nil;
    for (NSMutableDictionary *e in gNotes) if ([e[@"id"] isEqualToString:noteId]) return e;
    return nil;
}
// A read refused by data protection (before the first unlock after a reboot with a passcode), by permissions, or by anything but "no file": the
// store is not readable yet. Read once, off the main thread, with no link followed and nothing over 8 MB taken (30 full notes are under 2 MB).
__attribute__((noinline)) static NSData *DMStickyReadFile(NSString *path, int *err) {
    *err = 0;
#if DEBUG
    if (DMTestFlag("/tmp/msb-notes-unreadable")) { *err = EPERM; return nil; }   // (debug: as before the first unlock -- device row F12)
#endif
    int fd = open(path.fileSystemRepresentation, O_RDONLY | O_NOFOLLOW | O_CLOEXEC);
    if (fd < 0) { *err = errno; return nil; }
    struct stat st;
    if (fstat(fd, &st) != 0 || !S_ISREG(st.st_mode) || st.st_size > 8 * 1024 * 1024) { *err = 0; close(fd); return [NSData data]; }   // (no store: put aside)
    NSMutableData *d = [NSMutableData dataWithLength:(NSUInteger)st.st_size];
    ssize_t got = 0;
    while (got < st.st_size) { ssize_t n = read(fd, (char *)d.mutableBytes + got, (size_t)(st.st_size - got)); if (n <= 0) break; got += n; }
    int e = got == st.st_size ? 0 : errno ?: EIO;
    close(fd);
    if (e) { *err = e; return nil; }
    return d;
}
// A file that is not a store goes aside, never overwritten (StickyNotes-unreadable.plist, then "... 2"...): NO when it could not be moved -- the
// store is then left alone as unreadable.
__attribute__((noinline)) static BOOL DMStickyPutAside(NSString *path) {
    NSString *dir = path.stringByDeletingLastPathComponent;
    for (int n = 1; n < 1000; n++) {
        NSString *to = [dir stringByAppendingPathComponent:MSBDStickyAsideName(n)];
        struct stat st; if (lstat(to.fileSystemRepresentation, &st) == 0) continue;
        return rename(path.fileSystemRepresentation, to.fileSystemRepresentation) == 0;
    }
    return NO;
}
static void DMStickyStoreChangedForDesktop(void);   // (below: the desktop shows the notes as they are now)
static void DMStickyTrash(NSMutableDictionary *e);   // (below, with Put Back)
// The store read (once; again while not readable yet): `done` runs on the main thread when it has been tried.
__attribute__((noinline)) static void DMStickyLoad(void (^done)(void)) {
    if (gNotesRead && gNotesStatus != MSBDStickyUnread) { if (done) done(); return; }
    if (!gNotesWaiting) gNotesWaiting = [NSMutableArray array];
    if (done) [gNotesWaiting addObject:[done copy]];
    if (gNotesReading) return;
    gNotesReading = YES; gNotesTriedAt = CACurrentMediaTime();
    dispatch_async(DMStickyQueue(), ^{
        NSString *path = DMStickyPath();
        int err = 0; NSData *data = DMStickyReadFile(path, &err);
        NSMutableArray *shown = [NSMutableArray array], *kept = [NSMutableArray array]; int skipped = 0;
        MSBDStickyStatus st = MSBDStickyStoreRead(data, err, shown, kept, &skipped);
        if (st == MSBDStickyAside && !DMStickyPutAside(path)) st = MSBDStickyUnread;   // (it could not be put aside: never written over)
        dispatch_async(dispatch_get_main_queue(), ^{
            gNotesReading = NO; gNotesRead = YES; gNotesStatus = st;
            gNotes = MSBDStickyWritable(st) ? shown : [NSMutableArray array];
            gNotesKept = MSBDStickyWritable(st) ? kept : nil;
            DMLog([NSString stringWithFormat:@"[notes] the store read: %@ (errno %d), %lu note(s), %lu kept past the cap, %d entr%@ skipped", MSBDStickyStatusName(st), err,
                   (unsigned long)gNotes.count, (unsigned long)gNotesKept.count, skipped, skipped == 1 ? @"y" : @"ies"]);
            NSArray *waiting = gNotesWaiting; gNotesWaiting = nil;
            for (void (^b)(void) in waiting) b();
            DMStickyStoreChangedForDesktop();
        });
    });
}
// The whole store written on the queue: a temp file made 0600 with data protection class C (readable after the first unlock, while locked too),
// then rename(2) over the old one. The folder is made 0700.
__attribute__((noinline)) static BOOL DMStickyWriteFile(NSData *data) {
    if (!data) return NO;
    NSFileManager *fm = [NSFileManager defaultManager];
    NSString *dir = DMStickyFolder(), *path = DMStickyPath(), *tmp = [dir stringByAppendingPathComponent:@".StickyNotes.plist.new"];
    struct stat st;
    if (lstat(dir.fileSystemRepresentation, &st) != 0) [fm createDirectoryAtPath:dir withIntermediateDirectories:YES attributes:@{NSFilePosixPermissions: @0700} error:nil];
    if (lstat(dir.fileSystemRepresentation, &st) != 0 || !S_ISDIR(st.st_mode)) return NO;   // (never through a link)
    if ((st.st_mode & 0777) != 0700) chmod(dir.fileSystemRepresentation, 0700);
    unlink(tmp.fileSystemRepresentation);
    BOOL ok = [fm createFileAtPath:tmp contents:data attributes:@{NSFilePosixPermissions: @0600, NSFileProtectionKey: NSFileProtectionCompleteUntilFirstUserAuthentication}];
    if (ok) ok = rename(tmp.fileSystemRepresentation, path.fileSystemRepresentation) == 0;
    if (!ok) unlink(tmp.fileSystemRepresentation);
    return ok;
}
// Now: the notes as they are, written (on the queue, after any write before it). `then` on the main thread with whether it was written.
__attribute__((noinline)) static void DMStickyWriteNow(void (^then)(BOOL ok)) {
    if (!gNotesRead || !MSBDStickyWritable(gNotesStatus)) { if (then) then(NO); return; }   // (never before a read worked, never over an unread or newer store)
    NSData *data = MSBDStickyStoreBuild(gNotes, gNotesKept);   // (a copy made here, on the main thread: the queue never sees the notes change under it)
    gNotesWrittenGen = gNotesGen;
    NSUInteger n = gNotes.count;
    dispatch_async(DMStickyQueue(), ^{
        BOOL ok = DMStickyWriteFile(data);
        dispatch_async(dispatch_get_main_queue(), ^{
            if (ok && gNotesStatus != MSBDStickyOK) gNotesStatus = MSBDStickyOK;
            DMLog([NSString stringWithFormat:@"[notes] the store written: %@ (%lu note(s), %lu bytes)", ok ? @"yes" : @"FAILED", (unsigned long)n, (unsigned long)data.length]);
            if (then) then(ok);
        });
    });
}
// A change to save: after `delay` seconds without another (the text 1 s after typing stops, a look, place or size 0.3 s; 0 at the end of typing).
__attribute__((noinline)) static void DMStickyChanged(double delay) {
    if (!gNotesRead || !MSBDStickyWritable(gNotesStatus)) return;
    NSUInteger gen = ++gNotesGen;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(delay * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{ if (gen == gNotesGen) DMStickyWriteNow(nil); });
}

// ---- the geometry the notes give their views (1.8.8.2) ----
// Every frame, centre, transform and inset the notes' code sets goes through these, and every view it makes gets its frame through DMStickyFrame
// (CGRectZero aside): a value with a NaN or an infinity in it (StickyNotes.h MSBDStickyRectOK, MSBDStickyPointOK, MSBDStickyTransformOK) is refused,
// the view left as it was. A DEBUG build says so in its log, naming the value and the site (an assertion: the device rows look for that line); it
// never raises: a raise here stopped SpringBoard (Safe Mode) and the device pass with it, for a value the release build only skips -- such as the
// notes made while the desktop was not on its page yet, before -dm_area gave it a finite area (1.8.8.2's review). (1.8.8.2's test build: a name
// field made from a bar not laid out yet had an infinite origin, and UIKit's selection grabbers over it got a NaN position; SpringBoard raised
// inside UIKit, far from the cause.)
__attribute__((noinline)) static void DMStickyGeometryRefused(const char *site, NSString *value) {
#if DEBUG
    DMLog([NSString stringWithFormat:@"[notes] ASSERTION: a geometry that is not finite (%@) refused at %s", value, site]);
#else
    (void)site; (void)value;
#endif
}
__attribute__((noinline)) static void DMStickySetFrame(UIView *v, CGRect f, const char *site) { if (MSBDStickyRectOK(f)) v.frame = f; else DMStickyGeometryRefused(site, NSStringFromCGRect(f)); }
__attribute__((noinline)) static CGRect DMStickyFrame(CGRect f, const char *site) { if (MSBDStickyRectOK(f)) return f; DMStickyGeometryRefused(site, NSStringFromCGRect(f)); return CGRectZero; }   // (a view made with a frame)
__attribute__((noinline)) static void DMStickySetCenter(UIView *v, CGPoint c, const char *site) { if (MSBDStickyPointOK(c)) v.center = c; else DMStickyGeometryRefused(site, NSStringFromCGPoint(c)); }
__attribute__((noinline)) static void DMStickySetTransform(UIView *v, CGAffineTransform t, const char *site) { if (MSBDStickyTransformOK(t)) v.transform = t; else DMStickyGeometryRefused(site, NSStringFromCGAffineTransform(t)); }
__attribute__((noinline)) static void DMStickySetBottomInset(UIScrollView *v, CGFloat bottom, const char *site) {
    if (!isfinite(bottom)) { DMStickyGeometryRefused(site, [NSString stringWithFormat:@"bottom inset %f", bottom]); return; }
    UIEdgeInsets i = v.contentInset; i.bottom = bottom; v.contentInset = i;
}

// ---- the views ----
__attribute__((noinline)) static UIColor *DMStickyColor(int i, BOOL band) {
    int k = i >= 0 && i < MSBD_NOTE_COLORS ? i : 0; CGFloat r, g, b;
    MSBDStickyRGB(band ? kMSBDStickyColors[k].band : kMSBDStickyColors[k].body, &r, &g, &b);
    return [UIColor colorWithRed:r green:g blue:b alpha:1];
}
__attribute__((noinline)) static UIColor *DMStickyInk(void) { return [UIColor colorWithRed:0x1E / 255.0 green:0x1E / 255.0 blue:0x1E / 255.0 alpha:1]; }   // (near black on every colour, both appearances)
__attribute__((noinline)) static UIFont *DMStickyFont(void) { return [UIFont systemFontOfSize:16.0]; }
static const CGFloat kDMNoteCorner = 4.0, kDMNoteSide = 8.0, kDMNoteUnderBand = 6.0, kDMNoteGrip = 22.0;
// The name in a note's top bar (1.8.8.2 F37): 12 pt semibold in the ink at 75 %, centred, cut with an ellipsis -- the same on every colour (all six
// bars are light) and in Dark mode (a note is paper, as on a Mac).
__attribute__((noinline)) static UIFont *DMStickyNameFont(void) { return [UIFont systemFontOfSize:12.0 weight:UIFontWeightSemibold]; }
__attribute__((noinline)) static void DMStickyDrawName(NSString *name, CGRect bar) {
    if (!name.length || bar.size.width < 24.0) return;
    NSMutableParagraphStyle *ps = [NSMutableParagraphStyle new]; ps.alignment = NSTextAlignmentCenter; ps.lineBreakMode = NSLineBreakByTruncatingTail;
    UIFont *f = DMStickyNameFont();
    CGFloat lh = ceil(f.lineHeight);
    CGRect r = CGRectMake(bar.origin.x + 8.0, bar.origin.y + floor((bar.size.height - lh) / 2.0), bar.size.width - 16.0, lh);
    [name drawInRect:r withAttributes:@{NSFontAttributeName: f, NSForegroundColorAttributeName: [DMStickyInk() colorWithAlphaComponent:0.75], NSParagraphStyleAttributeName: ps}];
}
// The idle note: drawn, not a text view (one UITextView only, the note being typed in: memory, and no UIKit description that prints its text).
@interface DMNoteView : UIView
@property (nonatomic, copy) NSString *noteId;
@property (nonatomic) int colorIndex;
- (void)dm_setBody:(NSString *)body;
- (void)dm_setName:(NSString *)name;   // (the name its bar shows, 1.8.8.2 F37)
- (NSUInteger)dm_bodyLength;
@end
@implementation DMNoteView { NSString *_body, *_name; }   // (ivars: no method named text -- UIView's own description reads one)
- (instancetype)initWithFrame:(CGRect)frame {
    if (!(self = [super initWithFrame:frame])) return nil;
    self.opaque = NO; self.backgroundColor = [UIColor clearColor]; self.contentMode = UIViewContentModeRedraw;
    self.layer.shadowColor = [UIColor blackColor].CGColor; self.layer.shadowOpacity = 0.25; self.layer.shadowRadius = 6.0; self.layer.shadowOffset = CGSizeMake(0, 3);
    self.isAccessibilityElement = YES;
    _body = @"";
    return self;
}
- (void)dm_setBody:(NSString *)body { NSString *b = MSBDStickyTextCut(body, MSBD_NOTE_TEXT_MAX); if ([b isEqualToString:_body]) return; _body = b; [self setNeedsDisplay]; }
- (void)dm_setName:(NSString *)name { if ([name isEqualToString:_name] || (!name && !_name)) return; _name = [name copy]; [self setNeedsDisplay]; }
- (NSUInteger)dm_bodyLength { return _body.length; }
- (void)setColorIndex:(int)i { if (i == _colorIndex) return; _colorIndex = i; [self setNeedsDisplay]; }
- (void)layoutSubviews { [super layoutSubviews]; self.layer.shadowPath = [UIBezierPath bezierPathWithRoundedRect:self.bounds cornerRadius:kDMNoteCorner].CGPath; }
- (void)drawRect:(CGRect)rect {
    CGRect b = self.bounds;
    UIBezierPath *paper = [UIBezierPath bezierPathWithRoundedRect:b cornerRadius:kDMNoteCorner];
    [DMStickyColor(_colorIndex, NO) setFill]; [paper fill];
    CGContextRef c = UIGraphicsGetCurrentContext();
    CGContextSaveGState(c); [paper addClip];
    [DMStickyColor(_colorIndex, YES) setFill]; UIRectFill(MSBDStickyBarRect(b));   // (the top bar, 1.8.8.2 B78)
    CGContextRestoreGState(c);
    DMStickyDrawName(_name, MSBDStickyBarRect(b));
    if (!_body.length) return;
    NSString *shown = _body.length > MSBD_NOTE_DRAW_MAX ? MSBDStickyTextCut(_body, MSBD_NOTE_DRAW_MAX) : _body;   // (cut off at the bottom, no scrolling)
    NSMutableParagraphStyle *ps = [NSMutableParagraphStyle new]; ps.lineBreakMode = NSLineBreakByWordWrapping;
    CGRect tr = CGRectMake(kDMNoteSide, MSBD_NOTE_BAR + kDMNoteUnderBand, b.size.width - 2 * kDMNoteSide, b.size.height - MSBD_NOTE_BAR - 2 * kDMNoteUnderBand);
    CGContextSaveGState(c); UIRectClip(tr);
    [shown drawWithRect:tr options:NSStringDrawingUsesLineFragmentOrigin attributes:@{NSFontAttributeName: DMStickyFont(), NSForegroundColorAttributeName: DMStickyInk(), NSParagraphStyleAttributeName: ps} context:nil];
    CGContextRestoreGState(c);
}
// (assistive features: one element -- "Sticky Note, Yellow", never its text; its value is the text, which VoiceOver has to read; using it types in it)
- (NSString *)accessibilityLabel { return [@"Sticky Note, " stringByAppendingString:MSBDStickyColorName(_colorIndex)]; }
- (NSString *)accessibilityValue { return _body; }
- (UIAccessibilityTraits)accessibilityTraits { return UIAccessibilityTraitButton; }
- (BOOL)accessibilityActivate { DMDesktop *d = gDesktop; return d && [d dm_noteAXActivate:self]; }   // (one of its notes, on any page: -dm_noteAXActivate:)
- (NSString *)description { return [NSString stringWithFormat:@"<%@: %p; %lu characters>", NSStringFromClass([self class]), self, (unsigned long)_body.length]; }
- (NSString *)debugDescription { return [self description]; }
@end
// The note's text view while it is typed in: UIKit's descriptions of a text view print its text, so these give its length only.
@interface DMNoteTextView : UITextView
@end
@implementation DMNoteTextView
- (NSString *)description { return [NSString stringWithFormat:@"<%@: %p; %lu characters>", NSStringFromClass([self class]), self, (unsigned long)self.text.length]; }
- (NSString *)debugDescription { return [self description]; }
@end
// The top bar of the note being typed in (1.8.8.2 B78 / F37): the band's colour, the name drawn (an ivar, as the idle note's), the move pan on it.
// The field its name is edited in is laid out by the bar itself, from its own bounds (StickyNotes.h MSBDStickyNameFieldRect), never autoresized
// from a frame made before the bar had one.
@interface DMNoteBar : UIView
@property (nonatomic) BOOL nameHidden;
@property (nonatomic, weak) UITextField *field;
- (void)dm_setName:(NSString *)name;
@end
@implementation DMNoteBar { NSString *_name; }
- (instancetype)initWithFrame:(CGRect)frame { if (!(self = [super initWithFrame:frame])) return nil; self.opaque = NO; self.contentMode = UIViewContentModeRedraw; return self; }
- (void)layoutSubviews { [super layoutSubviews]; UITextField *f = _field; if (f.superview == self) DMStickySetFrame(f, MSBDStickyNameFieldRect(self.bounds), "the name field in its bar"); }
- (void)dm_setName:(NSString *)name { if ([name isEqualToString:_name] || (!name && !_name)) return; _name = [name copy]; [self setNeedsDisplay]; }
- (void)setNameHidden:(BOOL)h { if (h == _nameHidden) return; _nameHidden = h; [self setNeedsDisplay]; }
- (void)drawRect:(CGRect)rect { if (!_nameHidden) DMStickyDrawName(_name, self.bounds); }
- (NSString *)description { return [NSString stringWithFormat:@"<%@: %p; %lu characters>", NSStringFromClass([self class]), self, (unsigned long)_name.length]; }
- (NSString *)debugDescription { return [self description]; }
@end
// The field a note's name is edited in, over its bar (1.8.8.2 F37): UIKit's descriptions of a text field print its text, so these give its length.
@interface DMNoteNameField : UITextField
@end
@implementation DMNoteNameField
- (NSString *)description { return [NSString stringWithFormat:@"<%@: %p; %lu characters>", NSStringFromClass([self class]), self, (unsigned long)self.text.length]; }
- (NSString *)debugDescription { return [self description]; }
@end
// The note being typed in, in the desktop's typing window: the paper, its top bar, the one text view, and two resize grips at the bottom corners as
// our windows have (NativeWindow.h: the pill turned 45 degrees, half outside the paper, 22 pt hot areas, pans named "dm.note.resize"). The bar moves
// it (1.8.8.2 B78: a pan named "dm.note.move", as the windows' title bar; the typing, the caret and the keyboard stay).
@interface DMNoteEditor : UIView
@property (nonatomic, copy) NSString *noteId;
@property (nonatomic, strong) DMNoteTextView *textView;
@property (nonatomic, strong) DMNoteBar *band;
@property (nonatomic, strong) UIView *gripL, *gripR;
@property (nonatomic, strong) UIPanGestureRecognizer *movePan;
@property (nonatomic, strong) UITapGestureRecognizer *barTap;   // (a tap on the bar: twice, its name is edited -- 1.8.8.2 F37)
@property (nonatomic) BOOL placed;
- (instancetype)initWithFrame:(CGRect)frame color:(int)color text:(NSString *)text name:(NSString *)name target:(id)target;
@end
@implementation DMNoteEditor
- (instancetype)initWithFrame:(CGRect)frame color:(int)color text:(NSString *)text name:(NSString *)name target:(id)target {
    if (!(self = [super initWithFrame:frame])) return nil;
    self.backgroundColor = DMStickyColor(color, NO);
    self.layer.cornerRadius = kDMNoteCorner; self.layer.cornerCurve = kCACornerCurveContinuous;
    self.layer.shadowColor = [UIColor blackColor].CGColor; self.layer.shadowOpacity = 0.35; self.layer.shadowRadius = 18.0; self.layer.shadowOffset = CGSizeMake(0, 10);   // (the native windows' shadow: lifted)
    _band = [DMNoteBar new]; _band.backgroundColor = DMStickyColor(color, YES); [_band dm_setName:name];
    _band.layer.cornerRadius = kDMNoteCorner; _band.layer.maskedCorners = kCALayerMinXMinYCorner | kCALayerMaxXMinYCorner;
    _movePan = [[UIPanGestureRecognizer alloc] initWithTarget:target action:@selector(dm_noteMove:)];
    _movePan.name = @"dm.note.move"; _movePan.maximumNumberOfTouches = 1;
    [_band addGestureRecognizer:_movePan];
    _barTap = [[UITapGestureRecognizer alloc] initWithTarget:target action:@selector(dm_noteBarTap:)];
    _barTap.name = @"dm.note.bartap";
    [_band addGestureRecognizer:_barTap];
    [self addSubview:_band];
    _textView = [[DMNoteTextView alloc] initWithFrame:CGRectZero];
    _textView.backgroundColor = [UIColor clearColor];
    _textView.font = DMStickyFont(); _textView.textColor = DMStickyInk(); _textView.tintColor = DMStickyInk();
    _textView.textContainerInset = UIEdgeInsetsMake(kDMNoteUnderBand, kDMNoteSide, kDMNoteUnderBand, kDMNoteSide);
    _textView.textContainer.lineFragmentPadding = 0;   // (where the idle note draws it: no jump between the two)
    _textView.keyboardAppearance = UIKeyboardAppearanceLight;
    _textView.text = text ?: @"";
    _textView.accessibilityLabel = [@"Sticky Note, " stringByAppendingString:MSBDStickyColorName(color)];
    [self addSubview:_textView];
    for (int side = 0; side < 2; side++) {
        UIView *g = DMMakeResizeGrip();
        DMStickySetTransform(g, CGAffineTransformMakeRotation(side == 0 ? -M_PI_4 : M_PI_4), "a grip's turn");
        g.backgroundColor = DMResizeGripColor(NO);   // (the paper is always light)
        UIView *hot = [[UIView alloc] initWithFrame:DMStickyFrame(CGRectMake(0, 0, kDMNoteGrip, kDMNoteGrip), "a grip's hot area")];
        hot.tag = side;
        [hot addSubview:g]; DMStickySetCenter(g, CGPointMake(kDMNoteGrip / 2.0, kDMNoteGrip / 2.0), "a grip in its hot area");
        UIPanGestureRecognizer *rs = [[UIPanGestureRecognizer alloc] initWithTarget:target action:@selector(dm_noteResize:)];
        rs.name = @"dm.note.resize"; rs.maximumNumberOfTouches = 1;
        [hot addGestureRecognizer:rs];
        [self addSubview:hot];
        if (side == 0) _gripL = hot; else _gripR = hot;
    }
    return self;
}
- (void)layoutSubviews {
    [super layoutSubviews];
    CGRect b = self.bounds;
    self.layer.shadowPath = [UIBezierPath bezierPathWithRoundedRect:b cornerRadius:kDMNoteCorner].CGPath;
    DMStickySetFrame(_band, MSBDStickyBarRect(b), "the editor's bar");
    DMStickySetFrame(_textView, CGRectMake(0, MSBD_NOTE_BAR, b.size.width, MAX(0.0, b.size.height - MSBD_NOTE_BAR)), "the editor's text");
    DMStickySetFrame(_gripL, CGRectMake(-kDMNoteGrip / 2.0 + 6.0, b.size.height - kDMNoteGrip / 2.0 - 6.0, kDMNoteGrip, kDMNoteGrip), "the editor's left grip");
    DMStickySetFrame(_gripR, CGRectMake(b.size.width - kDMNoteGrip / 2.0 - 6.0, b.size.height - kDMNoteGrip / 2.0 - 6.0, kDMNoteGrip, kDMNoteGrip), "the editor's right grip");
}
// (the grips' halves outside the paper take their touches too, as a native window's: NativeWindow.h -dm_takesPoint:, the check's item 5)
- (BOOL)pointInside:(CGPoint)q withEvent:(UIEvent *)e { return CGRectContainsPoint(self.bounds, q) || (!_gripL.hidden && CGRectContainsPoint(_gripL.frame, q)) || (!_gripR.hidden && CGRectContainsPoint(_gripR.frame, q)); }
- (NSString *)description { return [NSString stringWithFormat:@"<%@: %p; %lu characters>", NSStringFromClass([self class]), self, (unsigned long)_textView.text.length]; }
- (NSString *)debugDescription { return [self description]; }
@end
// A Home Screen page's own layer of notes (1.8.8.2 F36): at the back of that page's icon list, its page's frame; only a note takes a touch here (the
// page's empty space and its app icons stay iPadOS's). Its tap is "dm.note.tap", judged as the desktop's.
@interface DMNotesPageView : UIView
@property (nonatomic, copy) NSString *pageId;
@end
@implementation DMNotesPageView
- (UIView *)hitTest:(CGPoint)p withEvent:(UIEvent *)e {
    if (self.hidden || self.alpha < 0.01 || !self.userInteractionEnabled) return nil;
    for (UIView *v in [self.subviews reverseObjectEnumerator]) if ([v isKindOfClass:[DMNoteView class]] && !v.hidden && v.alpha > 0.01 && CGRectContainsPoint(v.frame, p)) return v;
    return nil;
}
@end
// The desktop's notes: their layer, their views, the note under a press, the note being typed in. Its name's field's delegate (1.8.8.2 F37).
@interface DMNotesState : NSObject <UITextFieldDelegate>
@property (nonatomic, weak) DMDesktop *desk;
@property (nonatomic, strong) UIView *layer;
@property (nonatomic, strong) NSMutableDictionary<NSString *, DMNoteView *> *views;
@property (nonatomic, weak) DMNoteView *track;          // (the note a press on the desktop began on, -dm_event:)
@property (nonatomic) BOOL trackBar;                    // (... on its top bar: the note's from the touch down, 1.8.8.2 B78)
@property (nonatomic, weak) DMNoteView *cued;           // (lifted as a held finger's cue, 0.2 s in: back when the press ends without a drag)
@property (nonatomic, weak) UITouch *tapTouch;          // (the desktop tap's touch: the press it ends is the one -dm_event: followed when it is that touch)
@property (nonatomic) CFTimeInterval tapDownAt;         // (... when it went down)
@property (nonatomic) CGPoint tapDown;                  // (... and where, screen points)
@property (nonatomic, weak) DMNoteView *dragging;       // (... held and moved: it follows the finger, over the icons)
@property (nonatomic) CGPoint grab;
@property (nonatomic, strong) DMNoteEditor *editor;     // (the note being typed in)
@property (nonatomic, copy) NSString *editFront;        // (the app in front when its typing began: another one ends it)
@property (nonatomic, weak) UIWindow *keyBefore;
@property (nonatomic) CGRect home, resizeStart;         // (screen points: the note's own place; the editor's frame as a resize began)
@property (nonatomic) BOOL resizing;                    // (a grip or the bar is being pulled: the keyboard's moves leave the editor where the finger has it)
@property (nonatomic, strong) DMNoteNameField *nameField;   // (the note's name being edited in its bar, 1.8.8.2 F37)
@property (nonatomic, copy) NSString *barTapId;         // (... and the last tap on a note's bar: which note, when -- a second soon after edits the name)
@property (nonatomic) CFTimeInterval barTapAt;
// (1.8.8.2 F36: the Home Screen's pages as last read -- page 1 first -- and the layers of the pages that hold notes; a drag's turns at the screen's side)
@property (nonatomic, copy) NSArray<NSString *> *pageIds;      // (nil: other pages off -- one page, or ids not readable here)
@property (nonatomic, copy) NSSet<NSString *> *hiddenIds;      // (the hidden pages' ids, nil when not readable: their notes hide with them)
@property (nonatomic, copy) NSArray<UIView *> *pageLists;
@property (nonatomic, strong) NSMutableDictionary<NSString *, DMNotesPageView *> *pageLayers;
@property (nonatomic, strong) NSMutableDictionary<NSString *, NSString *> *pageLaidOut;   // (each page layer's last layout: what it depended on)
@property (nonatomic, weak) UIView *dragFrom;                  // (the layer a dragged note came from)
@property (nonatomic, strong) DMNoteView *rider;               // (its picture in our menu window, under the finger, once a page turned)
@property (nonatomic) int edgeSide, edgeTurns;
@property (nonatomic) long turnedTo;                           // (the page this drag's last turn went to, page 1 is 0; -1 none: where it lands)
@property (nonatomic) CFTimeInterval edgeSince;
@property (nonatomic) BOOL edgeTicking;
@end
@implementation DMNotesState
- (BOOL)textFieldShouldReturn:(UITextField *)tf { if (tf == _nameField) [_desk dm_noteRenameEnd:YES refocus:YES]; return NO; }   // (Return keeps the name)
- (void)textFieldDidEndEditing:(UITextField *)tf { if (tf == _nameField) [_desk dm_noteRenameEnd:YES refocus:NO]; }   // (a tap in the text, or the typing's end: kept)
@end

__attribute__((noinline)) static BOOL DMStickyPref(void) {   // (Settings > Desktop > Show Sticky Notes, stickyNotes: on unless set; Desktop.h DMDesktopApplyPref)
    CFPropertyListRef v = CFPreferencesCopyValue(CFSTR("stickyNotes"), MSB_DOMAIN, kCFPreferencesCurrentUser, kCFPreferencesAnyHost);
    BOOL on = !v || (CFGetTypeID(v) == CFBooleanGetTypeID() ? CFBooleanGetValue(v) : (CFGetTypeID(v) == CFNumberGetTypeID() ? [(__bridge NSNumber *)v boolValue] : YES));
    if (v) CFRelease(v);
    return on;
}
__attribute__((noinline)) static BOOL DMStickyShown(void) { return gDesktopNotesOn && gNotesRead && MSBDStickyWritable(gNotesStatus); }
// Is the typing window there to be made (its class and initializer)? Without it a note shows, but cannot be typed in (New Sticky Note greyed).
__attribute__((noinline)) static BOOL DMStickyCanType(void) { return DMDesktopTypingWindowCan(); }
// A touch's place on its screen (its window's point in the screen's space), where it is now.
__attribute__((noinline)) static CGPoint DMStickyTouchAt(UITouch *t) {
    UIWindow *w = t.window;
    return w ? [w convertPoint:[t locationInView:nil] toCoordinateSpace:(w.screen ?: [UIScreen mainScreen]).coordinateSpace] : [t locationInView:nil];
}
// A note's look lifted (the dragged shadow: a drag, or a held finger's cue) or at rest, eased over 0.12 s.
__attribute__((noinline)) static void DMStickyLiftLook(UIView *v, BOOL lifted) {
    CALayer *l = v.layer;
    float op = lifted ? 0.35f : 0.25f; CGFloat rad = lifted ? 18.0 : 6.0; CGSize off = CGSizeMake(0, lifted ? 10.0 : 3.0);
    if (l.shadowOpacity == op && l.shadowRadius == rad && CGSizeEqualToSize(l.shadowOffset, off)) return;
    CABasicAnimation *a = [CABasicAnimation animationWithKeyPath:@"shadowOpacity"]; a.fromValue = @(l.presentationLayer ? l.presentationLayer.shadowOpacity : l.shadowOpacity); a.toValue = @(op);
    CABasicAnimation *b = [CABasicAnimation animationWithKeyPath:@"shadowRadius"]; b.fromValue = @(l.shadowRadius); b.toValue = @(rad);
    CABasicAnimation *c = [CABasicAnimation animationWithKeyPath:@"shadowOffset"]; c.fromValue = [NSValue valueWithCGSize:l.shadowOffset]; c.toValue = [NSValue valueWithCGSize:off];
    CAAnimationGroup *g = [CAAnimationGroup animation]; g.animations = @[a, b, c]; g.duration = 0.12;
    l.shadowOpacity = op; l.shadowRadius = rad; l.shadowOffset = off;
    [l addAnimation:g forKey:@"dm.note.lift"];
}
// -dm_noteResize:'s stop at the page's app icons, widgets and page dots (StickyNotes.h MSBDStickyResizeClear, the note's minimum), in one space.
__attribute__((noinline)) static CGRect DMStickyResizeClear(CGRect start, CGRect want, int tag, NSArray<NSValue *> *occ) {
    CGRect *r = malloc(sizeof(CGRect) * MAX(1, occ.count));
    for (NSUInteger k = 0; k < occ.count; k++) r[k] = occ[k].CGRectValue;
    CGRect f = MSBDStickyResizeClear(start, want, tag, CGSizeMake(MSBD_NOTE_MIN_W, MSBD_NOTE_MIN_H), r, (int)occ.count);
    free(r);
    return f;
}

// Where a note is shown on its page (StickyNotes.h MSBDStickyPlaceClearFit, 1.8.8.2): the nearest clear frame of its size, else smaller where it is
// (B72's rule: the sides that meet the icons pulled in), else the smallest at the nearest clear place. Before, a note with no clear frame of its size
// on its page (the Dock moved to a side, the icons moved into it) stayed under the icons. *anchor: the frame of its own size the place came from.
__attribute__((noinline)) static CGRect DMStickyPlaceFit(CGRect f, CGRect area, const CGRect *r, int n, CGRect *anchor, NSString *noteId) {
    CGRect a, out = MSBDStickyPlaceClearFit(f, area, r, n, CGSizeMake(MSBD_NOTE_MIN_W, MSBD_NOTE_MIN_H), MSBD_NOTE_CLEAR_TESTS, &a);
    if (anchor) *anchor = a;
    if (out.size.width < a.size.width - 0.5 || out.size.height < a.size.height - 0.5) {
        DM_FEATURE_MARK("sticky-note-fit");
        DMLog([NSString stringWithFormat:@"[notes] note %@: no clear place of its size (%.0f x %.0f) on its page: shown %@ (its size kept)", MSBDStickyShortId(noteId), a.size.width, a.size.height, NSStringFromCGRect(out)]);
    }
    return out;
}
// A note let go, moved or sent to a page: its frame at its own stored size centred where it was put (a note shown smaller is placed as itself).
__attribute__((noinline)) static CGRect DMStickyAtItsSize(NSDictionary *e, CGRect put, CGRect area) {
    if (!e) return MSBDStickyClampInside(put, area);
    return MSBDStickyFrameAt(area, CGPointMake(CGRectGetMidX(put), CGRectGetMidY(put)), CGSizeMake([e[@"w"] doubleValue], [e[@"h"] doubleValue]));
}
// A SpringBoard getter the notes' pages read (1.8.8.2 F36): called only where the object answers it as a getter of an object (no argument, the
// return type "@"); any other shape on some iPadOS gives nil -- other pages off, or a hidden page's notes on page 1 -- never a value read as an object.
__attribute__((noinline)) static id DMStickyObjGet(id obj, NSString *name) {
    SEL s = NSSelectorFromString(name);
    NSMethodSignature *g = obj && [obj respondsToSelector:s] ? [obj methodSignatureForSelector:s] : nil;
    if (!g || g.numberOfArguments != 2 || strcmp(g.methodReturnType ?: "", "@")) return nil;
    return ((id (*)(id, SEL))objc_msgSend)(obj, s);
}
// A Home Screen page's id (1.8.8.2 F36): its icon list's model's -uniqueIdentifier, read only where both answer as object getters (DMStickyObjGet)
// and it is a string of a key's length.
__attribute__((noinline)) static NSString *DMStickyPageIdOfList(UIView *list) {
    id u = nil;
    @try { u = DMStickyObjGet(DMStickyObjGet(list, @"model"), @"uniqueIdentifier"); } @catch (NSException *x) { u = nil; }
    return MSBDStickyPageKey(u) ? u : nil;
}
// The ids of the Home Screen's hidden pages (Edit Pages): the root folder's own lists (-folder, -lists, object getters: DMStickyObjGet) whose
// -isHidden answers YES, each id read as a page's is; nil where the folder, its lists or a list's -isHidden (no argument, a BOOL) is not there in that
// shape -- then a hidden page's notes show on page 1 as a removed page's do.
__attribute__((noinline)) static NSSet<NSString *> *DMStickyHiddenPageIds(void) {
    id rfc = DMCall(DMCall(DMSBManager("SBIconController"), @"iconManager"), @"rootFolderController");
    id lists = nil;
    @try { lists = DMStickyObjGet(DMStickyObjGet(rfc, @"folder"), @"lists"); } @catch (NSException *x) { return nil; }
    if (![lists isKindOfClass:[NSArray class]]) return nil;
    NSMutableSet *ids = [NSMutableSet set];
    SEL hs = NSSelectorFromString(@"isHidden");
    @try {
        for (id m in (NSArray *)lists) {
            NSMethodSignature *g = [m respondsToSelector:hs] ? [m methodSignatureForSelector:hs] : nil;
            if (!g || g.numberOfArguments != 2 || (strcmp(g.methodReturnType, "B") && strcmp(g.methodReturnType, "c"))) return nil;
            if (!((BOOL (*)(id, SEL))objc_msgSend)(m, hs)) continue;
            id u = DMStickyObjGet(m, @"uniqueIdentifier");
            if (MSBDStickyPageKey(u)) [ids addObject:u];
        }
    } @catch (NSException *x) { return nil; }
    return ids;
}
// The root folder's own page turn (SpringBoard sends -setCurrentPageIndex:animated: to it itself), only where it and its page indexes answer with the
// argument and return types checked here (q, B; q) -- else nil: a dragged note never turns a page.
__attribute__((noinline)) static id DMStickyRootFolder(void) {
    id rfc = DMCall(DMCall(DMSBManager("SBIconController"), @"iconManager"), @"rootFolderController");
    if (!rfc) return nil;
    for (NSString *g in @[@"currentPageIndex", @"firstIconPageIndex", @"lastIconPageIndex"]) {
        NSMethodSignature *m = [rfc respondsToSelector:NSSelectorFromString(g)] ? [rfc methodSignatureForSelector:NSSelectorFromString(g)] : nil;
        if (!m || m.numberOfArguments != 2 || strcmp(m.methodReturnType, "q")) return nil;
    }
    SEL t = NSSelectorFromString(@"setCurrentPageIndex:animated:");
    NSMethodSignature *m = [rfc respondsToSelector:t] ? [rfc methodSignatureForSelector:t] : nil;
    if (!m || m.numberOfArguments != 4 || strcmp([m getArgumentTypeAtIndex:2], "q") || strcmp([m getArgumentTypeAtIndex:3], "B")) return nil;
    return rfc;
}
__attribute__((noinline)) static long DMStickyFolderIndex(id rfc, NSString *sel) { return rfc ? (long)((long long (*)(id, SEL))objc_msgSend)(rfc, NSSelectorFromString(sel)) : -1; }
__attribute__((noinline)) static void DMStickyTurnTo(id rfc, long page) { if (rfc) ((void (*)(id, SEL, long long, BOOL))objc_msgSend)(rfc, NSSelectorFromString(@"setCurrentPageIndex:animated:"), page, YES); }
@implementation DMDesktop (Notes)
- (void)dm_noteInit {
    _notes = [DMNotesState new];
    _notes.desk = self;
    _notes.views = [NSMutableDictionary dictionary];
    _notes.pageLayers = [NSMutableDictionary dictionary]; _notes.pageLaidOut = [NSMutableDictionary dictionary];
    UIView *layer = [[UIView alloc] initWithFrame:DMStickyFrame(self.bounds, "page 1's layer of notes")];
    layer.backgroundColor = [UIColor clearColor];
    layer.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    layer.hidden = !gDesktopNotesOn;
    _notes.layer = layer;
    [self insertSubview:layer atIndex:0];   // (under every icon: an icon on a note stays in reach, the pile too -- DesktopPlace.h nHard)
    if (gDesktopNotesOn) DMStickyLoad(nil);
    // (a desktop made again in this SpringBoard -- Show Desktop Icons or Finder off and on -- finds the store read already: its notes are shown on it
    //  once it is up, as the read's own pass did for the desktop before it)
    __weak DMDesktop *ws = self;
    if (gNotesRead) dispatch_async(dispatch_get_main_queue(), ^{ [ws dm_noteStoreChanged]; });
}
// ---- shown on page 1 ----
// The notes' frames for this pass: each inside the free area at its own size and place, then clear of the app icons, widgets and page dots.
- (void)dm_noteLayoutIn:(CGRect)area {
    if (!_notes) return;
    _notes.layer.hidden = !DMStickyShown();
    if (_notes.layer.hidden) return;
    NSArray<NSValue *> *occ = [self dm_occupied];
    CGRect *r = malloc(sizeof(CGRect) * MAX(1, occ.count));
    for (NSUInteger k = 0; k < occ.count; k++) r[k] = occ[k].CGRectValue;
    for (NSDictionary *e in gNotes) {
        DMNoteView *v = _notes.views[e[@"id"]];
        if (!v || v == _notes.dragging || v.superview != _notes.layer) continue;   // (page 1's notes: another page's lay out in their own layer, 1.8.8.2 F36)
        CGRect f = MSBDStickyFrameAt(area, [self dm_pointFor:@[e[@"x"], e[@"y"]] area:area], CGSizeMake([e[@"w"] doubleValue], [e[@"h"] doubleValue]));
        f = DMStickyPlaceFit(f, area, r, (int)occ.count, NULL, v.noteId);
        if (!CGRectEqualToRect(v.frame, f)) DMStickySetFrame(v, f, "a note laid out on page 1");
    }
    free(r);
    if (_notes.editor) [self dm_noteFit];   // (its own place moved: a turn, the Dock, More Space)
}
// Icons keep clear of the notes (soft rects: DesktopPlace.h nHard), the one being typed in too (its place is kept for it).
- (void)dm_noteTakeInto:(DMPlacer *)pl {
    if (!_notes || _notes.layer.hidden) return;
    for (DMNoteView *v in _notes.views.allValues) if (v.superview == _notes.layer && v != _notes.dragging) DMPlacerTake(pl, v.frame);   // (page 1's only, 1.8.8.2 F36)
}
// The views made, removed and drawn as the store has the notes; then a layout pass (the icons step aside).
- (void)dm_noteStoreChanged {
    if (!_notes) return;
    BOOL shown = DMStickyShown();
    _notes.layer.hidden = !shown;
    [self dm_noteReadPages];   // (1.8.8.2 F36: which page each note shows on)
    NSMutableSet *ids = [NSMutableSet set];
    for (NSDictionary *e in shown ? gNotes : @[]) {
        NSString *noteId = e[@"id"]; [ids addObject:noteId];
        DMNoteView *v = _notes.views[noteId];
        if (!v) {
            CGRect area = [self dm_area];
            v = [[DMNoteView alloc] initWithFrame:DMStickyFrame(MSBDStickyFrameAt(area, [self dm_pointFor:@[e[@"x"], e[@"y"]] area:area], CGSizeMake([e[@"w"] doubleValue], [e[@"h"] doubleValue])), "a note made")];
            v.noteId = noteId;
            _notes.views[noteId] = v;
            [self dm_notePlace:v of:e];
            [self dm_addMenu:[[UIContextMenuInteraction alloc] initWithDelegate:self] to:v];   // (a right click: its menu, -contextMenuInteraction:configurationForMenuAtLocation:)
        }
        v.colorIndex = MSBDStickyColorIndex(e[@"color"]);
        if (!(_notes.editor && [_notes.editor.noteId isEqualToString:noteId])) { [v dm_setBody:e[@"text"]]; [v dm_setName:MSBDStickyNameShown(e[@"name"], e[@"text"])]; v.hidden = _notes.rider && v == _notes.dragging; }   // (riding to another page: its picture shows)
        [self dm_notePlace:v of:e];   // (its page's layer: page 1's when its page is not shown now; none while its page is hidden)
        if (v != _notes.dragging && v.superview) [v.superview bringSubviewToFront:v];   // (the stacking order: last on top)
    }
    NSMutableArray *gone = [NSMutableArray array];
    for (NSString *noteId in _notes.views) if (![ids containsObject:noteId]) [gone addObject:noteId];
    if (_notes.editor && [gone containsObject:_notes.editor.noteId]) { [self dm_noteEnd:@"the note went"]; return; }   // (that ends here again)
    for (NSString *noteId in gone) { [_notes.views[noteId] removeFromSuperview]; [_notes.views removeObjectForKey:noteId]; }
    [_notes.pageLaidOut removeAllObjects];   // (every other page's layer lays out again)
    [self dm_notePagesTick];
    [self dm_placeAgain];
}
// ---- other Home Screen pages (1.8.8.2 F36) ----
// The pages as they are now: the icon lists in page 1's scroll view (SBIconListView, shown), in page order -- the leftmost first, the rightmost in a
// right-to-left layout --, each with iPadOS's own id. Page 1 must be the desktop's list and every page must give its id, else other pages are off.
- (void)dm_noteReadPages {
    UIView *list = _list, *scroll = list.superview;
    Class lc = objc_getClass("SBIconListView");
    NSMutableArray<UIView *> *lists = [NSMutableArray array]; NSMutableArray<NSString *> *ids = [NSMutableArray array];
    BOOL ok = list && lc && [scroll isKindOfClass:[UIScrollView class]];
    if (ok) {
        for (UIView *l in scroll.subviews) if ([l isKindOfClass:lc] && !l.hidden) [lists addObject:l];
        BOOL rtl = scroll.effectiveUserInterfaceLayoutDirection == UIUserInterfaceLayoutDirectionRightToLeft;
        [lists sortUsingComparator:^NSComparisonResult(UIView *a, UIView *b) { CGFloat x = a.frame.origin.x, y = b.frame.origin.x; return x == y ? NSOrderedSame : ((x < y) != rtl) ? NSOrderedAscending : NSOrderedDescending; }];
        if (lists.firstObject != list || lists.count < 2) ok = NO;
        for (UIView *l in ok ? lists : @[]) { NSString *i = DMStickyPageIdOfList(l); if (!i || [ids containsObject:i]) { ok = NO; break; } [ids addObject:i]; }
    }
    _notes.pageIds = ok ? ids : nil;
    _notes.pageLists = ok ? lists : (list ? @[list] : @[]);
    _notes.hiddenIds = list ? DMStickyHiddenPageIds() : nil;   // (a hidden page's notes hide with it, KT 22 Nov)
}
- (NSUInteger)dm_notePageOf:(NSDictionary *)e { return MSBDStickyPageOrHidden(e[@"page"], _notes.pageIds, _notes.hiddenIds); }   // (MSBD_NOTE_PAGE_HIDDEN: shown nowhere now)
// Where a note's view lies: its page's layer, or none while its page is hidden (it hides with the page's icons, back with them).
- (void)dm_notePlace:(DMNoteView *)v of:(NSDictionary *)e {
    if (!v || v == _notes.dragging) return;
    NSUInteger page = [self dm_notePageOf:e];
    if (page == MSBD_NOTE_PAGE_HIDDEN) { if (v.superview) { [v removeFromSuperview]; DMLog([NSString stringWithFormat:@"[notes] note %@ hides with its hidden Home Screen page", MSBDStickyShortId(v.noteId)]); } return; }
    UIView *home = [self dm_noteLayerFor:page make:YES];
    if (v.superview != home) { [home addSubview:v]; DMStickySetFrame(v, MSBDStickyFrameAt([self dm_area], [self dm_pointFor:@[e[@"x"], e[@"y"]] area:[self dm_area]], CGSizeMake([e[@"w"] doubleValue], [e[@"h"] doubleValue])), "a note into its page's layer"); }
}
- (NSUInteger)dm_notePageOfLayer:(UIView *)layer {
    if (![layer isKindOfClass:[DMNotesPageView class]]) return 0;
    NSUInteger k = [_notes.pageIds indexOfObject:((DMNotesPageView *)layer).pageId ?: @""];
    return k == NSNotFound ? 0 : k;
}
// (Put Back: a note goes back to its page only while that page is shown; else page 1 -- never into a hidden page, out of sight)
- (BOOL)dm_notePageShownFor:(NSString *)key { [self dm_noteReadPages]; NSUInteger p = MSBDStickyPageOrHidden(key, _notes.pageIds, _notes.hiddenIds); return p != MSBD_NOTE_PAGE_HIDDEN && p > 0; }
- (UIView *)dm_noteListOfPage:(NSUInteger)page { return page > 0 && page < _notes.pageLists.count && _notes.pageIds ? _notes.pageLists[page] : _list; }
// The layer a page's notes lie in: page 1's is the desktop's; another page's is made (make) at the back of its icon list, framed as its page.
- (UIView *)dm_noteLayerFor:(NSUInteger)page make:(BOOL)make {
    if (page == 0 || page >= _notes.pageIds.count) return _notes.layer;
    NSString *pid = _notes.pageIds[page];
    DMNotesPageView *l = _notes.pageLayers[pid];
    if (!l && make) {
        l = [[DMNotesPageView alloc] initWithFrame:CGRectZero];
        l.pageId = pid; l.backgroundColor = [UIColor clearColor];
        UITapGestureRecognizer *tap = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(dm_noteTap:)];
        tap.delegate = self; tap.name = @"dm.note.tap";
        if (@available(iOS 13.4, *)) tap.buttonMaskRequired = UIEventButtonMaskPrimary;
        [l addGestureRecognizer:tap];
        _notes.pageLayers[pid] = l;
        DM_FEATURE_MARK("sticky-note-page");
        DMLog([NSString stringWithFormat:@"[notes] a layer of notes made for Home Screen page %lu (%@)", (unsigned long)page + 1, MSBDStickyShortId(pid)]);
    }
    UIView *list = _notes.pageLists[page];
    if (l && l.superview != list) { [list insertSubview:l atIndex:0]; DMStickySetFrame(l, DMDesktopPageFrameIn(list), "a page's layer of notes"); }
    return l ?: _notes.layer;
}
// The page shown now: the root folder's own index where it answers (it changes at a turn's start), else the page that fills most of the scroll view.
- (NSUInteger)dm_notePageNow {
    if (!_notes.pageIds) return 0;
    id rfc = DMStickyRootFolder();
    long first = DMStickyFolderIndex(rfc, @"firstIconPageIndex"), now = DMStickyFolderIndex(rfc, @"currentPageIndex") - first;
    if (rfc && now >= 0 && now < (long)_notes.pageLists.count) return (NSUInteger)now;
    UIScrollView *scroll = (UIScrollView *)_list.superview; NSUInteger best = 0; CGFloat most = -1;
    for (NSUInteger i = 0; i < _notes.pageLists.count; i++) { CGRect r = CGRectIntersection([_notes.pageLists[i] convertRect:_notes.pageLists[i].bounds toView:scroll], scroll.bounds); CGFloat a = CGRectIsNull(r) ? 0 : r.size.width * r.size.height; if (a > most) { most = a; best = i; } }
    return best;
}
- (BOOL)dm_notePageShowing:(NSUInteger)page {
    UIView *list = [self dm_noteListOfPage:page], *scroll = list.superview;
    return list.window && scroll && CGRectIntersectsRect([list convertRect:list.bounds toView:scroll], scroll.bounds);
}
// A page layer's notes laid out in it: each inside the free area at its own size and place, clear of that page's app icons, widgets and page dots.
- (void)dm_noteLayoutPage:(NSUInteger)page layer:(UIView *)layer {
    CGRect area = [self dm_area];
    NSArray<NSValue *> *occ = [self dm_occupiedIn:[self dm_noteListOfPage:page] into:layer];
    CGRect *r = malloc(sizeof(CGRect) * MAX(1, occ.count));
    for (NSUInteger k = 0; k < occ.count; k++) r[k] = occ[k].CGRectValue;
    for (NSDictionary *e in gNotes) {
        DMNoteView *v = _notes.views[e[@"id"]];
        if (!v || v == _notes.dragging || v.superview != layer) continue;
        CGRect f = MSBDStickyFrameAt(area, [self dm_pointFor:@[e[@"x"], e[@"y"]] area:area], CGSizeMake([e[@"w"] doubleValue], [e[@"h"] doubleValue]));
        f = DMStickyPlaceFit(f, area, r, (int)occ.count, NULL, v.noteId);
        if (!CGRectEqualToRect(v.frame, f)) DMStickySetFrame(v, f, "a note laid out on its page");
    }
    free(r);
}
// Each tick (and after a store change): the pages read again where a note needs them; a layer whose page went is emptied into page 1's and goes, one
// with no note goes; the rest are put back in their lists (SpringBoard makes lists again), shown as the notes are (never in jiggle mode), and laid
// out again when what they depend on changed (the area, their page's icons, their notes) while their page shows.
- (void)dm_notePagesTick {
    BOOL wanted = _notes.pageLayers.count > 0;
    if (!wanted) for (NSDictionary *e in gNotes) if (MSBDStickyPageIdOf(e[@"page"])) { wanted = YES; break; }
    if (!wanted) return;
    NSArray *before = _notes.pageIds; NSSet *hiddenBefore = _notes.hiddenIds;
    [self dm_noteReadPages];
    BOOL moved = !(before == _notes.pageIds || [before isEqualToArray:_notes.pageIds]) || !(hiddenBefore == _notes.hiddenIds || [hiddenBefore isEqualToSet:_notes.hiddenIds]);
    BOOL shown = DMStickyShown() && !_editing;
    for (NSString *pid in [_notes.pageLayers allKeys]) {
        DMNotesPageView *l = _notes.pageLayers[pid];
        NSUInteger page = [_notes.pageIds indexOfObject:pid];
        BOOL empty = YES; for (UIView *v in l.subviews) if ([v isKindOfClass:[DMNoteView class]] && v != _notes.dragging) { empty = NO; break; }
        if (page == NSNotFound || page == 0 || empty) {   // (its page went, hides, is page 1 now, or holds no note: its notes placed by the rule, the layer goes)
            for (UIView *v in [l.subviews copy]) if ([v isKindOfClass:[DMNoteView class]] && v != _notes.dragging) {
                NSDictionary *e = DMStickyEntry(((DMNoteView *)v).noteId);
                if (e) [self dm_notePlace:(DMNoteView *)v of:e];
                if (v.superview == l) [_notes.layer addSubview:v];   // (never left in a layer that goes)
            }
            if (l != _notes.dragFrom || !_notes.dragging) { [l removeFromSuperview]; [_notes.pageLayers removeObjectForKey:pid]; [_notes.pageLaidOut removeObjectForKey:pid]; moved = YES; }
            continue;
        }
        UIView *list = _notes.pageLists[page];
        if (l.superview != list) { [list insertSubview:l atIndex:0]; [_notes.pageLaidOut removeObjectForKey:pid]; }
        CGRect fr = DMDesktopPageFrameIn(list); if (!CGRectEqualToRect(l.frame, fr)) DMStickySetFrame(l, fr, "a page's layer of notes, its page");
        if (l.hidden != !shown) l.hidden = !shown;
        if (!shown || ![self dm_notePageShowing:page]) continue;
        NSMutableString *sig = [NSMutableString stringWithFormat:@"%@|%lu|", NSStringFromCGRect([self dm_area]), (unsigned long)gNotesGen];
        for (NSValue *r in [self dm_occupiedIn:list into:l]) { CGRect f = r.CGRectValue; [sig appendFormat:@"%.0f,%.0f,%.0f,%.0f;", f.origin.x, f.origin.y, f.size.width, f.size.height]; }
        if ([_notes.pageLaidOut[pid] isEqualToString:sig]) continue;
        _notes.pageLaidOut[pid] = sig;
        [self dm_noteLayoutPage:page layer:l];
        if (_notes.editor && [self dm_notePageOfLayer:[self dm_noteLayerOfEditor]] == page) [self dm_noteFit];
    }
    if (moved) { for (NSDictionary *e in gNotes) [self dm_notePlace:_notes.views[e[@"id"]] of:e]; [_notes.pageLaidOut removeAllObjects]; [self dm_placeAgain]; }
}
- (void)dm_notePagesOff {   // (the desktop leaves its page: every other page's layer goes with it; the next tick puts them back)
    for (DMNotesPageView *l in _notes.pageLayers.allValues) [l removeFromSuperview];
    [_notes.pageLaidOut removeAllObjects];
}
- (UIView *)dm_noteHitAt:(CGPoint)p {   // (-hitTest:withEvent:, after the icons: they lie over the notes)
    if (!_notes || _notes.layer.hidden) return nil;
    for (UIView *v in [_notes.layer.subviews reverseObjectEnumerator]) if ([v isKindOfClass:[DMNoteView class]] && !v.hidden && v.alpha > 0.01 && CGRectContainsPoint(v.frame, p)) return v;
    return nil;
}
- (BOOL)dm_noteAtScreen:(CGPoint)sp {   // (page 1's, or another page's layer: 1.8.8.2 F36)
    id<UICoordinateSpace> scr = (self.window.screen ?: [UIScreen mainScreen]).coordinateSpace;
    if ([self dm_noteHitAt:[self convertPoint:sp fromCoordinateSpace:scr]]) return YES;
    for (DMNotesPageView *l in _notes.pageLayers.allValues) if (l.window && [l hitTest:[l convertPoint:sp fromCoordinateSpace:scr] withEvent:nil]) return YES;
    return NO;
}
// ---- New Sticky Note (the empty desktop's menu): at the pressed spot, Yellow, 220 x 180, clear of the app icons; typed in at once ----
- (UIAction *)dm_noteNewRowAt:(CGPoint)sp {
    if (!gDesktopNotesOn) return nil;   // (Show Sticky Notes off: no row)
    __weak DMDesktop *ws = self;
    UIAction *a = [UIAction actionWithTitle:@"New Sticky Note" image:[UIImage systemImageNamed:@"note.text.badge.plus"] identifier:nil handler:^(UIAction *x) { [ws dm_noteNewAt:sp]; }];
    if (!gNotesRead || !MSBDStickyWritable(gNotesStatus) || gNotes.count >= MSBD_NOTES_MAX || !DMStickyCanType()) a.attributes = UIMenuElementAttributesDisabled;   // (30 notes, a store not readable yet or newer, no typing window)
    return a;
}
- (void)dm_noteNewAt:(CGPoint)sp {
    if (!DMStickyShown() || gNotes.count >= MSBD_NOTES_MAX || !DMStickyCanType()) return;
    DM_FEATURE_MARK("sticky-note-new");
    CGRect area = [self dm_area];
    NSArray<NSValue *> *occ = [self dm_occupied];
    CGRect *r = malloc(sizeof(CGRect) * MAX(1, occ.count));
    for (NSUInteger k = 0; k < occ.count; k++) r[k] = occ[k].CGRectValue;
    CGRect f = MSBDStickyNewFrame([self convertPoint:sp fromCoordinateSpace:(self.window.screen ?: [UIScreen mainScreen]).coordinateSpace], area, r, (int)occ.count);
    free(r);
    NSArray *c = [self dm_fractionFor:CGPointMake(CGRectGetMidX(f), CGRectGetMidY(f)) area:area];
    NSMutableDictionary *e = [@{@"id": [NSUUID UUID].UUIDString, @"color": @"Yellow", @"x": c[0], @"y": c[1], @"w": @(MSBD_NOTE_W), @"h": @(MSBD_NOTE_H), @"text": @""} mutableCopy];
    [gNotes addObject:e];
    DMStickyChanged(0.3);
    [self dm_noteStoreChanged];
    [self layoutIfNeeded];
    DMLog([NSString stringWithFormat:@"[notes] New Sticky Note %@ at %@ (%lu notes)", MSBDStickyShortId(e[@"id"]), NSStringFromCGRect(f), (unsigned long)gNotes.count]);
    [self dm_noteBegin:_notes.views[e[@"id"]] at:CGPointMake(NAN, NAN)];
}
// ---- a tap: the note is typed in, the caret where the finger touched (at the end below the text; on the bar at the end) ----
// (1.8.8.2 B78: only a press that never went past its drag distance, by -dm_event:'s own note of that press -- _trackMoved -- and by the distance
//  from where the tap's touch went down to where it lifted, held less than the menu's time, no menu of ours up: StickyNotes.h MSBDStickyPressTypes)
// (UIKit asks this before SpringBoard's -sendEvent: has the touch: -dm_event: has not seen it yet, so the press is matched by the touch itself at the tap)
- (void)dm_noteTapDown:(UITouch *)t {   // (the desktop tap's -gestureRecognizer:shouldReceiveTouch:, as its touch goes down)
    if (!_notes) return;
    _notes.tapTouch = t; _notes.tapDownAt = CACurrentMediaTime();
    _notes.tapDown = DMStickyTouchAt(t);
}
- (void)dm_noteTap:(UITapGestureRecognizer *)g {
    BOOL other = [g.view isKindOfClass:[DMNotesPageView class]];   // (another page's layer's tap, 1.8.8.2 F36)
    CGPoint p = [g locationInView:other ? g.view : self];
    DMNoteView *v = (DMNoteView *)(other ? [g.view hitTest:p withEvent:nil] : [self dm_noteHitAt:p]);
    if (![v isKindOfClass:[DMNoteView class]] || _editing) return;
    CGPoint up = other ? [g.view convertPoint:p toCoordinateSpace:(self.window.screen ?: [UIScreen mainScreen]).coordinateSpace] : [self dm_screen:p];
    UITouch *tt = _notes.tapTouch;
    BOOL samePress = tt != nil && tt == _pressTouch;   // (the press -dm_event: followed last is this tap's own: the same touch)
    CGPoint lift = tt ? DMStickyTouchAt(tt) : up;      // (where the tap's touch is now, at the tap: where it lifted -- the tap's own location is where it went down)
    BOOL moved = MSBDStickyTapMoved(samePress, _trackMoved, hypot(_trackLast.x - _trackDown.x, _trackLast.y - _trackDown.y), hypot(lift.x - _notes.tapDown.x, lift.y - _notes.tapDown.y), _lastTapPointer ? 4.0 : 10.0);
    double held = CACurrentMediaTime() - _notes.tapDownAt;
    if (!MSBDStickyPressTypes(moved, gOverlay != nil, held, _lastTapPointer ? kDMDesktopHoldMenuPointer : kDMDesktopHoldMenu)) {
        DMLog([NSString stringWithFormat:@"[notes] a %@ on note %@ that %@: not typed in", _lastTapPointer ? @"click" : @"tap", MSBDStickyShortId(v.noteId),
               moved ? @"moved past a drag's distance" : gOverlay ? @"came with a menu of ours up" : [NSString stringWithFormat:@"was held %.2f s", held]]);
        return;
    }
    if (MSBDStickyOnBar(v.frame, [v.superview convertPoint:p fromView:other ? g.view : self])) { [self dm_noteIdleBarTap:v]; return; }   // (its bar: twice edits its name, 1.8.8.2 F37)
    [self dm_noteBegin:v at:up];
}
- (BOOL)dm_noteAXActivate:(UIView *)v {
    if (![v isKindOfClass:[DMNoteView class]] || _notes.views[((DMNoteView *)v).noteId ?: @""] != v || !v.window || _editing || !self.userInteractionEnabled) return NO;
    [self dm_noteBegin:(DMNoteView *)v at:CGPointMake(NAN, NAN)];
    return YES;
}
// ---- the typing ----
- (BOOL)dm_noteActive { return _notes.editor != nil; }
- (void)dm_noteBegin:(DMNoteView *)nv at:(CGPoint)sp {
    if (!nv || !nv.window || _editing || !DMStickyShown()) return;
    NSMutableDictionary *e = DMStickyEntry(nv.noteId);
    if (!e) return;
    if (_notes.editor) [self dm_noteEnd:@"another note is typed in"];
    [self dm_endRename:YES];   // (one or the other in the typing window)
    if (_sel.count) [self dm_select:@[]];   // (the icon selection clears)
    UIView *host = DMDesktopRenameHost();
    if (!host) { DMLog(@"[notes] no typing window here: the note shows but is not typed in"); return; }
    DM_FEATURE_MARK("sticky-note-typing");
    [gNotes removeObjectIdenticalTo:e]; [gNotes addObject:e];   // (typed in: on top)
    [nv.superview bringSubviewToFront:nv];   // (in its page's layer, 1.8.8.2 F36)
    id<UICoordinateSpace> scr = (self.window.screen ?: [UIScreen mainScreen]).coordinateSpace;
    CGRect home = [nv convertRect:nv.bounds toCoordinateSpace:scr];
    DMNoteEditor *ed = [[DMNoteEditor alloc] initWithFrame:DMStickyFrame([host convertRect:home fromCoordinateSpace:scr], "the editor made") color:MSBDStickyColorIndex(e[@"color"]) text:e[@"text"] name:MSBDStickyNameShown(e[@"name"], e[@"text"]) target:self];
    ed.noteId = nv.noteId;
    ed.textView.delegate = self;
    [host addSubview:ed];
    _notes.editor = ed; _notes.home = home;
    _notes.editFront = [DMActiveApp() bundleIdentifier] ?: @"";
    nv.hidden = YES;
    UIWindow *key = nil; for (UIWindow *w in self.window.windowScene.windows) if (w.isKeyWindow) key = w;
    _notes.keyBefore = key;
    DMDesktopFocus(YES);   // (the rename's lock: SpringBoard's on-screen keyboard comes with it, over the windows and the Dock)
    if (!gDesktopRenameWindow.isKeyWindow) [gDesktopRenameWindow makeKeyWindow];
    [ed.textView becomeFirstResponder];
    UITextPosition *pos = nil;
    if (isfinite(sp.x) && isfinite(sp.y)) pos = [ed.textView closestPositionToPoint:[ed.textView convertPoint:sp fromCoordinateSpace:scr]];
    if (!pos) pos = [e[@"text"] length] ? ed.textView.endOfDocument : ed.textView.beginningOfDocument;
    ed.textView.selectedTextRange = [ed.textView textRangeFromPosition:pos toPosition:pos];
    [self dm_noteFit];
    DMLog([NSString stringWithFormat:@"[notes] note %@ typed in (%lu characters; its window at %.1f, first responder %d)", MSBDStickyShortId(ed.noteId), (unsigned long)[e[@"text"] length], gDesktopRenameWindow.windowLevel, ed.textView.isFirstResponder]);
}
// Every way the typing ends (Design v2 2k) does the same: the text saved, the focus lock and the key window given back, the note shown at its own place.
- (void)dm_noteEnd:(NSString *)why {
    DMNoteEditor *ed = _notes.editor;
    if (!ed) return;
    [self dm_noteRenameEnd:YES refocus:NO];   // (its name being edited: kept, as a click elsewhere keeps it -- 1.8.8.2 F37)
    _notes.editor = nil; _notes.resizing = NO;
    NSMutableDictionary *e = DMStickyEntry(ed.noteId);
    NSString *text = MSBDStickyTextCut(ed.textView.text, MSBD_NOTE_TEXT_MAX);
    if (e) e[@"text"] = text;
    if (ed.textView.isFirstResponder) [ed.textView resignFirstResponder];
    ed.textView.delegate = nil;
    [ed removeFromSuperview];
    DMDesktopFocus(NO);
    if (!_renameField) DMDesktopRenameHostDone();
    UIWindow *before = _notes.keyBefore; _notes.keyBefore = nil;
    if (before && before != self.window && before != gDesktopRenameWindow && !before.hidden) [before makeKeyWindow];
    else if (self.window && !self.window.hidden && !self.window.isKeyWindow) [self.window makeKeyWindow];
    DMStickyChanged(0);
    DMLog([NSString stringWithFormat:@"[notes] note %@: the typing ended (%@), %lu characters", MSBDStickyShortId(ed.noteId), why, (unsigned long)text.length]);
    [self dm_noteStoreChanged];
}
- (void)textViewDidChange:(UITextView *)tv {
    if (tv != _notes.editor.textView) return;
    NSMutableDictionary *e = DMStickyEntry(_notes.editor.noteId);
    if (e) e[@"text"] = MSBDStickyTextCut(tv.text, MSBD_NOTE_TEXT_MAX);
    if (e) [_notes.editor.band dm_setName:MSBDStickyNameShown(e[@"name"], e[@"text"])];   // (a note with no name of its own is named after its first line)
    DMStickyChanged(1.0);   // (a second after the typing stops, as TextEdit saves)
}
// (a paste or a typed text past the cap is cut to fit, never inside a character)
- (BOOL)textView:(UITextView *)tv shouldChangeTextInRange:(NSRange)range replacementText:(NSString *)text {
    if (tv != _notes.editor.textView) return YES;
    NSUInteger keep = tv.text.length >= range.length ? tv.text.length - range.length : 0;
    if (keep + text.length <= MSBD_NOTE_TEXT_MAX) return YES;
    NSString *cut = MSBDStickyTextCut(text, keep < MSBD_NOTE_TEXT_MAX ? MSBD_NOTE_TEXT_MAX - keep : 0);
    UITextPosition *a = [tv positionFromPosition:tv.beginningOfDocument offset:(NSInteger)range.location], *b = a ? [tv positionFromPosition:a offset:(NSInteger)range.length] : nil;
    if (cut.length && a && b) [tv replaceRange:[tv textRangeFromPosition:a toPosition:b] withText:cut];
    DMLog([NSString stringWithFormat:@"[notes] a text of %lu characters cut to %lu: the note holds %d at most", (unsigned long)text.length, (unsigned long)cut.length, MSBD_NOTE_TEXT_MAX]);
    return NO;
}
// (the keyboard's hide key: the keyboard goes, the note stays typed in with its grips -- a tap in the text brings the keyboard back)
- (void)textViewDidEndEditing:(UITextView *)tv { if (tv == _notes.editor.textView) DMLog(@"[notes] the keyboard went: the note stays typed in"); }
// The keyboard: a docked on-screen one lifts the note 8 pt above it (never above the free area's top; a note too tall gets an inset with the caret
// in view), back when it goes; the grips hide while it is lifted. Asked when the keyboard moves and the window turns (-dm_fitRenameField).
- (void)dm_noteFit {
    DMNoteEditor *ed = _notes.editor;
    UIView *host = ed.superview;
    if (!ed || !host || _notes.resizing) return;
    id<UICoordinateSpace> scr = (self.window.screen ?: [UIScreen mainScreen]).coordinateSpace;
    DMNoteView *nv = _notes.views[ed.noteId];
    if (nv.superview && self.window) _notes.home = [nv convertRect:nv.bounds toCoordinateSpace:scr];   // (its own place: laid out, hidden while typed in)
    CGFloat inset = 0;
    UIView *lay = nv.superview ?: self;   // (its page's layer: the screen through it, 1.8.8.2 F36)
    CGRect area = self.window && lay.window ? [lay convertRect:[self dm_area] toCoordinateSpace:scr] : _notes.home;
    CGRect f = MSBDStickyLift(_notes.home, gOwnKeyboardFrame, CGRectGetMinY(area), &inset);
    BOOL lifted = !CGRectEqualToRect(f, _notes.home);
    ed.gripL.hidden = lifted; ed.gripR.hidden = lifted; ed.movePan.enabled = !lifted;   // (lifted over the keyboard: no resize, no move -- 1.8.8.2 B78)
    ed.barTap.enabled = !lifted; ed.band.nameHidden = lifted || _notes.nameField != nil;   // (... and no name in its bar, 1.8.8.2 F37: a name being edited keeps its field)
    DMStickySetBottomInset(ed.textView, inset, "the text's inset over the keyboard");
    if (inset > 0) [ed.textView scrollRangeToVisible:ed.textView.selectedRange];
    CGRect local = [host convertRect:f fromCoordinateSpace:(host.window.screen ?: [UIScreen mainScreen]).coordinateSpace];
    if (CGRectEqualToRect(ed.frame, local)) return;
    if (!ed.placed) { ed.placed = YES; DMStickySetFrame(ed, local, "the editor placed"); return; }
    [UIView animateWithDuration:0.2 animations:^{ DMStickySetFrame(ed, local, "the editor lifted or back"); }];
    DMLog([NSString stringWithFormat:@"[notes] note %@ %@ (keyboard %@)", MSBDStickyShortId(ed.noteId), lifted ? @"lifted above the keyboard" : @"at its own place", NSStringFromCGRect(gOwnKeyboardFrame)]);
}
// A bottom corner's grip: the windows' maths (NativeWindow.h DMNativeResized: the left grip keeps the right edge, the minimum, never wider than the
// free area or past its bottom), then kept inside the area (the check's item 14). Kept as the note's own size and place when the finger lifts.
// (inside YES: the moving side stops at the area's side, so the other side stays where it is; 1.8.8.2 B72, the left grip pulled past the area's
//  left side grew the note to the right)
// (and it stops where the note would meet the page's app icons, widgets or page dots, DMStickyResizeClear: the layout keeps every note clear of
//  them, so a note grown over them was moved at the let go, carrying its size -- its other side moved, or it jumped up off the page dots)
- (void)dm_noteResize:(UIPanGestureRecognizer *)g {
    DMNoteEditor *ed = _notes.editor;
    UIView *host = ed.superview;
    if (!ed || !host || g.view.superview != ed) return;
    id<UICoordinateSpace> scr = (host.window.screen ?: [UIScreen mainScreen]).coordinateSpace;
    if (g.state == UIGestureRecognizerStateBegan) { _notes.resizeStart = ed.frame; _notes.resizing = YES; DM_FEATURE_MARK("sticky-note-resize"); }
    UIView *lay = [self dm_noteLayerOfEditor];   // (its page's layer, 1.8.8.2 F36)
    CGRect desk = [host convertRect:[lay convertRect:[self dm_area] toCoordinateSpace:(self.window.screen ?: [UIScreen mainScreen]).coordinateSpace] fromCoordinateSpace:scr];
    CGRect f = MSBDStickyClampInside(DMNativeResized(_notes.resizeStart, [g translationInView:host], (int)g.view.tag, CGSizeMake(MSBD_NOTE_MIN_W, MSBD_NOTE_MIN_H), desk, YES), desk);
    f = DMStickyResizeClear(_notes.resizeStart, f, (int)g.view.tag, [self dm_noteOccupiedIn:host]);
    DMStickySetFrame(ed, f, "the editor resized");
    if (g.state != UIGestureRecognizerStateEnded && g.state != UIGestureRecognizerStateCancelled && g.state != UIGestureRecognizerStateFailed) return;
    _notes.resizing = NO;
    NSMutableDictionary *e = DMStickyEntry(ed.noteId);
    if (!e || !self.window) return;
    CGRect mine = [lay convertRect:[host convertRect:f toCoordinateSpace:scr] fromCoordinateSpace:(self.window.screen ?: [UIScreen mainScreen]).coordinateSpace];
    NSArray *c = [self dm_fractionFor:CGPointMake(CGRectGetMidX(mine), CGRectGetMidY(mine)) area:[self dm_area]];
    e[@"x"] = c[0]; e[@"y"] = c[1]; e[@"w"] = @(mine.size.width); e[@"h"] = @(mine.size.height);   // (the frame as shown: a rounded size moved a side, B72)
    DMStickyChanged(0.3);
    DMLog([NSString stringWithFormat:@"[notes] note %@ resized to %.0f x %.0f", MSBDStickyShortId(ed.noteId), mine.size.width, mine.size.height]);
    [_notes.pageLaidOut removeAllObjects]; [self dm_notePagesTick];   // (another page's: laid out again there)
    [self dm_placeAgain]; [self layoutIfNeeded];   // (its own place again, kept clear; the icons step aside)
}
// The top bar of the note being typed in, pulled (1.8.8.2 B78): the editor follows inside the free area, the typing, the caret and the keyboard stay;
// let go, the note's place is stored as a drop stores it (clear of the app icons, the centre's share, on top) and the editor goes to that place.
- (void)dm_noteMove:(UIPanGestureRecognizer *)g {
    DMNoteEditor *ed = _notes.editor;
    UIView *host = ed.superview;
    if (!ed || !host || g.view.superview != ed) return;
    id<UICoordinateSpace> scr = (host.window.screen ?: [UIScreen mainScreen]).coordinateSpace;
    if (g.state == UIGestureRecognizerStateBegan) { _notes.resizeStart = ed.frame; _notes.resizing = YES; DM_FEATURE_MARK("sticky-note-move-typing"); }
    UIView *lay = [self dm_noteLayerOfEditor];   // (its page's layer, 1.8.8.2 F36)
    CGRect desk = [host convertRect:[lay convertRect:[self dm_area] toCoordinateSpace:(self.window.screen ?: [UIScreen mainScreen]).coordinateSpace] fromCoordinateSpace:scr];
    CGPoint d = [g translationInView:host];
    CGRect f = MSBDStickyClampInside(CGRectOffset(_notes.resizeStart, d.x, d.y), desk);
    DMStickySetFrame(ed, f, "the editor moved by its bar");
    if (g.state != UIGestureRecognizerStateEnded && g.state != UIGestureRecognizerStateCancelled && g.state != UIGestureRecognizerStateFailed) return;
    _notes.resizing = NO;
    NSMutableDictionary *e = DMStickyEntry(ed.noteId);
    if (!e || !self.window) return;
    CGRect area = [self dm_area], mine = [lay convertRect:[host convertRect:f toCoordinateSpace:scr] fromCoordinateSpace:(self.window.screen ?: [UIScreen mainScreen]).coordinateSpace];
    NSArray<NSValue *> *occ = [self dm_occupiedIn:[self dm_noteListOfPage:[self dm_notePageOfLayer:lay]] into:lay];
    CGRect *r = malloc(sizeof(CGRect) * MAX(1, occ.count));
    for (NSUInteger k = 0; k < occ.count; k++) r[k] = occ[k].CGRectValue;
    CGRect anchor, placed = DMStickyPlaceFit(DMStickyAtItsSize(e, mine, area), area, r, (int)occ.count, &anchor, ed.noteId);
    free(r);
    NSArray *c = [self dm_fractionFor:CGPointMake(CGRectGetMidX(anchor), CGRectGetMidY(anchor)) area:area];   // (its own size's frame: the next layout gives the same)
    e[@"x"] = c[0]; e[@"y"] = c[1];
    [gNotes removeObjectIdenticalTo:e]; [gNotes addObject:e];   // (moved: on top)
    DMStickyChanged(0.3);
    DMLog([NSString stringWithFormat:@"[notes] note %@ moved by its bar while typed in, to %@ (first responder %d)", MSBDStickyShortId(ed.noteId), NSStringFromCGRect(placed), ed.textView.isFirstResponder]);
    [_notes.pageLaidOut removeAllObjects]; [self dm_notePagesTick];   // (another page's: laid out again there)
    [self dm_placeAgain]; [self layoutIfNeeded];   // (its own place again; the editor goes there, -dm_noteFit)
}
// The rects the note being typed in keeps clear of (its page's app icons, widgets and page dots: -dm_occupiedIn:into:, as the layout's), in another
// view's space (the typing window's).
- (NSArray<NSValue *> *)dm_noteOccupiedIn:(UIView *)host {
    NSMutableArray<NSValue *> *a = [NSMutableArray array];
    UIView *lay = [self dm_noteLayerOfEditor];
    if (!self.window || !host.window || !lay.window) return a;
    id<UICoordinateSpace> mine = (self.window.screen ?: [UIScreen mainScreen]).coordinateSpace, theirs = (host.window.screen ?: [UIScreen mainScreen]).coordinateSpace;
    for (NSValue *r in [self dm_occupiedIn:[self dm_noteListOfPage:[self dm_notePageOfLayer:lay]] into:lay]) [a addObject:[NSValue valueWithCGRect:[host convertRect:[lay convertRect:r.CGRectValue toCoordinateSpace:mine] fromCoordinateSpace:theirs]]];
    return a;
}
- (UIView *)dm_noteLayerOfEditor { DMNoteView *nv = _notes.views[_notes.editor.noteId ?: @""]; return nv.superview && nv.superview != self ? nv.superview : _notes.layer; }
- (BOOL)dm_noteGripAt:(CGPoint)sp {
    DMNoteEditor *ed = _notes.editor;
    if (!ed.window) return NO;
    id<UICoordinateSpace> scr = (ed.window.screen ?: [UIScreen mainScreen]).coordinateSpace;
    for (UIView *g in @[ed.gripL, ed.gripR]) if (!g.hidden && CGRectContainsPoint([g convertRect:g.bounds toCoordinateSpace:scr], sp)) return YES;
    return ed.movePan.enabled && CGRectContainsPoint([ed.band convertRect:ed.band.bounds toCoordinateSpace:scr], sp);   // (its bar: a move, 1.8.8.2 B78)
}
// Keys while a note is typed in (the desktop has them first, -dm_hasKeys): Esc ends; the Command editing keys are the note's own; Return and every
// other key go on to the text view (NO: SpringBoard's own handling types them). Nothing reaches an active Finder or TextEdit window.
- (BOOL)dm_noteKey:(UIKey *)key {
    UIKeyModifierFlags m = key.modifierFlags & (UIKeyModifierCommand | UIKeyModifierShift | UIKeyModifierAlternate | UIKeyModifierControl);
    if (_notes.nameField) {   // (its name being edited, 1.8.8.2 F37: Esc keeps the old one, back to the text; Return and the rest are the field's)
        if (key.keyCode == UIKeyboardHIDUsageKeyboardEscape && m == 0) { [self dm_noteRenameEnd:NO refocus:YES]; return YES; }
        return NO;
    }
    if (key.keyCode == UIKeyboardHIDUsageKeyboardEscape && m == 0) { [self dm_noteEnd:@"Esc"]; return YES; }
    DMNoteTextView *tv = _notes.editor.textView;
    return tv.isFirstResponder && DMTextViewEditKey(tv, key, YES);
}
// A touch that begins anywhere but on the note being typed in (its window's views, the edit menu, our keyboard), our menu or a context menu ends it.
- (void)dm_noteTouchBegan:(UITouch *)t {
    if (!_notes.editor) return;
    UIView *v = t.view;
    if (gOverlay && v && [v isDescendantOfView:gOverlay]) return;
    if (DMAnyContextMenuVC(NULL)) return;
    UIScreen *screen = t.window.screen;
    CGPoint sp = t.window ? [t.window convertPoint:[t locationInView:nil] toCoordinateSpace:(screen ?: [UIScreen mainScreen]).coordinateSpace] : [t locationInView:nil];
    if (DMDesktopTypingTakes(sp, screen)) return;
    [self dm_noteEnd:@"a touch elsewhere"];
}
// Every tick: the typing ends when jiggle mode, Guided Access or the switch take the notes away, page 1 goes, another app comes to the front or
// another text field takes the typing; the typing window's level is checked again (a note is typed in for minutes, the check's item 11). A store
// not readable yet is tried again every 5 s.
- (void)dm_noteTick {
    if (!_notes) return;
    if (gDesktopNotesOn && gNotesRead && gNotesStatus == MSBDStickyUnread && !gNotesReading && CACurrentMediaTime() - gNotesTriedAt > 5.0) DMStickyLoad(nil);
    [self dm_notePagesTick];   // (1.8.8.2 F36: the layers of the other pages' notes)
    // (1.8.8.3: iPadOS's App Switcher up -- its transition event seen and a switcher showing --: the typing ends, a note's, its name's or a desktop
    //  name's, whichever way the switcher came; its event ends it as it comes, Desktop.h DMDesktopTypingSwitcherEvent. The typing window, kept just
    //  above the switcher's window, lay over the App Switcher's cards: never raised over them here)
    if (gEnvMode == 2 && [self dm_typingNow] && DMSwitcherVisible()) { [self dm_typingEnd:@"the App Switcher is up"]; return; }
    if (!_notes.editor) return;
    NSString *why = nil;
    if (_editing) why = @"jiggle mode or Guided Access";
    else if (!DMStickyShown()) why = @"Show Sticky Notes is off";
    else if (![self dm_notePageShowing:[self dm_notePageOfLayer:[self dm_noteLayerOfEditor]]]) why = @"its page no longer shows";   // (1.8.8.2 F36: page 1's, or another's)
    else if (![[DMActiveApp() bundleIdentifier] ?: @"" isEqualToString:_notes.editFront ?: @""]) why = @"another app came to the front";
    else if (DMSBTextInputTypingBut(gDesktopRenameWindow, nil)) why = @"another text field has the typing";
    if (why) { [self dm_noteEnd:why]; return; }
    UIWindow *w = gDesktopRenameWindow;
    CGFloat level = DMDesktopRenameLevel();
    if (w && fabs(w.windowLevel - level) > 0.01) { DMLog([NSString stringWithFormat:@"[notes] the typing window to level %.1f (was %.1f)", level, w.windowLevel]); w.windowLevel = level; }
}
- (void)dm_notePrefChanged {
    if (!_notes) return;
    if (!gDesktopNotesOn) [self dm_noteEnd:@"Show Sticky Notes is off"];
    else DMStickyLoad(nil);
    [self dm_noteStoreChanged];
}
// ---- held, then moved: the note follows the finger (a pointer at once), over the icons, and is let go clear of the app icons ----
- (BOOL)dm_noteTrackBegin:(UIView *)at at:(CGPoint)sp {
    DMNoteView *v = [at isKindOfClass:[DMNoteView class]] && _notes.views[((DMNoteView *)at).noteId ?: @""] == at && !at.hidden ? (DMNoteView *)at : nil;   // (one of ours, on any page: 1.8.8.2 F36)
    if (_notes) { _notes.track = v; _notes.trackBar = v && MSBDStickyOnBar(v.frame, [v.superview convertPoint:sp fromCoordinateSpace:(self.window.screen ?: [UIScreen mainScreen]).coordinateSpace]); }
    return v != nil;
}
// How long a finger is held on the note followed before a move drags it (-dm_event:, and the Dock's swipe down by the same rule): 0 on its top bar,
// 0.2 s elsewhere (1.8.8.2 B78; an icon 0.3 s, the empty desktop 0.35 s, Desktop.h DMDesktopHoldToTake).
- (double)dm_noteHoldToMove { return MSBDStickyHoldToMove(_notes.trackBar); }
// A press on a note's top bar that moves (before its drag distance): the note's from here -- every other gesture on its touch lets go, the page's
// scroll too, so a swipe that starts on the bar never turns the page; it drags once past the drag distance.
- (void)dm_noteBarFirstMove:(UITouch *)t {
    if (![self dm_noteTracked] || !_notes.trackBar || _trackOwner != MSBDTouchUndecided || _trackSecondary || !t) return;
    _trackOwner = MSBDTouchDesktop;
    [self dm_noteTakeTouch:t];
    DM_FEATURE_MARK("sticky-note-bar-press");
    DMLog([NSString stringWithFormat:@"[notes] a %@ on note %@'s bar moved: the note's, not the page's", _trackPointer ? @"pointer" : @"finger", MSBDStickyShortId(_notes.track.noteId)]);
}
// A press that is the note's: every other gesture on its touch lets go (the Home Screen's own long press among them) and the page's scroll too.
- (void)dm_noteTakeTouch:(UITouch *)t {
    for (UIGestureRecognizer *o in [t.gestureRecognizers copy]) if (![o.name hasPrefix:@"dm."] && o.enabled) { o.enabled = NO; o.enabled = YES; }
    for (UIView *v = self.superview; v; v = v.superview) if ([v isKindOfClass:[UIScrollView class]]) { UIPanGestureRecognizer *pan = ((UIScrollView *)v).panGestureRecognizer; pan.enabled = NO; pan.enabled = YES; }
}
// A pointer's primary press on a note (1.8.8.2): the note's from the touch down. A pointer on a note only types in it (a click), moves it (a drag)
// or opens its menu (a click held 0.75 s): never a page swipe, never the Home Screen's. Before, its other gestures kept the touch until our menu's
// time, and on iPadOS 16 the Home Screen's own hold began its editing (jiggle mode) first, 0.7 s into a held click. Its other gestures let go now
// and once more on the next turn of the main queue (UIKit gives a touch its gestures around SpringBoard's -sendEvent:: which comes first is
// UIKit's). A secondary click keeps them (the note's own menu interaction opens its menu); a finger is not touched here (its quick swipe turns the
// page; its menu at 0.45 s lets them go, -dm_holdCheck:).
- (void)dm_notePointerPress:(UITouch *)t {
    if (![self dm_noteTracked] || !_trackPointer || _trackSecondary || !t || t != _track) return;
    _trackOwner = MSBDTouchDesktop;
    [self dm_noteTakeTouch:t];
    DM_FEATURE_MARK("sticky-note-pointer-press");
    __weak DMDesktop *ws = self; __weak UITouch *wt = t; CFTimeInterval at = _trackAt;
    dispatch_async(dispatch_get_main_queue(), ^{
        DMDesktop *s = ws; UITouch *x = wt;
        if (s && x && s->_track == x && s->_trackAt == at && x.phase != UITouchPhaseEnded && x.phase != UITouchPhaseCancelled) [s dm_noteTakeTouch:x];
    });
}
// A finger held still on a note's paper: at 0.2 s the note lifts (the dragged shadow), so the finger sees a move will drag it; back when the press
// ends without a drag (the drop puts the look back after one).
- (void)dm_noteHoldCueFor:(UITouch *)t {
    if (!_notes.track || _notes.trackBar || _trackPointer || !t) return;
    __weak DMDesktop *ws = self; __weak UITouch *wt = t; CFTimeInterval at = _trackAt;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(MSBD_NOTE_HOLD_TO_MOVE * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{ [ws dm_noteCueCheck:wt since:at]; });
}
- (void)dm_noteCueCheck:(UITouch *)t since:(CFTimeInterval)at {
    BOOL on = t && t == _track && _trackAt == at && t.phase != UITouchPhaseEnded && t.phase != UITouchPhaseCancelled;
    __weak DMDesktop *ws = self; __weak UITouch *wt = t;
    void (^again)(void) = ^{ dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.05 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{ [ws dm_noteCueCheck:wt since:at]; }); };
    DMNoteView *c = _notes.cued;
    if (c) {
        if (c == _notes.dragging) { _notes.cued = nil; return; }   // (it went on into a drag: the drop puts the look back)
        if (on) { again(); return; }
        _notes.cued = nil; DMStickyLiftLook(c, NO);
        return;
    }
    DMNoteView *v = _notes.track;
    if (!on || !v || !v.window || v.hidden || _trackMode || _lifted || hypot(_trackLast.x - _trackDown.x, _trackLast.y - _trackDown.y) > 10.0) return;
    _notes.cued = v; DMStickyLiftLook(v, YES);
    DM_FEATURE_MARK("sticky-note-hold-cue");
    again();
}
- (BOOL)dm_noteTracked { return _notes.track != nil && _trackView == nil; }
- (BOOL)dm_noteLiftAt:(CGPoint)sp {
    DMNoteView *v = _notes.track;
    if (!v || !v.window || v.hidden || !DMStickyShown()) return NO;
    DM_FEATURE_MARK("sticky-note-drag");
    if (_sel.count) [self dm_select:@[]];
    UIView *from = v.superview;   // (its page's layer: page 1's in the desktop, another page's in its list, 1.8.8.2 F36)
    CGPoint p = [from convertPoint:sp fromCoordinateSpace:(self.window.screen ?: [UIScreen mainScreen]).coordinateSpace];
    _notes.grab = CGPointMake(p.x - v.frame.origin.x, p.y - v.frame.origin.y);
    _notes.dragging = v; _notes.dragFrom = from; _notes.edgeSide = 0; _notes.edgeTurns = 0; _notes.turnedTo = -1;
    if (from == _notes.layer) [self addSubview:v]; else [from bringSubviewToFront:v];   // (over the icons while it is dragged)
    if (_notes.cued == v) _notes.cued = nil; else DMStickyLiftLook(v, YES);
    DMLog([NSString stringWithFormat:@"[notes] note %@ lifted (%@)", MSBDStickyShortId(v.noteId), _trackPointer ? @"a pointer drag" : @"a finger held and moved"]);
    return YES;
}
- (void)dm_noteDragTo:(CGPoint)sp {
    DMNoteView *v = _notes.dragging;
    if (!v) return;
    id<UICoordinateSpace> scr = (self.window.screen ?: [UIScreen mainScreen]).coordinateSpace;
    DMNoteView *rd = _notes.rider;
    UIView *in = rd ? rd.superview : v.superview;   // (a page turned: its picture in our menu window, screen space)
    if (!in) return;
    CGPoint p = [in convertPoint:sp fromCoordinateSpace:scr];
    CGRect f = (rd ?: v).frame; f.origin = CGPointMake(p.x - _notes.grab.x, p.y - _notes.grab.y);
    // (a page at rest covers the screen, so the free area in a page's space is the area on the screen: the rider is kept to it as the note is)
    CGRect area = rd ? [in convertRect:[self dm_area] fromCoordinateSpace:scr] : [self dm_area];
    DMStickySetFrame(rd ?: v, MSBDStickyClampInside(f, area), "a dragged note");
    [self dm_noteEdgeAt:sp];
}
// ---- to another page (1.8.8.2 F36): the finger kept at the screen's side turns the page; from the first turn the note rides in our menu window ----
- (void)dm_noteEdgeAt:(CGPoint)sp {
    int side = 0;
    if (_notes.pageIds.count >= 2 && _notes.dragging && !_editing) {
        CGRect ab = [self dm_area];   // (as on the screen: a page at rest covers it)
        side = MSBDStickyEdgeSide(sp.x, (self.window.screen ?: [UIScreen mainScreen]).bounds.size.width, CGRectGetMinX(ab), CGRectGetMaxX(ab));
    }
    if (side != _notes.edgeSide) { _notes.edgeSide = side; _notes.edgeSince = CACurrentMediaTime(); _notes.edgeTurns = 0; }
    if (!side || _notes.edgeTicking) return;
    _notes.edgeTicking = YES;
    __weak DMDesktop *ws = self;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.1 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{ [ws dm_noteEdgeTick]; });
}
- (void)dm_noteEdgeTick {
    _notes.edgeTicking = NO;
    if (!_notes.dragging || !_notes.edgeSide || _editing) return;
    if (MSBDStickyEdgeTurnDue(CACurrentMediaTime() - _notes.edgeSince, _notes.edgeTurns)) {
        id rfc = DMStickyRootFolder();
        UIView *scroll = _list.superview;
        long first = DMStickyFolderIndex(rfc, @"firstIconPageIndex"), last = DMStickyFolderIndex(rfc, @"lastIconPageIndex"), cur = DMStickyFolderIndex(rfc, @"currentPageIndex");
        long to = rfc ? MSBDStickyTurnTarget(cur, _notes.edgeSide, scroll.effectiveUserInterfaceLayoutDirection == UIUserInterfaceLayoutDirectionRightToLeft, first, last) : -1;
        _notes.edgeSince = CACurrentMediaTime();
        if (to >= 0 && [self dm_noteRide]) {
            _notes.edgeTurns++;
            DM_FEATURE_MARK("sticky-note-page-turn");
            DMLog([NSString stringWithFormat:@"[notes] note %@ held at the screen's %@ side: Home Screen page %ld to %ld", MSBDStickyShortId(_notes.dragging.noteId), _notes.edgeSide < 0 ? @"left" : @"right", cur - first + 1, to - first + 1]);
            DMStickyTurnTo(rfc, to);
            _notes.turnedTo = to - first;   // (the page it lands on if let go now, whatever iPadOS's index says mid slide: MSBDStickyDropPage)
        }
    }
    _notes.edgeTicking = YES;
    __weak DMDesktop *ws = self;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.1 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{ [ws dm_noteEdgeTick]; });
}
// The dragged note's picture into our menu window (screen space, over the pages as they slide), the note itself hidden in its layer until let go.
- (BOOL)dm_noteRide {
    if (_notes.rider) return YES;
    DMNoteView *v = _notes.dragging;
    NSMutableDictionary *e = DMStickyEntry(v.noteId);
    UIView *host = DMMenuHost();
    if (!v || !e || !host || !v.superview) return NO;
    id<UICoordinateSpace> scr = (self.window.screen ?: [UIScreen mainScreen]).coordinateSpace;
    DMNoteView *rd = [[DMNoteView alloc] initWithFrame:DMStickyFrame([host convertRect:[v.superview convertRect:v.frame toCoordinateSpace:scr] fromCoordinateSpace:scr], "a dragged note's picture")];
    rd.colorIndex = v.colorIndex; [rd dm_setBody:e[@"text"]]; [rd dm_setName:MSBDStickyNameShown(e[@"name"], e[@"text"])];
    rd.userInteractionEnabled = NO; rd.isAccessibilityElement = NO;
    DMStickyLiftLook(rd, YES);
    [host addSubview:rd];
    _notes.rider = rd; v.hidden = YES;
    return YES;
}
- (void)dm_noteDropAt:(CGPoint)sp {
    DMNoteView *v = _notes.dragging;
    _notes.track = nil;
    if (!v) return;
    [self dm_noteDragTo:sp];
    _notes.dragging = nil; _notes.edgeSide = 0;
    id<UICoordinateSpace> scr = (self.window.screen ?: [UIScreen mainScreen]).coordinateSpace;
    // (the page it lands on: once a page turned, the page the last turn went to, the one shown when the slide ends -- also let go mid slide,
    //  where iPadOS's own index still answers the page being left (seen on iPadOS 17.5.1); else the one it came from -- 1.8.8.2 F36)
    DMNoteView *rd = _notes.rider; _notes.rider = nil;
    UIView *from = _notes.dragFrom ?: _notes.layer; _notes.dragFrom = nil;
    long turnedTo = _notes.turnedTo; _notes.turnedTo = -1;
    NSUInteger page = rd ? MSBDStickyDropPage(turnedTo, [self dm_notePageNow], _notes.pageLists.count) : [self dm_notePageOfLayer:from];
    UIView *layer = rd ? [self dm_noteLayerFor:page make:YES] : from;
    CGRect area = [self dm_area], start = v.frame;
    if (rd) {   // (where the finger has its picture on the screen, on the page as it is at rest -- mid slide its layer is not where it will be)
        CGRect sf = rd.superview ? [rd.superview convertRect:rd.frame toCoordinateSpace:scr] : v.frame;
        CGRect pb = [layer convertRect:layer.bounds toCoordinateSpace:scr];
        start = CGRectOffset([layer convertRect:sf fromCoordinateSpace:scr], CGRectGetMinX(pb), CGRectGetMinY(pb));
        [rd removeFromSuperview]; v.hidden = NO;
    }
    NSArray<NSValue *> *occ = layer == _notes.layer ? [self dm_occupied] : [self dm_occupiedIn:[self dm_noteListOfPage:page] into:layer];
    CGRect *r = malloc(sizeof(CGRect) * MAX(1, occ.count));
    for (NSUInteger k = 0; k < occ.count; k++) r[k] = occ[k].CGRectValue;
    NSMutableDictionary *e = DMStickyEntry(v.noteId);
    CGRect anchor, f = DMStickyPlaceFit(DMStickyAtItsSize(e, start, area), area, r, (int)occ.count, &anchor, v.noteId);
    free(r);
    if (e) {
        NSArray *c = [self dm_fractionFor:CGPointMake(CGRectGetMidX(anchor), CGRectGetMidY(anchor)) area:area];   // (its own size's frame: the next layout gives the same)
        e[@"x"] = c[0]; e[@"y"] = c[1];
        NSString *key = page > 0 && page < _notes.pageIds.count ? MSBDStickyPageKey(_notes.pageIds[page]) : nil;   // (page 1: no key)
        if (key) e[@"page"] = key; else [e removeObjectForKey:@"page"];
        [gNotes removeObjectIdenticalTo:e]; [gNotes addObject:e];   // (moved: on top)
        DMStickyChanged(0.3);
    }
    [layer addSubview:v];   // (back under the icons, on its page)
    DMStickySetFrame(v, start, "a note let go");
    DMStickyLiftLook(v, NO);
    [UIView animateWithDuration:0.2 animations:^{ DMStickySetFrame(v, f, "a note let go, placed"); }];
    DMLog([NSString stringWithFormat:@"[notes] note %@ let go at %@ on Home Screen page %lu", MSBDStickyShortId(v.noteId), NSStringFromCGRect(f), (unsigned long)page + 1]);
    [_notes.pageLaidOut removeAllObjects];
    [self dm_placeAgain];   // (the icons step aside, keeping their places)
}
// ---- its menu: Color, Move to Trash (a finger held still, a click held, a right click) ----
- (UIMenu *)dm_noteMenuFor:(DMNoteView *)v {
    NSMutableDictionary *e = DMStickyEntry(v.noteId);
    if (!e) return nil;
    __weak DMDesktop *ws = self; NSString *noteId = v.noteId;
    NSMutableArray *colors = [NSMutableArray array];
    int now = MSBDStickyColorIndex(e[@"color"]);
    for (int i = 0; i < MSBD_NOTE_COLORS; i++) {
        UIAction *a = [UIAction actionWithTitle:MSBDStickyColorName(i) image:nil identifier:nil handler:^(UIAction *x) { [ws dm_noteSetColor:i of:noteId]; }];
        if (i == now) a.state = UIMenuElementStateOn;
        [colors addObject:a];
    }
    UIMenu *color = [UIMenu menuWithTitle:@"Color" image:[UIImage systemImageNamed:@"paintpalette"] identifier:nil options:0 children:colors];
    UIAction *rename = [UIAction actionWithTitle:@"Rename" image:[UIImage systemImageNamed:@"pencil"] identifier:nil handler:^(UIAction *x) { [ws dm_noteRename:noteId]; }];   // (1.8.8.2 F37)
    if (!DMStickyCanType()) rename.attributes = UIMenuElementAttributesDisabled;
    NSMutableArray *first = [NSMutableArray arrayWithObjects:color, rename, nil];
    [self dm_noteReadPages];
    if (_notes.pageIds.count >= 2) {   // (Move to Page, 1.8.8.2 F36: the Home Screen's pages, its own ticked; there with no drag)
        NSMutableArray *pages = [NSMutableArray array]; NSUInteger here = [self dm_notePageOf:e];
        for (NSUInteger i = 0; i < _notes.pageIds.count; i++) {
            UIAction *a = [UIAction actionWithTitle:[NSString stringWithFormat:@"Page %lu", (unsigned long)i + 1] image:nil identifier:nil handler:^(UIAction *x) { [ws dm_noteToPage:i of:noteId]; }];
            if (i == here) a.state = UIMenuElementStateOn;
            [pages addObject:a];
        }
        [first addObject:[UIMenu menuWithTitle:@"Move to Page" image:[UIImage systemImageNamed:@"rectangle.on.rectangle"] identifier:nil options:0 children:pages]];
    }
    UIAction *trash = [UIAction actionWithTitle:@"Move to Trash" image:[UIImage systemImageNamed:@"trash"] identifier:nil handler:^(UIAction *x) { [ws dm_noteTrash:noteId]; }];
    trash.attributes = UIMenuElementAttributesDestructive;
    return [UIMenu menuWithTitle:@"" children:@[[UIMenu menuWithTitle:@"" image:nil identifier:nil options:UIMenuOptionsDisplayInline children:first],
                                                [UIMenu menuWithTitle:@"" image:nil identifier:nil options:UIMenuOptionsDisplayInline children:@[trash]]]];
}
- (BOOL)dm_noteHoldMenuFor:(UITouch *)t {
    DMNoteView *v = [self dm_noteTracked] ? _notes.track : nil;
    if (!v) return NO;
    if (!v.window || v.hidden) return YES;
    UIMenu *menu = [self dm_noteMenuFor:v];
    UIView *host = DMMenuHost();
    if (!menu || !host) return YES;
    if (_sel.count) [self dm_select:@[]];
    for (UIGestureRecognizer *o in [t.gestureRecognizers copy]) if (![o.name hasPrefix:@"dm."] && o.enabled) { o.enabled = NO; o.enabled = YES; }   // (the press is ours now)
    _holdMenu = YES;
    DM_FEATURE_MARK("sticky-note-menu");
    DMLog([NSString stringWithFormat:@"[notes] %@ held still on note %@: its menu over the windows", _trackPointer ? @"a click" : @"a finger", MSBDStickyShortId(v.noteId)]);
    DMFinderShowMenuIn(host, menu, _trackDown);
    return YES;
}
- (BOOL)dm_noteOwnsMenu:(UIContextMenuInteraction *)i { return [i.view isKindOfClass:[DMNoteView class]]; }
// ---- its name (1.8.8.2 F37): edited in a field over its bar, inside its typing (begun first for an idle note) ----
- (void)dm_noteRename:(NSString *)noteId {
    NSMutableDictionary *e = DMStickyEntry(noteId);
    if (!e || _editing || !DMStickyShown()) return;
    if (![_notes.editor.noteId isEqualToString:noteId]) { DMNoteView *v = _notes.views[noteId]; if (!v) return; [self dm_noteBegin:v at:CGPointMake(NAN, NAN)]; }
    DMNoteEditor *ed = _notes.editor;
    if (!ed || ![ed.noteId isEqualToString:noteId] || _notes.nameField) return;
    DM_FEATURE_MARK("sticky-note-rename");
    // (the editor laid out first, so its bar has its frame: an idle note's editor was made a moment ago, in -dm_noteBegin:, and its bar's bounds were
    //  still zero -- a field made from them had an infinite origin, and the on-screen keyboard's selection grabbers over it a NaN position)
    [ed layoutIfNeeded];
    DMNoteNameField *tf = [[DMNoteNameField alloc] initWithFrame:DMStickyFrame(MSBDStickyNameFieldRect(ed.band.bounds), "the name field made")];   // (the bar lays it out from then on)
    tf.font = DMStickyNameFont(); tf.textAlignment = NSTextAlignmentCenter; tf.textColor = DMStickyInk(); tf.tintColor = DMStickyInk();
    tf.backgroundColor = [UIColor colorWithWhite:1.0 alpha:0.6]; tf.layer.cornerRadius = 4.0; tf.borderStyle = UITextBorderStyleNone;
    tf.returnKeyType = UIReturnKeyDone; tf.keyboardAppearance = UIKeyboardAppearanceLight;
    tf.text = MSBDStickyNameShown(e[@"name"], ed.textView.text ?: e[@"text"]);
    tf.delegate = _notes;
    _notes.nameField = tf;
    ed.band.nameHidden = YES;
    ed.band.field = tf; [ed.band addSubview:tf];
    [tf becomeFirstResponder];
    [tf selectAll:nil];
    DMLog([NSString stringWithFormat:@"[notes] note %@: its name is edited in its bar (%lu characters, first responder %d)", MSBDStickyShortId(noteId), (unsigned long)tf.text.length, tf.isFirstResponder]);
}
// keep: the name typed is the note's own (empty: back to the default); not: as it was. refocus: the note's text has the typing again.
- (void)dm_noteRenameEnd:(BOOL)keep refocus:(BOOL)refocus {
    DMNoteNameField *tf = _notes.nameField;
    if (!tf) return;
    _notes.nameField = nil; tf.delegate = nil;
    DMNoteEditor *ed = _notes.editor;
    NSMutableDictionary *e = DMStickyEntry(ed.noteId);
    if (keep && e) {
        NSString *typed = MSBDStickyNameClean(tf.text), *own = MSBDStickyNameClean(e[@"name"]), *text = ed.textView.text ?: e[@"text"];
        NSString *now = !typed ? nil : [typed isEqualToString:MSBDStickyNameShown(own, text)] ? own : typed;   // (unchanged: as it was; empty: the default)
        if (!(now == own || [now isEqualToString:own])) {
            if (now) e[@"name"] = now; else [e removeObjectForKey:@"name"];
            DMStickyChanged(0.3);
            NSUInteger len = MSBDStickyNameShown(now, text).length;
            DMLog([NSString stringWithFormat:@"[notes] note %@ %@ (%lu characters)", MSBDStickyShortId(ed.noteId), now ? @"renamed" : @"named after its text again", (unsigned long)len]);
        }
    }
    if (tf.isFirstResponder) [tf resignFirstResponder];
    [tf removeFromSuperview]; if (ed.band.field == tf) ed.band.field = nil;
    if (ed) { [ed.band dm_setName:MSBDStickyNameShown(e[@"name"], ed.textView.text ?: e[@"text"])]; ed.band.nameHidden = NO; }
    if (refocus && ed.superview && !ed.textView.isFirstResponder) [ed.textView becomeFirstResponder];
    if (ed) [self dm_noteFit];
}
// A tap on the bar of the note being typed in: the second one soon after the first edits its name.
- (void)dm_noteBarTap:(UITapGestureRecognizer *)g {
    DMNoteEditor *ed = _notes.editor;
    if (!ed || g.view != ed.band || _notes.nameField) return;
    CFTimeInterval now = CACurrentMediaTime();
    BOOL twice = MSBDStickyBarTwice(_notes.barTapId, ed.noteId, now - _notes.barTapAt);
    _notes.barTapId = twice ? nil : ed.noteId; _notes.barTapAt = now;
    if (twice) [self dm_noteRename:ed.noteId];
}
// A tap (or click) on an idle note's bar (1.8.8.2): the second one soon after the first edits its name (Rename's path: its typing begins with the
// field up); the first does not begin the typing at once (with the on-screen keyboard the note is lifted and its bar's taps are off, so a second tap
// never reached a bar): when the double tap's time is over, it begins as a bar tap's did (the caret at the end), unless something came between
// (StickyNotes.h MSBDStickyBarOnceTypes).
- (void)dm_noteIdleBarTap:(DMNoteView *)v {
    CFTimeInterval now = CACurrentMediaTime();
    if (MSBDStickyBarTwice(_notes.barTapId, v.noteId, now - _notes.barTapAt)) {
        _notes.barTapId = nil;
        DMLog([NSString stringWithFormat:@"[notes] note %@: its bar tapped twice: its name is edited", MSBDStickyShortId(v.noteId)]);
        [self dm_noteRename:v.noteId];
        return;
    }
    _notes.barTapId = v.noteId; _notes.barTapAt = now;
    NSString *noteId = v.noteId, *front = [DMActiveApp() bundleIdentifier] ?: @"";
    __weak DMDesktop *ws = self;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(MSBD_NOTE_BAR_TWICE * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{ [ws dm_noteBarOnce:noteId at:now front:front]; });
}
- (void)dm_noteBarOnce:(NSString *)noteId at:(CFTimeInterval)at front:(NSString *)front {
    BOOL mine = _notes.barTapAt == at && [_notes.barTapId isEqualToString:noteId];
    if (mine) _notes.barTapId = nil;
    if (!MSBDStickyBarOnceTypes(mine, _touchBeganAt > at, [[DMActiveApp() bundleIdentifier] ?: @"" isEqualToString:front], _notes.editor != nil)) {
        if (mine) DMLog([NSString stringWithFormat:@"[notes] note %@: its bar tapped once, then something else came: not typed in", MSBDStickyShortId(noteId)]);
        return;
    }
    DMNoteView *v = _notes.views[noteId ?: @""];
    if (v) [self dm_noteBegin:v at:CGPointMake(NAN, NAN)];
}
// A note's own menu interaction (a pointer's right click): our menu over the windows, as an icon's (-contextMenuInteraction:...); UIKit's never.
- (UIContextMenuConfiguration *)dm_noteConfigFor:(UIContextMenuInteraction *)i at:(CGPoint)loc {
    DMNoteView *v = (DMNoteView *)i.view;
    if (!(_trackSecondary && _trackPointer && _track && CACurrentMediaTime() - _trackAt < 1.0) || _ownMenuAt == _trackAt || !v.window || v.hidden) return nil;
    _trackSecondary = NO; _ownMenuAt = _trackAt;
    CGPoint sp = [i.view convertPoint:loc toCoordinateSpace:(self.window.screen ?: [UIScreen mainScreen]).coordinateSpace];
    CFTimeInterval press = _trackAt; __weak DMDesktop *ws = self; __weak DMNoteView *wv = v;
    dispatch_async(dispatch_get_main_queue(), ^{   // (after UIKit is done with this press; not for one gone on into a drag meanwhile)
        DMDesktop *s = ws; DMNoteView *x = wv;
        if (!s || !x || s->_trackAt != press || s->_trackMode || s->_lifted || s->_band) return;
        UIMenu *menu = [s dm_noteMenuFor:x];
        UIView *host = DMMenuHost();
        if (!menu || !host) return;
        DM_FEATURE_MARK("sticky-note-menu");
        DMLog([NSString stringWithFormat:@"[notes] secondary click on note %@: its menu over the windows", MSBDStickyShortId(x.noteId)]);
        DMFinderShowMenuIn(host, menu, sp);
    });
    return nil;
}
// Move to Page (1.8.8.2 F36): the note goes to that page at the same spot (every page is the screen's size), or the nearest free place there, and
// the Home Screen turns to that page with it (KT 22 Nov), the edge drag's turn: the root folder's own checked call, MSBDStickyPageTurnIndex's page.
- (void)dm_noteToPage:(NSUInteger)page of:(NSString *)noteId {
    NSMutableDictionary *e = DMStickyEntry(noteId); DMNoteView *v = _notes.views[noteId ?: @""];
    [self dm_noteReadPages];
    if (!e || !v || v == _notes.dragging || page >= _notes.pageIds.count || page == [self dm_notePageOf:e]) return;
    if ([_notes.editor.noteId isEqualToString:noteId]) [self dm_noteEnd:@"Move to Page"];
    UIView *layer = [self dm_noteLayerFor:page make:YES];
    CGRect area = [self dm_area];
    NSArray<NSValue *> *occ = layer == _notes.layer ? [self dm_occupied] : [self dm_occupiedIn:[self dm_noteListOfPage:page] into:layer];
    CGRect *r = malloc(sizeof(CGRect) * MAX(1, occ.count));
    for (NSUInteger k = 0; k < occ.count; k++) r[k] = occ[k].CGRectValue;
    CGRect anchor, f = DMStickyPlaceFit(DMStickyAtItsSize(e, v.frame, area), area, r, (int)occ.count, &anchor, noteId);
    free(r);
    DM_FEATURE_MARK("sticky-note-move-to-page");
    NSArray *c = [self dm_fractionFor:CGPointMake(CGRectGetMidX(anchor), CGRectGetMidY(anchor)) area:area];   // (its own size's frame: the next layout gives the same)
    e[@"x"] = c[0]; e[@"y"] = c[1];
    NSString *key = page > 0 ? MSBDStickyPageKey(_notes.pageIds[page]) : nil;
    if (key) e[@"page"] = key; else [e removeObjectForKey:@"page"];
    [gNotes removeObjectIdenticalTo:e]; [gNotes addObject:e];   // (on top there)
    DMStickyChanged(0.3);
    [layer addSubview:v]; DMStickySetFrame(v, f, "a note moved to a page");
    DMLog([NSString stringWithFormat:@"[notes] note %@ moved to Home Screen page %lu (Move to Page) at %@", MSBDStickyShortId(noteId), (unsigned long)page + 1, NSStringFromCGRect(f)]);
    [_notes.pageLaidOut removeAllObjects];
    [self dm_notePagesTick];
    [self dm_placeAgain];
    [self dm_noteShowPage:page];
}
// The Home Screen turned to one of the pages read (Move to Page): the root folder's own -setCurrentPageIndex:animated:, never in jiggle mode.
- (void)dm_noteShowPage:(NSUInteger)page {
    id rfc = _editing ? nil : DMStickyRootFolder();
    long first = DMStickyFolderIndex(rfc, @"firstIconPageIndex"), last = DMStickyFolderIndex(rfc, @"lastIconPageIndex"), cur = DMStickyFolderIndex(rfc, @"currentPageIndex");
    long to = rfc ? MSBDStickyPageTurnIndex((long)page, (long)_notes.pageLists.count, first, last) : -1;
    if (to < 0 || to == cur) { if (rfc && to < 0) DMLog([NSString stringWithFormat:@"[notes] Move to Page: the Home Screen not turned (the folder's pages %ld to %ld, %lu read)", first, last, (unsigned long)_notes.pageLists.count]); return; }
    DMLog([NSString stringWithFormat:@"[notes] Move to Page: Home Screen page %ld to %ld", cur - first + 1, to - first + 1]);
    DMStickyTurnTo(rfc, to);
}
- (void)dm_noteSetColor:(int)i of:(NSString *)noteId {
    NSMutableDictionary *e = DMStickyEntry(noteId);
    if (!e || [e[@"color"] isEqualToString:MSBDStickyColorName(i)]) return;
    DM_FEATURE_MARK("sticky-note-color");
    e[@"color"] = MSBDStickyColorName(i);
    DMStickyChanged(0.3);
    DMLog([NSString stringWithFormat:@"[notes] note %@ is %@ now", MSBDStickyShortId(noteId), MSBDStickyColorName(i)]);
    [self dm_noteStoreChanged];
}
// Move to Trash: an empty note just goes; one with text becomes "<its name>.txt" in Finder's Trash (DMStickyTrash, 1.8.8.2 F37) with Put Back and Undo.
- (void)dm_noteTrash:(NSString *)noteId {
    if ([_notes.editor.noteId isEqualToString:noteId]) [self dm_noteEnd:@"Move to Trash"];
    NSMutableDictionary *e = DMStickyEntry(noteId);
    if (!e) return;
    DM_FEATURE_MARK("sticky-note-trash");
    if (![e[@"text"] length]) {
        [gNotes removeObjectIdenticalTo:e];
        DMStickyChanged(0);
        DMLog([NSString stringWithFormat:@"[notes] note %@ went (empty: no Trash file)", MSBDStickyShortId(noteId)]);
        [self dm_noteStoreChanged];
        return;
    }
    DMStickyTrash(e);
}
- (NSString *)dm_noteDiag { return _notes ? [NSString stringWithFormat:@"; notes %lu, store %@, editing %d, switch %d, pages %@ (layers %lu, turn %d)", (unsigned long)gNotes.count, gNotesRead ? MSBDStickyStatusName(gNotesStatus) : @"not read", _notes.editor != nil, gDesktopNotesOn,
                                                     _notes.pageIds ? [NSString stringWithFormat:@"%lu", (unsigned long)_notes.pageIds.count] : @"off", (unsigned long)_notes.pageLayers.count, DMStickyRootFolder() != nil] : @""; }
#if DEBUG
// desk_note:<what>[,<args>] (debug builds only, through desk_): the notes' state and actions for the device rows. Text is printed only for notes whose
// text starts with MSB-TEST, and typed only when it does.
- (void)dm_noteDebug:(NSString *)arg {
    NSArray<NSString *> *q = [arg componentsSeparatedByString:@","];
    NSString *what = q.firstObject ?: @"state";
    NSMutableDictionary *(^byShort)(NSString *) = ^NSMutableDictionary *(NSString *s) { for (NSMutableDictionary *e in gNotes) if ([MSBDStickyShortId(e[@"id"]) isEqualToString:s]) return e; return nil; };
    id<UICoordinateSpace> scr = (self.window.screen ?: [UIScreen mainScreen]).coordinateSpace;
    if ([what isEqualToString:@"state"]) {
        DMLog([NSString stringWithFormat:@"[notes] test state: switch %d, store %@, %lu notes (%lu kept), editing %@, typing window %@ level %.1f key %d, keyboard %@, can type %d",
               gDesktopNotesOn, gNotesRead ? MSBDStickyStatusName(gNotesStatus) : @"not read", (unsigned long)gNotes.count, (unsigned long)gNotesKept.count,
               _notes.editor ? MSBDStickyShortId(_notes.editor.noteId) : @"-", gDesktopRenameWindow ? NSStringFromClass([gDesktopRenameWindow class]) : @"none", gDesktopRenameWindow.windowLevel,
               gDesktopRenameWindow.isKeyWindow, NSStringFromCGRect(gOwnKeyboardFrame), DMStickyCanType()]);
        for (NSDictionary *e in gNotes) {
            DMNoteView *v = _notes.views[e[@"id"]]; NSString *t = e[@"text"];
            NSString *nm = MSBDStickyNameShown(e[@"name"], t);
            DMLog([NSString stringWithFormat:@"[notes] test note %@ %@ at %@ (screen %@) stored %@x%@ at %.3f,%.3f, %lu characters%@%@%@", MSBDStickyShortId(e[@"id"]), e[@"color"],
                   v ? NSStringFromCGRect(v.frame) : @"-", v.window ? NSStringFromCGRect([v convertRect:v.bounds toCoordinateSpace:scr]) : @"-", e[@"w"], e[@"h"], [e[@"x"] doubleValue], [e[@"y"] doubleValue],
                   (unsigned long)t.length, v.hidden ? @", hidden" : @"", e[@"name"] ? @", own name" : @"",
                   [t hasPrefix:@"MSB-TEST"] && ([nm hasPrefix:@"MSB-TEST"] || [nm isEqualToString:MSBD_NOTE_DEFAULT_NAME]) ? [NSString stringWithFormat:@", name \"%@\", text %@", nm, t] : @""]);
        }
        if (_notes.editor) { DMNoteEditor *ed = _notes.editor;
            DMLog([NSString stringWithFormat:@"[notes] test editor %@ at %@ (screen %@), first responder %d, grips %d %d, inset %.1f, %lu characters", MSBDStickyShortId(ed.noteId), NSStringFromCGRect(ed.frame),
                   NSStringFromCGRect([ed convertRect:ed.bounds toCoordinateSpace:scr]), ed.textView.isFirstResponder, !ed.gripL.hidden, !ed.gripR.hidden, ed.textView.contentInset.bottom, (unsigned long)ed.textView.text.length]); }
    }
    else if ([what isEqualToString:@"new"]) [self dm_noteNewAt:q.count == 3 ? CGPointMake(q[1].doubleValue, q[2].doubleValue) : [self dm_screen:CGPointMake(CGRectGetMidX(self.bounds), CGRectGetMidY(self.bounds))]];
    else if ([what isEqualToString:@"begin"] && q.count == 2) { NSMutableDictionary *e = byShort(q[1]); DMNoteView *v = e ? _notes.views[e[@"id"]] : nil; if (v) [self dm_noteBegin:v at:CGPointMake(NAN, NAN)]; }
    else if ([what isEqualToString:@"type"] && q.count >= 2) { NSString *t = [[q subarrayWithRange:NSMakeRange(1, q.count - 1)] componentsJoinedByString:@","];
        if ([t hasPrefix:@"MSB-TEST"] && _notes.editor.textView) [_notes.editor.textView insertText:t]; else DMLog(@"[notes] test: type only MSB-TEST text, into a note being typed in"); }
    else if ([what isEqualToString:@"end"]) [self dm_noteEnd:@"desk_note:end"];
    else if ([what isEqualToString:@"color"] && q.count == 3) { NSMutableDictionary *e = byShort(q[1]); if (e) [self dm_noteSetColor:MSBDStickyColorIndex(q[2]) of:e[@"id"]]; }
    else if ([what isEqualToString:@"trash"] && q.count == 2) { NSMutableDictionary *e = byShort(q[1]); if (e) [self dm_noteTrash:e[@"id"]]; }
    else if ([what isEqualToString:@"move"] && q.count == 4) { NSMutableDictionary *e = byShort(q[1]); DMNoteView *v = e ? _notes.views[e[@"id"]] : nil;   // move,<id>,<x>,<y>: as if dragged to that screen point (its middle)
        if (v) { _notes.track = v; _trackView = nil; CGPoint at = [self dm_screen:CGPointMake(CGRectGetMidX(v.frame), CGRectGetMidY(v.frame))]; if ([self dm_noteLiftAt:at]) [self dm_noteDropAt:CGPointMake(q[2].doubleValue, q[3].doubleValue)]; } }
    else if ([what isEqualToString:@"menu"] && q.count == 2) { NSMutableDictionary *e = byShort(q[1]); UIMenu *m = e ? [self dm_noteMenuFor:_notes.views[e[@"id"]]] : nil; NSMutableArray *t = [NSMutableArray array];
        for (UIMenuElement *g in m.children) for (UIMenuElement *x in ((UIMenu *)g).children) {
            if ([x isKindOfClass:[UIMenu class]]) { NSMutableArray *s = [NSMutableArray array]; for (UIAction *a in ((UIMenu *)x).children) [s addObject:[NSString stringWithFormat:@"%@%@", a.title, a.state == UIMenuElementStateOn ? @" (on)" : @""]]; [t addObject:[NSString stringWithFormat:@"%@ > %@", x.title, [s componentsJoinedByString:@" / "]]]; }
            else [t addObject:[NSString stringWithFormat:@"%@%@", x.title, (((UIAction *)x).attributes & UIMenuElementAttributesDestructive) ? @" (red)" : @""]]; }
        DMLog([NSString stringWithFormat:@"[notes] test menu: %@", [t componentsJoinedByString:@" | "]]); }
    else if ([what isEqualToString:@"pages"]) {   // pages: the Home Screen's pages as read (short ids), which hold notes, their layers, the turn (1.8.8.2 F36)
        [self dm_noteReadPages];
        NSMutableArray *t = [NSMutableArray array];
        for (NSUInteger i = 0; i < _notes.pageLists.count; i++) {
            NSString *pid = i < _notes.pageIds.count ? _notes.pageIds[i] : nil; NSUInteger n = 0;
            for (NSDictionary *e in gNotes) if ([self dm_notePageOf:e] == i) n++;
            DMNotesPageView *l = pid ? _notes.pageLayers[pid] : nil;
            [t addObject:[NSString stringWithFormat:@"%lu %@ %lu note(s)%@%@", (unsigned long)i + 1, pid ? MSBDStickyShortId(pid) : @"-", (unsigned long)n, l ? (l.superview == _notes.pageLists[i] ? @" layer" : @" layer off its list") : @"", [self dm_notePageShowing:i] ? @" shown" : @""]];
        }
        NSUInteger hid = 0; for (NSDictionary *e in gNotes) if ([self dm_notePageOf:e] == MSBD_NOTE_PAGE_HIDDEN) hid++;
        DMLog([NSString stringWithFormat:@"[notes] test pages: %@; ids %d, hidden pages %@ (%lu note(s) hidden with them), now %lu, turn %d, kept off page 1: %@", [t componentsJoinedByString:@" | "], _notes.pageIds != nil,
               _notes.hiddenIds ? [NSString stringWithFormat:@"%lu", (unsigned long)_notes.hiddenIds.count] : @"not readable", (unsigned long)hid, (unsigned long)[self dm_notePageNow] + 1, DMStickyRootFolder() != nil,
               [[gNotes filteredArrayUsingPredicate:[NSPredicate predicateWithBlock:^BOOL(NSDictionary *e, id b) { return MSBDStickyPageIdOf(e[@"page"]) && [self dm_notePageOf:e] == 0; }]] count] ? @"some (their page not shown)" : @"none"]);
    }
    else if ([what isEqualToString:@"topage"] && q.count == 3) { NSMutableDictionary *e = byShort(q[1]); NSInteger n = q[2].integerValue; if (e && n >= 1) [self dm_noteToPage:(NSUInteger)(n - 1) of:e[@"id"]]; }   // topage,<id>,<n>: Move to Page n
    else if ([what isEqualToString:@"rename"] && q.count >= 2) { NSMutableDictionary *e = byShort(q[1]);   // rename,<id>: its name edited in its bar; rename,<id>,<MSB-TEST name>: set
        if (e && q.count == 2) [self dm_noteRename:e[@"id"]];
        else if (e) { NSString *n = [[q subarrayWithRange:NSMakeRange(2, q.count - 2)] componentsJoinedByString:@","];
            if ([n hasPrefix:@"MSB-TEST"]) { e[@"name"] = MSBDStickyNameClean(n); DMStickyChanged(0.3); [self dm_noteStoreChanged]; } else DMLog(@"[notes] test: only an MSB-TEST name"); } }
    else if ([what isEqualToString:@"purge"]) {   // purge: every note whose text starts with MSB-TEST, and every such sticky note file in Finder's Trash (never Empty Trash)
        NSUInteger n = 0;
        for (NSMutableDictionary *e in [gNotes copy]) if ([e[@"text"] hasPrefix:@"MSB-TEST"] || ![e[@"text"] length]) { if ([_notes.editor.noteId isEqualToString:e[@"id"]]) [self dm_noteEnd:@"desk_note:purge"]; [gNotes removeObjectIdenticalTo:e]; n++; }
        if (n) { DMStickyChanged(0); [self dm_noteStoreChanged]; }
        dispatch_async(DMFinderFileQueue(), ^{
            NSUInteger k = 0;
            for (NSString *f in [[NSFileManager defaultManager] contentsOfDirectoryAtPath:kFinderTrash error:nil]) {
                if (![f hasSuffix:@".txt"]) continue;
                NSString *p = [kFinderTrash stringByAppendingPathComponent:f];
                if (![DMFinderOrigin(p) isEqualToString:MSBD_NOTE_TRASH_ORIGIN]) continue;   // (a sticky note's file only: named after the note since 1.8.8.2)
                NSString *t = [NSString stringWithContentsOfFile:p encoding:NSUTF8StringEncoding error:nil];
                if ([t hasPrefix:@"MSB-TEST"] && !DMFinderRemove(p)) k++;
            }
            dispatch_async(dispatch_get_main_queue(), ^{ DMFinderRefreshFolders([NSSet setWithObject:kFinderTrash]); DMLog([NSString stringWithFormat:@"[notes] test purge: %lu test note(s) and %lu Trash file(s) removed", (unsigned long)n, (unsigned long)k]); });
        });
    }
    else if ([what isEqualToString:@"file"]) {   // file: the store's folder and file -- modes, owner, data protection class (device row F12)
        NSString *dir = DMStickyFolder(), *path = DMStickyPath();
        NSDictionary *da = [[NSFileManager defaultManager] attributesOfItemAtPath:dir error:nil], *fa = [[NSFileManager defaultManager] attributesOfItemAtPath:path error:nil];
        DMLog([NSString stringWithFormat:@"[notes] test file: folder %@ %lo %@, file %@ %lo %@ %@ %llu bytes", da ? @"there" : @"missing", [da[NSFilePosixPermissions] unsignedLongValue], da[NSFileOwnerAccountName] ?: @"-",
               fa ? @"there" : @"missing", [fa[NSFilePosixPermissions] unsignedLongValue], fa[NSFileOwnerAccountName] ?: @"-", fa[NSFileProtectionKey] ?: @"-", [fa[NSFileSize] unsignedLongLongValue]]);
    }
    else DMLog([NSString stringWithFormat:@"[notes] test: unknown desk_note:%@", what]);
}
#endif
@end
// ---- Move to Trash, Put Back and Undo (Finder.h's Trash: its file queue, its origin and place attributes, its Undo list) ----
// The Trash file: named after the note's name (1.8.8.2 F37, StickyNotes.h MSBDStickyTrashFileName: "<its name>.txt", numbered when taken; before,
// always "Sticky Note.txt"), the text as UTF-8, written to a hidden temp name in the Trash 0600 with class C and renamed in. Its origin is a marker
// (MSBD_NOTE_TRASH_ORIGIN, never a path), its place the icons' "fx,fy", its look "1 <color> <w> <h>" (MSBD_NOTE_TRASH_ATTR), and a note's own name
// MSBD_NOTE_TRASH_NAME_ATTR (none for a note named after its text). The note leaves the store only once the file is there.
__attribute__((noinline)) static void DMStickyTrash(NSMutableDictionary *e) {
    NSString *noteId = e[@"id"], *text = e[@"text"] ?: @"", *place = [NSString stringWithFormat:@"%.5f,%.5f", [e[@"x"] doubleValue], [e[@"y"] doubleValue]];
    NSString *look = MSBDStickyTrashAttr(e[@"color"], [e[@"w"] doubleValue], [e[@"h"] doubleValue]);
    NSString *fileName = MSBDStickyTrashFileName(MSBDStickyNameShown(e[@"name"], text)), *own = MSBDStickyNameClean(e[@"name"]), *pageKey = MSBDStickyPageRead(e[@"page"]);
    NSData *data = [text dataUsingEncoding:NSUTF8StringEncoding];
    dispatch_async(DMFinderFileQueue(), ^{
        NSError *err = DMFinderPrepareTrash(kFinderTrash);
        NSString *dst = nil;
        if (!err) {
            dst = DMFinderFreeName(kFinderTrash, fileName, @"");
            NSString *tmp = [kFinderTrash stringByAppendingPathComponent:[NSString stringWithFormat:@".sticky-note-%@.new", [NSUUID UUID].UUIDString]];
            BOOL ok = [[NSFileManager defaultManager] createFileAtPath:tmp contents:data attributes:@{NSFilePosixPermissions: @0600, NSFileProtectionKey: NSFileProtectionCompleteUntilFirstUserAuthentication}];
            if (ok) {
                DMFinderSetOrigin(tmp, MSBD_NOTE_TRASH_ORIGIN);
                DMFinderSetDesktopPlace(tmp, place);
                ok = setxattr(tmp.fileSystemRepresentation, MSBD_NOTE_TRASH_ATTR, look.UTF8String, strlen(look.UTF8String), 0, XATTR_NOFOLLOW) == 0;
                if (ok && own) ok = setxattr(tmp.fileSystemRepresentation, MSBD_NOTE_TRASH_NAME_ATTR, own.UTF8String, strlen(own.UTF8String), 0, XATTR_NOFOLLOW) == 0;
                if (ok && pageKey) ok = setxattr(tmp.fileSystemRepresentation, MSBD_NOTE_TRASH_PAGE_ATTR, pageKey.UTF8String, strlen(pageKey.UTF8String), 0, XATTR_NOFOLLOW) == 0;   // (its page, 1.8.8.2 F36)
            }
            if (ok) ok = rename(tmp.fileSystemRepresentation, dst.fileSystemRepresentation) == 0;
            if (!ok) { unlink(tmp.fileSystemRepresentation); err = DMFinderError(@"The sticky note couldn't be moved to the Trash."); }
        }
        dispatch_async(dispatch_get_main_queue(), ^{
            if (err) { DMLog(@"[notes] Move to Trash: the Trash file could not be made, the note stays"); [DMFinderOps() fail:err what:@"Move to Trash"]; return; }
            NSMutableDictionary *now = DMStickyEntry(noteId);
            if (now) [gNotes removeObjectIdenticalTo:now];
            DMStickyChanged(0);
            DMFinderPushUndo(@"notetrash", @"Move to Trash", @[@[MSBD_NOTE_TRASH_ORIGIN, DMFinderNorm(dst)]]);
            DMFinderRefreshFolders([NSSet setWithObject:kFinderTrash]);
            DMLog([NSString stringWithFormat:@"[notes] note %@ moved to the Trash (%lu characters)", MSBDStickyShortId(noteId), (unsigned long)text.length]);
            DMStickyStoreChangedForDesktop();
        });
    });
}
// Put Back (Finder's Trash, dm_run's putback) and Undo of a Move to Trash: the file becomes a note again -- its colour, place and size, a new id, on
// top -- and the file goes once the store is written (DMFinderRemove: only ever inside the Trash). Refused, with the reason, while Show Sticky Notes is
// off (the check's item 13), while the store is not readable or is a newer one's, and at 30 notes. `done` on the main thread.
__attribute__((noinline)) static void DMStickyPutBack(NSString *path, void (^done)(NSError *e)) {
    void (^fail)(NSString *) = ^(NSString *why) { DMLog(@"[notes] Put Back refused"); if (done) done(DMFinderError(why)); };
    if (!gDesktopNotesOn) { fail(@"Turn on Show Sticky Notes in Settings > Desktop to put this sticky note back."); return; }
    DMStickyLoad(^{
        if (!MSBDStickyWritable(gNotesStatus)) { fail(gNotesStatus == MSBDStickyNewer ? @"The sticky notes were saved by a newer version of MacStatusBar&Dock." : @"The sticky notes can't be read yet. Try again in a moment."); return; }
        if (gNotes.count >= MSBD_NOTES_MAX) { fail([NSString stringWithFormat:@"There are already %d sticky notes. Move one to the Trash first.", MSBD_NOTES_MAX]); return; }
        dispatch_async(DMStickyQueue(), ^{
            int err = 0; NSData *d = DMStickyReadFile(path, &err);
            NSString *text = d ? [[NSString alloc] initWithData:d encoding:NSUTF8StringEncoding] : nil;
            char buf[128]; ssize_t n = getxattr(path.fileSystemRepresentation, MSBD_NOTE_TRASH_ATTR, buf, sizeof buf - 1, 0, XATTR_NOFOLLOW);
            NSString *look = n > 0 ? [[NSString alloc] initWithBytes:buf length:(NSUInteger)n encoding:NSUTF8StringEncoding] : nil;
            n = getxattr(path.fileSystemRepresentation, kFinderDesktopPlaceAttr, buf, sizeof buf - 1, 0, XATTR_NOFOLLOW);
            NSString *place = n > 0 ? [[NSString alloc] initWithBytes:buf length:(NSUInteger)n encoding:NSUTF8StringEncoding] : nil;
            char nb[1024]; ssize_t nn = getxattr(path.fileSystemRepresentation, MSBD_NOTE_TRASH_NAME_ATTR, nb, sizeof nb - 1, 0, XATTR_NOFOLLOW);   // (its own name, 1.8.8.2 F37)
            NSString *ownName = nn > 0 ? MSBDStickyNameClean([[NSString alloc] initWithBytes:nb length:(NSUInteger)nn encoding:NSUTF8StringEncoding]) : nil;
            nn = getxattr(path.fileSystemRepresentation, MSBD_NOTE_TRASH_PAGE_ATTR, nb, sizeof nb - 1, 0, XATTR_NOFOLLOW);   // (its page, 1.8.8.2 F36: shown on page 1 while that page is not)
            NSString *pageKey = nn > 0 ? MSBDStickyPageRead([[NSString alloc] initWithBytes:nb length:(NSUInteger)nn encoding:NSUTF8StringEncoding]) : nil;
            dispatch_async(dispatch_get_main_queue(), ^{
                if (!text) { fail(@"The sticky note can't be read."); return; }
                if (gNotes.count >= MSBD_NOTES_MAX) { fail([NSString stringWithFormat:@"There are already %d sticky notes. Move one to the Trash first.", MSBD_NOTES_MAX]); return; }
                NSString *color = @"Yellow"; double w = MSBD_NOTE_W, h = MSBD_NOTE_H, fx = 0.5, fy = 0.5;
                MSBDStickyTrashAttrRead(look, &color, &w, &h);
                MSBDStickyPlaceRead(place, &fx, &fy);
                NSMutableDictionary *e = [@{@"id": [NSUUID UUID].UUIDString, @"color": color, @"x": @(fx), @"y": @(fy), @"w": @(w), @"h": @(h), @"text": MSBDStickyTextCut(text, MSBD_NOTE_TEXT_MAX)} mutableCopy];
                if (ownName) e[@"name"] = ownName;
                if (pageKey && [gDesktop dm_notePageShownFor:pageKey]) e[@"page"] = pageKey;   // (its page shown now: there; else page 1)
                [gNotes addObject:e];
                DMStickyWriteNow(^(BOOL ok) {
                    if (!ok) { [gNotes removeObjectIdenticalTo:e]; DMStickyStoreChangedForDesktop(); fail(@"The sticky note couldn't be saved."); return; }
                    DM_FEATURE_MARK("sticky-note-put-back");
                    DMLog([NSString stringWithFormat:@"[notes] a note put back from the Trash as %@ (%lu characters)", MSBDStickyShortId(e[@"id"]), (unsigned long)[e[@"text"] length]]);
                    DMStickyStoreChangedForDesktop();
                    dispatch_async(DMFinderFileQueue(), ^{
                        NSError *re = DMFinderRemove(path);
                        dispatch_async(dispatch_get_main_queue(), ^{ if (re) DMLog(@"[notes] the put-back note's Trash file could not be removed"); DMFinderRefreshFolders([NSSet setWithObject:kFinderTrash]); if (done) done(nil); });
                    });
                });
            });
        });
    });
}
__attribute__((noinline)) static NSString *DMStickyOrigin(NSString *origin) { return [origin isEqualToString:MSBD_NOTE_TRASH_ORIGIN] ? origin : nil; }
// Undo of a Move to Trash (Finder's Undo list, kind "notetrash"): each note put back; one no longer in the Trash is passed over, as Finder's Undo does.
__attribute__((noinline)) static void DMStickyUndoTrash(NSArray<NSArray<NSString *> *> *pairs, DMFinderWindow *window) {
    for (NSArray<NSString *> *pr in pairs) {
        if (pr.count != 2 || !DMStickyOrigin(pr[0]) || !DMFinderTaken(pr[1])) continue;
        __weak DMFinderWindow *ww = window;
        DMStickyPutBack(pr[1], ^(NSError *e) { if (e) [ww fail:e what:@"Undo Move to Trash"]; });
    }
}
// Our Respring: the note being typed in and the store written before SpringBoard goes (waited for, on its queue).
__attribute__((noinline)) static void DMStickyFlush(void) {
    if (gDesktop) [gDesktop dm_noteEnd:@"our Respring"];
    if (!gNotesRead) return;   // (never read: nothing of ours to write, and no file made for someone who never used a note)
    if (gNotesGen != gNotesWrittenGen && MSBDStickyWritable(gNotesStatus)) { gNotesGen++; DMStickyWriteNow(nil); }   // (a change not written yet: now -- a save waiting is this one)
    dispatch_sync(DMStickyQueue(), ^{});   // (and every write on its way finished)
}
// The screen going off, a lock, the Cover Sheet coming down (StatusBar.x): the typing ends, saved.
__attribute__((noinline)) static void DMStickyEnd(NSString *why) { if (gDesktop) [gDesktop dm_noteEnd:why]; }
__attribute__((noinline)) static void DMStickyStoreChangedForDesktop(void) { [gDesktop dm_noteStoreChanged]; }
// axdump (StatusBar.x, debug): a note's value is its text -- only its length is printed. nil: not a note's view.
__attribute__((noinline)) static NSString *DMStickyAXDumpValue(UIView *v) {
    if ([v isKindOfClass:[DMNoteView class]]) return [NSString stringWithFormat:@"(%lu characters)", (unsigned long)[(DMNoteView *)v dm_bodyLength]];
    if ([v isKindOfClass:[DMNoteTextView class]]) return [NSString stringWithFormat:@"(%lu characters)", (unsigned long)((DMNoteTextView *)v).text.length];
    return nil;
}
// (Desktop.h's typing touch, for the screen-edge pulls: one of the note's resize grips, or its top bar, at that screen point)
__attribute__((noinline)) static BOOL DMStickyGripAt(CGPoint sp) { return gDesktop && [gDesktop dm_noteGripAt:sp]; }
