// CustomShortcutsRule.h -- Custom Shortcuts (Settings > Keyboard, 1.8.5 item 2, off unless switched on): keyboard shortcuts of your own that open an
// app, open a URL, lay out the front window or go Home. Plain C (an Objective-C part at the end), so the Mac test (tools/test-customshortcuts.c)
// runs these very rules; SpringBoard runs the shortcuts (statusbar/CustomShortcuts.h), Settings records them (macsettings/CustomShortcuts.x).
//
// Based on KeyPilot by wanghuangjie (github.com/wanghuangjie/KeyPilot, main 4b2b247, 6 Nov 2026): its rule format (key, keyCode, modifiers, action,
// enabled), the actions' spelling (app:, url:, window:, system:home), the 64-rule limit, the key names and the shortcut's display order (KPShared.m),
// and the window action names with their aliases (KPWindowActions.m) are his, ported here; its author allowed the integration (KT, 7 Nov 2026).
// Differences from KeyPilot, on purpose (plans/keypilot-integration-study.md): Globe is part of a shortcut's match (KeyPilot's mask drops it, so a
// rule on Control-Left also fired on Globe-Control-Left), Caps Lock is not (a rule must not stop working while Caps Lock is on), shortcuts that
// clash with this tweak's own keys are refused when recorded, and there are no shell actions. As KeyPilot's, the keys are matched in the app that
// has the keyboard (1.8.6: through MacAppBridge's existing key hook, "In the app with the keyboard" below), and SpringBoard also takes them from its
// own presses and its key commands.
//
// Portions: Copyright (c) 2026 wanghuangjie. MIT License:
//   Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the
//   "Software"), to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish,
//   distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the
//   following conditions:
//   The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.
//   THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF
//   MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY
//   CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE
//   OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
// (the full text: third_party/KeyPilot/LICENSE, in the package at /usr/lib/MacStatusBarAndDock/third_party/KeyPilot/LICENSE)
#ifndef MSBD_CUSTOM_SHORTCUTS_RULE_H
#define MSBD_CUSTOM_SHORTCUTS_RULE_H
#include <stdbool.h>
#include <stdint.h>
#include <string.h>
#include <strings.h>
#include "../statusbar/WindowKeysRule.h"   // (the modifier flags, and Window Tiling Shortcuts' rows: a shortcut on one of them is refused)

// The preferences: their own domain, read by SpringBoard at each change (the notification) and written by Settings.
#define kMSBDCSDomain   "com.besiktasliseba.customshortcuts"
#define kMSBDCSEnabled  "enabled"        // (the switch: off unless switched on)
#define kMSBDCSRules    "rules"          // (an array of rules, each {key, keyCode, modifiers, action, enabled}, as KeyPilot's)
#define kMSBDCSChanged  "com.besiktasliseba.customshortcuts/prefsChanged"
// Darwin state while Settings records a shortcut: 1, else 0. SpringBoard runs none of the shortcuts then (a key already taken by one of them would
// run it instead of reaching Settings) and leaves them out of its key commands.
#define kMSBDCSRecordingNote "com.besiktasliseba.customshortcuts.recording"
#define kMSBDCSMaxRules 64               // (KeyPilot's KPMaximumRuleCount)

// KeyPilot (its package: com.whj.keypilot): while it is installed ours step aside (both would run each key) and its rules can be imported.
#define kMSBDCSKeyPilotDomain "com.whj.keypilot"
#define kMSBDCSKeyPilotRules  "Rules"

// The modifiers a shortcut is matched on: Shift, Control, Option, Command and Globe (kMSBDModMask, WindowKeysRule.h). Caps Lock and the keypad
// bit are left out.
static inline unsigned long long MSBDCSMods(unsigned long long flags) { return flags & kMSBDModMask; }

// Why a shortcut can't be recorded, or none.
enum {
    kMSBDCSOK = 0,
    kMSBDCSNoKey,          // (a modifier alone, or no key)
    kMSBDCSNeedsModifier,  // (no Command, Option, Control or Globe: the key would stop typing; Shift alone is typing too)
    kMSBDCSWindowTiling,   // (one of Window Tiling Shortcuts' Globe-Control keys)
    kMSBDCSMacSwitcher,    // (the Mac Switcher's Control-Left, -Right, -Up)
    kMSBDCSEscape,         // (Escape: it cancels the recording, and closes our menus and panels)
    kMSBDCSTaken,          // (another custom shortcut has it)
};
// HID usages (keyboard page 7) a shortcut reads by name.
enum { kMSBDCSHIDA = 0x04, kMSBDCSHIDZ = 0x1D, kMSBDCSHID1 = 0x1E, kMSBDCSHID0 = 0x27, kMSBDCSHIDReturn = 0x28, kMSBDCSHIDEscape = 0x29,
       kMSBDCSHIDDelete = 0x2A, kMSBDCSHIDTab = 0x2B, kMSBDCSHIDSpace = 0x2C, kMSBDCSHIDRight = 0x4F, kMSBDCSHIDLeft = 0x50, kMSBDCSHIDDown = 0x51,
       kMSBDCSHIDUp = 0x52 };
