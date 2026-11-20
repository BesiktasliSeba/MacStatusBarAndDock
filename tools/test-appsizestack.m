// test-appsizestack.m: App Window Sizes' Add App on the navigation stack Settings builds on iPadOS 15 to 17 and on 18 (1.8.8, F1: on the A12Z's
// 18.5 a pick in AltList's picker only checked the app and the picker stayed; S1-F1: F1's fix, the picker popped with no slide and the page pushed
// in the same turn, left two empty NavigationStackHostingControllers on 18.5's stack, row E1 of p03). Built and run by tools/test-appwindowsize.sh
// with stand-ins for UIKit's and Preferences' controllers: the list's tableView:didSelectRowAtIndexPath:, msbPickedApp:specifier:, msbPickerOnTop,
// msbOpenPickedNextTurn, msbOpenPickedWhenSettled, msbAfter:then:, msbOpenAppPage: and viewDidAppear:, and the app page's msbRemoveApp:, are
// pasted from MSBAppSizesController.m as written (appsizestack-list.inc, appsizestack-page.inc), beside MSBSettingsStack.h. Four stack shapes:
//  - 15-17 (plain): each page is an entry of the stack;
//  - 18 (hosted): each page is the child of a hosting controller, the stack's entry, as the Settings probe's vctree read it on the A12Z (12 Nov:
//    SwiftUI.UIKitNavigationController > NavigationStackHostingController<AnyView> > PSGGeneralController, MSBWindowsListController,
//    MSBAppSizesController, ATLApplicationListSelectionController, each in its own);
//  - 18 (hosted, two deep): one more controller between the entry and the page, should SwiftUI put one there;
//  - 18 (SwiftUI's record): the hosted stack with SwiftUI's own record of it (the s1f1 harness on the Mac's macCatalyst 18.7 SwiftUI, and E1):
//    Settings' push appends the page to the record and hosts it at once, and on the next turn UIKit's stack is set to the hosts of the record as it
//    was at the push; a UIKit pop changes UIKit's stack at once, and the record takes it in later (at the slide's start with a slide, right after
//    the new top's viewDidAppear with none), taking the pages past the stack's count at the pop out of their hosts. A push recorded while the record
//    still holds a popped page leaves E1's shape: hosts with no page on the stack, record and stack out of step.
// A push or a pop with no slide shows its new top on the next turn (viewDidAppear, passed down to the hosted page as containment does); a pop with
// a slide runs until the test ends it (a transition coordinator meanwhile, whose completions run at its end, then the new top's viewDidAppear).
// Every main-queue block is a turn of its own, numbered (the pasted code's dispatch_async and dispatch_after go through the numbering), so a push in
// the same turn as a pop is seen. Checks named "seen:" are what the user sees (the stack, empty hosts); the others the way there. Exit 0 when every
// check passes.
#import <Foundation/Foundation.h>
#import <objc/runtime.h>
#import <objc/message.h>

static int fails = 0, checks = 0;
static void ok(BOOL c, NSString *what) { checks++; if (!c) { fails++; printf("FAIL: %s\n", what.UTF8String); } }

// ---- the turns ----
static int gTurn;
static void MSBTAsync(dispatch_queue_t q, dispatch_block_t b) { dispatch_async(q, ^{ gTurn++; b(); }); }
static void MSBTAfter(dispatch_time_t t, dispatch_queue_t q, dispatch_block_t b) { dispatch_after(t, q, ^{ gTurn++; b(); }); }

