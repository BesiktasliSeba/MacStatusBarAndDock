// MSBDSSHModule.m -- SSH, our own Control Center control (MacSSH.bundle, 1.7.6 item 1), one implementation for iPadOS 15-18.
// Apple's own round toggle: Control Center's menu module view controller (ControlCenterUIKit's CCUIMenuModuleViewController, a button module), with
// a terminal glyph, tinted when SSH is on. A tap switches SSH; a press and hold opens Apple's expanded module: "SSH", On or Off, and the iPad's address
// with the command to log in, as a Mac's Sharing pane gives them for Remote Login -- nothing more. The switching itself is the one logic every switch
// of ours uses (common/SSHSwitch.h: the wish, the root helper, its answer): Settings' SSH row, the menu bar's SSH icon and this control always show
// the helper's one state, and follow its notification, also when SSH is switched elsewhere while Control Center is open. A switch that did not
// happen shows the real state again and the reason (the expanded module opens with it, and VoiceOver reads it).
// Offered only with OpenSSH installed and while our parts load (common/CCModuleRegister.h: the bundle's folder is not in Control Center's
// repository otherwise -- the tweak off, Safe Mode, an untested iPadOS, the crash guard's step 1b). iPadOS 18: 1 x 1, listed under Settings in
// "Add a Control" (its module settings, CCModuleRegister.h).
#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import <objc/message.h>
#include "../common/SSHSwitch.h"
#include "../common/DriveEject.h"   // (MSBDEjectHelperRunning: the root helper is there -- it publishes its pid for every request of ours)
// (a release-build feature marker, as RAM & CPU's: tools/verify-release-features.sh finds "msbd-feature:<name>" in the built bundle)
#define DM_FEATURE_MARK(name) do { static const char *const dmFeatureMark = "msbd-feature:" name; __asm__ volatile("" :: "r"(dmFeatureMark)); } while (0)

// (ControlCenterUIKit's classes, as 15.6.1 and 18.5 have them; this bundle links the framework, Control Center has it loaded)
@interface CCUIButtonModuleViewController : UIViewController
- (void)setGlyphImage:(UIImage *)image;
- (void)setSelectedGlyphImage:(UIImage *)image;
- (void)setSelectedGlyphColor:(UIColor *)color;
- (void)setSelected:(BOOL)selected;
- (BOOL)isSelected;
- (BOOL)isExpanded;
- (UIView *)buttonView;
- (void)buttonTapped:(id)sender forEvent:(UIEvent *)event;
@end
@interface CCUIMenuModuleViewController : CCUIButtonModuleViewController
- (void)setTitle:(NSString *)title;
- (void)setSubtitle:(NSString *)subtitle;
- (void)setCustomContentView:(UIView *)view;
- (void)setHideGlyphInHeader:(BOOL)hide;
- (void)setContentModuleContext:(id)context;
- (id)contentModuleContext;
- (CGFloat)preferredExpandedContentHeight;
- (CGFloat)preferredExpandedContentWidth;
- (BOOL)shouldBeginTransitionToExpandedContentModule;
- (void)willTransitionToExpandedContentMode:(BOOL)expanded;
@end
@protocol CCUIContentModule <NSObject>
@optional
- (UIViewController *)contentViewController;
- (void)setContentModuleContext:(id)context;
@end

#if DEBUG
static void MSBDSSHLog(NSString *what) {   // (debug builds, with /tmp/macstatusbar-debug: into the status bar part's log)
    if (access("/tmp/macstatusbar-debug", F_OK) != 0) return;
    NSDateFormatter *f = [NSDateFormatter new]; f.dateFormat = @"HH:mm:ss.SSS";
    NSString *line = [NSString stringWithFormat:@"%@ [sshcc] %@\n", [f stringFromDate:[NSDate date]], what];
    FILE *fp = fopen("/tmp/macstatusbar.log", "a");
    if (fp) { fputs(line.UTF8String, fp); fclose(fp); }
}
#else
#define MSBDSSHLog(...) do {} while (0)
#endif

static const CGFloat kSSHInfoHeight = 58.0, kSSHInfoReasonHeight = 38.0;   // (the expanded module's lines under Apple's header: the address and the command; the reason, two lines, above them when there is one)

