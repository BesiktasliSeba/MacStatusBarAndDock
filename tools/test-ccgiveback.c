// test-ccgiveback.c -- Mac test of common/CCGiveBack.h (1.8.0, regression F1): what our own Control Center keeps of Apple's and hands back when
// iPadOS's look comes back without a respring. The header's status bar alpha played as Apple's iPad Control Center sets it (once, 1.0, in the
// header's -initWithFrame:; 15.6.1's code) and as the iPhone's slide-up provider does (each presentation step), through Mac sessions and live
// switches, against a start with iPadOS -- with the rule as built in 1.8.0~z02 (nothing handed back) as the reference that fails; Apple's views'
// order put back after any run of takes, removals and adds (a sweep against Apple's own order, with two old ways as references). Run by test-ccgiveback.sh.
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include "../common/CCGiveBack.h"
static int fails = 0, checks = 0;
static int near(double a, double b) { return fabs(a - b) < 1e-9; }
#define CHECK(cond, what) do { checks++; if (cond) printf("PASS  %s\n", what); else { fails++; printf("FAIL  %s\n", what); } } while (0)

// ---- the header's status bar alpha (CCUIHeaderPocketView -statusBarAlpha / -setStatusBarAlpha:) ----
// One header, the panel's three places that touch it: a presentation's start (DMCCPHeaderBarAway: Apple's value kept, then 0 through Apple's own
// setter), Apple's own calls while the panel shows (DMCCPHeaderBarAlpha: kept, 0 set in their place), the give-back (DMCCPGiveBack). gaveBack = 0
// plays the rule as built in 1.8.0~z02 (nothing handed back).
typedef struct { double bar; MSBDCCApple k; int gaveBack; } Header;
static void appleInit(Header *h, int macOn) {   // (-initWithFrame: sets 1.0: our hook keeps it while ours holds the header, and sets 0)
    if (macOn) { MSBDCCKeepAsked(&h->k, 1.0); h->bar = 0.0; } else h->bar = 1.0;
}
static void appleAsks(Header *h, double a, int macOn) {   // (the slide-up provider's step; never on the iPad)
    if (macOn || h->k.kept) MSBDCCKeepAsked(&h->k, a);
    h->bar = macOn ? 0.0 : a;
}
static void macPresents(Header *h) { if (!h->k.kept) MSBDCCKeepBefore(&h->k, h->bar); h->bar = 0.0; }
static void giveBack(Header *h) { double a = -1; if (h->gaveBack && MSBDCCGiveBack(&h->k, &a)) h->bar = a; }

// ---- Apple's views among their siblings: taken out at their index then, put back in the reverse order at it ----
#define MAXV 40
typedef struct { int ids[MAXV]; int n; } List;
static int indexOf(const List *l, int id) { for (int i = 0; i < l->n; i++) if (l->ids[i] == id) return i; return -1; }
static void removeAt(List *l, int i) { memmove(&l->ids[i], &l->ids[i + 1], (size_t)(l->n - i - 1) * sizeof(int)); l->n--; }
static void insertAt(List *l, int i, int id) { memmove(&l->ids[i + 1], &l->ids[i], (size_t)(l->n - i) * sizeof(int)); l->ids[i] = id; l->n++; }
static int sameList(const List *a, const List *b) { if (a->n != b->n) return 0; for (int i = 0; i < a->n; i++) if (a->ids[i] != b->ids[i]) return 0; return 1; }

