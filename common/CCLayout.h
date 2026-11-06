// CCLayout.h -- our own Control Center's panel (1.8.0, Control Center Style: Mac; plans/control-center-1.8.0.md 2.3 / 2.4): where every tile
// goes, where the panel hangs and how it moves with a pull. Plain C, so the Mac test (tools/test-cclayout.c) runs this very code;
// statusbar/CCPanel.h hands it the tiles -- ours (the Mac tiles) and Apple's own module containers adopted at Apple's grid sizes
// (-layoutView:layoutRectForSubview:, CCSupport's sizes included) -- with Apple's module unit and spacing in points, and puts each view at the
// frame it answers. No Auto Layout, stack or collection views: one pass at build, on a turn and on a module list change; nothing during a pull.
// The look (macOS 14 / 15's Control Center): four columns at Apple's own pitch, so an adopted tile keeps Apple's size --
//   [ Connectivity 2x2 ][ Focus 2x1                 ]
//   [                  ][ Stage Manager ][ Mirroring ]
//   [ Display 4x1                                    ]
//   [ Sound 4x1                                      ]
//   [ Now Playing 4x1                                ]
//   then rotation lock, mute and RAM & CPU, then the user's other modules in the user's own order, each at the first free place of its size,
//   row by row (a module the Mac section has no spot for, or a spot left empty, is filled the same way: no holes).
// A module one of our Mac tiles stands for (Apple's Connectivity, Display, audio, now playing) is not placed itself: its container stays adopted
// but hidden at that tile's frame, so Apple's expanded view of it grows out of our tile and closes back into it. Without that tile it is placed
// like any other module (Apple's Connectivity in the block's place). A module left out (MSBDCCLeftOut: Apple's Stage Manager while another window
// engine of ours runs) is not placed at all: its container stays adopted, hidden.
#ifndef MSBD_CC_LAYOUT_H
#define MSBD_CC_LAYOUT_H
#include <CoreGraphics/CoreGraphics.h>
#include <string.h>
#include <math.h>

#define kMSBDCCCols 4
#define kMSBDCCMaxRows 48
#define kMSBDCCPad 12.0          // the panel's inner margin, around the tiles
#define kMSBDCCBarGap 2.0        // under the menu bar, as our menus hang
#define kMSBDCCSideMargin 8.0    // from the screen's edge, under the status icons
#define kMSBDCCBottomMargin 12.0 // the room left under the panel on the screen
#define kMSBDCCDrop 8.0          // the panel drops this far into place as Control Center opens (none with Reduce Motion)

// What a tile is in the panel.
enum {
    MSBDCCRoleOther = 0,           // an Apple module of the user's: the grid, in the user's order
    MSBDCCRoleTileConnectivity,    // our Mac tiles (P3 draws them; placeholders until then)
    MSBDCCRoleTileDisplay,
    MSBDCCRoleTileSound,
    MSBDCCRoleTileNowPlaying,
    MSBDCCRoleFocus,               // Apple's, in the Mac section's spots
    MSBDCCRoleStageManager,
    MSBDCCRoleMirroring,
    MSBDCCRoleFirstRow,            // Apple's rotation lock, mute and our RAM & CPU: first in the grid (firstRow: their order)
    MSBDCCRoleStandIn,             // an Apple module a Mac tile stands for (standsFor: that tile's role)
};

// Apple's module identifiers (15-17, as Apple and CCSupport build them; read on 15.6.1, 16.7.7 and 17.5.1): what each is in the panel.
// *standsFor: the Mac tile's role for a stand-in, *firstRow: the order in the first row.
static inline int MSBDCCRoleForModule(const char *mid, int *standsFor, int *firstRow) {
    if (standsFor) *standsFor = MSBDCCRoleOther;
    if (firstRow) *firstRow = 0;
    if (!mid) return MSBDCCRoleOther;
    static const struct { const char *mid; int role, tile, first; } known[] = {
        { "com.apple.control-center.ConnectivityModule", MSBDCCRoleStandIn, MSBDCCRoleTileConnectivity, 0 },
        { "com.apple.control-center.DisplayModule", MSBDCCRoleStandIn, MSBDCCRoleTileDisplay, 0 },
        { "com.apple.mediaremote.controlcenter.audio", MSBDCCRoleStandIn, MSBDCCRoleTileSound, 0 },
        { "com.apple.mediaremote.controlcenter.nowplaying", MSBDCCRoleStandIn, MSBDCCRoleTileNowPlaying, 0 },
        { "com.apple.FocusUIModule", MSBDCCRoleFocus, 0, 0 },
        { "com.apple.springboard.ContinuousExposeModule", MSBDCCRoleStageManager, 0, 0 },   // (16+; TrollPad's on 17 has Apple's identifier)
        { "com.apple.mediaremote.controlcenter.airplaymirroring", MSBDCCRoleMirroring, 0, 0 },
        { "com.apple.control-center.OrientationLockModule", MSBDCCRoleFirstRow, 0, 1 },
        { "com.apple.control-center.MuteModule", MSBDCCRoleFirstRow, 0, 2 },
        { "com.besiktasliseba.macstatusbaranddock.ramcpu", MSBDCCRoleFirstRow, 0, 3 },
    };
    for (size_t i = 0; i < sizeof(known) / sizeof(known[0]); i++) if (!strcmp(mid, known[i].mid)) {
        if (standsFor) *standsFor = known[i].tile;
        if (firstRow) *firstRow = known[i].first;
        return known[i].role;
    }
    return MSBDCCRoleOther;
}

