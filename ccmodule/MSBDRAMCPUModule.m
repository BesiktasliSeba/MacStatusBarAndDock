// MSBDRAMCPUModule.m -- RAM & CPU, our own Control Center module (MacRAMCPU.bundle), one implementation for iPadOS 15-18.
// The 2 x 1 tile: the available memory (large), the used memory under it, and the CPU load on the right. A tap opens the detail panel (Control
// Center's own expanded module): used / available / total memory with a bar, wired, compressed, active; the CPU load with a bar, user and system,
// the cores; the uptime. Numbers: common/SystemStats.h (the same as the tile drawn over Memory Magic's). Updated once a second, and only while
// the tile or the panel is really on the screen (a Control Center that is not showing -- BigSurCenter keeps iPadOS's own one hidden -- costs
// nothing). iPadOS 18 offers it in "Add a Control" (its gallery offers every module it can make, in the sizes the module names: 2 x 1).
// BigSurCenter (15/16) shows every module in a square tile of its own and does not open a module's panel on a tap (only a press and hold): the
// tile lays its lines out for the size it is really given (RAMCPULayout.h), and a tap there asks Control Center for the panel itself.
#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import <objc/message.h>
#include <sys/sysctl.h>
#include <unistd.h>
#include "../common/SystemStats.h"
#include "../common/ActMonText.h"   // (MSBD_ACTMON_OPEN_NOTE: the "Open Activity Monitor" button posts it; SpringBoard opens the window)
#include <notify.h>
#include "RAMCPULayout.h"   // (where the tile's lines go, 2 x 1 or square -- plain C, tested on the Mac: tools/test-ccmodule.sh)
// (a release-build feature marker, as StatusBar.x's: tools/verify-release-features.sh finds "msbd-feature:<name>" in the built bundle)
#define DM_FEATURE_MARK(name) do { static const char *const dmFeatureMark = "msbd-feature:" name; __asm__ volatile("" :: "r"(dmFeatureMark)); } while (0)

// (Control Center's own protocols, declared here by name -- the runtime takes them as ControlCenterUIKit's: they are matched by name)
@protocol CCUIContentModuleContentViewController <NSObject>
- (CGFloat)preferredExpandedContentHeight;
@optional
- (CGFloat)preferredExpandedContentWidth;
- (BOOL)shouldBeginTransitionToExpandedContentModule;
- (void)willTransitionToExpandedContentMode:(BOOL)expanded;
- (void)didTransitionToExpandedContentMode:(BOOL)expanded;
- (BOOL)providesOwnPlatter;
- (BOOL)shouldExpandModuleOnTouch:(id)touch;
- (void)controlCenterWillPresent;
- (void)controlCenterDidDismiss;
@end
@protocol CCUIContentModule <NSObject>
@optional
- (UIViewController<CCUIContentModuleContentViewController> *)contentViewController;
- (void)setContentModuleContext:(id)context;
@end

typedef struct { unsigned long long width, height; } MSBDModuleLayoutSize;   // (CCUIModuleLayoutSize)

static BOOL MSBDViewShows(UIView *v) {   // (on a window that shows, nothing above it hidden or clear)
    UIWindow *w = v.window;
    if (!w || w.hidden || w.alpha < 0.01) return NO;
    for (UIView *x = v; x; x = x.superview) if (x.hidden || x.alpha < 0.01) return NO;
    return YES;
}
static NSString *MSBDBytes(uint64_t bytes) { char b[32]; MSBDFormatBytes(bytes, b, sizeof b); return @(b); }
#if DEBUG
static void MSBDModuleLog(NSString *what) {   // (debug builds, with /tmp/macstatusbar-debug: into the status bar part's log)
    if (access("/tmp/macstatusbar-debug", F_OK) != 0) return;
    NSDateFormatter *f = [NSDateFormatter new]; f.dateFormat = @"HH:mm:ss.SSS";
    NSString *line = [NSString stringWithFormat:@"%@ [ramcpu] %@\n", [f stringFromDate:[NSDate date]], what];
    FILE *fp = fopen("/tmp/macstatusbar.log", "a");
    if (fp) { fputs(line.UTF8String, fp); fclose(fp); }
}
#else
#define MSBDModuleLog(...) do {} while (0)   // (variadic: an argument with commas inside [ ] -- a stringWithFormat: message -- is one argument only between ( ))
#endif

