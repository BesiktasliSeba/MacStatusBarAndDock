// test-airpodsmenu.c -- the AirPods menu's rules (common/AirPodsMenu.h, MacStatusBar&Dock 1.8.8.1), plain C: the button's place beside the
// battery's, which battery records are which headphones', the cells, the levels, the modes, the route device, every menu kind's rows, the
// signature, the switch, the glyphs and what VoiceOver reads; since 1.8.8.1.1 when iPadOS's item is the headphones' (the glyph alone too) and
// which Bluetooth devices the menu lists. Built by tools/test-airpodsmenu.sh with -Wall -Wextra -Werror.
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <math.h>
#include "../common/AirPodsMenu.h"
#include "../common/BatteryMenu.h"

static int fails = 0, checks = 0;
static void check(int ok, const char *what) { checks++; if (!ok) fails++; printf("%s  %s\n", ok ? "PASS" : "FAIL", what); }

// ---- the button's place ----
static const MSBDAPSide kNone = { 0, 0, 0 };
static MSBDAPSide side(double a, double b) { MSBDAPSide s = { 1, a, b }; return s; }
static void spans(void) {
    int bad = 0, cases = 0;
    const double gaps[] = { 0, 3, 8, 20 }, ks[] = { 1.0, 1.25 };
    for (int gi = 0; gi < 4; gi++) for (int ki = 0; ki < 2; ki++) for (int dir = 0; dir < 2; dir++) for (int battOn = 0; battOn < 2; battOn++) for (int other = 0; other < 2; other++) {
        double k = ks[ki], g = gaps[gi] * k, pad = 4.0 * k;
        double left = 60.0, floor = left - 2.0 * k;
        // (dir 0: the battery after the item -- its percentage, then its glyph, as on every iPad; dir 1: before it, a right-to-left bar read the other way)
        double lead = dir ? 160.0 : 100.0, trail = lead + 30.0 * k;
        double bl = dir ? lead - g - 40.0 * k : trail + g, bt = bl + 40.0 * k;
        double ba = 0, bb = 0;
        int battBtn = battOn && MSBDBattButtonSpan(bl, bt, pad, floor, &ba, &bb);
        MSBDAPSide batt = battBtn ? side(ba, bb) : kNone;
        MSBDAPSide prev = dir ? side(bl, bt) : (other ? side(lead - g - 20.0 * k, lead - g) : kNone);
        MSBDAPSide next = dir ? (other ? side(trail + g, trail + g + 20.0 * k) : kNone) : side(bl, bt);
        double a = 0, b = 0;
        int ok = MSBDAirPodsButtonSpan(lead, trail, pad, floor, prev, next, batt, &a, &b);
        cases++;
        // (the rule exactly: the pad, cut at a gap's middle, at the battery's button, at the floor -- and the properties it gives)
        double wa = lead - pad, wb = trail + pad;
        if (prev.has && wa < (prev.trail + lead) / 2.0) wa = (prev.trail + lead) / 2.0;
        if (next.has && wb > (trail + next.lead) / 2.0) wb = (trail + next.lead) / 2.0;
        if (battBtn && !dir && wb > ba) wb = ba;
        if (battBtn && dir && wa < bb) wa = bb;
        if (wa < floor) wa = floor;
        int good = ok && fabs(a - wa) < 1e-9 && fabs(b - wb) < 1e-9 && a < b && a >= floor - 1e-9;
        if (prev.has) good = good && a >= (prev.trail + lead) / 2.0 - 1e-9;
        if (next.has) good = good && b <= (trail + next.lead) / 2.0 + 1e-9;
        if (battBtn) good = good && (b <= ba + 1e-9 || a >= bb - 1e-9);   // (never over the battery's button)
        if (g >= 8.0 * k - 1e-9) good = good && a <= lead + 1e-9 && b >= trail - 1e-9;   // (a gap of 8 pt x k or more: the whole item is the AirPods button's)
        if (!good) { bad++; printf("   span case gap %.2f k %.2f dir %d batt %d other %d: %d [%.2f, %.2f] (item %.2f..%.2f, battery button %d %.2f..%.2f)\n", g, k, dir, battOn, other, ok, a, b, lead, trail, battBtn, ba, bb); }
    }
    char what[300];
    snprintf(what, sizeof what, "span: gaps 0, 3, 8, 20 pt x k (1, 1.25), both directions, a neighbour or none, Battery Menu on and off (%d cases): never before left - 2k, never past a gap's middle, never over the battery's button (it stops where that starts), the whole item from a gap of 8 pt x k", cases);
    check(!bad, what);
    double a = 0, b = 0;
    check(!MSBDAirPodsButtonSpan(10, 5, 4, 0, kNone, kNone, kNone, &a, &b), "span: no views (lead after trail): no area");
    check(!MSBDAirPodsButtonSpan(100, 110, 4, 200, kNone, kNone, kNone, &a, &b), "span: the item entirely before the floor (our Wi-Fi icon's area): no area");
    check(MSBDAirPodsButtonSpan(100, 130, 4, 98, kNone, kNone, kNone, &a, &b) && a == 98 && b == 134, "span: the floor cuts the leading pad only (98..134)");
    check(MSBDAirPodsButtonSpan(100, 130, 4, 0, kNone, side(131, 160), side(127, 175), &a, &b) && a == 96 && b == 127, "span: a gap of 1 pt with the battery's button reaching back 4 pt: ends where the battery's button starts (127)");
    check(MSBDAirPodsButtonSpan(100, 130, 4, 0, kNone, side(150, 170), kNone, &a, &b) && b == 134, "span: a 20 pt gap with Battery Menu off: the full 4 pt pad");
    check(MSBDAirPodsButtonSpan(100, 130, 4, 0, kNone, side(132, 170), kNone, &a, &b) && b == 131, "span: a 2 pt gap: the middle of the gap (131)");
}

