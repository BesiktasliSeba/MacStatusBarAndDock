// ActivityMonitor.h -- our Activity Monitor window (1.7.0), a native window (NativeWindow.h) like Finder's and TextEdit's, included into StatusBar.x
// after TextWindow.h. A Mac-style window: a unified toolbar with the five tabs (CPU, Memory, Energy, Disk, Network), a Quit and an Inspect button, a
// view filter and a search field; a sortable table of processes; a bottom summary with the device totals. One window (opening it again brings it
// forward). The figures come from ProcList.h (the same process-stats reads as the RAM & CPU tile) and common/SystemStats.h (the device totals), and
// %CPU is worked out between two refreshes with common/ProcSample.h, as on a Mac.
//  - This build fills the CPU, Memory and Disk columns for every process the window may read as the user SpringBoard runs as. Processes it cannot
//    read show by name with "–" (the rest arrives with the reader planned in the build plan). Energy and Network list by name for now.
//  - It samples every 2 s and only while the window is really on screen, like the Mac's 1-5 s refresh and like the RAM & CPU module; the reading is
//    done on a queue of its own, one at a time, and the window takes it on the main thread (dm_sample).
#import <UIKit/UIKit.h>
#include "ProcList.h"
#include "../common/ActMonText.h"   // (the plain lines where a figure is not available; Mac-tested)
#include "ActMonColumns.h"   // (each tab's column titles and where its columns sit; Mac test tools/test-actmoncolumns.sh)

typedef NS_ENUM(NSInteger, DMAMTab) { DMAMTabCPU = 0, DMAMTabMemory, DMAMTabEnergy, DMAMTabDisk, DMAMTabNetwork };
typedef NS_ENUM(NSInteger, DMAMFilter) { DMAMFilterAll = 0, DMAMFilterMine, DMAMFilterSystem };

@interface DMActivityMonitorWindow : DMNativeWindow <UITableViewDataSource, UITableViewDelegate, UISearchBarDelegate>
@end

@implementation DMActivityMonitorWindow {
    UIView *_toolbarBack, *_toolbar, *_headerBar, *_summaryBar;
    UISegmentedControl *_tabs;
    UIButton *_quit, *_inspect, *_filterButton;
    UISearchBar *_search;
    UITableView *_list;
    UILabel *_cols[5]; NSInteger _colCount;
    UILabel *_sumLeft, *_sumRight, *_note; UIView *_memTrack, *_memFill;
    NSArray<DMProcInfo *> *_all, *_rows;
    NSMutableDictionary<NSNumber *, NSNumber *> *_prevCpu;
    NSTimer *_timer;
    DMAMTab _tab; DMAMFilter _filter; NSString *_query;
    NSInteger _sortCol; BOOL _sortDesc;
    MSBDCPUTicks _ticks; BOOL _haveTicks; double _cpuLoad, _cpuUser, _cpuSystem; unsigned _cores;
    MSBDMemory _mem; BOOL _haveMem;
    DMProcInfo *_selected;
    BOOL _sampling, _secondSoon; uint64_t _lastWall;   // (a snapshot being read on its queue; the quick second reading due; the last one's time)
}