// ---- stand-ins: UIKit ----
@protocol UIViewControllerTransitionCoordinatorContext <NSObject>
@end
@protocol UIViewControllerTransitionCoordinator <UIViewControllerTransitionCoordinatorContext>
- (BOOL)animateAlongsideTransition:(void (^)(id<UIViewControllerTransitionCoordinatorContext> context))animation completion:(void (^)(id<UIViewControllerTransitionCoordinatorContext> context))completion;
@end
// A transition running: the completions it took run at its end. One that refuses takes none (NO), as UIKit's may. A push's or a pop's slide
// shows the new top at its end (its viewDidAppear); another transition (a rotation, a push still ending) shows nothing new.
@interface MSBTCoordinator : NSObject <UIViewControllerTransitionCoordinator>
@property (nonatomic, strong) NSMutableArray *completions;
@property (nonatomic, assign) BOOL refuses, shows;
- (void)msbtEnd;
@end
@implementation MSBTCoordinator
- (instancetype)init { if ((self = [super init])) _completions = [NSMutableArray array]; return self; }
- (BOOL)animateAlongsideTransition:(void (^)(id<UIViewControllerTransitionCoordinatorContext>))animation completion:(void (^)(id<UIViewControllerTransitionCoordinatorContext>))completion {
	if (_refuses) return NO;
	if (completion) [_completions addObject:[completion copy]];
	return YES;
}
- (void)msbtEnd { NSArray *c = [_completions copy]; [_completions removeAllObjects]; for (void (^b)(id) in c) b(self); }
@end
@interface MSBTView : NSObject
@property (nonatomic, strong) id window;
@end
@implementation MSBTView
@end
@interface UITableView : NSObject
@end
@implementation UITableView
@end
@class UINavigationController;
@interface UIViewController : NSObject
@property (nonatomic, weak) UIViewController *parentViewController;
@property (nonatomic, strong, readonly) NSMutableArray<UIViewController *> *kids;
@property (nonatomic, strong, readonly) MSBTView *view;
@property (nonatomic, strong) MSBTCoordinator *msbtPresenting;   // a presentation of its own running (the picker's search closing)
@property (nonatomic, readonly) id<UIViewControllerTransitionCoordinator> transitionCoordinator;   // its own presentation's, else its parent's
- (NSArray<UIViewController *> *)childViewControllers;
- (UINavigationController *)navigationController;
- (void)viewDidAppear:(BOOL)animated;
- (void)msbtAdopt:(UIViewController *)child;
- (void)msbtOutOfParent;
@end
@interface UINavigationController : UIViewController
@property (nonatomic, strong) NSMutableArray<UIViewController *> *viewControllers;
@property (nonatomic, strong) NSMutableArray<NSString *> *calls;   // the pushes and pops, in order
@property (nonatomic, strong) NSMutableArray<NSNumber *> *turns;   // the turn of each
@property (nonatomic, strong) NSMutableArray<UIViewController *> *record;   // 18 (SwiftUI's record): the pages SwiftUI holds, from the root
@property (nonatomic, strong) NSMutableArray<UIViewController *> *recordHosts;   // ... and the host of each
- (UIViewController *)topViewController;
- (UIViewController *)popViewControllerAnimated:(BOOL)animated;
- (NSArray *)popToViewController:(UIViewController *)vc animated:(BOOL)animated;
- (void)setViewControllers:(NSArray *)vcs animated:(BOOL)animated;
- (void)msbtPush:(UIViewController *)page;
- (void)msbtPushNow:(UIViewController *)page;
- (MSBTCoordinator *)msbtBeginTransition;
- (void)msbtEndTransition;
- (void)msbtClear;
@end
@implementation UIViewController
- (instancetype)init { if ((self = [super init])) { _kids = [NSMutableArray array]; _view = [MSBTView new]; } return self; }
- (NSArray<UIViewController *> *)childViewControllers { return [_kids copy]; }
- (UINavigationController *)navigationController {
	for (UIViewController *p = self.parentViewController; p; p = p.parentViewController) if ([p isKindOfClass:[UINavigationController class]]) return (UINavigationController *)p;
	return nil;
}
- (id<UIViewControllerTransitionCoordinator>)transitionCoordinator { return _msbtPresenting ?: self.parentViewController.transitionCoordinator; }
- (void)viewDidAppear:(BOOL)animated {}
- (void)msbtAdopt:(UIViewController *)child { [_kids addObject:child]; child.parentViewController = self; }
- (void)msbtOutOfParent { UIViewController *p = self.parentViewController; self.parentViewController = nil; [p.kids removeObjectIdenticalTo:self]; }
@end
// 18's hosting controller (NavigationStackHostingController), the stack's entry; and the controller a deeper shape puts between it and the page
@interface MSBTHost : UIViewController
@end
@implementation MSBTHost
@end
@interface MSBTBetween : UIViewController
@end
@implementation MSBTBetween
@end
static int gShape;   // 0 = 15-17 (plain), 1 = 18 (hosted), 2 = 18 (hosted, two deep), 3 = 18 (SwiftUI's record)
static BOOL gLate;   // shape 3 only: the record takes a pop with a slide in only one frame after the slide's end (fix 7a's limit)
static NSString *MSBTShape(void) { return gShape == 0 ? @"15-17 (plain)" : gShape == 1 ? @"18 (hosted)" : gShape == 2 ? @"18 (hosted, two deep)" : gLate ? @"18 (SwiftUI's record, late)" : @"18 (SwiftUI's record)"; }
static NSString *MSBTName(UIViewController *entry);
static void MSBTShown(UIViewController *vc, BOOL on) { vc.view.window = on ? @1 : nil; for (UIViewController *c in vc.childViewControllers) MSBTShown(c, on); }
static void MSBTAppear(UIViewController *vc) { [vc viewDidAppear:YES]; for (UIViewController *c in vc.childViewControllers) MSBTAppear(c); }

