// Mac test of common/PointerAnim.h (1.5.1): Pointer Animations with the Mac pointer -- off once per Mac-pointer period with the user's value kept,
// never fought when the user turns them back on, given back only while still off as we left them; 1.7.0: off again when Apple's Reduce Motion
// switch turned them on with it, unless the user had turned them on.
#import <Foundation/Foundation.h>
#include "../common/PointerAnim.h"
static int fails = 0, passes = 0;
#define CHECK(cond, ...) do { if (cond) { passes++; } else { fails++; printf("FAIL: "); printf(__VA_ARGS__); printf("\n"); } } while (0)

// A little world: the stored state and Pointer Animations, stepped as SpringBoard does (at every start and every pointer-style change).
typedef struct { bool applied, savedPresent, saved, anim; int writes; } World;
static void Step(World *w, bool mac) {
    DMPtrAnimStep s = DMPtrAnimDecide(mac, w->applied, w->savedPresent, w->saved, w->anim);
    if (s.set == 1) { w->anim = false; w->writes++; }
    if (s.set == 2) { w->anim = true; w->writes++; }
    w->applied = s.applied; w->savedPresent = s.keepSaved; w->saved = s.saved;
}

// 1.7.0: after the switch-off of a period, Apple's Reduce Motion switch (it sets Pointer Animations to the opposite of Reduce Motion, iPadOS
// 15.6.1) and the user's own Pointer Animations switch, with StatusBar.x DMPointerAnimFollow's looks (one half a second after each Reduce Motion
// notice, noticed = YES, and the 2 s checks) -- the user's own choice stored as userOn.
typedef struct { bool rm, pa, userOn, lookRM, lookPA; int sets; } AXWorld;
static void Look(AXWorld *w, bool noticed) {
    DMPtrAnimLook l = DMPtrAnimAfterLook(w->lookRM, w->lookPA, w->rm, w->pa, noticed, w->userOn);
    w->userOn = l.userOn;
    if (l.set == 1) { w->pa = false; w->sets++; }
    w->lookRM = w->rm; w->lookPA = w->pa;
}
static void AppleRM(AXWorld *w, bool on) { w->rm = on; w->pa = !on; Look(w, true); Look(w, false); }   // (Apple's setter, then the notice's look and a 2 s check)
static void UserPA(AXWorld *w, bool on) { w->pa = on; Look(w, false); Look(w, false); }                  // (Accessibility > Pointer Control, then two 2 s checks)

// The bridge's tick (StatusBar.x DMPointerAnimTick, every 2 s and at each change): whether the Mac pointer counts, then the decision. style: Pointer
// Style Mac; state: MacPointer's published state (0 not said, 1 drawing, 2 standing down); off: switched off (the off marker) or being removed.
static void Tick(World *w, bool style, unsigned long long state, bool off) {
    Step(w, DMPtrAnimIsMacPointer(style, state, off));
}

