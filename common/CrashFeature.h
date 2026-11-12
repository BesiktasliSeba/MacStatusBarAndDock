// CrashFeature.h -- which feature or part did the crash come from? (MacStatusBar&Dock, 2026-09-26) The crash guard's step 1b (CrashStep.h) asks
// this, through MacCrashBlame.dylib (loader/CrashFeatureHelper.m), about a SpringBoard crash report that points at us (CrashBlame.h: verdict OURS),
// so it can turn off only what crashed instead of the whole tweak.
//
// The place: the top-most frame in one of our parts -- in the last exception backtrace if there is one (where an exception was thrown), else in
// the faulting thread -- as that part's image offset. The map (CrashMap.txt, built by tools/make-crashmap.py from tools/crashmap-rules.txt) says
// what that place belongs to:
//  - a big part (MacStatusBarCore, DockMagnification) has a function map per arch slice, keyed by the slice's LC_UUID; a report whose image UUID is
//    not in the map (an old map, another build) gets the part's own fallback, never a guess from someone else's addresses;
//  - a small part has one target for all of it.
// A target is a switch (domain, key, the value that turns it off) or "part" (the part is not loaded in SpringBoard any more, CrashStep.h). A switch
// that is already off cannot be the cause, so the part's own fallback goes instead (for the status bar: Stock status bar mode), else the part. Our two loaders (MacStatusBar.dylib, MacDock.dylib) and anything not in the
// map have no target: the guard then goes on to its step 2 as before.
// Cost: only after a crash that counted against us: one report parse (as CrashBlame.h) and one read of the map (~15 KB).
#pragma once
#import "CrashBlame.h"
#include "DisplayPrefs.h"   // (1.8.7: a switch a display turns on for itself, MSBDFeatureDispOn)

// The report body (the JSON object after the header line), as MSBDBlameReportData reads it.
static inline NSDictionary *MSBDFeatureBody(NSData *data) {
    if (!data.length || data.length > MSBD_BLAME_MAX_BYTES) return nil;
    const char *bytes = (const char *)data.bytes;
    const char *nl = memchr(bytes, '\n', data.length);
    id body = nil;
    if (nl) {
        NSUInteger start = (NSUInteger)(nl - bytes) + 1;
        if (start < data.length) body = [NSJSONSerialization JSONObjectWithData:[data subdataWithRange:NSMakeRange(start, data.length - start)] options:0 error:nil];
        if (!body && start < data.length) {
            NSUInteger len = MSBDBlameObjectLength(bytes + start, data.length - start);
            if (len) body = [NSJSONSerialization JSONObjectWithData:[data subdataWithRange:NSMakeRange(start, len)] options:0 error:nil];
        }
    }
    if (![body isKindOfClass:[NSDictionary class]] || !body[@"threads"]) {
        id whole = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
        if ([whole isKindOfClass:[NSDictionary class]]) body = whole;
    }
    if (![body isKindOfClass:[NSDictionary class]]) return nil;
    // (a watchdog report: its stacks are only in a stackshot -- turned into the usual shape as the verdict's reader does, MSBDBlameBodyFromData;
    // without it a stuck main thread counted against us but was "not pinned on us" here, and the whole tweak went off instead of the part)
    if (!body[@"threads"] && body[@"stackshot"]) body = MSBDBlameFromStackshot(body);
    return body;
}

