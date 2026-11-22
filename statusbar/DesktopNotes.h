// DesktopNotes.h -- Sticky Notes on the desktop (1.8.8.1, sticky-notes.md Design v2 with the check's fixes 1-7), included at the end of Desktop.h.
// The rules (colours, frames, the store's read rule, the caps) are common/StickyNotes.h, tested on the Mac (tools/test-stickynotes.sh).
//  - A note lives on Home Screen page 1, in a layer of the desktop's under every icon: behind the app windows, the app icons, widgets and page dots
//    (it keeps clear of them, they take its touches), on every Mac Switcher desktop, hidden in jiggle mode and Guided Access with the desktop.
//    Desktop icons keep clear of notes (DesktopPlace.h's soft rects) and keep their saved places for when the note moves away.
//  - The empty desktop's menu has New Sticky Note. A tap on a note types in it: it lifts into the desktop's typing window (Desktop.h, the one a name
//    is typed in), above the windows and the Dock, with the keyboard, both bottom-corner resize grips (the windows' maths, NativeWindow.h
//    DMNativeResized) and the Command editing keys (TextWindow.h DMTextViewEditKey). A touch elsewhere, Esc, the screen going off, a lock, the Cover
//    Sheet, another app in front, a native window made active, the Mac Switcher, jiggle mode, page 1 going and the switches end the typing; every
//    way saves, gives back the focus lock and the key window, and shows the note at its own place. The keyboard's hide key leaves it active.
//  - Idle, a finger held 0.3 s then moved drags it like an icon (a pointer at once); held still, or a right click, opens its menu: Color, Move to
//    Trash. With text, Move to Trash makes "Sticky Note.txt" in Finder's Trash (0600, data protection class C); Put Back and Undo make it a note again.
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

