#!/usr/bin/env bash
#
# sync-from-source.sh — refresh this skill's A/B testing material from the
# private source notes, re-applying the link rewrites that keep the skill
# self-contained (no links into private repos).
#
# Usage:
#   scripts/sync-from-source.sh [PATH_TO_SOURCE_AB_TESTING_DIR]
#
# Source resolution order: $1  ->  $AB_SRC  ->  ~/staff-ds-interview-prep/ab-testing
#
# What it does:
#   1. copies playbook.md, deep-dives/*.md, and the two case examples in
#   2. rewrites cross-references so every link resolves *inside this repo*
#      and no private repo/folder is named
#   3. verifies: no private references survive, and every local link resolves
#
# If the source ever introduces a NEW kind of private link, step 3 fails loudly
# — add a rule to the rewrite block below and re-run.
set -euo pipefail

SRC="${1:-${AB_SRC:-$HOME/staff-ds-interview-prep/ab-testing}}"
REF="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/reference"

[ -f "$SRC/playbook.md" ] || { echo "ERROR: no playbook at $SRC/playbook.md (pass the source ab-testing dir as arg 1)" >&2; exit 1; }
echo "source: $SRC"
echo "dest:   $REF"

# 1. copy ---------------------------------------------------------------------
mkdir -p "$REF/deep-dives" "$REF/case-walkthroughs"
cp "$SRC/playbook.md"        "$REF/ab-testing-playbook.md"
cp "$SRC/deep-dives/"*.md    "$REF/deep-dives/"
cp "$SRC/examples/experiment-design.md" \
   "$SRC/examples/experimentation-platform-design.md" "$REF/case-walkthroughs/"

# 2. rewrite links ------------------------------------------------------------
# Applied to every reference markdown file; each rule only matches what it matches.
rewrite() {
  perl -i -pe '
    # relink the two A/B case examples to their local home
    s{\(\.\./\.\./ab-testing/examples/}{(case-walkthroughs/}g;
    # deep-dive back-links point at the renamed playbook
    s{\.\./playbook\.md}{../ab-testing-playbook.md}g;
    s{`playbook\.md`}{`ab-testing-playbook.md`}g;
    # de-link private cross-references, keeping the link label as plain text
    s{\[([^\]]+)\]\((?:\.\./)+repos/ml-interview-prep/[^)]*\)}{$1}g;
    s{\[([^\]]+)\]\((?:\.\./)+causal-inference/playbook\.md\)}{$1}g;
    s{\[([^\]]+)\]\((?:\.\./)+metric-diagnosis/examples/metrics-diagnosis\.md\)}{$1}g;
    s{\[([^\]]+)\]\(https://github\.com/ruoyanhuang216/stats-interview-review/[^)]*\)}{$1}g;
    s{\[([^\]]+)\]\(https://github\.com/ruoyanhuang216/ml-interview-prep/[^)]*\)}{$1}g;
    # tidy residual plain-text private path mentions into generic prose
    s{`ml-interview-prep/algorithms/notes/causal_inference\.md`}{companion causal-inference notes}g;
    s{`ml-interview-prep/algorithms/notes/time_series_forecasting\.md`}{companion time-series notes}g;
    s{`(?:\.\./)+causal-inference/playbook\.md`}{companion causal-inference notes}g;
    s{`stats-interview-review/STAT_415_Review\.md`}{a companion hypothesis-testing reference}g;
    s{`stats-interview-review/Experiment_Design\.md`}{a companion DOE reference}g;
    s{`examples/metrics-diagnosis\.md`}{companion metric-diagnosis notes}g;
    s{`STAT_415_Review\.md`}{that hypothesis-testing reference}g;
    s{`causal_inference\.md`}{companion causal-inference notes}g;
    s{`time_series_forecasting\.md`}{companion time-series notes}g;
    s{causal_inference\.md}{companion causal-inference notes}g;
    s{time_series_forecasting\.md}{companion time-series notes}g;
    s{the companion stats repo: a companion hypothesis-testing reference}{a companion hypothesis-testing reference}g;
  ' "$1"
}
while IFS= read -r f; do rewrite "$f"; done < <(find "$REF" -name '*.md')

# 3a. verify no private reference survived -------------------------------------
if grep -rnE 'staff-ds-interview-prep|ml-interview-prep|stats-interview-review|repos/ml-interview|causal-inference/playbook|metric-diagnosis/|metrics-diagnosis\.md|STAT_415|Experiment_Design\.md|causal_inference\.md|time_series_forecasting\.md|\.\./\.\./ab-testing' "$REF"; then
  echo "ERROR: private references survived — add a rule to the rewrite block in $0" >&2
  exit 1
fi

# 3b. verify every local markdown link resolves --------------------------------
miss=0
while IFS= read -r line; do
  file="${line%%::*}"; link="${line##*::}"; target="${link%%#*}"
  [ -z "$target" ] && continue              # pure-anchor
  case "$target" in *"<"*) continue;; esac  # illustrative placeholder, e.g. <topic>.md
  [ -e "$(dirname "$file")/$target" ] || { echo "BROKEN LINK: $file -> $link" >&2; miss=$((miss+1)); }
done < <(grep -rnoE '\]\(([^)]+)\)' "$REF" --include='*.md' \
          | sed -E 's/:\]\(/::/; s/\)$//' | grep -vE '::https?:|::#|::mailto:' || true)
[ "$miss" -eq 0 ] || { echo "ERROR: $miss broken local link(s)" >&2; exit 1; }

echo "✓ synced & verified — reference/ is self-contained ($(find "$REF" -name '*.md' | wc -l | tr -d ' ') markdown files)"