// ---- the state ----
static MSBDAPHeadset hs(const char *name, const char *shown, const char *addr, long long pid, int level) {
    MSBDAPHeadset h; memset(&h, 0, sizeof h);
    snprintf(h.name, sizeof h.name, "%s", name); snprintf(h.shown, sizeof h.shown, "%s", shown ? shown : name); snprintf(h.address, sizeof h.address, "%s", addr);
    h.productId = pid; h.level = level; h.connected = 1;
    return h;
}
static MSBDAPPart pt(unsigned long long parts, int pct, int chg, const char *group, const char *match, long long pid) {
    MSBDAPPart p; memset(&p, 0, sizeof p);
    p.parts = parts; p.percent = pct; p.charging = chg; p.productId = pid;
    snprintf(p.groupName, sizeof p.groupName, "%s", group); snprintf(p.matchId, sizeof p.matchId, "%s", match);
    return p;
}
static MSBDAPRouteDev rd(unsigned type, const char *uid, unsigned modes, int current) {
    MSBDAPRouteDev r; memset(&r, 0, sizeof r);
    r.type = type; snprintf(r.uid, sizeof r.uid, "%s", uid); r.modes = modes; r.current = current;
    return r;
}
static MSBDAPState base(void) { MSBDAPState s; memset(&s, 0, sizeof s); s.headsetPart = s.partsPart = s.noisePart = 1; return s; }
#define M3 ((1u << kMSBDAPModeOff) | (1u << kMSBDAPModeTransparency) | (1u << kMSBDAPModeNoiseCancellation))
#define M4 (M3 | (1u << kMSBDAPModeAdaptive))
#define PRO "My AirPods Pro"
#define PROADDR "AA:BB:CC:DD:EE:01"
static void addPro(MSBDAPState *s) {   // (podfake_pro: merged 75, Case 40 charging; Off / Transparency / Noise Cancellation, current Noise Cancellation)
    s->headsets[s->nheadsets++] = hs(PRO, NULL, PROADDR, 0x200e, 75);
    s->parts[s->nparts++] = pt(3, 75, 0, PRO, "G1", 0x200e);
    s->parts[s->nparts++] = pt(4, 40, 1, "My AirPods Pro Case", "G1", 0x200e);
    s->route[s->nroute++] = rd(2, "aa:bb:cc:dd:ee:01-tacl", M3, kMSBDAPModeNoiseCancellation);
}
static void addOther(MSBDAPState *s) {   // (podfake_other: non-Apple, no BatteryCenter record, level 55)
    s->headsets[s->nheadsets++] = hs("Studio Headset", NULL, "11:22:33:44:55:66", 0, 55);
}