@interface MSBDRAMCPUViewController : UIViewController <CCUIContentModuleContentViewController, UIGestureRecognizerDelegate>
@property (nonatomic, weak) id moduleContext;   // (CCUIContentModuleContext: -requestExpandModule, for a tap where the host does not open the panel)
@end

@implementation MSBDRAMCPUViewController {
    UIView *_compact, *_detail;
    UILabel *_ramValue, *_ramCaption, *_usedLabel, *_cpuValue, *_cpuCaption, *_sqRamCaption, *_sqCpuCaption;
    UIView *_sqDivider;
    UITapGestureRecognizer *_tap;
    int _laidOutSquare;   // (-1: not laid out yet; the log line when the layout changes)
    UILabel *_title, *_memHeader, *_cpuHeader, *_memLabels[3], *_memValues[3], *_memExtra, *_cpuLabel, *_cpuValueBig, *_cpuExtra, *_uptime;
    UIButton *_openButton;
    UIView *_memTrack, *_memFill, *_cpuTrack, *_cpuFill;
    NSTimer *_timer;
    MSBDCPUTicks _ticks; BOOL _haveTicks;
    double _cpu; unsigned _cores;
    MSBDMemory _mem; BOOL _haveMem;
    BOOL _expanded;
    long long _gridSizeClass;
}

