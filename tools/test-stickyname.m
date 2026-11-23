// Mac test of a sticky note's name (1.8.8.2 F37, KT 22 Nov: "with the notes in the top bar we can show the name of that note and give ability to change
// the name"): common/StickyNotes.h's MSBDStickyNameShown (the name its bar shows), MSBDStickyNameClean (a typed name as kept) and
// MSBDStickyTrashFileName (its Move to Trash file). Run by test-stickyname.sh.
#import <Foundation/Foundation.h>
#include "../common/StickyNotes.h"

static int fails = 0, passes = 0;
#define CHECK(cond, ...) do { if (cond) { passes++; printf("PASS  "); } else { fails++; printf("FAIL  "); } printf(__VA_ARGS__); printf("\n"); } while (0)
static BOOL is(NSString *a, NSString *b) { return [a isEqualToString:b]; }

int main(void) { @autoreleasepool {
    // ---- the name shown ----
    CHECK(is(MSBDStickyNameShown(nil, @""), @"Sticky Note") && is(MSBDStickyNameShown(nil, nil), @"Sticky Note") && is(MSBD_NOTE_DEFAULT_NAME, @"Sticky Note"), "no name and no text: \"Sticky Note\"");
    CHECK(is(MSBDStickyNameShown(nil, @"MSB-TEST Shopping\nmilk\neggs"), @"MSB-TEST Shopping"), "no name of its own: its text's first line");
    CHECK(is(MSBDStickyNameShown(nil, @"\n   \n\t MSB-TEST second  \nthird"), @"MSB-TEST second"), "  ... the first line that is not blank, without the spaces at its ends");
    CHECK(is(MSBDStickyNameShown(nil, @" \n\t\n "), @"Sticky Note"), "  ... a text of blank lines only: \"Sticky Note\"");
    CHECK(is(MSBDStickyNameShown(@"MSB-TEST Own", @"MSB-TEST text line"), @"MSB-TEST Own") && is(MSBDStickyNameShown(@"  ", @"MSB-TEST text line"), @"MSB-TEST text line"), "its own name wins; a blank own name is none");
    NSMutableString *lng = [NSMutableString string]; while (lng.length < 300) [lng appendString:@"MSB-TEST "];
    CHECK(MSBDStickyNameShown(nil, lng).length <= MSBD_NOTE_NAME_MAX && MSBDStickyNameShown(nil, lng).length >= MSBD_NOTE_NAME_MAX - 1, "a first line longer than 100 characters: cut to 100 (%lu)", (unsigned long)MSBDStickyNameShown(nil, lng).length);
    NSString *emoji = [[@"" stringByPaddingToLength:MSBD_NOTE_NAME_MAX - 1 withString:@"a" startingAtIndex:0] stringByAppendingString:@"\U0001F469\u200D\U0001F4BB more"];
    CHECK(MSBDStickyNameShown(nil, emoji).length == MSBD_NOTE_NAME_MAX - 1, "  ... never inside a character (an emoji at the cut goes whole)");
    // ---- the Trash file's name ----
    CHECK(is(MSBDStickyTrashFileName(@"MSB-TEST Shopping"), @"MSB-TEST Shopping.txt") && is(MSBDStickyTrashFileName(MSBD_NOTE_DEFAULT_NAME), @"Sticky Note.txt"), "the Trash file is \"<the name shown>.txt\" (\"Sticky Note.txt\" for the default)");
    CHECK(is(MSBDStickyTrashFileName(@"MSB-TEST a/b:c"), @"MSB-TEST a-b-c.txt"), "  ... a \"/\" or \":\" made \"-\" (never a folder, never Finder's separator)");
    CHECK(is(MSBDStickyTrashFileName(@"..MSB-TEST hidden"), @"MSB-TEST hidden.txt") && is(MSBDStickyTrashFileName(@"..."), @"Sticky Note.txt"), "  ... no leading dot (never a hidden file); nothing left: \"Sticky Note.txt\"");
    CHECK(is(MSBDStickyTrashFileName(@"MSB-TEST\x01\x1F\x7F x"), @"MSB-TEST x.txt") && is(MSBDStickyTrashFileName(@3), @"Sticky Note.txt") && is(MSBDStickyTrashFileName(nil), @"Sticky Note.txt"), "  ... no control character; not a string: \"Sticky Note.txt\"");
    NSMutableString *wide = [NSMutableString string]; while (wide.length < 200) [wide appendString:@"\u6F22\u5B57\u00E9\U0001F600"];   // (three, two and four bytes a character)
    NSString *f = MSBDStickyTrashFileName(wide), *base = [f substringToIndex:f.length - 4];
    BOOL whole = YES; for (NSUInteger i = 0; i < base.length; ) { NSRange r = [base rangeOfComposedCharacterSequenceAtIndex:i]; if (NSMaxRange(r) > base.length) whole = NO; i = NSMaxRange(r); }
    CHECK([base lengthOfBytesUsingEncoding:NSUTF8StringEncoding] <= 200 && [f lengthOfBytesUsingEncoding:NSUTF8StringEncoding] <= 204 && whole && [f hasSuffix:@".txt"] && [wide hasPrefix:base],
          "  ... at most 200 bytes before \".txt\" (a file name holds 255, the Trash's numbering fits), never half a character (%lu bytes)", (unsigned long)[base lengthOfBytesUsingEncoding:NSUTF8StringEncoding]);
    // ---- a double tap or click on the bar (1.8.8.2: an idle note's first tap waits for a possible second, its typing after the double tap's time) ----
    NSString *a = @"MSB-TEST-A", *b = @"MSB-TEST-B";
    CHECK(MSBD_NOTE_BAR_TWICE == 0.45, "the double tap time on a note's bar: 0.45 s (the desktop icons')");
    CHECK(MSBDStickyBarTwice(a, a, 0.0) && MSBDStickyBarTwice(a, a, 0.18) && MSBDStickyBarTwice(a, a, 0.449), "a second tap on the same note's bar within 0.45 s (the device's double tap 0.18 s apart): twice, its name edited");
    CHECK(!MSBDStickyBarTwice(a, a, 0.45) && !MSBDStickyBarTwice(a, a, 2.0) && !MSBDStickyBarTwice(a, b, 0.1) && !MSBDStickyBarTwice(nil, a, 0.1) && !MSBDStickyBarTwice(a, nil, 0.1) && !MSBDStickyBarTwice(a, a, -0.1),
          "  ... not at 0.45 s or later, not on another note's bar, not without a first tap, never back in time");
    CHECK(MSBDStickyBarOnceTypes(1, 0, 1, 0), "a single tap on an idle note's bar: its typing begins when the double tap's time is over");
    CHECK(!MSBDStickyBarOnceTypes(0, 0, 1, 0), "  ... not when a second tap came (it renamed) or another bar was tapped since");
    CHECK(!MSBDStickyBarOnceTypes(1, 1, 1, 0), "  ... not when a touch began since (a drag of the note, a tap elsewhere: they decide)");
    CHECK(!MSBDStickyBarOnceTypes(1, 0, 0, 0) && !MSBDStickyBarOnceTypes(1, 0, 1, 1), "  ... not when another app came to the front, nor when a typing began another way");
    printf("test-stickyname: %d passed, %d failed\n", passes, fails);
    return fails ? 1 : 0;
} }