// ---- rows as text ----
static void render(const MSBDAPState *s, char *out, size_t n) {
    MSBDAPBlock b[MSBD_AP_MAX_HEADSETS]; MSBDAPRow r[MSBD_AP_MAX_ROWS];
    int nb = MSBDAirPodsBlocks(s, b, MSBD_AP_MAX_HEADSETS), nr = MSBDAirPodsMenuRows(s, b, nb, r, MSBD_AP_MAX_ROWS);
    out[0] = 0;
    for (int i = 0; i < nr; i++) {
        char one[300] = "";
        switch (r[i].kind) {
            case kMSBDAPRowHeading: snprintf(one, sizeof one, "H %s%s%s", r[i].text, r[i].value[0] ? " = " : "", r[i].value); break;
            case kMSBDAPRowStrip: {
                snprintf(one, sizeof one, "S");
                for (int c = 0; c < r[i].ncells; c++) {
                    const char *word; char pc[8], cell[40];
                    MSBDAirPodsGlyphs(r[i].cells[c].kind, &word); MSBDAirPodsPercentText(r[i].cells[c].percent, pc, sizeof pc);
                    snprintf(cell, sizeof cell, " [%s %s%s]", word, pc, r[i].cells[c].charging ? " +" : "");
                    strncat(one, cell, sizeof one - strlen(one) - 1);
                }
                break;
            }
            case kMSBDAPRowSection: snprintf(one, sizeof one, "# %s", r[i].text); break;
            case kMSBDAPRowMode: snprintf(one, sizeof one, "M%s %s", r[i].checked ? "*" : "", r[i].text); break;
            case kMSBDAPRowInfo: snprintf(one, sizeof one, "I %s", r[i].text); break;
            case kMSBDAPRowConnect: case kMSBDAPRowDisconnect: case kMSBDAPRowSettings: snprintf(one, sizeof one, "A %s", r[i].text); break;
            case kMSBDAPRowSeparator: snprintf(one, sizeof one, "--"); break;
            default: snprintf(one, sizeof one, "?%d", r[i].kind);
        }
        if (i) strncat(out, " | ", n - strlen(out) - 1);
        strncat(out, one, n - strlen(out) - 1);
    }
}
static void rows(const char *what, const MSBDAPState *s, const char *want) {
    char got[4096], line[4600];
    render(s, got, sizeof got);
    int ok = !strcmp(got, want);
    snprintf(line, sizeof line, "rows, %s: %s%s%s", what, got, ok ? "" : "\n        wanted: ", ok ? "" : want);
    check(ok, line);
}
#define SET "A Bluetooth Settings\xe2\x80\xa6"
static void kinds(void) {
    MSBDAPState s = base(); addPro(&s);
    rows("pro (merged 75, Case 40 charging, three modes, Noise Cancellation)", &s,
         "H My AirPods Pro | S [L R 75%] [Case 40% +] | -- | # Noise Control | M Off | M Transparency | M* Noise Cancellation | -- | A Disconnect | -- | " SET);
    MSBDAPState p2 = base();   // (podfake_pro2: Left 80, Right 62 charging -- BatteryCenter keeps them apart --, Case 15; Adaptive, current)
    p2.headsets[p2.nheadsets++] = hs("My AirPods Pro", NULL, PROADDR, 0x2014, 62);
    p2.parts[p2.nparts++] = pt(1, 80, 0, PRO, "G2", 0x2014); p2.parts[p2.nparts++] = pt(2, 62, 1, PRO, "G2", 0x2014);
    p2.parts[p2.nparts++] = pt(4, 15, 0, "Charging Case", "G2", 0x2014);
    p2.route[p2.nroute++] = rd(2, "AA:BB:CC:DD:EE:01", M4, kMSBDAPModeAdaptive);
    rows("pro2 (split: Left 80, Right 62 charging, Case 15; four modes, Adaptive)", &p2,
         "H My AirPods Pro | S [L 80%] [R 62% +] [Case 15%] | -- | # Noise Control | M Off | M Transparency | M* Adaptive | M Noise Cancellation | -- | A Disconnect | -- | " SET);
    MSBDAPState ap2 = base();   // (podfake_ap2: merged 90, Case 55, no modes)
    ap2.headsets[ap2.nheadsets++] = hs("AirPods", NULL, "AA:BB:CC:DD:EE:02", 0x200f, 90);
    ap2.parts[ap2.nparts++] = pt(3, 90, 0, "AirPods", "G3", 0x200f); ap2.parts[ap2.nparts++] = pt(4, 55, 0, "AirPods Case", "G3", 0x200f);
    ap2.route[ap2.nroute++] = rd(2, "AA:BB:CC:DD:EE:02-tacl", 0, -1);
    rows("ap2 (merged 90, Case 55, no modes: no Noise Control)", &ap2, "H AirPods | S [L R 90%] [Case 55%] | -- | A Disconnect | -- | " SET);
    MSBDAPState co = base();   // (podfake_caseonly: the Case alone, the heading's level from Bluetooth)
    co.headsets[co.nheadsets++] = hs("AirPods", NULL, "AA:BB:CC:DD:EE:02", 0x200f, 70);
    co.parts[co.nparts++] = pt(4, 40, 0, "AirPods Case", "G3", 0x200f);
    rows("caseonly (the Case alone: the heading keeps Bluetooth's level)", &co, "H AirPods = 70% | S [Case 40%] | -- | A Disconnect | -- | " SET);
    MSBDAPState mx = base();   // (podfake_max: one battery, parts 0 at 60; three modes)
    mx.headsets[mx.nheadsets++] = hs("My AirPods Max", NULL, "AA:BB:CC:DD:EE:03", 0x200a, 58);
    mx.parts[mx.nparts++] = pt(0, 60, 0, "My AirPods Max", "G4", 0x200a);
    mx.route[mx.nroute++] = rd(2, "AA:BB:CC:DD:EE:03-tacl", M3, kMSBDAPModeOff);
    rows("max (one battery: its level at the heading's right, no strip)", &mx,
         "H My AirPods Max = 60% | -- | # Noise Control | M* Off | M Transparency | M Noise Cancellation | -- | A Disconnect | -- | " SET);
    MSBDAPState ot = base(); addOther(&ot);
    rows("other (non-Apple, no record: the heading with Bluetooth's level, Disconnect)", &ot, "H Studio Headset = 55% | -- | A Disconnect | -- | " SET);
    MSBDAPState un = base(); un.headsets[un.nheadsets++] = hs("Headset", NULL, "11:22:33:44:55:77", 0, -1);
    rows("unknown (level -1, no records: --)", &un, "H Headset = -- | -- | A Disconnect | -- | " SET);
    MSBDAPState two = base(); addPro(&two); addOther(&two);
    rows("two (pro and other: a block each, Noise Control under the output only, Bluetooth Settings once)", &two,
         "H My AirPods Pro | S [L R 75%] [Case 40% +] | -- | # Noise Control | M Off | M Transparency | M* Noise Cancellation | -- | A Disconnect | -- | "
         "H Studio Headset = 55% | -- | A Disconnect | -- | " SET);
    MSBDAPState dr = base(); addPro(&dr); dr.headsets[0].connected = 0;
    rows("they drop with the menu open (Not Connected and Connect, no stale strip or modes)", &dr, "H My AirPods Pro | I Not Connected | -- | A Connect | -- | " SET);
    MSBDAPState er = base(); addPro(&er); er.noiseError = 1;
    rows("a mode change failed (the line under the modes, the real tick)", &er,
         "H My AirPods Pro | S [L R 75%] [Case 40% +] | -- | # Noise Control | M Off | M Transparency | M* Noise Cancellation | I Couldn't Change Noise Control | -- | A Disconnect | -- | " SET);
    MSBDAPState pe = base(); addPro(&pe); pe.route[0].current = kMSBDAPModeTransparency;
    rows("a tap on Transparency, pending (the tick moved at once)", &pe,
         "H My AirPods Pro | S [L R 75%] [Case 40% +] | -- | # Noise Control | M Off | M* Transparency | M Noise Cancellation | -- | A Disconnect | -- | " SET);
    MSBDAPState nt = base(); addPro(&nt); nt.route[0].current = -1;
    rows("a current mode that is not offered (no tick)", &nt,
         "H My AirPods Pro | S [L R 75%] [Case 40% +] | -- | # Noise Control | M Off | M Transparency | M Noise Cancellation | -- | A Disconnect | -- | " SET);
    MSBDAPState hp = base(); addPro(&hp); hp.headsetPart = 0;
    rows("the Bluetooth part off (heading Headphones, the one group's strip, the one Bluetooth output's modes, no Disconnect)", &hp,
         "H Headphones | S [L R 75%] [Case 40% +] | -- | # Noise Control | M Off | M Transparency | M* Noise Cancellation | -- | " SET);
    MSBDAPState pp = base(); addPro(&pp); pp.partsPart = 0;
    rows("the BatteryCenter part off (the one level from Bluetooth)", &pp,
         "H My AirPods Pro = 75% | -- | # Noise Control | M Off | M Transparency | M* Noise Cancellation | -- | A Disconnect | -- | " SET);
    MSBDAPState np = base(); addPro(&np); np.noisePart = 0;
    rows("the noise part off (no Noise Control)", &np, "H My AirPods Pro | S [L R 75%] [Case 40% +] | -- | A Disconnect | -- | " SET);
    MSBDAPState all = base(); all.headsetPart = all.partsPart = all.noisePart = 0;
    rows("every part off (never empty: Headphones and Bluetooth Settings)", &all, "H Headphones = -- | -- | " SET);
    MSBDAPState none = base();
    rows("nothing found (Headphones and Bluetooth Settings)", &none, "H Headphones = -- | -- | " SET);
    MSBDAPState sh = base(); addPro(&sh); snprintf(sh.headsets[0].shown, sizeof sh.headsets[0].shown, "AirPods Pro");
    rows("screenshot mode's name shown, the real one matched", &sh,
         "H AirPods Pro | S [L R 75%] [Case 40% +] | -- | # Noise Control | M Off | M Transparency | M* Noise Cancellation | -- | A Disconnect | -- | " SET);
}

