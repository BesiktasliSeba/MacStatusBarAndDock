// GraveEscapeTweak — grave/tilde key acts as Escape.
//
// Loaded into every UIKit process (SpringBoard and all apps), in three parts:
//
//  1. UIPhysicalKeyboardEvent getters (_keyCode, _modifierFlags,
//     _modifiedInput, _unmodifiedInput): what SpringBoard's Home Screen reads.
//  2. UIKey getters (keyCode, modifierFlags, characters,
//     charactersIgnoringModifiers): what apps see in pressesBegan: and
//     UIKeyCommand matching.
//  3. Dock menus (bottom of file): their menu is in a non-key window, so the
//     key never reaches it; SpringBoard is asked to dismiss it directly.
//
// Rules: grave (HID 0x35) without Command becomes Escape (HID 0x29), and
// Shift is dropped so Shift+grave is a bare Escape. Cmd+grave is untouched
// so window cycling keeps working.
//
// The getters need each other's original values (keyCode wants the modifier
// flags, modifierFlags wants the keyCode). If they simply called each other
// they'd recurse forever, so a per-thread guard makes any nested call return
// the ORIGINAL value instead of the substituted one.

#import <UIKit/UIKit.h>
#import <objc/message.h>
#include <notify.h>

#define kHIDGrave 53
#define kHIDEscape 41
#define kModShift 0x20000
#define kModCommand 0x100000

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
#define kPrefsChanged "com.besiktasliseba.graveescapetweak/prefsChanged"   // posted by the Settings switch
#define kPrefsDomain  CFSTR("com.besiktasliseba.graveescapetweak")
static volatile BOOL gEnabled = NO;
static BOOL GEOn(void) { return gEnabled; }
static void ReadState(int token) { uint64_t v = 0; gEnabled = notify_get_state(token, &v) == NOTIFY_STATUS_OK && v == 1; }
static void PublishSwitch(void) {   // (SpringBoard)
    static int token = 0;
    if (!token) notify_register_check(kEnabledState, &token);
    CFPreferencesAppSynchronize(kPrefsDomain);
    BOOL enabled = NO;   // off until switched on
    CFPropertyListRef v = CFPreferencesCopyValue(CFSTR("enabled"), kPrefsDomain, kCFPreferencesCurrentUser, kCFPreferencesAnyHost);
    if (v) { if (CFGetTypeID(v) == CFBooleanGetTypeID()) enabled = CFBooleanGetValue(v); CFRelease(v); }
    notify_set_state(token, enabled ? 1 : 0);
    notify_post(kEnabledState);
}

static BOOL isRemapped(long long origKeyCode, long long origFlags) {
	return origKeyCode == kHIDGrave && !(origFlags & kModCommand);
}

// ---------------------------------------------------------------------------
// Layer 1: UIPhysicalKeyboardEvent
// ---------------------------------------------------------------------------
%hook UIPhysicalKeyboardEvent

- (long long)_keyCode {
	if (!GEOn()) return %orig;
	long long code = %orig;
	if (gInside || code != kHIDGrave) return code;
	gInside = YES;
	long long flags = [self _modifierFlags];
	gInside = NO;
	if (isRemapped(code, flags)) {
		return kHIDEscape;
	}
	return code;
}

- (long long)_modifierFlags {
	if (!GEOn()) return %orig;
	long long flags = %orig;
	if (gInside) return flags;
	gInside = YES;
	long long code = [self _keyCode];
	gInside = NO;
	if (isRemapped(code, flags)) return flags & ~(long long)kModShift;
	return flags;
}

- (NSString *)_modifiedInput {
	if (!GEOn()) return %orig;
	if (!gInside) {
		gInside = YES;
		BOOL remap = isRemapped([self _keyCode], [self _modifierFlags]);
		gInside = NO;
		if (remap) return @"\x1B";
	}
	return %orig;
}

- (NSString *)_unmodifiedInput {
	if (!GEOn()) return %orig;
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
	if (!GEOn()) return %orig;
	UIKeyboardHIDUsage code = %orig;
	if (gInside || code != kHIDGrave) return code;
	gInside = YES;
	long long flags = (long long)[self modifierFlags];
	gInside = NO;
	if (isRemapped(code, flags)) {
		return (UIKeyboardHIDUsage)kHIDEscape;
	}
	return code;
}

- (UIKeyModifierFlags)modifierFlags {
	if (!GEOn()) return %orig;
	UIKeyModifierFlags flags = %orig;
	if (gInside) return flags;
	gInside = YES;
	long long code = (long long)[self keyCode];
	gInside = NO;
	if (isRemapped(code, (long long)flags)) return (UIKeyModifierFlags)((long long)flags & ~(long long)kModShift);
	return flags;
}

- (NSString *)characters {
	if (!GEOn()) return %orig;
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
	if (!GEOn()) return %orig;
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
	static int token = 0;
	if (notify_register_dispatch(kEnabledState, &token, dispatch_get_main_queue(), ^(int t) { ReadState(t); }) == NOTIFY_STATUS_OK) ReadState(token);
	if (inSpringBoard()) {
		static int prefsToken = 0;
		notify_register_dispatch(kPrefsChanged, &prefsToken, dispatch_get_main_queue(), ^(int t) { PublishSwitch(); });
		PublishSwitch();
	}
}