// Those lines: laid out for the size Apple's menu gives them (its custom content view)
@interface MSBDSSHInfoView : UIView
@property (nonatomic, readonly) UILabel *reasonLine, *addressLine, *commandLine;
@end
@implementation MSBDSSHInfoView
- (UILabel *)line:(CGFloat)size weight:(UIFontWeight)weight alpha:(CGFloat)alpha mono:(BOOL)mono {
    UILabel *l = [UILabel new];
    l.font = mono ? [UIFont monospacedSystemFontOfSize:size weight:weight] : [UIFont systemFontOfSize:size weight:weight];
    l.textColor = [UIColor colorWithWhite:1.0 alpha:alpha];
    l.adjustsFontSizeToFitWidth = YES; l.minimumScaleFactor = 0.75;
    [self addSubview:l];
    return l;
}
- (instancetype)initWithFrame:(CGRect)frame {
    if ((self = [super initWithFrame:frame])) {
        _reasonLine = [self line:13 weight:UIFontWeightSemibold alpha:1.0 mono:NO]; _reasonLine.textColor = [UIColor systemOrangeColor];
        _reasonLine.numberOfLines = 2; _reasonLine.adjustsFontSizeToFitWidth = NO; _reasonLine.lineBreakMode = NSLineBreakByWordWrapping;
        _addressLine = [self line:15 weight:UIFontWeightRegular alpha:0.9 mono:NO];
        _commandLine = [self line:13 weight:UIFontWeightRegular alpha:0.6 mono:YES];
    }
    return self;
}
- (void)layoutSubviews {
    [super layoutSubviews];
    CGFloat x = 16.0, w = MAX(0.0, self.bounds.size.width - 32.0), y = 8.0;
    if (_reasonLine.text.length) { _reasonLine.frame = CGRectMake(x, y, w, 34.0); y += 38.0; } else _reasonLine.frame = CGRectZero;
    _addressLine.frame = CGRectMake(x, y, w, 20.0); y += 24.0;
    _commandLine.frame = CGRectMake(x, y, w, 18.0);
}
@end

@interface MSBDSSHViewController : CCUIMenuModuleViewController
@end

@implementation MSBDSSHViewController {
    MSBDSSHInfoView *_info;
    int _stateToken;
    BOOL _pending; int _want; MSBDSSHState _before; unsigned _request;   // (the request this control is waiting for an answer to)
    NSString *_reason; CFAbsoluteTime _reasonAt;                          // (the last switch that did not happen, and when)
}

- (instancetype)initWithNibName:(NSString *)nib bundle:(NSBundle *)bundle {
    if ((self = [super initWithNibName:nib bundle:bundle])) _stateToken = NOTIFY_TOKEN_INVALID;
    return self;
}
- (void)dealloc { if (_stateToken != NOTIFY_TOKEN_INVALID) notify_cancel(_stateToken); }

- (void)viewDidLoad {
    [super viewDidLoad];
    UIImageSymbolConfiguration *cfg = [UIImageSymbolConfiguration configurationWithPointSize:22 weight:UIImageSymbolWeightMedium];
    UIImage *glyph = [[UIImage systemImageNamed:@"terminal.fill" withConfiguration:cfg] imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate];
    if (glyph) { [self setGlyphImage:glyph]; [self setSelectedGlyphImage:glyph]; }
    [self setSelectedGlyphColor:[UIColor systemBlueColor]];
    // (the expanded module's header: "SSH" and On / Off only -- the round glyph there is smaller than the tile's and drew the terminal glyph over
    //  its selected disc's edges, a white diamond, A12Z 18.5)
    if ([self respondsToSelector:@selector(setHideGlyphInHeader:)]) [self setHideGlyphInHeader:YES];
    [self setTitle:@"SSH"];
    // (Apple's menu takes a custom view's height from its frame -- -scrollViewContentHeightForWidth:, 18.5 -- and leaves its frame to it: given
    //  here, its width follows the menu's in -viewDidLayoutSubviews. A view made with no frame showed an empty panel, A12Z)
    _info = [[MSBDSSHInfoView alloc] initWithFrame:CGRectMake(0, 0, 320.0, kSSHInfoHeight)];
    if ([self respondsToSelector:@selector(setCustomContentView:)]) [self setCustomContentView:_info];
    __weak typeof(self) weakSelf = self;
    notify_register_dispatch(kMSBDSSHStateNote, &_stateToken, dispatch_get_main_queue(), ^(int t) { [weakSelf stateChanged]; });
    [self refresh];
    DM_FEATURE_MARK("ssh-cc-control");
}
- (void)viewWillAppear:(BOOL)animated { [super viewWillAppear:animated]; [self refresh]; }

// What the control shows: the helper's state (or the wish while waiting for its answer), and in the expanded module the address and the reason.
- (BOOL)showsOn {
    if (_pending) return _want;
    return MSBDSSHReadState().on != 0;   // (no state yet -- no helper has run: OpenSSH is on unless switched off, as Settings' row reads it)
}
- (void)refresh {
    if (!self.isViewLoaded) return;
    BOOL on = [self showsOn];
    [self setSelected:on];
    [self setSubtitle:on ? @"On" : @"Off"];
    char addr[INET_ADDRSTRLEN + 8]; MSBDSSHAddress(addr, sizeof(addr));
    _info.addressLine.text = addr[0] ? [NSString stringWithFormat:@"Address: %s", addr] : @"No network address";
    _info.commandLine.text = on && addr[0] ? [NSString stringWithFormat:@"ssh mobile@%s", addr] : @"";
    BOOL recent = _reason && CFAbsoluteTimeGetCurrent() - _reasonAt < 60.0;
    _info.reasonLine.text = recent ? _reason : @"";
    CGFloat h = kSSHInfoHeight + (recent ? kSSHInfoReasonHeight : 0.0);   // (Apple's menu takes the height from the frame)
    if (fabs(_info.frame.size.height - h) > 0.5) _info.frame = CGRectMake(_info.frame.origin.x, _info.frame.origin.y, _info.frame.size.width, h);
    [_info setNeedsLayout];
    UIView *button = [self respondsToSelector:@selector(buttonView)] ? [self buttonView] : nil;
    button.accessibilityLabel = @"SSH";
    button.accessibilityValue = on ? @"On" : @"Off";
}

