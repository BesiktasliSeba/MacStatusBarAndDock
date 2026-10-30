// test-escrule.c -- Mac test of Esc Ends Typing in Windows' rule (appbridge/EscRule.h, used by AppBridge.x MABEscEndsTypingNow): the 1.3.3 audit
// M-9 cases keep Esc in the session (terminals, virtual machines, remote desktops read the keys themselves), a text input of the app's own that does
// not read the keys ends its typing again (1.7.1 item 10), UIKit's fields and views as before, and every older rule still holds.
#include <stdio.h>
#include "../appbridge/EscRule.h"
static int fails = 0, checks = 0;
static void Expect(const char *what, int got, int want) { checks++; if (got != want) { fails++; printf("FAIL  %s (got %d, want %d)\n", what, got, want); } else printf("PASS  %s\n", what); }
static MSBDEscState Base(void) { MSBDEscState s = {0}; s.typing = 1; s.inWindow = 1; return s; }
int main(void) {
    MSBDEscState s;
    s = Base(); s.uikitText = 1;
    Expect("UIKit's text field in a window (Notes, Messages, Settings' search): Esc ends the typing", MSBDEscEndsTyping(s), 1);
    s = Base(); s.uikitText = 1; s.appReadsKeys = 1;
    Expect("  ... also when the app reads keys elsewhere in the chain (as before 1.7.1: UIKit's own fields always ended it)", MSBDEscEndsTyping(s), 1);
    s = Base(); s.appReadsKeys = 1;
    Expect("M-9: a terminal / virtual machine / remote desktop view of the app's own reading the keys: Esc stays the session's", MSBDEscEndsTyping(s), 0);
    s = Base();
    Expect("item 10: a text input of the app's own that does not read the keys: Esc ends its typing again (1.3.3 to 1.7.0: left alone)", MSBDEscEndsTyping(s), 1);
    s = Base(); s.appEscCommand = 1;
    Expect("  ... unless the app has its own Esc shortcut from it up", MSBDEscEndsTyping(s), 0);
    s = Base(); s.uikitText = 1; s.appEscCommand = 1;
    Expect("the app's own Esc shortcut (cancelling a search): the app's", MSBDEscEndsTyping(s), 0);
    s = Base(); s.uikitText = 1; s.composing = 1;
    Expect("a composition in progress (marked text): the input method's", MSBDEscEndsTyping(s), 0);
    s = Base(); s.webContent = 1;
    Expect("web content: the page's", MSBDEscEndsTyping(s), 0);
    s = Base(); s.uikitText = 1; s.terminalApp = 1;
    Expect("a terminal app: Esc is a key there", MSBDEscEndsTyping(s), 0);
    s = Base(); s.uikitText = 1; s.switchOff = 1;
    Expect("the switch off: nothing", MSBDEscEndsTyping(s), 0);
    s = Base(); s.uikitText = 1; s.inWindow = 0;
    Expect("full screen: the app keeps Esc (the feature is for windows)", MSBDEscEndsTyping(s), 0);
    s = Base(); s.inWindow = 0;
    Expect("full screen, an input of the app's own: the app keeps Esc", MSBDEscEndsTyping(s), 0);
    s = Base(); s.uikitText = 1; s.modifiers = 1;
    Expect("Esc with Cmd, Ctrl or Alt: a shortcut, not ours", MSBDEscEndsTyping(s), 0);
    s = Base(); s.typing = 0;
    Expect("nothing typing: nothing to end", MSBDEscEndsTyping(s), 0);
    printf("%d checks, %d failed\n", checks, fails);
    return fails ? 1 : 0;
}
