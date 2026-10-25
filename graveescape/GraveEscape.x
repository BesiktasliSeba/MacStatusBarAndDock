// GraveEscapeTweak — the key left of the 1 key acts as Escape.
//
// Mechanism (1.5.0, 25 Oct): the UIKit key getters below (UIPhysicalKeyboardEvent / UIKey) turn the top-left key into Escape for everything that
// reads UIKit's keys (apps, SpringBoard, our menus; not Spotlight's search field, which reads below UIKit), Command kept (Command + that key is
// unchanged), Shift dropped. The key is picked per keyboard: SpringBoard reads the attached keyboard's StandardType and maker and publishes its layout
// (kLayoutState). An ANSI keyboard's top-left key is HID 0x35, and so is other makers' ISO keyboards' (the HID usage tables put Grave there); Apple's
// ISO keyboards report the top-left key as 0x64 and the key left of Z as 0x35 (KT's Spanish ISO Magic Keyboard, 25 Oct -- the old 0x35-only rule
// turned the key left of Z into Escape there, the ISO bug); a JIS keyboard is left unchanged.
// The HID-level remap (Apple's per-keyboard UserKeyMapping, HIDKeyboardModifierMappingPairs, set from SpringBoard) that 77cbde8 made the mechanism is
// OFF in 1.5.0 (coordinator / KT, 25 Oct): it was never proven with a real key press (injected keys skip the service's filter), the ISO pair did
// nothing on the A12Z, and that property may remap only modifier keys. Its code stays for later behind the debug flag /tmp/msb-ge-hid (debug builds
// only; the getters then stand down, as with 77cbde8). Every start takes off any pair of ours an earlier build wrote (the 1.5.0 RCs on test iPads),
// as does the package's removal.
//
// Parts:
//  1 & 2. The getter hooks (UIPhysicalKeyboardEvent / UIKey), with the key for the attached keyboard's layout (GEGetterKey).
//  3. Dock menus (bottom of file): their menu is in a non-key window, so even a real Escape never passes through it; SpringBoard is asked to dismiss
//     it directly. Unchanged -- it already acts on a real Escape (HID 0x29), which the mapping now delivers.
//
// The getters need each other's original values (keyCode wants the modifier flags, and the reverse); a per-thread guard makes any nested call return
// the ORIGINAL value, so they never recurse.

#import <UIKit/UIKit.h>
#import <objc/message.h>
#import <objc/runtime.h>
#include <notify.h>
#include <dlfcn.h>

#define kHIDGrave 53
#define kHIDEscape 41
#define kModShift 0x20000
#define kModCommand 0x100000

// HID usages (Keyboard/Keypad page 0x07) as full UserKeyMapping values ((0x07 << 32) | usage):
#define kUsageANSIGrave 0x35   // ANSI: the key left of 1
#define kUsageISOGrave  0x64   // ISO:  the key left of 1 (measured on KT's Spanish ISO Magic Keyboard; the ISO board's 0x35 is left of Z)
#define kUsageEscape    0x29
#define kHIDPage(u) (0x700000000ULL | (unsigned long long)(u))

@interface UIPhysicalKeyboardEvent : UIEvent
- (long long)_keyCode;
- (long long)_modifierFlags;
- (NSString *)_modifiedInput;
- (NSString *)_unmodifiedInput;
@end

static __thread BOOL gInside = NO;

static BOOL inSpringBoard(void) {
	static BOOL v;
	static dispatch_once_t once;
	dispatch_once(&once, ^{ v = strcmp(getprogname(), "SpringBoard") == 0; });
	return v;
}