- (instancetype)initWithFrame:(CGRect)frame {
    if (!(self = [super initWithTitle:@"Activity Monitor" frame:frame])) return nil;
    self.appName = @"Activity Monitor";
    self.titleBarHeight = 52.0; self.fullSizeContent = YES; self.showsTitle = NO;
    self.minSize = CGSizeMake(520, 320);
    _prevCpu = [NSMutableDictionary dictionary];
    _tab = DMAMTabCPU; _filter = DMAMFilterAll; _query = @""; _sortCol = 1; _sortDesc = YES;   // (CPU tab: sort by %CPU, descending)
    UIView *c = self.contentView;

    _toolbarBack = [UIView new]; _toolbarBack.backgroundColor = [UIColor systemBackgroundColor]; [c addSubview:_toolbarBack];
    _toolbar = [UIView new]; [self.titleBar addSubview:_toolbar];
    _tabs = [[UISegmentedControl alloc] initWithItems:@[@"CPU", @"Memory", @"Energy", @"Disk", @"Network"]];
    _tabs.selectedSegmentIndex = 0;
    [_tabs addTarget:self action:@selector(dm_tabChanged) forControlEvents:UIControlEventValueChanged];
    [_toolbar addSubview:_tabs];
    _quit = [UIButton buttonWithType:UIButtonTypeSystem];
    [_quit setImage:[UIImage systemImageNamed:@"xmark.octagon"] forState:UIControlStateNormal];
    [_quit addTarget:self action:@selector(dm_quitTapped) forControlEvents:UIControlEventTouchUpInside];
    _quit.enabled = NO;   // (wired in the Quit/Inspect step of the build plan; apps only, through our existing Force Quit)
    [_toolbar addSubview:_quit];
    _inspect = [UIButton buttonWithType:UIButtonTypeSystem];
    [_inspect setImage:[UIImage systemImageNamed:@"info.circle"] forState:UIControlStateNormal];
    [_inspect addTarget:self action:@selector(dm_inspectTapped) forControlEvents:UIControlEventTouchUpInside];
    _inspect.enabled = NO;
    [_toolbar addSubview:_inspect];
    _filterButton = [UIButton buttonWithType:UIButtonTypeSystem];
    _filterButton.titleLabel.font = [UIFont systemFontOfSize:13.0];
    [_filterButton addTarget:self action:@selector(dm_filterTapped) forControlEvents:UIControlEventTouchUpInside];
    [_toolbar addSubview:_filterButton];
    _search = [UISearchBar new]; _search.searchBarStyle = UISearchBarStyleMinimal; _search.placeholder = @"Search"; _search.delegate = self;
    [_toolbar addSubview:_search];

    _headerBar = [UIView new]; _headerBar.backgroundColor = [UIColor secondarySystemBackgroundColor]; [c addSubview:_headerBar];
    for (int i = 0; i < 5; i++) {
        UILabel *l = [UILabel new]; l.font = [UIFont systemFontOfSize:11.0 weight:UIFontWeightSemibold]; l.textColor = [UIColor secondaryLabelColor];
        l.userInteractionEnabled = YES; l.tag = 500 + i;
        [l addGestureRecognizer:[[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(dm_headerTapped:)]];
        [_headerBar addSubview:l]; _cols[i] = l;
    }
    _list = [[UITableView alloc] initWithFrame:CGRectZero style:UITableViewStylePlain];
    _list.dataSource = self; _list.delegate = self; _list.rowHeight = 28.0;
    _list.separatorInset = UIEdgeInsetsZero;
    if (@available(iOS 15.0, *)) _list.sectionHeaderTopPadding = 0;
    [c addSubview:_list];

    _summaryBar = [UIView new]; _summaryBar.backgroundColor = [UIColor secondarySystemBackgroundColor]; [c addSubview:_summaryBar];
    _sumLeft = [UILabel new]; _sumLeft.font = [UIFont monospacedDigitSystemFontOfSize:12.0 weight:UIFontWeightRegular]; _sumLeft.textColor = [UIColor labelColor]; [_summaryBar addSubview:_sumLeft];
    _sumRight = [UILabel new]; _sumRight.font = [UIFont monospacedDigitSystemFontOfSize:12.0 weight:UIFontWeightRegular]; _sumRight.textColor = [UIColor secondaryLabelColor]; _sumRight.textAlignment = NSTextAlignmentRight; [_summaryBar addSubview:_sumRight];
    _memTrack = [UIView new]; _memTrack.backgroundColor = [UIColor colorWithWhite:0.5 alpha:0.25]; _memTrack.layer.cornerRadius = 3.0; _memTrack.clipsToBounds = YES; [_summaryBar addSubview:_memTrack];
    _memFill = [UIView new]; _memFill.backgroundColor = [UIColor systemGreenColor]; [_memTrack addSubview:_memFill];
    _note = [UILabel new]; _note.font = [UIFont systemFontOfSize:10.5]; _note.textColor = [UIColor tertiaryLabelColor]; [_summaryBar addSubview:_note];

    [self dm_updateFilterTitle];
    [self dm_applyColumns];
    DM_FEATURE_MARK("activity-monitor");
    return self;
}

// ---- layout ----
- (void)layoutSubviews {
    [super layoutSubviews];
    CGRect b = self.contentView.bounds; CGFloat tb = self.titleBarHeight, w = b.size.width;
    CGFloat lead = 80.0, cy = (tb - 30.0) / 2.0;   // (room for the traffic lights at the left of the unified toolbar)
    _toolbarBack.frame = CGRectMake(0, 0, w, tb);
    _toolbar.frame = CGRectMake(0, 0, w, tb);
    // right to left: Inspect, Quit, Search, Filter; the tabs fill what is left between the lights and the filter (so nothing overlaps)
    CGFloat rx = w - 10.0;
    _inspect.frame = CGRectMake(rx - 32, cy, 32, 30); rx -= 38;
    _quit.frame = CGRectMake(rx - 32, cy, 32, 30); rx -= 40;
    CGFloat searchW = MIN(180.0, MAX(110.0, w * 0.22));
    _search.frame = CGRectMake(rx - searchW, (tb - 34.0) / 2.0, searchW, 34.0); rx -= searchW + 8;
    [_filterButton sizeToFit];
    CGFloat fw = MIN(150.0, _filterButton.bounds.size.width + 10);
    BOOL showFilter = (rx - fw - 10 - lead) >= 200.0;   // (too narrow: hide the filter button, the tabs keep the room)
    _filterButton.hidden = !showFilter;
    if (showFilter) { _filterButton.frame = CGRectMake(rx - fw, cy, fw, 30.0); rx -= fw + 10; }
    CGFloat tabsW = MIN(360.0, MAX(200.0, rx - lead));
    _tabs.frame = CGRectMake(lead, cy, tabsW, 30.0);

    // content sits BELOW the unified toolbar (fullSizeContent: the content view reaches up under the title bar)
    CGFloat headerH = 22.0, sumH = 48.0, row1 = 26.0;   // the summary bar: the device totals on top, the plain note under them
    _headerBar.frame = CGRectMake(0, tb, w, headerH);
    _list.frame = CGRectMake(0, tb + headerH, w, b.size.height - tb - headerH - sumH);
    _summaryBar.frame = CGRectMake(0, b.size.height - sumH, w, sumH);
    [self dm_layoutColumns:w];
    CGFloat barW = 150.0;
    _memTrack.frame = CGRectMake(w - 14 - barW, (row1 - 6) / 2.0, barW, 6.0);
    _memFill.frame = CGRectMake(0, 0, _memTrack.bounds.size.width * ((_haveMem && _mem.total) ? (double)_mem.used / _mem.total : 0.0), 6.0);
    _sumLeft.frame = CGRectMake(14, 0, w * 0.42 - 20, row1);
    _sumRight.frame = CGRectMake(w * 0.40, 0, (_tab == DMAMTabMemory ? (w - 28 - barW) : (w - 14)) - w * 0.40, row1);
    _note.frame = CGRectMake(14, row1, w - 28, sumH - row1);
}

// the column x positions: a wide Name column, then the per-tab metric columns on the right (ActMonColumns.h)
- (NSArray<NSNumber *> *)dm_columnEdges:(CGFloat)w {
    double e[MSBD_AM_MAX_COLUMNS]; int n = MSBDActMonColumnEdges((int)_tab, w, e);
    NSMutableArray<NSNumber *> *edges = [NSMutableArray arrayWithCapacity:n];
    for (int i = 0; i < n; i++) [edges addObject:@(e[i])];
    return edges;
}
- (void)dm_layoutColumns:(CGFloat)w {
    NSArray<NSNumber *> *edges = [self dm_columnEdges:w];
    for (int i = 0; i < 5; i++) {
        if (i >= _colCount) { _cols[i].hidden = YES; continue; }
        _cols[i].hidden = NO;
        CGFloat x = [edges[i] doubleValue], nx = (i + 1 < (int)edges.count) ? [edges[i + 1] doubleValue] : w - kMSBDAMRightInset;
        _cols[i].frame = CGRectMake(x, 0, nx - x - kMSBDAMColumnGap, 22);
        _cols[i].textAlignment = (i == 0) ? NSTextAlignmentLeft : NSTextAlignmentRight;
    }
}
- (void)dm_applyColumns {
    const char *titles[MSBD_AM_MAX_COLUMNS];
    _colCount = MSBDActMonTitles((int)_tab, titles);
    for (int i = 0; i < 5; i++) _cols[i].text = (i < _colCount) ? @(titles[i]) : @"";
    [self dm_markSortColumn];
    [self setNeedsLayout];
}
- (void)dm_markSortColumn {
    for (int i = 0; i < _colCount; i++) {
        NSString *base = [_cols[i].text stringByTrimmingCharactersInSet:[NSCharacterSet characterSetWithCharactersInString:@" ↑↓"]];
        _cols[i].text = (i == _sortCol) ? [base stringByAppendingString:(_sortDesc ? @" ↓" : @" ↑")] : base;
    }
}

// ---- data ----
// The snapshot -- every process's figures, a few reads per process, tens of ms on a busy iPad -- is read on a queue of its own, never on SpringBoard's
// main thread; the window takes it there. One at a time: a refresh asked while one is still being read is left out (the next one comes 2 s later).
static dispatch_queue_t DMAMSampleQueue(void) {
    static dispatch_queue_t q; static dispatch_once_t once;
    dispatch_once(&once, ^{ q = dispatch_queue_create("com.besiktasliseba.activitymonitor.sample", dispatch_queue_attr_make_with_qos_class(DISPATCH_QUEUE_SERIAL, QOS_CLASS_UTILITY, 0)); });
    return q;
}
- (void)dm_sample {
    if (_sampling) return;
    _sampling = YES;
    __weak typeof(self) ws = self;
    dispatch_async(DMAMSampleQueue(), ^{
        NSArray<DMProcInfo *> *snap = DMProcListSnapshot();
        uint64_t at = mach_absolute_time();   // (the readings' time, for %CPU: right after them, as before)
        MSBDMemory m; BOOL mem = MSBDMemoryNow(&m);
        MSBDCPUTicks t; BOOL ticks = MSBDCPUTicksNow(&t);
        dispatch_async(dispatch_get_main_queue(), ^{ [ws dm_took:snap at:at memory:m haveMemory:mem ticks:t haveTicks:ticks]; });
    });
}
- (void)dm_took:(NSArray<DMProcInfo *> *)snap at:(uint64_t)nowMach memory:(MSBDMemory)m haveMemory:(BOOL)haveMem ticks:(MSBDCPUTicks)t haveTicks:(BOOL)haveTicks {
    _sampling = NO;
    NSMutableDictionary<NSNumber *, NSNumber *> *nowCpu = [NSMutableDictionary dictionaryWithCapacity:snap.count];
    uint64_t wallNs = 0; static mach_timebase_info_data_t tbi; if (!tbi.denom) mach_timebase_info(&tbi);
    if (_lastWall) wallNs = MSBDMachTicksToNs(nowMach - _lastWall, tbi.numer, tbi.denom);
    _lastWall = nowMach;
    for (DMProcInfo *p in snap) {
        if (p.haveStats) {
            nowCpu[@(p.pid)] = @(p.cpuNs);
            NSNumber *prev = _prevCpu[@(p.pid)];
            if (prev && wallNs) p.cpuPercent = MSBDProcCPUPercent(prev.unsignedLongLongValue, p.cpuNs, wallNs);
        }
    }
    _prevCpu = nowCpu;
    _all = snap;
    if (haveMem) { _mem = m; _haveMem = YES; }
    if (haveTicks) {
        if (_haveTicks) { double u = 0, s = 0, l = MSBDCPULoadBetween(_ticks, t, &u, &s); if (l >= 0) { _cpuLoad = l; _cpuUser = u; _cpuSystem = s; } }
        _ticks = t; _haveTicks = YES; _cores = t.cores;
    }
    [self dm_rebuildRowsInPlace:YES];
    [self dm_updateSummary];
    if (_secondSoon) {   // (the first %CPU needs two readings: the second one 0.3 s after the first is in)
        _secondSoon = NO;
        __weak typeof(self) ws = self;
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.3 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{ if ([ws dm_onScreen]) [ws dm_sample]; });
    }
}
- (double)dm_metric:(DMProcInfo *)p {
    switch (_tab) {
        case DMAMTabCPU:    return p.cpuPercent;
        case DMAMTabMemory: return p.footprint;
        case DMAMTabDisk:   return p.disk;
        default:            return 0;   // Energy / Network: no per-process metric in this build
    }
}
- (void)dm_rebuildRows { [self dm_rebuildRowsInPlace:NO]; }   // (a tab, a sort, the filter, a search: the whole list again)
// The rows, sorted and filtered. In place (the 2 s refresh): no -reloadData -- the visible rows are filled again where they stand (only what
// changed is drawn, -dm_fillCell:), rows a process list grew or shrank by are added or taken off the end, without animation.
- (void)dm_rebuildRowsInPlace:(BOOL)inPlace {
    NSString *q = [_query lowercaseString];
    NSMutableArray<DMProcInfo *> *rows = [NSMutableArray array];
    for (DMProcInfo *p in _all) {
        if (_filter == DMAMFilterMine && p.uid == 0) continue;
        if (_filter == DMAMFilterSystem && p.uid != 0) continue;
        if (q.length && [p.name.lowercaseString rangeOfString:q].location == NSNotFound) continue;
        [rows addObject:p];
    }
    [rows sortUsingComparator:^NSComparisonResult(DMProcInfo *a, DMProcInfo *b) {
        NSComparisonResult r;
        if (_sortCol == 0) r = [a.name localizedCaseInsensitiveCompare:b.name];
        else if (_sortCol == _colCount - 1) r = (a.pid < b.pid ? NSOrderedAscending : a.pid > b.pid ? NSOrderedDescending : NSOrderedSame);
        else if (_tab == DMAMTabCPU && _sortCol == 3) r = (a.threads < b.threads ? NSOrderedAscending : a.threads > b.threads ? NSOrderedDescending : NSOrderedSame);
        else if (_tab != DMAMTabCPU && _sortCol == 2) r = (a.threads < b.threads ? NSOrderedAscending : a.threads > b.threads ? NSOrderedDescending : NSOrderedSame);
        else { double x = [self dm_metric:a], y = [self dm_metric:b]; r = (x < y ? NSOrderedAscending : x > y ? NSOrderedDescending : NSOrderedSame); }
        if (r != NSOrderedSame) return _sortDesc ? (NSComparisonResult)(-r) : r;
        // (equal figures -- most processes show 0.0 %CPU -- keep one order, by name, then pid: without it they changed places at every refresh, the
        //  process list comes in no fixed order, and a row tapped a moment after a screenshot was another process, M1 29 Oct)
        r = [a.name localizedCaseInsensitiveCompare:b.name];
        return r != NSOrderedSame ? r : (a.pid < b.pid ? NSOrderedAscending : a.pid > b.pid ? NSOrderedDescending : NSOrderedSame);
    }];
    NSInteger had = (NSInteger)_rows.count, now = (NSInteger)rows.count;
    _rows = rows;
    if (!inPlace || [_list numberOfRowsInSection:0] != had) [_list reloadData];
    else {
        if (now != had) [UIView performWithoutAnimation:^{
            [_list performBatchUpdates:^{
                NSMutableArray<NSIndexPath *> *ends = [NSMutableArray array];
                for (NSInteger r = MIN(had, now); r < MAX(had, now); r++) [ends addObject:[NSIndexPath indexPathForRow:r inSection:0]];
                if (now > had) [_list insertRowsAtIndexPaths:ends withRowAnimation:UITableViewRowAnimationNone];
                else [_list deleteRowsAtIndexPaths:ends withRowAnimation:UITableViewRowAnimationNone];
            } completion:nil];
        }];
        CGFloat w = _list.bounds.size.width;
        for (NSIndexPath *ip in _list.indexPathsForVisibleRows) {
            UITableViewCell *cell = ip.row < now ? [_list cellForRowAtIndexPath:ip] : nil;
            if (cell) [self dm_fillCell:cell row:_rows[ip.row] width:w];
        }
    }
    // (the selected process stays selected across the refreshes, as on a Mac -- -reloadData drops the table's selection, so its row lost the
    //  highlight within 2 s while Quit and Inspect still acted on it --: found again by its pid, every refresh making new rows; a process that has
    //  gone or is no longer listed (search, filter) leaves nothing selected. In place, the selection the table keeps is a row number: moved with
    //  its process, or taken off.)
    NSIndexPath *was = _list.indexPathForSelectedRow;
    if (_selected) {
        NSUInteger at = NSNotFound;
        for (NSUInteger i = 0; i < _rows.count; i++) if (_rows[i].pid == _selected.pid) { at = i; break; }
        if (at == NSNotFound) { _selected = nil; _inspect.enabled = NO; _quit.enabled = NO; [self dm_refreshNote]; if (was) [_list deselectRowAtIndexPath:was animated:NO]; }
        else if (was.row != (NSInteger)at || !was) { _selected = _rows[at]; [_list selectRowAtIndexPath:[NSIndexPath indexPathForRow:(NSInteger)at inSection:0] animated:NO scrollPosition:UITableViewScrollPositionNone]; }
        else _selected = _rows[at];
    } else if (was) [_list deselectRowAtIndexPath:was animated:NO];
}
- (void)dm_updateSummary {
    char buf[32];
    if (_tab == DMAMTabMemory && _haveMem) {
        MSBDFormatBytes(_mem.used, buf, sizeof buf); NSString *used = @(buf);
        MSBDFormatBytes(_mem.available, buf, sizeof buf); NSString *avail = @(buf);
        MSBDFormatBytes(_mem.total, buf, sizeof buf);
        _sumLeft.text = [NSString stringWithFormat:@"%lu processes", (unsigned long)_rows.count];
        _sumRight.text = [NSString stringWithFormat:@"Used %@   Available %@   Total %@", used, avail, @(buf)];
        double frac = _mem.total ? (double)_mem.used / _mem.total : 0.0;
        _memFill.backgroundColor = frac > 0.9 ? [UIColor systemRedColor] : frac > 0.75 ? [UIColor systemOrangeColor] : [UIColor systemGreenColor];
        _memTrack.hidden = NO;
    } else {
        _memTrack.hidden = YES;
        if (_tab == DMAMTabCPU && _haveTicks) {
            _sumLeft.text = [NSString stringWithFormat:@"CPU Load %.0f%%", _cpuLoad * 100.0];
            _sumRight.text = [NSString stringWithFormat:@"User %.0f%%   System %.0f%%   Idle %.0f%%   %u cores   %lu processes",
                              _cpuUser * 100.0, _cpuSystem * 100.0, (1.0 - _cpuLoad) * 100.0, _cores, (unsigned long)_rows.count];
        } else {
            _sumLeft.text = [NSString stringWithFormat:@"%lu processes", (unsigned long)_rows.count];
            _sumRight.text = @"";   // (the plain note, if any, is set below; nothing here suggests a figure is coming)
        }
    }
    [self dm_refreshNote];
    [self setNeedsLayout];
}

