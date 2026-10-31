// SMResizeAnchor.h -- a window resized by a corner or side keeps its opposite corner where it is, as with our other engines and on a Mac (1.7.0,
// the Stage Manager engine). Included by StatusBar.x after SMResizeEdges.h; installed by the engine's start-up self-check (optional: a class, method,
// instance variable or signature not as expected = Apple's way, the engine runs). The geometry: SMResizeAnchorMath.h (Mac-tested).
//   iPadOS 16 (read on the iPad 2, 16.7.7, 29 Oct): every step of a live resize is -[SBItemResizeGestureSwitcherModifier
//   _responseForGestureUpdateAtGestureEnd:]. With _resizeAnchor 0 -- every window but one within 22 pt of the stage area's side with others on the
//   stage, set as the gesture begins -- it mirrors the finger about the window's centre as the drag began: the proposed width and height are twice the
//   finger's distance from that centre, and the window's centre for any size (a block of the step's flags: the drawn frame, the scene's centre) stays
//   there, so both sides move. Its held-side arithmetic (anchor 1 / 2: the width the finger to the area's side, the centre that side plus half the
//   size; a height whose mirrored side passes the area's: held there) is used only at the stage area's sides. 17.5.1 holds the window's own opposite
//   sides instead (its anchors measured from the window's frame, the height from its far side).
//   Our engine on 16: for that one call, Apple's held-side arithmetic with the window's own frame as the area (the anchor from 17's table, the area
//   for resizing the frame, the frame's centre half a window past its far side where the height is dragged: SMResizeAnchorMath.h) -- Stage Manager
//   still works out every size, its grid and its rubber band, and the app gets those. The scene's centre for a size is the opposite corner kept also
//   when the step's scene-ready answer (-handleSceneReadyEvent:) sends the size again with the drawn frame's centre (the drawn frame is the rubber-
//   banded size: past the smallest size the scene would have moved by half the difference). And the dragged side keeps its distance from where the
//   finger touched down (16's step puts it at the finger itself: it jumped onto the finger at the first step), as 17 and Aerial keep it: the step
//   reads the finger plus that grab offset (SMResizeAnchorMath.h MSBDResizeGrabOffset). Everything is put back after the call.
//   iPadOS 17 (17.5.1) holds the opposite sides itself (a lone window in its default position excepted -- our engine's windows never are: they go
//   out as placed by the user, SMEngineAPI.h DMSMAttrPlacedByUser; a fresh lone window was held at its corner, 29 Oct). But each step puts the
//   dragged side at the finger plus an edge adjustment measured where the gesture began, after the pan's start distance: the side stays behind the
//   finger by that travel (a corner dragged in past the smallest size and back out ended ~20 pt ahead of it); our catch-up adds the travel, as for
//   Aerial's handle (-resizeCatchUp:), so the side keeps the distance it had where the finger touched down.
//   Debug /tmp/msb-sm-applecorner: Apple's way. /tmp/msb-resizetrace: every step's values in the log.
#pragma once
#include "SMResizeAnchorMath.h"

static Ivar gSMRAEdgeIv, gSMRAAnchorIv, gSMRAStartIv, gSMRALayoutIv, gSMRALocIv, gSMRAAdjIv, gSMRADrawIv, gSMRASceneIv;
static BOOL gSMRAOn16, gSMRAOn17, gSMRAOff;   // (installed for 16 / 17; switched off after a step that did not ask for the area as read)
// (16, during one step for one of our windows: the area Apple's step asks for, once, from the model it asks -- and what the step was given)
static struct { BOOL armed, used; __unsafe_unretained id model; MSBDResizeFake16 fake; } gSMRAArea;
static struct { BOOL in; __unsafe_unretained id mod; unsigned long long edge; CGRect start; BOOL vertical; } gSMRAStep;
static struct { __unsafe_unretained id mod; CGPoint down; } gSMRADown;   // (16: where the finger touched down for this modifier's gesture -- its grab offset)

