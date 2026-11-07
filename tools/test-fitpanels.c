// test-fitpanels.c -- Mac test of statusbar/FitQuestionPlace.h (1.8.3 item 6): Fit to Window's question panels are the windows' frames 12 pt in, the
// same on every engine. Numbers as read on the iPad 2 (16.7.7, landscape 1024 x 768, Dock at Left; regression-1.8.2.2-ipad2.md F1). Run by
// test-fitpanels.sh.
#include <stdio.h>
#include <math.h>
#include "../statusbar/FitQuestionPlace.h"
static int fails = 0, checks = 0;
static int near(double a, double b) { return fabs(a - b) < 0.01; }
static int same(CGRect a, CGRect b) { return near(a.origin.x, b.origin.x) && near(a.origin.y, b.origin.y) && near(a.size.width, b.size.width) && near(a.size.height, b.size.height); }
static void Frame(const char *what, CGRect got, CGRect want) {
    checks++;
    if (same(got, want)) printf("PASS  %s\n", what);
    else { fails++; printf("FAIL  %s (got {%.2f, %.2f, %.2f, %.2f}, want {%.2f, %.2f, %.2f, %.2f})\n", what, got.origin.x, got.origin.y, got.size.width, got.size.height, want.origin.x, want.origin.y, want.size.width, want.size.height); }
}
static void Yes(const char *what, int ok) { checks++; if (ok) printf("PASS  %s\n", what); else { fails++; printf("FAIL  %s\n", what); } }
// Aerial 5.x's stage for a window (StatusBar.x DMA5StageFromWindow with its measured margins 13 / 6 / 20 / 6 and the 11 pt shift): the engine's frame the
// panels were cut from before 1.8.3, kept here only to show the difference it made.
static CGRect A5Stage(CGRect w) { return CGRectMake(w.origin.x - 6.0, w.origin.y + 24.0 - 13.0 - 11.0, w.size.width + 12.0, w.size.height - 24.0 + 13.0 + 20.0); }
int main(void) {
    CGRect left = CGRectMake(56.5, 20, 480, 748), right = CGRectMake(542.5, 20, 481.5, 748), fill = CGRectMake(56.5, 20, 967.5, 748);
    Frame("Left: the window's frame 12 pt in (Stage Manager's panel, F1)", MSBDFitQuestionPanel(left), CGRectMake(68.5, 32, 456, 724));
    Frame("Right: the same rule", MSBDFitQuestionPanel(right), CGRectMake(554.5, 32, 457.5, 724));
    Yes("Aerial 5.x: the panel from its stage was the other engines' one grown 6 pt at each side and 9 pt below (the cause)",
        same(MSBDFitQuestionPanel(A5Stage(left)), CGRectMake(62.5, 32, 468, 733)));
    Yes("  ... from the window it is Stage Manager's exactly", same(MSBDFitQuestionPanel(left), CGRectMake(68.5, 32, 456, 724)));
    Yes("the title: 16 pt under the desktop's top", near(MSBDFitQuestionTitleY(fill), 36.0));
    Yes("  ... the same from the stage's top (the title matched already)", near(MSBDFitQuestionTitleY(A5Stage(fill)), 36.0));
    Yes("no layout frame: no panel", CGRectIsNull(MSBDFitQuestionPanel(CGRectNull)));
    Yes("an empty frame: no panel", CGRectIsNull(MSBDFitQuestionPanel(CGRectMake(10, 10, 0, 300))));
    printf("%d checks, %d failed\n", checks, fails);
    return fails ? 1 : 0;
}