@implementation UINavigationController {
	MSBTCoordinator *_moving;
	NSMutableArray<UIViewController *> *_leaving;   // the entries a running slide takes off
	NSInteger _lateTakeIn;   // shape 3, late: the count a slide's pop leaves, taken in one frame after the slide's end (-1: none)
}
- (instancetype)init {
	if ((self = [super init])) {
		_viewControllers = [NSMutableArray array]; _calls = [NSMutableArray array]; _turns = [NSMutableArray array];
		_record = [NSMutableArray array]; _recordHosts = [NSMutableArray array]; _leaving = [NSMutableArray array]; _lateTakeIn = -1;
		self.view.window = @1;
	}
	return self;
}
- (id<UIViewControllerTransitionCoordinator>)transitionCoordinator { return _moving ?: [super transitionCoordinator]; }
- (UIViewController *)topViewController { return _viewControllers.lastObject; }
- (void)msbtCall:(NSString *)what { [_calls addObject:what]; [_turns addObject:@(gTurn)]; }
- (void)msbtClear { [_calls removeAllObjects]; [_turns removeAllObjects]; }
// The new top shown: at once (its viewDidAppear on the next turn, if it is still the top then, and on SwiftUI's record the pop taken in right after
// it), or with a slide that runs until the test ends it
- (void)msbtShowTop:(BOOL)slide takeIn:(NSInteger)count {
	for (UIViewController *e in _viewControllers) MSBTShown(e, e == _viewControllers.lastObject);
	if (slide) {
		_moving = [MSBTCoordinator new]; _moving.shows = YES;
		if (count >= 0 && gLate) _lateTakeIn = count;
		else if (count >= 0) { __weak UINavigationController *weakSelf = self; MSBTAsync(dispatch_get_main_queue(), ^{ [weakSelf msbtTakeIn:count]; }); }   // (the slide's start)
		return;
	}
	UIViewController *top = _viewControllers.lastObject;
	__weak UINavigationController *weakSelf = self;
	MSBTAsync(dispatch_get_main_queue(), ^{
		if (top && weakSelf.topViewController == top && !weakSelf.transitionCoordinator) MSBTAppear(top);
		if (count >= 0) [weakSelf msbtTakeIn:count];
	});
}
// SwiftUI's record takes a pop in: the pages past the count UIKit's stack had after the pop are taken out of their hosts (shape 3)
- (void)msbtTakeIn:(NSInteger)count {
	while ((NSInteger)_record.count > count) {
		[_record.lastObject msbtOutOfParent];
		[_record removeLastObject]; [_recordHosts removeLastObject];
	}
}
// The entries a pop takes off: out of the stack at once with no slide, at the slide's end with one
- (void)msbtTakeOff:(NSArray *)gone slide:(BOOL)slide {
	for (UIViewController *e in gone) { MSBTShown(e, NO); if (slide) [_leaving addObject:e]; else e.parentViewController = nil; }
}
- (MSBTCoordinator *)msbtBeginTransition { _moving = [MSBTCoordinator new]; return _moving; }   // (another transition: a push still ending, a rotation)
- (void)msbtEndTransition {
	if (!_moving) return;
	gTurn++;
	MSBTCoordinator *c = _moving; _moving = nil;
	for (UIViewController *e in _leaving) e.parentViewController = nil;
	[_leaving removeAllObjects];
	if (_lateTakeIn >= 0) {   // (one frame after the slide's end)
		NSInteger n = _lateTakeIn; _lateTakeIn = -1; __weak UINavigationController *weakSelf = self;
		MSBTAfter(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.016 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{ [weakSelf msbtTakeIn:n]; });
	}
	[c msbtEnd];
	if (c.shows && _viewControllers.lastObject) MSBTAppear(_viewControllers.lastObject);
}
// A page in the shape's entry: itself (15-17), or inside a hosting controller (18), with a controller between (two deep)
- (UIViewController *)msbtEntryFor:(UIViewController *)page {
	if (!gShape) return page;
	UIViewController *entry = [MSBTHost new], *holder = entry;
	if (gShape == 2) { holder = [MSBTBetween new]; [entry msbtAdopt:holder]; }
	[holder msbtAdopt:page];
	return entry;
}
// A page pushed as Settings pushes it in this shape. 15-17 and 18 (hosted): onto the stack at once. 18 (SwiftUI's record): appended to the record
// and hosted at once; UIKit's stack set to the record's hosts as they were here on the next turn.
- (void)msbtPush:(UIViewController *)page {
	[self msbtCall:[@"push " stringByAppendingString:MSBTName(page)]];
	UIViewController *entry = [self msbtEntryFor:page];
	if (gShape != 3) {
		entry.parentViewController = self;
		[_viewControllers addObject:entry];
		[self msbtShowTop:NO takeIn:-1];
		return;
	}
	[_record addObject:page]; [_recordHosts addObject:entry];
	NSArray *hosts = [_recordHosts copy];
	__weak UINavigationController *weakSelf = self;
	MSBTAsync(dispatch_get_main_queue(), ^{ [weakSelf msbtSetStack:hosts]; });
}
- (void)msbtSetStack:(NSArray *)hosts {
	for (UIViewController *e in _viewControllers) if (![hosts containsObject:e]) e.parentViewController = nil;
	_viewControllers = [hosts mutableCopy];
	for (UIViewController *e in hosts) e.parentViewController = self;
	[self msbtShowTop:NO takeIn:-1];
}
// The test's own: another page shown over the top at once, in every shape
- (void)msbtPushNow:(UIViewController *)page {
	[self msbtCall:[@"push " stringByAppendingString:MSBTName(page)]];
	UIViewController *entry = [self msbtEntryFor:page];
	if (gShape == 3) { [_record addObject:page]; [_recordHosts addObject:entry]; }
	entry.parentViewController = self;
	[_viewControllers addObject:entry];
	[self msbtShowTop:NO takeIn:-1];
}
- (UIViewController *)popViewControllerAnimated:(BOOL)animated {
	if (_viewControllers.count < 2) return nil;
	UIViewController *top = _viewControllers.lastObject;
	[_viewControllers removeLastObject];
	[self msbtCall:[NSString stringWithFormat:@"pop%@ %@", animated ? @" animated" : @"", MSBTName(top)]];
	[self msbtTakeOff:@[top] slide:animated];
	[self msbtShowTop:animated takeIn:gShape == 3 ? (NSInteger)_viewControllers.count : -1];
	return top;
}
- (NSArray *)popToViewController:(UIViewController *)vc animated:(BOOL)animated {
	NSUInteger i = [_viewControllers indexOfObjectIdenticalTo:vc];
	if (i == NSNotFound) { [self msbtCall:@"popTo (not in the stack)"]; return nil; }
	NSRange gone = NSMakeRange(i + 1, _viewControllers.count - i - 1);
	NSArray *out = [_viewControllers subarrayWithRange:gone];
	[_viewControllers removeObjectsInRange:gone];
	[self msbtCall:[NSString stringWithFormat:@"popTo%@ %@", animated ? @" animated" : @"", MSBTName(vc)]];
	[self msbtTakeOff:out slide:animated];
	[self msbtShowTop:animated takeIn:gShape == 3 ? (NSInteger)_viewControllers.count : -1];
	return out;
}
// UIKit's stack replaced as given; SwiftUI's record is not told (the s1f1 harness's D: the page lands raw, the picker's entry stays in the record)
- (void)setViewControllers:(NSArray *)vcs animated:(BOOL)animated {
	NSMutableArray *names = [NSMutableArray array];
	for (UIViewController *e in vcs) [names addObject:MSBTName(e)];
	[self msbtCall:[@"set " stringByAppendingString:[names componentsJoinedByString:@", "]]];
	NSMutableArray *gone = [NSMutableArray array];
	for (UIViewController *e in _viewControllers) if (![vcs containsObject:e]) [gone addObject:e];
	_viewControllers = [vcs mutableCopy];
	for (UIViewController *e in vcs) e.parentViewController = self;
	[self msbtTakeOff:gone slide:animated];
	[self msbtShowTop:animated takeIn:-1];
}
@end