// The top-most frame in one of our images: its image name (no ".dylib"), that image's UUID (lowercase, "" if not given) and the offset. Our
// pass-through hooks (the map's "transparent" functions) are passed over while any other frame of ours is there. In a stack overflow the top-most
// frame of ours IN THE CYCLE (MSBDBlameRecursion, CrashBlame.h): the very top is only where the stack ran out -- the desktop's hit-test recursion
// ran out in a window-layout helper and Windowing was switched off instead of the desktop (iPad 2, 3 Oct). A cycle with no frame of ours: as before.
static inline BOOL MSBDFeatureTopFrameIn(NSDictionary *body, NSString *map, NSString **image, NSString **uuid, unsigned long long *offset, NSString **where, BOOL cycleOnly);
static inline BOOL MSBDFeatureTopFrame(NSDictionary *body, NSString *map, NSString **image, NSString **uuid, unsigned long long *offset, NSString **where) {
    return MSBDFeatureTopFrameIn(body, map, image, uuid, offset, where, YES) || MSBDFeatureTopFrameIn(body, map, image, uuid, offset, where, NO);
}
static inline BOOL MSBDFeatureTopFrameIn(NSDictionary *body, NSString *map, NSString **image, NSString **uuid, unsigned long long *offset, NSString **where, BOOL cycleOnly) {
    NSArray *images = [body[@"usedImages"] isKindOfClass:[NSArray class]] ? body[@"usedImages"] : ([body[@"binaryImages"] isKindOfClass:[NSArray class]] ? body[@"binaryImages"] : nil);
    NSArray *threads = [body[@"threads"] isKindOfClass:[NSArray class]] ? body[@"threads"] : nil;
    NSArray *faultFrames = nil;
    id ft = body[@"faultingThread"];
    if ([ft isKindOfClass:[NSNumber class]] && [ft unsignedIntegerValue] < threads.count && [threads[[ft unsignedIntegerValue]] isKindOfClass:[NSDictionary class]])
        faultFrames = threads[[ft unsignedIntegerValue]][@"frames"];
    if (![faultFrames isKindOfClass:[NSArray class]]) {
        faultFrames = nil;
        for (NSDictionary *t in threads)
            if ([t isKindOfClass:[NSDictionary class]] && [t[@"triggered"] boolValue] && [t[@"frames"] isKindOfClass:[NSArray class]]) { faultFrames = t[@"frames"]; break; }
    }
    NSArray *excFrames = [body[@"lastExceptionBacktrace"] isKindOfClass:[NSArray class]] ? body[@"lastExceptionBacktrace"] : nil;
    NSArray *fallback = nil;   // (a pass-through hook of ours: only when no other frame of ours is there)
    for (int pass = 0; pass < 2; pass++) {   // (the exception backtrace first: where the exception was thrown)
        NSArray *frames = pass == 0 ? excFrames : faultFrames;
        NSSet<NSString *> *cycle = cycleOnly ? MSBDBlameRecursion(frames) : nil;
        if (cycleOnly && !cycle) continue;   // (no overflow here: the plain scan, cycleOnly NO)
        for (NSUInteger k = MSBDBlameFirstFrame(frames); k < frames.count; k++) {   // (not a signal handler's frames)
            NSDictionary *f = frames[k];
            if (![f isKindOfClass:[NSDictionary class]] || ![f[@"imageIndex"] isKindOfClass:[NSNumber class]] || ![f[@"imageOffset"] isKindOfClass:[NSNumber class]]) continue;
            if (cycle && ![cycle containsObject:MSBDBlameFrameKey(f) ?: @""]) continue;   // (where the stack ran out: not the cause)
            NSUInteger i = [f[@"imageIndex"] unsignedIntegerValue];
            if (i >= images.count || ![images[i] isKindOfClass:[NSDictionary class]]) continue;
            NSDictionary *img = images[i];
            NSString *path = [img[@"path"] isKindOfClass:[NSString class]] ? img[@"path"] : nil;
            NSString *name = [img[@"name"] isKindOfClass:[NSString class]] ? img[@"name"] : path.lastPathComponent;
            if (MSBDBlameImageKind(path, name) != kMSBDImgOurs) continue;
            BOOL through = MSBDBlameTransparent(map, img, name, f);
            if (through && fallback) continue;
            if ([name hasSuffix:@".dylib"]) name = [name substringToIndex:name.length - 6];
            NSString *u = [img[@"uuid"] isKindOfClass:[NSString class]] ? [img[@"uuid"] lowercaseString] : @"";
            NSString *w = [(pass == 0 ? @"exception backtrace" : @"faulting thread") stringByAppendingString:cycle ? @", recursion" : @""];
            if (through) { fallback = @[name, u, f[@"imageOffset"], w]; continue; }   // (used only if nothing else of ours is there)
            *image = name; *uuid = u; *offset = [f[@"imageOffset"] unsignedLongLongValue]; *where = w;
            return YES;
        }
    }
    // (a cycle whose only frame of ours is a pass-through hook says nothing about which part of ours: the plain scan decides, as before)
    if (fallback && !cycleOnly) { *image = fallback[0]; *uuid = fallback[1]; *offset = [fallback[2] unsignedLongLongValue]; *where = fallback[3]; return YES; }
    return NO;
}

// (The map lookup, MSBDFeatureMapTarget, is in CrashBlame.h: the classifier needs it too, for the transparent hooks.)