// ---- the views ----
__attribute__((noinline)) static UIColor *DMStickyColor(int i, BOOL band) {
    int k = i >= 0 && i < MSBD_NOTE_COLORS ? i : 0; CGFloat r, g, b;
    MSBDStickyRGB(band ? kMSBDStickyColors[k].band : kMSBDStickyColors[k].body, &r, &g, &b);
    return [UIColor colorWithRed:r green:g blue:b alpha:1];
}
__attribute__((noinline)) static UIColor *DMStickyInk(void) { return [UIColor colorWithRed:0x1E / 255.0 green:0x1E / 255.0 blue:0x1E / 255.0 alpha:1]; }   // (near black on every colour, both appearances)
__attribute__((noinline)) static UIFont *DMStickyFont(void) { return [UIFont systemFontOfSize:16.0]; }
static const CGFloat kDMNoteCorner = 4.0, kDMNoteSide = 8.0, kDMNoteUnderBand = 6.0, kDMNoteGrip = 22.0;
// The idle note: drawn, not a text view (one UITextView only, the note being typed in: memory, and no UIKit description that prints its text).
@interface DMNoteView : UIView
@property (nonatomic, copy) NSString *noteId;
@property (nonatomic) int colorIndex;
- (void)dm_setBody:(NSString *)body;
- (NSUInteger)dm_bodyLength;
@end
@implementation DMNoteView { NSString *_body; }   // (an ivar: no method named text -- UIView's own description reads one)
- (instancetype)initWithFrame:(CGRect)frame {
    if (!(self = [super initWithFrame:frame])) return nil;
    self.opaque = NO; self.backgroundColor = [UIColor clearColor]; self.contentMode = UIViewContentModeRedraw;
    self.layer.shadowColor = [UIColor blackColor].CGColor; self.layer.shadowOpacity = 0.25; self.layer.shadowRadius = 6.0; self.layer.shadowOffset = CGSizeMake(0, 3);
    self.isAccessibilityElement = YES;
    _body = @"";
    return self;
}
- (void)dm_setBody:(NSString *)body { NSString *b = MSBDStickyTextCut(body, MSBD_NOTE_TEXT_MAX); if ([b isEqualToString:_body]) return; _body = b; [self setNeedsDisplay]; }
- (NSUInteger)dm_bodyLength { return _body.length; }
- (void)setColorIndex:(int)i { if (i == _colorIndex) return; _colorIndex = i; [self setNeedsDisplay]; }
- (void)layoutSubviews { [super layoutSubviews]; self.layer.shadowPath = [UIBezierPath bezierPathWithRoundedRect:self.bounds cornerRadius:kDMNoteCorner].CGPath; }
- (void)drawRect:(CGRect)rect {
    CGRect b = self.bounds;
    UIBezierPath *paper = [UIBezierPath bezierPathWithRoundedRect:b cornerRadius:kDMNoteCorner];
    [DMStickyColor(_colorIndex, NO) setFill]; [paper fill];
    CGContextRef c = UIGraphicsGetCurrentContext();
    CGContextSaveGState(c); [paper addClip];
    [DMStickyColor(_colorIndex, YES) setFill]; UIRectFill(CGRectMake(0, 0, b.size.width, MSBD_NOTE_BAND));
    CGContextRestoreGState(c);
    if (!_body.length) return;
    NSString *shown = _body.length > MSBD_NOTE_DRAW_MAX ? MSBDStickyTextCut(_body, MSBD_NOTE_DRAW_MAX) : _body;   // (cut off at the bottom, no scrolling)
    NSMutableParagraphStyle *ps = [NSMutableParagraphStyle new]; ps.lineBreakMode = NSLineBreakByWordWrapping;
    CGRect tr = CGRectMake(kDMNoteSide, MSBD_NOTE_BAND + kDMNoteUnderBand, b.size.width - 2 * kDMNoteSide, b.size.height - MSBD_NOTE_BAND - 2 * kDMNoteUnderBand);
    CGContextSaveGState(c); UIRectClip(tr);
    [shown drawWithRect:tr options:NSStringDrawingUsesLineFragmentOrigin attributes:@{NSFontAttributeName: DMStickyFont(), NSForegroundColorAttributeName: DMStickyInk(), NSParagraphStyleAttributeName: ps} context:nil];
    CGContextRestoreGState(c);
}
// (assistive features: one element -- "Sticky Note, Yellow", never its text; its value is the text, which VoiceOver has to read; using it types in it)
- (NSString *)accessibilityLabel { return [@"Sticky Note, " stringByAppendingString:MSBDStickyColorName(_colorIndex)]; }
- (NSString *)accessibilityValue { return _body; }
- (UIAccessibilityTraits)accessibilityTraits { return UIAccessibilityTraitButton; }
- (BOOL)accessibilityActivate { DMDesktop *d = gDesktop; return d && [self isDescendantOfView:d] && [d dm_noteAXActivate:self]; }
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
// The note being typed in, in the desktop's typing window: the paper, its band, the one text view, and two resize grips at the bottom corners as
// our windows have (NativeWindow.h: the pill turned 45 degrees, half outside the paper, 22 pt hot areas, pans named "dm.note.resize").
@interface DMNoteEditor : UIView
@property (nonatomic, copy) NSString *noteId;
@property (nonatomic, strong) DMNoteTextView *textView;
@property (nonatomic, strong) UIView *band, *gripL, *gripR;
@property (nonatomic) BOOL placed;
- (instancetype)initWithFrame:(CGRect)frame color:(int)color text:(NSString *)text target:(id)target;
@end
@implementation DMNoteEditor
- (instancetype)initWithFrame:(CGRect)frame color:(int)color text:(NSString *)text target:(id)target {
    if (!(self = [super initWithFrame:frame])) return nil;
    self.backgroundColor = DMStickyColor(color, NO);
    self.layer.cornerRadius = kDMNoteCorner; self.layer.cornerCurve = kCACornerCurveContinuous;
    self.layer.shadowColor = [UIColor blackColor].CGColor; self.layer.shadowOpacity = 0.35; self.layer.shadowRadius = 18.0; self.layer.shadowOffset = CGSizeMake(0, 10);   // (the native windows' shadow: lifted)
    _band = [UIView new]; _band.backgroundColor = DMStickyColor(color, YES); _band.userInteractionEnabled = NO;
    _band.layer.cornerRadius = kDMNoteCorner; _band.layer.maskedCorners = kCALayerMinXMinYCorner | kCALayerMaxXMinYCorner;
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
        g.transform = CGAffineTransformMakeRotation(side == 0 ? -M_PI_4 : M_PI_4);
        g.backgroundColor = DMResizeGripColor(NO);   // (the paper is always light)
        UIView *hot = [[UIView alloc] initWithFrame:CGRectMake(0, 0, kDMNoteGrip, kDMNoteGrip)];
        hot.tag = side;
        [hot addSubview:g]; g.center = CGPointMake(kDMNoteGrip / 2.0, kDMNoteGrip / 2.0);
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
    _band.frame = CGRectMake(0, 0, b.size.width, MSBD_NOTE_BAND);
    _textView.frame = CGRectMake(0, MSBD_NOTE_BAND, b.size.width, b.size.height - MSBD_NOTE_BAND);
    _gripL.frame = CGRectMake(-kDMNoteGrip / 2.0 + 6.0, b.size.height - kDMNoteGrip / 2.0 - 6.0, kDMNoteGrip, kDMNoteGrip);
    _gripR.frame = CGRectMake(b.size.width - kDMNoteGrip / 2.0 - 6.0, b.size.height - kDMNoteGrip / 2.0 - 6.0, kDMNoteGrip, kDMNoteGrip);
}
// (the grips' halves outside the paper take their touches too, as a native window's: NativeWindow.h -dm_takesPoint:, the check's item 5)
- (BOOL)pointInside:(CGPoint)q withEvent:(UIEvent *)e { return CGRectContainsPoint(self.bounds, q) || (!_gripL.hidden && CGRectContainsPoint(_gripL.frame, q)) || (!_gripR.hidden && CGRectContainsPoint(_gripR.frame, q)); }
- (NSString *)description { return [NSString stringWithFormat:@"<%@: %p; %lu characters>", NSStringFromClass([self class]), self, (unsigned long)_textView.text.length]; }
- (NSString *)debugDescription { return [self description]; }
@end
// The desktop's notes: their layer, their views, the note under a press, the note being typed in.
@interface DMNotesState : NSObject
@property (nonatomic, strong) UIView *layer;
@property (nonatomic, strong) NSMutableDictionary<NSString *, DMNoteView *> *views;
@property (nonatomic, weak) DMNoteView *track;          // (the note a press on the desktop began on, -dm_event:)
@property (nonatomic, weak) DMNoteView *dragging;       // (... held and moved: it follows the finger, over the icons)
@property (nonatomic) CGPoint grab;
@property (nonatomic, strong) DMNoteEditor *editor;     // (the note being typed in)
@property (nonatomic, copy) NSString *editFront;        // (the app in front when its typing began: another one ends it)
@property (nonatomic, weak) UIWindow *keyBefore;
@property (nonatomic) CGRect home, resizeStart;         // (screen points: the note's own place; the editor's frame as a resize began)
@property (nonatomic) BOOL resizing;                    // (a grip is being pulled: the keyboard's moves leave the editor where the finger has it)
@end
@implementation DMNotesState
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

