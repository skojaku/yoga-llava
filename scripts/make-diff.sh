#!/usr/bin/env bash
#
# Build a latexdiff PDF between two versions of the paper.
#
#   ./scripts/make-diff.sh                  # first commit -> working tree
#   ./scripts/make-diff.sh HEAD~5           # HEAD~5       -> working tree
#   ./scripts/make-diff.sh v1 v2            # v1           -> v2
#
# Output: diff.pdf in the repository root.
#
# The old and new trees are materialized separately, so main.tex may be a
# single file in one version and a set of \input{sections/...} files in the
# other. latexdiff --flatten resolves the includes on both sides.

set -euo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO"

MAIN="main.tex"
OUT="diff.pdf"

# Default base: the repository's root commit.
BASE="${1:-$(git rev-list --max-parents=0 HEAD | tail -1)}"
NEW="${2:-}"

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
mkdir -p "$WORK/old" "$WORK/new"

echo "base: $BASE ($(git log -1 --format=%s "$BASE"))"
git archive "$BASE" | tar -x -C "$WORK/old"

if [[ -n "$NEW" ]]; then
    echo "new:  $NEW ($(git log -1 --format=%s "$NEW"))"
    git archive "$NEW" | tar -x -C "$WORK/new"
else
    echo "new:  working tree"
    # Read tracked paths from disk so uncommitted edits are included.
    git ls-files -z | tar -cf - --null -T - | tar -xf - -C "$WORK/new"
fi

echo "running latexdiff..."
latexdiff --flatten --encoding=utf8 \
    "$WORK/old/$MAIN" "$WORK/new/$MAIN" > "$WORK/diff.tex"

# Compile in the new tree so figures and references.bib resolve.
cp "$WORK/diff.tex" "$WORK/new/diff.tex"
cd "$WORK/new"

echo "compiling..."
for pass in 1 2 3; do
    pdflatex -interaction=nonstopmode -halt-on-error diff.tex > /dev/null 2>&1 || {
        echo "pdflatex failed on pass $pass; see $WORK/new/diff.log" >&2
        tail -30 diff.log >&2
        exit 1
    }
    [[ $pass == 1 && -f references.bib ]] && bibtex diff > /dev/null 2>&1 || true
done

cp diff.pdf "$REPO/$OUT"
echo "wrote $REPO/$OUT"