// The window engine, for the Stage Manager spot (statusbar/CCTiles.h reads it at each presentation): 0 none of ours (windowing off, or no engine --
// iPadOS's own Stage Manager is the user's then), 1 the Stage Manager engine, 2 another engine of ours (Aerial, Zetsu, MilkyWay). Apple's Stage
// Manager module shows only where it is the user's to use: left out while another engine of ours runs (its button would fight that engine; our
// Stage Manager guard holds it then anyway), plans/control-center-1.8.0.md 1.1.
enum { kMSBDCCEngineNone = 0, kMSBDCCEngineStageManager = 1, kMSBDCCEngineOther = 2 };
static inline int MSBDCCLeftOut(int role, int engine) { return role == MSBDCCRoleStageManager && engine == kMSBDCCEngineOther; }

// One tile: what it is and its size in grid units (in), where it went (out).
typedef struct {
    int role;           // MSBDCCRole...
    int standsFor;      // MSBDCCRoleStandIn: the role of the Mac tile it stands for
    int firstRow;       // MSBDCCRoleFirstRow: its order there
    int order;          // its place in the user's list (Apple's own order of building them), for the grid
    int leftOut;        // in: not placed at all (MSBDCCLeftOut), its view hidden
    int w, h;           // its size in units (Apple's for an adopted module: 1-4 columns, 1-4 rows; ours for a Mac tile)
    int col, row;       // out: its place (-1: not placed -- no room, or a stand-in, see hidden)
    int hidden;         // out: a stand-in whose Mac tile is there: not shown, at that tile's frame
    CGRect frame;       // out: in the panel's content (its top left at the panel's)
} MSBDCCItem;

// Apple's module grid in points (CCUILayoutOptions' item edge size and item spacing on this iPad), our margin.
typedef struct { double unit, gap, pad; } MSBDCCMetrics;

// The panel that comes out: its width, its content's height (every row and the margins), how many rows.
typedef struct { double width, contentHeight; int rows, placed; } MSBDCCResult;

static inline int MSBDCCMetricsSane(MSBDCCMetrics m) {
    return isfinite(m.unit) && isfinite(m.gap) && isfinite(m.pad) && m.unit >= 30.0 && m.unit <= 160.0 && m.gap >= 0.0 && m.gap <= 60.0 && m.pad >= 0.0 && m.pad <= 60.0;
}
static inline CGRect MSBDCCCellFrame(MSBDCCMetrics m, int col, int row, int w, int h) {
    double pitch = m.unit + m.gap;
    return CGRectMake(m.pad + col * pitch, m.pad + row * pitch, w * m.unit + (w - 1) * m.gap, h * m.unit + (h - 1) * m.gap);
}
static inline int MSBDCCFree(unsigned char used[kMSBDCCMaxRows][kMSBDCCCols], int col, int row, int w, int h) {
    if (col < 0 || row < 0 || col + w > kMSBDCCCols || row + h > kMSBDCCMaxRows) return 0;
    for (int y = row; y < row + h; y++) for (int x = col; x < col + w; x++) if (used[y][x]) return 0;
    return 1;
}
static inline void MSBDCCTake(unsigned char used[kMSBDCCMaxRows][kMSBDCCCols], MSBDCCItem *it, MSBDCCMetrics m, int col, int row, int *rows) {
    for (int y = row; y < row + it->h; y++) for (int x = col; x < col + it->w; x++) used[y][x] = 1;
    it->col = col; it->row = row; it->hidden = 0;
    it->frame = MSBDCCCellFrame(m, col, row, it->w, it->h);
    if (row + it->h > *rows) *rows = row + it->h;
}