// A switch's value now (its default when never set). A text (a list row's choice) reads as the default -- or, where the rule names the texts that
// count as off (offtext=<text>[,<text>...]: Dock Style's "default"; the Banner and Control Center Styles' "stock", and Control Center's
// "bigsurcenter"), as off for those and on for any other (review 1.8.4 P2-L1: Default was read as on, so a crash pinned there set nothing that was
// not set already, and the whole tweak went after the next crash instead of the part).
// One stored value read so (*known NO: nothing that reads as a value of the switch -- then `def`).
static inline BOOL MSBDFeatureValueOn(CFPropertyListRef v, BOOL def, BOOL off, NSArray<NSString *> *offTexts, BOOL *known) {
    BOOL on = def, k = NO;
    if (v) {
        if (CFGetTypeID(v) == CFBooleanGetTypeID()) { on = CFBooleanGetValue(v); k = YES; }
        else if (CFGetTypeID(v) == CFNumberGetTypeID()) { on = [(__bridge NSNumber *)v boolValue]; k = YES; }
        else if (offTexts.count && CFGetTypeID(v) == CFStringGetTypeID()) { on = [offTexts containsObject:(__bridge NSString *)v] ? off : !off; k = YES; }
    }
    if (known) *known = k;
    return on;
}
static inline BOOL MSBDFeaturePrefValue(NSString *domain, NSString *key, BOOL def, BOOL off, NSArray<NSString *> *offTexts) {
    CFPreferencesAppSynchronize((__bridge CFStringRef)domain);
    CFPropertyListRef v = CFPreferencesCopyValue((__bridge CFStringRef)key, (__bridge CFStringRef)domain, kCFPreferencesCurrentUser, kCFPreferencesAnyHost);
    BOOL on = MSBDFeatureValueOn(v, def, off, offTexts, NULL);
    if (v) CFRelease(v);
    return on;
}
// 1.8.7 (the per-display settings, plans/design-1.8.7-displays.md section 8): is a switch of KT's domains (part msb or dock, DisplayPrefs.h) on for a
// display though the iPad's key is off? A display's own override of it ("<display>/<part>/<key>" in the displays domain) that reads on, as the iPad's
// key is read, while the layer's master switch is on (off: every override dormant); or the row's display default when it is not the off value (Show
// Trash in Dock: ON on every display, whatever the master switch) for a remembered display ("<display>/info") with no override of its own read. Then
// the path that crashed can run on that display -- Menu Bar Size above Small for a TV with the iPad at Small, the TV's auto-hide, the TV's Trash with
// the iPad's off -- so the switch is still the answer: step 1b sets the iPad's key (no change there) and every display's (CrashStep.h
// MSBDGuardDispClear). Without it a crash on a display-only path took the part's fallback (Stock status bar mode), then the part, and the TV's
// override that ran it stayed (review of 1.8.7).
static inline BOOL MSBDFeatureDispOn(NSString *domain, NSString *key, BOOL off, NSArray<NSString *> *offTexts) {
    const char *part = MSBDDispPartOfDomain(domain.UTF8String);
    if (!part || !key.length) return NO;
    CFStringRef dom = CFSTR(MSBD_DISP_DOMAIN);
    CFPreferencesSynchronize(dom, kCFPreferencesCurrentUser, kCFPreferencesAnyHost);
    NSDictionary *all = CFBridgingRelease(CFPreferencesCopyMultiple(NULL, dom, kCFPreferencesCurrentUser, kCFPreferencesAnyHost));
    if (![all isKindOfClass:[NSDictionary class]] || !all.count) return NO;
    id master = all[@MSBD_DISP_MASTER_KEY];
    BOOL layerOn = ![master isKindOfClass:[NSNumber class]] || [master boolValue];
    NSMutableSet<NSString *> *own = [NSMutableSet set];   // (the displays whose own override is read: their display default does not stand)
    for (NSString *flat in all) {
        char display[128];
        if (!layerOn || ![flat isKindOfClass:[NSString class]] || !MSBDDispFlatIs(flat.UTF8String, part, key.UTF8String)
            || !MSBDDispFlatSplit(flat.UTF8String, display, sizeof display, NULL, 0, NULL, 0)) continue;
        BOOL known = NO, on = MSBDFeatureValueOn((__bridge CFPropertyListRef)all[flat], !off, off, offTexts, &known);
        if (!known) continue;   // (a value of another type reads as not set)
        if (on != off) return YES;
        [own addObject:@(display)];
    }
    int def = 0;
    if (!MSBDDispDisplayDefault(part, key.UTF8String, &def) || (def != 0) == off) return NO;
    for (NSString *k in all) {
        if (![k isKindOfClass:[NSString class]] || ![k hasSuffix:@MSBD_DISP_INFO_SUFFIX]) continue;
        NSString *d = [k substringToIndex:k.length - strlen(MSBD_DISP_INFO_SUFFIX)];
        if (MSBDDispKeyValid(d.UTF8String) && ![own containsObject:d]) return YES;
    }
    return NO;
}

