#!/bin/bash
# prewarm-part-id.sh <prewarmblock folder> <d|r>: the prewarm block's build ID (common/PrewarmPartID.h) -- the first 16 hex digits of a SHA-256 over
# the part's sources (PrewarmBlock.x and every file it includes with quotes, followed through their own quoted includes), its Makefile, and the
# build kind (d: debug, r: release). Run by prewarmblock/Makefile at every build; the Mac test (tools/test-prewarmpartid.sh) checks it.
# The same sources give the same ID in every worktree and build (no paths, no times go in), so an install that does not change the part leaves
# dasd running; any change to them gives a new ID, and the install restarts dasd so it loads the new part.
set -u
DIR="${1:?usage: prewarm-part-id.sh <prewarmblock folder> <d|r>}"; KIND="${2:?usage: prewarm-part-id.sh <prewarmblock folder> <d|r>}"
case "$KIND" in d|r) ;; *) echo "build kind must be d or r" >&2; exit 2;; esac
cd "$DIR" || exit 2
# the files, by path relative to the part's folder, each once, in the order found (breadth first from PrewarmBlock.x)
list="PrewarmBlock.x"; todo="PrewarmBlock.x"
while [ -n "$todo" ]; do
    next=""
    for f in $todo; do
        [ -f "$f" ] || { echo "missing source: $f" >&2; exit 2; }
        d=$(dirname "$f")
        for inc in $(sed -n -E 's/^[[:space:]]*#[[:space:]]*(include|import)[[:space:]]*"([^"]*)".*/\2/p' "$f"); do
            p=$(python3 -I -c 'import os,sys; print(os.path.normpath(os.path.join(sys.argv[1], sys.argv[2])))' "$d" "$inc")
            case " $list " in *" $p "*) ;; *) list="$list $p"; next="$next $p";; esac
        done
    done
    todo="$next"
done
for f in $list Makefile; do [ -f "$f" ] || { echo "missing source: $f" >&2; exit 2; }; done
{ for f in $list Makefile; do printf '%s\n' "== $f"; cat "$f"; done; printf '== kind %s\n' "$KIND"; } | shasum -a 256 | cut -c1-16