// Every tile's place: the Mac section first (fixed spots, in rows of its own), then the grid. A size out of range (0, more than four columns or
// rows) is made 1 x 1, as Apple's grid would never give it; nonsense metrics place nothing (result 0 x 0).
static inline MSBDCCResult MSBDCCLayout(MSBDCCItem *items, int n, MSBDCCMetrics m) {
    MSBDCCResult r = { 0, 0, 0, 0 };
    if (!items || n <= 0) { if (MSBDCCMetricsSane(m)) { r.width = 2 * m.pad + kMSBDCCCols * m.unit + (kMSBDCCCols - 1) * m.gap; r.contentHeight = 2 * m.pad; } return r; }
    for (int i = 0; i < n; i++) { items[i].col = items[i].row = -1; items[i].hidden = 0; items[i].frame = CGRectZero; }
    if (!MSBDCCMetricsSane(m)) return r;
    unsigned char used[kMSBDCCMaxRows][kMSBDCCCols];
    memset(used, 0, sizeof used);
    for (int i = 0; i < n; i++) {
        if (items[i].w < 1 || items[i].w > kMSBDCCCols || items[i].h < 1 || items[i].h > 4) items[i].w = items[i].h = 1;
    }
    int rows = 0;
    // The Mac section. Connectivity's block (2 x 2) at the top left, Focus / Stage Manager / Mirroring beside it (only at the size the spot has),
    // then the wide tiles, one row each, under whatever of the block is there.
    int tile[MSBDCCRoleTileNowPlaying + 1]; for (int k = 0; k <= MSBDCCRoleTileNowPlaying; k++) tile[k] = -1;
    for (int i = 0; i < n; i++) if (items[i].role >= MSBDCCRoleTileConnectivity && items[i].role <= MSBDCCRoleTileNowPlaying && tile[items[i].role] < 0) tile[items[i].role] = i;
    int c = tile[MSBDCCRoleTileConnectivity];
    if (c >= 0) { items[c].w = 2; items[c].h = 2; MSBDCCTake(used, &items[c], m, 0, 0, &rows); }
    else for (int i = 0; i < n; i++) {   // (no Connectivity tile of ours: Apple's own takes the block's place, at its own 2 x 2)
        MSBDCCItem *it = &items[i];
        if (it->role == MSBDCCRoleStandIn && it->standsFor == MSBDCCRoleTileConnectivity && it->w == 2 && it->h == 2) { MSBDCCTake(used, it, m, 0, 0, &rows); break; }
    }
    static const struct { int role, col, row, w, h; } spots[] = {
        { MSBDCCRoleFocus, 2, 0, 2, 1 }, { MSBDCCRoleStageManager, 2, 1, 1, 1 }, { MSBDCCRoleMirroring, 3, 1, 1, 1 },
    };
    for (size_t s = 0; s < sizeof(spots) / sizeof(spots[0]); s++) {
        for (int i = 0; i < n; i++) {
            MSBDCCItem *it = &items[i];
            if (it->role != spots[s].role || it->col >= 0 || it->leftOut) continue;
            if (it->w == spots[s].w && it->h == spots[s].h && MSBDCCFree(used, spots[s].col, spots[s].row, it->w, it->h)) MSBDCCTake(used, it, m, spots[s].col, spots[s].row, &rows);
            break;   // (one module per spot; another of the same kind, or one of another size, goes to the grid)
        }
    }
    for (int k = MSBDCCRoleTileDisplay; k <= MSBDCCRoleTileNowPlaying; k++) {
        int i = tile[k];
        if (i < 0) continue;
        items[i].w = kMSBDCCCols; items[i].h = 1;
        MSBDCCTake(used, &items[i], m, 0, rows, &rows);
    }
    // Stand-ins: at their tile's frame, hidden; without their tile, in the grid like any other module.
    for (int i = 0; i < n; i++) {
        MSBDCCItem *it = &items[i];
        if (it->role != MSBDCCRoleStandIn) continue;
        int t = it->standsFor >= MSBDCCRoleTileConnectivity && it->standsFor <= MSBDCCRoleTileNowPlaying ? tile[it->standsFor] : -1;
        if (t >= 0 && items[t].col >= 0) { it->hidden = 1; it->frame = items[t].frame; }
    }
    // The grid: the first row's modules (in their order), then everyone else in the user's order; each at the first free place of its size.
    int idx[256], k = 0;
    for (int pass = 0; pass < 2; pass++) {
        int from = k;
        for (int i = 0; i < n && k < 256; i++) {
            MSBDCCItem *it = &items[i];
            if (it->col >= 0 || it->hidden || it->leftOut || (it->role >= MSBDCCRoleTileConnectivity && it->role <= MSBDCCRoleTileNowPlaying)) continue;
            if ((pass == 0) != (it->role == MSBDCCRoleFirstRow)) continue;
            idx[k++] = i;
        }
        for (int a = from + 1; a < k; a++) {   // (a stable sort: first-row order, else the user's)
            int v = idx[a], b = a - 1;
            int kv = pass == 0 ? items[v].firstRow : items[v].order;
            while (b >= from && (pass == 0 ? items[idx[b]].firstRow : items[idx[b]].order) > kv) { idx[b + 1] = idx[b]; b--; }
            idx[b + 1] = v;
        }
    }
    for (int a = 0; a < k; a++) {
        MSBDCCItem *it = &items[idx[a]];
        int done = 0;
        for (int row = 0; row + it->h <= kMSBDCCMaxRows && !done; row++) for (int col = 0; col + it->w <= kMSBDCCCols && !done; col++)
            if (MSBDCCFree(used, col, row, it->w, it->h)) { MSBDCCTake(used, it, m, col, row, &rows); done = 1; }
    }
    for (int i = 0; i < n; i++) if (items[i].col >= 0) r.placed++;
    r.rows = rows;
    r.width = 2 * m.pad + kMSBDCCCols * m.unit + (kMSBDCCCols - 1) * m.gap;
    r.contentHeight = 2 * m.pad + (rows > 0 ? rows * m.unit + (rows - 1) * m.gap : 0);
    return r;
}