@implementation DMDesktop (Notes)
- (void)dm_noteInit {
    _notes = [DMNotesState new];
    _notes.views = [NSMutableDictionary dictionary];
    UIView *layer = [[UIView alloc] initWithFrame:self.bounds];
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
        if (!v || v == _notes.dragging) continue;
        CGRect f = MSBDStickyFrameAt(area, [self dm_pointFor:@[e[@"x"], e[@"y"]] area:area], CGSizeMake([e[@"w"] doubleValue], [e[@"h"] doubleValue]));
        f = MSBDStickyPlaceClear(f, area, r, (int)occ.count, MSBD_NOTE_CLEAR_TESTS, NULL);
        if (!CGRectEqualToRect(v.frame, f)) v.frame = f;
    }
    free(r);
    if (_notes.editor) [self dm_noteFit];   // (its own place moved: a turn, the Dock, More Space)
}
// Icons keep clear of the notes (soft rects: DesktopPlace.h nHard), the one being typed in too (its place is kept for it).
- (void)dm_noteTakeInto:(DMPlacer *)pl {
    if (!_notes || _notes.layer.hidden) return;
    for (DMNoteView *v in _notes.views.allValues) if (v.superview && v != _notes.dragging) DMPlacerTake(pl, v.frame);
}
// The views made, removed and drawn as the store has the notes; then a layout pass (the icons step aside).
- (void)dm_noteStoreChanged {
    if (!_notes) return;
    BOOL shown = DMStickyShown();
    _notes.layer.hidden = !shown;
    NSMutableSet *ids = [NSMutableSet set];
    for (NSDictionary *e in shown ? gNotes : @[]) {
        NSString *noteId = e[@"id"]; [ids addObject:noteId];
        DMNoteView *v = _notes.views[noteId];
        if (!v) {
            CGRect area = [self dm_area];
            v = [[DMNoteView alloc] initWithFrame:MSBDStickyFrameAt(area, [self dm_pointFor:@[e[@"x"], e[@"y"]] area:area], CGSizeMake([e[@"w"] doubleValue], [e[@"h"] doubleValue]))];
            v.noteId = noteId;
            _notes.views[noteId] = v;
            [_notes.layer addSubview:v];
            [self dm_addMenu:[[UIContextMenuInteraction alloc] initWithDelegate:self] to:v];   // (a right click: its menu, -contextMenuInteraction:configurationForMenuAtLocation:)
        }
        v.colorIndex = MSBDStickyColorIndex(e[@"color"]);
        if (!(_notes.editor && [_notes.editor.noteId isEqualToString:noteId])) { [v dm_setBody:e[@"text"]]; v.hidden = NO; }
        if (v != _notes.dragging) [_notes.layer bringSubviewToFront:v];   // (the stacking order: last on top)
    }
    NSMutableArray *gone = [NSMutableArray array];
    for (NSString *noteId in _notes.views) if (![ids containsObject:noteId]) [gone addObject:noteId];
    if (_notes.editor && [gone containsObject:_notes.editor.noteId]) { [self dm_noteEnd:@"the note went"]; return; }   // (that ends here again)
    for (NSString *noteId in gone) { [_notes.views[noteId] removeFromSuperview]; [_notes.views removeObjectForKey:noteId]; }
    [self dm_placeAgain];
}
- (UIView *)dm_noteHitAt:(CGPoint)p {   // (-hitTest:withEvent:, after the icons: they lie over the notes)
    if (!_notes || _notes.layer.hidden) return nil;
    for (UIView *v in [_notes.layer.subviews reverseObjectEnumerator]) if ([v isKindOfClass:[DMNoteView class]] && !v.hidden && v.alpha > 0.01 && CGRectContainsPoint(v.frame, p)) return v;
    return nil;
}
- (BOOL)dm_noteAtScreen:(CGPoint)sp { return [self dm_noteHitAt:[self convertPoint:sp fromCoordinateSpace:(self.window.screen ?: [UIScreen mainScreen]).coordinateSpace]] != nil; }
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
// ---- a tap: the note is typed in, the caret where the finger touched (at the end below the text) ----
- (void)dm_noteTap:(UITapGestureRecognizer *)g {
    CGPoint p = [g locationInView:self];
    DMNoteView *v = (DMNoteView *)[self dm_noteHitAt:p];
    if (!v || _editing || gOverlay) return;   // (a menu of ours open: the hold's lift, not a tap)
    if (_notes.track == v && CACurrentMediaTime() - _trackAt > (_trackPointer ? kDMDesktopHoldMenuPointer : kDMDesktopHoldMenu)) return;   // (held past the menu's time)
    [self dm_noteBegin:v at:[self dm_screen:p]];
}
- (BOOL)dm_noteAXActivate:(UIView *)v {
    if (![v isKindOfClass:[DMNoteView class]] || !v.window || _editing || !self.userInteractionEnabled) return NO;
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
    [_notes.layer bringSubviewToFront:nv];
    id<UICoordinateSpace> scr = (self.window.screen ?: [UIScreen mainScreen]).coordinateSpace;
    CGRect home = [nv convertRect:nv.bounds toCoordinateSpace:scr];
    DMNoteEditor *ed = [[DMNoteEditor alloc] initWithFrame:[host convertRect:home fromCoordinateSpace:scr] color:MSBDStickyColorIndex(e[@"color"]) text:e[@"text"] target:self];
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
    CGRect area = self.window ? [self convertRect:[self dm_area] toCoordinateSpace:scr] : _notes.home;
    CGRect f = MSBDStickyLift(_notes.home, gOwnKeyboardFrame, CGRectGetMinY(area), &inset);
    BOOL lifted = !CGRectEqualToRect(f, _notes.home);
    ed.gripL.hidden = lifted; ed.gripR.hidden = lifted;
    UIEdgeInsets ci = ed.textView.contentInset; ci.bottom = inset; ed.textView.contentInset = ci;
    if (inset > 0) [ed.textView scrollRangeToVisible:ed.textView.selectedRange];
    CGRect local = [host convertRect:f fromCoordinateSpace:(host.window.screen ?: [UIScreen mainScreen]).coordinateSpace];
    if (CGRectEqualToRect(ed.frame, local)) return;
    if (!ed.placed) { ed.placed = YES; ed.frame = local; return; }
    [UIView animateWithDuration:0.2 animations:^{ ed.frame = local; }];
    DMLog([NSString stringWithFormat:@"[notes] note %@ %@ (keyboard %@)", MSBDStickyShortId(ed.noteId), lifted ? @"lifted above the keyboard" : @"at its own place", NSStringFromCGRect(gOwnKeyboardFrame)]);
}
// A bottom corner's grip: the windows' maths (NativeWindow.h DMNativeResized: the left grip keeps the right edge, the minimum, never wider than the
// free area or past its bottom), then kept inside the area (the check's item 14). Kept as the note's own size and place when the finger lifts.
// (inside YES: the moving side stops at the area's side, so the other side stays where it is; 1.8.8.2 B72, the left grip pulled past the area's
//  left side grew the note to the right)
- (void)dm_noteResize:(UIPanGestureRecognizer *)g {
    DMNoteEditor *ed = _notes.editor;
    UIView *host = ed.superview;
    if (!ed || !host || g.view.superview != ed) return;
    id<UICoordinateSpace> scr = (host.window.screen ?: [UIScreen mainScreen]).coordinateSpace;
    if (g.state == UIGestureRecognizerStateBegan) { _notes.resizeStart = ed.frame; _notes.resizing = YES; DM_FEATURE_MARK("sticky-note-resize"); }
    CGRect desk = [host convertRect:[self convertRect:[self dm_area] toCoordinateSpace:(self.window.screen ?: [UIScreen mainScreen]).coordinateSpace] fromCoordinateSpace:scr];
    CGRect f = MSBDStickyClampInside(DMNativeResized(_notes.resizeStart, [g translationInView:host], (int)g.view.tag, CGSizeMake(MSBD_NOTE_MIN_W, MSBD_NOTE_MIN_H), desk, YES), desk);
    ed.frame = f;
    if (g.state != UIGestureRecognizerStateEnded && g.state != UIGestureRecognizerStateCancelled && g.state != UIGestureRecognizerStateFailed) return;
    _notes.resizing = NO;
    NSMutableDictionary *e = DMStickyEntry(ed.noteId);
    if (!e || !self.window) return;
    CGRect mine = [self convertRect:[host convertRect:f toCoordinateSpace:scr] fromCoordinateSpace:(self.window.screen ?: [UIScreen mainScreen]).coordinateSpace];
    NSArray *c = [self dm_fractionFor:CGPointMake(CGRectGetMidX(mine), CGRectGetMidY(mine)) area:[self dm_area]];
    e[@"x"] = c[0]; e[@"y"] = c[1]; e[@"w"] = @(round(mine.size.width)); e[@"h"] = @(round(mine.size.height));
    DMStickyChanged(0.3);
    DMLog([NSString stringWithFormat:@"[notes] note %@ resized to %.0f x %.0f", MSBDStickyShortId(ed.noteId), mine.size.width, mine.size.height]);
    [self dm_placeAgain]; [self layoutIfNeeded];   // (its own place again, kept clear; the icons step aside)
}
- (BOOL)dm_noteGripAt:(CGPoint)sp {
    DMNoteEditor *ed = _notes.editor;
    if (!ed.window) return NO;
    id<UICoordinateSpace> scr = (ed.window.screen ?: [UIScreen mainScreen]).coordinateSpace;
    for (UIView *g in @[ed.gripL, ed.gripR]) if (!g.hidden && CGRectContainsPoint([g convertRect:g.bounds toCoordinateSpace:scr], sp)) return YES;
    return NO;
}
// Keys while a note is typed in (the desktop has them first, -dm_hasKeys): Esc ends; the Command editing keys are the note's own; Return and every
// other key go on to the text view (NO: SpringBoard's own handling types them). Nothing reaches an active Finder or TextEdit window.
- (BOOL)dm_noteKey:(UIKey *)key {
    UIKeyModifierFlags m = key.modifierFlags & (UIKeyModifierCommand | UIKeyModifierShift | UIKeyModifierAlternate | UIKeyModifierControl);
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
    if (!_notes.editor) return;
    NSString *why = nil;
    if (_editing) why = @"jiggle mode or Guided Access";
    else if (!DMStickyShown()) why = @"Show Sticky Notes is off";
    else if (![self dm_pageShowing]) why = @"page 1 no longer shows";
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
- (BOOL)dm_noteTrackBegin:(UIView *)at {
    DMNoteView *v = [at isKindOfClass:[DMNoteView class]] && [at isDescendantOfView:self] && !at.hidden ? (DMNoteView *)at : nil;
    if (_notes) _notes.track = v;
    return v != nil;
}
- (BOOL)dm_noteTracked { return _notes.track != nil && _trackView == nil; }
- (BOOL)dm_noteLiftAt:(CGPoint)sp {
    DMNoteView *v = _notes.track;
    if (!v || !v.window || v.hidden || !DMStickyShown()) return NO;
    DM_FEATURE_MARK("sticky-note-drag");
    if (_sel.count) [self dm_select:@[]];
    CGPoint p = [self convertPoint:sp fromCoordinateSpace:(self.window.screen ?: [UIScreen mainScreen]).coordinateSpace];
    _notes.grab = CGPointMake(p.x - v.frame.origin.x, p.y - v.frame.origin.y);
    _notes.dragging = v;
    [self addSubview:v];   // (over the icons while it is dragged)
    v.layer.shadowOpacity = 0.35; v.layer.shadowRadius = 18.0; v.layer.shadowOffset = CGSizeMake(0, 10);
    DMLog([NSString stringWithFormat:@"[notes] note %@ lifted (%@)", MSBDStickyShortId(v.noteId), _trackPointer ? @"a pointer drag" : @"a finger held and moved"]);
    return YES;
}
- (void)dm_noteDragTo:(CGPoint)sp {
    DMNoteView *v = _notes.dragging;
    if (!v) return;
    CGPoint p = [self convertPoint:sp fromCoordinateSpace:(self.window.screen ?: [UIScreen mainScreen]).coordinateSpace];
    CGRect f = v.frame; f.origin = CGPointMake(p.x - _notes.grab.x, p.y - _notes.grab.y);
    v.frame = MSBDStickyClampInside(f, [self dm_area]);
}
- (void)dm_noteDropAt:(CGPoint)sp {
    DMNoteView *v = _notes.dragging;
    _notes.track = nil;
    if (!v) return;
    [self dm_noteDragTo:sp];
    _notes.dragging = nil;
    CGRect area = [self dm_area];
    NSArray<NSValue *> *occ = [self dm_occupied];
    CGRect *r = malloc(sizeof(CGRect) * MAX(1, occ.count));
    for (NSUInteger k = 0; k < occ.count; k++) r[k] = occ[k].CGRectValue;
    CGRect f = MSBDStickyPlaceClear(MSBDStickyClampInside(v.frame, area), area, r, (int)occ.count, MSBD_NOTE_CLEAR_TESTS, NULL);
    free(r);
    NSMutableDictionary *e = DMStickyEntry(v.noteId);
    if (e) {
        NSArray *c = [self dm_fractionFor:CGPointMake(CGRectGetMidX(f), CGRectGetMidY(f)) area:area];
        e[@"x"] = c[0]; e[@"y"] = c[1];
        [gNotes removeObjectIdenticalTo:e]; [gNotes addObject:e];   // (moved: on top)
        DMStickyChanged(0.3);
    }
    [_notes.layer addSubview:v];   // (back under the icons)
    v.layer.shadowOpacity = 0.25; v.layer.shadowRadius = 6.0; v.layer.shadowOffset = CGSizeMake(0, 3);
    [UIView animateWithDuration:0.2 animations:^{ v.frame = f; }];
    DMLog([NSString stringWithFormat:@"[notes] note %@ let go at %@", MSBDStickyShortId(v.noteId), NSStringFromCGRect(f)]);
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
    UIAction *trash = [UIAction actionWithTitle:@"Move to Trash" image:[UIImage systemImageNamed:@"trash"] identifier:nil handler:^(UIAction *x) { [ws dm_noteTrash:noteId]; }];
    trash.attributes = UIMenuElementAttributesDestructive;
    return [UIMenu menuWithTitle:@"" children:@[[UIMenu menuWithTitle:@"" image:nil identifier:nil options:UIMenuOptionsDisplayInline children:@[color]],
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
- (void)dm_noteSetColor:(int)i of:(NSString *)noteId {
    NSMutableDictionary *e = DMStickyEntry(noteId);
    if (!e || [e[@"color"] isEqualToString:MSBDStickyColorName(i)]) return;
    DM_FEATURE_MARK("sticky-note-color");
    e[@"color"] = MSBDStickyColorName(i);
    DMStickyChanged(0.3);
    DMLog([NSString stringWithFormat:@"[notes] note %@ is %@ now", MSBDStickyShortId(noteId), MSBDStickyColorName(i)]);
    [self dm_noteStoreChanged];
}
// Move to Trash: an empty note just goes; one with text becomes "Sticky Note.txt" in Finder's Trash (DMStickyTrash) with Put Back and Undo.
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
- (NSString *)dm_noteDiag { return _notes ? [NSString stringWithFormat:@"; notes %lu, store %@, editing %d, switch %d", (unsigned long)gNotes.count, gNotesRead ? MSBDStickyStatusName(gNotesStatus) : @"not read", _notes.editor != nil, gDesktopNotesOn] : @""; }
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
            DMLog([NSString stringWithFormat:@"[notes] test note %@ %@ at %@ (screen %@) stored %@x%@ at %.3f,%.3f, %lu characters%@%@", MSBDStickyShortId(e[@"id"]), e[@"color"],
                   v ? NSStringFromCGRect(v.frame) : @"-", v.window ? NSStringFromCGRect([v convertRect:v.bounds toCoordinateSpace:scr]) : @"-", e[@"w"], e[@"h"], [e[@"x"] doubleValue], [e[@"y"] doubleValue],
                   (unsigned long)t.length, v.hidden ? @", hidden" : @"", [t hasPrefix:@"MSB-TEST"] ? [@", text " stringByAppendingString:t] : @""]);
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
    else if ([what isEqualToString:@"purge"]) {   // purge: every note whose text starts with MSB-TEST, and every such Sticky Note*.txt in Finder's Trash (never Empty Trash)
        NSUInteger n = 0;
        for (NSMutableDictionary *e in [gNotes copy]) if ([e[@"text"] hasPrefix:@"MSB-TEST"] || ![e[@"text"] length]) { if ([_notes.editor.noteId isEqualToString:e[@"id"]]) [self dm_noteEnd:@"desk_note:purge"]; [gNotes removeObjectIdenticalTo:e]; n++; }
        if (n) { DMStickyChanged(0); [self dm_noteStoreChanged]; }
        dispatch_async(DMFinderFileQueue(), ^{
            NSUInteger k = 0;
            for (NSString *f in [[NSFileManager defaultManager] contentsOfDirectoryAtPath:kFinderTrash error:nil]) {
                if (![f hasPrefix:@"Sticky Note"] || ![f hasSuffix:@".txt"]) continue;
                NSString *p = [kFinderTrash stringByAppendingPathComponent:f];
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
// The Trash file: "Sticky Note.txt" (numbered when taken; the name never comes from the text), the text as UTF-8, written to a hidden temp name in the
// Trash 0600 with class C and renamed in. Its origin is a marker (MSBD_NOTE_TRASH_ORIGIN, never a path), its place the icons' "fx,fy", its look
// "1 <color> <w> <h>" (MSBD_NOTE_TRASH_ATTR). The note leaves the store only once the file is there.
__attribute__((noinline)) static void DMStickyTrash(NSMutableDictionary *e) {
    NSString *noteId = e[@"id"], *text = e[@"text"] ?: @"", *place = [NSString stringWithFormat:@"%.5f,%.5f", [e[@"x"] doubleValue], [e[@"y"] doubleValue]];
    NSString *look = MSBDStickyTrashAttr(e[@"color"], [e[@"w"] doubleValue], [e[@"h"] doubleValue]);
    NSData *data = [text dataUsingEncoding:NSUTF8StringEncoding];
    dispatch_async(DMFinderFileQueue(), ^{
        NSError *err = DMFinderPrepareTrash(kFinderTrash);
        NSString *dst = nil;
        if (!err) {
            dst = DMFinderFreeName(kFinderTrash, MSBD_NOTE_TRASH_NAME, @"");
            NSString *tmp = [kFinderTrash stringByAppendingPathComponent:[NSString stringWithFormat:@".sticky-note-%@.new", [NSUUID UUID].UUIDString]];
            BOOL ok = [[NSFileManager defaultManager] createFileAtPath:tmp contents:data attributes:@{NSFilePosixPermissions: @0600, NSFileProtectionKey: NSFileProtectionCompleteUntilFirstUserAuthentication}];
            if (ok) {
                DMFinderSetOrigin(tmp, MSBD_NOTE_TRASH_ORIGIN);
                DMFinderSetDesktopPlace(tmp, place);
                ok = setxattr(tmp.fileSystemRepresentation, MSBD_NOTE_TRASH_ATTR, look.UTF8String, strlen(look.UTF8String), 0, XATTR_NOFOLLOW) == 0;
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
            dispatch_async(dispatch_get_main_queue(), ^{
                if (!text) { fail(@"The sticky note can't be read."); return; }
                if (gNotes.count >= MSBD_NOTES_MAX) { fail([NSString stringWithFormat:@"There are already %d sticky notes. Move one to the Trash first.", MSBD_NOTES_MAX]); return; }
                NSString *color = @"Yellow"; double w = MSBD_NOTE_W, h = MSBD_NOTE_H, fx = 0.5, fy = 0.5;
                MSBDStickyTrashAttrRead(look, &color, &w, &h);
                MSBDStickyPlaceRead(place, &fx, &fy);
                NSMutableDictionary *e = [@{@"id": [NSUUID UUID].UUIDString, @"color": color, @"x": @(fx), @"y": @(fy), @"w": @(w), @"h": @(h), @"text": MSBDStickyTextCut(text, MSBD_NOTE_TEXT_MAX)} mutableCopy];
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
// (Desktop.h's typing touch, for the screen-edge pulls: one of the note's resize grips at that screen point)
__attribute__((noinline)) static BOOL DMStickyGripAt(CGPoint sp) { return gDesktop && [gDesktop dm_noteGripAt:sp]; }