static BOOL DMSMRARead(id o, Ivar iv, void *out, size_t n) {
    if (!o || !iv) return NO;
    memcpy(out, (const char *)(__bridge const void *)o + ivar_getOffset(iv), n);
    return YES;
}
static void DMSMRAWrite(id o, Ivar iv, const void *v, size_t n) {
    if (o && iv) memcpy((char *)(__bridge void *)o + ivar_getOffset(iv), v, n);
}
static BOOL DMSMRAOurs(void) { return DMSMFree() && !gSMRAOff && !DMTestFlag("/tmp/msb-sm-applecorner"); }
#if DEBUG
static void DMSMRATrace(id mod, NSString *what) {
    if (!DMTestFlag("/tmp/msb-resizetrace")) return;
    unsigned long long edge = 0, anchor = 0; CGPoint loc = CGPointZero, adj = CGPointZero; CGRect start = CGRectNull, draw = CGRectNull; CGSize scene = CGSizeZero;
    DMSMRARead(mod, gSMRAEdgeIv, &edge, sizeof edge); DMSMRARead(mod, gSMRAAnchorIv, &anchor, sizeof anchor); DMSMRARead(mod, gSMRALocIv, &loc, sizeof loc);
    BOOL hasAdj = DMSMRARead(mod, gSMRAAdjIv, &adj, sizeof adj);
    DMSMRARead(mod, gSMRAStartIv, &start, sizeof start); DMSMRARead(mod, gSMRADrawIv, &draw, sizeof draw); DMSMRARead(mod, gSMRASceneIv, &scene, sizeof scene);
    DMLog([NSString stringWithFormat:@"[smresize] %@: edge %llu anchor %llu location %@%@ start %@ drawn %@ scene %@", what, edge, anchor,
        NSStringFromCGPoint(loc), hasAdj ? [NSString stringWithFormat:@" (edge adjustment %@)", NSStringFromCGPoint(adj)] : @"", NSStringFromCGRect(start), NSStringFromCGRect(draw), NSStringFromCGSize(scene)]);
}
#endif
// ---- iPadOS 16 ----
static CGRect (*o_SMRAArea)(id, SEL);
static CGRect DMSMRAArea(id self, SEL _cmd) {   // -[SBChamoisOverlappingModel stageAreaForResizing]
    CGRect r = o_SMRAArea(self, _cmd);
    if (!gSMRAArea.armed || self != gSMRAArea.model) return r;
    gSMRAArea.armed = NO; gSMRAArea.used = YES;   // (once: the step asks right after it read the window's frame)
    r.origin.x = gSMRAArea.fake.areaX; r.size.width = gSMRAArea.fake.areaW;
    if (gSMRAArea.fake.vertical) { r.origin.y = gSMRAArea.fake.areaY; r.size.height = gSMRAArea.fake.areaH; }
    return r;
}
// 16's last step (the finger lifted): where the dragged sides end, snapped as on every engine (1.7.3 item 3, WindowSnap.h: within 10 pt of the
// desktop's edges or the stage's other windows' sides; 17 and 18 snap a resized side themselves and are left as Apple has them). at: the location
// the step reads, which is where it puts the dragged sides; start: the card as the drag began (the switcher's points: the screen's); the window as
// drawn is the card with our title bar above it. The window being resized is the one whose held sides are start's (WindowSnap.h
// MSBDSnapHeldSidesMatch). Only a window of the iPad's own screen found that way among the working stage's windows is snapped: this step runs for a
// TV's window too (16 with an extended display), and the working stage can be the TV's -- the area here is the iPad's desktop and the neighbours
// another screen's points, so a TV's side was pulled up to 10 pt onto a line of the iPad's (its Dock line, its right edge) and never onto the TV's
// own. A TV's window is left as Apple's step has it, as a move leaves it (DMSMSnapMoveTarget); so is one that is not found (1.7.3 review).
static CGPoint DMSMRASnapEnd(unsigned long long edge, CGRect start, CGPoint at) {
    MSBDResizeSides sd = MSBDResizeSidesOf(edge);
    if (DMSnapOff() || !(sd.left || sd.right || sd.top || sd.bottom)) return at;
    CGRect card = start;
    if (sd.left) { card.origin.x = at.x; card.size.width = CGRectGetMaxX(start) - at.x; }
    if (sd.right) card.size.width = at.x - start.origin.x;
    if (sd.top) { card.origin.y = at.y; card.size.height = CGRectGetMaxY(start) - at.y; }
    if (sd.bottom) card.size.height = at.y - start.origin.y;
    if (!(card.size.width > 0) || !(card.size.height > 0)) return at;
    CGRect window = CGRectMake(card.origin.x, card.origin.y - kSMBarH, card.size.width, card.size.height + kSMBarH);
    unsigned how = (sd.left ? MSBDSnapLeft : 0) | (sd.right ? MSBDSnapRight : 0) | (sd.top ? MSBDSnapTop : 0) | (sd.bottom ? MSBDSnapBottom : 0);
    CGRect others[32]; int n = 0, mine = 0; BOOL offIPad = NO;
    NSDictionary<NSString *, NSValue *> *frames = DMSMOpenWindowFrames();
    for (NSString *k in frames) {
        CGRect f = frames[k].CGRectValue, c = CGRectMake(f.origin.x, f.origin.y + kSMBarH, f.size.width, f.size.height - kSMBarH);
        if (MSBDSnapHeldSidesMatch(c, start, how)) {   // (the window being resized: not a neighbour of its own)
            mine++;
            UIView *own = DMSMCardFor(k);
            if ((own.window.screen ?: [UIScreen mainScreen]) != [UIScreen mainScreen]) offIPad = YES;
            continue;
        }
        if (n < 32) others[n++] = f;
    }
    if (!mine || offIPad) {   // (a TV's window, or one not found on the working stage: left as Apple's step has it)
        static int told = 0;
        if (told < 4) { told++; DMLog([NSString stringWithFormat:@"[snap] a Stage Manager window's resize ended %@: not snapped (the iPad's own windows only)", offIPad ? @"on another screen" : @"where none of the working stage's windows is"]); }
        return at;
    }
    CGRect s = DMSnapFrameFor(@"a Stage Manager window", window, how, others, n, DMSMUsableAreaForIdentity(nil, NULL));
    if (CGRectEqualToRect(s, window)) return at;
    if (sd.left) at.x = CGRectGetMinX(s);
    if (sd.right) at.x = CGRectGetMaxX(s);
    if (sd.top) at.y = CGRectGetMinY(s) + kSMBarH;
    if (sd.bottom) at.y = CGRectGetMaxY(s);
    return at;
}
static id (*o_SMRAStep16)(id, SEL, BOOL);
static id DMSMRAStep16(id self, SEL _cmd, BOOL end) {   // -[SBItemResizeGestureSwitcherModifier _responseForGestureUpdateAtGestureEnd:]
    unsigned long long edge = 0, anchor = 0; CGRect start = CGRectNull; id layout = nil;
    if (!DMSMRAOurs() || gSMRAStep.in || !DMSMRARead(self, gSMRAEdgeIv, &edge, sizeof edge) || edge < 1 || edge > 8
        || !DMSMRARead(self, gSMRAStartIv, &start, sizeof start) || !DMSMRectSane(start) || !DMSMRARead(self, gSMRAAnchorIv, &anchor, sizeof anchor))
        return o_SMRAStep16(self, _cmd, end);
    // (the model the step asks for the area -- the calculator's cached last model, so the same object here and there -- and the two lengths the step
    //  tells a full-height window by: the container's height and the screen-edge padding)
    layout = object_getIvar(self, gSMRALayoutIv);
    static SEL modelS, boundsS, attrsS, padS;
    static NSString *modelSig;
    if (!modelS) { modelS = NSSelectorFromString(@"overlappingModelForAppLayout:"); boundsS = NSSelectorFromString(@"containerViewBounds");
                   attrsS = NSSelectorFromString(@"chamoisLayoutAttributes"); padS = NSSelectorFromString(@"screenEdgePadding"); modelSig = DMSMExpect(@encode(id), @encode(id), NULL); }
    id model = layout && DMSMSigOK(self, modelS, modelSig, "resize step's overlapping model") ? ((id (*)(id, SEL, id))objc_msgSend)(self, modelS, layout) : nil;
    id attrs = DMSMSigOK(self, attrsS, DMSMSigObj(), "resize step's layout attributes") ? ((id (*)(id, SEL))objc_msgSend)(self, attrsS) : nil;
    if (!DMSMIsKind(model, "SBChamoisOverlappingModel") || !attrs || !DMSMSigOK(self, boundsS, DMSMSigRect(), "resize step's container")
        || !DMSMSigOK(attrs, padS, DMSMSigDouble(), "screenEdgePadding")) return o_SMRAStep16(self, _cmd, end);
    CGRect container = ((CGRect (*)(id, SEL))objc_msgSend)(self, boundsS);
    double pad = ((double (*)(id, SEL))objc_msgSend)(attrs, padS);
    MSBDResizeFake16 f = MSBDResizeFake16For(edge, start, container.size.height, pad);
    CGPoint loc = CGPointZero, grab = gSMRADown.mod == self ? MSBDResizeGrabOffset(edge, start, gSMRADown.down) : CGPointZero;
    BOOL moveLoc = (grab.x != 0 || grab.y != 0) && DMSMRARead(self, gSMRALocIv, &loc, sizeof loc);
    gSMRAArea.armed = YES; gSMRAArea.used = NO; gSMRAArea.model = model; gSMRAArea.fake = f;
    gSMRAStep.in = YES; gSMRAStep.mod = self; gSMRAStep.edge = edge; gSMRAStep.start = start; gSMRAStep.vertical = f.vertical;
    DMSMRAWrite(self, gSMRAAnchorIv, &f.anchor, sizeof f.anchor);
    DMSMRAWrite(self, gSMRAStartIv, &f.frame, sizeof f.frame);
    if (moveLoc) { CGPoint at = CGPointMake(loc.x + grab.x, loc.y + grab.y); DMSMRAWrite(self, gSMRALocIv, &at, sizeof at); }
    if (end) {   // (1.7.3 item 3: the finger lifted -- the dragged sides where they snap; the location put back after the step, as the grab's)
        CGPoint cur = CGPointZero;
        if (DMSMRARead(self, gSMRALocIv, &cur, sizeof cur)) {
            CGPoint snapped = DMSMRASnapEnd(edge, start, cur);
            if (!CGPointEqualToPoint(snapped, cur)) {
                if (!moveLoc) { loc = cur; moveLoc = YES; }
                DMSMRAWrite(self, gSMRALocIv, &snapped, sizeof snapped);
            }
        }
    }
    id r = nil;
    @try { r = o_SMRAStep16(self, _cmd, end); }
    @finally {
        DMSMRAWrite(self, gSMRAAnchorIv, &anchor, sizeof anchor);
        DMSMRAWrite(self, gSMRAStartIv, &start, sizeof start);
        if (moveLoc) DMSMRAWrite(self, gSMRALocIv, &loc, sizeof loc);
        gSMRAArea.armed = NO; gSMRAArea.model = nil; gSMRAStep.in = NO; gSMRAStep.mod = nil;
    }
    if (!gSMRAArea.used) {   // (the step did not ask that model for the area: its frame and side were Apple's for nothing -- Apple's way from now on)
        gSMRAOff = YES;
        DMLog(@"[smresize] iPadOS 16's resize step did not ask for its area as read on 16.7.7: corner drags are Apple's (around the window's centre) from now on");
        return r;
    }
    DM_FEATURE_MARK("sm-resize-keeps-corner");
#if DEBUG
    DMSMRATrace(self, end ? @"16 step (end)" : @"16 step");
#endif
    return r;
}
// The scene's size and centre for a step: the centre is the opposite corner kept (the step's own centre for its size is that already; the scene-ready
// answer's is the drawn frame's, the rubber-banded size's).
static id (*o_SMRASceneSize)(id, SEL, CGSize, CGPoint, BOOL);
static id DMSMRASceneSize(id self, SEL _cmd, CGSize size, CGPoint c, BOOL only) {
    CGPoint was = c;
    if (gSMRAOn16 && DMSMRAOurs() && isfinite(size.width) && isfinite(size.height) && size.width > 0 && size.height > 0) {
        unsigned long long edge = 0; CGRect start = CGRectNull; BOOL vertical = NO, known = NO;
        if (gSMRAStep.in && gSMRAStep.mod == self) { edge = gSMRAStep.edge; start = gSMRAStep.start; vertical = gSMRAStep.vertical; known = YES; }
        else if (DMSMRARead(self, gSMRAEdgeIv, &edge, sizeof edge) && DMSMRARead(self, gSMRAStartIv, &start, sizeof start) && DMSMRectSane(start)) {
            static SEL boundsS, attrsS, padS;
            if (!boundsS) { boundsS = NSSelectorFromString(@"containerViewBounds"); attrsS = NSSelectorFromString(@"chamoisLayoutAttributes"); padS = NSSelectorFromString(@"screenEdgePadding"); }
            id attrs = DMSMSigOK(self, attrsS, DMSMSigObj(), "resize step's layout attributes") ? ((id (*)(id, SEL))objc_msgSend)(self, attrsS) : nil;
            if (attrs && DMSMSigOK(self, boundsS, DMSMSigRect(), "resize step's container") && DMSMSigOK(attrs, padS, DMSMSigDouble(), "screenEdgePadding")) {
                CGRect container = ((CGRect (*)(id, SEL))objc_msgSend)(self, boundsS);
                vertical = MSBDResizeFake16For(edge, start, container.size.height, ((double (*)(id, SEL))objc_msgSend)(attrs, padS)).vertical;
                known = YES;
            }
        }
        if (known && edge >= 1 && edge <= 8) c = MSBDResizeCenterKeeping(edge, start, size, c, vertical);
    }
#if DEBUG
    if (DMTestFlag("/tmp/msb-resizetrace")) DMLog([NSString stringWithFormat:@"[smresize] scene %@ at %@%@%@", NSStringFromCGSize(size), NSStringFromCGPoint(c),
        CGPointEqualToPoint(c, was) ? @"" : [NSString stringWithFormat:@" (Apple's %@)", NSStringFromCGPoint(was)], only ? @", scene only" : @""]);
#endif
    return o_SMRASceneSize(self, _cmd, size, c, only);
}
// ---- iPadOS 17 (and the debug trace on both) ----
// The event's phase (1: the gesture began), its translation from where the finger touched down and the finger, by signature; NO when unreadable.
static BOOL DMSMRAEventRead(id event, unsigned long long *phase, CGPoint *translation, CGPoint *location) {
    static SEL phaseS, transS, locS;
    static NSString *phaseSig, *pointSig;
    if (!phaseS) { phaseS = NSSelectorFromString(@"phase"); transS = NSSelectorFromString(@"translationInContainerView"); locS = NSSelectorFromString(@"locationInContainerView");
                   phaseSig = DMSMExpect(@encode(unsigned long long), NULL); pointSig = DMSMExpect(@encode(CGPoint), NULL); }
    if (!DMSMSigOK(event, phaseS, phaseSig, "resize event's phase") || !DMSMSigOK(event, transS, pointSig, "resize event's translation")
        || !DMSMSigOK(event, locS, pointSig, "resize event's location")) return NO;
    *phase = ((unsigned long long (*)(id, SEL))objc_msgSend)(event, phaseS);
    *translation = ((CGPoint (*)(id, SEL))objc_msgSend)(event, transS);
    *location = ((CGPoint (*)(id, SEL))objc_msgSend)(event, locS);
    return isfinite(translation->x) && isfinite(translation->y) && isfinite(location->x) && isfinite(location->y);
}
// 16: where the finger touched down, in the switcher's points. 16.7.7's event starts its translation where the gesture began (it read {0, -0.5} at
// the begin of a drag that had gone 13 pt), so the touch-down comes from the recogniser behind the event (its touch history provider,
// SBFluidSwitcherPanGestureRecognizer): its _initialTouchLocation, in its own view (the system gesture window's: the screen's portrait points --
// {77, 501} for a touch at {501, 691} in landscape), in the screen's coordinate space, which the switcher's points are (read: {501, 691}). Only a
// touch-down near the finger as the gesture began (60 pt).
static BOOL DMSMRATouchDown16(id event, CGPoint began, CGPoint *down) {
    Ivar hp = class_getInstanceVariable(object_getClass(event), "_touchHistoryProvider");
    const char *ht = hp ? ivar_getTypeEncoding(hp) : NULL;
    id prov = ht && ht[0] == '@' ? object_getIvar(event, hp) : nil;
    if (![prov isKindOfClass:[UIGestureRecognizer class]]) return NO;
    Ivar it = class_getInstanceVariable(object_getClass(prov), "_initialTouchLocation");
    const char *tt = it ? ivar_getTypeEncoding(it) : NULL;
    UIView *from = ((UIGestureRecognizer *)prov).view;
    UIScreen *screen = from.window.screen;
    if (!tt || ![DMSMNormEncoding(tt) isEqualToString:DMSMNormEncoding(@encode(CGPoint))] || !screen) return NO;
    CGPoint first; memcpy(&first, (const char *)(__bridge const void *)prov + ivar_getOffset(it), sizeof first);
    CGPoint p = [from convertPoint:first toCoordinateSpace:screen.coordinateSpace];
    if (!isfinite(p.x) || !isfinite(p.y) || hypot(p.x - began.x, p.y - began.y) > 60.0) return NO;
    *down = p;
    return YES;
}
static id (*o_SMRAGesture)(id, SEL, id);
static id DMSMRAGesture(id self, SEL _cmd, id event) {   // -[SBItemResizeGestureSwitcherModifier handleGestureEvent:]
    unsigned long long edge = 0, phase = 0; CGPoint t = CGPointZero, at = CGPointZero, adj = CGPointZero;
    BOOL read = DMSMRAEventRead(event, &phase, &t, &at);
    // (16: where the finger touched down, before the gesture's first step; unknown: no grab offset, the side at the finger as Apple has it)
    if (gSMRAOn16 && read && phase == 1) { CGPoint d = CGPointZero; gSMRADown.mod = DMSMRATouchDown16(event, at, &d) ? self : nil; gSMRADown.down = d; }
#if DEBUG
    if (gSMRAOn16 && read && phase == 1 && DMTestFlag("/tmp/msb-resizetrace"))
        DMLog([NSString stringWithFormat:@"[smresize] began: finger %@, translation %@, touched down %@", NSStringFromCGPoint(at), NSStringFromCGPoint(t), gSMRADown.mod == self ? NSStringFromCGPoint(gSMRADown.down) : @"unknown"]);
#endif
    id r = o_SMRAGesture(self, _cmd, event);
    // (17.5.1 measures the edge adjustment -- each step's side = the finger plus it -- as the side minus the finger where the gesture BEGAN, once the
    //  pan had gone its start distance: the side then keeps that much more distance from the finger for the whole drag than it had where the finger
    //  touched down (17.5: {17, 21} for a corner grabbed 6 pt in; a late start {60, 83}), behind the finger in the drag's first direction -- in past
    //  the smallest size and back out, ~20 pt ahead of it. As our Aerial catch-up (-resizeCatchUp:): the adjustment plus the pan's travel before it
    //  began (the event's translation then, from the touch-down), so the side keeps the distance it had from where the finger touched; from the next
    //  step on. Only for a touch-down near the side (the result within 60 pt), each axis the edge drags)
    if (gSMRAOn17 && DMSMRAOurs() && read && phase == 1 && DMSMRARead(self, gSMRAEdgeIv, &edge, sizeof edge) && edge >= 1 && edge <= 8
        && DMSMRARead(self, gSMRAAdjIv, &adj, sizeof adj)) {
        MSBDResizeSides s = MSBDResizeSidesOf(edge);
        CGPoint was = adj;
        if ((s.left || s.right) && fabs(adj.x + t.x) <= 60.0) adj.x += t.x;
        if ((s.top || s.bottom) && fabs(adj.y + t.y) <= 60.0) adj.y += t.y;
        if (!CGPointEqualToPoint(adj, was)) {
            DMSMRAWrite(self, gSMRAAdjIv, &adj, sizeof adj);
            DM_FEATURE_MARK("sm-resize-catch-up");
#if DEBUG
            if (DMTestFlag("/tmp/msb-resizetrace")) DMLog([NSString stringWithFormat:@"[smresize] began %@ from the touch-down: edge adjustment %@ -> %@", NSStringFromCGPoint(t), NSStringFromCGPoint(was), NSStringFromCGPoint(adj)]);
#endif
        }
    }
#if DEBUG
    if (DMTestFlag("/tmp/msb-resizetrace") && read) DMSMRATrace(self, [NSString stringWithFormat:@"event phase %llu translation %@ finger %@%@", phase, NSStringFromCGPoint(t), NSStringFromCGPoint(at),
        gSMRADown.mod == self ? [NSString stringWithFormat:@" (touched down %@)", NSStringFromCGPoint(gSMRADown.down)] : @""]);
#endif
    return r;
}
static void DMSMResizeAnchorInstall(int gen) {   // (optional: once, from the start-up self-check; gen = the layout engine's table, 16 or 17)
    static BOOL done = NO;
    if (done) return;
    done = YES;
    Class c = objc_getClass("SBItemResizeGestureSwitcherModifier"), model = objc_getClass("SBChamoisOverlappingModel");
    // (each instance variable by name, of the type read and written here -- its encoding's shape: 16.7.7 names the struct fields, {CGRect="origin"...})
    Ivar (^iv)(const char *, const char *) = ^Ivar(const char *name, const char *type) {
        Ivar v = c ? class_getInstanceVariable(c, name) : NULL;
        const char *t = v ? ivar_getTypeEncoding(v) : NULL;
        return t && [DMSMNormEncoding(t) isEqualToString:DMSMNormEncoding(type)] ? v : NULL;
    };
    gSMRAEdgeIv = iv("_selectedEdge", @encode(unsigned long long)); gSMRAAnchorIv = iv("_resizeAnchor", @encode(unsigned long long));
    gSMRAStartIv = iv("_initialFrameInScreenCoordinates", @encode(CGRect));
    gSMRALocIv = iv("_location", @encode(CGPoint)); gSMRADrawIv = iv("_currentFrameForDrawingInScreenCoordinates", @encode(CGRect));
    gSMRASceneIv = iv("_currentSceneSize", @encode(CGSize));
    Ivar layoutIv = c ? class_getInstanceVariable(c, "_currentAppLayout") : NULL;
    gSMRALayoutIv = layoutIv && ivar_getTypeEncoding(layoutIv) && ivar_getTypeEncoding(layoutIv)[0] == '@' ? layoutIv : NULL;
    gSMRAAdjIv = iv("_locationEdgeAdjustment", @encode(CGPoint));
    BOOL has17 = class_getInstanceVariable(c, "_selectedItemWasInitiallyInDefaultPosition") != NULL;   // (17's other new one: tells the two steps apart)
    SEL stepS = sel_registerName("_responseForGestureUpdateAtGestureEnd:"), sceneS = sel_registerName("_responseForSceneSizeUpdateToSize:center:sceneUpdatesOnly:");
    SEL gestureS = sel_registerName("handleGestureEvent:"), areaS = sel_registerName("stageAreaForResizing");
    Method mStep = c ? class_getInstanceMethod(c, stepS) : NULL, mScene = c ? class_getInstanceMethod(c, sceneS) : NULL, mGesture = c ? class_getInstanceMethod(c, gestureS) : NULL;
    Method mArea = model ? class_getInstanceMethod(model, areaS) : NULL;
    BOOL gestureOK = mGesture && [DMSMSigOfMethod(mGesture) isEqualToString:DMSMExpect(@encode(id), @encode(id), NULL)];
    BOOL sceneOK = mScene && [DMSMSigOfMethod(mScene) isEqualToString:DMSMExpect(@encode(id), @encode(CGSize), @encode(CGPoint), @encode(BOOL), NULL)];
    if (gen == 16) {
        // (16's step as read on 16.7.7: its instance variables -- none of 17's edge adjustment or default position --, the step, the scene's answer,
        //  the model's area for resizing)
        BOOL ok = gSMRAEdgeIv && gSMRAAnchorIv && gSMRAStartIv && gSMRALayoutIv && gSMRALocIv && !gSMRAAdjIv && !has17 && sceneOK && mArea
               && mStep && [DMSMSigOfMethod(mStep) isEqualToString:DMSMExpect(@encode(id), @encode(BOOL), NULL)]
               && [DMSMSigOfMethod(mArea) isEqualToString:DMSMSigRect()];
        if (!ok) {
            DMLog([NSString stringWithFormat:@"[smresize] iPadOS 16's resize step is not as read on 16.7.7 here (ivars %d%d%d%d, no 17 ones %d%d, step %s, scene %d, area %s): a corner drag resizes around the window's centre, as Apple has it",
                gSMRAEdgeIv != NULL, gSMRAAnchorIv != NULL, gSMRAStartIv != NULL, gSMRALayoutIv != NULL, !gSMRAAdjIv, !has17, mStep ? method_getTypeEncoding(mStep) : "-", sceneOK, mArea ? method_getTypeEncoding(mArea) : "-"]);
            return;
        }
        MSHookMessageEx(model, areaS, (IMP)DMSMRAArea, (IMP *)&o_SMRAArea);
        MSHookMessageEx(c, stepS, (IMP)DMSMRAStep16, (IMP *)&o_SMRAStep16);
        MSHookMessageEx(c, sceneS, (IMP)DMSMRASceneSize, (IMP *)&o_SMRASceneSize);
        gSMRAOn16 = o_SMRAArea && o_SMRAStep16 && o_SMRASceneSize;
        if (gSMRAOn16 && gestureOK) MSHookMessageEx(c, gestureS, (IMP)DMSMRAGesture, (IMP *)&o_SMRAGesture);   // (16: the touch-down, for the grab offset)
        DMLog(gSMRAOn16 ? [NSString stringWithFormat:@"[smresize] a corner or side drag keeps the window's opposite corner (iPadOS 16's resize step held at the window's own frame)%@",
                           o_SMRAGesture ? @", the side its distance from where the finger touched" : @" -- the side at the finger (the gesture event is not as read)"]
                        : @"[smresize] the resize hooks did not all go in");
        return;
    }
    BOOL ok = gSMRAEdgeIv && gSMRAAdjIv && gestureOK;
    if (!ok) {
        DMLog([NSString stringWithFormat:@"[smresize] iPadOS 17's resize gesture is not as read on 17.5.1 here (ivars %d%d, gesture %d): a dragged side stays behind the finger by the pan's start distance, as Apple has it",
            gSMRAEdgeIv != NULL, gSMRAAdjIv != NULL, gestureOK]);
        return;
    }
    MSHookMessageEx(c, gestureS, (IMP)DMSMRAGesture, (IMP *)&o_SMRAGesture);
    gSMRAOn17 = o_SMRAGesture != NULL;
#if DEBUG
    if (sceneOK) MSHookMessageEx(c, sceneS, (IMP)DMSMRASceneSize, (IMP *)&o_SMRASceneSize);   // (17: only the trace -- gSMRAOn16 is off)
#endif
    DMLog(gSMRAOn17 ? @"[smresize] a dragged side keeps its distance from where the finger touched (17's edge adjustment caught up with the pan's start)"
                    : @"[smresize] the resize hook did not go in");
}
