// test-editmenufollow.m: Mac test (Mac Catalyst) of UIKit's edit menu following what is typed in the desktop's typing window through a turn
// (statusbar/Desktop.h DMDesktopEditMenuFollow, 1.8.8.2). The function is cut out of Desktop.h by test-editmenufollow.sh (CUT_H) and run on views
// that carry edit menu interactions of a class of this test's own (a UIEditMenuInteraction that counts the calls made to it).
#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import <objc/message.h>
#include <ctype.h>
// (iPadOS 15's way, 1.8.8.3: no UIEditMenuInteraction class there -- the harness hides it from the cut code; the turn's times as Desktop.h keeps them)
static BOOL gNoEMI = NO;
static Class TClass(const char *n) { return gNoEMI && !strcmp(n, "UIEditMenuInteraction") ? Nil : objc_getClass(n); }
#define objc_getClass(n) TClass(n)
__attribute__((unused)) static CFTimeInterval gDesktopTurnToldAt = 0, gDesktopEditMenuHidAt = 0, gDesktopEditMenuTurnDone = 0;
#include CUT_H
#undef objc_getClass
// UIMenuController as iPadOS 15 has it, counted: shown or not, hidden, shown from where
static BOOL gMCVisible = NO; static int gMCHid = 0, gMCShown = 0; static CGRect gMCRect;
static BOOL TMCVisible(id self, SEL _cmd) { return gMCVisible; }
static void TMCHide(id self, SEL _cmd) { gMCHid++; gMCVisible = NO; }
static void TMCShow(id self, SEL _cmd, UIView *v, CGRect r) { gMCShown++; gMCRect = r; gMCVisible = YES; }
@interface TRange : UITextRange
@end
@implementation TRange
- (BOOL)isEmpty { return NO; }
- (UITextPosition *)start { return [UITextPosition new]; }
- (UITextPosition *)end { return [UITextPosition new]; }
@end
@interface TField : UITextField
@end
@implementation TField
- (UITextRange *)selectedTextRange { return [TRange new]; }
- (CGRect)firstRectForRange:(UITextRange *)r { return CGRectMake(10, 2, 40, 16); }
- (UIView *)textInputView { return self; }
@end

static int fails = 0, passes = 0;
static void Check(BOOL ok, const char *what, NSString *detail) {
    if (ok) { passes++; printf("PASS  %s\n", what); }
    else { fails++; printf("FAIL  %s%s%s\n", what, detail.length ? ": " : "", detail.length ? detail.UTF8String : ""); }
}
@interface TMenu : UIEditMenuInteraction
@property (nonatomic) int asked, animated;
@end
@implementation TMenu
- (void)updateVisibleMenuPositionAnimated:(BOOL)animated { self.asked++; if (animated) self.animated++; }
@end