// The answer for one report and map: YES with *action = "pref <image> <domain> <key> <value> [text=<off text>] <row title>|<where>" (text: the
// list row's choice to store instead of the value -- its rule's first off text, so Settings shows a choice: Dock Style "default") or
// "part <image> - - 0 <where>|<what>" (a piece: "part <its target> - - 0 <where>|<what>"); NO with *action = why not.
// *detail gets where it was found (for the log).
static inline BOOL MSBDFeatureForReport(NSData *report, NSString *map, NSString **action, NSString **detail) {
    *detail = @"";
    NSDictionary *body = MSBDFeatureBody(report);
    NSString *blamed = nil;
    if (MSBDBlameReportBodyMap(body, map, &blamed) != kMSBDBlameOurs) { *action = [NSString stringWithFormat:@"not pinned on us (%@)", blamed]; return NO; }
    NSString *image = nil, *uuid = nil, *where = nil; unsigned long long offset = 0;
    if (!MSBDFeatureTopFrame(body, map, &image, &uuid, &offset, &where)) { *action = [NSString stringWithFormat:@"none of our code on the crash stacks (%@)", blamed]; return NO; }
    if (!map.length) { *action = @"no crash map"; return NO; }
    NSDictionary<NSString *, NSArray *> *targets = nil; NSString *how = nil, *partTitle = nil;
    NSString *target = MSBDFeatureMapTarget(map, image, uuid, offset, &targets, &how, &partTitle);
    *detail = [NSString stringWithFormat:@"%@+0x%llx (%@; %@) -> %@", image, offset, where, how, target ?: @"nothing"];
    NSArray *spec = target ? targets[target] : nil;
    if (!spec.count) { *action = [NSString stringWithFormat:@"%@ cannot be turned off on its own", image]; return NO; }
    // A piece (review of 1.8.6): code with no Settings row of its own (the battery icon's plug during a charge hold) goes off as a part does -- on
    // the skip list under its target's name, which that code reads (MSBDCrashSkipped), and with Turn Back On to bring it back -- never as a stored
    // switch nobody can switch back.
    if ([spec[0] isEqualToString:@"piece"]) {
        NSString *title = spec.count > 1 ? [[spec subarrayWithRange:NSMakeRange(1, spec.count - 1)] componentsJoinedByString:@" "] : [NSString stringWithFormat:@"%@|%@", target, target];
        *action = [NSString stringWithFormat:@"part %@ - - 0 %@", target, title];
        return YES;
    }
    // A switch that is already off cannot be the cause: then the part's own fallback (for the status bar: Stock status bar mode), then the part. Off
    // means off on every display too (1.8.7: a display's own override, or the row's display default, runs the path with the iPad's key off).
    NSString *fallback = MSBDFeatureMapTarget(map, image, @"", 0, &targets, &how, &partTitle);
    BOOL isPref = [spec[0] isEqualToString:@"pref"];   // (a "part" target is the part, no fallback)
    for (NSArray *try in @[spec, isPref && fallback && ![fallback isEqualToString:target] && targets[fallback] ? targets[fallback] : @[]]) {
        if (try.count < 5 || ![try[0] isEqualToString:@"pref"]) continue;
        NSString *domain = try[1], *key = try[2]; BOOL off = [try[3] boolValue], def = [try[4] boolValue];
        NSUInteger at = 5;
        NSArray<NSString *> *offTexts = nil;   // (the texts that count as off; the first is the one written to turn it off)
        if (try.count > at && [try[at] hasPrefix:@"offtext="]) offTexts = [[try[at++] substringFromIndex:8] componentsSeparatedByString:@","];
        NSString *title = try.count > at ? [[try subarrayWithRange:NSMakeRange(at, try.count - at)] componentsJoinedByString:@" "] : [NSString stringWithFormat:@"%@|%@", key, key];
        if (MSBDFeaturePrefValue(domain, key, def, off, offTexts) != off || MSBDFeatureDispOn(domain, key, off, offTexts)) {   // (1.8.7: or on for a display)
            NSString *text = offTexts.firstObject.length ? [@" text=" stringByAppendingString:offTexts.firstObject] : @"";
            *action = [NSString stringWithFormat:@"pref %@ %@ %@ %d%@ %@", image, domain, key, off, text, title];
            return YES;
        }
        *detail = [*detail stringByAppendingFormat:@" (%@ already %@)", key, off ? @"on" : @"off"];
    }
    *action = [NSString stringWithFormat:@"part %@ - - 0 %@", image, partTitle.length ? partTitle : [NSString stringWithFormat:@"its part %@|%@", image, image]];
    return YES;
}
