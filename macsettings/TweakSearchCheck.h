// TweakSearchCheck.h -- the check behind TweakSearch.x (tweak settings in the Settings search and in Spotlight): every private class, selector and
// type encoding it uses, compared with what this iPadOS really has. Included by macsettings/TweakSearch.x (at load, in Settings) and by
// tools/test-tweaksearch.m (on the Mac, against Apple's methods of 15.6.1 19G82, 16.7.7 20H330 and 17.5.1 21F90, tools/setsearch-fixtures).
// Two parts, checked apart:
//  - the results (MTSCheckResults): the sidebar list and Apple's results controller -- needed to add tweak settings to the Settings search;
//  - the opening (MTSCheckOpening): the Settings app's own URL handler (PreferencesAppController, in the app itself, not in the shared cache) --
//    needed to open a Spotlight result; without it nothing is donated to Spotlight.
#pragma once
#import "SidebarSearchCheck.h"

static void MTSCheckResults(Class list, Class results, NSMutableArray *why) {
    if (!MSSDescendsFrom(list, "UIViewController")) [why addObject:@"PSUIPrefsListController missing"];
    if (!MSSDescendsFrom(results, "UICollectionViewController")) [why addObject:@"SUIKSearchResultsCollectionViewController missing or not a UICollectionViewController"];
    if (why.count) return;
    NSString *obj = MSSExpect(@encode(id), NULL), *none = MSSExpect(@encode(void), NULL), *takesObj = MSSExpect(@encode(void), @encode(id), NULL),
             *takesTwo = MSSExpect(@encode(void), @encode(id), @encode(id), NULL), *icon = MSSExpect(@encode(id), @encode(id), @encode(id), NULL),
             *show = MSSExpect(@encode(BOOL), @encode(id), @encode(id), NULL), *sort = MSSExpect(@encode(long long), @encode(id), @encode(id), @encode(id), NULL);
    // the sidebar list: the results' delegate (Apple's own icon, order and filter per category) and the query it runs
    MSSHas(list, "updateSearchResultsForSearchController:", takesObj, why);
    MSSHas(list, "searchResultsCollectionViewController:didSelectURL:", takesTwo, why);
    MSSHas(list, "searchResultsCollectionViewController:iconForCategory:", icon, why);
    MSSHas(list, "searchResultsCollectionViewController:shouldShowCategory:", show, why);
    MSSHas(list, "searchResultsCollectionViewController:sortCategory1:sortCategory2:", sort, why);
    MSSHas(list, "spotlightSearchController", obj, why);
    MSSHas(list, "searchResultsController", obj, why);
    // Apple's results controller (both instances: Apple's own and the sidebar field's)
    MSSHas(results, "searchQueryFoundItems:", takesObj, why);
    MSSHas(results, "searchQueryCompleted", none, why);
    MSSHas(results, "delegate", obj, why);
}
static void MTSCheckOpening(Class app, NSMutableArray *why) {
    if (!MSSDescendsFrom(app, "UIApplication")) { [why addObject:@"PreferencesAppController missing or not a UIApplication"]; return; }
    MSSHas(app, "processURL:animated:fromSearch:withCompletion:", MSSExpect(@encode(void), @encode(id), @encode(BOOL), @encode(BOOL), @encode(id), NULL), why);
}