// ---- matching ----
static int groupOf(const MSBDAPHeadset *h, const MSBDAPPart *p, int n, char *out, size_t on) {
    int idx[MSBD_AP_MAX_PARTS], g = MSBDAirPodsGroupFor(h, p, n, idx, MSBD_AP_MAX_PARTS);
    out[0] = 0;
    for (int i = 0; i < g; i++) { char one[8]; snprintf(one, sizeof one, "%s%d", i ? "," : "", idx[i]); strncat(out, one, on - strlen(out) - 1); }
    return g;
}
static void matching(void) {
    char got[64];
    MSBDAPHeadset h = hs(PRO, "AirPods Pro", PROADDR, 0x200e, 75);
    MSBDAPPart a[] = { pt(3, 75, 0, PRO, "G1", 0x200e), pt(4, 40, 1, "My AirPods Pro Case", "G1", 0x200e), pt(0, 90, 1, "iPad", "G1", 0x200e) };
    a[2].internal = 1;   // (the iPad's own battery, even sharing the group's id and product id)
    groupOf(&h, a, 3, got, sizeof got);
    check(!strcmp(got, "0,1"), "match: one group by name; the Case joins by matchIdentifier though its groupName differs; the iPad's own battery never counts");
    MSBDAPPart b[] = { pt(3, 75, 0, PRO, "G1", 0x200e), pt(4, 40, 0, "Case", "G1", 0x200e), pt(3, 50, 0, PRO, "G9", 0x200e), pt(4, 20, 0, "Case", "G9", 0x200e) };
    check(groupOf(&h, b, 4, got, sizeof got) == 0, "match: two groups with the same name (and product id): none, the single level");
    MSBDAPHeadset miss = hs("Living Room", NULL, PROADDR, 0x200e, 75);
    check(groupOf(&miss, a, 3, got, sizeof got) == 2 && !strcmp(got, "0,1"), "match: a name miss with one product-id group gives that group");
    check(groupOf(&miss, b, 4, got, sizeof got) == 0, "match: a name miss with two product-id groups gives none");
    MSBDAPHeadset nopid = hs("Living Room", NULL, PROADDR, 0, 75);
    check(groupOf(&nopid, a, 3, got, sizeof got) == 0, "match: a name miss and no product id: none");
    MSBDAPPart c[] = { pt(3, 75, 0, PRO, "", 0x200e), pt(4, 40, 0, "Case", "", 0x200e) };
    check(groupOf(&h, c, 2, got, sizeof got) == 1 && !strcmp(got, "0"), "match: an empty matchIdentifier: only the matched records (the Case cannot join)");
    MSBDAPPart d[] = { pt(3, 75, 0, "AirPods Pro", "G1", 0x200e), pt(4, 40, 0, "Case", "G1", 0x200e) };
    MSBDAPHeadset hd = h; hd.productId = 0;
    check(groupOf(&hd, d, 2, got, sizeof got) == 0, "match: the screenshot name is never used (a record named as screenshot mode shows them is not matched)");
    MSBDAPPart e[] = { pt(3, 75, 0, PRO, "G1", 0x200e), pt(4, 40, 0, "Case", "G1", 0x200e), pt(0, 30, 0, PRO, "G2", 0x200e) };
    check(groupOf(&h, e, 3, got, sizeof got) == 0, "match: name candidates in two groups and product ids alike: none (ambiguous)");
    MSBDAPPart f[] = { pt(1, 80, 0, PRO, "G1", 0x200e), pt(2, 62, 1, PRO, "G1", 0x200e), pt(4, 15, 0, "Case", "G1", 0x200e), pt(3, 99, 0, "Other AirPods", "G7", 0x2013) };
    check(groupOf(&h, f, 4, got, sizeof got) == 3 && !strcmp(got, "0,1,2"), "match: a split pair and its Case; another set nearby left out");
    MSBDAPPart g1[] = { pt(4, 40, 0, "Case", "G1", 0x200e) };
    check(groupOf(&h, g1, 1, got, sizeof got) == 1, "match: the Case alone (buds in it, not reported) joins by product id");
    MSBDAPState st = base(); st.headsetPart = 0;
    st.parts[st.nparts++] = pt(3, 75, 0, PRO, "G1", 0x200e); st.parts[st.nparts++] = pt(3, 60, 0, "Other", "G2", 0x2013);
    MSBDAPBlock bl[4];
    check(MSBDAirPodsBlocks(&st, bl, 4) == 1 && bl[0].ncells == 0, "match: no headphones known and two groups: no strip");
}

