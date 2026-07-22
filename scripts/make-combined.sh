#!/usr/bin/env bash
#
# Expand main.tex into a single self-contained main-combined.tex.
#
#   ./scripts/make-combined.sh          # write main-combined.tex and build it
#   ./scripts/make-combined.sh --check  # fail if main-combined.tex is stale
#
# Submission systems that want one .tex file take main-combined.tex plus the
# figures and references.bib (or main-combined.bbl). The file is a snapshot,
# not a live include, so rerun this after editing anything under sections/.

set -euo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO"

MAIN="main.tex"
OUT="main-combined.tex"
CHECK=0
[[ "${1:-}" == "--check" ]] && CHECK=1

expand() {
    python3 - "$MAIN" <<'PY'
import re, sys, pathlib

def expand(path, depth=0):
    if depth > 8:
        raise SystemExit(f"\\input nesting too deep at {path}")
    text = pathlib.Path(path).read_text()
    def sub(m):
        child = m.group(1)
        p = pathlib.Path(child if child.endswith('.tex') else child + '.tex')
        if not p.exists():
            raise SystemExit(f"missing input: {p}")
        return expand(p, depth + 1).rstrip('\n')
    return re.sub(r'\\input\{([^}]+)\}', sub, text)

sys.stdout.write(expand(sys.argv[1]))
PY
}

NEW="$(expand)"

if [[ $CHECK == 1 ]]; then
    if [[ -f "$OUT" && "$NEW" == "$(cat "$OUT")" ]]; then
        echo "$OUT is up to date"
        exit 0
    fi
    echo "$OUT is stale; run ./scripts/make-combined.sh" >&2
    exit 1
fi

printf '%s' "$NEW" > "$OUT"
echo "wrote $OUT ($(wc -l < "$OUT" | tr -d ' ') lines)"

echo "building..."
BASE="${OUT%.tex}"
pdflatex -interaction=nonstopmode -halt-on-error "$OUT" > /dev/null 2>&1 || {
    echo "pdflatex failed; see $BASE.log" >&2; tail -30 "$BASE.log" >&2; exit 1
}
bibtex "$BASE" > /dev/null 2>&1 || true
pdflatex -interaction=nonstopmode -halt-on-error "$OUT" > /dev/null 2>&1
pdflatex -interaction=nonstopmode -halt-on-error "$OUT" > /dev/null 2>&1

undef=$(grep -c "undefined" "$BASE.log" || true)
echo "built $BASE.pdf ($(pdfinfo "$BASE.pdf" | awk '/^Pages/{print $2}') pages, $undef undefined references)"

# The combined file must render exactly like the split build.
if [[ -f main.pdf ]]; then
    pdftotext main.pdf /tmp/_split.txt 2>/dev/null
    pdftotext "$BASE.pdf" /tmp/_comb.txt 2>/dev/null
    if diff -q /tmp/_split.txt /tmp/_comb.txt > /dev/null; then
        echo "text output identical to main.pdf"
    else
        echo "WARNING: output differs from main.pdf (rebuild main.tex and compare)" >&2
    fi
    rm -f /tmp/_split.txt /tmp/_comb.txt
fi