// ---- stand-ins: Preferences ----
enum { PSLinkCell = 1, PSLinkListCell = 2 };
@interface PSSpecifier : NSObject
@property (nonatomic, strong) NSMutableDictionary *props;
@property (nonatomic, assign) Class detailControllerClass;
@property (nonatomic, copy) NSString *identifier;
+ (instancetype)preferenceSpecifierNamed:(NSString *)name target:(id)target set:(SEL)set get:(SEL)get detail:(Class)detail cell:(long)cell edit:(Class)edit;
- (void)setProperty:(id)value forKey:(NSString *)key;
- (id)propertyForKey:(NSString *)key;
@end
@implementation PSSpecifier
+ (instancetype)preferenceSpecifierNamed:(NSString *)name target:(id)target set:(SEL)set get:(SEL)get detail:(Class)detail cell:(long)cell edit:(Class)edit {
	PSSpecifier *s = [self new]; s.props = [NSMutableDictionary dictionary]; s.detailControllerClass = detail; return s;
}
- (void)setProperty:(id)value forKey:(NSString *)key { if (value) _props[key] = value; else [_props removeObjectForKey:key]; }
- (id)propertyForKey:(NSString *)key { return _props[key]; }
@end
@class PSListController;
static PSSpecifier *MSBASSpecAt(PSListController *c, NSIndexPath *ip);
@interface PSListController : UIViewController
@property (nonatomic, strong) PSSpecifier *specifier;
- (id)controllerForSpecifier:(PSSpecifier *)spec;
- (void)showController:(UIViewController *)c animate:(BOOL)animate;
- (void)tableView:(UITableView *)tv didSelectRowAtIndexPath:(NSIndexPath *)ip;
@end
@compatibility_alias PSViewController PSListController;
@implementation PSListController
- (id)controllerForSpecifier:(PSSpecifier *)spec { PSListController *c = [[spec detailControllerClass] new]; c.specifier = spec; return c; }
- (void)showController:(UIViewController *)c animate:(BOOL)animate { [self.navigationController msbtPush:c]; }
- (void)tableView:(UITableView *)tv didSelectRowAtIndexPath:(NSIndexPath *)ip {   // (Preferences: a link row's page pushed)
	PSSpecifier *s = MSBASSpecAt(self, ip);
	if (s.detailControllerClass) [self showController:[self controllerForSpecifier:s] animate:YES];
}
@end
@interface MSBTGeneral : PSListController   // (General)
@end
@implementation MSBTGeneral
@end
@interface MSBTWindows : PSListController   // (Windows & Multitasking)
@end
@implementation MSBTWindows
@end
@interface MSBTPicker : PSListController   // (AltList's ATLApplicationListSelectionController)
@end
@implementation MSBTPicker
@end
@interface MSBTOther : PSListController   // (another page over the list)
@end
@implementation MSBTOther
@end

// ---- what the pasted methods call ----
static NSString *const kMSBASBundleKey = @"msbBundle";
enum { MSBDAppSizeNone = -1 };
static NSMutableArray<NSString *> *gLog, *gWrites;
static void MSBASLog(NSString *line) { [gLog addObject:line]; }
static void MSBASWrite(NSString *bundle, int choice) { [gWrites addObject:[NSString stringWithFormat:@"%@ %d", bundle, choice]]; }
static NSString *MSBASAppName(NSString *bundle) { return bundle; }
static Class MSBASPickerClass(void) { return [MSBTPicker class]; }
#import "MSBSettingsStack.h"

@interface MSBAppSizeController : PSListController
- (NSString *)msbBundle;
@end
@interface MSBAppSizesController : PSListController
- (void)msbPickedApp:(id)value specifier:(PSSpecifier *)spec;
- (BOOL)msbPickerOnTop;
- (void)msbOpenAppPage:(NSString *)bundle;
@end
// The list's rows the test taps: 0 Clock's row (a listed app, its page), 1 Add App (AltList's picker)
static PSSpecifier *MSBASSpecAt(PSListController *c, NSIndexPath *ip) {
	NSUInteger row = [ip indexAtPosition:0];
	PSSpecifier *s = [PSSpecifier preferenceSpecifierNamed:nil target:c set:NULL get:NULL detail:row ? [MSBTPicker class] : [MSBAppSizeController class] cell:PSLinkListCell edit:Nil];
	s.identifier = row ? @"APP_SIZES_ADD" : @"APP_SIZE_com.apple.mobiletimer";
	if (!row) [s setProperty:@"com.apple.mobiletimer" forKey:kMSBASBundleKey];
	return s;
}
#define dispatch_async MSBTAsync
#define dispatch_after MSBTAfter
@implementation MSBAppSizeController
- (NSString *)msbBundle { id b = [self.specifier propertyForKey:kMSBASBundleKey]; return [b isKindOfClass:[NSString class]] && [b length] ? b : nil; }
#include "appsizestack-page.inc"
@end
@implementation MSBAppSizesController {
	NSString *_picked;
	BOOL _pickOpen;
	__weak UIViewController *_closedPicker;
}
#include "appsizestack-list.inc"
@end
#undef dispatch_async
#undef dispatch_after