// RAM & CPU put in Control Center by itself (StatusBar.x's CCAutoAdd, 1.7.7 item 8: "where there is room") while the panel is Control Center
// (Apple's grid under it is empty and tells nothing): room for one more module -- extra: its role, Apple's size for it -- is the panel still showing
// every tile without scrolling on the screen's shorter side (the room under the bar there, as MSBDCCPanelFrame gives it) with the module placed.
// In the panel tiles go where its rules put them (the user's list gives only their order), so the others making way for it is the panel's own
// layout, as for any module added in Settings > Control Center. It goes at the end of the user's list, where Settings' + adds one. *needH
// (optional): the content's height with it; *roomH (optional): the room; *placed (optional): the module as laid out. Nonsense input: no room.
static inline int MSBDCCRoomForOne(const MSBDCCItem *items, int n, MSBDCCItem extra, MSBDCCMetrics m, double shortSide, double barH, double *needH, double *roomH, MSBDCCItem *placed) {
    if (needH) *needH = 0;
    if (roomH) *roomH = 0;
    if (n < 0 || n > 254 || (n > 0 && !items) || !MSBDCCMetricsSane(m) || !isfinite(shortSide) || !isfinite(barH) || shortSide <= 0) return 0;
    MSBDCCItem all[255];
    int last = -1;
    for (int i = 0; i < n; i++) { all[i] = items[i]; if (items[i].order > last) last = items[i].order; }
    extra.order = last + 1;
    all[n] = extra;
    MSBDCCResult r = MSBDCCLayout(all, n + 1, m);
    double room = shortSide - fmax(0.0, barH) - kMSBDCCBarGap - kMSBDCCBottomMargin;
    if (needH) *needH = r.contentHeight;
    if (roomH) *roomH = room;
    if (placed) *placed = all[n];
    return all[n].col >= 0 && !all[n].hidden && r.contentHeight <= room + 0.5;
}

// The order VoiceOver and the other assistive features go through the panel: every tile placed, row by row and in each row from its leading
// column (a tile taller than a row comes at its top row), so the reading order is the order on the screen, whatever order the views were added
// in. Fills `order` with the items' indices (at most n), returns how many.
static inline int MSBDCCAXOrder(const MSBDCCItem *items, int n, int *order) {
    int k = 0;
    if (!items || !order || n <= 0) return 0;
    for (int i = 0; i < n; i++) if (items[i].col >= 0 && items[i].row >= 0) order[k++] = i;
    for (int a = 1; a < k; a++) {   // (a stable sort by row, then column)
        int v = order[a], b = a - 1;
        while (b >= 0 && (items[order[b]].row > items[v].row || (items[order[b]].row == items[v].row && items[order[b]].col > items[v].col))) { order[b + 1] = order[b]; b--; }
        order[b + 1] = v;
    }
    return k;
}

// Where the panel hangs on its screen (screenW x screenH, in the overlay's space): its top kMSBDCCBarGap under the menu bar (barH), under the
// status icons -- at the right, or at the left in a right-to-left language (the bar is mirrored there, the icons at its left) --, kMSBDCCSideMargin
// in from that edge; as tall as its content, at most down to kMSBDCCBottomMargin over the screen's bottom (the rest scrolls).
// (lo, hi: the span across the screen the panel may use, its trailing edge at hi -- at lo with a right-to-left bar. kMSBDCCSideMargin from the screen's edges,
//  MSBDCCPanelFrame below; beside a Dock at the screen's side the Today panel's span, common/DockSide.h MSBDDockSideSpanWithin: the panel covered a Right Dock by
//  42 x 691 pt, M1 F3 / 17.5 F2 / A12Z F3, 1.8.2.2)
static inline CGRect MSBDCCPanelFrameWithin(double screenW, double screenH, double barH, double width, double contentH, int rtl, double lo, double hi) {
    if (!isfinite(screenW) || !isfinite(screenH) || !isfinite(barH) || !isfinite(width) || !isfinite(contentH) || screenW <= 0 || screenH <= 0 || width <= 0) return CGRectZero;
    if (!isfinite(lo) || !isfinite(hi)) { lo = kMSBDCCSideMargin; hi = screenW - kMSBDCCSideMargin; }
    double top = fmax(0.0, barH) + kMSBDCCBarGap;
    double room = screenH - top - kMSBDCCBottomMargin;
    double h = fmax(0.0, fmin(contentH, room));
    double x = rtl ? lo : hi - width;
    if (x + width > screenW) x = screenW - width;   // (no room for the margin: against the far edge)
    if (x < 0) x = 0;   // (a screen narrower than the panel: from its left edge)
    return CGRectMake(x, top, width, h);
}
static inline CGRect MSBDCCPanelFrame(double screenW, double screenH, double barH, double width, double contentH, int rtl) {
    return MSBDCCPanelFrameWithin(screenW, screenH, barH, width, contentH, rtl, kMSBDCCSideMargin, screenW - kMSBDCCSideMargin);
}