// The modifier keys themselves (Control, Shift, Option, Command, left and right; Caps Lock), and no key: usages 0 to 3 are none on the keyboard page
// (no event, roll-over, POST fail, undefined) -- the Globe key, pressed on its own, comes to an app as a press of usage 3 with the Globe flag (M1,
// 15.6.1, Magic Keyboard: it was taken as "Globe-Key 3").
static inline bool MSBDCSIsModifierKey(long usage) { return (usage >= 0xE0 && usage <= 0xE7) || usage == 0x39 || (usage >= 0x0 && usage <= 0x3); }

// A recorded key: whether it may be a shortcut. usage: the press's HID usage; chars: what the key types without modifiers (UTF-8); flags: the
// press's modifier flags.
static inline int MSBDCSCheck(long usage, const char *chars, unsigned long long flags) {
    unsigned long long m = MSBDCSMods(flags);
    if (MSBDCSIsModifierKey(usage)) return kMSBDCSNoKey;
    if (usage == kMSBDCSHIDEscape) return kMSBDCSEscape;
    if (!(m & (kMSBDModControl | kMSBDModOption | kMSBDModCommand | kMSBDModGlobe))) return kMSBDCSNeedsModifier;
    if (MSBDWinKeyRowFor(MSBDWinKeyFor(usage, chars), m) >= 0) return kMSBDCSWindowTiling;
    if (m == kMSBDModControl && (usage == kMSBDCSHIDLeft || usage == kMSBDCSHIDRight || usage == kMSBDCSHIDUp)) return kMSBDCSMacSwitcher;
    return kMSBDCSOK;
}
// Two shortcuts are the same: the same key (its usage) and the same modifiers.
static inline bool MSBDCSSame(long usageA, unsigned long long flagsA, long usageB, unsigned long long flagsB) {
    return usageA == usageB && MSBDCSMods(flagsA) == MSBDCSMods(flagsB);
}