// ---- the test's own reading of a stack (not the code under test) ----
static UIViewController *MSBTPageOf(UIViewController *entry) {   // (the page an entry holds, by the stand-ins' own shape; nil for an empty host)
	while ([entry isKindOfClass:[MSBTHost class]] || [entry isKindOfClass:[MSBTBetween class]]) entry = entry.childViewControllers.firstObject;
	return entry;
}
static NSString *MSBTName(UIViewController *entry) {
	UIViewController *p = MSBTPageOf(entry);
	if (!p) return @"empty host";
	if ([p isKindOfClass:[MSBAppSizeController class]]) return [NSString stringWithFormat:@"page(%@)", [(MSBAppSizeController *)p msbBundle]];
	if ([p isKindOfClass:[MSBTPicker class]]) return @"picker";
	if ([p isKindOfClass:[MSBAppSizesController class]]) return @"list";
	if ([p isKindOfClass:[MSBTWindows class]]) return @"windows";
	if ([p isKindOfClass:[MSBTGeneral class]]) return @"general";
	if ([p isKindOfClass:[MSBTOther class]]) return @"other";
	return NSStringFromClass([p class]);
}
static NSString *MSBTStack(UINavigationController *nav) {   // ("general, windows, list, page(com.apple.calculator)")
	NSMutableArray *n = [NSMutableArray array];
	for (UIViewController *e in nav.viewControllers) [n addObject:MSBTName(e)];
	return [n componentsJoinedByString:@", "];
}
static NSString *MSBTCalls(UINavigationController *nav) { return [nav.calls componentsJoinedByString:@"; "]; }
static int MSBTEmptyHosts(UINavigationController *nav) { int n = 0; for (UIViewController *e in nav.viewControllers) if (!MSBTPageOf(e)) n++; return n; }
static BOOL MSBTRecordIsStack(UINavigationController *nav) {   // (SwiftUI's record and UIKit's stack the same: each entry hosts its record's page)
	if (gShape != 3) return YES;
	if (nav.record.count != nav.viewControllers.count) return NO;
	for (NSUInteger i = 0; i < nav.record.count; i++) if (MSBTPageOf(nav.viewControllers[i]) != nav.record[i]) return NO;
	return YES;
}
static NSString *MSBTSeenStack(UINavigationController *nav) {   // (the stack, its empty hosts and the record, on one line)
	return [NSString stringWithFormat:@"%@ | empty hosts %d | record %@", MSBTStack(nav), MSBTEmptyHosts(nav), MSBTRecordIsStack(nav) ? @"= stack" : [NSString stringWithFormat:@"%lu entries", (unsigned long)nav.record.count]];
}
static NSString *MSBTSeenOK(NSString *stack) { return [stack stringByAppendingString:@" | empty hosts 0 | record = stack"]; }
static NSString *MSBTPopPush(UINavigationController *nav) {   // (a push in the same turn as a pop before it: the two, or nil)
	for (NSUInteger i = 0; i < nav.calls.count; i++) for (NSUInteger j = i + 1; j < nav.calls.count; j++)
		if ([nav.calls[i] hasPrefix:@"pop"] && [nav.calls[j] hasPrefix:@"push"] && [nav.turns[i] isEqual:nav.turns[j]]) return [NSString stringWithFormat:@"%@ then %@", nav.calls[i], nav.calls[j]];
	return nil;
}
static NSUInteger MSBTLogged(NSString *prefix) { NSUInteger n = 0; for (NSString *l in gLog) if ([l hasPrefix:prefix]) n++; return n; }
// The main queue's next turns, until it has none left (a block queued here is on the main queue's port at once, so an idle run loop means none);
// MSBTWait for a time, for the blocks queued with dispatch_after
static void MSBTTurn(void) { while (CFRunLoopRunInMode(kCFRunLoopDefaultMode, 0.005, true) == kCFRunLoopRunHandledSource) {} gTurn++; }
static void MSBTWait(double s) { [[NSRunLoop mainRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:s]]; gTurn++; }
static NSIndexPath *MSBTRow(NSUInteger row) { return [NSIndexPath indexPathWithIndex:row]; }
// Settings > General > Windows & Multitasking > App Window Sizes, pushed as Settings pushes them in this shape, settled
static MSBAppSizesController *MSBTSettings(UINavigationController **navOut) {
	UINavigationController *nav = [UINavigationController new];
	MSBAppSizesController *list = [MSBAppSizesController new];
	[nav msbtPush:[MSBTGeneral new]]; [nav msbtPush:[MSBTWindows new]]; [nav msbtPush:list];
	MSBTTurn();
	[nav msbtClear];
	gLog = [NSMutableArray array]; gWrites = [NSMutableArray array];
	*navOut = nav;
	return list;
}
// ... with Add App tapped (the list's didSelectRow marks the opening, then Preferences pushes AltList's picker), the picker settled
static MSBAppSizesController *MSBTPickerUp(UINavigationController **navOut) {
	MSBAppSizesController *list = MSBTSettings(navOut);
	[list tableView:nil didSelectRowAtIndexPath:MSBTRow(1)]; MSBTTurn();
	[*navOut msbtClear];
	return list;
}
static NSString *W(NSString *what, id got) {   // (a check's words, with what it got on one line)
	if ([got isKindOfClass:[NSArray class]]) got = [got componentsJoinedByString:@" / "];
	return [NSString stringWithFormat:@"%@: %@ (got: %@)", MSBTShape(), what, got];
}
static NSString *S(NSString *what, id got) { return W([@"seen: " stringByAppendingString:what], got); }   // (what the user sees)

