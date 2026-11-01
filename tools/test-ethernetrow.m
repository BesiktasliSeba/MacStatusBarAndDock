// Mac test of the Ethernet row's rule (common/InputDevices.h MSBDEthernetListed; 1.7.5 item 3, KT 31 Oct): listed with an adapter, and without one
// unless a trackpad or mouse AND a keyboard are attached (then our Pointer and Keyboard rows are in the sidebar).
#import <Foundation/Foundation.h>
#include "../common/InputDevices.h"
int main(void) {
    int fails = 0, checks = 0;
    for (int adapter = 0; adapter < 2; adapter++) for (int pointer = 0; pointer < 2; pointer++) for (int keyboard = 0; keyboard < 2; keyboard++) {
        BOOL want = adapter || !(pointer && keyboard);   // (KT: hidden ONLY with both rows showing and no adapter)
        checks++;
        if (MSBDEthernetListed(adapter, pointer, keyboard) != want) { fails++; printf("FAIL adapter %d pointer %d keyboard %d\n", adapter, pointer, keyboard); }
    }
    checks++; if (MSBDEthernetListed(NO, YES, YES)) { fails++; printf("FAIL both attached, no adapter: left out\n"); }
    checks++; if (!MSBDEthernetListed(YES, YES, YES)) { fails++; printf("FAIL an adapter brings it back at once\n"); }
    checks++; if (!MSBDEthernetListed(NO, YES, NO) || !MSBDEthernetListed(NO, NO, YES)) { fails++; printf("FAIL one of the two missing: listed\n"); }
    printf("%d checks, %d failed\n", checks, fails);
    return fails ? 1 : 0;
}