// The Settings switch (Settings > Keyboard, shown while a hardware keyboard is attached; off for a new install). SpringBoard reads it and publishes
// it as Darwin notification state (kEnabledState, 1 = on; unset = off) and posts the same name; every process keeps a copy of it, updated on that
// post, so the key getters below never ask for it (they run many times per key press).
#define kEnabledState "com.besiktasliseba.graveescapetweak.enabled"
#define kHIDActiveState "com.besiktasliseba.graveescapetweak.hidactive"   // 1 = the HID mapping is the mechanism (SpringBoard set it); the getters stand down
#define kLayoutState    "com.besiktasliseba.graveescapetweak.layout"      // the attached keyboard's layout (SpringBoard): 1 the top-left key is 0x35, 2 it is 0x64 (Apple ISO), 3 JIS; 0 unknown (= 1)
#define kPrefsChanged "com.besiktasliseba.graveescapetweak/prefsChanged"   // posted by the Settings switch
#define kPrefsDomain  CFSTR("com.besiktasliseba.graveescapetweak")
static volatile BOOL gEnabled = NO;
static volatile BOOL gHIDActive = NO;
static volatile long long gLayout = 0;
static BOOL GEOn(void) { return gEnabled; }
// The getters are the mechanism (see the top): on while the switch is on, unless the debug-only HID mapping is the mechanism (/tmp/msb-ge-hid).
static BOOL GEUIKitRemap(void) { return gEnabled && !gHIDActive; }
// The top-left key, next to 1, as UIKit reads it on the attached keyboard; none (-1) on a JIS keyboard.
static long long GEGetterKey(void) { return gLayout == 2 ? kUsageISOGrave : (gLayout == 3 ? -1 : kHIDGrave); }
// The HID pairs: off in 1.5.0, kept for later behind a debug flag (see the top).
static BOOL GEHIDWanted(void) {
#if DEBUG
	return access("/tmp/msb-ge-hid", F_OK) == 0;
#else
	return NO;
#endif
}
static void ReadState(int token) { uint64_t v = 0; gEnabled = notify_get_state(token, &v) == NOTIFY_STATUS_OK && v == 1; }
static void ReadHIDActive(int token) { uint64_t v = 0; gHIDActive = notify_get_state(token, &v) == NOTIFY_STATUS_OK && v == 1; }
static void ReadLayout(int token) { uint64_t v = 0; gLayout = notify_get_state(token, &v) == NOTIFY_STATUS_OK && v <= 3 ? (long long)v : 0; }
static void GEUpdateMapping(void);   // (SpringBoard, defined below)
static void PublishSwitch(void) {   // (SpringBoard)
    static int token = 0;
    if (!token) notify_register_check(kEnabledState, &token);
    CFPreferencesAppSynchronize(kPrefsDomain);
    BOOL enabled = NO;   // off until switched on
    CFPropertyListRef v = CFPreferencesCopyValue(CFSTR("enabled"), kPrefsDomain, kCFPreferencesCurrentUser, kCFPreferencesAnyHost);
    if (v) { if (CFGetTypeID(v) == CFBooleanGetTypeID()) enabled = CFBooleanGetValue(v); CFRelease(v); }
    gEnabled = enabled;   // SpringBoard is the authority: set it before the mapping is applied, not only via the async handler
    notify_set_state(token, enabled ? 1 : 0);
    notify_post(kEnabledState);
    GEUpdateMapping();   // apply or remove the HID mapping for this switch, and publish whether it is the mechanism
}

static BOOL isRemapped(long long origKeyCode, long long origFlags) {
	return origKeyCode == GEGetterKey() && !(origFlags & kModCommand);
}

// ---------------------------------------------------------------------------
// The HID mapping (SpringBoard only): Apple's per-keyboard UserKeyMapping.
// ---------------------------------------------------------------------------
typedef struct __IOHIDEventSystemClient *GEHIDClient;
typedef struct __IOHIDServiceClient *GEHIDService;
static GEHIDClient gHIDClient;
static GEHIDClient (*geCreate)(CFAllocatorRef);
static CFArrayRef (*geCopyServices)(GEHIDClient);
static CFTypeRef (*geCopyProp)(GEHIDService, CFStringRef);
static Boolean (*geSetProp)(GEHIDService, CFStringRef, CFTypeRef);
static void (*geSetMatching)(GEHIDClient, CFDictionaryRef);
static void (*geRegMatchCb)(GEHIDClient, void (*)(void *, void *, GEHIDService), void *);
static void (*geSchedQ)(GEHIDClient, dispatch_queue_t);
static void GEMatchCb(void *target, void *refcon, GEHIDService service);   // (reapply on connect)

