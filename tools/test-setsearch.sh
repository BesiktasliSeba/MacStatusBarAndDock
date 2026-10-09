#!/bin/bash
# Mac test of the Settings sidebar search field's check (macsettings/SidebarSearchCheck.h, used by macsettings/SidebarSearch.x) against Apple's own
# classes of the builds in tools/setsearch-fixtures (15.6.1 19G82 and 16.7.7 20H330, both tested on the iPads; 17.5.1 21F90 iPad7,1, not tested on a
# device: made by tools/make-setsearch-fixture.py from each build's dyld shared cache). Per build: the check passes (the field is offered); each of the 25 methods it needs taken away, or given another type, and each of
# the three classes missing or without its UIKit base: the check refuses and names it. test-setsearch.m.
set -e
cd "$(dirname "$0")"
W=$(mktemp -d); trap 'rm -rf "$W"' EXIT
clang -fobjc-arc -Wall -Wno-unused-function -U__OBJC_BOOL_IS_BOOL -D__OBJC_BOOL_IS_BOOL=1 -framework Foundation -o "$W/t" test-setsearch.m
NEEDS="PSUIPrefsListController:spotlightSearchController PSUIPrefsListController:searchResultsController PSUIPrefsListController:setSearchResultsController:
PSUIPrefsListController:updateSearchResultsForSearchController: PSUIPrefsListController:searchResultsCollectionViewController:didSelectURL:
PSUIPrefsListController:continueSearchInSettingsWithTerm: PSUIPrefsListController:_tabKeyPressed PSUIPrefsListController:_upArrowKeyPressed
PSUIPrefsListController:_downArrowKeyPressed PSUIPrefsListController:keyCommands PSUIPrefsListController:viewDidLayoutSubviews PSUIPrefsListController:table
PSKeyboardNavigationSearchController:searchBar PSKeyboardNavigationSearchController:searchResultsUpdater PSKeyboardNavigationSearchController:isActive
PSKeyboardNavigationSearchController:setActive: SUIKSearchResultsCollectionViewController:init SUIKSearchResultsCollectionViewController:delegate
SUIKSearchResultsCollectionViewController:setDelegate: SUIKSearchResultsCollectionViewController:searchQueryStarted
SUIKSearchResultsCollectionViewController:searchQueryFoundItems: SUIKSearchResultsCollectionViewController:selectNextSearchResult
SUIKSearchResultsCollectionViewController:selectPreviousSearchResult SUIKSearchResultsCollectionViewController:showSelectedSearchResult
SUIKSearchResultsCollectionViewController:collectionView:didSelectItemAtIndexPath:"
CLASSES="PSUIPrefsListController PSKeyboardNavigationSearchController SUIKSearchResultsCollectionViewController"
fail=0; n=0
for F in setsearch-fixtures/*.txt; do
    "$W/t" "$F" pass || fail=$((fail+1)); n=$((n+1))
    for need in $NEEDS; do
        c=${need%%:*}; s=${need#*:}
        "$W/t" "$F" drop "$c" "$s" > "$W/o" || { cat "$W/o"; fail=$((fail+1)); }; n=$((n+1))
        "$W/t" "$F" retype "$c" "$s" "v@:q" > "$W/o" || { cat "$W/o"; fail=$((fail+1)); }; n=$((n+1))
    done
    for c in $CLASSES; do
        "$W/t" "$F" nobase "$c" > "$W/o" || { cat "$W/o"; fail=$((fail+1)); }; n=$((n+1))
        "$W/t" "$F" noclass "$c" > "$W/o" || { cat "$W/o"; fail=$((fail+1)); }; n=$((n+1))
    done
done
if [ $fail = 0 ]; then echo "test-setsearch: $n/$n passed"; else echo "test-setsearch: $fail of $n FAILED"; exit 1; fi
