#!/bin/bash
# verify-release-features.sh <deb | unpacked package folder>: every feature marker in the source (DM_FEATURE_MARK("name") in *.x / *.m / *.h, see
# statusbar/StatusBar.x) must be in the RELEASE build's binaries as "msbd-feature:<name>". A feature compiled only into debug builds (in 1.1.0/1.1.1 the
# Stage Manager engine's activate-on-touch hook lived in the debug build's own sendEvent: hook) then fails here instead of shipping silently.
# Prints each marker and ends with "FEATURES: GO" (exit 0) or "FEATURES: NO-GO" (exit 1). tools/verify-release.sh runs it on the package it checks.
#   MSBD_TREE=<folder>  the source tree the markers are read from (default: the tree this script is in)
set -u
IN="${1:?usage: verify-release-features.sh <deb or unpacked package folder>}"
TREE="${MSBD_TREE:-$(cd "$(dirname "$0")/.." && pwd)}"
W=""
if [ -f "$IN" ]; then
    case "$IN" in /*) ;; *) IN="$PWD/$IN";; esac
    W=$(mktemp -d "${TMPDIR:-/tmp}/msbd-features.XXXXXX"); trap 'rm -rf "$W"' EXIT
    (cd "$W" && ar x "$IN" && mkdir d && tar -xf data.tar.* -C d) || { echo "cannot unpack $IN"; echo "FEATURES: NO-GO"; exit 1; }
    ROOT="$W/d"
elif [ -d "$IN" ]; then ROOT="$IN"
else echo "not a file or folder: $IN"; echo "FEATURES: NO-GO"; exit 1; fi
# the markers named in the source (one per line, sorted, unique); the macro's own definition line is not one
MARKS=$(grep -rhoE --include='*.x' --include='*.m' --include='*.h' --include='*.xm' --exclude-dir=.theos --exclude-dir=packages \
        'DM_FEATURE_MARK\("[a-z0-9-]+"\)' "$TREE" | sed -E 's/.*\("([^"]+)"\).*/\1/' | sort -u)
[ -n "$MARKS" ] || { echo "  NO-GO: no DM_FEATURE_MARK in the source tree $TREE"; echo "FEATURES: NO-GO"; exit 1; }
# every string "msbd-feature:..." in the package's Mach-O files
FOUND=$(find "$ROOT" -type f | while IFS= read -r f; do file "$f" | grep -q Mach-O && strings -a "$f" | grep -oE 'msbd-feature:[a-z0-9-]+'; done | sed 's/^msbd-feature://' | sort -u)
bad=0; n=0
for m in $MARKS; do
    n=$((n+1))
    if printf '%s\n' "$FOUND" | grep -qx -- "$m"; then echo "  ok: $m"; else echo "  NO-GO: '$m' is in the source but NOT in the built binaries (compiled out -- under #if DEBUG, or dead code?)"; bad=$((bad+1)); fi
done
for f in $FOUND; do printf '%s\n' "$MARKS" | grep -qx -- "$f" || echo "  note: '$f' is in the binaries but no longer in the source (a stale build?)"; done
if [ $bad = 0 ]; then echo "FEATURES: GO ($n markers)"; exit 0; else echo "FEATURES: NO-GO ($bad of $n missing)"; exit 1; fi
