// SliderCells.h -- Settings' slider rows (PSSliderCell) on our own pages: the Status Bar and Desktop pages (statusbar/macstatusbarprefs/
// MSBRootListController.m) and the Dock page (dock/dockmagnificationprefs/DMRootListController.m), from each page's
// -tableView:cellForRowAtIndexPath:, after Settings has set the cell up. Tested by tools/test-dockcolor.sh (test-dockcolorpage.m, run as it is).
#pragma once
#import <UIKit/UIKit.h>
#import <objc/runtime.h>

// The stock slider cell's value label is a little too narrow for two decimals on iPadOS 16: "0.70" showed as "0.7C" (iPad 2 cross-test, both
// sliders; the Dock page's Dock Background opacity the same in a Settings window about 510 pt wide, the 1.8.7.6~b01 pass). The label keeps its place and size;
// its text shrinks a touch when it would not fit.
static inline void MSBDFitValueLabels(UIView *v) {
	for (UIView *sub in v.subviews) {
		if ([sub isKindOfClass:[UILabel class]]) {
			UILabel *l = (UILabel *)sub;
			NSString *t = l.text ?: @"";
			if (t.length && [t rangeOfCharacterFromSet:[[NSCharacterSet characterSetWithCharactersInString:@"0123456789.,-"] invertedSet]].location == NSNotFound) {
				l.adjustsFontSizeToFitWidth = YES; l.minimumScaleFactor = 0.6;
			}
		}
		MSBDFitValueLabels(sub);
	}
}

// PSSliderCell leaves its UISlider not continuous on iPadOS 15 to 18 whatever the row's isContinuous in the plist says: the knob and the value label
// follow the finger, but the value is written (-setPreferenceValue:specifier:) only when it lifts. A row whose value must go out while it is dragged
// (the desktop's Icon Size since 1.7.5 and App Icon Corner Radius, the Dock's Dock Background opacity since 1.8.8.1) passes live YES: its slider is
// made continuous. Cells are reused for any row of their kind, so every other slider row passes NO: a cell that had a live row gets its slider's own
// setting back, and one that never had one is left as Settings made it. The own setting is taken on the live row, so no slider row of ours carries
// isContinuous in its plist: a Settings that took it would make that YES the setting given back to the page's other sliders.
static inline void MSBDSliderCellContinuous(UIView *cell, BOOL live) {
	static char kOwnContinuous;   // (the slider's own setting, kept while a live row has it)
	NSMutableArray *views = [NSMutableArray arrayWithObject:cell];
	for (NSUInteger k = 0; k < views.count && k < 80; k++) {
		UIView *v = views[k];
		if (![v isKindOfClass:[UISlider class]]) { [views addObjectsFromArray:v.subviews]; continue; }
		UISlider *s = (UISlider *)v;
		NSNumber *own = objc_getAssociatedObject(s, &kOwnContinuous);
		if (live) {
			if (!own) objc_setAssociatedObject(s, &kOwnContinuous, @(s.continuous), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
			s.continuous = YES;
		} else if (own) {
			s.continuous = own.boolValue;
			objc_setAssociatedObject(s, &kOwnContinuous, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
		}
	}
}