int main(int argc, char **argv) {
    @autoreleasepool {
        (void)argc; (void)argv;
        // the typing window's container, a field being typed in with UIKit's text views inside it, a sibling field
        UIView *container = [[UIView alloc] initWithFrame:CGRectMake(0, 0, 1366, 1024)];
        UITextField *field = [[UITextField alloc] initWithFrame:CGRectMake(600, 400, 160, 24)];
        UIView *editor = [[UIView alloc] initWithFrame:field.bounds], *canvas = [[UIView alloc] initWithFrame:field.bounds];
        UITextField *other = [[UITextField alloc] initWithFrame:CGRectMake(100, 100, 160, 24)];
        [container addSubview:field]; [field addSubview:editor]; [editor addSubview:canvas]; [container addSubview:other];
        TMenu *onField = [[TMenu alloc] initWithDelegate:nil], *onCanvas = [[TMenu alloc] initWithDelegate:nil], *onContainer = [[TMenu alloc] initWithDelegate:nil], *onOther = [[TMenu alloc] initWithDelegate:nil];
        [field addInteraction:onField]; [canvas addInteraction:onCanvas]; [container addInteraction:onContainer]; [other addInteraction:onOther];
        int asked = DMDesktopEditMenuFollow(field);
        Check(asked == 3 && onField.asked == 1 && onCanvas.asked == 1 && onContainer.asked == 1, "the edit menu interactions on the field, inside it and around it are asked to place their menu again (the selection's place now)",
              [NSString stringWithFormat:@"asked %d: field %d, canvas %d, container %d", asked, onField.asked, onCanvas.asked, onContainer.asked]);
        Check(onOther.asked == 0, "  ... never another field's (only what is being typed in)", nil);
        Check(onField.animated == 0 && onCanvas.animated == 0 && onContainer.animated == 0, "  ... at once, not animated (the turn's own animation is over or the field is already there)", nil);
        Check(DMDesktopEditMenuFollow(nil) == 0, "nothing typed in: nothing asked", nil);
        UIView *plain = [[UIView alloc] initWithFrame:CGRectMake(0, 0, 10, 10)];
        Check(DMDesktopEditMenuFollow(plain) == 0, "a view with no edit menu around it: nothing asked", nil);
        UIView *deep = field;   // (a deep tree: bounded)
        for (int i = 0; i < 300; i++) { UIView *v = [[UIView alloc] initWithFrame:CGRectZero]; [deep addSubview:v]; deep = v; }
        TMenu *far = [[TMenu alloc] initWithDelegate:nil]; [deep addInteraction:far];
        int before = onField.asked;
        asked = DMDesktopEditMenuFollow(field);
        Check(onField.asked == before + 1 && asked == 3 && far.asked == 0, "  ... a tree 300 views deep: looked at only so far (bounded), the field's own still asked", [NSString stringWithFormat:@"asked %d, the far one %d", asked, far.asked]);
        // ---- iPadOS 15 (UIMenuController; 1.8.8.3): UIKit hides the menu as the screen turns, before the typing window is told of the turn ----
        {
            Class mc = object_getClass([UIMenuController sharedMenuController]);   // (the shared one's own class: Mac Catalyst's may be a subclass)
            class_replaceMethod(mc, @selector(isMenuVisible), (IMP)TMCVisible, method_getTypeEncoding(class_getInstanceMethod(mc, @selector(isMenuVisible))));
            class_replaceMethod(mc, @selector(hideMenu), (IMP)TMCHide, method_getTypeEncoding(class_getInstanceMethod(mc, @selector(hideMenu))));
            class_replaceMethod(mc, @selector(showMenuFromView:rect:), (IMP)TMCShow, method_getTypeEncoding(class_getInstanceMethod(mc, @selector(showMenuFromView:rect:))));
            gNoEMI = YES;
            TField *tf = [[TField alloc] initWithFrame:CGRectMake(600, 400, 160, 24)];
            CFTimeInterval now = CACurrentMediaTime();
            gMCVisible = YES; gMCHid = gMCShown = 0; gDesktopTurnToldAt = 0; gDesktopEditMenuHidAt = 0;
            int a1 = DMDesktopEditMenuFollow(tf);
            Check(a1 == 1 && gMCHid == 1 && gMCShown == 1 && CGRectEqualToRect(gMCRect, CGRectMake(10, 2, 40, 16)), "15: the menu shown at a turn: hidden and shown again at the selection's place now (as 1.8.8.2)", [NSString stringWithFormat:@"asked %d, hid %d, shown %d", a1, gMCHid, gMCShown]);
            gMCVisible = NO; gMCHid = gMCShown = 0; gDesktopTurnToldAt = now - 0.1; gDesktopEditMenuHidAt = now - 0.3;
            int a2 = DMDesktopEditMenuFollow(tf);
            Check(a2 == 1 && gMCHid == 0 && gMCShown == 1 && gDesktopEditMenuHidAt == 0, "15: the menu UIKit hid as the screen turned (0.2 s before the typing window was told of it): shown again at the selection's new place, once (15.6.1: it stayed gone)",
                  [NSString stringWithFormat:@"asked %d, hid %d, shown %d, hid-at %.2f", a2, gMCHid, gMCShown, gDesktopEditMenuHidAt]);
            gMCVisible = NO; gMCShown = 0;
            Check(DMDesktopEditMenuFollow(tf) == 0 && gMCShown == 0, "  ... asked again (the follow 0.4 s on) after it was shown and closed: not again", nil);
            gMCVisible = NO; gMCShown = 0; gDesktopTurnToldAt = now - 0.1; gDesktopEditMenuHidAt = 0;
            gDesktopEditMenuTurnDone = 0;   // (the cases below: a turn the follow has not shown the menu for yet, so each tests its own rule)
            Check(DMDesktopEditMenuFollow(tf) == 0 && gMCShown == 0, "15: no menu before the turn: none shown", nil);
            gDesktopEditMenuHidAt = now - 3.0;
            Check(DMDesktopEditMenuFollow(tf) == 0 && gMCShown == 0, "15: a menu closed 3 s before the turn (by the user): not shown again", nil);
            gDesktopTurnToldAt = now - 2.0; gDesktopEditMenuHidAt = now - 2.1;
            Check(DMDesktopEditMenuFollow(tf) == 0 && gMCShown == 0, "15: asked 2 s after the turn: nothing (a follow of that turn only)", nil);
            gDesktopTurnToldAt = 0; gDesktopEditMenuHidAt = now - 0.1;
            Check(DMDesktopEditMenuFollow(tf) == 0 && gMCShown == 0, "15: a container change with no turn told (a rename's begin): nothing", nil);
            // (review 1.8.8.3: once per turn. The follow runs at the turn and again 0.4 s on; a close by the user between the two -- a tap, a key
            //  typed: UIMenuController's will-hide, noted as any hide while the window types -- is the user's and stays)
            CFTimeInterval t2 = CACurrentMediaTime();
            gMCVisible = NO; gMCHid = gMCShown = 0; gDesktopTurnToldAt = t2 - 0.1; gDesktopEditMenuHidAt = t2 - 0.3;
            int b1 = DMDesktopEditMenuFollow(tf);
            gMCVisible = NO; gDesktopEditMenuHidAt = CACurrentMediaTime();   // (the user closes it: its will-hide)
            int b2 = DMDesktopEditMenuFollow(tf);
            Check(b1 == 1 && b2 == 0 && gMCShown == 1, "15: the menu UIKit hid shown again at the turn, then closed by the user before the follow 0.4 s on: not shown again",
                  [NSString stringWithFormat:@"asked %d then %d, shown %d", b1, b2, gMCShown]);
            CFTimeInterval t3 = CACurrentMediaTime();
            gMCVisible = YES; gMCHid = gMCShown = 0; gDesktopTurnToldAt = t3 - 0.1; gDesktopEditMenuHidAt = 0;
            int c1 = DMDesktopEditMenuFollow(tf);
            gMCVisible = NO; gDesktopEditMenuHidAt = CACurrentMediaTime();
            int c2 = DMDesktopEditMenuFollow(tf);
            Check(c1 == 1 && c2 == 0 && gMCShown == 1 && gMCHid == 1, "15: a menu still shown at the turn moved there, then closed by the user before the follow 0.4 s on: not shown again",
                  [NSString stringWithFormat:@"asked %d then %d, shown %d, hid %d", c1, c2, gMCShown, gMCHid]);
            CFTimeInterval t4 = CACurrentMediaTime() + 0.01;
            gMCVisible = NO; gMCShown = 0; gDesktopTurnToldAt = t4 - 0.05; gDesktopEditMenuHidAt = t4 - 0.2;
            Check(DMDesktopEditMenuFollow(tf) == 1 && gMCShown == 1, "  ... the next turn (another told time) hiding it again: shown again for that turn", nil);
            gDesktopTurnToldAt = 0; gDesktopEditMenuHidAt = 0; gDesktopEditMenuTurnDone = 0;
            gNoEMI = NO;
        }
        printf("test-editmenufollow: %d passed, %d failed\n", passes, fails);
        return fails ? 1 : 0;
    }
}
