// SpecDump (debug builds only: the Makefile leaves it out of FINALPACKAGE builds): with /tmp/macsettings-dump present, every Settings page that appears writes its specifiers (identifier, name, cell
// type, detail class, getter/setter, target, properties) to /tmp/macsettings-dump.log -- used to read Apple's own pages (Pointer Control, Trackpad &
// Mouse, Home Screen & Dock) on each iOS version instead of guessing. Read-only: nothing is changed.
#import <UIKit/UIKit.h>
#import <objc/message.h>
#import <objc/runtime.h>
#import <unistd.h>

@interface PSListController : UIViewController
- (NSArray *)specifiers;
@end

static SEL SDSel(id spec, const char *name) {
    Ivar iv = class_getInstanceVariable(object_getClass(spec), name);
    if (!iv) return NULL;
    return *(SEL *)((uint8_t *)(__bridge void *)spec + ivar_getOffset(iv));
}
static void SDDump(PSListController *l) {
    if (access("/tmp/macsettings-dump", F_OK) != 0) return;
    NSMutableString *out = [NSMutableString stringWithFormat:@"==== %@ title=%@ (%@)\n", NSStringFromClass([l class]), l.title, [NSDate date]];
    @try {
        for (id sp in [l specifiers]) {
            NSString *ident = [sp respondsToSelector:@selector(identifier)] ? [sp performSelector:@selector(identifier)] : nil;
            NSString *name = [sp respondsToSelector:@selector(name)] ? [sp performSelector:@selector(name)] : nil;
            long long cell = [sp respondsToSelector:NSSelectorFromString(@"cellType")] ? ((long long (*)(id, SEL))objc_msgSend)(sp, NSSelectorFromString(@"cellType")) : -1;
            Class detail = [sp respondsToSelector:NSSelectorFromString(@"detailControllerClass")] ? ((Class (*)(id, SEL))objc_msgSend)(sp, NSSelectorFromString(@"detailControllerClass")) : Nil;
            id target = nil; @try { target = [sp valueForKey:@"target"]; } @catch (NSException *e) {}
            SEL g = SDSel(sp, "getter"), s = SDSel(sp, "setter");
            NSDictionary *props = nil; @try { props = [sp valueForKey:@"properties"]; } @catch (NSException *e) {}
            NSMutableString *p = [NSMutableString string];
            for (id k in props) { NSString *v = [[props[k] description] stringByReplacingOccurrencesOfString:@"\n" withString:@" "]; if (v.length > 160) v = [[v substringToIndex:160] stringByAppendingString:@"…"]; [p appendFormat:@" %@=%@;", k, v]; }
            [out appendFormat:@"- id=%@ name=%@ cell=%lld detail=%@ target=%@ get=%@ set=%@ |%@\n", ident, name, cell, detail ? NSStringFromClass(detail) : @"-",
                target ? NSStringFromClass([target class]) : @"-", g ? NSStringFromSelector(g) : @"-", s ? NSStringFromSelector(s) : @"-", p];
        }
    } @catch (NSException *e) { [out appendFormat:@"exception %@\n", e.reason]; }
    FILE *f = fopen("/tmp/macsettings-dump.log", "a");
    if (f) { fputs(out.UTF8String, f); fclose(f); }
}

%hook PSListController
- (void)viewDidAppear:(BOOL)animated {
    %orig;
    SDDump((PSListController *)self);
}
%end
