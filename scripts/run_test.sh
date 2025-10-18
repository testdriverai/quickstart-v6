#!/usr/bin/env bash
set -euo pipefail

TEST_FILE="${1:?usage: ./run_td_and_append.sh path/to/test.yaml}"

START_MS=$(($(date +%s%N)/1000000))
LOG="$(mktemp)"
trap 'rm -f "$LOG"' EXIT

# Live output to terminal + log to file
npx testdriverai@latest run "$TEST_FILE" 2>&1 | tee "$LOG"
EXIT_CODE=${PIPESTATUS[0]}

END_MS=$(($(date +%s%N)/1000000))
DURATION_MS=$((END_MS - START_MS)) / 1000  # in seconds

# If you have a summary file, point to it (optional)
[[ -f summary.md ]] && export SUMMARY_FILE="summary.md"

# Post to Google Sheets. td_sheets.sh reads the log from stdin.
DURATION_MS="$DURATION_MS" ./scripts/td_sheets.sh "$TEST_FILE" < "$LOG"

exit $EXIT_CODE
