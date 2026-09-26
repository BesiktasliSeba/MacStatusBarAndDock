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
    return [body isKindOfClass:[NSDictionary class]] ? body : nil;
}

// The top-most frame in one of our images: its image name (no ".dylib"), that image's UUID (lowercase, "" if not given) and the offset. Our
// pass-through hooks (the map's "transparent" functions) are passed over while any other frame of ours is there.
static inline BOOL MSBDFeatureTopFrame(NSDictionary *body, NSString *map, NSString **image, NSString **uuid, unsigned long long *offset, NSString **where) {
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
        for (NSUInteger k = MSBDBlameFirstFrame(frames); k < frames.count; k++) {   // (not a signal handler's frames)
            NSDictionary *f = frames[k];
            if (![f isKindOfClass:[NSDictionary class]] || ![f[@"imageIndex"] isKindOfClass:[NSNumber class]] || ![f[@"imageOffset"] isKindOfClass:[NSNumber class]]) continue;
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
            NSString *w = pass == 0 ? @"exception backtrace" : @"faulting thread";
            if (through) { fallback = @[name, u, f[@"imageOffset"], w]; continue; }   // (used only if nothing else of ours is there)
            *image = name; *uuid = u; *offset = [f[@"imageOffset"] unsignedLongLongValue]; *where = w;
            return YES;
        }
    }
    if (fallback) { *image = fallback[0]; *uuid = fallback[1]; *offset = [fallback[2] unsignedLongLongValue]; *where = fallback[3]; return YES; }
    return NO;
}

// (The map lookup, MSBDFeatureMapTarget, is in CrashBlame.h: the classifier needs it too, for the transparent hooks.)

// A switch's value now (its default when never set).
static inline BOOL MSBDFeaturePrefValue(NSString *domain, NSString *key, BOOL def) {
    CFPreferencesAppSynchronize((__bridge CFStringRef)domain);
    CFPropertyListRef v = CFPreferencesCopyValue((__bridge CFStringRef)key, (__bridge CFStringRef)domain, kCFPreferencesCurrentUser, kCFPreferencesAnyHost);
    BOOL on = def;
    if (v) { if (CFGetTypeID(v) == CFBooleanGetTypeID()) on = CFBooleanGetValue(v); else if (CFGetTypeID(v) == CFNumberGetTypeID()) on = [(__bridge NSNumber *)v boolValue]; CFRelease(v); }
    return on;
}

// The answer for one report and map: YES with *action = "pref <image> <domain> <key> <value> <row title>|<where>" or
// "part <image> - - 0 <where>|<what>"; NO with *action = why not.
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
    // A switch that is already off cannot be the cause: then the part's own fallback (for the status bar: Stock status bar mode), then the part.
    NSString *fallback = MSBDFeatureMapTarget(map, image, @"", 0, &targets, &how, &partTitle);
    BOOL isPref = [spec[0] isEqualToString:@"pref"];   // (a "part" target is the part, no fallback)
    for (NSArray *try in @[spec, isPref && fallback && ![fallback isEqualToString:target] && targets[fallback] ? targets[fallback] : @[]]) {
        if (try.count < 5 || ![try[0] isEqualToString:@"pref"]) continue;
        NSString *domain = try[1], *key = try[2]; BOOL off = [try[3] boolValue], def = [try[4] boolValue];
        NSString *title = try.count > 5 ? [[try subarrayWithRange:NSMakeRange(5, try.count - 5)] componentsJoinedByString:@" "] : [NSString stringWithFormat:@"%@|%@", key, key];
        if (MSBDFeaturePrefValue(domain, key, def) != off) { *action = [NSString stringWithFormat:@"pref %@ %@ %@ %d %@", image, domain, key, off, title]; return YES; }
        *detail = [*detail stringByAppendingFormat:@" (%@ already %@)", key, off ? @"on" : @"off"];
    }
    *action = [NSString stringWithFormat:@"part %@ - - 0 %@", image, partTitle.length ? partTitle : [NSString stringWithFormat:@"its part %@|%@", image, image]];
    return YES;
}