// ---- In the app with the keyboard (1.8.6, the KeyPilot author's report: with an app in front the shortcuts did nothing) ----
// SpringBoard gets no keys while an app has the keyboard, only the key commands backboardd agrees to route to it: chords with Command, Control or
// Globe whose key UIKit can name, so Option-only chords (Option-J) and F-keys never came. So, as KeyPilot does, the app with the keyboard matches
// the shortcuts itself: MacAppBridge's -[UIApplication handleKeyUIEvent:] hook (appbridge/AppBridge.x, already in every UIKit app), first in that
// hook, so a shortcut wins over the app's own shortcut and its typing, as a Mac's global shortcuts do. The app's sandbox can't read our preferences,
// so SpringBoard publishes the rules as Darwin notify states (KeyPilot's way): one per rule (MSBDCSPack), the count with a generation, and whether
// the apps take them at all (MSBDCSWantedNow, worked out in SpringBoard: the sandbox can't look for KeyPilot's files). A match posts the rule's own
// run name, SpringBoard runs it (MSBDCSRunOnceNow drops the same key come both ways), and the key-down, its repeats and its key-up are
// kept from the app as a pair (MSBDCSKeyAct, common/MenuKeys.h's held keys). Apps without our bridge (the recovery apps: loader/Loader.c) keep only
// SpringBoard's key commands.
#define kMSBDCSRuleStateFmt "com.besiktasliseba.customshortcuts.rule.%u"   // (rule n, 0..63: MSBDCSPack; 0 for none)
#define kMSBDCSRulesState   "com.besiktasliseba.customshortcuts.rules"     // (MSBDCSRulesNext: the count and a generation; posted once all are set)
#define kMSBDCSWantedState  "com.besiktasliseba.customshortcuts.wanted"    // (1: the apps take the shortcuts; 0 or never set: they don't)
#define kMSBDCSRunFmt       "com.besiktasliseba.customshortcuts.run.%u"    // (posted by the app: run rule n; a name per rule, so no state from the sandbox)
// A rule as one uint64: its HID usage (bits 0-15), its modifiers as MSBDCSMods keeps them (in their own bits, 17-23) and on (bit 32). 0: none.
#define kMSBDCSPackUsage 0xFFFFULL
#define kMSBDCSPackOn    (1ULL << 32)
static inline uint64_t MSBDCSPack(long usage, unsigned long long flags, bool on) {
    if (usage <= 0 || usage > (long)kMSBDCSPackUsage) return 0;
    return (uint64_t)usage | MSBDCSMods(flags) | (on ? kMSBDCSPackOn : 0);
}
static inline long MSBDCSPackedUsage(uint64_t p) { return (long)(p & kMSBDCSPackUsage); }
static inline unsigned long long MSBDCSPackedMods(uint64_t p) { return MSBDCSMods(p); }
// A rule that can match: on, a key, and no bit we never write (a state some other code set is not a rule).
static inline bool MSBDCSPackedOn(uint64_t p) {
    return (p & kMSBDCSPackOn) && MSBDCSPackedUsage(p) > 0 && !(p & ~(kMSBDCSPackUsage | (uint64_t)kMSBDModMask | kMSBDCSPackOn));
}
// The rules' state: the count (bits 0-7, at most kMSBDCSMaxRules) and a generation (bits 8-63, 1 or more once published, so 0 is never published).
// Each publish takes the next generation, so an app that read the rules before can tell they changed.
static inline unsigned MSBDCSRulesCount(uint64_t s) { unsigned c = (unsigned)(s & 0xFF); return c > kMSBDCSMaxRules ? kMSBDCSMaxRules : c; }
static inline uint64_t MSBDCSRulesGen(uint64_t s) { return s >> 8; }
static inline uint64_t MSBDCSRulesNext(uint64_t previous, unsigned count) {
    uint64_t g = MSBDCSRulesGen(previous) + 1;
    if (g >= (1ULL << 56)) g = 1;
    return (g << 8) | (count > kMSBDCSMaxRules ? kMSBDCSMaxRules : count);
}
// Whether the shortcuts are taken (SpringBoard's presses and key commands, and the apps through the wanted state): the switch on, KeyPilot not
// installed (it runs its own: both would run each key), a rule, and Settings not recording one (the keys go to the recording).
static inline bool MSBDCSWantedNow(bool switchOn, bool keyPilot, unsigned count, bool recording) { return switchOn && !keyPilot && count > 0 && !recording; }
// The apps' wanted state (kMSBDCSWantedState): the shortcuts taken (MSBDCSWantedNow) and SpringBoard's run gate for a run an app posts open (a
// hardware keyboard attached: statusbar/CustomShortcuts.h DMCSRunFromApp). SpringBoard publishes this one answer and its run gate asks the same
// one, so an app keeps a key from itself only when SpringBoard will run it (1.8.6 i05, iPad 2 and 17.5 with keys injected and no keyboard: the
// app matched Option-J and kept it, SpringBoard refused the run, the key was lost and nothing ran). With no keyboard every key goes to the app.
static inline bool MSBDCSAppsWanted(bool taken, bool keyboard) { return taken && keyboard; }
// The published rules are what SpringBoard means (1.8.6 i05, M1 and A12Z: the last rule turned off or deleted kept its keys from every app and
// nothing ran, until a respring; the check compared the slots below the new count and never the count, so a list one shorter, the others
// unchanged, was "the same"). Same: published before, the live rules' state the one SpringBoard wrote last (its generation), its count the count
// meant now, and each slot below that count the rule meant. slot(i, ctx): the live slot i, read only while all before it matched. A slot past
// the count is no rule to the apps (MSBDCSRulesCount); a publish clears those that were read before (MSBDCSSlotsToWrite).
static inline bool MSBDCSPublishedSame(bool published, uint64_t live, uint64_t written, unsigned count, const uint64_t *meant,
                                       uint64_t (*slot)(unsigned i, void *ctx), void *ctx) {
    if (!published || live != written || MSBDCSRulesCount(live) != count) return false;
    for (unsigned i = 0; i < count && i < kMSBDCSMaxRules; i++) if (slot(i, ctx) != meant[i]) return false;
    return true;
}
// The slots a publish writes: the ones meant now and every one an app may have read before, the count SpringBoard wrote last and the count
// published (after a respring SpringBoard wrote none yet), the ones past the new count set to 0.
static inline unsigned MSBDCSSlotsToWrite(unsigned count, unsigned lastCount, uint64_t live) {
    unsigned n = count, lc = MSBDCSRulesCount(live);
    if (lastCount > n) n = lastCount;
    if (lc > n) n = lc;
    return n > kMSBDCSMaxRules ? kMSBDCSMaxRules : n;
}
// A chord a shortcut can be: one with Control, Option, Command or Globe (MSBDCSCheck). Plain typing, Shift included, is never asked about.
static inline bool MSBDCSChord(unsigned long long flags) { return (MSBDCSMods(flags) & (kMSBDModControl | kMSBDModOption | kMSBDModCommand | kMSBDModGlobe)) != 0; }
// The rule a key-down is, from the published rules, or -1 (the first one, as SpringBoard's DMCSRuleFor: the key's usage and the modifiers by
// MSBDCSSame, so Caps Lock and the keypad bit don't count).
static inline int MSBDCSMatch(const uint64_t *rules, unsigned count, long usage, unsigned long long flags) {
    if (!rules || usage <= 0 || !MSBDCSChord(flags)) return -1;
    if (count > kMSBDCSMaxRules) count = kMSBDCSMaxRules;
    for (unsigned i = 0; i < count; i++)
        if (MSBDCSPackedOn(rules[i]) && MSBDCSSame(MSBDCSPackedUsage(rules[i]), MSBDCSPackedMods(rules[i]), usage, flags)) return (int)i;
    return -1;
}
// The keys the app's check has seen go down (usages 0-255; the keyboard page's keys are all below): held, a shortcut's (its repeats and key-up
// kept from the app with it); app, the app's (its repeats stay the app's, even if a modifier pressed meanwhile makes them look like a shortcut).
// at: when each last came; mods: the modifiers a shortcut's key went down with. A key whose key-up never came here (the keyboard went to another
// app before it, which a shortcut that opens an app or goes Home can do) is forgotten when this app loses the keyboard (MSBDCSKeyForget: the
// bridge's resign-active, scene-deactivate and key-window observers). As a second guard, a shortcut key's key-down is its repeat only while the
// shortcut's Control, Option, Command or Globe are still down, or within kMSBDCSRepeatMs of the last one (Option let go while the key repeats:
// still the shortcut's), and never more than kMSBDCSHeldLostMs after it. So a plain 'h' typed after Option-H, its key-up gone elsewhere, is the
// app's (review 1.8.6, L).
#define kMSBDCSHeldLostMs 2500.0
#define kMSBDCSRepeatMs 800.0   // (a held key's repeats come every ~0.1 s; the first after the delay before repeating)
typedef struct { uint64_t held[4]; uint64_t app[4]; double at[256]; unsigned long long mods[256]; } MSBDCSKeyHeld;
static inline void MSBDCSKeyForget(MSBDCSKeyHeld *h) { if (h) memset(h, 0, sizeof *h); }   // (the keyboard went elsewhere: no key is down here now)
static inline int MSBDCSKeyBit(const uint64_t set[4], long u) { return u >= 0 && u < 256 && ((set[u >> 6] >> (u & 63)) & 1); }
static inline void MSBDCSKeySetBit(uint64_t set[4], long u, int on) {
    if (u < 0 || u >= 256) return;
    uint64_t bit = (uint64_t)1 << (u & 63);
    if (on) set[u >> 6] |= bit; else set[u >> 6] &= ~bit;
}
enum { MSBDCSKeyPass = 0, MSBDCSKeyRun = 1, MSBDCSKeyTake = 2 };
// What the app does with a key event: pass it on (MSBDCSKeyPass), keep it from the app (MSBDCSKeyTake: a shortcut's repeat or key-up), or run rule
// *runRule and keep the key-down from the app (MSBDCSKeyRun). confirm is asked only for a key-down the published rules match (so typing pays
// nothing more): SpringBoard's word now (taken, not recording) and the rules read again if they changed since; it answers the rule to run, or -1.
static inline int MSBDCSKeyAct(MSBDCSKeyHeld *h, const uint64_t *rules, unsigned count, long usage, int isDown, unsigned long long flags, double nowMs,
                               int (*confirm)(long usage, unsigned long long flags, int rule), int *runRule) {
    if (runRule) *runRule = -1;
    if (!h || usage <= 0 || usage >= 256) return MSBDCSKeyPass;
    if (MSBDCSKeyBit(h->held, usage)) {
        if (!isDown) { MSBDCSKeySetBit(h->held, usage, 0); return MSBDCSKeyTake; }
        double gap = nowMs - h->at[usage];
        unsigned long long chord = h->mods[usage] & (kMSBDModControl | kMSBDModOption | kMSBDModCommand | kMSBDModGlobe);
        bool chordDown = (MSBDCSMods(flags) & chord) == chord;
        if (gap <= kMSBDCSHeldLostMs && (chordDown || gap <= kMSBDCSRepeatMs)) { h->at[usage] = nowMs; return MSBDCSKeyTake; }   // (a repeat)
        MSBDCSKeySetBit(h->held, usage, 0);   // (its key-up went elsewhere: a new press)
    }
    if (MSBDCSKeyBit(h->app, usage)) {
        if (!isDown) { MSBDCSKeySetBit(h->app, usage, 0); return MSBDCSKeyPass; }
        if (nowMs - h->at[usage] <= kMSBDCSHeldLostMs) { h->at[usage] = nowMs; return MSBDCSKeyPass; }
        MSBDCSKeySetBit(h->app, usage, 0);
    }
    if (!isDown) return MSBDCSKeyPass;   // (a key-up nobody saw go down: the app's, as before)
    int i = MSBDCSMatch(rules, count, usage, flags);
    if (i >= 0 && confirm) i = confirm(usage, flags, i);
    h->at[usage] = nowMs;
    if (i < 0 || i >= kMSBDCSMaxRules) { MSBDCSKeySetBit(h->app, usage, 1); return MSBDCSKeyPass; }
    MSBDCSKeySetBit(h->held, usage, 1);
    h->mods[usage] = MSBDCSMods(flags);
    if (runRule) *runRule = i;
    return MSBDCSKeyRun;
}
// SpringBoard's run gate (statusbar/CustomShortcuts.h DMCSRunOnce and DMCSRunFromApp). A key comes two ways: SpringBoard's own (its presses and
// its key commands, one way: a held key's repeats come too, every ~0.1 s, and a press can come as both) and an app's post (MSBDCSKeyAct: once per
// real press, the repeats kept in the app). The app keeps every key it posts, so SpringBoard drops a post only when it is a key already run
// (review 1.8.6, L: a second Option-J 0.3 s after the first, or Option-1 then Option-2 0.2 s apart, were kept by the app and never run).
//  - Once per key (MSBDCSRunOnceNow): the same rule come the other way within kMSBDCSSameKeyMs of an arrival not yet paired is that key again
//    (the two arrive together: a chord with Command, Control or Globe can come as a key command and as the app's post); SpringBoard's own way,
//    the same rule within kMSBDCSSameKeyMs of its last arrival, is a repeat (each moves the time on, so a held URL shortcut opens one tab; review
//    1.8.5-k M2, as on the Home Screen). An app's post is never its own repeat: a second press of the same shortcut runs again at any pace.
//  - The posts' rate (MSBDCSFromAppTake): any process can post the run names (a loop posting run.0 and run.1 in turn ran the shortcuts hundreds of
//    times a second on SpringBoard's main thread; review 1.8.6, L), so they run from a bucket of kMSBDCSFromAppBurst, one back every
//    kMSBDCSFromAppEveryMs: presses by hand, kMSBDCSFromAppEveryMs or more apart, always run, a few quicker ones too, and a flood runs at most
//    kMSBDCSFromAppBurst at once, then one each kMSBDCSFromAppEveryMs. A post the bucket refuses takes nothing from it.
enum { kMSBDCSWaySpringBoard = 0, kMSBDCSWayApp = 1 };
#define kMSBDCSSameKeyMs 500.0
#define kMSBDCSFromAppBurst 4.0
#define kMSBDCSFromAppEveryMs 150.0
typedef struct { bool seen, paired; unsigned rule; double atMs; } MSBDCSArrival;   // (paired: the other way's arrival of the same key came)
typedef struct { MSBDCSArrival way[2]; } MSBDCSRunOnceState;                       // (all 0: nothing came yet)
// Whether rule's arrival by way (kMSBDCSWaySpringBoard, kMSBDCSWayApp) at nowMs runs: false for a key already run.
static inline bool MSBDCSRunOnceNow(MSBDCSRunOnceState *o, unsigned rule, int way, double nowMs) {
    if (!o || (way != kMSBDCSWaySpringBoard && way != kMSBDCSWayApp)) return false;
    MSBDCSArrival *mine = &o->way[way], *other = &o->way[1 - way];
    if (other->seen && !other->paired && other->rule == rule && nowMs - other->atMs < kMSBDCSSameKeyMs) {   // (the same key, the other way)
        other->paired = true;
        *mine = (MSBDCSArrival){ true, true, rule, nowMs };
        return false;
    }
    if (way == kMSBDCSWaySpringBoard && mine->seen && mine->rule == rule && nowMs - mine->atMs < kMSBDCSSameKeyMs) {   // (a repeat)
        mine->atMs = nowMs;
        return false;
    }
    *mine = (MSBDCSArrival){ true, false, rule, nowMs };
    return true;
}
typedef struct { bool started; double tokens, atMs; } MSBDCSFromAppBucket;   // (all 0: full at the first post)
// Whether a run an app posted at nowMs may run now (one taken from the bucket if so).
static inline bool MSBDCSFromAppTake(MSBDCSFromAppBucket *b, double nowMs) {
    if (!b) return false;
    if (!b->started) { b->started = true; b->tokens = kMSBDCSFromAppBurst; b->atMs = nowMs; }
    double t = b->tokens + (nowMs > b->atMs ? (nowMs - b->atMs) / kMSBDCSFromAppEveryMs : 0);
    if (t > kMSBDCSFromAppBurst) t = kMSBDCSFromAppBurst;
    b->tokens = t; b->atMs = nowMs;
    if (t < 1.0) return false;
    b->tokens = t - 1.0;
    return true;
}