// Where the panel hangs while iPadOS's sensor indicator shows in Control Center's header (the camera, the microphone or the location in use: a
// small pill right under the status bar, over the status icons -- where the panel hangs; a tap on it opens Apple's list of the apps that used them):
// sx, sy, sw, sh its frame on the screen (sw or sh <= 0: none shows). Over the panel's column, the panel starts kMSBDCCSensorGap under it, so the
// indicator shows as on a stock iPad; beside it, the panel stays where MSBDCCPanelFrame puts it. As tall as its content either way, at most down to
// kMSBDCCBottomMargin over the screen's bottom (the rest scrolls).
#define kMSBDCCSensorGap 6.0
// A touch at y (the overlay's space: the screen's, from its top) over our menu bar of height barH: Apple's sensor indicator, laid out under its own
// lower status bar, takes a touch 20 pt beyond its frame on every side (-[CCUIHeaderPocketView hitTest:withEvent:]), which over our taller bar
// took the tap on our Control Center icon (1.8.0 regression iPad 2, finding 3: 16.7.7 x 803 to 883 for the pill, our icon at x 876). Nonsense: no.
static inline int MSBDCCOverOurBar(double y, double barH) { return isfinite(y) && isfinite(barH) && barH > 0 && y < barH; }
static inline CGRect MSBDCCPanelFrameUnderWithin(double screenW, double screenH, double barH, double width, double contentH, int rtl, double sx, double sy, double sw, double sh, double lo, double hi) {
    CGRect f = MSBDCCPanelFrameWithin(screenW, screenH, barH, width, contentH, rtl, lo, hi);
    if (f.size.width <= 0 || !(sw > 0) || !(sh > 0) || !isfinite(sx) || !isfinite(sy) || !isfinite(sw) || !isfinite(sh)) return f;
    if (sx + sw <= f.origin.x || sx >= f.origin.x + f.size.width) return f;   // (beside the panel's column: it shows already)
    double top = sy + sh + kMSBDCCSensorGap;
    if (top <= f.origin.y || top > screenH / 2.0) return f;   // (above the panel's top already; or not a header's indicator: nonsense)
    f.origin.y = top;
    f.size.height = fmax(0.0, fmin(contentH, screenH - top - kMSBDCCBottomMargin));
    return f;
}
static inline CGRect MSBDCCPanelFrameUnder(double screenW, double screenH, double barH, double width, double contentH, int rtl, double sx, double sy, double sw, double sh) {
    return MSBDCCPanelFrameUnderWithin(screenW, screenH, barH, width, contentH, rtl, sx, sy, sw, sh, kMSBDCCSideMargin, screenW - kMSBDCCSideMargin);
}

// The panel during a presentation (Apple's transition state: progress 0 closed .. 1 open, past 1 while pulled further, below 0 never): it fades
// with the progress and drops kMSBDCCDrop pt into place; with Reduce Motion it only fades.
static inline void MSBDCCMotion(double progress, int reduceMotion, double *alpha, double *dy) {
    double a = isfinite(progress) ? fmax(0.0, fmin(1.0, progress)) : 1.0;
    if (alpha) *alpha = a;
    if (dy) *dy = reduceMotion ? 0.0 : -kMSBDCCDrop * (1.0 - a);
}

// A detail page in place of the tiles (its own height, worked out before it shows; the back row above it): the panel's height for it, never
// shorter than one row of Apple's grid nor taller than the room the panel has on the screen (the page scrolls then; the room wins).
static inline double MSBDCCDetailHeight(double pageH, double headerH, double pad, double room, double unit) {
    double h = fmax((isfinite(pageH) ? fmax(0.0, pageH) : 0.0) + headerH + 2 * pad, 2 * pad + unit);
    return isfinite(room) && room > 0 ? fmin(h, room) : h;
}

// ---- Control Center Size (Settings > Status Bar > Control Center, controlCenterScale) ---------------------------------------------------------
// The slider sizes our panel as a whole, as it sizes BigSurCenter's (KT 3 Nov): the layout above runs at Apple's own unit and spacing and every
// frame and the panel's width and height come out times the size (the layout is linear in the unit, the spacing and the margin, so that is the
// layout at the smaller unit exactly). Our tiles lay their parts out at their frame's own size and draw their text and symbols at the size
// (statusbar/CCTiles.h: no picture made smaller); Apple's adopted containers keep Apple's own size and are drawn at the panel's (MSBDCCPlaceAt: a
// scale about their middle, so a module's content keeps its proportions; at most 1, nothing is ever enlarged), an open page the same way (its rows
// are the menus' own). Never set: 1, the panel as it was (0.82 is BigSurCenter's own default, its panel's only); stored: kMSBDCCSizeMin ... 1.
#define kMSBDCCSizeMin 0.5
static inline double MSBDCCSize(int stored, double value) {
    if (!stored || !isfinite(value)) return 1.0;
    return fmax(kMSBDCCSizeMin, fmin(1.0, value));
}
// The slider as Settings shows it (MSBRootListController's -readPreferenceValue:): what is stored, else the chosen style's own size -- 1 for ours,
// BigSurCenter's 0.82 (its panel's default since 1.x, StatusBar.x gCCScale).
#define kMSBDCCSizeBigSurCenter 0.82
static inline double MSBDCCSizeShown(int ours, int stored, double value) {
    if (stored && isfinite(value)) return fmax(kMSBDCCSizeMin, fmin(1.0, value));
    return ours ? 1.0 : kMSBDCCSizeBigSurCenter;
}
static inline CGRect MSBDCCScaleRect(CGRect r, double s) { return CGRectMake(r.origin.x * s, r.origin.y * s, r.size.width * s, r.size.height * s); }
// MSBDCCLayout's answer at size s: every item's frame (a stand-in's too: its tile's) and the panel's width and content height.
static inline void MSBDCCScaleLayout(MSBDCCItem *items, int n, MSBDCCResult *r, double s) {
    if (!isfinite(s) || s <= 0.0 || fabs(s - 1.0) < 1e-9) return;
    for (int i = 0; items && i < n; i++) items[i].frame = MSBDCCScaleRect(items[i].frame, s);
    if (r) { r->width *= s; r->contentHeight *= s; }
}
// One of Apple's containers at frame f of a panel drawn at size s: its bounds Apple's own size (f's at size 1), its centre f's, drawn at s.
typedef struct { CGRect bounds; CGPoint center; double scale; } MSBDCCPlaced;
static inline MSBDCCPlaced MSBDCCPlaceAt(CGRect f, double s) {
    MSBDCCPlaced p;
    if (!isfinite(s) || s <= 0.0 || s > 1.0) s = 1.0;
    p.bounds = CGRectMake(0, 0, f.size.width / s, f.size.height / s);
    p.center = CGPointMake(f.origin.x + f.size.width / 2.0, f.origin.y + f.size.height / 2.0);
    p.scale = s;
    return p;
}
// RAM & CPU's room in the panel at size s (MSBDCCRoomForOne's rule with the panel's height at that size): a smaller panel has more room under it.
static inline int MSBDCCRoomForOneAt(const MSBDCCItem *items, int n, MSBDCCItem extra, MSBDCCMetrics m, double s, double shortSide, double barH, double *needH, double *roomH, MSBDCCItem *placed) {
    if (!isfinite(s) || s <= 0.0 || s > 1.0) s = 1.0;
    double need = 0, room = 0;
    MSBDCCItem it = extra; it.col = it.row = -1; it.hidden = 0; it.frame = CGRectZero;   // (nonsense input: MSBDCCRoomForOne places nothing)
    MSBDCCRoomForOne(items, n, extra, m, shortSide, barH, &need, &room, &it);
    if (needH) *needH = need * s;
    if (roomH) *roomH = room;
    if (placed) { *placed = it; placed->frame = MSBDCCScaleRect(it.frame, s); }
    return it.col >= 0 && !it.hidden && need > 0 && need * s <= room + 0.5;
}
// An open page at size s: laid out at the panel's width at size 1 (width / s) with the room the panel has there (room / s), drawn at s -- its
// panel's height (the page's at size 1 times s, as MSBDCCDetailHeight gives it).
static inline double MSBDCCDetailHeightAt(double pageH, double headerH, double pad, double room, double unit, double s) {
    if (!isfinite(s) || s <= 0.0 || s > 1.0) s = 1.0;
    return MSBDCCDetailHeight(pageH, headerH, pad, isfinite(room) && room > 0 ? room / s : room, unit) * s;
}