// ---- table ----
- (NSInteger)tableView:(UITableView *)tv numberOfRowsInSection:(NSInteger)s { return _rows.count; }
- (NSString *)dm_metricText:(DMProcInfo *)p {
    char buf[32];
    switch (_tab) {
        case DMAMTabCPU:    return (p.haveStats && p.cpuPercent >= 0) ? [NSString stringWithFormat:@"%.1f", p.cpuPercent] : @"–";
        case DMAMTabMemory: if (!p.haveStats) return @"–"; MSBDFormatBytes(p.footprint, buf, sizeof buf); return @(buf);
        case DMAMTabDisk:   if (!p.haveStats) return @"–"; MSBDFormatBytes(p.disk, buf, sizeof buf); return @(buf);
        default:            return @"–";
    }
}
- (UITableViewCell *)tableView:(UITableView *)tv cellForRowAtIndexPath:(NSIndexPath *)ip {
    UITableViewCell *cell = [tv dequeueReusableCellWithIdentifier:@"p"];
    if (!cell) {
        cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:@"p"];
        cell.backgroundColor = [UIColor clearColor];
        for (int i = 0; i < 5; i++) {
            UILabel *l = [UILabel new]; l.tag = 600 + i;
            l.font = i == 0 ? [UIFont systemFontOfSize:13.0] : [UIFont monospacedDigitSystemFontOfSize:12.0 weight:UIFontWeightRegular];
            l.textColor = i == 0 ? [UIColor labelColor] : [UIColor secondaryLabelColor];
            [cell.contentView addSubview:l];
        }
    }
    [self dm_fillCell:cell row:_rows[ip.row] width:tv.bounds.size.width];
    return cell;
}
// A row's labels set from its process. Only what differs is set: a label given its text again is drawn again, and the 2 s refresh redrew every
// visible label at once -- a 40-45 ms frame on SpringBoard's main thread, a hitch in any scroll or animation on the screen (M1, 1.7.2 item 6).
- (void)dm_fillCell:(UITableViewCell *)cell row:(DMProcInfo *)p width:(CGFloat)w {
    NSArray<NSNumber *> *edges = [self dm_columnEdges:w];
    // (none of these is ever nil -- an array literal with a nil throws, inside SpringBoard: a name read from bytes that were not UTF-8 was, until
    //  DMProcInfo's name became never nil; the figures are our own ASCII)
    NSArray<NSString *> *vals = _tab == DMAMTabCPU
        ? @[p.name, [self dm_metricText:p], p.haveStats ? [self dm_cpuTime:p.cpuNs] : @"–", p.threads >= 0 ? @(p.threads).stringValue : @"–", @(p.pid).stringValue]
        : @[p.name, [self dm_metricText:p], p.threads >= 0 ? @(p.threads).stringValue : @"–", @(p.pid).stringValue];
    for (int i = 0; i < 5; i++) {
        UILabel *l = [cell.contentView viewWithTag:600 + i];
        if (i >= (int)vals.count) { if (!l.hidden) l.hidden = YES; continue; }
        if (l.hidden) l.hidden = NO;
        if (![l.text isEqualToString:vals[i]]) l.text = vals[i];
        CGFloat x = [edges[i] doubleValue], nx = (i + 1 < (int)edges.count) ? [edges[i + 1] doubleValue] : w - kMSBDAMRightInset;
        CGRect f = CGRectMake(x, 0, nx - x - kMSBDAMColumnGap, 28);
        if (!CGRectEqualToRect(l.frame, f)) l.frame = f;
        NSTextAlignment a = i == 0 ? NSTextAlignmentLeft : NSTextAlignmentRight;
        if (l.textAlignment != a) l.textAlignment = a;
    }
}
- (NSString *)dm_cpuTime:(uint64_t)ns {   // seconds.hundredths, like Activity Monitor's shorter form
    double s = ns / 1e9; unsigned m = (unsigned)(s / 60); double rem = s - m * 60;
    return m ? [NSString stringWithFormat:@"%u:%05.2f", m, rem] : [NSString stringWithFormat:@"%.2f", rem];
}
- (void)tableView:(UITableView *)tv didSelectRowAtIndexPath:(NSIndexPath *)ip {
    _selected = _rows[ip.row];
    _inspect.enabled = _selected != nil;
    _quit.enabled = [self dm_appForSelected] != nil;   // (Quit is for apps only, through our existing Force Quit; off for system processes)
    [self dm_refreshNote];
}
// The running app for the selected process, or nil -- the same "app" the Force Quit Apps panel uses (a Home Screen icon, not AppHider-hidden).
- (id)dm_appForSelected {
    if (!_selected) return nil;
    for (id app in DMUserRunningApps()) if (DMPidForApp(app) == _selected.pid) return app;
    return nil;
}
- (NSString *)dm_noteText {
    if (_selected && _quit.enabled == NO && [self dm_appForSelected] == nil) {   // a row is selected and it is not an app: say why Quit is off
        const char *r = MSBDActMonQuitReason(0); if (r[0]) return @(r);
    }
    BOOL anyMissing = NO; for (DMProcInfo *p in _rows) if (!p.haveStats) { anyMissing = YES; break; }
    const char *note = MSBDActMonFooterNote((int)_tab, anyMissing ? 1 : 0);
    return note[0] ? @(note) : @"";
}
- (void)dm_refreshNote { _note.text = [self dm_noteText]; }

