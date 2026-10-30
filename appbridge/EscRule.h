// EscRule.h -- whether Esc ends the typing in a windowed app (appbridge/AppBridge.x MABEscEndsTypingNow), plain C so the Mac test
// (tools/test-escrule.c) runs this very rule.
//  - Esc Ends Typing in Windows (on unless switched off): Esc while typing in a windowed app puts the typing away, like clicking the desktop on a Mac.
//  - Esc stays the app's own when the app uses it: its own Esc shortcut from the text input up (cancelling a search, closing a sheet), an input
//    method's composition (marked text), web content (pages use Esc themselves), a terminal app (Esc is a key there), and an app that reads the
//    keys itself at the text input or above it -- its own -pressesBegan:withEvent: (terminals, virtual machines, remote desktops: Esc belongs to
//    the session; ending the typing there kept vi in insert mode and took the keyboard out of the session, 1.3.3 audit M-9).
//  - 1.3.3's fix for M-9 left Esc to every text input that is not UIKit's own text field or text view, whether or not the app reads the keys;
//    1.7.1 (item 10, KT: "bring that back") keeps only the cause: a text input of the app's own ends its typing again unless the app reads the keys
//    itself. UIKit's text fields and views (and their subclasses) end it as before, whatever the app's key handling.
//  - Only in a window (the feature's own scope since 27 Sep: full screen keeps Esc for the app), and Esc alone (with Cmd, Ctrl or Alt it is a
//    shortcut).
#ifndef MSBD_ESC_RULE_H
#define MSBD_ESC_RULE_H

typedef struct {
    int switchOff;       // Esc Ends Typing in Windows switched off
    int terminalApp;     // one of the terminal apps
    int typing;          // a text input is first responder
    int composing;       // marked text: an input method's composition
    int webContent;      // web content
    int uikitText;       // UIKit's own text field or text view, or a subclass
    int appReadsKeys;    // the app's own -pressesBegan:withEvent: at the text input or above it
    int appEscCommand;   // the app's own Esc shortcut from the text input up
    int inWindow;        // the app's scene is smaller than the screen
    int modifiers;       // Cmd, Ctrl or Alt held
} MSBDEscState;

static inline int MSBDEscEndsTyping(MSBDEscState s) {
    if (s.switchOff || s.terminalApp || !s.typing || s.composing || s.webContent || s.modifiers) return 0;
    if (!s.uikitText && s.appReadsKeys) return 0;   // (M-9's cause: the app reads the keys itself -- Esc is the session's)
    if (s.appEscCommand) return 0;
    return s.inWindow ? 1 : 0;
}

#endif
