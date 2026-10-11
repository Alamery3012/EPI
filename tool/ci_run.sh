#!/usr/bin/env bash
# Runs a CI command, keeps its output, and on failure reports the last lines
# as a GitHub annotation (readable through the API even when raw logs aren't).
# Usage: bash tool/ci_run.sh "<label>" <command...>
label="$1"; shift
mkdir -p ci-logs
log="ci-logs/$(echo "$label" | tr ' /' '__').log"
"$@" > "$log" 2>&1
code=$?
cat "$log"
if [ $code -ne 0 ]; then
  # analyzer errors one by one (max 9), then a tail summary
  grep -E "^\s*error •|^ERROR\|" "$log" | head -9 | while IFS= read -r l; do
    echo "::error title=$label::$(echo "$l" | sed 's/%/%25/g')"
  done
  tail -n 60 "$log" | sed 's/%/%25/g' | awk 'BEGIN{ORS="%0A"}{print}' | sed "s/^/::error title=$label (tail)::/"
  echo
fi
exit $code
