// MSBAppSizesController.h: App Window Sizes (1.8.8), Settings > Windows & Multitasking, right under Window Size (MSBAppSizesController.m).
#import <Foundation/Foundation.h>

// The row's value on the Windows & Multitasking page: how many apps have a size of their own, as SpringBoard reads the stored list ("2 Apps",
// "1 App"; none: "", nothing shown).
NSString *MSBAppSizesRowValue(void);
