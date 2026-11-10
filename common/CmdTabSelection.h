// CmdTabSelection.h -- whether SpringBoard's -[SBCommandTabViewController selectedApplicationDisplayItem] can be asked (M1 15.6.1, 9 Nov: it is objectAtIndex: on the switcher's
// list, so with an empty list it raises NSRangeException and SpringBoard aborts). Plain C, so the Mac test (tools/test-cmdtabselection.c) runs this very rule.
// listKnown: the list's ivar is there on this iPadOS, count its size (no list object: 0); indexKnown: the selection's ivar is there and an integer. A list we can't read: asked as before.
#ifndef MSBD_CMDTAB_SELECTION_H
#define MSBD_CMDTAB_SELECTION_H
#include <stdbool.h>
#include <stddef.h>
static inline bool MSBDCmdTabSelectionReadable(bool listKnown, size_t count, bool indexKnown, size_t index) {
    if (!listKnown) return true;
    if (count == 0) return false;
    return !indexKnown || index < count;
}
#endif
