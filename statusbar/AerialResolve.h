// AerialResolve.h -- finds the methods our integration uses in an obfuscated Aerial build (5.x) by their shape (MacStatusBar&Dock). Plain Foundation:
// StatusBar.x (DMAerialResolveObfuscated) and the Mac test tools/test-a5resolve.m run this very code, the test on two builds' method lists (private).
// Each build renames Aerial's own selectors to random names ("Aerial_" and random letters), but three things survive: the type encodings, the methods that keep
// their real names (UIKit overrides, delegate methods, a few public ones), and the source order, which the compiler keeps as the order of the code in
// the binary (the caller sorts by code address). The real-named methods are the anchors; every role must be found with the exact expected shape, or
// it is missing and the integration stays off: nothing is ever called on a guess.
// stage: AerialStage's own instance methods, core: AerialCore's own class methods -- each an array of @[name, types], in source order, where types
// is the type encoding without the frame offsets (digits) and with CGRect written as R ("v@:R").
#pragma once
#import <Foundation/Foundation.h>

// A selector this build scrambled (every scrambled name starts with Aerial_); anything else kept its real name.
static inline BOOL DMA5Scrambled(NSString *name) { return [name hasPrefix:@"Aerial_"]; }
static inline NSInteger DMA5Index(NSArray<NSArray *> *list, NSString *name) {
    for (NSUInteger i = 0; i < list.count; i++) if ([list[i][0] isEqualToString:name]) return (NSInteger)i;
    return -1;
}
static inline NSString *DMA5At(NSArray<NSArray *> *list, NSInteger i, NSString *types) {   // the name at that place if its types match, else nil
    if (i < 0 || i >= (NSInteger)list.count) return nil;
    return [list[i][1] isEqualToString:types] ? list[i][0] : nil;
}
// The roles (3.0's names) -> this build's names, or nil with every missing role added to `missing`. *minimizeTakesTransform: the minimize method
// takes a CGAffineTransform (5.0 and later).
static NSDictionary<NSString *, NSString *> *DMA5ResolveRoles(NSArray<NSArray *> *L, NSArray<NSArray *> *C, NSMutableArray<NSString *> *missing, BOOL *minimizeTakesTransform) {
    NSMutableDictionary<NSString *, NSString *> *m = [NSMutableDictionary dictionary];
    #define DM_ROLE(key, expr) do { NSString *v_ = (expr); if (v_ && ![m.allValues containsObject:v_]) m[key] = v_; else [missing addObject:key]; } while (0)
    NSInteger touches = DMA5Index(L, @"touchesBegan:withEvent:");
    DM_ROLE(@"_bringStageToFrontIfNeeded", touches == 1 ? DMA5At(L, 0, @"v@:") : nil);   // the very first method, before touchesBegan:withEvent:
    NSInteger initFrame = DMA5Index(L, @"initWithFrame:"), layout = DMA5Index(L, @"layoutSubviews");
    DM_ROLE(@"handlePan:", (initFrame >= 0 && layout == initFrame + 2) ? DMA5At(L, initFrame + 1, @"v@:@") : nil);   // the only method between those two
    NSInteger trait = DMA5Index(L, @"traitCollectionDidChange:");
    BOOL traitOK = trait >= 0 && DMA5At(L, trait + 1, @"v@:@") != nil;   // (a one-object method right after it)
    DM_ROLE(@"_adjustStageToFitScreenIfNeeded", traitOK ? DMA5At(L, trait + 2, @"v@:") : nil);
    DM_ROLE(@"_saveCurrentStateForOrientation", traitOK ? DMA5At(L, trait + 3, @"v@:") : nil);
    // Between gestureRecognizer:shouldRecognizeSimultaneouslyWithGestureRecognizer: and removeFromSuperview: four scrambled void methods without
    // arguments, in this order -- the roles adjustContentScaleToHost and ensureSceneVisible, one we do not use, and removeStageSafely. A method that
    // kept its real name in between is one Aerial added later, never one of the four (5.1 added one before the last, so "removeFromSuperview minus 5"
    // found nothing and three roles were missing). Any other scrambled method in between, or a count other than four: refused.
    NSInteger removeSV = DMA5Index(L, @"removeFromSuperview"), simul = DMA5Index(L, @"gestureRecognizer:shouldRecognizeSimultaneouslyWithGestureRecognizer:");
    NSMutableArray<NSString *> *run = [NSMutableArray array];
    BOOL runOK = simul >= 0 && removeSV > simul;
    for (NSInteger i = simul + 1; runOK && i < removeSV; i++) {
        if (!DMA5Scrambled(L[i][0])) continue;   // (a real-named addition)
        if (![L[i][1] isEqualToString:@"v@:"]) runOK = NO; else [run addObject:L[i][0]];
    }
    if (run.count != 4) runOK = NO;
    DM_ROLE(@"adjustContentScaleToHost", runOK ? run[0] : nil);
    DM_ROLE(@"ensureSceneVisible", runOK ? run[1] : nil);
    DM_ROLE(@"removeStageSafely", runOK ? run[3] : nil);   // (run[2] is not used)
    NSString *flex = nil; int flexCount = 0;
    for (NSArray *e in L) if ([e[1] isEqualToString:@"v@:R"]) { flex = e[0]; flexCount++; }
    DM_ROLE(@"_applyFlexDisabledLayoutWithScreenBounds:", flexCount == 1 ? flex : nil);
    NSInteger willEnd = DMA5Index(L, @"contextMenuInteraction:willEndForConfiguration:animator:"), menuVisible = -1; int boolCount = 0;
    for (NSUInteger i = 0; i < L.count; i++) if ([L[i][1] isEqualToString:@"B@:"]) { menuVisible = (NSInteger)i; boolCount++; }   // (the only no-argument BOOL)
    DM_ROLE(@"handleResizeBR:", (boolCount == 1 && willEnd >= 0 && menuVisible > willEnd) ? DMA5At(L, menuVisible + 1, @"v@:@") : nil);
    NSInteger trim = -1;
    for (NSUInteger i = 0; i < L.count; i++) if ([L[i][0] hasSuffix:@":adjustLeft:adjustRight:adjustTop:adjustBottom:"]) trim = (trim == -1) ? (NSInteger)i : -2;
    BOOL trimOK = trim > 3 && DMA5At(L, trim - 2, @"v@:@") != nil;   // (a one-object method two before it)
    DM_ROLE(@"restoreFromMinimize", trimOK ? DMA5At(L, trim - 1, @"v@:") : nil);
    NSString *minimize = trimOK ? DMA5At(L, trim - 3, @"v@:{CGAffineTransform=dddddd}") : nil;
    if (minimizeTakesTransform) *minimizeTakesTransform = minimize != nil;
    if (!minimize && trimOK) minimize = DMA5At(L, trim - 3, @"v@:");
    DM_ROLE(@"minimizeStage", minimize);
    // AerialCore (class methods): these kept their later keywords, only the first one is renamed
    NSString *fg = nil, *bg = nil, *apply = nil, *rehost = nil; int fgN = 0, bgN = 0, applyN = 0, rehostN = 0;
    NSInteger trigger = DMA5Index(C, @"triggerAerialForBundle:");
    for (NSUInteger i = 0; i < C.count; i++) {
        NSString *s = C[i][0], *t = C[i][1];
        if ([s hasSuffix:@":foregroundvalue:"] && [t isEqualToString:@"v@:@B"]) { fg = s; fgN++; }
        if ([s hasSuffix:@":forApp:"] && [t isEqualToString:@"v@:B@"]) { bg = s; bgN++; }
        NSString *base = [s componentsSeparatedByString:@":"][0];
        if ([s isEqualToString:[base stringByAppendingString:@":frame:"]] && [t isEqualToString:@"v@:@R"] && DMA5Index(C, [base stringByAppendingString:@":frame:force:"]) < 0) { apply = s; applyN++; }
        if ([s isEqualToString:[base stringByAppendingString:@":"]] && [t isEqualToString:@"v@:@"] && trigger >= 0 && (NSInteger)i < trigger) {
            NSInteger c = DMA5Index(C, [base stringByAppendingString:@":completion:"]);
            if (c == (NSInteger)i + 1 && [C[c][1] isEqualToString:@"v@:@@?"]) { rehost = s; rehostN++; }
        }
    }
    DM_ROLE(@"setForeground:foregroundvalue:", fgN == 1 ? fg : nil);
    DM_ROLE(@"forceBackgrounded:forApp:", bgN == 1 ? bg : nil);
    DM_ROLE(@"applySceneFrameForBundle:frame:", applyN == 1 ? apply : nil);
    DM_ROLE(@"rehost:", rehostN == 1 ? rehost : nil);
    #undef DM_ROLE
    return missing.count ? nil : m;
}
// A type encoding as the roles compare it: the frame offsets (digits) taken out, CGRect written as R.
static inline NSString *DMA5Types(const char *enc) {
    NSMutableString *t = [NSMutableString string];
    for (const char *c = enc ? enc : ""; *c; c++) if (*c < '0' || *c > '9') [t appendFormat:@"%c", *c];
    [t replaceOccurrencesOfString:@"{CGRect={CGPoint=dd}{CGSize=dd}}" withString:@"R" options:0 range:NSMakeRange(0, t.length)];
    return t;
}