// ---- cells ----
static void cells(void) {
    MSBDAPCell c[4]; int single, idx[] = { 0, 1, 2, 3 };
    MSBDAPPart m[] = { pt(3, 75, 0, "x", "G", 1), pt(4, 40, 1, "y", "G", 1) };
    int n = MSBDAirPodsCells(m, idx, 2, c, &single);
    check(n == 2 && c[0].kind == kMSBDAPCellBoth && c[0].percent == 75 && c[1].kind == kMSBDAPCellCase && c[1].charging && single == -1, "cells: parts 3 gives one merged cell at its level, then the Case");
    MSBDAPPart s[] = { pt(4, 40, 0, "y", "G", 1), pt(2, 62, 1, "x", "G", 1), pt(1, 80, 0, "x", "G", 1) };
    n = MSBDAirPodsCells(s, idx, 3, c, &single);
    check(n == 3 && c[0].kind == kMSBDAPCellLeft && c[0].percent == 80 && c[1].kind == kMSBDAPCellRight && c[1].charging && c[2].kind == kMSBDAPCellCase, "cells: 1 + 2 (one charging) give Left then Right, then the Case, whatever the records' order");
    MSBDAPPart z[] = { pt(0, 60, 0, "x", "G", 1) };
    n = MSBDAirPodsCells(z, idx, 1, c, &single);
    check(n == 0 && single == 60, "cells: parts 0 gives no cell, the heading's level");
    MSBDAPPart u[] = { pt(8 | 4, 33, 0, "y", "G", 1), pt(16, 50, 0, "x", "G", 1) };
    n = MSBDAirPodsCells(u, idx, 2, c, &single);
    check(n == 1 && c[0].kind == kMSBDAPCellCase && c[0].percent == 33 && single == 50, "cells: unknown bits ignored (8 with 4: the Case; 16 alone: a single battery)");
    MSBDAPPart w[] = { pt(3, 70, 0, "x", "G", 1), pt(1, 80, 0, "x", "G", 1) };
    n = MSBDAirPodsCells(w, idx, 2, c, &single);
    check(n == 1 && c[0].kind == kMSBDAPCellBoth, "cells: merged and apart at once: the merged cell only");
}

