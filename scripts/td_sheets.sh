#!/usr/bin/env bash
set -euo pipefail

# Required:
#   GCP_SA_KEY              # service account JSON (string)
#   SHEETS_SPREADSHEET_ID   # target spreadsheet id
# Optional:
#   SUMMARY_FILE            # e.g., "summary.md" (if present, contents sent as "Result Summary")

# --- Read CLI output from stdin, echo to terminal, keep in variable ---
INPUT="$(cat)"
printf "%s" "$INPUT"

# --- Extract fields from CLI output ---
# Pass/Fail
if echo "$INPUT" | grep -qiE 'Test status:\s*passed'; then PASS="True"; else PASS="False"; fi
# Duration (prefer env var; fall back to parsing)
if [[ -n "${DURATION_MS:-}" ]]; then
  DURATION="$DURATION_MS"
else
  if DUR_MS_RAW="$(echo "$INPUT" | grep -ioE 'duration[:=]?[[:space:]]*[0-9]+[[:space:]]*ms' | tail -n1)"; then
    DURATION="${DUR_MS_RAW//[!0-9]/}"
  else
    DURATION="0"
  fi
fi

# Replay (last Dashcam URL)
REPLAY="$(echo "$INPUT" | grep -Eio 'https://app\.dashcam\.io/replay/[a-z0-9]+(\?share=[A-Za-z0-9]+)?' | tail -n1 || true)"
# Summary (optional file)
SUMMARY=""
if [[ -n "${SUMMARY_FILE:-}" && -f "${SUMMARY_FILE}" ]]; then
  SUMMARY="$(cat "$SUMMARY_FILE")"
fi

# --- New columns ---
TIMESTAMP="$(date -u '+%Y-%m-%d %H:%M:%S UTC')"     # first column
TEST_NAME="${1:-unknown}"                            # second column (pass test filename as arg)

# --- Build request body for Sheets ---
PAYLOAD="$(jq -n \
  --arg ts "$TIMESTAMP" \
  --arg test "$TEST_NAME" \
  --arg pass "$PASS" \
  --arg summary "$SUMMARY" \
  --argjson duration ${DURATION_MS:-0} \
  --arg replay "${REPLAY:-}" \
  '{majorDimension:"ROWS", values:[[ $ts, $test, $pass, $summary, $duration, $replay ]] }')"

# --- Service account auth (JWT) -> access token ---
SA_EMAIL="$(printf '%s' "${GCP_SA_KEY:?Missing GCP_SA_KEY}" | jq -r '.client_email')"
SA_PRIV_KEY="$(printf '%s' "${GCP_SA_KEY}" | jq -r '.private_key')"

b64url() { openssl base64 -A | tr '+/' '-_' | tr -d '='; }

HEADER='{"alg":"RS256","typ":"JWT"}'
IAT=$(date +%s)
EXP=$((IAT + 3600))
SCOPE="https://www.googleapis.com/auth/spreadsheets"
AUD="https://oauth2.googleapis.com/token"
PAYLOAD_JWT=$(jq -n --arg iss "$SA_EMAIL" --arg scope "$SCOPE" --arg aud "$AUD" --argjson iat "$IAT" --argjson exp "$EXP" \
  '{iss:$iss, scope:$scope, aud:$aud, iat:$iat, exp:$exp}')

H_B64=$(printf '%s' "$HEADER" | b64url)
P_B64=$(printf '%s' "$PAYLOAD_JWT" | b64url)
DATA="${H_B64}.${P_B64}"

KEYFILE="$(mktemp)"
trap 'rm -f "$KEYFILE"' EXIT
printf '%s' "$SA_PRIV_KEY" > "$KEYFILE"

SIG=$(printf '%s' "$DATA" | openssl dgst -sha256 -sign "$KEYFILE" -binary | b64url)
ASSERTION="${DATA}.${SIG}"

ACCESS_TOKEN="$(curl -s --fail -X POST "$AUD" \
  -H 'Content-Type: application/x-www-form-urlencoded' \
  --data "grant_type=urn:ietf:params:oauth:grant-type:jwt-bearer&assertion=${ASSERTION}" \
  | jq -r '.access_token')"

# --- Append the row to Google Sheets (no explicit range) ---
curl -s --fail -X POST \
  "https://sheets.googleapis.com/v4/spreadsheets/${SHEETS_SPREADSHEET_ID:?Missing SHEETS_SPREADSHEET_ID}/values/Sheet1:append?valueInputOption=RAW&insertDataOption=INSERT_ROWS" \
  -H "Authorization: Bearer ${ACCESS_TOKEN}" \
  -H "Content-Type: application/json" \
  --data "${PAYLOAD}" >/dev/null
