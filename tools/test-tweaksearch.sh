#!/bin/bash
# Mac test of the check behind tweak settings in the Settings search and in Spotlight (macsettings/TweakSearchCheck.h, used by
# macsettings/TweakSearch.x) against Apple's own classes: the sidebar list and the results controller of each build in tools/setsearch-fixtures
# (15.6.1 19G82, 16.7.7 20H330, 17.5.1 21F90), and the Settings app's controller where its binary was read (tools/tweaksearch-fixtures: 19G82,
# 20H330; on 17.5.1 the app is not checked here and the device's own check decides). Per build: the check passes; each method it needs taken away
# or given another type, and each class missing or without its UIKit base: the check refuses and names it. test-tweaksearch.m.
set -e
cd "$(dirname "$0")"
W=$(mktemp -d); trap 'rm -rf "$W"' EXIT
clang -fobjc-arc -Wall -Wno-unused-function -U__OBJC_BOOL_IS_BOOL -D__OBJC_BOOL_IS_BOOL=1 -framework Foundation -o "$W/t" test-tweaksearch.m
NEEDS="PSUIPrefsListController:updateSearchResultsForSearchController: PSUIPrefsListController:searchResultsCollectionViewController:didSelectURL:
PSUIPrefsListController:searchResultsCollectionViewController:iconForCategory: PSUIPrefsListController:searchResultsCollectionViewController:shouldShowCategory:
PSUIPrefsListController:searchResultsCollectionViewController:sortCategory1:sortCategory2: PSUIPrefsListController:spotlightSearchController
PSUIPrefsListController:searchResultsController SUIKSearchResultsCollectionViewController:searchQueryFoundItems:
SUIKSearchResultsCollectionViewController:searchQueryCompleted SUIKSearchResultsCollectionViewController:delegate"
fail=0; n=0; apps=0
for F in setsearch-fixtures/*.txt; do
    B=$(basename "$F" .txt); A=tweaksearch-fixtures/app-$B.txt; [ -f "$A" ] || A=-
    [ "$A" = - ] || apps=$((apps+1))
    "$W/t" "$F" "$A" pass > "$W/o" || { cat "$W/o"; fail=$((fail+1)); }; n=$((n+1))
    for need in $NEEDS; do
        c=${need%%:*}; s=${need#*:}
        "$W/t" "$F" "$A" drop "$c" "$s" > "$W/o" || { cat "$W/o"; fail=$((fail+1)); }; n=$((n+1))
        "$W/t" "$F" "$A" retype "$c" "$s" "v@:q" > "$W/o" || { cat "$W/o"; fail=$((fail+1)); }; n=$((n+1))
    done
    for c in PSUIPrefsListController SUIKSearchResultsCollectionViewController; do
        "$W/t" "$F" "$A" nobase "$c" > "$W/o" || { cat "$W/o"; fail=$((fail+1)); }; n=$((n+1))
        "$W/t" "$F" "$A" noclass "$c" > "$W/o" || { cat "$W/o"; fail=$((fail+1)); }; n=$((n+1))
    done
    if [ "$A" != - ]; then
        "$W/t" "$F" "$A" drop PreferencesAppController processURL:animated:fromSearch:withCompletion: > "$W/o" || { cat "$W/o"; fail=$((fail+1)); }; n=$((n+1))
        "$W/t" "$F" "$A" retype PreferencesAppController processURL:animated:fromSearch:withCompletion: "v@:@B@" > "$W/o" || { cat "$W/o"; fail=$((fail+1)); }; n=$((n+1))
        "$W/t" "$F" "$A" nobase PreferencesAppController > "$W/o" || { cat "$W/o"; fail=$((fail+1)); }; n=$((n+1))
        "$W/t" "$F" "$A" noclass PreferencesAppController > "$W/o" || { cat "$W/o"; fail=$((fail+1)); }; n=$((n+1))
    fi
done
if [ $fail = 0 ]; then echo "test-tweaksearch: $n/$n passed (app checked on $apps builds)"; else echo "test-tweaksearch: $fail of $n FAILED"; exit 1; fi