// Every private call is checked once; if any is missing the mapping is never used and the getter hooks remain the mechanism (gHIDActive stays off).
static BOOL GEHIDLoad(void) {
	static dispatch_once_t once; static BOOL ok = NO;
	dispatch_once(&once, ^{
		void *io = dlopen("/System/Library/Frameworks/IOKit.framework/IOKit", RTLD_LAZY);
		if (!io) return;
		geCreate = dlsym(io, "IOHIDEventSystemClientCreate");
		geCopyServices = dlsym(io, "IOHIDEventSystemClientCopyServices");
		geCopyProp = dlsym(io, "IOHIDServiceClientCopyProperty");
		geSetProp = dlsym(io, "IOHIDServiceClientSetProperty");
		geSetMatching = dlsym(io, "IOHIDEventSystemClientSetMatching");
		geRegMatchCb = dlsym(io, "IOHIDEventSystemClientRegisterDeviceMatchingCallback");
		geSchedQ = dlsym(io, "IOHIDEventSystemClientScheduleWithDispatchQueue");
		ok = geCreate && geCopyServices && geCopyProp && geSetProp;
	});
	return ok;
}

static long long GENumProp(GEHIDService s, CFStringRef key, BOOL *found) {
	long long n = 0; if (found) *found = NO;
	CFTypeRef v = geCopyProp(s, key);
	if (v) { if (CFGetTypeID(v) == CFNumberGetTypeID()) { CFNumberGetValue(v, kCFNumberLongLongType, &n); if (found) *found = YES; } CFRelease(v); }
	return n;
}
static BOOL GEIsKeyboard(GEHIDService s) {
	return GENumProp(s, CFSTR("PrimaryUsagePage"), NULL) == 1 && GENumProp(s, CFSTR("PrimaryUsage"), NULL) == 6;
}
// The key left of 1 for this keyboard, or 0 to leave the keyboard alone (JIS).
static uint32_t GESrcUsage(GEHIDService s) {
	BOOL found = NO; long long t = GENumProp(s, CFSTR("StandardType"), &found);
	if (found && t == 2) return 0;                 // JIS: unchanged
	if (found && t == 1) return kUsageISOGrave;    // ISO
	return kUsageANSIGrave;                         // ANSI, or unknown (the common key)
}

// The getters' layout code for one keyboard (kLayoutState): 3 JIS; 2 an Apple ISO keyboard (its top-left key reported as 0x64; Apple's vendor IDs:
// USB 0x05AC, Bluetooth 0x004C); otherwise 1 (the top-left key is 0x35: ANSI, and other makers' ISO keyboards).
static long long GELayoutOf(GEHIDService s) {
	BOOL found = NO; long long t = GENumProp(s, CFSTR("StandardType"), &found);
	if (found && t == 2) return 3;
	if (found && t == 1) { long long vendor = GENumProp(s, CFSTR("VendorID"), NULL); if (vendor == 0x05AC || vendor == 0x004C) return 2; }
	return 1;
}
static void GEPublishLayout(long long layout) {   // SpringBoard (the token is kept, so the state lives as long as SpringBoard)
	static int token = 0;
	if (!token) notify_register_check(kLayoutState, &token);
	gLayout = layout;
	uint64_t cur = 0; notify_get_state(token, &cur);
	if ((long long)cur != layout) { notify_set_state(token, (uint64_t)layout); notify_post(kLayoutState); }
}

