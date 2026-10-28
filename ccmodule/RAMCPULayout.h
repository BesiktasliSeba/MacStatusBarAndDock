// RAMCPULayout.h -- where RAM & CPU's tile puts its lines (1.6.0): plain C, run by the Mac test tools/test-ccmodule.sh.
// Control Center gives the module the 2 x 1 tile it asks for (142 x 66 on the iPad 2, 16.7.7). BigSurCenter (15/16) puts every module in a square
// tile of its own, 75 x 75, whatever size the module asks for: laid out for 2 x 1 there, every line was cut to "..." (iPad 2, 16.7.7). A tile that
// is not clearly wider than tall gets the square layout: the available memory over the CPU load, as the tile drawn over Memory Magic's has them.
#include <CoreGraphics/CoreGraphics.h>

static inline int MSBDRAMCPUSquare(CGSize s) { return s.width < s.height * 1.5; }

enum { kRCRamValue, kRCRamCaption, kRCUsed, kRCCpuValue, kRCCpuCaption, kRCDivider, kRCCount };
// out[kRCCount]: each line's frame in the tile's own points (an empty one is not shown in that layout)
static inline void MSBDRAMCPUFrames(CGRect b, CGRect *out) {
    for (int i = 0; i < kRCCount; i++) out[i] = CGRectMake(0, 0, 0, 0);
    CGFloat w = b.size.width, h = b.size.height;
    if (MSBDRAMCPUSquare(b.size)) {   // (square: "RAM AVAILABLE" and its value, a thin line, "CPU USED" and its value -- 10 points in from each side)
        CGFloat x = 10.0, lw = w - 20.0, half = (h - 12.0) / 2.0;
        out[kRCRamCaption] = CGRectMake(x, 7.0, lw, 10.0);
        out[kRCRamValue] = CGRectMake(x, 16.0, lw, 18.0);
        out[kRCDivider] = CGRectMake(x, 7.0 + half + 0.5, lw, 0.5);
        out[kRCCpuCaption] = CGRectMake(x, 7.0 + half + 5.0, lw, 10.0);
        out[kRCCpuValue] = CGRectMake(x, 7.0 + half + 14.0, lw, 18.0);
        return;
    }
    // 2 x 1 (iPadOS 18's is a pill: the round ends need the inset): the memory on the left, the CPU on the right
    CGFloat inset = h * 0.26 < 10.0 ? 10.0 : (h * 0.26 > 18.0 ? 18.0 : h * 0.26), iw = w - 2.0 * inset;
    CGFloat cpuW = iw * 0.38 < 52.0 ? iw * 0.38 : 52.0, memW = iw - cpuW - 6.0, top = (h - 46.0) / 2.0 > 4.0 ? (h - 46.0) / 2.0 : 4.0;
    out[kRCRamValue] = CGRectMake(inset, top, memW, 21.0);
    out[kRCRamCaption] = CGRectMake(inset, top + 21.0, memW, 12.0);
    out[kRCUsed] = CGRectMake(inset, top + 33.0, memW, 12.0);
    out[kRCCpuValue] = CGRectMake(w - inset - cpuW, top, cpuW, 21.0);
    out[kRCCpuCaption] = CGRectMake(w - inset - cpuW, top + 21.0, cpuW, 12.0);
}
