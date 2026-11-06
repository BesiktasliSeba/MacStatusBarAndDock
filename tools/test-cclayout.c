// test-cclayout.c -- Mac test of common/CCLayout.h (1.8.0 P2, our own Control Center's panel): every tile's place from Apple's grid sizes, the
// stand-ins at their Mac tile's frame, the panel's place under the bar (left to right and mirrored), its motion with a pull, a detail page's
// height. Numbers as read on the 17.5 (iPad7,1, 17.5.1, landscape 1366 x 1024; Apple's module unit 69 pt, spacing 15 pt) with KT's 13 modules,
// in the order Apple built them there (30 Oct spike). Run by test-cclayout.sh.
#include <stdio.h>
#include "../common/CCLayout.h"
static int fails = 0, checks = 0;
static int near(double a, double b) { return fabs(a - b) < 0.01; }
static void Frame(const char *what, CGRect got, CGRect want) {
    checks++;
    if (near(got.origin.x, want.origin.x) && near(got.origin.y, want.origin.y) && near(got.size.width, want.size.width) && near(got.size.height, want.size.height)) printf("PASS  %s\n", what);
    else { fails++; printf("FAIL  %s (got {%.2f, %.2f, %.2f, %.2f}, want {%.2f, %.2f, %.2f, %.2f})\n", what, got.origin.x, got.origin.y, got.size.width, got.size.height, want.origin.x, want.origin.y, want.size.width, want.size.height); }
}
static void Num(const char *what, double got, double want) { checks++; if (near(got, want)) printf("PASS  %s\n", what); else { fails++; printf("FAIL  %s (got %.3f, want %.3f)\n", what, got, want); } }
static void Int(const char *what, int got, int want) { checks++; if (got == want) printf("PASS  %s\n", what); else { fails++; printf("FAIL  %s (got %d, want %d)\n", what, got, want); } }
// An Apple module as CCPanel.h hands it over: its identifier's role, its place in Apple's order, Apple's size.
static MSBDCCItem Apple(const char *mid, int order, int w, int h) {
    MSBDCCItem it; memset(&it, 0, sizeof it);
    it.role = MSBDCCRoleForModule(mid, &it.standsFor, &it.firstRow);
    it.order = order; it.w = w; it.h = h;
    return it;
}
static MSBDCCItem Tile(int role) { MSBDCCItem it; memset(&it, 0, sizeof it); it.role = role; it.order = -1; it.w = 1; it.h = 1; return it; }
static int KT17(MSBDCCItem *it) {   // (KT's 13 modules on the 17.5 in Apple's order and our four Mac tiles: main's first fixture, for the size checks)
    int n = 0;
    it[n++] = Apple("com.apple.mediaremote.controlcenter.audio", 0, 1, 2); it[n++] = Apple("com.apple.control-center.ConnectivityModule", 1, 2, 2);
    it[n++] = Apple("com.apple.control-center.QuickNoteModule", 2, 1, 1); it[n++] = Apple("com.apple.control-center.CameraModule", 3, 1, 1);
    it[n++] = Apple("com.apple.mediaremote.controlcenter.airplaymirroring", 4, 1, 1); it[n++] = Apple("com.apple.control-center.FlashlightModule", 5, 1, 1);
    it[n++] = Apple("com.apple.control-center.OrientationLockModule", 6, 1, 1); it[n++] = Apple("com.besiktasliseba.macstatusbaranddock.ramcpu", 7, 2, 1);
    it[n++] = Apple("com.apple.mediaremote.controlcenter.nowplaying", 8, 2, 2); it[n++] = Apple("com.apple.springboard.ContinuousExposeModule", 9, 1, 1);
    it[n++] = Apple("com.apple.control-center.MuteModule", 10, 1, 1); it[n++] = Apple("com.apple.control-center.DisplayModule", 11, 1, 2);
    it[n++] = Apple("com.apple.control-center.LowPowerModule", 12, 1, 1);
    it[n++] = Tile(MSBDCCRoleTileConnectivity); it[n++] = Tile(MSBDCCRoleTileDisplay); it[n++] = Tile(MSBDCCRoleTileSound); it[n++] = Tile(MSBDCCRoleTileNowPlaying);
    return n;
}
int main(void) {
    MSBDCCMetrics m = { 69.0, 15.0, kMSBDCCPad };   // (the 17.5's grid; our 12 pt margin)
    // ---- what Apple's identifiers are in the panel ----
    int tile = -1, first = -1;
    Int("Apple's Connectivity: a stand-in ...", MSBDCCRoleForModule("com.apple.control-center.ConnectivityModule", &tile, &first), MSBDCCRoleStandIn);
    Int("  ... for our Connectivity tile", tile, MSBDCCRoleTileConnectivity);
    Int("Apple's Display: a stand-in for our Display tile", MSBDCCRoleForModule("com.apple.control-center.DisplayModule", &tile, NULL) == MSBDCCRoleStandIn && tile == MSBDCCRoleTileDisplay, 1);
    Int("Apple's audio: a stand-in for our Sound tile", MSBDCCRoleForModule("com.apple.mediaremote.controlcenter.audio", &tile, NULL) == MSBDCCRoleStandIn && tile == MSBDCCRoleTileSound, 1);
    Int("Apple's now playing: a stand-in for our Now Playing tile", MSBDCCRoleForModule("com.apple.mediaremote.controlcenter.nowplaying", &tile, NULL) == MSBDCCRoleStandIn && tile == MSBDCCRoleTileNowPlaying, 1);
    Int("Stage Manager (Apple's identifier, TrollPad's module on 17 too): its Mac spot", MSBDCCRoleForModule("com.apple.springboard.ContinuousExposeModule", NULL, NULL), MSBDCCRoleStageManager);
    Int("Screen Mirroring: its Mac spot", MSBDCCRoleForModule("com.apple.mediaremote.controlcenter.airplaymirroring", NULL, NULL), MSBDCCRoleMirroring);
    Int("Focus: its Mac spot", MSBDCCRoleForModule("com.apple.FocusUIModule", NULL, NULL), MSBDCCRoleFocus);
    Int("rotation lock, mute, RAM & CPU: the first row, in that order", MSBDCCRoleForModule("com.apple.control-center.OrientationLockModule", NULL, &first) == MSBDCCRoleFirstRow && first == 1
        && MSBDCCRoleForModule("com.apple.control-center.MuteModule", NULL, &first) == MSBDCCRoleFirstRow && first == 2
        && MSBDCCRoleForModule("com.besiktasliseba.macstatusbaranddock.ramcpu", NULL, &first) == MSBDCCRoleFirstRow && first == 3, 1);
    Int("any other module (Camera, a CCSupport module): the user's grid", MSBDCCRoleForModule("com.apple.control-center.CameraModule", &tile, &first) == MSBDCCRoleOther && tile == MSBDCCRoleOther && first == 0
        && MSBDCCRoleForModule("com.muirey03.powermodule", NULL, NULL) == MSBDCCRoleOther && MSBDCCRoleForModule(NULL, NULL, NULL) == MSBDCCRoleOther, 1);

    // ---- KT's 13 modules on the 17.5, our four Mac tiles ----
    MSBDCCItem it[17];
    int n = 0;
    it[n++] = Apple("com.apple.mediaremote.controlcenter.audio", 0, 1, 2);
    it[n++] = Apple("com.apple.control-center.ConnectivityModule", 1, 2, 2);
    it[n++] = Apple("com.apple.control-center.QuickNoteModule", 2, 1, 1);
    it[n++] = Apple("com.apple.control-center.CameraModule", 3, 1, 1);
    it[n++] = Apple("com.apple.mediaremote.controlcenter.airplaymirroring", 4, 1, 1);
    it[n++] = Apple("com.apple.control-center.FlashlightModule", 5, 1, 1);
    it[n++] = Apple("com.apple.control-center.OrientationLockModule", 6, 1, 1);
    it[n++] = Apple("com.besiktasliseba.macstatusbaranddock.ramcpu", 7, 2, 1);
    it[n++] = Apple("com.apple.mediaremote.controlcenter.nowplaying", 8, 2, 2);
    it[n++] = Apple("com.apple.springboard.ContinuousExposeModule", 9, 1, 1);
    it[n++] = Apple("com.apple.control-center.MuteModule", 10, 1, 1);
    it[n++] = Apple("com.apple.control-center.DisplayModule", 11, 1, 2);
    it[n++] = Apple("com.apple.control-center.LowPowerModule", 12, 1, 1);
    it[n++] = Tile(MSBDCCRoleTileConnectivity); it[n++] = Tile(MSBDCCRoleTileDisplay); it[n++] = Tile(MSBDCCRoleTileSound); it[n++] = Tile(MSBDCCRoleTileNowPlaying);
    MSBDCCResult r = MSBDCCLayout(it, n, m);
    Frame("Connectivity (ours) at the top left, 2 x 2 at Apple's pitch", it[13].frame, CGRectMake(12, 12, 153, 153));
    Frame("Stage Manager in its spot beside it, second row", it[9].frame, CGRectMake(180, 96, 69, 69));
    Frame("Screen Mirroring next to it", it[4].frame, CGRectMake(264, 96, 69, 69));
    Frame("Display (ours) across the panel under the block", it[14].frame, CGRectMake(12, 180, 321, 69));
    Frame("Sound (ours) under it", it[15].frame, CGRectMake(12, 264, 321, 69));
    Frame("Now Playing (ours) under that", it[16].frame, CGRectMake(12, 348, 321, 69));
    Int("Apple's Connectivity: hidden ...", it[1].hidden, 1);
    Frame("  ... at our Connectivity tile's frame (an expanded view grows out of our tile)", it[1].frame, it[13].frame);
    Int("  ... and not placed in the grid itself", it[1].col, -1);
    Int("Apple's Display, audio and now playing: hidden at our Display, Sound and Now Playing tiles", it[11].hidden && it[0].hidden && it[8].hidden
        && CGRectEqualToRect(it[11].frame, it[14].frame) && CGRectEqualToRect(it[0].frame, it[15].frame) && CGRectEqualToRect(it[8].frame, it[16].frame), 1);
    Frame("no Focus on this iPad: rotation lock (first row) takes the free place at the top right", it[6].frame, CGRectMake(180, 12, 69, 69));
    Frame("  ... mute beside it", it[10].frame, CGRectMake(264, 12, 69, 69));
    Frame("RAM & CPU (2 x 1, CCSupport's size) at the first free place of its size: under Now Playing", it[7].frame, CGRectMake(12, 432, 153, 69));
    Frame("the user's other modules in the user's order: Notes after it", it[2].frame, CGRectMake(180, 432, 69, 69));
    Frame("  ... Camera", it[3].frame, CGRectMake(264, 432, 69, 69));
    Frame("  ... Torch on the next row", it[5].frame, CGRectMake(12, 516, 69, 69));
    Frame("  ... Low Power Mode", it[12].frame, CGRectMake(96, 516, 69, 69));
    Int("7 rows", r.rows, 7);
    Num("the panel 345 pt wide (4 x 69 + 3 x 15 + 2 x 12)", r.width, 345.0);
    Num("its content 597 pt tall (7 x 69 + 6 x 15 + 2 x 12)", r.contentHeight, 597.0);
    Int("13 placed (9 modules, 4 tiles; 4 hidden stand-ins)", r.placed, 13);

    // ---- the reading order for assistive features (1.8.0 P3): every placed tile, row by row, each row from its leading column ----
    int ax[17];
    int na = MSBDCCAXOrder(it, 17, ax);
    Int("the reading order: every placed tile (13), the hidden stand-ins left out", na, 13);
    Int("  ... Connectivity first, then rotation lock and mute (row 0), Stage Manager and Mirroring (row 1, under them), Display, Sound, Now Playing",
        ax[0] == 13 && ax[1] == 6 && ax[2] == 10 && ax[3] == 9 && ax[4] == 4 && ax[5] == 14 && ax[6] == 15 && ax[7] == 16, 1);
    Int("  ... then RAM & CPU, Notes, Camera, Torch, Low Power Mode", ax[8] == 7 && ax[9] == 2 && ax[10] == 3 && ax[11] == 5 && ax[12] == 12, 1);
    Int("  ... nothing asked or nowhere to write: none", MSBDCCAXOrder(NULL, 3, ax) == 0 && MSBDCCAXOrder(it, 17, NULL) == 0 && MSBDCCAXOrder(it, 0, ax) == 0, 1);
    // ---- Apple's Stage Manager module and the window engine (1.8.0 P3, plans/control-center-1.8.0.md 1.1) ----
    Int("Stage Manager is left out while another window engine of ours runs (Aerial, Zetsu, MilkyWay)", MSBDCCLeftOut(MSBDCCRoleStageManager, kMSBDCCEngineOther), 1);
    Int("  ... kept with the Stage Manager engine, and with none of ours (iPadOS's own Stage Manager is the user's)",
        !MSBDCCLeftOut(MSBDCCRoleStageManager, kMSBDCCEngineStageManager) && !MSBDCCLeftOut(MSBDCCRoleStageManager, kMSBDCCEngineNone), 1);
    Int("  ... no other module is ever left out", !MSBDCCLeftOut(MSBDCCRoleOther, kMSBDCCEngineOther) && !MSBDCCLeftOut(MSBDCCRoleMirroring, kMSBDCCEngineOther) && !MSBDCCLeftOut(MSBDCCRoleFocus, kMSBDCCEngineOther), 1);
    for (int i = 0; i < 17; i++) it[i].leftOut = MSBDCCLeftOut(it[i].role, kMSBDCCEngineOther);
    r = MSBDCCLayout(it, 17, m);
    Int("left out: Stage Manager not placed and not a stand-in (its view hidden)", it[9].col == -1 && it[9].hidden == 0, 1);
    Frame("  ... its spot is free for the grid: Screen Mirroring keeps its own beside it", it[4].frame, CGRectMake(264, 96, 69, 69));
    Frame("  ... the next module of its size takes the free place: Notes in Stage Manager's place", it[2].frame, CGRectMake(180, 96, 69, 69));
    Frame("  ... RAM & CPU (2 x 1) still under Now Playing", it[7].frame, CGRectMake(12, 432, 153, 69));
    Int("  ... 12 placed", r.placed, 12);
    for (int i = 0; i < 17; i++) it[i].leftOut = 0;

    // ---- no Mac tiles yet: the stand-ins are modules like any other ----
    MSBDCCItem a[5]; n = 0;
    a[n++] = Apple("com.apple.control-center.ConnectivityModule", 0, 2, 2);
    a[n++] = Apple("com.apple.control-center.DisplayModule", 1, 1, 2);
    a[n++] = Apple("com.apple.control-center.MuteModule", 2, 1, 1);
    a[n++] = Apple("com.apple.FocusUIModule", 3, 2, 1);
    a[n++] = Apple("com.apple.springboard.ContinuousExposeModule", 4, 1, 1);
    r = MSBDCCLayout(a, n, m);
    Int("without our Connectivity tile Apple's is shown ...", a[0].hidden, 0);
    Frame("  ... in the grid, at the first free place of its size", a[0].frame, CGRectMake(12, 12, 153, 153));
    Frame("Focus (2 x 1) in its spot at the top right", a[3].frame, CGRectMake(180, 12, 153, 69));
    Frame("Stage Manager in its spot under it", a[4].frame, CGRectMake(180, 96, 69, 69));
    Frame("mute (first row) at the first free place: beside Stage Manager", a[2].frame, CGRectMake(264, 96, 69, 69));
    Frame("Display (1 x 2) on the next rows", a[1].frame, CGRectMake(12, 180, 69, 153));
    Int("4 rows", r.rows, 4);

    // ---- a spot only at its own size; one module per spot ----
    MSBDCCItem b[4]; n = 0;
    b[n++] = Tile(MSBDCCRoleTileConnectivity);
    b[n++] = Apple("com.apple.FocusUIModule", 0, 1, 1);
    b[n++] = Apple("com.apple.springboard.ContinuousExposeModule", 1, 1, 1);
    b[n++] = Apple("com.apple.springboard.ContinuousExposeModule", 2, 1, 1);
    r = MSBDCCLayout(b, n, m);
    Frame("a Focus module of another size (1 x 1) is not put in the 2 x 1 spot: the grid's first free place", b[1].frame, CGRectMake(180, 12, 69, 69));
    Frame("the first Stage Manager module in its spot", b[2].frame, CGRectMake(180, 96, 69, 69));
    Frame("a second one: the grid", b[3].frame, CGRectMake(264, 12, 69, 69));

    MSBDCCItem d[3]; n = 0;   // (a module of another size than its spot's must not take it: the spot's neighbour keeps its own)
    d[n++] = Tile(MSBDCCRoleTileConnectivity);
    d[n++] = Apple("com.apple.FocusUIModule", 0, 1, 2);
    d[n++] = Apple("com.apple.springboard.ContinuousExposeModule", 1, 1, 1);
    r = MSBDCCLayout(d, n, m);
    Frame("a Focus module of 1 x 2 does not take the 2 x 1 spot: Stage Manager keeps its own", d[2].frame, CGRectMake(180, 96, 69, 69));
    Frame("  ... and Focus goes to the first free place of its size (two rows, beside it)", d[1].frame, CGRectMake(264, 12, 69, 153));

    // ---- sizes Apple's grid never gives, nonsense metrics, an empty list, too many modules ----
    MSBDCCItem c[2]; n = 0;
    c[n++] = Apple("com.apple.control-center.CameraModule", 0, 0, 3);
    c[n++] = Apple("com.apple.control-center.FlashlightModule", 1, 5, 1);
    r = MSBDCCLayout(c, n, m);
    Frame("a size of 0 columns: 1 x 1", c[0].frame, CGRectMake(12, 12, 69, 69));
    Frame("a size of 5 columns: 1 x 1", c[1].frame, CGRectMake(96, 12, 69, 69));
    MSBDCCMetrics bad = { NAN, 15.0, 12.0 };
    r = MSBDCCLayout(c, n, bad);
    Int("nonsense metrics: nothing placed", r.placed == 0 && c[0].col == -1 && r.width == 0.0, 1);
    MSBDCCMetrics tinyUnit = { 4.0, 15.0, 12.0 };
    r = MSBDCCLayout(c, n, tinyUnit);
    Int("a 4 pt unit (not a module grid): nothing placed", r.placed, 0);
    r = MSBDCCLayout(NULL, 0, m);
    Num("no tiles at all: the panel's width ...", r.width, 345.0);
    Num("  ... and its margins only", r.contentHeight, 24.0);
    MSBDCCItem many[200]; n = 0;
    for (int i = 0; i < 200; i++) many[n++] = Apple("com.apple.control-center.CameraModule", i, 1, 1);
    r = MSBDCCLayout(many, n, m);
    Int("200 modules: as many rows as the grid has (48 x 4 places)", r.placed, kMSBDCCMaxRows * kMSBDCCCols);
    Int("  ... the rest not placed", many[199].col, -1);

    // ---- where the panel hangs ----
    CGRect p = MSBDCCPanelFrame(1366, 1024, 24, 345, 597, 0);
    Frame("the 17.5 in landscape, 24 pt bar: 2 pt under the bar, 8 pt in from the right edge", p, CGRectMake(1013, 26, 345, 597));
    p = MSBDCCPanelFrame(1366, 1024, 24, 345, 597, 1);
    Frame("  ... right to left (the bar mirrored, its icons at the left): 8 pt in from the left edge", p, CGRectMake(8, 26, 345, 597));
    p = MSBDCCPanelFrame(1366, 1024, 37, 345, 597, 0);
    Frame("Menu Bar Size Large (37 pt bar): under it", p, CGRectMake(1013, 39, 345, 597));
    p = MSBDCCPanelFrame(1024, 768, 20, 345, 900, 0);
    Frame("the iPad 2 in landscape (20 pt bar), a content taller than the screen: down to 12 pt over the bottom (it scrolls)", p, CGRectMake(671, 22, 345, 734));
    p = MSBDCCPanelFrame(300, 600, 24, 345, 400, 0);
    Num("a screen narrower than the panel: its left edge at the screen's", p.origin.x, 0.0);
    p = MSBDCCPanelFrame(300, 600, 24, 345, 400, 1);
    Num("  ... right to left too", p.origin.x, 0.0);
    p = MSBDCCPanelFrame(350, 600, 24, 345, 400, 1);
    Num("  ... no room for the margin, right to left: against the right edge (not past it)", p.origin.x, 5.0);
    p = MSBDCCPanelFrame(350, 600, 24, 345, 400, 0);
    Num("  ... left to right: against the left edge", p.origin.x, 0.0);
    p = MSBDCCPanelFrame(NAN, 1024, 24, 345, 597, 0);
    Int("nonsense: no frame", CGRectIsEmpty(p), 1);

    // ---- under Apple's sensor indicator (P4: the camera, microphone or location in use -- a pill under the status bar, over the status icons) ----
    // (the iPad 2, 16.7.7, landscape 1024 x 768, 20 pt bar, the panel 318 pt wide: the indicator read at {803, 19, 80, 23} with Maps' location in use)
    p = MSBDCCPanelFrameUnder(1024, 768, 20, 318, 622, 0, 803, 19, 80, 23);
    Frame("the indicator over the panel's column: the panel 6 pt under it", p, CGRectMake(698, 48, 318, 622));
    p = MSBDCCPanelFrameUnder(1024, 768, 20, 318, 900, 0, 803, 19, 80, 23);
    Frame("  ... a content taller than the room: down to 12 pt over the bottom from there (it scrolls)", p, CGRectMake(698, 48, 318, 708));
    p = MSBDCCPanelFrameUnder(1024, 768, 20, 318, 622, 0, 833, 19, 20, 23);
    Frame("  ... its narrow look (the icon only) too", p, CGRectMake(698, 48, 318, 622));
    Int("item 12 (15-17): a touch over our menu bar (20 pt on the iPad 2, our icon at y 10) is not the sensor indicator's", MSBDCCOverOurBar(10, 20), 1);
    Int("  ... just under the bar (the indicator's own frame, y 19 to 42 on 16.7.7, from y 20 on): the indicator's", MSBDCCOverOurBar(20, 20) == 0 && MSBDCCOverOurBar(30, 20) == 0, 1);
    Int("  ... nonsense: no", MSBDCCOverOurBar(NAN, 20) == 0 && MSBDCCOverOurBar(10, 0) == 0 && MSBDCCOverOurBar(10, NAN) == 0 && MSBDCCOverOurBar(-INFINITY, 20) == 0 && MSBDCCOverOurBar(-10, -5) == 0, 1);
    p = MSBDCCPanelFrameUnder(1024, 768, 20, 318, 622, 0, 400, 19, 80, 23);
    Frame("the indicator beside the panel's column: the panel under the bar, as without one", p, CGRectMake(698, 22, 318, 622));
    p = MSBDCCPanelFrameUnder(1024, 768, 20, 318, 622, 0, 618, 19, 80, 23);
    Frame("  ... one ending exactly where the panel begins is beside it", p, CGRectMake(698, 22, 318, 622));
    p = MSBDCCPanelFrameUnder(1024, 768, 20, 318, 622, 1, 803, 19, 80, 23);
    Frame("  ... right to left (the panel at the left): the indicator at the right is beside it", p, CGRectMake(8, 22, 318, 622));
    p = MSBDCCPanelFrameUnder(1024, 768, 20, 318, 622, 1, 141, 19, 80, 23);
    Frame("  ... right to left, the indicator over the status icons at the left: the panel 6 pt under it there", p, CGRectMake(8, 48, 318, 622));
    p = MSBDCCPanelFrameUnder(1024, 768, 20, 318, 622, 0, 650, 19, 80, 23);
    Frame("  ... one across the panel's leading edge is over its column: under it", p, CGRectMake(698, 48, 318, 622));
    p = MSBDCCPanelFrameUnder(1024, 768, 20, 318, 622, 0, 0, 0, 0, 0);
    Frame("none shows: under the bar", p, CGRectMake(698, 22, 318, 622));
    p = MSBDCCPanelFrameUnder(1024, 768, 20, 318, 622, 0, 803, 2, 80, 10);
    Frame("an indicator ending above the panel's top already: where it is", p, CGRectMake(698, 22, 318, 622));
    p = MSBDCCPanelFrameUnder(1024, 768, 20, 318, 622, 0, 803, 500, 80, 23);
    Frame("nonsense (one half way down the screen, not a header's): under the bar", p, CGRectMake(698, 22, 318, 622));
    p = MSBDCCPanelFrameUnder(1024, 768, 20, 318, 622, 0, 803, NAN, 80, 23);
    Frame("  ... no number: under the bar", p, CGRectMake(698, 22, 318, 622));
    p = MSBDCCPanelFrameUnder(NAN, 768, 20, 318, 622, 0, 803, 19, 80, 23);
    Int("  ... no screen: no frame", CGRectIsEmpty(p), 1);

    // ---- beside a Dock at the screen's side (Settings > Dock > Position, 1.8.2.2: M1 F3, 17.5 F2, A12Z F3) ----
    // (the M1, 15.6.1, landscape 1194 x 834, 30 pt bar: a Right Dock's platter x 1144..1188, the desktop x 0..1142.01; the panel {868, 32, 318, 698} lay over the
    //  platter by 42 x 691 pt. The span is the Today panel's, DockSide.h MSBDDockSideSpanWithin: its edge 10 pt inside the desktop, 12 pt clear of the platter)
    p = MSBDCCPanelFrameWithin(1194, 834, 30, 318, 698, 0, 8, 1142.01 - 10.0);
    Frame("the panel beside a Right Dock: its right edge 10 pt inside the desktop (12 pt clear of the platter at 1144)", p, CGRectMake(814.01, 32, 318, 698));
    Int("  ... the old rule's place covered the platter (868..1186 against 1144): this one ends before it", CGRectGetMaxX(p) < 1144.0 && CGRectGetMaxX(MSBDCCPanelFrame(1194, 834, 30, 318, 698, 0)) > 1144.0, 1);
    Frame("  ... the span from the screen's edges (8 pt): the very place it had", MSBDCCPanelFrameWithin(1194, 834, 30, 318, 698, 0, 8, 1186), MSBDCCPanelFrame(1194, 834, 30, 318, 698, 0));
    Frame("  ... right to left the panel hangs at the span's low end (a Left Dock's desktop from 51.99: 61.99)", MSBDCCPanelFrameWithin(1194, 834, 30, 318, 698, 1, 61.99, 1186), CGRectMake(61.99, 32, 318, 698));
    Frame("  ... a span with no numbers: the screen's edges, as before", MSBDCCPanelFrameWithin(1194, 834, 30, 318, 698, 0, NAN, NAN), MSBDCCPanelFrame(1194, 834, 30, 318, 698, 0));
    Frame("  ... under the sensor indicator too (the 17.5, a Right Dock's desktop to 1294.7: the span to 1284.7)", MSBDCCPanelFrameUnderWithin(1366, 1024, 20, 345, 597, 0, 0, 0, 0, 0, 8, 1284.7), CGRectMake(939.7, 22, 345, 597));
    Frame("  ... and the old name keeps its numbers", MSBDCCPanelFrameUnder(1024, 768, 20, 318, 622, 0, 803, 19, 80, 23), MSBDCCPanelFrameUnderWithin(1024, 768, 20, 318, 622, 0, 803, 19, 80, 23, 8, 1016));

    // ---- room for one more module (RAM & CPU put in Control Center by itself, 1.7.7 item 8, while the panel is Control Center) ----
    // (the iPad 2's 15 modules in its order with the four Mac tiles, 16.7.7: unit 66, spacing 10; 8 rows, a content of 622 pt -- as read there)
    MSBDCCMetrics m2 = { 66.0, 10.0, kMSBDCCPad };
    MSBDCCItem pad2[24]; int k2 = 0;
    const char *mods2[] = { "com.apple.control-center.ConnectivityModule", "com.apple.mediaremote.controlcenter.nowplaying", "com.apple.control-center.OrientationLockModule",
        "com.apple.mediaremote.controlcenter.airplaymirroring", "com.apple.control-center.DisplayModule", "com.apple.mediaremote.controlcenter.audio", "com.mtac.uptimemodule",
        "com.apple.control-center.MuteModule", "com.0xkuj.ccadsbegone", "com.apple.control-center.CameraModule", "com.apple.replaykit.controlcenter.screencapture",
        "com.apple.control-center.LowPowerModule", "com.apple.springboard.ContinuousExposeModule", "com.sop.MemoryMagic", "com.uzra.aerial.togglecc" };
    int w2[] = { 2, 2, 1, 1, 1, 1, 2, 1, 1, 1, 1, 1, 1, 2, 1 }, h2[] = { 2, 2, 1, 1, 2, 2, 1, 1, 1, 1, 1, 1, 1, 1, 1 };
    for (int i = 0; i < 15; i++) pad2[k2++] = Apple(mods2[i], i, w2[i], h2[i]);
    pad2[k2++] = Tile(MSBDCCRoleTileConnectivity); pad2[k2++] = Tile(MSBDCCRoleTileDisplay); pad2[k2++] = Tile(MSBDCCRoleTileSound); pad2[k2++] = Tile(MSBDCCRoleTileNowPlaying);
    MSBDCCItem ramcpu = Apple("com.besiktasliseba.macstatusbaranddock.ramcpu", -1, 2, 1);
    double need = 0, roomH = 0;
    Int("the iPad 2's panel with RAM & CPU (2 x 1): room (no new row, the panel does not scroll)", MSBDCCRoomForOne(pad2, k2, ramcpu, m2, 768, 20, &need, &roomH, NULL), 1);
    Num("  ... its content with it, as read there", need, 622.0);
    Num("  ... the room under the bar on the screen's shorter side, as read there", roomH, 734.0);
    MSBDCCResult r2 = MSBDCCLayout(pad2, k2, m2);
    Num("  ... the panel's own items are not moved by the question (a copy is laid out)", r2.contentHeight, 622.0);
    MSBDCCItem big[60]; int kb = 0;
    for (int i = 0; i < k2; i++) big[kb++] = pad2[i];
    for (int i = 0; i < 12; i++) big[kb++] = Apple("com.apple.control-center.QuickNoteModule", 15 + i, 1, 1);
    Int("twelve more modules (11 rows, 850 pt): no room, it would scroll", MSBDCCRoomForOne(big, kb, ramcpu, m2, 768, 20, &need, NULL, NULL), 0);
    Num("  ... the content it would need", need, 850.0);
    Int("  ... in portrait the room is the shorter side's too (1024 x 768: 768 counts)", MSBDCCRoomForOne(big, kb, ramcpu, m2, 768, 20, NULL, NULL, NULL), 0);
    kb = k2; for (int i = 0; i < 4; i++) big[kb++] = Apple("com.apple.control-center.QuickNoteModule", 15 + i, 1, 1);
    Int("four more (9 rows with it, 698 pt): room", MSBDCCRoomForOne(big, kb, ramcpu, m2, 768, 20, &need, NULL, NULL), 1);
    Num("  ... 698 pt", need, 698.0);
    Int("  ... a 37 pt bar (Large) on a 700 pt side: 649 pt of room, no room", MSBDCCRoomForOne(big, kb, ramcpu, m2, 700, 37, NULL, NULL, NULL), 0);
    MSBDCCItem other = Apple("com.apple.control-center.CameraModule", -1, 1, 1), at;
    MSBDCCRoomForOne(pad2, k2, other, m2, 768, 20, &need, NULL, &at);
    Num("another module goes at the end of the user's list (where Settings' + adds one): the last row has a place for it", need, 622.0);
    Int("  ... after the Aerial toggle, the list's last (row 7, column 1)", at.row * 10 + at.col, 71);
    MSBDCCRoomForOne(pad2, k2, ramcpu, m2, 768, 20, NULL, NULL, &at);
    Int("  ... RAM & CPU, a first-row module, in the first row after the Mac section's (row 5, columns 0-1)", at.row * 10 + at.col, 50);
    MSBDCCItem sm = Apple("com.apple.springboard.ContinuousExposeModule", -1, 1, 1); sm.leftOut = 1;
    Int("a module the panel leaves out (Stage Manager with another window engine): never room", MSBDCCRoomForOne(pad2, k2, sm, m2, 768, 20, NULL, NULL, NULL), 0);
    MSBDCCMetrics bad2 = { NAN, 10.0, kMSBDCCPad };
    Int("nonsense metrics: no room", MSBDCCRoomForOne(pad2, k2, ramcpu, bad2, 768, 20, NULL, NULL, NULL), 0);
    Int("  ... no screen: no room", MSBDCCRoomForOne(pad2, k2, ramcpu, m2, NAN, 20, NULL, NULL, NULL), 0);
    static MSBDCCItem lots[256]; for (int i = 0; i < 256; i++) lots[i] = Apple("com.apple.control-center.CameraModule", i, 1, 1);
    need = -1;
    Int("  ... more modules than the question takes (255; its copy holds 254 and the module): no room ...", MSBDCCRoomForOne(lots, 255, ramcpu, m, 768, 20, &need, NULL, NULL), 0);
    Num("  ... and nothing laid out", need, 0.0);
    MSBDCCRoomForOne(lots, 254, ramcpu, m, 768, 20, &need, NULL, NULL);
    Int("  ... 254 are laid out (no room: far too tall)", need > 1000.0, 1);
    Int("  ... none at all and a module: room", MSBDCCRoomForOne(NULL, 0, ramcpu, m2, 768, 20, &need, NULL, NULL), 1);
    Num("  ... one row", need, 90.0);

    // ---- Control Center Size (controlCenterScale, 1.8.0): the panel drawn smaller as a whole ----
    Num("Control Center Size never set: 1, the panel as it was (0.82 is BigSurCenter's own default, its panel's only)", MSBDCCSize(0, 0.82), 1.0);
    Num("  ... stored: that size", MSBDCCSize(1, 0.8), 0.8);
    Num("  ... never larger than 1 (nothing enlarged)", MSBDCCSize(1, 1.4), 1.0);
    Num("  ... never under the minimum", MSBDCCSize(1, 0.1), kMSBDCCSizeMin);
    Num("  ... no number stored: 1", MSBDCCSize(1, NAN), 1.0);
    Num("Settings shows ours at 1 when never set (as SpringBoard lays it out)", MSBDCCSizeShown(1, 0, 0.0), 1.0);
    Num("  ... BigSurCenter's at its own 0.82", MSBDCCSizeShown(0, 0, 0.0), kMSBDCCSizeBigSurCenter);
    Num("  ... a stored size for either", MSBDCCSizeShown(1, 1, 0.7) + MSBDCCSizeShown(0, 1, 0.7), 1.4);
    Num("  ... clamped as SpringBoard clamps it", MSBDCCSizeShown(1, 1, 3.0), 1.0);
    {   // (the layout at a size is the layout at Apple's unit, spacing and our margin times it, exactly: it is linear in them -- KT's 13 on the 17.5)
        MSBDCCItem a[17], b[17], c[17];
        int na = KT17(a); KT17(b); KT17(c);
        MSBDCCMetrics m17 = { 69.0, 15.0, kMSBDCCPad };
        MSBDCCResult ra = MSBDCCLayout(a, na, m17);
        MSBDCCScaleLayout(a, na, &ra, 0.8);
        MSBDCCMetrics ms = { m17.unit * 0.8, m17.gap * 0.8, m17.pad * 0.8 };
        MSBDCCResult rb = MSBDCCLayout(b, na, ms);
        int same = na == 17 && near(ra.width, rb.width) && near(ra.contentHeight, rb.contentHeight) && ra.rows == rb.rows;
        for (int i = 0; i < na; i++) same = same && near(a[i].frame.origin.x, b[i].frame.origin.x) && near(a[i].frame.origin.y, b[i].frame.origin.y) && near(a[i].frame.size.width, b[i].frame.size.width)
            && near(a[i].frame.size.height, b[i].frame.size.height) && a[i].col == b[i].col && a[i].row == b[i].row && a[i].hidden == b[i].hidden;
        Int("the 17.5's panel at 0.8: every tile's frame, the stand-ins' and the panel's size the layout's at the unit, spacing and margin times 0.8", same, 1);
        Num("  ... its width (345 pt at 1)", ra.width, 345.0 * 0.8);
        Frame("  ... our Connectivity block", a[13].frame, CGRectMake(9.6, 9.6, 122.4, 122.4));
        Frame("  ... Apple's Connectivity hidden at our block's frame, at the size too (its expanded view grows out of the block as drawn)", a[1].frame, a[13].frame);
        MSBDCCResult rc = MSBDCCLayout(c, na, m17), rd = rc;
        MSBDCCScaleLayout(c, na, &rd, 1.0); MSBDCCScaleLayout(c, na, &rd, NAN); MSBDCCScaleLayout(c, na, &rd, -2);
        Int("  ... at 1 (or nonsense) nothing changes", near(rd.width, rc.width) && near(rd.contentHeight, rc.contentHeight) && near(c[13].frame.size.width, 153.0), 1);
    }
    MSBDCCPlaced pl = MSBDCCPlaceAt(CGRectMake(9.6, 9.6, 122.4, 122.4), 0.8);
    Frame("one of Apple's containers at 0.8: its bounds Apple's own size (the 2 x 2 of 153 pt) -- the module lays itself out as Apple made it", pl.bounds, CGRectMake(0, 0, 153, 153));
    Num("  ... centred on its frame ...", pl.center.x + pl.center.y, 70.8 * 2);
    Num("  ... drawn at 0.8 about its middle: it covers its frame exactly", pl.bounds.size.width * pl.scale, 122.4);
    pl = MSBDCCPlaceAt(CGRectMake(10, 20, 30, 40), 1.3);
    Int("  ... a size over 1 or nonsense: drawn at 1 (never enlarged)", near(pl.scale, 1.0) && near(pl.bounds.size.width, 30) && near(MSBDCCPlaceAt(CGRectMake(0, 0, 30, 40), NAN).scale, 1.0), 1);
    Frame("a rect at a size", MSBDCCScaleRect(CGRectMake(10, 20, 30, 40), 0.5), CGRectMake(5, 10, 15, 20));
    kb = k2; for (int i = 0; i < 12; i++) big[kb++] = Apple("com.apple.control-center.QuickNoteModule", 15 + i, 1, 1);
    Int("RAM & CPU's room at a size: twelve more modules (850 pt at 1) have no room at 1 ...", MSBDCCRoomForOneAt(big, kb, ramcpu, m2, 1.0, 768, 20, &need, &roomH, NULL), 0);
    Num("  ... (850 pt)", need, 850.0);
    Int("  ... room at 0.8 (680 pt of 734)", MSBDCCRoomForOneAt(big, kb, ramcpu, m2, 0.8, 768, 20, &need, &roomH, &at), 1);
    Num("  ... the content it would need there", need, 680.0);
    Num("  ... the room is the screen's (not scaled)", roomH, 734.0);
    Int("  ... the module at its place at the size (the first row after the Mac section's, as at 1)", at.row * 10 + at.col == 50 && near(at.frame.origin.x, 12.0 * 0.8), 1);
    Int("  ... a module the panel leaves out: never room, at any size", MSBDCCRoomForOneAt(pad2, k2, sm, m2, 0.6, 768, 20, NULL, NULL, NULL), 0);
    Int("  ... nonsense metrics: no room", MSBDCCRoomForOneAt(pad2, k2, ramcpu, bad2, 0.8, 768, 20, NULL, NULL, NULL), 0);
    Int("  ... at 1 the same answer as MSBDCCRoomForOne", MSBDCCRoomForOneAt(pad2, k2, ramcpu, m2, 1.0, 768, 20, NULL, NULL, NULL) == MSBDCCRoomForOne(pad2, k2, ramcpu, m2, 768, 20, NULL, NULL, NULL), 1);
    Num("an open page at 0.8: its height at 1 times the size", MSBDCCDetailHeightAt(300, 36, kMSBDCCPad, 1000, 69, 0.8), (300 + 36 + 24) * 0.8);
    Num("  ... taller than the room: the room on the screen (it scrolls), whatever the size", MSBDCCDetailHeightAt(2000, 36, kMSBDCCPad, 700, 69, 0.8), 700.0);
    Num("  ... at 1 as MSBDCCDetailHeight", MSBDCCDetailHeightAt(300, 36, kMSBDCCPad, 1000, 69, 1.0), MSBDCCDetailHeight(300, 36, kMSBDCCPad, 1000, 69));

    // ---- its motion with a pull (Apple's progress) ----
    double al = -1, dy = -1;
    MSBDCCMotion(0.0, 0, &al, &dy); Num("closed: transparent ...", al, 0.0); Num("  ... 8 pt up", dy, -8.0);
    MSBDCCMotion(0.5, 0, &al, &dy); Num("half way: half faded in ...", al, 0.5); Num("  ... 4 pt up", dy, -4.0);
    MSBDCCMotion(1.0, 0, &al, &dy); Num("open: opaque ...", al, 1.0); Num("  ... in place", dy, 0.0);
    MSBDCCMotion(1.35, 0, &al, &dy); Num("pulled further than open: stays in place, opaque", al + dy, 1.0);
    MSBDCCMotion(-0.2, 0, &al, &dy); Num("below closed: transparent", al, 0.0);
    MSBDCCMotion(0.25, 1, &al, &dy); Num("Reduce Motion: it fades ...", al, 0.25); Num("  ... and does not move", dy, 0.0);
    MSBDCCMotion(NAN, 0, &al, &dy); Num("no progress told: shown, in place", al + dy, 1.0);

    // ---- a detail page's height ----
    Num("a page of 200 pt with a 36 pt back row: 260 pt", MSBDCCDetailHeight(200, 36, 12, 986, 69), 260.0);
    Num("a page taller than the room: the room (it scrolls)", MSBDCCDetailHeight(1200, 36, 12, 734, 69), 734.0);
    Num("an empty page: one row of the grid at least", MSBDCCDetailHeight(0, 0, 12, 986, 69), 93.0);
    Num("less room than one row: the room", MSBDCCDetailHeight(0, 0, 12, 60, 69), 60.0);
    Num("no room told: the page's own height", MSBDCCDetailHeight(200, 36, 12, NAN, 69), 260.0);

    // ---- iPadOS 18: Apple's grid answered into the Mac panel's place (CC18Shape.h) ----
    // (the A12Z, 12.9", 18.5, landscape 1366 x 1024: Apple's content 414 x 624 with its own margins 26 on top and 60 at each side; Apple's own
    //  answer {80, 0, 0, 0}; 4 columns of 66 pt tiles at a 76 pt pitch: 294 pt of tiles; our bar 24 / 30 / 37 pt at Small / Medium / Large)
    MSBDCCInsets e18 = { 26, 60, 0, 60 }, in18;
    Num("the panel's top: 2 pt under the bar (Large, 37 pt; the Lock Screen's too: our bar's locked look is drawn there)", MSBDCC18PanelTop(37), 39.0);
    Num("  ... Medium (30 pt)", MSBDCC18PanelTop(30), 32.0);
    Num("  ... Small (24 pt)", MSBDCC18PanelTop(24), 26.0);
    Num("  ... no bar's height told: right under the screen's top", MSBDCC18PanelTop(NAN), 2.0);
    Num("the tiles' top: the panel's margin, the top row (Apple's + and power) and its gap under it", MSBDCC18TilesTop(39), 91.0);
    Int("landscape, Large: insets answered", MSBDCC18Insets(414, 624, 1366, 1024, e18, MSBDCC18TilesTop(39), 0, &in18), 1);
    Num("  ... top: the tiles at 91 (the content's own 26 pt over them)", in18.top, 65.0);
    Num("  ... trailing: the tiles' right edge 8 + 12 pt in from the screen's (past it by the content's own margin: -40)", in18.right, -40.0);
    Num("  ... leading: the rest of the width (Apple's layout takes the four as one)", in18.left, 992.0);
    Num("  ... bottom: the rest of the height", in18.bottom, 335.0);
    CGRect g18 = MSBDCC18GridRect(414, 624, e18, in18);
    Frame("  ... the grid's columns and rows there: the tiles from x 1052 to 1346 (= 1366 - 20), from y 91", g18, CGRectMake(1052, 91, 294, 598));
    Int("  ... in a right-to-left language: answered", MSBDCC18Insets(414, 624, 1366, 1024, e18, MSBDCC18TilesTop(39), 1, &in18), 1);
    Num("  ... the tiles' left edge 20 pt in from the screen's (the leading inset -40)", in18.left, -40.0);
    Num("  ... the trailing one the rest", in18.right, 992.0);
    Frame("  ... the grid at the left", MSBDCC18GridRect(414, 624, e18, in18), CGRectMake(20, 91, 294, 598));
    MSBDCCInsets er = { 26, 50, 0, 70 };
    MSBDCC18Insets(414, 624, 1366, 1024, er, 91, 1, &in18);
    Num("  ... uneven margins: the leading side's own margin counts (left in right-to-left)", in18.left + er.left, 20.0);
    MSBDCC18Insets(414, 624, 1366, 1024, er, 91, 0, &in18);
    Num("  ... and the trailing one's in left-to-right", 1366 - (1366 - in18.right - er.right), 20.0);
    MSBDCC18Insets(414, 624, 1366, 1024, e18, MSBDCC18TilesTop(MSBDCC18PanelTop(30)), 0, &in18);
    Num("Medium: the tiles 7 pt higher (top inset 58)", in18.top, 58.0);
    MSBDCC18Insets(414, 624, 1366, 1024, e18, MSBDCC18TilesTop(MSBDCC18PanelTop(24)), 0, &in18);
    Num("Small: top inset 52", in18.top, 52.0);
    // (18.5 beside a Right Dock, A12Z F3: the platter x 1300.2..1360 lay under the panel {1040, 39, 318, 661}. The desktop to 1298.22, the span to 1288.22: the
    //  panel's trailing margin 1366 - 1288.22 = 77.78 instead of 8, its tiles 89.78 pt in from the screen's edge)
    MSBDCCInsets inR;
    Int("18 beside a Right Dock: insets answered with the Dock's margin", MSBDCC18InsetsMargin(414, 624, 1366, 1024, e18, MSBDCC18TilesTop(39), 0, 1366 - 1288.22, &inR), 1);
    Frame("  ... the tiles end 12 pt inside the span (1288.22 - 12): clear of the Dock", MSBDCC18GridRect(414, 624, e18, inR), CGRectMake(1288.22 - 12.0 - 294.0, 91, 294, 598));
    MSBDCC18Insets(414, 624, 1366, 1024, e18, MSBDCC18TilesTop(39), 0, &in18);
    MSBDCCInsets inD; MSBDCC18InsetsMargin(414, 624, 1366, 1024, e18, MSBDCC18TilesTop(39), 0, 8.0, &inD);
    Int("  ... the screen's own margin (8): the very insets it had", fabs(inD.top - in18.top) < 0.001 && fabs(inD.left - in18.left) < 0.001 && fabs(inD.right - in18.right) < 0.001 && fabs(inD.bottom - in18.bottom) < 0.001, 1);
    Int("  ... a margin leaving the tiles no room: Apple's insets kept", MSBDCC18InsetsMargin(414, 624, 400, 1024, e18, 91, 0, 77.78, &inR), 0);
    Int("  ... no number for the margin: Apple's insets kept", MSBDCC18InsetsMargin(414, 624, 1366, 1024, e18, 91, 0, NAN, &inR), 0);
    Int("portrait (1024 x 1366): answered", MSBDCC18Insets(414, 624, 1024, 1366, e18, 91, 0, &in18), 1);
    Frame("  ... the grid at the right, the same 20 pt in", MSBDCC18GridRect(414, 624, e18, in18), CGRectMake(710, 91, 294, 598));
    Num("  ... the four insets add up to the bounds less the content (width)", in18.left + in18.right, 1024.0 - 414.0);
    Num("  ... (height)", in18.top + in18.bottom, 1366.0 - 624.0);
    Int("nonsense: no content size", MSBDCC18Insets(NAN, 624, 1366, 1024, e18, 91, 0, &in18), 0);
    Int("  ... no bounds", MSBDCC18Insets(414, 624, 0, 1024, e18, 91, 0, &in18), 0);
    MSBDCCInsets eneg = { 26, -5, 0, 60 };
    Int("  ... a negative margin of Apple's", MSBDCC18Insets(414, 624, 1366, 1024, eneg, 91, 0, &in18), 0);
    Int("  ... tiles wider than the screen leaves room for (1330 + 2 x 20 > 1366)", MSBDCC18Insets(1450, 624, 1366, 1024, e18, 91, 0, &in18), 0);
    Int("  ... margins as wide as the content (no tiles)", MSBDCC18Insets(120, 624, 1366, 1024, e18, 91, 0, &in18), 0);
    Int("  ... the tiles' top below the screen", MSBDCC18Insets(414, 624, 1366, 1024, e18, 1100, 0, &in18), 0);
    Int("  ... no place to write the answer", MSBDCC18Insets(414, 624, 1366, 1024, e18, 91, 0, NULL), 0);
    // the panel (our material) for the page that shows
    CGRect grid = CGRectMake(1052, 91, 294, 598);
    Frame("KT's first page (7 rows: 522 pt of tiles): the panel from the top row down to the last tile and its margin", MSBDCC18PanelFrame(grid, 39, 7 * 76 - 10), CGRectMake(1040, 39, 318, 586));
    Frame("  ... a page of one small tile keeps the grid's width", MSBDCC18PanelFrame(grid, 39, 66), CGRectMake(1040, 39, 318, 130));
    Frame("  ... an empty page: the top row and the margins", MSBDCC18PanelFrame(grid, 39, 0), CGRectMake(1040, 39, 318, 64));
    Frame("  ... a negative height: as empty", MSBDCC18PanelFrame(grid, 39, -30), CGRectMake(1040, 39, 318, 64));
    Int("  ... nonsense: no panel", CGRectIsEmpty(MSBDCC18PanelFrame(grid, NAN, 522)) && CGRectIsEmpty(MSBDCC18PanelFrame(CGRectZero, 39, 522)), 1);
    {   // One of our pages open when the grid moves (code review 1.8.1, 3): the panel's place and width, the page's height; else it closes
        CGRect pg = CGRectZero, was = MSBDCC18PanelFrame(grid, 39, 0), moved = CGRectOffset(was, -342, 0);   // (landscape -> portrait on the A12Z: the grid 342 pt further left)
        Int("a page follows the panel to its new place", MSBDCC18PageFrame(moved, was.size.width, 400, &pg), 1);
        Frame("  ... its x and y, the panel's width, the page's own height", pg, CGRectMake(was.origin.x - 342, was.origin.y, was.size.width, 400));
        Int("  ... a shorter room: the height given, not the panel's", MSBDCC18PageFrame(moved, was.size.width, 120, &pg) && pg.size.height == 120, 1);
        Int("  ... half a point of rounding in the width still follows", MSBDCC18PageFrame(moved, was.size.width + 0.5, 400, &pg), 1);
        Int("  ... a panel of another width: it closes (a page is laid out at its opening's width)", MSBDCC18PageFrame(moved, was.size.width + 40, 400, &pg), 0);
        Int("  ... no panel any more: it closes", MSBDCC18PageFrame(MSBDCC18PanelFrame(CGRectZero, 39, 0), was.size.width, 400, &pg), 0);
        Int("  ... nonsense heights: it closes", MSBDCC18PageFrame(moved, was.size.width, NAN, &pg) + MSBDCC18PageFrame(moved, was.size.width, 0, &pg), 0);
        Int("  ... no place to write it: asked all the same", MSBDCC18PageFrame(moved, was.size.width, 400, NULL), 1);
    }
    CGRect pf18 = MSBDCC18PanelFrame(grid, 39, 522), eb, pb;
    MSBDCC18TopRowFrames(pf18, 29, 29, 0, &eb, &pb);
    Frame("Apple's + in the top row at the tiles' leading edge, centred in the row", eb, CGRectMake(1052, 51.5, 29, 29));
    Frame("  ... its power button at their trailing edge", pb, CGRectMake(1317, 51.5, 29, 29));
    MSBDCC18TopRowFrames(pf18, 29, 29, 1, &eb, &pb);
    Frame("  ... right to left: + at the right (Apple mirrors its header)", eb, CGRectMake(1317, 51.5, 29, 29));
    Frame("  ... power at the left", pb, CGRectMake(1052, 51.5, 29, 29));
    Num("  ... the row ends over the tiles' top", 51.5 + 29 <= MSBDCC18TilesTop(39) - 0.0 ? 1 : 0, 1);
    CGPoint dc = MSBDCC18DotsCenter(pf18, grid, 20, 80, 1366, 0);
    Num("Apple's page dots beside the panel on its left, 8 pt off it", dc.x, 1022.0);
    Num("  ... centred on the grid's rows (as Apple centres them on its content)", dc.y, 390.0);
    dc = MSBDCC18DotsCenter(CGRectMake(8, 39, 318, 586), CGRectMake(20, 91, 294, 598), 20, 80, 1366, 1);
    Num("  ... right to left: on the panel's right", dc.x, 344.0);
    dc = MSBDCC18DotsCenter(pf18, grid, 20, 760, 1366, 0);
    Num("  ... dots taller than half the grid never start above the panel's top", dc.y, 39.0 + 380.0);
    dc = MSBDCC18DotsCenter(CGRectMake(10, 39, 318, 586), grid, 20, 80, 1366, 0);
    Num("  ... kept on the screen", dc.x, 10.0);
    Num("Apple's page control keeps its own width beside the panel (20 pt in our layout: the room between the tiles and the screen's edge)", MSBDCC18DotsWidth(20), 20.0);
    Num("  ... a control as wide as the room left of tiles at the left (1052 pt: the dots drawn in its middle) is made the dots' column", MSBDCC18DotsWidth(1052), kMSBDCC18DotsMaxW);
    dc = MSBDCC18DotsCenter(CGRectMake(8, 39, 318, 586), CGRectMake(20, 91, 294, 598), MSBDCC18DotsWidth(1052), 158.5, 1366, 1);
    Num("  ... and its dots then beside the panel (right to left: 326 + 8 + 14)", dc.x, 348.0);
    Num("  ... no width told: the column", MSBDCC18DotsWidth(NAN), kMSBDCC18DotsMaxW);
    Frame("our material's capsule behind Apple's dots: their column (28 pt) and the control's height, centred on them (20 pt control at x 1022)", MSBDCC18DotsPillFrame(CGPointMake(1022, 390), 20, 158.5), CGRectMake(1008, 310.75, 28, 158.5));
    Frame("  ... a control as wide as the column: the same capsule", MSBDCC18DotsPillFrame(CGPointMake(1022, 390), kMSBDCC18DotsMaxW, 158.5), CGRectMake(1008, 310.75, 28, 158.5));
    Frame("  ... never narrower than the control", MSBDCC18DotsPillFrame(CGPointMake(100, 100), 40, 60), CGRectMake(80, 70, 40, 60));
    Frame("  ... right to left: around the dots at the panel's right", MSBDCC18DotsPillFrame(dc, MSBDCC18DotsWidth(1052), 158.5), CGRectMake(334, 310.75, 28, 158.5));
    Int("  ... nonsense: none", CGRectIsEmpty(MSBDCC18DotsPillFrame(CGPointMake(NAN, 1), 20, 100)) && CGRectIsEmpty(MSBDCC18DotsPillFrame(CGPointMake(1, 1), 0, 100)) && CGRectIsEmpty(MSBDCC18DotsPillFrame(CGPointMake(1, 1), 20, -5)) && CGRectIsEmpty(MSBDCC18DotsPillFrame(CGPointMake(1, 1), 20, NAN)), 1);
    // ---- iPadOS 18: a pull's part past the full presentation, and Esc (1.8.1 items 14 and 10) ----
    double pr, pg;
    pr = 10.556; pg = 1.0;
    Int("a pull far past the full presentation in the panel (A12Z 18.5: progress 10.6, paging 1.0): made again", MSBDCC18PullState(1, 1, &pr, &pg), 1);
    Num("  ... with no paging part (Apple's shrank the pages about the screen's middle, the tiles out of the panel)", pg, 0.0);
    Num("  ... and its progress at the full presentation (past 1 Apple's module views rubber-band down, out of the panel's bottom)", pr, 1.0);
    pr = 3.048; pg = 0.511;
    Int("  ... half way to the dots: made again", MSBDCC18PullState(1, 1, &pr, &pg) && pr == 1.0 && pg == 0.0, 1);
    pr = 1.4; pg = 0.0;
    Int("  ... past 1 before any paging part: made again, at 1", MSBDCC18PullState(1, 1, &pr, &pg) && pr == 1.0 && pg == 0.0, 1);
    pr = 0.379; pg = 0.0;
    Int("  ... on its way down (most steps): Apple's own state goes on, its progress kept", MSBDCC18PullState(1, 1, &pr, &pg) == 0 && pr == 0.379, 1);
    pr = 1.0; pg = 0.0;
    Int("  ... at the full presentation: Apple's own", MSBDCC18PullState(1, 1, &pr, &pg), 0);
    pr = 10.0; pg = 1.0;
    Int("  ... iPadOS's own Control Center (or edit mode): Apple's own, untouched", MSBDCC18PullState(0, 1, &pr, &pg) == 0 && pr == 10.0 && pg == 1.0, 1);
    pr = 1.8; pg = 0.0;
    Int("  ... a dismissal's state: Apple's own, untouched", MSBDCC18PullState(1, 0, &pr, &pg) == 0 && pr == 1.8, 1);
    pr = 0.9; pg = NAN;
    Int("  ... a nonsense paging part in the panel is made 0", MSBDCC18PullState(1, 1, &pr, &pg) && pg == 0.0 && pr == 0.9, 1);
    Int("  ... nowhere to read: nothing", MSBDCC18PullState(1, 1, NULL, &pg) || MSBDCC18PullState(1, 1, &pr, NULL), 0);
    // ---- iPadOS 18: Apple's sensor attribution in the panel's top row (1.8.1 item 2) ----
    CGRect band18 = CGRectMake(0, kMSBDCCPad, 318, kMSBDCC18TopRow), e18r = CGRectMake(12, 12.5, 29, 29), p18r = CGRectMake(277, 12.5, 29, 29);
    Frame("the Camera app's attribution (124 x 23, 18.5) centred between + and power on their middle (the A12Z's row: + {12, 12.5}, power {277, 12.5})", MSBDCC18SensorFrame(band18, e18r, p18r, 124, 23), CGRectMake(97, 15.5, 124, 23));
    Frame("  ... right to left (+ at the right, power at the left): the same place", MSBDCC18SensorFrame(band18, p18r, e18r, 124, 23), CGRectMake(97, 15.5, 124, 23));
    Frame("  ... wider than the room between them (8 pt clear of each): the room", MSBDCC18SensorFrame(band18, e18r, p18r, 300, 23), CGRectMake(49, 15.5, 220, 23));
    Int("  ... a panel with no room between the buttons: none (Apple's place)", CGRectIsEmpty(MSBDCC18SensorFrame(CGRectMake(0, 12, 70, 30), CGRectMake(12, 12.5, 29, 29), CGRectMake(41, 12.5, 29, 29), 124, 23)), 1);
    Int("  ... taller than the row: none", CGRectIsEmpty(MSBDCC18SensorFrame(band18, e18r, p18r, 124, 31)), 1);
    Int("  ... nonsense: none", CGRectIsEmpty(MSBDCC18SensorFrame(band18, e18r, p18r, NAN, 23)) && CGRectIsEmpty(MSBDCC18SensorFrame(band18, e18r, p18r, 124, 0)) && CGRectIsEmpty(MSBDCC18SensorFrame(CGRectZero, e18r, p18r, 124, 23)) && CGRectIsEmpty(MSBDCC18SensorFrame(band18, CGRectZero, p18r, 124, 23)), 1);
    CGRect row18 = CGRectMake(1040, 39, 318, kMSBDCCPad + kMSBDCC18TopRow);
    Int("its touches in the panel: on the control within the top row", MSBDCC18SensorTouch(1, CGPointMake(1199, 66), row18), 1);
    Int("  ... Apple's 20 pt more around it, below the row (the first tiles' top): not the control's", MSBDCC18SensorTouch(1, CGPointMake(1199, 95), row18), 0);
    Int("  ... above the row (our menu bar: its Control Center icon): not the control's (1.8.1 item 12)", MSBDCC18SensorTouch(1, CGPointMake(1199, 30), row18), 0);
    Int("  ... anything else of the header's: none", MSBDCC18SensorTouch(0, CGPointMake(1199, 66), row18), 0);
    Int("Esc with nothing open: Control Center closes", MSBDCC18EscStep(0, 0), kMSBDCC18EscClose);
    Int("  ... content Apple presents (an expanded module, the sensor list, edit mode, its gallery): it closes first (the 15-17 panel's page goes back first)", MSBDCC18EscStep(1, 0), kMSBDCC18EscClosePresented);
    Int("  ... an expanded module is itself presented over Control Center on 18 (its container): still closed first", MSBDCC18EscStep(1, 1), kMSBDCC18EscClosePresented);
    Int("  ... something else presented over Control Center keeps the key", MSBDCC18EscStep(0, 1), kMSBDCC18EscNone);
    printf("%d checks, %d failed\n", checks, fails);
    return fails ? 1 : 0;
}
