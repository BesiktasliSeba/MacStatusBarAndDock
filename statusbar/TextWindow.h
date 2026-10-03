// TextWindow.h -- a TextEdit-style window for plain text files (2026-10-03), a native window (NativeWindow.h) like Finder's, included into
// StatusBar.x after Finder.h. Opening a text file -- from the desktop, a Finder window, the Dock's Downloads stack -- shows it here, one window
// per file (opening it again brings that window forward), titled with the file's name.
//  - Plain text only: what Finder's Quick Look shows as text (DMQLIsText), up to 1 MB, that reads as text: UTF-8 (a byte order mark is kept on
//    save), or an encoding the file itself names. Anything else -- larger, binary, UTF-16 (zero bytes) -- goes to Quick Look as before. Read off
//    the main thread (a file on a USB drive is slow).
//  - Editable only where Finder may change the file (the user's own places, DMFinderCanChange); elsewhere it opens read-only ("Read Only" in
//    the title).
//  - Saved ~1 s after typing stops, on Command-S and on close (atomically, through NSFileCoordinator in File Provider storage, as Finder's own
//    writes); "Edited" in the title while unsaved. A change on disk while open and unedited is read again; edited on both sides, ours is kept.
//  - The window follows its file, not its path, as TextEdit follows a document: renamed or moved (here, in Finder, in the Files app), the title
//    and the saves go with it; moved to the Trash or deleted, it stops saving -- "Moved to Trash" / "Deleted" in the title, no typing, closing
//    writes nothing --, so a file that went is never made again at its old place. Put Back from the Trash: followed back, editable again.
//  - Keys (the native layer's -dm_handleKey:, SpringBoard's key handling): Command-S, Command-W, Command-Z / Shift-Command-Z, Command-C / V / X / A;
//    Esc ends the typing. Everything else is the text view's own typing.
@interface DMTextWindow : DMNativeWindow <UITextViewDelegate>
@property (nonatomic, copy) NSString *file;
- (instancetype)initWithFile:(NSString *)path text:(NSString *)text encoding:(NSStringEncoding)enc bom:(BOOL)bom editable:(BOOL)editable;
- (void)dm_save;
#if DEBUG
- (void)dm_debugType:(NSString *)s; - (NSString *)dm_debugState;
#endif
@end
static dispatch_queue_t DMTextQueue(void) {
    static dispatch_queue_t q; static dispatch_once_t once;
    dispatch_once(&once, ^{ q = dispatch_queue_create("com.besiktasliseba.text.save", DISPATCH_QUEUE_SERIAL); });
    return q;
}
// The file's text and encoding (and whether it starts with UTF-8's byte order mark, which NSString drops), or nil when it is not plain text
// this window takes (not text, over 1 MB, not readable as text). Any thread.
static NSString *DMTextRead(NSString *path, NSStringEncoding *enc, BOOL *bom) {
    struct stat st;
    if (stat(path.fileSystemRepresentation, &st) != 0 || !S_ISREG(st.st_mode) || st.st_size > 1024 * 1024) return nil;
    if (!DMQLIsText(path, [UTType typeWithFilenameExtension:path.pathExtension])) return nil;
    NSData *d = [NSData dataWithContentsOfFile:path];
    if (!d) return nil;
    if (memchr(d.bytes, 0, d.length)) return nil;   // (a zero byte: not plain text)
    NSString *s = [[NSString alloc] initWithData:d encoding:NSUTF8StringEncoding];
    if (s) { *enc = NSUTF8StringEncoding; *bom = d.length >= 3 && memcmp(d.bytes, "\xEF\xBB\xBF", 3) == 0; return s; }
    *bom = NO;
    NSStringEncoding used = 0;
    s = [NSString stringWithContentsOfFile:path usedEncoding:&used error:nil];
    if (s && used) { *enc = used; return s; }
    return nil;
}
@implementation DMTextWindow {
    UITextView *_text;
    NSStringEncoding _enc;
    BOOL _editable, _edited, _bom;
    BOOL _gone; NSString *_goneWhy;   // (moved to the Trash, or deleted: nothing is saved any more)
    int _fileFD;                      // (the file's own watch: its descriptor follows the file wherever it goes, -dm_locate)
    NSUInteger _saveSerial;
    NSDate *_savedDate;   // (the file's modification date as we last read or wrote it: a change on disk is anything else)
    dispatch_source_t _watch, _watchFile;
}
- (instancetype)initWithFile:(NSString *)path text:(NSString *)text encoding:(NSStringEncoding)enc bom:(BOOL)bom editable:(BOOL)editable {
    CGRect d = DMNativeDesktop();
    CGFloat w = MIN(620.0, d.size.width - 60.0), h = MIN(460.0, d.size.height - 60.0);
    NSUInteger n = gNativeWindows.count;
    if (!(self = [super initWithTitle:path.lastPathComponent frame:CGRectMake(CGRectGetMidX(d) - w / 2.0 + 20.0 * (n % 6), CGRectGetMidY(d) - h / 2.0 + 20.0 * (n % 6), w, h)])) return nil;
    _file = [path copy]; _enc = enc; _bom = bom; _editable = editable; _fileFD = -1;
    self.appName = @"TextEdit";
    self.minSize = CGSizeMake(280.0, 180.0);
    _text = [[UITextView alloc] initWithFrame:self.contentView.bounds];
    _text.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    _text.font = [UIFont systemFontOfSize:13.0];
    _text.textColor = [UIColor labelColor];
    _text.backgroundColor = [UIColor systemBackgroundColor];
    _text.textContainerInset = UIEdgeInsetsMake(10.0, 8.0, 10.0, 8.0);
    _text.autocorrectionType = UITextAutocorrectionTypeNo; _text.autocapitalizationType = UITextAutocapitalizationTypeNone;
    _text.spellCheckingType = UITextSpellCheckingTypeNo; _text.smartQuotesType = UITextSmartQuotesTypeNo; _text.smartDashesType = UITextSmartDashesTypeNo;
    _text.alwaysBounceVertical = YES;
    _text.editable = editable;
    _text.text = text;
    _text.delegate = self;
    [self.contentView addSubview:_text];
    _savedDate = [[NSFileManager defaultManager] attributesOfItemAtPath:path error:nil].fileModificationDate;
    [self dm_updateTitle];
    [self dm_watch];
    return self;
}
- (void)dm_updateTitle {
    NSString *t = self.file.lastPathComponent;
    if (_gone) t = [t stringByAppendingFormat:@" • %@", _goneWhy];
    else if (!_editable) t = [t stringByAppendingString:@" • Read Only"];
    else if (_edited) t = [t stringByAppendingString:@" • Edited"];
    self.title = t;
    for (UIView *v in self.titleBar.subviews) if ([v isKindOfClass:[UILabel class]]) ((UILabel *)v).text = t;   // (the title bar's label shows the title)
}
- (void)show {
    [super show];
    if (_editable && !_gone && !_text.isFirstResponder) {   // (typing goes here at once, with the hardware or the on-screen keyboard)
        if (!gNativeLayer.isKeyWindow) [gNativeLayer makeKeyWindow];
        [_text becomeFirstResponder];
    }
}
- (void)textViewDidChange:(UITextView *)tv {
    if (!_edited) { _edited = YES; [self dm_updateTitle]; }
    NSUInteger serial = ++_saveSerial; __weak DMTextWindow *ws = self;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{   // (a second after the typing stops)
        DMTextWindow *s = ws; if (s && s->_saveSerial == serial) [s dm_save];
    });
}
- (void)dm_save {
    if (!_editable || !_edited) return;
    DM_FEATURE_MARK("text-window-save");
    if (![self dm_locate]) { DMLog([NSString stringWithFormat:@"[text] not saved: the file is gone (%@)", _goneWhy]); return; }   // (never made again where it was)
    NSString *path = self.file, *text = _text.text ?: @"";
    if (!DMFinderCanChange(path)) { DMLog(@"[text] not saved: the file is outside the user's places now"); return; }
    NSData *data = [text dataUsingEncoding:_enc];
    if (!data) {   // (a character the file's own encoding can't hold: it becomes UTF-8 now, and stays so)
        DMLog(@"[text] the file's encoding can't hold the text: saved as UTF-8");
        _enc = NSUTF8StringEncoding; data = [text dataUsingEncoding:NSUTF8StringEncoding];
    }
    if (_bom && _enc == NSUTF8StringEncoding) { NSMutableData *m = [NSMutableData dataWithBytes:"\xEF\xBB\xBF" length:3]; [m appendData:data]; data = m; }
    _edited = NO; [self dm_updateTitle];
    __weak DMTextWindow *ws = self;
    dispatch_async(DMTextQueue(), ^{
        __block BOOL ok = NO; NSError *ce = nil;
        if (DMFinderCoordinated(path)) [[[NSFileCoordinator alloc] initWithFilePresenter:nil] coordinateWritingItemAtURL:[NSURL fileURLWithPath:path] options:NSFileCoordinatorWritingForReplacing error:&ce byAccessor:^(NSURL *u) { ok = [data writeToURL:u atomically:YES]; }];
        else ok = [data writeToFile:path atomically:YES];
        NSDate *date = [[NSFileManager defaultManager] attributesOfItemAtPath:path error:nil].fileModificationDate;
        dispatch_async(dispatch_get_main_queue(), ^{
            DMTextWindow *s = ws;
            DMLog([NSString stringWithFormat:@"[text] saved: %@ (%lu bytes)", ok ? @"yes" : @"FAILED", (unsigned long)data.length]);
            if (!s) return;
            if (ok) { s->_savedDate = date; if ([s.file isEqualToString:path]) [s dm_watch]; DMFinderRefreshFolders([NSSet setWithObject:path.stringByDeletingLastPathComponent]); }
            else { s->_edited = YES; [s dm_updateTitle]; [s sheetTitle:[NSString stringWithFormat:@"“%@” couldn't be saved", path.lastPathComponent] message:ce.localizedDescription field:nil action:@"OK" destructive:NO then:^(NSString *t) {}]; }
        });
    });
}
// The file and its folder are watched (an atomic save replaces the file, which only the folder sees; a write in place only the file sees): a
// change by someone else is read again while ours is unedited.
- (dispatch_source_t)dm_watchPath:(NSString *)p mask:(unsigned long)mask {
    int fd = open(p.fileSystemRepresentation, O_EVTONLY | O_SYMLINK);   // (a link: the link itself, never its target -- 1.3 logic re-check R2)
    if (fd < 0) return nil;
    dispatch_source_t src = dispatch_source_create(DISPATCH_SOURCE_TYPE_VNODE, (uintptr_t)fd, mask, dispatch_get_main_queue());
    if (!src) { close(fd); return nil; }
    __weak DMTextWindow *ws = self;
    dispatch_source_set_event_handler(src, ^{
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.3 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{ [ws dm_diskChanged]; });
    });
    dispatch_source_set_cancel_handler(src, ^{ close(fd); });
    dispatch_resume(src);
    return src;
}
- (void)dm_unwatch {
    if (_watch) { dispatch_source_cancel(_watch); _watch = nil; }
    if (_watchFile) { dispatch_source_cancel(_watchFile); _watchFile = nil; }
    _fileFD = -1;   // (closed by the source's cancel handler)
}
- (void)dm_watch {
    [self dm_unwatch];
    _watch = [self dm_watchPath:self.file.stringByDeletingLastPathComponent mask:DISPATCH_VNODE_WRITE | DISPATCH_VNODE_DELETE | DISPATCH_VNODE_RENAME | DISPATCH_VNODE_LINK];
    _watchFile = [self dm_watchPath:self.file mask:DISPATCH_VNODE_WRITE | DISPATCH_VNODE_EXTEND | DISPATCH_VNODE_ATTRIB | DISPATCH_VNODE_DELETE | DISPATCH_VNODE_RENAME];
    _fileFD = _watchFile ? (int)dispatch_source_get_handle(_watchFile) : -1;
}
- (void)dm_markGone:(NSString *)why {
    if (_gone && [_goneWhy isEqualToString:why]) return;
    _gone = YES; _goneWhy = why;
    _text.editable = NO;
    if (_text.isFirstResponder) [_text resignFirstResponder];
    [self dm_updateTitle];
    DMLog([NSString stringWithFormat:@"[text] the file was %@: no more saves%@", why.lowercaseString, _edited ? @" (the unsaved typing stays in the window)" : @""]);
}
// Where the file is now. Its own watch's descriptor stays on the file through a rename or a move, so the kernel tells its path (F_GETPATH):
// another name or folder is followed; the Trash marks the window (and Put Back is followed out again). A file with no links left was deleted
// -- or replaced at its path by an atomic save (ours, another app's): then the new file at the path is the file. NO when there is none to save to.
- (BOOL)dm_locate {
    struct stat st; char buf[MAXPATHLEN];
    if (_fileFD >= 0 && fstat(_fileFD, &st) == 0 && st.st_nlink > 0 && fcntl(_fileFD, F_GETPATH, buf) == 0) {
        NSString *now = DMFinderNorm([[NSFileManager defaultManager] stringWithFileSystemRepresentation:buf length:strlen(buf)]);
        if (now.length && ![now isEqualToString:self.file]) {
            BOOL trashed = DMFinderInTrash(now);   // (Finder's Trash, iCloud's, a drive's -- or any other app's .Trash folder)
            for (NSString *c in now.pathComponents) if ([c hasPrefix:@".Trash"]) trashed = YES;
            self.file = now;
            _editable = DMFinderCanChange(now) && access(now.fileSystemRepresentation, W_OK) == 0;
            if (trashed) [self dm_markGone:@"Moved to Trash"];
            else {
                if (_gone) DMLog(@"[text] the file is back from the Trash: saved again");
                _gone = NO; _goneWhy = nil;
                _text.editable = _editable;
                DMLog(@"[text] the file was renamed or moved: the window follows it");
            }
            [self dm_watch];   // (its folder may be another one now)
            [self dm_updateTitle];
        }
        return !_gone;
    }
    if (!_gone && lstat(self.file.fileSystemRepresentation, &st) == 0 && S_ISREG(st.st_mode)) { [self dm_watch]; return YES; }   // (replaced at its path)
    if (!_gone || ![_goneWhy isEqualToString:@"Deleted"]) { [self dm_unwatch]; [self dm_markGone:@"Deleted"]; }
    return NO;
}
- (void)dm_diskChanged {
    if (![self dm_locate]) return;   // (moved to the Trash or deleted: the window keeps what it shows, and saves nothing)
    NSDate *date = [[NSFileManager defaultManager] attributesOfItemAtPath:self.file error:nil].fileModificationDate;
    if (!date || [date isEqualToDate:_savedDate]) return;   // (our own save)
    if (_edited) { DMLog(@"[text] the file changed on disk while edited here: ours is kept (saved over it)"); return; }
    NSString *path = self.file; NSStringEncoding enc0 = _enc; __weak DMTextWindow *ws = self;
    dispatch_async(DMTextQueue(), ^{   // (read off the main thread, then shown if nothing changed meanwhile)
        NSStringEncoding enc = enc0; BOOL bom = NO;
        NSString *t = DMTextRead(path, &enc, &bom);
        dispatch_async(dispatch_get_main_queue(), ^{
            DMTextWindow *s = ws;
            if (!t || !s || s->_edited || s->_gone || ![s.file isEqualToString:path]) return;
            s->_savedDate = date; s->_enc = enc; s->_bom = bom;
            [s dm_watch];   // (the file may be a new one now: watched again)
            NSRange sel = s->_text.selectedRange;
            s->_text.text = t;
            s->_text.selectedRange = NSMakeRange(MIN(sel.location, t.length), 0);
            DMLog(@"[text] the file changed on disk: read again");
        });
    });
}
- (void)close {
    [self dm_save];
    [self dm_unwatch];
    [_text resignFirstResponder];
    [super close];
}
- (BOOL)dm_handleKey:(UIKey *)key {
    UIKeyModifierFlags m = key.modifierFlags & (UIKeyModifierCommand | UIKeyModifierShift | UIKeyModifierAlternate | UIKeyModifierControl);
    BOOL cmd = m == UIKeyModifierCommand, cmdShift = m == (UIKeyModifierCommand | UIKeyModifierShift);
    switch ((long)key.keyCode) {
        case UIKeyboardHIDUsageKeyboardS: if (cmd) { [self dm_save]; return YES; } break;
        case UIKeyboardHIDUsageKeyboardW: if (cmd) { [self close]; return YES; } break;
        case UIKeyboardHIDUsageKeyboardM: if (cmd) { [self minimize]; return YES; } break;
        case UIKeyboardHIDUsageKeyboardZ:
            if (cmd && _text.undoManager.canUndo) { [_text.undoManager undo]; return YES; }
            if (cmdShift && _text.undoManager.canRedo) { [_text.undoManager redo]; return YES; }
            return cmd || cmdShift;
        case UIKeyboardHIDUsageKeyboardC: if (cmd) { [_text copy:nil]; return YES; } break;
        case UIKeyboardHIDUsageKeyboardV: if (cmd && _editable) { [_text paste:nil]; return YES; } break;
        case UIKeyboardHIDUsageKeyboardX: if (cmd && _editable) { [_text cut:nil]; return YES; } break;
        case UIKeyboardHIDUsageKeyboardA: if (cmd) { [_text selectAll:nil]; return YES; } break;
        case UIKeyboardHIDUsageKeyboardEscape: if (m == 0 && _text.isFirstResponder) { [_text resignFirstResponder]; return YES; } break;
        default: break;
    }
    return NO;
}
#if DEBUG
- (void)dm_debugType:(NSString *)s { if (!_editable || _gone) return; [_text insertText:s]; }   // (tests: as if typed)
- (NSString *)dm_debugState { return [NSString stringWithFormat:@"title '%@' editable %d edited %d gone %d chars %lu first responder %d", self.title, _editable, _edited, _gone, (unsigned long)_text.text.length, _text.isFirstResponder]; }
#endif
@end
// Opens a text file in its window (the one it has, or a new one). The file is read off the main thread; when it turns out not to be plain text
// this window takes, `otherwise` runs (on the main thread): the caller shows it as before. NO only when the window isn't there (Finder off).
static BOOL DMTextWindowOpen(NSString *path, dispatch_block_t otherwise) {
    if (!gFinderOn || !path.length) return NO;
    NSString *norm = DMFinderNorm(path);
    DMTextWindow *(^existing)(void) = ^DMTextWindow *{ for (DMNativeWindow *w in gNativeWindows) if ([w isKindOfClass:[DMTextWindow class]] && [((DMTextWindow *)w).file isEqualToString:norm]) return (DMTextWindow *)w; return nil; };
    DMTextWindow *had = existing();
    if (had) { [had show]; return YES; }
    dispatch_async(DMTextQueue(), ^{   // (after any save still being written)
        NSStringEncoding enc = NSUTF8StringEncoding; BOOL bom = NO;
        NSString *text = DMTextRead(path, &enc, &bom);
        dispatch_async(dispatch_get_main_queue(), ^{
            if (!text || !gFinderOn) { if (otherwise) otherwise(); return; }
            DMTextWindow *w = existing();   // (opened twice quickly: one window)
            if (w) { [w show]; return; }
            DM_FEATURE_MARK("text-window");
            BOOL editable = DMFinderCanChange(path) && access(path.fileSystemRepresentation, W_OK) == 0;
            w = [[DMTextWindow alloc] initWithFile:norm text:text encoding:enc bom:bom editable:editable];
            [w show];
            DMLog([NSString stringWithFormat:@"[text] opened (%lu characters, %@)", (unsigned long)text.length, editable ? @"editable" : @"read only"]);
        });
    });
    return YES;
}
// The Dock's Downloads stack (dock/Downloads.m) opens text files here too (found with dlsym): `otherwise` when it isn't one.
__attribute__((visibility("default"))) BOOL MSBDOpenTextFileElse(NSString *path, dispatch_block_t otherwise) { return [path isKindOfClass:[NSString class]] && DMTextWindowOpen(path, otherwise); }