// ---- levels, modes, uids ----
static void words(void) {
    char b[8]; int ok = 1;
    MSBDAirPodsPercentText(-1, b, sizeof b); ok &= !strcmp(b, "--");
    MSBDAirPodsPercentText(-5, b, sizeof b); ok &= !strcmp(b, "--");
    MSBDAirPodsPercentText(101, b, sizeof b); ok &= !strcmp(b, "--");
    MSBDAirPodsPercentText(0, b, sizeof b); ok &= !strcmp(b, "0%");
    MSBDAirPodsPercentText(100, b, sizeof b); ok &= !strcmp(b, "100%");
    check(ok, "percent: \"--\" for -1, -5 and 101; \"0%\", \"100%\"");
    int out[kMSBDAPModes], tick;
    const char *avail[] = { "AVOutputDeviceBluetoothListeningModeActiveNoiseCancellation", "AVOutputDeviceBluetoothListeningModeFuture", "AVOutputDeviceBluetoothListeningModeNormal",
                            "AVOutputDeviceBluetoothListeningModeAudioTransparency" };
    unsigned mask = 0;
    for (int i = 0; i < 4; i++) { int m = MSBDAirPodsModeIndex(avail[i]); if (m >= 0) mask |= 1u << m; }
    int n = MSBDAirPodsModeList(mask, MSBDAirPodsModeIndex("AVOutputDeviceBluetoothListeningModeActiveNoiseCancellation"), out, &tick);
    check(n == 3 && out[0] == kMSBDAPModeOff && out[1] == kMSBDAPModeTransparency && out[2] == kMSBDAPModeNoiseCancellation && tick == 2,
          "modes: Off, Transparency, Noise Cancellation in that order whatever the list's; an unknown string left out; no Automatic, no Adaptive; the tick on the current one");
    n = MSBDAirPodsModeList(mask | (1u << kMSBDAPModeAdaptive), kMSBDAPModeAdaptive, out, &tick);
    check(n == 4 && out[2] == kMSBDAPModeAdaptive && tick == 2, "modes: Automatic listed: Adaptive third (Control Center's order), ticked");
    n = MSBDAirPodsModeList(mask, MSBDAirPodsModeIndex("AVOutputDeviceBluetoothListeningModeAutomatic"), out, &tick);
    check(n == 3 && tick == -1, "modes: a current mode that is not listed gets no tick");
    check(MSBDAirPodsModeList(0, -1, out, &tick) == 0 && MSBDAirPodsModeIndex(NULL) == -1 && MSBDAirPodsModeIndex("") == -1, "modes: an empty list: no section; no string, no mode");
    check(MSBDAirPodsUIDMatches("AA:BB:CC:DD:EE:FF-tacl", "aa:bb:cc:dd:ee:ff") && MSBDAirPodsUIDMatches("aa:bb:cc:dd:ee:ff", "AA:BB:CC:DD:EE:FF")
          && !MSBDAirPodsUIDMatches("AA:BB:CC:DD:EE:F", "aa:bb:cc:dd:ee:ff") && !MSBDAirPodsUIDMatches("AA:BB:CC:DD:EE:FF", "aa:bb:cc:dd:ee:f")
          && !MSBDAirPodsUIDMatches("AA:BB:CC:DD:EE:00-tacl", "aa:bb:cc:dd:ee:ff") && !MSBDAirPodsUIDMatches(NULL, "aa:bb:cc:dd:ee:ff"),
          "uid: \"AA:BB:CC:DD:EE:FF-tacl\" matches \"aa:bb:cc:dd:ee:ff\"; a 16-character uid or address does not; another address does not");
    MSBDAPRouteDev r[] = { rd(1, "Speaker", 0, -1), rd(2, "AIRPODS-ROUTE-UID-1234", M3, 0) };
    check(MSBDAirPodsRoutePick(r, 2, PROADDR, 1) == 1, "uid: the one deviceType-2 device with one set of headphones (a uid that is not an address)");
    check(MSBDAirPodsRoutePick(r, 2, PROADDR, 2) == -1, "uid: ... not with two sets of headphones");
    MSBDAPRouteDev r2[] = { rd(2, "AIRPODS-ROUTE-UID-1234", M3, 0), rd(2, "AIRPODS-ROUTE-UID-5678", M3, 0) };
    check(MSBDAirPodsRoutePick(r2, 2, PROADDR, 1) == -1, "uid: two deviceType-2 devices and no address match: none");
    MSBDAPRouteDev r3[] = { rd(2, "11:22:33:44:55:66-tacl", M3, 0) };
    check(MSBDAirPodsRoutePick(r3, 1, PROADDR, 1) == -1, "uid: the one deviceType-2 device is another device's address: not these headphones'");
    MSBDAPRouteDev r4[] = { rd(1, "aa:bb:cc:dd:ee:01", M3, 0), rd(2, "aa:bb:cc:dd:ee:01-tacl", M3, 0) };
    check(MSBDAirPodsRoutePick(r4, 2, PROADDR, 2) == 1, "uid: the address match is deviceType 2 only, with two sets of headphones too");
}