- (instancetype)initWithNibName:(NSString *)nib bundle:(NSBundle *)bundle {
    if ((self = [super initWithNibName:nib bundle:bundle])) { _cpu = -1.0; _gridSizeClass = 2; _laidOutSquare = -1; }
    return self;
}
- (UILabel *)label:(UIView *)parent size:(CGFloat)size weight:(UIFontWeight)weight alpha:(CGFloat)alpha digits:(BOOL)digits {
    UILabel *l = [UILabel new];
    l.font = digits ? [UIFont monospacedDigitSystemFontOfSize:size weight:weight] : [UIFont systemFontOfSize:size weight:weight];
    l.textColor = [UIColor colorWithWhite:1.0 alpha:alpha];
    l.adjustsFontSizeToFitWidth = YES; l.minimumScaleFactor = 0.7;
    [parent addSubview:l];
    return l;
}
- (UIView *)track:(UIView *)parent fill:(UIView **)fill {
    UIView *t = [UIView new]; t.backgroundColor = [UIColor colorWithWhite:1.0 alpha:0.16]; t.layer.cornerRadius = 3.0; t.clipsToBounds = YES;
    UIView *f = [UIView new]; f.backgroundColor = [UIColor systemGreenColor]; [t addSubview:f];
    [parent addSubview:t];
    *fill = f;
    return t;
}
- (void)loadView {
    UIView *v = [UIView new];
    v.backgroundColor = [UIColor clearColor];
    _compact = [UIView new]; [v addSubview:_compact];
    _ramValue = [self label:_compact size:17 weight:UIFontWeightSemibold alpha:1.0 digits:YES];
    _ramCaption = [self label:_compact size:10 weight:UIFontWeightMedium alpha:0.6 digits:NO]; _ramCaption.text = @"available";
    _usedLabel = [self label:_compact size:10 weight:UIFontWeightMedium alpha:0.6 digits:YES];
    _cpuValue = [self label:_compact size:17 weight:UIFontWeightSemibold alpha:1.0 digits:YES]; _cpuValue.textAlignment = NSTextAlignmentRight;
    _cpuCaption = [self label:_compact size:10 weight:UIFontWeightMedium alpha:0.6 digits:NO]; _cpuCaption.text = @"CPU"; _cpuCaption.textAlignment = NSTextAlignmentRight;
    // (the square tile's own lines: captions in small capitals, a thin line between the two, as the tile drawn over Memory Magic's)
    _sqRamCaption = [self label:_compact size:7.5 weight:UIFontWeightSemibold alpha:0.55 digits:NO]; _sqRamCaption.text = @"RAM AVAILABLE";
    _sqCpuCaption = [self label:_compact size:7.5 weight:UIFontWeightSemibold alpha:0.55 digits:NO]; _sqCpuCaption.text = @"CPU USED";
    _sqDivider = [UIView new]; _sqDivider.backgroundColor = [UIColor colorWithWhite:1.0 alpha:0.14]; [_compact addSubview:_sqDivider];
    _tap = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(dm_tapped:)];
    _tap.delegate = self; _tap.cancelsTouchesInView = NO;
    [_compact addGestureRecognizer:_tap];

    _detail = [UIView new]; _detail.hidden = YES; [v addSubview:_detail];
    _title = [self label:_detail size:17 weight:UIFontWeightBold alpha:1.0 digits:NO]; _title.text = @"RAM & CPU";
    _memHeader = [self label:_detail size:12 weight:UIFontWeightSemibold alpha:0.6 digits:NO]; _memHeader.text = @"MEMORY";
    NSArray *names = @[@"Used", @"Available", @"Total"];
    for (int i = 0; i < 3; i++) {
        _memLabels[i] = [self label:_detail size:15 weight:UIFontWeightRegular alpha:0.9 digits:NO]; _memLabels[i].text = names[i];
        _memValues[i] = [self label:_detail size:15 weight:UIFontWeightSemibold alpha:1.0 digits:YES]; _memValues[i].textAlignment = NSTextAlignmentRight;
    }
    UIView *fill = nil;
    _memTrack = [self track:_detail fill:&fill]; _memFill = fill;
    _memExtra = [self label:_detail size:11 weight:UIFontWeightRegular alpha:0.6 digits:YES];
    _cpuHeader = [self label:_detail size:12 weight:UIFontWeightSemibold alpha:0.6 digits:NO]; _cpuHeader.text = @"CPU";
    _cpuLabel = [self label:_detail size:15 weight:UIFontWeightRegular alpha:0.9 digits:NO]; _cpuLabel.text = @"Load";
    _cpuValueBig = [self label:_detail size:15 weight:UIFontWeightSemibold alpha:1.0 digits:YES]; _cpuValueBig.textAlignment = NSTextAlignmentRight;
    _cpuTrack = [self track:_detail fill:&fill]; _cpuFill = fill;
    _cpuExtra = [self label:_detail size:11 weight:UIFontWeightRegular alpha:0.6 digits:YES];
    _uptime = [self label:_detail size:11 weight:UIFontWeightRegular alpha:0.6 digits:YES];
    _openButton = [UIButton buttonWithType:UIButtonTypeSystem];
    [_openButton setTitle:@"Open Activity Monitor" forState:UIControlStateNormal];
    _openButton.titleLabel.font = [UIFont systemFontOfSize:14 weight:UIFontWeightSemibold];
    [_openButton setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    _openButton.backgroundColor = [UIColor colorWithWhite:1.0 alpha:0.14];
    _openButton.layer.cornerRadius = 9.0;
    [_openButton addTarget:self action:@selector(openActivityMonitor) forControlEvents:UIControlEventTouchUpInside];
    [_detail addSubview:_openButton];
    self.view = v;
    [self refreshLabels];
}
- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    CGRect b = self.view.bounds;
    _compact.frame = b; _detail.frame = b;
    // the tile: 2 x 1, the memory on the left and the CPU on the right; in a square tile (BigSurCenter's) the memory over the CPU
    if (!_expanded && b.size.width > 1.0 && b.size.height > 1.0) {   // (expanded: the tile's lines are hidden, the panel's size says nothing about the tile)
        CGRect f[kRCCount]; MSBDRAMCPUFrames(b, f);   // (RAMCPULayout.h)
        int square = MSBDRAMCPUSquare(b.size);
        if (square) DM_FEATURE_MARK("ramcpu-square-tile");
        _ramValue.frame = f[kRCRamValue]; _cpuValue.frame = f[kRCCpuValue];
        _ramCaption.frame = f[kRCRamCaption]; _usedLabel.frame = f[kRCUsed]; _cpuCaption.frame = f[kRCCpuCaption];
        _sqRamCaption.frame = f[kRCRamCaption]; _sqCpuCaption.frame = f[kRCCpuCaption]; _sqDivider.frame = f[kRCDivider];
        _ramCaption.hidden = _usedLabel.hidden = _cpuCaption.hidden = square;
        _sqRamCaption.hidden = _sqCpuCaption.hidden = _sqDivider.hidden = !square;
        UIFont *value = [UIFont monospacedDigitSystemFontOfSize:square ? 16.0 : 17.0 weight:UIFontWeightSemibold];
        _ramValue.font = value; _cpuValue.font = value;
        _cpuValue.textAlignment = square ? NSTextAlignmentLeft : NSTextAlignmentRight;
        if (square != _laidOutSquare) { _laidOutSquare = square; MSBDModuleLog([NSString stringWithFormat:@"tile laid out %@ (%.0f x %.0f)", square ? @"square" : @"2 x 1", b.size.width, b.size.height]); }
    }
    // the panel
    CGFloat x = 20.0, pw = b.size.width - 40.0, y = 18.0;
    _title.frame = CGRectMake(x, y, pw, 22.0); y += 34.0;
    _memHeader.frame = CGRectMake(x, y, pw, 15.0); y += 21.0;
    for (int i = 0; i < 3; i++) { _memLabels[i].frame = CGRectMake(x, y, pw * 0.5, 20.0); _memValues[i].frame = CGRectMake(x + pw * 0.5, y, pw * 0.5, 20.0); y += 24.0; }
    _memTrack.frame = CGRectMake(x, y + 2.0, pw, 6.0); y += 14.0;
    _memExtra.frame = CGRectMake(x, y, pw, 14.0); y += 28.0;
    _cpuHeader.frame = CGRectMake(x, y, pw, 15.0); y += 21.0;
    _cpuLabel.frame = CGRectMake(x, y, pw * 0.5, 20.0); _cpuValueBig.frame = CGRectMake(x + pw * 0.5, y, pw * 0.5, 20.0); y += 24.0;
    _cpuTrack.frame = CGRectMake(x, y + 2.0, pw, 6.0); y += 14.0;
    _cpuExtra.frame = CGRectMake(x, y, pw, 14.0); y += 24.0;
    _uptime.frame = CGRectMake(x, y, pw, 14.0); y += 22.0;
    _openButton.frame = CGRectMake(x, y, pw, 34.0);
    [self layoutBars];
}
- (void)layoutBars {
    double used = _haveMem && _mem.total ? (double)_mem.used / (double)_mem.total : 0.0, cpu = _cpu >= 0.0 ? _cpu : 0.0;
    _memFill.frame = CGRectMake(0, 0, _memTrack.bounds.size.width * used, _memTrack.bounds.size.height);
    _cpuFill.frame = CGRectMake(0, 0, _cpuTrack.bounds.size.width * cpu, _cpuTrack.bounds.size.height);
    _memFill.backgroundColor = used > 0.9 ? [UIColor systemRedColor] : (used > 0.75 ? [UIColor systemOrangeColor] : [UIColor systemGreenColor]);
    _cpuFill.backgroundColor = cpu > 0.85 ? [UIColor systemRedColor] : (cpu > 0.6 ? [UIColor systemOrangeColor] : [UIColor systemBlueColor]);
}
- (void)sample {
    MSBDMemory m;
    if (MSBDMemoryNow(&m)) { _mem = m; _haveMem = YES; }
    MSBDCPUTicks t;
    if (MSBDCPUTicksNow(&t)) {
        double load = _haveTicks ? MSBDCPULoadBetween(_ticks, t, NULL, NULL) : -1.0;
        if (load >= 0.0) _cpu = load;
        _ticks = t; _haveTicks = YES; _cores = t.cores;
    }
}
- (void)refreshLabels {
    _ramValue.text = _haveMem ? MSBDBytes(_mem.available) : @"–";
    _usedLabel.text = _haveMem ? [NSString stringWithFormat:@"%@ used", MSBDBytes(_mem.used)] : @"";
    NSString *cpu = _haveTicks && _cpu >= 0.0 ? [NSString stringWithFormat:@"%d%%", (int)lround(_cpu * 100.0)] : @"–";
    _cpuValue.text = cpu; _cpuValueBig.text = cpu;
    if (_haveMem) {
        _memValues[0].text = MSBDBytes(_mem.used); _memValues[1].text = MSBDBytes(_mem.available); _memValues[2].text = MSBDBytes(_mem.total);
        _memExtra.text = [NSString stringWithFormat:@"Wired %@  ·  Compressed %@  ·  Active %@", MSBDBytes(_mem.wired), MSBDBytes(_mem.compressed), MSBDBytes(_mem.active)];
    }
    // (no user / system split: iOS counts the kernel's time with the processes, its system counter stays 0 -- seen on 17.5 and 18.5)
    _cpuExtra.text = _haveTicks && _cpu >= 0.0 ? [NSString stringWithFormat:@"Idle %d%%  ·  %u cores", (int)lround((1.0 - _cpu) * 100.0), _cores] : @"";
    struct timeval boot; size_t len = sizeof(boot); int mib[2] = { CTL_KERN, KERN_BOOTTIME };
    if (sysctl(mib, 2, &boot, &len, NULL, 0) == 0 && boot.tv_sec > 0) {
        long up = (long)(time(NULL) - boot.tv_sec), d = up / 86400, hh = (up % 86400) / 3600, mm = (up % 3600) / 60;
        _uptime.text = d > 0 ? [NSString stringWithFormat:@"Up %ld d %ld h %ld min", d, hh, mm] : [NSString stringWithFormat:@"Up %ld h %ld min", hh, mm];
    }
    [self layoutBars];
}
- (void)tick {
    if (!MSBDViewShows(self.view)) return;   // (not on the screen: nothing sampled)
    [self sample];
    [self refreshLabels];
}
- (void)startUpdating {
    if (_timer) return;
    MSBDModuleLog(@"updating (on the screen)");
    [self sample];   // (the first CPU value needs two samples: it shows on the next tick, a quarter of a second later)
    [self refreshLabels];
    __weak typeof(self) weakSelf = self;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.25 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{ [weakSelf tick]; });
    _timer = [NSTimer timerWithTimeInterval:1.0 repeats:YES block:^(NSTimer *t) { [weakSelf tick]; }];
    _timer.tolerance = 0.2;
    [[NSRunLoop mainRunLoop] addTimer:_timer forMode:NSRunLoopCommonModes];
}
- (void)stopUpdating { if (_timer) MSBDModuleLog(@"stopped (off the screen)"); [_timer invalidate]; _timer = nil; }
- (void)viewWillAppear:(BOOL)animated { [super viewWillAppear:animated]; [self startUpdating]; }
- (void)viewDidDisappear:(BOOL)animated { [super viewDidDisappear:animated]; [self stopUpdating]; }
// A tap on the tile opens the panel. Control Center's own tile does that itself (-shouldExpandModuleOnTouch:); BigSurCenter's square tile only
// opens it on a press and hold, so a tap there did nothing (iPad 2, 16.7.7). Where the tile is not in Control Center's own module container --
// iPadOS 15 to 17, another tweak's Control Center around it -- this tap asks Control Center for the panel, unless it began opening meanwhile.
- (BOOL)dm_inControlCentersOwnTile {
    if ([NSProcessInfo processInfo].operatingSystemVersion.majorVersion >= 18) return YES;   // (18: no such tweaks; Control Center's tap only)
    Class own = NSClassFromString(@"CCUIContentModuleContainerView");
    for (UIView *v = self.view.superview; v; v = v.superview) if (own && [v isKindOfClass:own]) return YES;
    return NO;
}
- (BOOL)gestureRecognizerShouldBegin:(UIGestureRecognizer *)g { return g != _tap || (!_expanded && ![self dm_inControlCentersOwnTile]); }
- (BOOL)gestureRecognizer:(UIGestureRecognizer *)g shouldRecognizeSimultaneouslyWithGestureRecognizer:(UIGestureRecognizer *)other { return YES; }   // (never in the host's way)
- (void)dm_tapped:(UITapGestureRecognizer *)g {
    if (g.state != UIGestureRecognizerStateEnded || _expanded) return;
    DM_FEATURE_MARK("ramcpu-own-tap");
    __weak typeof(self) weakSelf = self;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.15 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        MSBDRAMCPUViewController *s = weakSelf;
        if (!s || s->_expanded) return;   // (the host opened it after all)
        id ctx = s.moduleContext;
        SEL expand = NSSelectorFromString(@"requestExpandModule");
        MSBDModuleLog([NSString stringWithFormat:@"tap in a host that does not open the panel: %@", [ctx respondsToSelector:expand] ? @"the panel asked for" : @"no module context"]);
        if ([ctx respondsToSelector:expand]) ((void (*)(id, SEL))objc_msgSend)(ctx, expand);
    });
}
- (void)controlCenterWillPresent { [self startUpdating]; }
- (void)controlCenterDidDismiss { [self stopUpdating]; }
- (void)dealloc { [_timer invalidate]; }

