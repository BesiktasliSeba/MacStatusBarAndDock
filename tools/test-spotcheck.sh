#!/bin/bash
# Mac test of our Spotlight sections' check (spotlight/MacSpotlightCheck.h, used by spotlight/MacSpotlight.x) against Apple's own classes of the builds
# in tools/spotcheck-fixtures (15.6.1 19G82 and 16.7.7 20H330, the two iPads' builds: made by tools/make-spotcheck-fixture.py from each build's dyld
# shared cache in Apple's IPSW). Per build: the check passes and picks that build's tap path (15: SearchUICommand, 16: SearchUICommandHandler); each
# method it needs taken away, or given another type, and each class missing or without the base it asks for: the check refuses and names it.
# (-init of SFSearchResult / SFResultSection is NSObject's too, so it is not taken away here.) test-spotcheck.m.
set -e
cd "$(dirname "$0")"
W=$(mktemp -d); trap 'rm -rf "$W"' EXIT
clang -fobjc-arc -Wall -Wno-unused-function -U__OBJC_BOOL_IS_BOOL -D__OBJC_BOOL_IS_BOOL=1 -framework Foundation -o "$W/t" test-spotcheck.m
COMMON="SPUIResultsViewController:-updateWithResultSections:resetScrollPoint: SPUIResultsViewController:-queryString SPUIResultsViewController:-_pushSectionsUpdate
SearchUIRowModel:-identifyingResult SFSearchResult:-setIdentifier: SFSearchResult:-identifier SFSearchResult:-setTitle: SFSearchResult:-setDescriptions:
SFSearchResult:-setThumbnail: SFSearchResult:-applicationBundleIdentifier SFResultSection:-results SFResultSection:-setResults: SFResultSection:-setTitle:
SFResultSection:-setBundleIdentifier: SFResultSection:-setIdentifier: SFResultSection:-copyWithZone: SFText:+textWithString: SFRichText:+textWithString:
SFSymbolImage:-setSymbolName: SFAppIconImage:-setBundleIdentifier:"
NEEDS16="SearchUICommandHandler:+handlerForRowModel:environment: SearchUICommandHandler:-initWithCommand:rowModel:button:environment: SearchUICommandHandler:-rowModel
SearchUICommandHandler:-executeWithTriggerEvent: SearchUICommandHandler:-shouldDeselectAfterExecution SearchUICommandHandler:-supportsCopy
SearchUICommandHandler:-supportsShare SearchUICommandHandler:-prefersContextMenu SearchUICollectionViewController:-canHighlightRowAtIndexPath:
SearchUICollectionViewController:-collectionModel SearchUICollectionModel:-rowModelForIndexPath:"
NEEDS15="SearchUICommand:+tapCommandForRowModel:environment: SearchUICommand:-initWithRowModel:command:environment: SearchUICommand:-rowModel
SearchUITapCommand:-performCommandWithCompletion: SearchUITapCommand:-presentsViewController"
CLASSES="SPUIResultsViewController SearchUIRowModel SFSearchResult SFResultSection SFText SFRichText SFSymbolImage SFAppIconImage"
BASED="SPUIResultsViewController SFRichText SFSymbolImage SFAppIconImage"
fail=0; n=0
for F in spotcheck-fixtures/*.txt; do
    if grep -q "^SearchUICommandHandler " "$F"; then TAP=16; NEEDS="$COMMON $NEEDS16"; MORE="SearchUICommandHandler SearchUICollectionViewController SearchUICollectionModel"; MOREBASED=""
    else TAP=15; NEEDS="$COMMON $NEEDS15"; MORE="SearchUICommand SearchUITapCommand"; MOREBASED="SearchUITapCommand"; fi
    "$W/t" "$F" pass $TAP > "$W/o" || { cat "$W/o"; fail=$((fail+1)); }; n=$((n+1))
    for need in $NEEDS; do
        c=${need%%:*}; s=${need#*:}
        "$W/t" "$F" drop "$c" "$s" > "$W/o" || { cat "$W/o"; fail=$((fail+1)); }; n=$((n+1))
        "$W/t" "$F" retype "$c" "$s" "v@:q" > "$W/o" || { cat "$W/o"; fail=$((fail+1)); }; n=$((n+1))
    done
    for c in $BASED $MOREBASED; do "$W/t" "$F" nobase "$c" > "$W/o" || { cat "$W/o"; fail=$((fail+1)); }; n=$((n+1)); done
    for c in $CLASSES $MORE; do "$W/t" "$F" noclass "$c" > "$W/o" || { cat "$W/o"; fail=$((fail+1)); }; n=$((n+1)); done
done
if [ $fail = 0 ]; then echo "test-spotcheck: $n/$n passed"; else echo "test-spotcheck: $fail of $n FAILED"; exit 1; fi