// ---- the signature: it changes with each shown field, and only with them ----
static uint64_t sig(const MSBDAPState *s) {
    MSBDAPBlock b[MSBD_AP_MAX_HEADSETS]; MSBDAPRow r[MSBD_AP_MAX_ROWS];
    int nb = MSBDAirPodsBlocks(s, b, MSBD_AP_MAX_HEADSETS), nr = MSBDAirPodsMenuRows(s, b, nb, r, MSBD_AP_MAX_ROWS);
    return MSBDAirPodsSignature(r, nr);
}
static void signatures(void) {
    MSBDAPState s = base(); addPro(&s); addOther(&s);
    uint64_t s0 = sig(&s);
    int same = 1, changed = 1; char bad[400] = "";
#define SHOWN(what, edit) do { MSBDAPState t = s; edit; if (sig(&t) == s0) { changed = 0; strncat(bad, " " what, sizeof bad - strlen(bad) - 1); } } while (0)
#define HIDDEN(what, edit) do { MSBDAPState t = s; edit; if (sig(&t) != s0) { same = 0; strncat(bad, " " what, sizeof bad - strlen(bad) - 1); } } while (0)
    SHOWN("merged level", t.parts[0].percent = 74);
    SHOWN("case level", t.parts[1].percent = 41);
    SHOWN("case charging", t.parts[1].charging = 0);
    SHOWN("split", (t.parts[0].parts = 1, t.parts[t.nparts++] = pt(2, 70, 0, PRO, "G1", 0x200e)));
    SHOWN("name", snprintf(t.headsets[0].shown, sizeof t.headsets[0].shown, "Pro"));
    SHOWN("other's level", t.headsets[1].level = 54);
    SHOWN("current mode", t.route[0].current = kMSBDAPModeOff);
    SHOWN("modes offered", t.route[0].modes = M4);
    SHOWN("error line", t.noiseError = 1);
    SHOWN("dropped", t.headsets[1].connected = 0);
    SHOWN("a third set", t.headsets[t.nheadsets++] = hs("Third", NULL, "22:22:22:22:22:22", 0, 10));
    HIDDEN("pro's Bluetooth level (the strip shows BatteryCenter's)", t.headsets[0].level = 12);
    HIDDEN("the real name (matching only: the same group by product id)", snprintf(t.headsets[0].name, sizeof t.headsets[0].name, "Another Name"));
    HIDDEN("the case's own name", snprintf(t.parts[1].groupName, sizeof t.parts[1].groupName, "Another Case Name"));
    HIDDEN("the route uid's suffix", snprintf(t.route[0].uid, sizeof t.route[0].uid, "AA:BB:CC:DD:EE:01-tsco"));
#undef SHOWN
#undef HIDDEN
    MSBDAPState t = s; t.route[0].current = -1;
    int tickSeen = sig(&t) != s0;
    char what[600];
    snprintf(what, sizeof what, "signature: changes with each shown field (levels, charging, split, name, modes, tick, error, a drop, a third set) and not with fields no row shows%s", bad);
    check(changed && same, what);
    check(tickSeen, "signature: the tick going off changes it");
}