int main(void) {
	@autoreleasepool {
		NSString *calc = @"com.apple.calculator";
		// ---- the two rules on their own ----
		for (gShape = 0; gShape < 4; gShape++) {
			UINavigationController *nav; MSBAppSizesController *list = MSBTSettings(&nav);
			UIViewController *entry = nav.viewControllers.lastObject;
			ok(MSBSSEntryOf(list, nav) == entry, W(@"the list's entry is the stack's last", MSBSSEntryOf(list, nav)));
			ok(gShape ? entry != list : entry == list, W(gShape ? @"the list is not its own entry" : @"the list is its own entry", entry));
			ok(MSBSSPageIn(entry, [MSBAppSizesController class]) == list, W(@"the entry holds the list", MSBSSPageIn(entry, [MSBAppSizesController class])));
			ok(MSBSSPageIn(entry, [MSBTPicker class]) == nil, W(@"the list's entry holds no picker", MSBSSPageIn(entry, [MSBTPicker class])));
			ok(MSBSSPageIn(nav.viewControllers.firstObject, [MSBAppSizesController class]) == nil, W(@"General's entry holds no list", nil));
			UIViewController *loose = [MSBAppSizesController new];
			ok(![nav.viewControllers containsObject:MSBSSEntryOf(loose, nav)], W(@"a page in no stack has no entry in it", nil));
			ok(MSBSSEntryOf(nav.viewControllers.firstObject, nav) == nav.viewControllers.firstObject, W(@"an entry is its own entry", nil));
		}
		ok(MSBSSPageIn(nil, [MSBTPicker class]) == nil && MSBSSPageIn([MSBTPicker new], Nil) == nil && MSBSSEntryOf(nil, nil) == nil, @"nil in, nil out");

		for (gShape = 0; gShape < 4; gShape++) {
			// ---- 1. the pick at the tap, the picker in front (AltList's setter from its row's tap; the A12Z's case): on its next turn the picker
			//         closes with a slide back to the list and nothing is pushed; the slide's end plus a turn: the app's page, once ----
			UINavigationController *nav; MSBAppSizesController *list = MSBTSettings(&nav);
			[list tableView:nil didSelectRowAtIndexPath:MSBTRow(1)]; MSBTTurn();
			ok([MSBTStack(nav) isEqualToString:@"general, windows, list, picker"], W(@"Add App shows the picker over the list", MSBTStack(nav)));
			ok([list msbPickerOnTop], W(@"the picker is read as in front, pushed from the list", @([list msbPickerOnTop])));
			UIViewController *picker = MSBTPageOf(nav.viewControllers.lastObject);
			[nav msbtClear];
			[list msbPickedApp:calc specifier:nil];
			ok([gLog.firstObject isEqualToString:@"picker: com.apple.calculator picked, the picker in front"], W(@"the pick logs the picker in front", gLog.firstObject));
			ok(nav.calls.count == 0, W(@"nothing moves in the setter's own turn", MSBTCalls(nav)));
			MSBTTurn();
			ok([MSBTCalls(nav) isEqualToString:@"popTo animated list"], W(@"the pick's next turn: the picker closes with a slide back to the list, nothing pushed", MSBTCalls(nav)));
			ok([gLog containsObject:@"picker: closed with a slide, the page opens when the list is back"], W(@"... and the log says so", gLog));
			[nav msbtEndTransition]; MSBTTurn();
			ok([MSBTCalls(nav) isEqualToString:@"popTo animated list; push page(com.apple.calculator)"], W(@"the slide's end plus a turn: the app's page pushed, once", MSBTCalls(nav)));
			ok([MSBTSeenStack(nav) isEqualToString:MSBTSeenOK(@"general, windows, list, page(com.apple.calculator)")], S(@"the app's page over the list, no empty host, the record the stack", MSBTSeenStack(nav)));
			ok(!MSBTPopPush(nav), W(@"no push in the same turn as a pop", MSBTPopPush(nav)));
			ok([gLog containsObject:@"page of com.apple.calculator opened once the list was back"] && MSBTLogged(@"page of ") == 1, W(@"the log names the list back, one page", gLog));
			NSString *parent = picker.parentViewController ? NSStringFromClass([picker.parentViewController class]) : @"none";
			ok([gLog containsObject:[@"picker parent " stringByAppendingString:parent]], W([@"the log names the closed picker's parent at the push: " stringByAppendingString:parent], gLog));
			if (gShape == 0 || gShape == 3) ok([parent isEqualToString:@"none"], W(@"the closed picker is out of the stack (and out of its host on SwiftUI's record) at the push", parent));
			ok(gWrites.count == 0, W(@"the pick stores nothing", gWrites));
			// ... a second call for the same opening (a save as the picker goes) moves nothing
			[nav msbtClear];
			[list msbPickedApp:calc specifier:nil]; MSBTTurn();
			ok(nav.calls.count == 0, W(@"a second call for one opening pushes nothing", MSBTCalls(nav)));
			ok([gLog.lastObject isEqualToString:@"picker: a later call for com.apple.calculator ignored (the pick was taken)"], W(@"... and is logged as ignored", gLog.lastObject));
			// ... Back from the page: the list, and nothing opens again
			[nav msbtClear];
			[nav popViewControllerAnimated:YES]; MSBTTurn(); [nav msbtEndTransition]; MSBTTurn();
			ok([MSBTSeenStack(nav) isEqualToString:MSBTSeenOK(@"general, windows, list")] && [MSBTCalls(nav) isEqualToString:@"pop animated page(com.apple.calculator)"],
			   S(@"Back from the page lands on the list, nothing opened again", [NSString stringWithFormat:@"%@ | %@", MSBTSeenStack(nav), MSBTCalls(nav)]));

			// ---- 2. the setter called with the list in front and settled (AltList's picker gone first): the page on the next turn, once, though the
			//         list's viewDidAppear in the same turn queues the settled opener too (two callers, one push) ----
			list = MSBTPickerUp(&nav);
			[nav popViewControllerAnimated:NO]; MSBTTurn(); [nav msbtClear];
			[list msbPickedApp:@"com.apple.mobilenotes" specifier:nil];
			ok([gLog.firstObject isEqualToString:@"picker: com.apple.mobilenotes picked, the picker going"], W(@"a pick with the list in front logs the picker going", gLog.firstObject));
			[list viewDidAppear:YES];
			MSBTTurn();
			ok([MSBTCalls(nav) isEqualToString:@"push page(com.apple.mobilenotes)"], W(@"a pick with the list in front settled: one push on the next turn, the second caller none", MSBTCalls(nav)));
			ok([MSBTSeenStack(nav) isEqualToString:MSBTSeenOK(@"general, windows, list, page(com.apple.mobilenotes)")], S(@"the app's page over the list", MSBTSeenStack(nav)));
			ok([gLog containsObject:@"page of com.apple.mobilenotes opened once the list was back"] && MSBTLogged(@"page of ") == 1 && MSBTLogged(@"picker: the pick of") == 0, W(@"... logged once, nothing dropped", gLog));

			// ---- 3. the setter called while the picker is going (AltList closing it with a slide): nothing until the slide ends, then one push (the
			//         transition's end and the list's viewDidAppear both look) ----
			list = MSBTPickerUp(&nav);
			[nav popViewControllerAnimated:YES];
			[list msbPickedApp:@"com.apple.mobilesafari" specifier:nil]; MSBTTurn();
			ok([MSBTCalls(nav) isEqualToString:@"pop animated picker"], W(@"nothing pushed while the slide runs", MSBTCalls(nav)));
			ok([gLog containsObject:@"picker: a transition is running, the pick waits for its end"], W(@"... and the log says so", gLog));
			[nav msbtEndTransition]; MSBTTurn();
			ok([MSBTCalls(nav) isEqualToString:@"pop animated picker; push page(com.apple.mobilesafari)"], W(@"the slide's end plus a turn: one push", MSBTCalls(nav)));
			ok([MSBTSeenStack(nav) isEqualToString:MSBTSeenOK(@"general, windows, list, page(com.apple.mobilesafari)")], S(@"the page opens once the list is back", MSBTSeenStack(nav)));
			ok(MSBTLogged(@"page of com.apple.mobilesafari opened once the list was back") == 1 && MSBTLogged(@"picker: the pick of") == 0, W(@"... logged once, nothing dropped", gLog));
			[list viewDidAppear:YES]; MSBTTurn();
			ok([MSBTCalls(nav) isEqualToString:@"pop animated picker; push page(com.apple.mobilesafari)"], W(@"a later viewDidAppear opens nothing more", MSBTCalls(nav)));
			ok(!MSBTPopPush(nav), W(@"no push in the same turn as a pop", MSBTPopPush(nav)));

			// ---- 4. the app's page already in front: not pushed again; another app's page is ----
			[nav msbtClear];
			[list msbOpenAppPage:@"com.apple.mobilesafari"]; MSBTTurn();
			ok(nav.calls.count == 0, W(@"the app's page in front is not pushed again", MSBTCalls(nav)));
			[list msbOpenAppPage:@"com.apple.mobilenotes"]; MSBTTurn();
			ok([MSBTCalls(nav) isEqualToString:@"push page(com.apple.mobilenotes)"], W(@"another app's page is", MSBTCalls(nav)));

			// ---- 5. Remove App: the app's entry removed, back to the list's entry in the stack ----
			list = MSBTSettings(&nav);
			[list msbOpenAppPage:calc]; MSBTTurn(); [nav msbtClear];
			MSBAppSizeController *page = (MSBAppSizeController *)MSBTPageOf(nav.viewControllers.lastObject);
			[page msbRemoveApp:nil]; MSBTTurn(); [nav msbtEndTransition]; MSBTTurn();
			ok([gWrites isEqualToArray:@[@"com.apple.calculator -1"]], W(@"Remove App removes the app's entry", gWrites));
			ok([MSBTCalls(nav) isEqualToString:@"popTo animated list"] && [MSBTSeenStack(nav) isEqualToString:MSBTSeenOK(@"general, windows, list")], S(@"Remove App goes back to the list", [NSString stringWithFormat:@"%@ | %@", MSBTCalls(nav), MSBTSeenStack(nav)]));

			// ---- 6. a transition running at the pick's next turn that is not the picker's pop (fix 3): the same checks one turn after it ends ----
			// a) the picker's own push still ending
			list = MSBTPickerUp(&nav);
			[nav msbtBeginTransition];
			[list msbPickedApp:calc specifier:nil]; MSBTTurn();
			ok(nav.calls.count == 0 && [gLog containsObject:@"picker: a transition is running, the pick waits for its end"], W(@"a transition at the pick's next turn: nothing moves, logged", MSBTCalls(nav)));
			[nav msbtEndTransition]; MSBTTurn();
			ok([MSBTCalls(nav) isEqualToString:@"popTo animated list"], W(@"its end plus a turn: the picker closes with a slide", MSBTCalls(nav)));
			[nav msbtEndTransition]; MSBTTurn();
			ok([MSBTCalls(nav) isEqualToString:@"popTo animated list; push page(com.apple.calculator)"] && [MSBTSeenStack(nav) isEqualToString:MSBTSeenOK(@"general, windows, list, page(com.apple.calculator)")],
			   S(@"then the page, once", [NSString stringWithFormat:@"%@ | %@", MSBTCalls(nav), MSBTSeenStack(nav)]));
			// b) the picker's search closing (its own presentation, not the stack's), then another transition starting as it ends: again after each
			list = MSBTPickerUp(&nav);
			UIViewController *pk = MSBTPageOf(nav.viewControllers.lastObject);
			MSBTCoordinator *search = [MSBTCoordinator new]; pk.msbtPresenting = search;
			[list msbPickedApp:calc specifier:nil]; MSBTTurn();
			ok(nav.calls.count == 0, W(@"the picker's search closing at the pick's next turn: nothing moves", MSBTCalls(nav)));
			gTurn++; pk.msbtPresenting = nil; [search msbtEnd]; [nav msbtBeginTransition]; MSBTTurn();
			ok(nav.calls.count == 0 && MSBTLogged(@"picker: a transition is running, the pick waits for its end") == 2, W(@"... another transition starting as it ends: still nothing, waited for twice", gLog));
			[nav msbtEndTransition]; MSBTTurn(); [nav msbtEndTransition]; MSBTTurn();
			ok([MSBTCalls(nav) isEqualToString:@"popTo animated list; push page(com.apple.calculator)"] && [MSBTSeenStack(nav) isEqualToString:MSBTSeenOK(@"general, windows, list, page(com.apple.calculator)")],
			   S(@"... its end: the picker closes with a slide, then the page, once", [NSString stringWithFormat:@"%@ | %@", MSBTCalls(nav), MSBTSeenStack(nav)]));
			// c) a coordinator that takes no completion: looked at again a moment later
			list = MSBTPickerUp(&nav);
			[nav msbtBeginTransition].refuses = YES;
			[list msbPickedApp:calc specifier:nil]; MSBTWait(0.25);
			ok(nav.calls.count == 0 && [gLog containsObject:@"a transition's end not offered: looked at again in 0.1 s"], W(@"a transition that takes no completion: nothing moves, looked at again", gLog));
			[nav msbtEndTransition]; MSBTWait(0.25); [nav msbtEndTransition]; MSBTTurn();
			ok([MSBTCalls(nav) isEqualToString:@"popTo animated list; push page(com.apple.calculator)"] && [MSBTSeenStack(nav) isEqualToString:MSBTSeenOK(@"general, windows, list, page(com.apple.calculator)")],
			   S(@"... once it has ended: the picker closes with a slide, then the page, once", [NSString stringWithFormat:@"%@ | %@", MSBTCalls(nav), MSBTSeenStack(nav)]));

			// ---- 7. the list back but still moving (fix 3, the settled opener): nothing pushed until the transition ends; a viewDidAppear while the
			//         slide runs pushes nothing ----
			list = MSBTPickerUp(&nav);
			[list msbPickedApp:calc specifier:nil]; MSBTTurn();
			[nav msbtEndTransition]; [nav msbtBeginTransition]; MSBTTurn();
			ok([MSBTCalls(nav) isEqualToString:@"popTo animated list"] && [gLog containsObject:@"list: a transition is running, the page waits for its end"], W(@"the list back but moving: nothing pushed, logged", MSBTCalls(nav)));
			[nav msbtEndTransition]; MSBTTurn();
			ok([MSBTCalls(nav) isEqualToString:@"popTo animated list; push page(com.apple.calculator)"] && MSBTLogged(@"page of ") == 1, W(@"its end plus a turn: the page pushed once", MSBTCalls(nav)));
			list = MSBTPickerUp(&nav);
			[list msbPickedApp:calc specifier:nil]; MSBTTurn();
			[list viewDidAppear:YES]; MSBTTurn();
			ok([MSBTCalls(nav) isEqualToString:@"popTo animated list"], W(@"a viewDidAppear while the slide still runs pushes nothing", MSBTCalls(nav)));
			[nav msbtEndTransition]; MSBTTurn();
			ok([MSBTCalls(nav) isEqualToString:@"popTo animated list; push page(com.apple.calculator)"] && [MSBTSeenStack(nav) isEqualToString:MSBTSeenOK(@"general, windows, list, page(com.apple.calculator)")],
			   S(@"... the page once the slide has ended", [NSString stringWithFormat:@"%@ | %@", MSBTCalls(nav), MSBTSeenStack(nav)]));

			// ---- 8. the list not in front once nothing moves: the pick dropped, logged, and nothing opened later ----
			// a) another page over the list before the settled turn
			list = MSBTPickerUp(&nav);
			[list msbPickedApp:calc specifier:nil]; MSBTTurn();
			[nav msbtEndTransition]; [nav msbtPushNow:[MSBTOther new]]; MSBTTurn();
			ok([MSBTCalls(nav) isEqualToString:@"popTo animated list; push other"] && [gLog containsObject:@"picker: the pick of com.apple.calculator dropped, the list has left its window"],
			   W(@"another page over the list at the settled turn: nothing pushed, the pick dropped", [NSString stringWithFormat:@"%@ | %@", MSBTCalls(nav), [gLog componentsJoinedByString:@" / "]]));
			[nav popViewControllerAnimated:YES]; MSBTTurn(); [nav msbtEndTransition]; MSBTTurn();
			ok([MSBTSeenStack(nav) isEqualToString:MSBTSeenOK(@"general, windows, list")] && ![MSBTCalls(nav) containsString:@"push page"], S(@"... Back to the list opens nothing", [NSString stringWithFormat:@"%@ | %@", MSBTSeenStack(nav), MSBTCalls(nav)]));
			// b) the list gone (Back past it) before the settled turn
			list = MSBTPickerUp(&nav);
			[list msbPickedApp:calc specifier:nil]; MSBTTurn();
			[nav msbtEndTransition]; [nav popViewControllerAnimated:NO]; MSBTTurn();
			ok(![MSBTCalls(nav) containsString:@"push page"] && [gLog containsObject:@"picker: the pick of com.apple.calculator dropped, the list has left its navigation stack"],
			   W(@"the list gone at the settled turn: nothing pushed, the pick dropped", [NSString stringWithFormat:@"%@ | %@", MSBTCalls(nav), [gLog componentsJoinedByString:@" / "]]));

			// ---- 9. a tap on another row of the list while the pick waits (fix 4): the pick dropped; Back from that row's page opens nothing ----
			list = MSBTPickerUp(&nav);
			[list msbPickedApp:calc specifier:nil]; MSBTTurn();
			[nav msbtEndTransition]; [nav msbtBeginTransition]; MSBTTurn();
			[list tableView:nil didSelectRowAtIndexPath:MSBTRow(0)];
			ok([gLog containsObject:@"picker: the pick of com.apple.calculator dropped, a row of the list tapped"], W(@"a tap on Clock's row while the pick waits drops it", gLog));
			MSBTTurn(); [nav msbtEndTransition]; MSBTTurn();
			ok([MSBTStack(nav) isEqualToString:@"general, windows, list, page(com.apple.mobiletimer)"], W(@"... Clock's page opens", MSBTStack(nav)));
			[nav popViewControllerAnimated:YES]; MSBTTurn(); [nav msbtEndTransition]; MSBTTurn();
			ok([MSBTSeenStack(nav) isEqualToString:MSBTSeenOK(@"general, windows, list")] && ![MSBTCalls(nav) containsString:@"push page(com.apple.calculator)"],
			   S(@"... Back from Clock's page lands on the list, Calculator's page never opened", [NSString stringWithFormat:@"%@ | %@", MSBTSeenStack(nav), MSBTCalls(nav)]));
			ok(!MSBTPopPush(nav), W(@"no push in the same turn as a pop", MSBTPopPush(nav)));
		}

		// ---- the known limit (fix 7a): SwiftUI's record taking a programmatic pop in only one frame after the slide's end (later than the Mac's
		//      macCatalyst 18.7 and than 18.5's Back in s01). Then the push lands in the stale record: E1's empty hosts, and the log's picker
		//      parent names its host. Expected, not a pass of the design: device row S1-F1b step 2 and its log line tell which 18.5 does ----
		gShape = 3; gLate = YES;
		{
			UINavigationController *nav; MSBAppSizesController *list = MSBTPickerUp(&nav);
			[list msbPickedApp:calc specifier:nil]; MSBTTurn(); [nav msbtEndTransition]; MSBTWait(0.1);
			BOOL limit = MSBTEmptyHosts(nav) > 0 && !MSBTRecordIsStack(nav) && [gLog containsObject:@"picker parent MSBTHost"];
			ok(limit, W(@"the known limit reproduces E1 (empty hosts, the record out of step, the picker still in its host at the push)", [NSString stringWithFormat:@"%@ | %@", MSBTSeenStack(nav), [gLog componentsJoinedByString:@" / "]]));
			printf("KNOWN LIMIT (not a pass): %s: %s\n", MSBTShape().UTF8String, MSBTSeenStack(nav).UTF8String);
		}
		gLate = NO;
		printf("test-appsizestack: %d checks, %d failed\n", checks, fails);
	}
	return fails ? 1 : 0;
}
