// test-editmenufollow.m: Mac test (Mac Catalyst) of UIKit's edit menu following what is typed in the desktop's typing window through a turn
// (statusbar/Desktop.h DMDesktopEditMenuFollow, 1.8.8.2). The function is cut out of Desktop.h by test-editmenufollow.sh (CUT_H) and run on views
// that carry edit menu interactions of a class of this test's own (a UIEditMenuInteraction that counts the calls made to it).
#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import <objc/message.h>
#include <ctype.h>
#include CUT_H

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
        printf("test-editmenufollow: %d passed, %d failed\n", passes, fails);
        return fails ? 1 : 0;
    }
}
