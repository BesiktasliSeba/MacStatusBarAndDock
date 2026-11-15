// MacFolder.h -- the macOS folder (1.8.7.4 round 2, KT 14 Nov), included into StatusBar.x before Finder.h and Desktop.h: the one picture of a
// folder that the desktop's folders (Desktop.h -dm_folderImage) and Finder's (Finder.h DMFinderFolderPicture: the list, the icons, Quick Look,
// a drag, an app's folder in On My iPad with the app's icon on it) are drawn with. Moved here from Desktop.h as it was; Finder drew iPadOS's
// folder.fill symbol before, whose tab is cut off from the front by a clear line across the top.
// A crash in it is its caller's (crashmap-rules.txt: transparent), the desktop's or Finder's.
// A folder's icon, drawn the same on every iPad (not the Files app's icon, which a theme or iOS itself changes): a macOS folder,
// light blue, its darker tab and back behind, two folds near the bottom (y down, s = the icon's side, laid out on a 256 grid)
static void DMDesktopFolderFill(CGContextRef c, CGPathRef p, CGFloat k, int n, const CGFloat *ys, const unsigned *rgbs) {
    CGColorSpaceRef cs = CGColorSpaceCreateDeviceRGB();
    CGFloat comps[24], locs[6];
    for (int i = 0; i < n; i++) {
        comps[i * 4] = (rgbs[i] >> 16 & 0xFF) / 255.0; comps[i * 4 + 1] = (rgbs[i] >> 8 & 0xFF) / 255.0; comps[i * 4 + 2] = (rgbs[i] & 0xFF) / 255.0; comps[i * 4 + 3] = 1;
        locs[i] = (ys[i] - ys[0]) / (ys[n - 1] - ys[0]);
    }
    CGGradientRef g = CGGradientCreateWithColorComponents(cs, comps, locs, n);
    CGContextSaveGState(c); CGContextAddPath(c, p); CGContextClip(c);
    CGContextDrawLinearGradient(c, g, CGPointMake(0, ys[0] * k), CGPointMake(0, ys[n - 1] * k), kCGGradientDrawsBeforeStartLocation | kCGGradientDrawsAfterEndLocation);
    CGContextRestoreGState(c); CGGradientRelease(g); CGColorSpaceRelease(cs);
}
static __attribute__((noinline)) void DMDesktopDrawFolder(CGContextRef c, CGFloat s) {   // (out of line: tools/crashmap-rules.txt passes over it)
    CGFloat k = s / 256.0;
    CGPathRef front = CGPathCreateWithRoundedRect(CGRectMake(26 * k, 68 * k, 209 * k, 145.5 * k), 12.5 * k, 12.5 * k, NULL);
    // back: the tab and the panel behind the front
    CGMutablePathRef back = CGPathCreateMutable();
    CGPathMoveToPoint(back, NULL, 26 * k, 80 * k);
    CGPathAddLineToPoint(back, NULL, 26 * k, 49 * k);
    CGPathAddArcToPoint(back, NULL, 26 * k, 37.5 * k, 37.5 * k, 37.5 * k, 11.5 * k);
    CGPathAddLineToPoint(back, NULL, 85 * k, 37.5 * k);
    CGPathAddCurveToPoint(back, NULL, 98 * k, 37.5 * k, 103 * k, 54.3 * k, 117 * k, 54.3 * k);
    CGPathAddLineToPoint(back, NULL, 223.5 * k, 54.3 * k);
    CGPathAddArcToPoint(back, NULL, 235 * k, 54.3 * k, 235 * k, 66 * k, 11.5 * k);
    CGPathAddLineToPoint(back, NULL, 235 * k, 80 * k);
    CGPathCloseSubpath(back);
    DMDesktopFolderFill(c, back, k, 3, (const CGFloat[]){ 38, 52, 68 }, (const unsigned[]){ 0x41A2D6, 0x2F96D2, 0x007AC9 });
    // (its soft shadow all around -- no offset, which UIKit and Core Graphics turn opposite ways --, then its colours over it)
    CGContextSaveGState(c); CGContextSetShadowWithColor(c, CGSizeZero, 5 * k, [UIColor colorWithWhite:0 alpha:0.6].CGColor);
    CGContextAddPath(c, front); CGContextSetRGBFillColor(c, 0.31, 0.71, 0.91, 1); CGContextFillPath(c); CGContextRestoreGState(c);
    DMDesktopFolderFill(c, front, k, 5, (const CGFloat[]){ 68, 76, 188, 194, 213 }, (const unsigned[]){ 0x6CC9F6, 0x74CFFB, 0x70CDF9, 0x64C4F0, 0x50B6E8 });
    // the two folds near the bottom
    CGContextSaveGState(c); CGContextAddPath(c, front); CGContextClip(c);
    CGContextSetRGBFillColor(c, 0, 0.3, 0.55, 0.08);
    CGContextFillRect(c, CGRectMake(26 * k, 195 * k, 209 * k, 1.5 * k)); CGContextFillRect(c, CGRectMake(26 * k, 203.5 * k, 209 * k, 1.5 * k));
    CGContextSetRGBFillColor(c, 1, 1, 1, 0.14);
    CGContextFillRect(c, CGRectMake(26 * k, 193.5 * k, 209 * k, 1.5 * k)); CGContextFillRect(c, CGRectMake(26 * k, 202 * k, 209 * k, 1.5 * k));
    CGContextRestoreGState(c);
    CGPathRelease(front); CGPathRelease(back);
}