// ---- the switch, the glyphs, VoiceOver, the words ----
static void rest(void) {
    check(MSBDAirPodsMenuOn(1, 1) && !MSBDAirPodsMenuOn(1, 0) && MSBDAirPodsMenuOn(0, 0) && MSBDAirPodsMenuOn(0, 1) && !strcmp(MSBD_AIRPODS_MENU_KEY, "airpodsMenu"),
          "switch: stored on, off; missing or not a boolean: on (airpodsMenu)");
    int ok = 1;
    for (int k = kMSBDAPCellBoth; k <= kMSBDAPCellCase + 1; k++) {
        const char *word; const char *const *chain = MSBDAirPodsGlyphs(k == kMSBDAPCellCase + 1 ? MSBD_AP_GLYPH_CHARGING : k, &word);
        int n = 0; for (; chain && chain[n]; n++) {}
        ok &= chain != NULL && n >= 1 && word && word[0];
    }
    check(ok, "glyphs: every chain has SF Symbols names and ends in a word (merged, Left, Right, Case, charging)");
    MSBDAPState s = base(); addPro(&s); addOther(&s);
    MSBDAPBlock b[4]; int nb = MSBDAirPodsBlocks(&s, b, 4);
    char ax[512]; MSBDAirPodsAXText(&s, b, nb, ax, sizeof ax);
    check(!strcmp(ax, "My AirPods Pro, Left and Right 75 percent, Case 40 percent, charging. Studio Headset, 55 percent"), ax);
    MSBDAPState p2 = base(); p2.headsets[p2.nheadsets++] = hs(PRO, NULL, PROADDR, 0x2014, 62);
    p2.parts[p2.nparts++] = pt(1, 80, 0, PRO, "G2", 0x2014); p2.parts[p2.nparts++] = pt(2, 62, 1, PRO, "G2", 0x2014);
    nb = MSBDAirPodsBlocks(&p2, b, 4); MSBDAirPodsAXText(&p2, b, nb, ax, sizeof ax);
    check(!strcmp(ax, "My AirPods Pro, Left 80 percent, Right 62 percent, charging"), ax);
    MSBDAPState dr = base(); addPro(&dr); dr.headsets[0].connected = 0; dr.headsets[dr.nheadsets++] = hs("X", NULL, "33:33:33:33:33:33", 0, -1);
    nb = MSBDAirPodsBlocks(&dr, b, 4); MSBDAirPodsAXText(&dr, b, nb, ax, sizeof ax);
    check(!strcmp(ax, "My AirPods Pro, not connected. X, level unknown"), ax);
    MSBDAPState co = base(); co.headsets[co.nheadsets++] = hs("AirPods", NULL, "AA:BB:CC:DD:EE:02", 0x200f, 70); co.parts[co.nparts++] = pt(4, 40, 0, "Case", "G3", 0x200f);
    nb = MSBDAirPodsBlocks(&co, b, 4); MSBDAirPodsAXText(&co, b, nb, ax, sizeof ax);
    check(!strcmp(ax, "AirPods, 70 percent, Case 40 percent"), ax);
    // (no em or en dash in any text the user sees or hears)
    const char *texts[] = { MSBD_AP_HEADING, MSBD_AP_NOISE_TITLE, MSBD_AP_NOISE_ERROR, MSBD_AP_NOT_CONNECTED, MSBD_AP_SETTINGS, "Connect", "Disconnect",
                            kMSBDAPModeTitles[0], kMSBDAPModeTitles[1], kMSBDAPModeTitles[2], kMSBDAPModeTitles[3], ax };
    ok = 1;
    for (unsigned i = 0; i < sizeof texts / sizeof texts[0]; i++) ok &= !strstr(texts[i], "\xe2\x80\x94") && !strstr(texts[i], "\xe2\x80\x93");
    check(ok, "words: no em or en dash in any row's title, the error line or what VoiceOver reads");
}

// ---- when there is a button, which devices are listed (1.8.8.1.1: the glyph alone is headphones too) ----
static void headphones(void) {
    check(MSBDAirPodsItemIsHeadphones(1, 0, 1, 2), "item: the headphones glyph alone (state 2, no level: AirPods on 17/18): a button");
    check(MSBDAirPodsItemIsHeadphones(2, 1, 1, 2) && MSBDAirPodsItemIsHeadphones(2, 1, 0, -1) && MSBDAirPodsItemIsHeadphones(1, 1, 1, 0),
          "item: the glyph with their level: a button, whatever the data says (only headphones have a level)");
    check(!MSBDAirPodsItemIsHeadphones(1, 0, 1, 0) && !MSBDAirPodsItemIsHeadphones(1, 0, 1, 1),
          "item: a Bluetooth indicator that is not headphones' (state 0 or 1, the regions' regulatory indicator): no button");
    check(MSBDAirPodsItemIsHeadphones(1, 0, 0, -1), "item: the glyph alone where the data cannot be read: taken as the headphones' (a button)");
    check(!MSBDAirPodsItemIsHeadphones(0, 0, 1, 2) && !MSBDAirPodsItemIsHeadphones(0, 1, 0, -1), "item: none of its views shown: no button");
    check(MSBDAirPodsListsDevice(1, 1, 1, 0) && MSBDAirPodsListsDevice(1, 1, 0, 0), "list: a connected device with a battery level (1.8.8.1's rule, kept)");
    check(MSBDAirPodsListsDevice(1, 0, 1, 16) && MSBDAirPodsListsDevice(1, 0, 1, 20), "list: connected headphones by iPadOS's type (16, 20) with no battery level reported");
    check(!MSBDAirPodsListsDevice(1, 0, 1, 0) && !MSBDAirPodsListsDevice(1, 0, 1, 19) && !MSBDAirPodsListsDevice(1, 0, 0, 16),
          "list: neither (a keyboard, another type, the type not readable with no level): not listed");
    check(!MSBDAirPodsListsDevice(0, 1, 1, 16), "list: not connected: never");
}

int main(void) {
    spans(); kinds(); matching(); cells(); words(); signatures(); rest(); headphones();
    printf("test-airpodsmenu (plain C): %d checks, %d fail\n", checks, fails);
    return fails ? 1 : 0;
}