// The actions (KeyPilot's spelling). shell: and sh: are refused (they would run commands from inside SpringBoard); a bare word (KeyPilot reads it
// as an app) is not ours either.
enum { kMSBDCSActNone = 0, kMSBDCSActApp, kMSBDCSActURL, kMSBDCSActWindow, kMSBDCSActHome, kMSBDCSActShell };
static inline bool MSBDCSHasPrefix(const char *s, const char *p) { return s && strncasecmp(s, p, strlen(p)) == 0; }
static inline const char *MSBDCSValue(const char *s, const char *p) {   // (the part after the prefix, spaces before it skipped)
    const char *v = s + strlen(p);
    while (*v == ' ' || *v == '\t') v++;
    return v;
}
// The window layouts, by KeyPilot's names and aliases (KPWindowActions.m KPWindowActionName), to the window API's (statusbar/WindowAPIRule.h:
// "left", "topleft"...). NULL: none.
static inline const char *MSBDCSLayoutName(const char *in) {
    static const char *const map[][2] = {
        { "left-half", "left" }, { "right-half", "right" }, { "top-half", "top" }, { "bottom-half", "bottom" },
        { "top-left", "topleft" }, { "top-right", "topright" }, { "bottom-left", "bottomleft" }, { "bottom-right", "bottomright" },
        { "fill", "fill" }, { "center", "center" }, { "small", "small" }, { "large", "large" },
        // KeyPilot's aliases
        { "left", "left" }, { "right", "right" }, { "top", "top" }, { "bottom", "bottom" }, { "maximize", "fill" }, { "fill-screen", "fill" },
        { "topleft", "topleft" }, { "topright", "topright" }, { "bottomleft", "bottomleft" }, { "bottomright", "bottomright" },
    };
    if (!in) return NULL;
    char n[32]; size_t j = 0;
    while (*in == ' ' || *in == '\t') in++;
    for (; *in && j < sizeof(n) - 1; in++) {   // (lower case; '_' and ' ' as '-', as KeyPilot reads them)
        char c = *in;
        if (c >= 'A' && c <= 'Z') c = (char)(c - 'A' + 'a');
        if (c == '_' || c == ' ') c = '-';
        n[j++] = c;
    }
    while (j && n[j - 1] == '-') j--;   // (trailing spaces)
    n[j] = 0;
    for (size_t i = 0; i < sizeof(map) / sizeof(map[0]); i++) if (!strcmp(n, map[i][0])) return map[i][1];
    return NULL;
}
static inline int MSBDCSActionKind(const char *action) {
    if (!action) return kMSBDCSActNone;
    while (*action == ' ' || *action == '\t') action++;
    if (!strcasecmp(action, "system:home")) return kMSBDCSActHome;
    if (MSBDCSHasPrefix(action, "window:")) return MSBDCSLayoutName(MSBDCSValue(action, "window:")) ? kMSBDCSActWindow : kMSBDCSActNone;
    if (MSBDCSHasPrefix(action, "app:")) return *MSBDCSValue(action, "app:") ? kMSBDCSActApp : kMSBDCSActNone;
    if (MSBDCSHasPrefix(action, "open:")) return *MSBDCSValue(action, "open:") ? kMSBDCSActApp : kMSBDCSActNone;   // (KeyPilot's other spelling)
    if (MSBDCSHasPrefix(action, "url:")) return strchr(MSBDCSValue(action, "url:"), ':') ? kMSBDCSActURL : kMSBDCSActNone;   // (a scheme)
    if (MSBDCSHasPrefix(action, "shell:") || MSBDCSHasPrefix(action, "sh:")) return kMSBDCSActShell;
    return kMSBDCSActNone;
}
// The value an action acts on: the app's bundle ID, the URL, the layout; NULL for Home and none.
static inline const char *MSBDCSActionValue(const char *action) {
    if (!action) return NULL;
    while (*action == ' ' || *action == '\t') action++;
    switch (MSBDCSActionKind(action)) {
        case kMSBDCSActApp: return MSBDCSHasPrefix(action, "app:") ? MSBDCSValue(action, "app:") : MSBDCSValue(action, "open:");
        case kMSBDCSActURL: return MSBDCSValue(action, "url:");
        case kMSBDCSActWindow: return MSBDCSLayoutName(MSBDCSValue(action, "window:"));
        default: return NULL;
    }
}