// ---- toolbar actions ----
- (void)dm_tabChanged { _tab = _tabs.selectedSegmentIndex; _sortCol = (_tab == DMAMTabCPU) ? 1 : 1; _sortDesc = YES; [self dm_applyColumns]; [self dm_rebuildRows]; [self dm_updateSummary]; }
- (void)dm_headerTapped:(UITapGestureRecognizer *)g {
    NSInteger col = g.view.tag - 500; if (col < 0 || col >= _colCount) return;
    if (col == _sortCol) _sortDesc = !_sortDesc; else { _sortCol = col; _sortDesc = (col != 0); }
    [self dm_markSortColumn]; [self dm_rebuildRows];
}
- (void)dm_filterTapped { _filter = (_filter + 1) % 3; [self dm_updateFilterTitle]; [self dm_rebuildRows]; [self dm_updateSummary]; }
- (void)dm_updateFilterTitle {
    NSString *t = _filter == DMAMFilterMine ? @"My Processes" : _filter == DMAMFilterSystem ? @"System Processes" : @"All Processes";
    [_filterButton setTitle:t forState:UIControlStateNormal]; [self setNeedsLayout];
}
- (void)dm_inspectTapped {
    DMProcInfo *p = _selected; if (!p) return;
    char f[32], r[32], d[32]; MSBDFormatBytes(p.footprint, f, sizeof f); MSBDFormatBytes(p.resident, r, sizeof r); MSBDFormatBytes(p.disk, d, sizeof d);
    NSString *msg = p.haveStats
        ? [NSString stringWithFormat:@"PID %d  (parent %d)\n%% CPU %@\nCPU Time %@\nMemory %@\nResident %@\nDisk %@\nThreads %d",
           p.pid, p.ppid, p.cpuPercent >= 0 ? [NSString stringWithFormat:@"%.1f", p.cpuPercent] : @"–", [self dm_cpuTime:p.cpuNs], @(f), @(r), @(d), p.threads]
        : [NSString stringWithFormat:@"PID %d  (parent %d)\n%@", p.pid, p.ppid, @(MSBDActMonInspectNote(0))];
    [self sheetTitle:p.name message:msg field:nil action:@"Done" destructive:NO then:^(NSString *t) {}];
}
- (void)dm_quitTapped {
    id app = [self dm_appForSelected];
    if (!app) return;   // (only apps can be quit; the button is off otherwise)
    NSString *name = DMCall(app, @"displayName") ?: _selected.name;
    [self sheetTitle:[NSString stringWithFormat:@"Quit %@?", name]
             message:@"The app is asked to quit, as if you swiped it up in the App Switcher."
               field:nil action:@"Quit" destructive:YES then:^(NSString *t) {
        id a = [self dm_appForSelected];   // (re-checked: it may have gone while the sheet was up)
        if (a) { DMForceQuit((SBApplication *)a); _quit.enabled = NO; }
    }];
}

