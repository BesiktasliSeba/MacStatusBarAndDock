// test-popupguard-loader.c -- Mac test of what the loader gives a recovery app (loader/Loader.c, 1.8.8.1 B68): Sileo and Zebra, which carry the
// LNPopupController library, get the popup guard (MacPopupGuard) and nothing else; a recovery app without the library (Filza, TrollStore) gets
// nothing, as before; any other app gets the app-side parts as before and never MacPopupGuard; on an untested iPadOS (rows only) a recovery app
// gets nothing at all. LOADER_INC: the loader's enum, its MacStatusBar parts table, MSBDRecoveryApp and MSBDRecoveryKind, cut out by
// test-popupguard.sh; the selection below is the loader's own loop condition (kPayloads[i].where & kind; rows only: kRow).
#include <stdio.h>
#include <string.h>
#include LOADER_INC

static int fails = 0, checks = 0;
static int gLibrary, gAsked;
static int Library(void) { gAsked++; return gLibrary; }
// the parts the loader would open for that process (path, UIKit loaded and bundled -> kUIKit as MSBDLoad decides), as a space-joined list
static const char *Parts(const char *path, int library, int rowsOnly, char *out, size_t n) {
    gLibrary = library;
    unsigned kind = kUIKit;
    if ((kind & ~kSpotlight) == kUIKit) kind = MSBDRecoveryKind(kind, MSBDRecoveryApp(path), Library);
    out[0] = 0;
    for (size_t i = 0; i < sizeof(kPayloads) / sizeof(kPayloads[0]); i++) {
        if (!(kPayloads[i].where & kind)) continue;
        if (rowsOnly && !(kPayloads[i].where & kRow)) continue;
        if (out[0]) strlcat(out, " ", n);
        strlcat(out, kPayloads[i].name, n);
    }
    return out;
}
static void Expect(const char *what, const char *got, const char *want) {
    checks++; int ok = strcmp(got, want) == 0; if (!ok) fails++;
    printf("%s  %s (%s)\n", ok ? "PASS" : "FAIL", what, ok ? got : got[0] ? got : "nothing");
    if (!ok) printf("        want: %s\n", want[0] ? want : "nothing");
}
static int Has(const char *list, const char *name) { size_t l = strlen(name); for (const char *p = strstr(list, name); p; p = strstr(p + 1, name)) if ((p == list || p[-1] == ' ') && (p[l] == 0 || p[l] == ' ')) return 1; return 0; }

int main(void) {
    char b[2048];
    const char *sileo = "/private/preboot/X/jb-Y/procursus/Applications/Sileo.app/Sileo", *zebra = "/private/preboot/X/jb-Y/procursus/Applications/Zebra.app/Zebra";
    const char *filza = "/private/preboot/X/jb-Y/procursus/Applications/Filza.app/Filza", *troll = "/private/var/containers/Bundle/Application/U/TrollStore.app/TrollStore";
    const char *safari = "/Applications/MobileSafari.app/MobileSafari", *store = "/private/var/containers/Bundle/Application/U/SomeApp.app/SomeApp";
    Expect("Sileo (carries the library): the popup guard alone", Parts(sileo, 1, 0, b, sizeof b), "MacPopupGuard");
    Expect("Zebra (carries the library): the popup guard alone", Parts(zebra, 1, 0, b, sizeof b), "MacPopupGuard");
    Expect("a recovery app without the library (Filza): nothing, as before", Parts(filza, 0, 0, b, sizeof b), "");
    Expect("TrollStore (no library): nothing, as before", Parts(troll, 0, 0, b, sizeof b), "");
    Expect("Sileo on an untested iPadOS or in the crash guard's safe mode (rows only): nothing", Parts(sileo, 1, 1, b, sizeof b), "");
    gAsked = 0; Parts(safari, 1, 0, b, sizeof b);
    checks++; if (gAsked) fails++; printf("%s  the library is looked for only in a recovery app (asked %d times for Safari)\n", gAsked ? "FAIL" : "PASS", gAsked);
    Parts(safari, 0, 0, b, sizeof b);
    checks++; { int ok = Has(b, "MacAppBridge") && !Has(b, "MacPopupGuard"); if (!ok) fails++; printf("%s  any other app: the app-side parts as before (MacAppBridge, which has the guard), never MacPopupGuard (%s)\n", ok ? "PASS" : "FAIL", b); }
    Parts(store, 1, 0, b, sizeof b);
    checks++; { int ok = Has(b, "MacAppBridge") && !Has(b, "MacPopupGuard"); if (!ok) fails++; printf("%s  an App Store app that carries the library: MacAppBridge (its guard), not MacPopupGuard too (%s)\n", ok ? "PASS" : "FAIL", b); }
    checks++; { int n = 0; for (size_t i = 0; i < sizeof(kPayloads) / sizeof(kPayloads[0]); i++) if (kPayloads[i].where & kPopupGuard) n++;
      int ok = n == 1; if (!ok) fails++; printf("%s  exactly one part is a recovery app's (%d)\n", ok ? "PASS" : "FAIL", n); }
    checks++; { unsigned k = MSBDRecoveryKind(kSpringBoard | kUIKit, 1, Library); int ok = k == (kSpringBoard | kUIKit); if (!ok) fails++; printf("%s  SpringBoard (not only an app) is not changed\n", ok ? "PASS" : "FAIL"); }
    printf("test-popupguard loader: %d checks, %d failed\n", checks, fails);
    return fails ? 1 : 0;
}