// Control Center: the panel
- (void)openActivityMonitor { notify_post(MSBD_ACTMON_OPEN_NOTE); }   // (SpringBoard dismisses Control Center and opens the window)
- (CGFloat)preferredExpandedContentHeight { return 340.0; }
- (CGFloat)preferredExpandedContentWidth { return 340.0; }
- (BOOL)shouldBeginTransitionToExpandedContentModule { return YES; }
- (BOOL)shouldExpandModuleOnTouch:(id)touch { return YES; }   // (a tap opens the panel)
- (BOOL)providesOwnPlatter { return NO; }
- (void)willTransitionToExpandedContentMode:(BOOL)expanded {
    _expanded = expanded;
    _compact.hidden = expanded; _detail.hidden = !expanded;
    [self.view setNeedsLayout];
    if (expanded) { [self sample]; [self refreshLabels]; }
}
- (MSBDModuleLayoutSize)moduleLayoutSizeForOrientation:(long long)orientation { MSBDModuleLayoutSize s = { 2, 1 }; return s; }   // (15-17: 2 x 1)
- (long long)gridSizeClass { return _gridSizeClass; }   // (18)
- (void)setGridSizeClass:(long long)c { _gridSizeClass = c; [self.view setNeedsLayout]; }
@end

@interface MSBDRAMCPUModule : NSObject <CCUIContentModule>
@end
@implementation MSBDRAMCPUModule {
    MSBDRAMCPUViewController *_content;
    id _context;   // (held, as Apple's modules hold theirs: Control Center keeps no other hold on it -- a weak one was nil when a tap needed it)
}
- (UIViewController<CCUIContentModuleContentViewController> *)contentViewController {
    if (!_content) { _content = [MSBDRAMCPUViewController new]; _content.moduleContext = _context; }
    return _content;
}
- (void)setContentModuleContext:(id)context {
    _context = context; _content.moduleContext = context;
    MSBDModuleLog([NSString stringWithFormat:@"module context: %@", context ? NSStringFromClass([context class]) : @"none"]);
}
- (unsigned long long)supportedGridSizeClasses { return 1ull << 2; }   // (18: smallWide, 2 x 1 -- 1 << the grid size class; Focus answers the same)
- (BOOL)expandsGridSizeClassesForAccessibility { return NO; }
@end