// A tap: SSH the other way, through the one logic (the wish, the helper); the control shows the wish until the helper answers.
- (void)buttonTapped:(id)sender forEvent:(UIEvent *)event {
    int want = ![self showsOn];
    MSBDSSHLog([NSString stringWithFormat:@"tapped: asking for %@", want ? @"on" : @"off"]);
    if (!MSBDSSHInstalled()) { [self failed:MSBDSSHReason(kMSBDSSHResultNotInstalled, want) want:want]; return; }
    if (!MSBDEjectHelperRunning()) { [self failed:MSBDSSHNoHelperReason() want:want]; return; }
    _before = MSBDSSHReadState(); _want = want; _pending = YES; _reason = nil;
    unsigned mine = ++_request;
    MSBDSSHAsk(want);
    [self refresh];
    __weak typeof(self) weakSelf = self;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(10.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{   // (the helper waits 2 s at most before it acts)
        typeof(self) me = weakSelf;
        if (!me || !me->_pending || me->_request != mine) return;
        [me failed:MSBDSSHNoAnswerReason() want:me->_want];
    });
}
- (void)stateChanged {
    if (_pending) {
        MSBDSSHState now = MSBDSSHReadState();
        MSBDSSHOutcome o = MSBDSSHJudge(_before, now, _want);
        if (o == kMSBDSSHWaiting) return;
        _pending = NO;
        MSBDSSHLog([NSString stringWithFormat:@"the helper answered: SSH %@ (%@)", now.on ? @"on" : @"off", o == kMSBDSSHDone ? @"done" : (o == kMSBDSSHFailed ? @"failed" : @"another wish since")]);
        if (o == kMSBDSSHFailed) { [self failed:MSBDSSHReason(now.result, _want) want:_want]; return; }
    }
    [self refresh];
}
// Not switched: the real state again, and why -- in the expanded module (opened for it while Control Center shows this control) and for VoiceOver.
- (void)failed:(const char *)why want:(int)want {
    _pending = NO;
    _reason = [NSString stringWithFormat:@"Could not turn SSH %@: %s", want ? @"on" : @"off", why];
    _reasonAt = CFAbsoluteTimeGetCurrent();
    MSBDSSHLog(_reason);
    [self refresh];
    UIAccessibilityPostNotification(UIAccessibilityAnnouncementNotification, _reason);
    BOOL shown = self.view.window && !self.view.window.hidden && !([self respondsToSelector:@selector(isExpanded)] && [self isExpanded]);
    id ctx = [self respondsToSelector:@selector(contentModuleContext)] ? [self contentModuleContext] : nil;
    SEL expand = NSSelectorFromString(@"requestExpandModule");
    if (shown && [ctx respondsToSelector:expand]) ((void (*)(id, SEL))objc_msgSend)(ctx, expand);
}

// The expanded module: Apple's header (the glyph, "SSH", On / Off), then our lines -- sized by Apple's menu from their frame
- (BOOL)shouldBeginTransitionToExpandedContentModule { return YES; }
- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    UIView *host = _info.superview;
    if (host && fabs(_info.frame.size.width - host.bounds.size.width) > 0.5) _info.frame = CGRectMake(0, _info.frame.origin.y, host.bounds.size.width, _info.frame.size.height);
}
- (void)willTransitionToExpandedContentMode:(BOOL)expanded {
    [super willTransitionToExpandedContentMode:expanded];
    if (expanded) [self refresh];   // (the address now, and the reason while it is recent)
}
@end

@interface MSBDSSHModule : NSObject <CCUIContentModule>
@end
@implementation MSBDSSHModule {
    MSBDSSHViewController *_content;
    id _context;   // (held, as Apple's modules hold theirs: Control Center keeps no other hold on it)
}
- (UIViewController *)contentViewController {
    if (!_content) {
        _content = [[MSBDSSHViewController alloc] initWithNibName:nil bundle:nil];
        if (_context) [_content setContentModuleContext:_context];
    }
    return _content;
}
- (void)setContentModuleContext:(id)context {
    _context = context;
    if (_content) [_content setContentModuleContext:context];
}
- (unsigned long long)supportedGridSizeClasses { return 1ull << 0; }   // (18: small, 1 x 1 -- Apple's round toggle)
- (BOOL)expandsGridSizeClassesForAccessibility { return NO; }
@end