// Add (add, the debug-only HID mechanism) or take off OUR Escape pair on one keyboard service, keeping any other mapping it has; the property is written
// only when something changes, so a keyboard with nothing of ours is never touched.
static void GEApplyService(GEHIDService s, BOOL add) {
	if (!GEIsKeyboard(s)) return;
	uint32_t src = add ? GESrcUsage(s) : 0;   // (0: JIS, never given a pair)
	long long wantSrc = kHIDPage(src), wantDst = kHIDPage(kUsageEscape);
	BOOL removed = NO;
	NSMutableArray *pairs = [NSMutableArray array];
	CFTypeRef cur = geCopyProp(s, CFSTR("HIDKeyboardModifierMappingPairs"));
	if (cur && CFGetTypeID(cur) == CFArrayGetTypeID()) for (id p in (__bridge NSArray *)cur) {
		if (![p isKindOfClass:[NSDictionary class]]) continue;
		long long ps = [p[@"HIDKeyboardModifierMappingSrc"] longLongValue], pd = [p[@"HIDKeyboardModifierMappingDst"] longLongValue];
		if (pd == wantDst && (ps == (long long)kHIDPage(kUsageANSIGrave) || ps == (long long)kHIDPage(kUsageISOGrave))) { removed = YES; continue; }   // drop ours (either type)
		[pairs addObject:p];
	}
	if (cur) CFRelease(cur);
	if (!src && !removed) return;   // (nothing to add, nothing of ours to take off)
	if (src) [pairs addObject:@{ @"HIDKeyboardModifierMappingSrc": @(wantSrc), @"HIDKeyboardModifierMappingDst": @(wantDst) }];
	geSetProp(s, CFSTR("HIDKeyboardModifierMappingPairs"), (__bridge CFArrayRef)pairs);
}

static void GEApplyAll(BOOL add) {   // SpringBoard: every keyboard's pair (see GEApplyService), and the attached keyboard's layout for the getters
	if (!GEHIDLoad()) return;
	if (!gHIDClient) {
		gHIDClient = geCreate(kCFAllocatorDefault);
		if (gHIDClient && geSetMatching && geRegMatchCb && geSchedQ) {   // reapply whenever a keyboard connects
			long long one = 1, six = 6;
			CFNumberRef nUsagePage = CFNumberCreate(NULL, kCFNumberLongLongType, &one), nUsage = CFNumberCreate(NULL, kCFNumberLongLongType, &six);
			const void *k[2] = { CFSTR("PrimaryUsagePage"), CFSTR("PrimaryUsage") }, *v[2] = { nUsagePage, nUsage };
			CFDictionaryRef m = CFDictionaryCreate(NULL, k, v, 2, &kCFTypeDictionaryKeyCallBacks, &kCFTypeDictionaryValueCallBacks);
			geSetMatching(gHIDClient, m);
			geRegMatchCb(gHIDClient, GEMatchCb, NULL);
			geSchedQ(gHIDClient, dispatch_get_main_queue());
			CFRelease(m); CFRelease(nUsagePage); CFRelease(nUsage);
		}
	}
	if (!gHIDClient) return;
	CFArrayRef svcs = geCopyServices(gHIDClient);
	long long layout = -1;
	if (svcs) {
		for (CFIndex i = 0; i < CFArrayGetCount(svcs); i++) {
			GEHIDService svc = (GEHIDService)CFArrayGetValueAtIndex(svcs, i);
			GEApplyService(svc, add);
			if (GEIsKeyboard(svc)) layout = MAX(layout, GELayoutOf(svc));   // (several keyboards: a JIS or Apple ISO one decides over a plain one)
		}
		CFRelease(svcs);
	}
	if (layout > 0) GEPublishLayout(layout);
}
// A keyboard connected: its pair (only with the debug HID mechanism; otherwise any old pair of ours is taken off), and it is the keyboard in use now.
static void GEMatchCb(void *target, void *refcon, GEHIDService service) {
	GEApplyService(service, gEnabled && GEHIDWanted());
	if (GEIsKeyboard(service)) GEPublishLayout(GELayoutOf(service));
}