int main(void) {
    // ---- the header: Apple's iPad Control Center (set once, at the header's -initWithFrame:) ----
    Header start = { 0, { 0, 0 }, 1 }; appleInit(&start, 0);
    CHECK(near(start.bar, 1.0), "a start with iPadOS: the header's status icons at 1 (its -initWithFrame:'s value)");
    Header h = { 0, { 0, 0 }, 1 }, z02 = { 0, { 0, 0 }, 0 };
    appleInit(&h, 0); appleInit(&z02, 0);
    for (int i = 0; i < 3; i++) { macPresents(&h); macPresents(&z02); }
    CHECK(near(h.bar, 0.0) && h.k.kept && near(h.k.apple, 1.0), "Mac shown three times: the header's copy held at 0, Apple's 1 kept (read once, before ours went in)");
    giveBack(&h); giveBack(&z02);
    CHECK(near(h.bar, start.bar), "Mac -> iPadOS live: the header's status icons as at a start with iPadOS (Apple's 1 handed back)");
    CHECK(!near(z02.bar, start.bar), "  ... the rule as built in 1.8.0~z02 leaves them at 0 until the next respring (F1: this test catches it)");
    CHECK(!h.k.kept, "  ... handed back once: nothing kept after it");
    giveBack(&h);
    CHECK(near(h.bar, 1.0), "  ... a second give-back sets nothing");
    // iPadOS -> Mac -> iPadOS again: Apple's value read again (never an old keep), and handed back again
    macPresents(&h); macPresents(&h); giveBack(&h);
    CHECK(near(h.bar, 1.0) && !h.k.kept, "Mac -> iPadOS -> Mac -> iPadOS live: the same again");
    // A start with Mac: Apple's -initWithFrame: runs while our hook holds the header (or before the panel is in: then Apple's 1 goes in, and is read)
    Header sm = { 0, { 0, 0 }, 1 }; appleInit(&sm, 1);
    CHECK(near(sm.bar, 0.0) && sm.k.kept && near(sm.k.apple, 1.0), "a header made while ours holds it: Apple's 1 kept from its own call, 0 set");
    macPresents(&sm);
    CHECK(near(sm.k.apple, 1.0), "  ... the next presentation does not read our 0 as Apple's (kept already)");
    giveBack(&sm);
    CHECK(near(sm.bar, 1.0), "  ... handed back: 1");
    Header sm2 = { 0, { 0, 0 }, 1 }; appleInit(&sm2, 0); macPresents(&sm2); giveBack(&sm2);
    CHECK(near(sm2.bar, 1.0), "a start with Mac, the header made before the panel was in: Apple's 1 read at the first presentation, handed back");
    // Never replaced: nothing to hand back
    Header nr = { 0, { 0, 0 }, 1 }; appleInit(&nr, 0); nr.bar = 0.7; giveBack(&nr);
    CHECK(near(nr.bar, 0.7), "ours never replaced it (iPadOS all along): nothing set");
    // Apple's value something else than 1 when ours first goes in: that value back
    Header v4 = { 0, { 0, 0 }, 1 }; appleInit(&v4, 0); appleAsks(&v4, 0.4, 0); macPresents(&v4); giveBack(&v4);
    CHECK(near(v4.bar, 0.4), "Apple's own value when ours went in (0.4): 0.4 back, not a guess of 1");

    // ---- the iPhone's slide-up provider (each presentation step sets it with the progress): the last value Apple asked for ----
    Header ip = { 0, { 0, 0 }, 1 }; appleInit(&ip, 0);
    macPresents(&ip);
    double steps[] = { 0.1, 0.45, 0.8, 1.0 };
    for (int i = 0; i < 4; i++) appleAsks(&ip, steps[i], 1);
    CHECK(near(ip.bar, 0.0) && near(ip.k.apple, 1.0), "Apple's steps while ours holds it: each kept as Apple's (the last: 1), 0 set");
    for (int i = 3; i >= 0; i--) appleAsks(&ip, steps[i] - 0.1, 1);   // (the dismissal: down to 0)
    giveBack(&ip);
    CHECK(near(ip.bar, 0.0), "  ... closed, then iPadOS: the last value Apple asked for (its dismissal's 0) handed back");
    appleAsks(&ip, 0.5, 0);
    CHECK(near(ip.bar, 0.5) && !ip.k.kept, "  ... afterwards Apple's own steps go in untouched, nothing kept");

    // ---- the rules themselves ----
    MSBDCCApple k = { 0, 0 };
    MSBDCCKeepBefore(&k, NAN);
    CHECK(!k.kept, "MSBDCCKeepBefore: no value read (not a number): nothing kept");
    MSBDCCKeepBefore(&k, 0.6); MSBDCCKeepBefore(&k, 0.0);
    CHECK(k.kept && near(k.apple, 0.6), "  ... kept once: a later read (ours) does not replace it");
    MSBDCCKeepAsked(&k, 0.25);
    CHECK(k.kept && near(k.apple, 0.25), "MSBDCCKeepAsked: what Apple asks for replaces what was kept");
    MSBDCCKeepAsked(&k, NAN);
    CHECK(near(k.apple, 0.25), "  ... not a number: ignored");
    double out = -1;
    CHECK(MSBDCCGiveBack(&k, &out) && near(out, 0.25) && !k.kept && !MSBDCCGiveBack(&k, &out), "MSBDCCGiveBack: the kept value once, then nothing");
    CHECK(!MSBDCCGiveBack(NULL, &out) && (MSBDCCKeepBefore(NULL, 1), MSBDCCKeepAsked(NULL, 1), 1), "  ... no keep: nothing (and no crash)");
    CHECK(MSBDCCStillOurs(1.0, 1.0) && !MSBDCCStillOurs(0.3, 1.0) && !MSBDCCStillOurs(NAN, 1.0) && MSBDCCStillOurs(1.0 - 1e-9, 1.0),
          "MSBDCCStillOurs: a value Apple set since is Apple's (only ours is handed back over)");

    // ---- Apple's order put back: a sweep of builds, takes, removals and adds ----
    // Apple's layout view holds its own views (some never ours) and the modules' containers; ours takes containers one at a time (at Apple's build
    // or when Mac is chosen, in any order), each with the views before it then; Apple removes some while they are ours and adds new ones (at the
    // end of its view, taken at once, as DMCCPDidAdd); then iPadOS: put back in the reverse order of the takes, each after the last of its views
    // that is back. Apple's own order then: the start's, minus the removed ones, with the added ones at the end. Two references: the take's own
    // index replayed (exact only without removals), and the rule as built in 1.8.0~z02 (appended in the panel's own order).
    srand(42);
    int runs = 6000, good = 0, idxSame = 0, z02same = 0, withRemoval = 0;
    for (int r = 0; r < runs; r++) {
        List view = { {0}, 0 }, apple = { {0}, 0 };
        int nApple = rand() % 4, nMods = 1 + rand() % 14, next = 100, removed = 0;
        for (int i = 0; i < nApple + nMods; i++) view.ids[view.n++] = i < nApple ? 1000 + i : next++;   // (Apple's own views and the containers)
        for (int s = 0; s < 6; s++) { int a = rand() % view.n, b = rand() % view.n, t = view.ids[a]; view.ids[a] = view.ids[b]; view.ids[b] = t; }
        apple = view;
        int takenId[MAXV], takenAt[MAXV], prevN[MAXV], prev[MAXV][MAXV], nt = 0, user[MAXV], nu = 0;
        int order[MAXV], no = 0;
        for (int i = 0; i < view.n; i++) if (view.ids[i] < 1000) order[no++] = view.ids[i];
        if (rand() % 2) for (int i = no - 1; i > 0; i--) { int j = rand() % (i + 1), t = order[i]; order[i] = order[j]; order[j] = t; }   // (in Apple's order, or any)
        for (int i = 0; i < no; i++) {
            int at = indexOf(&view, order[i]);
            takenId[nt] = order[i]; takenAt[nt] = at; prevN[nt] = at; for (int p = 0; p < at; p++) prev[nt][p] = view.ids[p];
            nt++;
            removeAt(&view, at);
            user[nu++] = order[i];
            if (rand() % 5 == 0 && nt > 0) {   // (Apple removes one of ours: its keep goes, Apple's order loses it)
                int victim = takenId[rand() % nt], ai = indexOf(&apple, victim);
                if (ai >= 0) {
                    removeAt(&apple, ai); removed = 1;
                    for (int t = 0; t < nt; t++) if (takenId[t] == victim) {
                        memmove(&takenId[t], &takenId[t + 1], (size_t)(nt - t - 1) * sizeof(int)); memmove(&takenAt[t], &takenAt[t + 1], (size_t)(nt - t - 1) * sizeof(int));
                        memmove(&prevN[t], &prevN[t + 1], (size_t)(nt - t - 1) * sizeof(int)); memmove(&prev[t], &prev[t + 1], (size_t)(nt - t - 1) * sizeof(prev[0]));
                        nt--; break;
                    }
                    for (int u = 0; u < nu; u++) if (user[u] == victim) { memmove(&user[u], &user[u + 1], (size_t)(nu - u - 1) * sizeof(int)); nu--; break; }
                }
            }
            if (rand() % 6 == 0 && apple.n < MAXV - 2) {   // (Apple adds a new module: at the end of its view, taken at once)
                int id = next++;
                apple.ids[apple.n++] = id;
                takenId[nt] = id; takenAt[nt] = view.n; prevN[nt] = view.n; for (int p = 0; p < view.n; p++) prev[nt][p] = view.ids[p];
                nt++;
                user[nu++] = id;
            }
        }
        withRemoval += removed;
        List back = view, byIdx = view, old = view;
        for (int t = nt - 1; t >= 0; t--) {
            long prevAt[MAXV];
            for (int p = 0; p < prevN[t]; p++) prevAt[p] = indexOf(&back, prev[t][p]);
            insertAt(&back, (int)MSBDCCPutBackAt(prevAt, prevN[t]), takenId[t]);
            insertAt(&byIdx, takenAt[t] > byIdx.n ? byIdx.n : takenAt[t], takenId[t]);
        }
        if (sameList(&back, &apple)) good++;
        if (sameList(&byIdx, &apple)) idxSame++;
        for (int u = nu - 1; u > 0; u--) { int j = rand() % (u + 1), t = user[u]; user[u] = user[j]; user[j] = t; }   // (the panel's order: the user's, any)
        for (int u = 0; u < nu; u++) old.ids[old.n++] = user[u];
        if (sameList(&old, &apple)) z02same++;
    }
    char what[220];
    snprintf(what, sizeof what, "Apple's views put back in Apple's order in %d of %d runs (%d with a module removed while ours; takes in Apple's order or any, Apple's own views among them, adds)", good, runs, withRemoval);
    CHECK(good == runs && withRemoval > runs / 4, what);
    snprintf(what, sizeof what, "  ... a take's own index replayed instead would keep it in only %d of %d (a removal shifts the others' indices)", idxSame, runs);
    CHECK(idxSame < runs, what);
    snprintf(what, sizeof what, "  ... the rule as built in 1.8.0~z02 (appended in the panel's order) kept it in only %d of %d", z02same, runs);
    CHECK(z02same < runs, what);
    long none[1] = { -1 }, some[3] = { -1, 4, 2 };
    CHECK(MSBDCCPutBackAt(NULL, 0) == 0 && MSBDCCPutBackAt(none, 1) == 0 && MSBDCCPutBackAt(some, 3) == 5, "MSBDCCPutBackAt: right after the last of its views that is there, else first");

    printf("%s: %d of %d checks passed\n", fails ? "FAIL" : "PASS", checks - fails, checks);
    return fails ? 1 : 0;
}