// The layouts offered when a shortcut is made (the Window menu's order: WindowAPIRule.h kMSBDWinAPILayouts) and their names in that menu.
#define kMSBDCSLayoutCount 12
static const char *const kMSBDCSLayouts[kMSBDCSLayoutCount] = {
    "fill", "center", "left", "right", "top", "bottom", "topleft", "topright", "bottomleft", "bottomright", "small", "large" };
static const char *const kMSBDCSLayoutTitles[kMSBDCSLayoutCount] = {
    "Fill Screen", "Center", "Left Half", "Right Half", "Top Half", "Bottom Half", "Top Left", "Top Right", "Bottom Left", "Bottom Right",
    "Small", "Large" };
static inline const char *MSBDCSLayoutTitle(const char *layout) {
    for (int i = 0; i < kMSBDCSLayoutCount; i++) if (layout && !strcmp(layout, kMSBDCSLayouts[i])) return kMSBDCSLayoutTitles[i];
    return NULL;
}

#ifdef __OBJC__
#import <Foundation/Foundation.h>
// A rule as stored: {key, keyCode, modifiers, action, enabled} (KeyPilot's keys). Valid: a key code, an action we run, enabled.
static inline BOOL MSBDCSRuleUsable(NSDictionary *r) {
    if (![r isKindOfClass:[NSDictionary class]]) return NO;
    id code = r[@"keyCode"], mods = r[@"modifiers"], act = r[@"action"], on = r[@"enabled"];
    if (![code isKindOfClass:[NSNumber class]] || [code longValue] <= 0 || ![mods isKindOfClass:[NSNumber class]] || ![act isKindOfClass:[NSString class]]) return NO;
    if (on && ![on boolValue]) return NO;
    int k = MSBDCSActionKind([act UTF8String]);
    if (!(k == kMSBDCSActApp || k == kMSBDCSActURL || k == kMSBDCSActWindow || k == kMSBDCSActHome)) return NO;
    // (the record-time rules too: a rule written some other way with no Command, Option, Control or Globe, Escape, or a Window Tiling or Mac
    //  Switcher key would take that key from typing everywhere; review 1.8.5-k L1)
    id key = r[@"key"];
    return MSBDCSCheck([code longValue], [key isKindOfClass:[NSString class]] ? [key UTF8String] : "", [mods unsignedLongLongValue]) == kMSBDCSOK;
}
// A rule as the apps get it (MSBDCSPack): 0 for one that is not a dictionary with a key code and modifiers.
static inline uint64_t MSBDCSPackRule(NSDictionary *r) {
    if (![r isKindOfClass:[NSDictionary class]] || ![r[@"keyCode"] isKindOfClass:[NSNumber class]] || ![r[@"modifiers"] isKindOfClass:[NSNumber class]]) return 0;
    id on = r[@"enabled"];
    return MSBDCSPack([r[@"keyCode"] longValue], [r[@"modifiers"] unsignedLongLongValue], !on || [on boolValue]);
}
// The key's name, as KeyPilot shows it (KPShared.m KPKeyName): the arrows as arrows, the named keys by name, a character in capitals.
static inline NSString *MSBDCSKeyName(long usage, NSString *key) {
    switch (usage) {
        case kMSBDCSHIDUp: return @"↑";
        case kMSBDCSHIDDown: return @"↓";
        case kMSBDCSHIDLeft: return @"←";
        case kMSBDCSHIDRight: return @"→";
        case kMSBDCSHIDReturn: return @"Return";
        case kMSBDCSHIDTab: return @"Tab";
        case kMSBDCSHIDSpace: return @"Space";
        case kMSBDCSHIDDelete: return @"Delete";
        case kMSBDCSHIDEscape: return @"Esc";
        default: break;
    }
    if (key.length) return key.uppercaseString;
    if (usage >= kMSBDCSHIDA && usage <= kMSBDCSHIDZ) return [NSString stringWithFormat:@"%c", (char)('A' + usage - kMSBDCSHIDA)];
    if (usage >= kMSBDCSHID1 && usage < kMSBDCSHID0) return [NSString stringWithFormat:@"%c", (char)('1' + usage - kMSBDCSHID1)];
    if (usage == kMSBDCSHID0) return @"0";
    return [NSString stringWithFormat:@"Key %ld", usage];
}
// The shortcut as a Mac menu shows it: Globe, Control, Option, Shift, Command, then the key (KeyPilot's order, Globe added first as on a Mac).
static inline NSString *MSBDCSShortcutText(long usage, NSString *key, unsigned long long flags) {
    NSMutableString *s = [NSMutableString string];
    if (flags & kMSBDModGlobe) [s appendString:@"\U0001F310︎"];
    if (flags & kMSBDModControl) [s appendString:@"⌃"];
    if (flags & kMSBDModOption) [s appendString:@"⌥"];
    if (flags & kMSBDModShift) [s appendString:@"⇧"];
    if (flags & kMSBDModCommand) [s appendString:@"⌘"];
    [s appendString:MSBDCSKeyName(usage, key)];
    return s;
}
// KeyPilot's rules made ours (the import): each one with an action we run and a shortcut we accept, its window layout in our spelling, at most
// kMSBDCSMaxRules with ours; the others counted. KeyPilot's modifiers have no Globe (its mask drops it), so its shortcuts are taken as they are.
static inline NSArray<NSDictionary *> *MSBDCSImport(NSArray *theirs, NSArray<NSDictionary *> *ours, NSUInteger *skippedShell, NSUInteger *skippedOther) {
    NSMutableArray *out = [NSMutableArray arrayWithArray:ours ?: @[]];
    NSUInteger shell = 0, other = 0;
    for (NSDictionary *r in [theirs isKindOfClass:[NSArray class]] ? theirs : @[]) {
        if (![r isKindOfClass:[NSDictionary class]] || ![r[@"action"] isKindOfClass:[NSString class]]) { other++; continue; }
        NSString *act = [r[@"action"] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
        int kind = MSBDCSActionKind(act.UTF8String);
        if (kind == kMSBDCSActShell) { shell++; continue; }
        if (kind == kMSBDCSActWindow) act = [@"window:" stringByAppendingString:@(MSBDCSActionValue(act.UTF8String))];
        else if (kind == kMSBDCSActApp) act = [@"app:" stringByAppendingString:@(MSBDCSActionValue(act.UTF8String))];
        else if (kind == kMSBDCSActHome) act = @"system:home";
        else if (kind != kMSBDCSActURL) { other++; continue; }
        long code = [r[@"keyCode"] isKindOfClass:[NSNumber class]] ? [r[@"keyCode"] longValue] : 0;
        unsigned long long mods = [r[@"modifiers"] isKindOfClass:[NSNumber class]] ? MSBDCSMods([r[@"modifiers"] unsignedLongLongValue]) : 0;
        NSString *key = [r[@"key"] isKindOfClass:[NSString class]] ? r[@"key"] : @"";
        if (MSBDCSCheck(code, key.UTF8String, mods) != kMSBDCSOK || code <= 0) { other++; continue; }
        BOOL taken = NO;
        for (NSDictionary *o in out) {   // (our stored rules: any dictionary; only numbers compared, review 1.8.5-k L2)
            if (![o[@"keyCode"] isKindOfClass:[NSNumber class]] || ![o[@"modifiers"] isKindOfClass:[NSNumber class]]) continue;
            if (MSBDCSSame([o[@"keyCode"] longValue], [o[@"modifiers"] unsignedLongLongValue], code, mods)) { taken = YES; break; }
        }
        if (taken || out.count >= kMSBDCSMaxRules) { other++; continue; }
        [out addObject:@{ @"key": key, @"keyCode": @(code), @"modifiers": @(mods), @"action": act,
                          @"enabled": @([r[@"enabled"] isKindOfClass:[NSNumber class]] ? [r[@"enabled"] boolValue] : YES) }];
    }
    if (skippedShell) *skippedShell = shell;
    if (skippedOther) *skippedOther = other;
    return out;
}
#endif
#endif