// SpringBoard: apply or remove the mapping for the current switch, then publish whether the HID mapping is the mechanism (so every process's getters
// stand down, or fall back if it could not be set).
static void GEUpdateMapping(void) {
	BOOL apiOK = GEHIDLoad();
	BOOL hid = gEnabled && GEHIDWanted();
	if (apiOK) GEApplyAll(hid);   // (at every start too, the switch on or off: any pair of ours an earlier build wrote comes off, and the layout is published)
	BOOL active = hid && apiOK;
	static int token = 0;
	if (!token) notify_register_check(kHIDActiveState, &token);
	notify_set_state(token, active ? 1 : 0);
	gHIDActive = active;
	notify_post(kHIDActiveState);
}

// ---------------------------------------------------------------------------
// Layer 1: UIPhysicalKeyboardEvent
// ---------------------------------------------------------------------------
%hook UIPhysicalKeyboardEvent

- (long long)_keyCode {
	if (!GEUIKitRemap()) return %orig;
	long long code = %orig;
	if (gInside || code != GEGetterKey()) return code;
	gInside = YES;
	long long flags = [self _modifierFlags];
	gInside = NO;
	if (isRemapped(code, flags)) {
		return kHIDEscape;
	}
	return code;
}

- (long long)_modifierFlags {
	if (!GEUIKitRemap()) return %orig;
	long long flags = %orig;
	if (gInside) return flags;
	gInside = YES;
	long long code = [self _keyCode];
	gInside = NO;
	if (isRemapped(code, flags)) return flags & ~(long long)kModShift;
	return flags;
}

- (NSString *)_modifiedInput {
	if (!GEUIKitRemap()) return %orig;
	if (!gInside) {
		gInside = YES;
		BOOL remap = isRemapped([self _keyCode], [self _modifierFlags]);
		gInside = NO;
		if (remap) return @"\x1B";
	}
	return %orig;
}

- (NSString *)_unmodifiedInput {
	if (!GEUIKitRemap()) return %orig;
	if (!gInside) {
		gInside = YES;
		BOOL remap = isRemapped([self _keyCode], [self _modifierFlags]);
		gInside = NO;
		if (remap) return @"\x1B";
	}
	return %orig;
}

%end

// ---------------------------------------------------------------------------
// Layer 2: UIKey (what apps and UIKeyCommand see)
// ---------------------------------------------------------------------------
%hook UIKey

- (UIKeyboardHIDUsage)keyCode {
	if (!GEUIKitRemap()) return %orig;
	UIKeyboardHIDUsage code = %orig;
	if (gInside || code != GEGetterKey()) return code;
	gInside = YES;
	long long flags = (long long)[self modifierFlags];
	gInside = NO;
	if (isRemapped(code, flags)) {
		return (UIKeyboardHIDUsage)kHIDEscape;
	}
	return code;
}

- (UIKeyModifierFlags)modifierFlags {
	if (!GEUIKitRemap()) return %orig;
	UIKeyModifierFlags flags = %orig;
	if (gInside) return flags;
	gInside = YES;
	long long code = (long long)[self keyCode];
	gInside = NO;
	if (isRemapped(code, (long long)flags)) return (UIKeyModifierFlags)((long long)flags & ~(long long)kModShift);
	return flags;
}

- (NSString *)characters {
	if (!GEUIKitRemap()) return %orig;
	if (!gInside) {
		gInside = YES;
		BOOL remap = isRemapped((long long)[self keyCode], (long long)[self modifierFlags]);
		gInside = NO;
		if (remap) {
			return UIKeyInputEscape;
		}
	}
	return %orig;
}

- (NSString *)charactersIgnoringModifiers {
	if (!GEUIKitRemap()) return %orig;
	if (!gInside) {
		gInside = YES;
		BOOL remap = isRemapped((long long)[self keyCode], (long long)[self modifierFlags]);
		gInside = NO;
		if (remap) {
			return UIKeyInputEscape;
		}
	}
	return %orig;
}

%end

