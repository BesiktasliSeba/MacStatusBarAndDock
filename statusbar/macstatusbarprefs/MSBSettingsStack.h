// MSBSettingsStack.h: a Settings page and its place in its navigation stack (1.8.8, App Window Sizes' Add App, MSBAppSizesController.m).
// On iPadOS 15 to 17 each page is itself an entry of the stack (UINavigationController's viewControllers). On 18 Settings' navigation is SwiftUI's:
// each page is the child of a hosting controller, and that hosting controller is the entry (A12Z 18.5, the Settings probe's vctree, 12 Nov:
// SwiftUI.UIKitNavigationController > NavigationStackHostingController<AnyView> > PSGGeneralController, then one each around
// MSBWindowsListController, MSBAppSizesController and AltList's picker). A page is compared with the stack only through these two, so the same code
// reads both shapes. Imported after UIKit (or after the Mac test's stand-ins: tools/test-appsizestack.m runs them on stacks of both shapes).

// The stack's entry that holds the page: the page itself (15 to 17), or the controller around it whose parent is the navigation controller (18).
// A page in no stack gives its outermost parent, which is no entry of nav.
static inline UIViewController *MSBSSEntryOf(UIViewController *page, UINavigationController *nav) {
	UIViewController *e = page;
	while (e.parentViewController && e.parentViewController != nav) e = e.parentViewController;
	return e;
}

// The page of that class an entry holds: the entry itself (15 to 17), or the one inside it (18: the hosting controller's child). Nil for none.
static inline id MSBSSPageIn(UIViewController *entry, Class cls) {
	if (!entry || !cls) return nil;
	if ([entry isKindOfClass:cls]) return entry;
	for (UIViewController *child in entry.childViewControllers) {
		id page = MSBSSPageIn(child, cls);
		if (page) return page;
	}
	return nil;
}
