// CauseHide.h -- a crash's cause never carries what the user wrote (1.8.8.1, with Sticky Notes). The words of an uncaught exception can name a view
// and quote it: UIKit's descriptions of a text view, a label or a text field read "text = '...'" (Mac Catalyst run, sticky-notes.md Design v2 1.3),
// and our own death record (CrashCause.h) and Apple's report (exceptionReason.composed_message) keep those words as they are. So wherever a cause
// is kept or shown -- the crash guard's record (CrashBlame.h MSBDBlameCauseText), the crash notice and Report a Problem (CrashExplain.h
// MSBDReportSanitize) -- the quoted text is hidden, and a reason that names a sticky note's code keeps only the exception's name. Another tweak's
// label text is hidden the same way, which is right too. Foundation only (the loader's helper, Settings, SpringBoard); Mac tests:
// tools/test-crashblame.sh, tools/test-crashexplain.sh.
#pragma once
#import <Foundation/Foundation.h>

static inline NSString *MSBDCauseHideText(NSString *cause) {
    if (![cause isKindOfClass:[NSString class]] || !cause.length) return cause;
    // (the notes' classes, their category's methods, their C functions and rules: statusbar/DesktopNotes.h, common/StickyNotes.h. The category's
    //  methods are named with the desktop's class, "-[DMDesktop dm_noteTick]": a dm_note... of another class is not the notes' -- Activity Monitor's
    //  -dm_noteText, whose crash would have read "in sticky notes")
    BOOL note = NO;
    for (NSString *n in @[@"DMNoteView", @"DMNoteTextView", @"DMNoteEditor", @"DMNotesState", @"DMDesktop dm_note", @"DMDesktop(Notes)", @"DMSticky", @"MSBDSticky"]) if ([cause rangeOfString:n].location != NSNotFound) note = YES;
    if (note) {
        NSRange colon = [cause rangeOfString:@":"];
        NSString *name = colon.location != NSNotFound ? [cause substringToIndex:colon.location] : @"";
        // (an exception's name is one word of letters and digits -- NSInvalidArgumentException, CALayerInvalidGeometry -- and never a note's)
        if (!name.length || [name rangeOfCharacterFromSet:[[NSCharacterSet alphanumericCharacterSet] invertedSet]].location != NSNotFound || [name containsString:@"Note"]) name = @"";
        return name.length ? [name stringByAppendingString:@": in sticky notes (details hidden)"] : @"in sticky notes (details hidden)";
    }
    NSRange t = [cause rangeOfString:@"text = '"];
    if (t.location != NSNotFound) return [[cause substringToIndex:t.location] stringByAppendingString:@"text hidden"];
    return cause;
}
