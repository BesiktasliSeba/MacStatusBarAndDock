// WindowCardPlan.h -- what the App Switcher's cards of the engines' windows need (statusbar/WindowCards.h), plain Foundation so the Mac test
// (tools/test-wincards.m) runs this very code.
//  - A card is SpringBoard's own app layout in its switcher model. SpringBoard makes one only when its main layout state goes to an app (a
//    full-screen open); an engine's window shows its app outside that state, so the window's app gets a card from SpringBoard's own call for an
//    app scene that is not the layout state (WindowCards.h). Asked once per window, and only while no card of SpringBoard's names the app.
//  - The window in front is the most recent app, as a full-screen app is when it opens: its card goes to the front of the list, unless it is
//    there already, the switcher is up or SpringBoard is in a transition (then it waits for a later tick) -- the switcher's list never changes
//    under a running switcher animation or gesture.
#ifndef MSBD_WINDOW_CARD_PLAN_H
#define MSBD_WINDOW_CARD_PLAN_H
#import <Foundation/Foundation.h>

// The iPadOS versions where SpringBoard's calls behind the cards were read and the cards checked on the engines (WindowCards.h): 15 (M1 15.6.1,
// the switcher view controller's calls), 16 (iPad 2 16.7.7), 17 (17.5.1) and 18 (A12Z 18.5), the coordinator's, per screen. Any other: iPadOS's
// cards as they are.
static inline BOOL MSBDWinCardOSChecked(NSInteger major) { return major >= 15 && major <= 18; }
// cards: the switcher's cards in their order, each card the bundle identifiers of its apps (a Split View card has two).
static inline BOOL MSBDWinCardHasCard(NSString *bundle, NSArray<NSArray<NSString *> *> *cards) {
    if (!bundle.length) return NO;
    for (NSArray<NSString *> *c in cards) if ([c containsObject:bundle]) return YES;
    return NO;
}
// Should SpringBoard be asked for a card for this window now? (one ask per window: asked = this window asked already)
static inline BOOL MSBDWinCardShouldAsk(NSString *bundle, BOOL asked, BOOL closing, BOOL sceneKnown, NSArray<NSArray<NSString *> *> *cards) {
    if (!bundle.length || asked || closing || !sceneKnown) return NO;
    return !MSBDWinCardHasCard(bundle, cards);
}
typedef NS_ENUM(NSInteger, MSBDWinCardFront) {
    MSBDWinCardFrontNothing = 0,   // nothing to do (no window app in front, no card, a card of several apps, or first already)
    MSBDWinCardFrontWait = 1,      // to the front, but not now (the switcher is up, or a transition or gesture runs): asked again later
    MSBDWinCardFrontMove = 2,      // its card to the front of the list now
};
// front: the app whose window is in front (nil: none); cards: as above, in the switcher's order (0 = most recent).
static inline MSBDWinCardFront MSBDWinCardFrontPlan(NSString *front, NSArray<NSArray<NSString *> *> *cards, BOOL switcherUp, BOOL busy) {
    if (!front.length) return MSBDWinCardFrontNothing;
    NSUInteger at = NSNotFound;
    for (NSUInteger i = 0; i < cards.count; i++) if ([cards[i] containsObject:front]) { at = i; break; }
    if (at == NSNotFound || cards[at].count != 1) return MSBDWinCardFrontNothing;   // (no card yet, or a Split View card: left as SpringBoard has it)
    if (at == 0) return MSBDWinCardFrontNothing;
    return switcherUp || busy ? MSBDWinCardFrontWait : MSBDWinCardFrontMove;
}

// ---- the windows' pictures as iPadOS's App Switcher comes (WindowCards.h DMWinCardsSwitcherComing) ----
// A window's card picture is current -- not taken again as the App Switcher comes -- when it was taken since the window was last in front (in
// use: changed), at the screen orientation and window size of now (shape: a turned picture is not found at all, a resized one is of another
// shape), and less than kMSBDWinCardPictureFresh s ago (a window that only shows changes little in that time; one that plays or counts is
// pictured again after it). takenAt 0: never pictured; frontAt 0: never in front.
static const double kMSBDWinCardPictureFresh = 5.0;
static inline BOOL MSBDWinCardPictureCurrent(double takenAt, double frontAt, double now, NSString *shapeThen, NSString *shapeNow) {
    if (takenAt <= 0.0 || now < takenAt || now - takenAt >= kMSBDWinCardPictureFresh) return NO;
    if (frontAt >= takenAt) return NO;
    return shapeThen.length && [shapeThen isEqualToString:shapeNow];
}
// One window as the App Switcher comes: it has its app yet, it shows (not hidden, minimized or on another desktop), its card has a picture of
// ours, that picture is current (above), it is the app in front's.
typedef struct { BOOL hasApp, showing, pictured, current, front; } MSBDWinCardPicWindow;
// The windows to picture, in the order they are taken (one per turn of the main run loop): the window in front first -- the one used last, whose
// card the switcher shows first --, then the others from the front back. w: the windows back to front, as the engines list them; order: room for
// n indexes into w. A window that shows is pictured unless its picture is current; one that does not show keeps its picture, unless it has none;
// one with no app yet is left out. Returns how many.
static inline NSUInteger MSBDWinCardPictureOrder(const MSBDWinCardPicWindow *w, NSUInteger n, NSUInteger *order) {
    NSUInteger k = 0, first = NSNotFound;
    for (NSUInteger i = n; i-- > 0;) if (w[i].front) { first = i; break; }   // (the front app's frontmost window)
    for (int pass = 0; pass < 2; pass++)
        for (NSUInteger i = n; i-- > 0;) {
            if ((pass == 0) != (i == first)) continue;
            if (w[i].hasApp && (w[i].showing ? !w[i].current : !w[i].pictured)) order[k++] = i;
        }
    return k;
}
#endif
