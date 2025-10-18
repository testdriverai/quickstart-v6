# TestDriver → Google Sheets (GCP API) Integration

Append each test run to a Google Sheet using the **Google Sheets API** (no Apps Script) and a **GCP service account**. This README covers **Bash/zsh (macOS/Linux)** and **PowerShell (Windows)** usage with the wrappers already in this repo.

---

## What you’ll get

Each run appends a row shaped like:

- Timestamp (UTC)
- Test (filename)
- Pass
- Result Summary
- Duration (ms)
- Replay URL

---

## Prerequisites

1. **Enable Google Sheets API** for your GCP project.
2. **Create a Service Account** and download a **JSON key**.
3. **Share your Google Sheet** with the service account email as **Editor** OR with anyone with the link.
4. **Install tools**:
   - macOS/Linux: `bash`, `jq`, `curl`, `openssl`, Node.js/npm.
   - Windows: PowerShell 7+ (recommended), Node.js/npm.
5. **Get your Spreadsheet ID** from the Sheet URL (`https://docs.google.com/spreadsheets/d/<ID>/edit`).

---

## Environment variables (all platforms)

Set the following before running:

- `GCP_SA_KEY` (required): full service account JSON. Either include real newlines or `\n`; the scripts normalize both.
- `SHEETS_SPREADSHEET_ID` (required): your Google Sheet ID.
- `SHEETS_RANGE` (optional): tab name or range, e.g. `Sheet1` or `Results!A:F`. Default is `Sheet1`.
- `SUMMARY_FILE` (optional): path to a `summary.md` file; contents are appended as the “Result Summary” column.

**macOS/Linux example:** export variables in your shell profile or session, e.g. `export GCP_SA_KEY='{"type":"service_account", ...}'`, `export SHEETS_SPREADSHEET_ID="your-spreadsheet-id"`, `export SHEETS_RANGE="Sheet1"`.

**Windows example:** set environment variables in your session, e.g. `$env:GCP_SA_KEY='{"type":"service_account", ...}'`, `$env:SHEETS_SPREADSHEET_ID='your-spreadsheet-id'`, `$env:SHEETS_RANGE='Sheet1'`.

---

## Using the wrappers

### macOS/Linux (Bash/zsh)

- Ensure the scripts are executable: run `chmod +x scripts/td_sheets.sh run_test.sh` once.
- Run a test with the wrapper: `./run_test.sh <path/to/test.yaml>`.

### Windows (PowerShell)

- Run a test with the wrapper: `./run_test.ps1 <path\to\test.yaml>`.

---

## Install the wrapper globally as `run_test`

### macOS/Linux

- From your repo root, create symlinks: `sudo ln -s "$(pwd)/run_test.sh" /usr/local/bin/run_test` and `sudo ln -s "$(pwd)/scripts/td_sheets.sh" /usr/local/bin/td_sheets`.
- Make sure they’re executable: `sudo chmod +x /usr/local/bin/run_test /usr/local/bin/td_sheets`.
- If needed, add `/usr/local/bin` to your PATH: append `export PATH="/usr/local/bin:$PATH"` to your shell profile and restart your shell.
- Usage from anywhere: `run_test <path/to/test.yaml>`.

### Windows

1. Create a user bin folder if you don’t have one, e.g. `C:\Users\<you>\bin`.
2. Copy the wrapper: `Copy-Item .\run_test.ps1 $HOME\bin\run_test.ps1`.
3. Allow script execution (CurrentUser): `Set-ExecutionPolicy RemoteSigned -Scope CurrentUser -Force`.
4. Add the folder to your user PATH (one-time). In PowerShell: update PATH to include `%USERPROFILE%\bin`, then restart your terminal.
5. Optional convenience: add a function alias named `run_test` to your `$PROFILE` that calls `$HOME\bin\run_test.ps1`.
6. Usage from anywhere: `run_test <path\to\test.yaml>` (or `run_test.ps1 <path\to\test.yaml>` if you didn’t add the alias).

---

## Troubleshooting

- **No rows appear**: confirm the service account email has **Editor** access; verify **Sheets API** is enabled; check `SHEETS_SPREADSHEET_ID` and the exact tab name in `SHEETS_RANGE`.
- **Token errors (`invalid_grant`)**: private key newline formatting is the usual cause; ensure `GCP_SA_KEY` JSON is intact (the scripts normalize `\n` to newlines).
- **Missing tools**: macOS/Linux require `jq`, `curl`, `openssl`; Windows requires PowerShell 7+ or OpenSSL for JWT signing fallback.

---

## Example end-to-end

1. Set environment variables (`GCP_SA_KEY`, `SHEETS_SPREADSHEET_ID`, and optionally `SHEETS_RANGE`, `SUMMARY_FILE`).
2. Run the wrapper with your test file:
   - macOS/Linux: `./run_test.sh testdriver/tests/login.yaml`
   - Windows: `./run_test.ps1 testdriver\tests\login.yaml`

With the wrapper on your PATH, you can simply run `run_test <path/to/test.yaml>` from any directory.