// ---------------------------------------------------------------------------
// Dock menus (SpringBoard only)
//
// Escape normally dismisses a Haptic Touch menu through a key command on
// _UIContextMenuView, found by walking the responder chain from the KEY
// window's first responder. The Dock lives in its own window
// (SBFloatingDockWindow) which is never the key window, so a key press never
// passes through its menu and the key command never fires.
//
// Every press does climb through SBIconController, though. So: as a press
// climbs the chain, remember whether it passed through a context menu view;
// when it reaches SBIconController without having done so and a menu is
// showing, ask SpringBoard's icon manager to dismiss it ourselves.
// ---------------------------------------------------------------------------
static __thread BOOL gSawContextMenuView = NO;

static id iconManagerOf(id iconController) {
	@try { return [iconController valueForKey:@"iconManager"]; }
	@catch (NSException *e) { return nil; }
}

%hook UIResponder

- (void)pressesBegan:(NSSet<UIPress *> *)presses withEvent:(UIPressesEvent *)event {
	if (!GEOn()) {
		%orig;
		return;
	}
	if (inSpringBoard()) {
		BOOL escape = NO;
		for (UIPress *p in presses) {
			if (p.key && p.key.keyCode == kHIDEscape) { escape = YES; break; }
		}
		if (escape) {
			const char *cls = class_getName(object_getClass(self));
			if (strstr(cls, "_UIContextMenu")) gSawContextMenuView = YES;

			if (strcmp(cls, "SBIconController") == 0 && !gSawContextMenuView) {
				id mgr = iconManagerOf(self);
				SEL showing = NSSelectorFromString(@"isShowingIconContextMenu");
				SEL dismiss = NSSelectorFromString(@"dismissIconContextMenu");
				if (mgr && [mgr respondsToSelector:showing] && [mgr respondsToSelector:dismiss] &&
				    ((BOOL (*)(id, SEL))objc_msgSend)(mgr, showing)) {
					((void (*)(id, SEL))objc_msgSend)(mgr, dismiss);
				}
			}
			if (strcmp(cls, "SBWindowScene") == 0) gSawContextMenuView = NO;  // end of the chain
		}
	}
	%orig;
}

%end

%ctor {
	%init;
	static int token = 0, hidToken = 0, layoutToken = 0;
	if (notify_register_dispatch(kEnabledState, &token, dispatch_get_main_queue(), ^(int t) { ReadState(t); }) == NOTIFY_STATUS_OK) ReadState(token);
	// every process keeps a copy of "is the HID mapping the mechanism": while it is, the getter hooks stand down (the key is already Escape)
	if (notify_register_dispatch(kHIDActiveState, &hidToken, dispatch_get_main_queue(), ^(int t) { ReadHIDActive(t); }) == NOTIFY_STATUS_OK) ReadHIDActive(hidToken);
	// and of the attached keyboard's layout (which key is the top-left one)
	if (notify_register_dispatch(kLayoutState, &layoutToken, dispatch_get_main_queue(), ^(int t) { ReadLayout(t); }) == NOTIFY_STATUS_OK) ReadLayout(layoutToken);
	if (inSpringBoard()) {
		static int prefsToken = 0, removeToken = 0;
		notify_register_dispatch(kPrefsChanged, &prefsToken, dispatch_get_main_queue(), ^(int t) { PublishSwitch(); });
		// the package is being removed (sshtoggled --uninstall, prerm): take the HID mapping off every keyboard now, while our code still runs, so
		// nothing stale is left behind (the mapping is a runtime setting that a respring alone would not clear)
		notify_register_dispatch("com.besiktasliseba.graveescapetweak/removing", &removeToken, dispatch_get_main_queue(), ^(int t) {
			gEnabled = NO; GEApplyAll(NO);
			static int hid = 0; if (!hid) notify_register_check(kHIDActiveState, &hid); notify_set_state(hid, 0); gHIDActive = NO; notify_post(kHIDActiveState);
		});
		PublishSwitch();   // reads the switch, applies/removes the mapping, publishes both states
	}
}