// ---- search ----
- (void)searchBar:(UISearchBar *)sb textDidChange:(NSString *)t { _query = t ?: @""; [self dm_rebuildRows]; [self dm_updateSummary]; }
- (void)searchBarSearchButtonClicked:(UISearchBar *)sb { [sb resignFirstResponder]; }
- (void)searchBarTextDidBeginEditing:(UISearchBar *)sb { [gNativeLayer makeKeyWindow]; }

// ---- visible-only sampling ----
- (BOOL)dm_onScreen {
    UIWindow *win = self.window;
    if (!win || win.hidden || self.hidden || self.alpha < 0.01) return NO;
    for (UIView *v = self; v; v = v.superview) if (v.hidden || v.alpha < 0.01) return NO;
    return YES;
}
- (void)dm_start {
    if (_timer) return;
    _secondSoon = YES;   // (the first %CPU needs two readings: the second one comes 0.3 s after the first is in, dm_took:)
    [self dm_sample];
    __weak typeof(self) ws = self;
    _timer = [NSTimer timerWithTimeInterval:2.0 repeats:YES block:^(NSTimer *t) { if ([ws dm_onScreen]) [ws dm_sample]; }];
    _timer.tolerance = 0.4;
    [[NSRunLoop mainRunLoop] addTimer:_timer forMode:NSRunLoopCommonModes];
}
- (void)dm_stop { [_timer invalidate]; _timer = nil; }
- (void)didMoveToWindow { [super didMoveToWindow]; if (self.window) [self dm_start]; else [self dm_stop]; }
- (void)dealloc { [_timer invalidate]; }
@end

// The one window (brought forward if it is already open).
static void DMActivityMonitorOpen(void) {
    for (DMNativeWindow *w in gNativeWindows) if ([w isKindOfClass:[DMActivityMonitorWindow class]]) { [w show]; return; }
    CGRect d = DMNativeDesktop();
    CGFloat w = MIN(900.0, d.size.width - 40.0), h = MIN(560.0, d.size.height - 40.0);
    DMActivityMonitorWindow *win = [[DMActivityMonitorWindow alloc] initWithFrame:CGRectMake(CGRectGetMidX(d) - w / 2.0, CGRectGetMidY(d) - h / 2.0, w, h)];
    [win show];
    DMLog(@"[actmonwin] opened");
}