// ---- iPadOS 18 (statusbar/CC18Shape.h) ----------------------------------------------------------------------------------------------------------
// On 18 every tile is Apple's own (SpringBoardHome icon lists of its modules and WidgetKit controls, its pages, edit mode and gallery), so nothing
// above lays them out: Apple's grid is answered into the Mac panel's place. Apple lays the grid out in its full-screen view with the insets its
// presentation provider answers around the content's size (-[CCUIOverlayStatusBarPresentationProvider _edgeInsetsForContentSize:withinBounds:
// contentEdgeInsets:orientation:]); the content has margins of its own around the tiles (contentEdgeInsets: 26 pt on top, 60 at each side on the
// 12.9", 18.5). The panel hangs as on 15-17: its top kMSBDCCBarGap under the menu bar, its trailing edge kMSBDCCSideMargin in from the screen's (the
// left in a right-to-left language), our material kMSBDCCPad around the tiles, and over them a top row for Apple's + (edit) and power buttons (KT
// 3 Nov: shown in the panel, working as on stock), the leading one at the tiles' leading edge, the other at their trailing edge.
#define kMSBDCC18TopRow 30.0      // the top row (Apple's + and power buttons are 29 pt round)
#define kMSBDCC18TopRowGap 10.0   // between it and the tiles (Apple's tile spacing on the 12.9")
#define kMSBDCC18DotsGap 8.0      // Apple's page dots beside the panel, on its side away from the screen's edge
#define kMSBDCC18DotsMaxW 28.0    // their column at most (Apple sizes its page control to the room between the tiles and the screen's edge -- 20 pt
                                  // in our layout -- and draws the dots in its middle; a wider control, centred beside the panel, put them far off)

typedef struct { double top, left, bottom, right; } MSBDCCInsets;

