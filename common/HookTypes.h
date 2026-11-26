// HookTypes.h -- a Logos hook group goes in only where each method it hooks has the types its declarations compile to (1.8.9).
// Why: a 1.8.9 test build crashed SpringBoard into Safe Mode at the first Lock Screen (iPadOS 18.5): two hooks declared
// -[SBDashBoardStatusBarController setStatusBarAlpha:(double)alpha style:legibilitySettings:] where iPadOS passes the alpha as an NSNumber
// ("v40@0:8@16q24@32" on 15.6.1, 16.7.7, 17.5.1 and 18.5): the hook took the style (an integer, 1) for the legibility settings object, and
// retaining it faulted.
// Each guarded group has a table kHookSigs_<group> beside it ({class, selector, types}); tools/test-hooktypes.sh checks every table against its
// group's declarations (compiled) and against the methods of iPadOS 15.6.1, 16.7.7, 17.5.1 and 18.5 read from Apple's IPSWs
// (tools/hooktypes-ipados.txt). At run time a method that is not there is Logos's own case (it hooks nothing for it, as before); one that is
// there with other types keeps the whole group out, and the caller says so in the system log.
#pragma once
#import <Foundation/Foundation.h>
#import <objc/runtime.h>
#include <os/log.h>
#include <string.h>

typedef struct { const char *cls; const char *sel; const char *types; } MSBDHookSig;   // types bare: "v@:@q@" = return, self, _cmd, arguments

// A runtime type string reduced to what a hook's declaration fixes: no frame offsets, no qualifiers (r n N o O R V), no quoted class names,
// no struct or union names, a block ("@?") as an object; an array's length kept ("[4c]"). "v36@0:8i16@20@?28" -> "v@:i@@". NO (and out
// empty) when it does not fit in n.
static inline BOOL MSBDHookBareTypes(const char *enc, char *out, size_t n) {
    if (!out || n == 0) return NO;
    out[0] = 0;
    if (!enc) return NO;
    size_t k = 0;
    BOOL arrayLength = NO;   // (the digits right after '[' are the array's length, part of the type)
    for (const char *p = enc; *p; p++) {
        char ch = *p;
        if (ch >= '0' && ch <= '9' && !arrayLength) continue;
        if (!(ch >= '0' && ch <= '9')) arrayLength = (ch == '[');
        if (ch == 'r' || ch == 'n' || ch == 'N' || ch == 'o' || ch == 'O' || ch == 'R' || ch == 'V') continue;
        if (ch == '"') { p++; while (*p && *p != '"') p++; if (!*p) break; continue; }
        if (ch == '?' && k > 0 && out[k - 1] == '@') continue;
        if (k + 1 >= n) { out[0] = 0; return NO; }
        out[k++] = ch;
        if (ch == '{' || ch == '(') {   // (the name up to '=' dropped: "{CGRect={CGPoint=dd}{CGSize=dd}}" -> "{{dd}{dd}}")
            const char *q = p + 1;
            while (*q && *q != '=' && *q != '}' && *q != ')' && *q != '{' && *q != '(') q++;
            if (*q == '=') p = q;
        }
    }
    out[k] = 0;
    return YES;
}

// nil when every method of the table that is there has the table's types; otherwise the first one that does not, for the log
static inline NSString *MSBDHookSigsWrong(const MSBDHookSig *sigs, size_t count) {
    for (size_t i = 0; i < count; i++) {
        Class c = sigs[i].cls ? objc_getClass(sigs[i].cls) : Nil;
        Method m = c && sigs[i].sel ? class_getInstanceMethod(c, sel_registerName(sigs[i].sel)) : NULL;
        if (!m) continue;   // (not there: Logos hooks nothing for it)
        const char *enc = method_getTypeEncoding(m);
        char bare[160];
        if (!MSBDHookBareTypes(enc, bare, sizeof bare) || !sigs[i].types || strcmp(bare, sigs[i].types) != 0)
            return [NSString stringWithFormat:@"-[%s %s] is %s on this iPadOS, our hook is written for %s", sigs[i].cls, sigs[i].sel, enc ?: "(no types)", sigs[i].types ?: "?"];
    }
    return nil;
}
#define MSBD_HOOK_SIGS_WRONG(table) MSBDHookSigsWrong((table), sizeof(table) / sizeof((table)[0]))

// The check before a group's %init: YES = hook it; NO = keep it out, said in the system log (module: our part's name, group: what stays off).
static inline BOOL MSBDHookGroupTypesOK(const MSBDHookSig *sigs, size_t count, const char *module, const char *group, NSString **wrongOut) {
    NSString *w = MSBDHookSigsWrong(sigs, count);
    if (wrongOut) *wrongOut = w;
    if (!w) return YES;
    os_log(OS_LOG_DEFAULT, "%{public}s: %{public}s not hooked: %{public}@", module ?: "?", group ?: "?", w);
    return NO;
}