int main(void) {
    @autoreleasepool {
        // a user with Pointer Animations on (Apple's default) and the Mac pointer (a new install, or an update): off once, the value kept
        World w = { false, false, false, true, 0 };
        Step(&w, true);
        CHECK(!w.anim && w.applied && w.savedPresent && w.saved && w.writes == 1, "Mac pointer: turned off once, the user's 'on' kept");
        for (int i = 0; i < 5; i++) Step(&w, true);
        CHECK(!w.anim && w.writes == 1, "every start after that: nothing more written");
        // the user turns them back on in Accessibility while the Mac pointer is on: left on, at every start
        w.anim = true;
        for (int i = 0; i < 5; i++) Step(&w, true);
        CHECK(w.anim && w.writes == 1, "turned back on by the user: never fought (writes %d)", w.writes);
        // the iPadOS pointer picked now: it is on already (the user's choice): nothing written, our record goes
        Step(&w, false);
        CHECK(w.anim && w.writes == 1 && !w.applied && !w.savedPresent, "iPadOS pointer after the user's own 'on': nothing written, record gone");
        // the Mac pointer again: a new period -- off once more
        Step(&w, true);
        CHECK(!w.anim && w.writes == 2 && w.applied, "Mac pointer picked again: off once more (a new period)");
        // the iPadOS pointer: given back on
        Step(&w, false);
        CHECK(w.anim && w.writes == 3 && !w.applied, "iPadOS pointer: given back on");
        for (int i = 0; i < 3; i++) Step(&w, false);
        CHECK(w.anim && w.writes == 3, "iPadOS pointer, more starts: nothing");

        // a user who had Pointer Animations off already: nothing written either way, it stays off
        World o = { false, false, false, false, 0 };
        Step(&o, true); Step(&o, true); Step(&o, false);
        CHECK(!o.anim && o.writes == 0 && !o.applied, "already off: never written, stays off after the give-back");
        // ... who turns them on while the Mac pointer is on: the give-back leaves that alone
        o = (World){ false, false, false, false, 0 };
        Step(&o, true); o.anim = true; Step(&o, false);
        CHECK(o.anim && o.writes == 0, "already off, turned on by the user meanwhile: left on");

        // switched off / removed (the same give-back): off as we left it -> back on; no record (iPadOS pointer all along) -> nothing
        World r = { false, false, false, true, 0 };
        Step(&r, true); Step(&r, false);
        CHECK(r.anim && r.writes == 2, "switched off or removed: given back on");
        World n = { false, false, false, true, 0 };
        Step(&n, false); Step(&n, false);
        CHECK(n.anim && n.writes == 0, "iPadOS pointer all along: never touched");
        // a record without the kept value (an older or damaged store): Apple's default (on) comes back
        World d = { true, false, false, false, 0 };
        Step(&d, false);
        CHECK(d.anim && d.writes == 1 && !d.applied, "record without a kept value: Apple's default, on");
        // ---- 1.5.1 logic test B1 / W4: what the pointer is, at every tick ----
        // the removal: the Mac pointer drawn, removing posted -> given back; then the 30 s refreshes (style Mac, MacPointer still drawing) never undo it
        World rm = { false, false, false, true, 0 };
        Tick(&rm, true, 1, false);
        CHECK(!rm.anim && rm.applied && rm.writes == 1, "Mac pointer drawn: off once");
        Tick(&rm, true, 1, true);
        CHECK(rm.anim && !rm.applied && rm.writes == 2, "removal: given back on at once");
        for (int i = 0; i < 40; i++) Tick(&rm, true, 1, true);   // (80 s of 2 s ticks, two 30 s refreshes among them)
        CHECK(rm.anim && rm.writes == 2, "removal, refreshes after it: never switched off again (B1; writes %d)", rm.writes);
        // switched off in Choicy (the off marker): the same; switched on again (the marker gone): a new period, off once more, the user's value kept
        World ch = { false, false, false, true, 0 };
        Tick(&ch, true, 1, false); Tick(&ch, true, 1, true);
        for (int i = 0; i < 40; i++) Tick(&ch, true, 1, true);
        CHECK(ch.anim && ch.writes == 2, "Choicy off: given back, and it stays given back (writes %d)", ch.writes);
        Tick(&ch, true, 1, false);
        CHECK(!ch.anim && ch.applied && ch.saved && ch.writes == 3, "switched on again: off once more, the user's 'on' kept");
        // the root helper's own give-back (a SpringBoard without our code): the same decision; the SpringBoard that still runs ours finds nothing left
        World hp = { false, false, false, true, 0 };
        Tick(&hp, true, 1, false);
        Step(&hp, false);   // (sshtoggled --ptranim-giveback, as mobile)
        Tick(&hp, true, 1, true);
        CHECK(hp.anim && !hp.applied && hp.writes == 2, "helper's give-back, then SpringBoard's tick while switched off: on, written once each way");
        // KT's rule (25 Oct): the Mac pointer SELECTED is enough -- no mouse or trackpad, MacPointer silent (state 0): off once
        World fr = { false, false, false, true, 0 };
        Tick(&fr, true, 0, false);
        CHECK(!fr.anim && fr.applied && fr.saved && fr.writes == 1, "Mac selected, mouse asleep, MacPointer silent: off once, the user's 'on' kept");
        for (int i = 0; i < 10; i++) Tick(&fr, true, 0, false);
        Tick(&fr, true, 1, false);   // (the mouse wakes: pointeruid starts, MacPointer draws)
        CHECK(!fr.anim && fr.writes == 1, "then MacPointer drawing: nothing more (the same period)");
        // ... turned back on by the user while Mac is selected and nothing is drawn: respected, at every tick and after a reboot (state 0 again)
        fr.anim = true;
        for (int i = 0; i < 10; i++) Tick(&fr, true, i % 2, false);
        CHECK(fr.anim && fr.writes == 1 && fr.applied, "turned back on by the user, Mac selected, mouse on or asleep: left on (writes %d)", fr.writes);
        // standing down for another pointer tweak: given back; back to drawing (or silent): a new period, off once more
        Tick(&fr, true, 2, false);
        CHECK(fr.anim && !fr.applied && fr.writes == 1, "MacPointer stands down: the record goes (they are on already: nothing written)");
        Tick(&fr, true, 0, false);
        CHECK(!fr.anim && fr.writes == 2, "Mac pointer ours again (MacPointer silent): off once more");
        Tick(&fr, true, 2, false);
        CHECK(fr.anim && fr.writes == 3, "stands down again: given back on");
        // the iPadOS pointer picked: given back whatever MacPointer said
        World ip = { false, false, false, true, 0 };
        Tick(&ip, true, 0, false); Tick(&ip, false, 0, false);
        CHECK(ip.anim && ip.writes == 2 && !ip.applied, "iPadOS pointer: given back whatever MacPointer said");
        // switched off or removed with MacPointer silent: given back too, and never applied again while it lasts
        World sl = { false, false, false, true, 0 };
        Tick(&sl, true, 0, false); Tick(&sl, true, 0, true);
        for (int i = 0; i < 40; i++) Tick(&sl, true, i % 3 == 0 ? 1 : 0, true);
        CHECK(sl.anim && sl.writes == 2, "switched off with MacPointer silent: given back, stays given back (writes %d)", sl.writes);
        // the decision table: the Mac pointer counts exactly when it is selected, not standing down, and we are neither off nor being removed
        int pbad = 0;
        for (int st = 0; st <= 1; st++) for (unsigned long long ms = 0; ms <= 3; ms++) for (int off = 0; off <= 1; off++)
            if (DMPtrAnimIsMacPointer(st, ms, off) != (st && ms != 2 && !off)) pbad++;
        CHECK(pbad == 0, "pointer table: %d wrong", pbad);
        // exhaustive: the Mac pointer never turns them ON; the give-back never turns them OFF; nothing written twice in a row
        int bad = 0, cases = 0;
        for (int m = 0; m <= 1; m++) for (int a = 0; a <= 1; a++) for (int sp = 0; sp <= 1; sp++) for (int sv = 0; sv <= 1; sv++) for (int c = 0; c <= 1; c++) {
            DMPtrAnimStep s = DMPtrAnimDecide(m, a, sp, sv, c);
            bool wrong = (m && s.set == 2) || (!m && s.set == 1) || (s.set == 1 && !c) || (s.set == 2 && c) || (m && a && s.set != 0);
            DMPtrAnimStep again = DMPtrAnimDecide(m, s.applied, s.keepSaved, s.saved, s.set == 1 ? false : s.set == 2 ? true : c);
            if (again.set != 0) wrong = true;
            if (wrong) bad++;
            cases++;
        }
        CHECK(bad == 0, "exhaustive: %d of %d cases wrong", bad, cases);

        // ---- 1.7.0: Apple's Reduce Motion switch turns Pointer Animations on with it (KT: off again with the Mac pointer, never fight the user) ----
        AXWorld ax = { false, false, false, false, false, 0 };   // (KT's M1: the switch-off applied, Reduce Motion off, Pointer Animations off)
        AppleRM(&ax, true);
        CHECK(!ax.pa && ax.sets == 0, "Reduce Motion on: Apple turns them off, nothing of ours");
        AppleRM(&ax, false);
        CHECK(!ax.pa && ax.sets == 1 && !ax.userOn, "Reduce Motion off: Apple's 'on' taken back (off again, once)");
        for (int i = 0; i < 5; i++) Look(&ax, false);
        CHECK(!ax.pa && ax.sets == 1, "then quiet: nothing more");
        AppleRM(&ax, true); AppleRM(&ax, false); AppleRM(&ax, true); AppleRM(&ax, false);
        CHECK(!ax.pa && ax.sets == 3, "every Reduce Motion on / off: off again each time (sets %d)", ax.sets);
        // the user turns them on themselves: theirs, through Reduce Motion on and off too (as iPadOS leaves them without us)
        UserPA(&ax, true);
        CHECK(ax.pa && ax.userOn && ax.sets == 3, "turned on by the user: left on, recorded as theirs");
        AppleRM(&ax, true);
        CHECK(!ax.pa && ax.userOn, "then Reduce Motion on: Apple turns them off, the user's choice still recorded");
        AppleRM(&ax, false);
        CHECK(ax.pa && ax.sets == 3, "then Reduce Motion off: Apple's 'on' is the user's choice: left on");
        // ... and off again by the user: theirs; the next Reduce Motion off: off again
        UserPA(&ax, false);
        CHECK(!ax.pa && !ax.userOn && ax.sets == 3, "turned off by the user: theirs, nothing written");
        AppleRM(&ax, true); AppleRM(&ax, false);
        CHECK(!ax.pa && ax.sets == 4, "Reduce Motion on / off after that: off again");
        // turned on by the user while Reduce Motion is on: theirs; Reduce Motion off leaves them on
        AppleRM(&ax, true); UserPA(&ax, true);
        CHECK(ax.pa && ax.userOn, "turned on while Reduce Motion is on: theirs");
        AppleRM(&ax, false);
        CHECK(ax.pa && ax.sets == 4, "Reduce Motion off then: left on");
        UserPA(&ax, false);
        // Reduce Motion on and off between two 2 s checks: the notice's look tells it is Apple's
        ax.rm = true; ax.pa = false; ax.rm = false; ax.pa = true; Look(&ax, true);
        CHECK(!ax.pa && ax.sets == 5, "Reduce Motion on and off between two looks, the notice seen: off again");
        // with Reduce Motion changed since the last look (no notice seen, e.g. its look still to come): still Apple's
        ax.rm = true; ax.pa = false; Look(&ax, false); ax.rm = false; ax.pa = true; Look(&ax, false);
        CHECK(!ax.pa && ax.sets == 6, "Reduce Motion off seen by a 2 s check: off again");
        // Pointer Animations turned on by the user right as Reduce Motion goes ON (not Apple's: Apple turns them off then)
        ax.rm = true; ax.pa = true; Look(&ax, true);
        CHECK(ax.pa && ax.userOn && ax.sets == 6, "on while Reduce Motion goes on: the user's, left on");
        // exhaustive: never turned ON by us; off only when they are on now, Apple's doing and not the user's; a user's change never written; a
        // second look with nothing changed does nothing
        int lbad = 0, lcases = 0;
        for (int rb = 0; rb <= 1; rb++) for (int pb = 0; pb <= 1; pb++) for (int rn = 0; rn <= 1; rn++) for (int pn = 0; pn <= 1; pn++)
        for (int nt = 0; nt <= 1; nt++) for (int uo = 0; uo <= 1; uo++) {
            DMPtrAnimLook l = DMPtrAnimAfterLook(rb, pb, rn, pn, nt, uo);
            bool apples = pn != pb && (rn != rb || nt) && pn == !rn;
            bool wrong = (l.set != 0 && l.set != 1) || (l.set == 1 && !(pn && apples && !uo)) || (pn && apples && !uo && l.set != 1)
                      || (l.by == 2 && (l.set || l.userOn != pn)) || (pn == pb && (l.set || l.by || l.userOn != uo));
            DMPtrAnimLook again = DMPtrAnimAfterLook(rn, l.set == 1 ? false : pn, rn, l.set == 1 ? false : pn, false, l.userOn);
            if (again.set || again.by || again.userOn != l.userOn) wrong = true;
            if (wrong) lbad++;
            lcases++;
        }
        CHECK(lbad == 0, "Reduce Motion looks, exhaustive: %d of %d cases wrong", lbad, lcases);
    }
    printf("test-pointeranim: %d passed, %d failed\n", passes, fails);
    return fails ? 1 : 0;
}