// The panel's top: kMSBDCCBarGap under our menu bar (barH) -- on the Lock Screen too: our bar is drawn there, in its locked look (the status
// icons on its band, in SpringBoard's status bar window over the Cover Sheet; 37 pt at Menu Bar Size Large, A12Z 18.5), so a panel hung under
// iOS's own 24 pt cut into it.
static inline double MSBDCC18PanelTop(double barH) { return (isfinite(barH) ? fmax(0.0, barH) : 0.0) + kMSBDCCBarGap; }
// The tiles' top under the panel's: its margin, the top row and the row's gap.
static inline double MSBDCC18TilesTop(double panelTop) { return panelTop + kMSBDCCPad + kMSBDCC18TopRow + kMSBDCC18TopRowGap; }
// The insets that put the content's tiles there -- their top at tilesTop, their trailing edge kMSBDCCSideMargin + kMSBDCCPad in from the screen's
// (the content's own margins taken off: edge) -- with the four insets adding up to the bounds less the content, as Apple's layout takes them
// (it placed the tiles exactly there, A12Z 18.5). The content may reach past the screen's edge by its own margin (a negative inset). 1 with
// *out; 0 for nonsense input or tiles wider than the screen leaves room for (the caller keeps Apple's insets).
// (margin: the panel's trailing edge from the bounds' -- kMSBDCCSideMargin, MSBDCC18Insets below; beside a Dock at that side of the screen, the Dock's room and
//  the Today panel's margin, as on 15-17: MSBDCCPanelFrameWithin, 1.8.2.2)
static inline int MSBDCC18InsetsMargin(double contentW, double contentH, double boundsW, double boundsH, MSBDCCInsets edge, double tilesTop, int rtl, double margin, MSBDCCInsets *out) {
    if (!out || !isfinite(contentW) || !isfinite(contentH) || !isfinite(boundsW) || !isfinite(boundsH) || !isfinite(tilesTop) || !isfinite(margin) || margin < 0) return 0;
    if (!isfinite(edge.top) || !isfinite(edge.left) || !isfinite(edge.bottom) || !isfinite(edge.right)) return 0;
    if (contentW <= 0 || contentH <= 0 || boundsW <= 0 || boundsH <= 0 || edge.top < 0 || edge.left < 0 || edge.bottom < 0 || edge.right < 0 || tilesTop < 0) return 0;
    double side = margin + kMSBDCCPad, tilesW = contentW - edge.left - edge.right;
    if (tilesW <= 0 || tilesW + side + kMSBDCCSideMargin + kMSBDCCPad > boundsW || tilesTop >= boundsH) return 0;
    MSBDCCInsets r;
    r.top = tilesTop - edge.top;
    r.bottom = boundsH - contentH - r.top;
    if (rtl) { r.left = side - edge.left; r.right = boundsW - contentW - r.left; }
    else { r.right = side - edge.right; r.left = boundsW - contentW - r.right; }
    *out = r;
    return 1;
}
static inline int MSBDCC18Insets(double contentW, double contentH, double boundsW, double boundsH, MSBDCCInsets edge, double tilesTop, int rtl, MSBDCCInsets *out) {
    return MSBDCC18InsetsMargin(contentW, contentH, boundsW, boundsH, edge, tilesTop, rtl, kMSBDCCSideMargin, out);
}
// The grid's columns as those insets place them (x and width of the tiles' area, the content's margins taken off) and the rows' area (y and the
// content's full height of rows): the panel keeps the grid's width on every page (a page of one small tile is still the panel's width).
static inline CGRect MSBDCC18GridRect(double contentW, double contentH, MSBDCCInsets edge, MSBDCCInsets insets) {
    return CGRectMake(insets.left + edge.left, insets.top + edge.top, contentW - edge.left - edge.right, contentH - edge.top - edge.bottom);
}
// Our material, the panel, for the page that shows: the grid's columns (grid), from its top (panelTop: the top row over the tiles) down to the
// page's last tile -- rowsH, the height its icon views take from its first row, read in the page's own space, so it is the same while the pages
// scroll -- and kMSBDCCPad more. The panel stays where it is while the pages scroll and takes the next page's height once they rest (CC18Shape.h).
// Empty for nonsense.
static inline CGRect MSBDCC18PanelFrame(CGRect grid, double panelTop, double rowsH) {
    if (!isfinite(grid.origin.x) || !isfinite(grid.size.width) || !isfinite(panelTop) || !isfinite(rowsH) || !(grid.size.width > 0)) return CGRectZero;
    double h = MSBDCC18TilesTop(panelTop) - panelTop + fmax(0.0, rowsH) + kMSBDCCPad;   // (a page with nothing on it: the top row and the margins)
    return CGRectMake(grid.origin.x - kMSBDCCPad, panelTop, grid.size.width + 2 * kMSBDCCPad, h);
}
// One of our pages open in the panel when the grid moves (the screen turned; statusbar/CC18Tiles.h): its frame -- the panel's place (panel: MSBDCC18PanelFrame's) and width, the page's own
// height h. NO when it cannot follow: no panel any more, or a panel of another width (a page is laid out at the width it opened at, as on 15-17 for Control Center Size): it closes then.
static inline int MSBDCC18PageFrame(CGRect panel, double openedWidth, double h, CGRect *out) {
    if (CGRectIsEmpty(panel) || !isfinite(h) || !(h > 0) || !(fabs(panel.size.width - openedWidth) <= 0.5)) return 0;
    if (out) *out = CGRectMake(panel.origin.x, panel.origin.y, panel.size.width, h);
    return 1;
}
// Apple's + (edit) and power buttons in the panel's top row (bw x bh each, Apple's): the leading one's (+) frame and the trailing one's (power), at
// the tiles' leading and trailing edges (the panel's margin in), centred in the row. In a right-to-left language Apple mirrors its own header:
// + at the right, power at the left.
static inline void MSBDCC18TopRowFrames(CGRect panel, double bw, double bh, int rtl, CGRect *edit, CGRect *power) {
    double y = panel.origin.y + kMSBDCCPad + (kMSBDCC18TopRow - bh) / 2.0;
    CGRect l = CGRectMake(panel.origin.x + kMSBDCCPad, y, bw, bh), r = CGRectMake(panel.origin.x + panel.size.width - kMSBDCCPad - bw, y, bw, bh);
    if (edit) *edit = rtl ? r : l;
    if (power) *power = rtl ? l : r;
}
// The width Apple's page control keeps beside the panel: its own, at most kMSBDCC18DotsMaxW (the dots are drawn in its middle).
static inline double MSBDCC18DotsWidth(double dw) { return isfinite(dw) && dw > 0 ? fmin(dw, kMSBDCC18DotsMaxW) : kMSBDCC18DotsMaxW; }
// Apple's page dots (dw x dh, dw from MSBDCC18DotsWidth) beside the panel, on its side away from the screen's edge (the left of it; the right in a
// right-to-left language), kMSBDCC18DotsGap off it, centred on the grid's rows (as Apple centres them on its content): their centre. Kept on the screen.
static inline CGPoint MSBDCC18DotsCenter(CGRect panel, CGRect grid, double dw, double dh, double boundsW, int rtl) {
    double x = rtl ? panel.origin.x + panel.size.width + kMSBDCC18DotsGap + dw / 2.0 : panel.origin.x - kMSBDCC18DotsGap - dw / 2.0;
    double y = grid.origin.y + grid.size.height / 2.0;
    if (isfinite(boundsW) && boundsW > dw) x = fmin(fmax(x, dw / 2.0), boundsW - dw / 2.0);
    if (isfinite(dh) && dh > 0 && y - dh / 2.0 < panel.origin.y) y = panel.origin.y + dh / 2.0;   // (never above the panel's top)
    return CGPointMake(x, y);
}
// Our material behind Apple's page dots (dw x dh, centred at dots): Apple draws them white for its darkening backdrop, which is hidden while the
// panel shows, so over a light window they all but vanished (Light Mode). A capsule of the dots' column -- kMSBDCC18DotsMaxW, never narrower
// than the control -- and the control's height, centred on them. Empty for nonsense.
static inline CGRect MSBDCC18DotsPillFrame(CGPoint dots, double dw, double dh) {
    if (!isfinite(dots.x) || !isfinite(dots.y) || !isfinite(dw) || !isfinite(dh) || !(dw > 0) || !(dh > 0)) return CGRectZero;
    double w = fmax(dw, kMSBDCC18DotsMaxW);
    return CGRectMake(dots.x - w / 2.0, dots.y - dh / 2.0, w, dh);
}
// A finger pull's presentation state past the full presentation (read on 18.5): its paging part (-pagingProgress, 0 to 1: how far the finger has
// gone on towards the page dots), by which Apple shrinks its pages as a paging hint (scale to 0.8, alpha to 0.7, about the screen's middle) and
// hands the pull to its paging, and its overshoot (progress past 1), by which Apple's module views rubber-band down (less as the paging part
// grows). In the panel nothing goes on past the full presentation, as the 15-17 panel's motion (MSBDCCMotion clamps the progress to 1): paging 0,
// progress at most 1; a dismissal's states and iPadOS's own Control Center keep Apple's. *progress and *paging are the state's; 1 when it is to
// be made again with them.
static inline int MSBDCC18PullState(int panel, int presentation, double *progress, double *paging) {
    if (!panel || !presentation || !progress || !paging) return 0;
    int again = !(*paging == 0.0) || *progress > 1.0;
    if (*progress > 1.0) *progress = 1.0;
    *paging = 0.0;
    return again;
}
// Apple's sensor attribution (the camera or the microphone in use, "Camera" with its two dots; 124 x 23 pt for the Camera app, 18.5) in the
// panel's top row, as macOS shows what uses them at the top of its Control Center: centred between Apple's + and power buttons (edit and power:
// their frames in the row's space, either side in a right-to-left language), kMSBDCC18SensorGap clear of them, at the size Apple gives it (w x h)
// or narrower where the room is less; its middle on the row's. Empty when it does not fit (less than kMSBDCC18SensorMinW) or for nonsense.
#define kMSBDCC18SensorGap 8.0
#define kMSBDCC18SensorMinW 20.0
static inline CGRect MSBDCC18SensorFrame(CGRect row, CGRect edit, CGRect power, double w, double h) {
    if (!isfinite(w) || !isfinite(h) || !(w > 0) || !(h > 0) || CGRectIsEmpty(row) || CGRectIsEmpty(edit) || CGRectIsEmpty(power)) return CGRectZero;
    double lo = fmin(CGRectGetMaxX(edit), CGRectGetMaxX(power)) + kMSBDCC18SensorGap, hi = fmax(CGRectGetMinX(edit), CGRectGetMinX(power)) - kMSBDCC18SensorGap;
    double room = hi - lo;
    if (!(room >= kMSBDCC18SensorMinW) || h > row.size.height) return CGRectZero;
    double fw = fmin(w, room);
    return CGRectMake((lo + hi) / 2.0 - fw / 2.0, CGRectGetMidY(row) - h / 2.0, fw, h);
}
// ... and its touches while the panel shows: on the control only within the panel's top row (Apple's header gives it 20 pt more on every side,
// -[CCUIHeaderPocketView hitTest:withEvent:] read on 18.5, which in the panel reached into the first row of tiles); none of the header's elsewhere.
static inline int MSBDCC18SensorTouch(int onControl, CGPoint p, CGRect row) { return onControl && CGRectContainsPoint(row, p); }
// Esc while the panel shows (a hardware keyboard): one level back -- what Apple counts as content it presents (a module open expanded, the sensor
// list, edit mode, its gallery; read on 18.5) is closed by Apple's own call --, else Control Center closes (as the 15-17 panel's page, then the
// close). Anything else presented over Control Center keeps the key.
enum { kMSBDCC18EscNone = 0, kMSBDCC18EscClosePresented = 1, kMSBDCC18EscClose = 2 };
static inline int MSBDCC18EscStep(int presentedContent, int overPresented) {
    if (presentedContent) return kMSBDCC18EscClosePresented;
    return overPresented ? kMSBDCC18EscNone : kMSBDCC18EscClose;
}
#endif
