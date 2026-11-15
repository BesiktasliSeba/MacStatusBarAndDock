# actmonsort-cut.py <ActivityMonitor.h> <ProcList.h> <out folder>: for tools/test-actmoncolumns.sh (the rows' sort, 1.8.7.5 audit L77). Cuts out of
# the real files the process record (ProcList.h DMProcInfo), the tabs (DMAMTab), the tab's metric (-dm_metric:) and the rows' sort (the comparator
# of -dm_rowsNow), each into its own file. Exit 1 if any is not found.
import os, sys
am, pl, out = open(sys.argv[1]).read().split('\n'), open(sys.argv[2]).read().split('\n'), sys.argv[3]
def cut(lines, first, last, strip=False):
    a = next(i for i, l in enumerate(lines) if (l.strip() if strip else l).startswith(first))
    return lines[a:next(i for i in range(a, len(lines)) if (lines[i].strip() if strip else lines[i]) == last) + 1]
try:
    parts = {
        'amsort-procinfo.h': cut(pl, '@interface DMProcInfo : NSObject', '@end') + cut(pl, '@implementation DMProcInfo', '@end'),
        'amsort-tab.h': [next(l for l in am if l.startswith('typedef NS_ENUM(NSInteger, DMAMTab)'))],
        'amsort-metric.h': cut(am, '- (double)dm_metric:(DMProcInfo *)p {', '}'),
        'amsort-sort.h': cut(am, '[rows sortUsingComparator:^NSComparisonResult(DMProcInfo *a, DMProcInfo *b) {', '}];', strip=True),
    }
except StopIteration:
    sys.exit(1)
for name, lines in parts.items():
    open(os.path.join(out, name), 'w').write('\n'.join(lines) + '\n')
