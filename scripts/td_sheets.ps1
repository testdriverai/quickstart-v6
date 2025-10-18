<# 
Requires:
  $env:GCP_SA_KEY              # service account JSON string
  $env:SHEETS_SPREADSHEET_ID   # spreadsheet ID
Optional:
  $env:SHEETS_RANGE            # e.g. "Sheet1" or "Results!A:F" (default: Sheet1)
  $env:SUMMARY_FILE            # path to summary.md
Notes:
  - PowerShell 7+ recommended (uses RSA.ImportFromPem). If unavailable, the script falls back to OpenSSL if present.
#>

param(
  [Parameter(Mandatory=$true)][string]$TestFile
)

function ConvertTo-Base64Url([byte[]]$bytes) {
  [Convert]::ToBase64String($bytes).TrimEnd('=') -replace '\+','-' -replace '/','_'
}
function Get-UTF8Bytes([string]$s) {
  [System.Text.Encoding]::UTF8.GetBytes($s)
}

# --- Run test with live output and capture log ---
$start = Get-Date
$log = New-TemporaryFile
try {
  # Combine stdout+stderr; capture; preserve native exit code
  $procInfo = New-Object System.Diagnostics.ProcessStartInfo
  $procInfo.FileName = "npx"
  $procInfo.ArgumentList = @("testdriverai@latest","run",$TestFile)
  $procInfo.RedirectStandardOutput = $true
  $procInfo.RedirectStandardError  = $true
  $procInfo.UseShellExecute = $false
  $proc = New-Object System.Diagnostics.Process
  $proc.StartInfo = $procInfo
  [void]$proc.Start()
  $sw = [System.IO.StreamWriter]::new($log.FullName, $false, [System.Text.Encoding]::UTF8)
  try {
    while (-not $proc.HasExited) {
      if (!$proc.StandardOutput.EndOfStream) {
        $line = $proc.StandardOutput.ReadLine()
        Write-Host $line
        $sw.WriteLine($line)
      }
      if (!$proc.StandardError.EndOfStream) {
        $line = $proc.StandardError.ReadLine()
        Write-Host $line
        $sw.WriteLine($line)
      }
      Start-Sleep -Milliseconds 10
    }
    # Drain remaining
    while (-not $proc.StandardOutput.EndOfStream) { $line=$proc.StandardOutput.ReadLine(); Write-Host $line; $sw.WriteLine($line) }
    while (-not $proc.StandardError.EndOfStream)  { $line=$proc.StandardError.ReadLine();  Write-Host $line; $sw.WriteLine($line) }
  } finally {
    $sw.Flush(); $sw.Dispose()
  }
  $proc.WaitForExit()
  $exitCode = $proc.ExitCode
} finally {
  $end = Get-Date
}

$durationMs = [math]::Round(($end - $start).TotalMilliseconds)

# --- Parse log for details ---
$inputText = Get-Content -Raw -Path $log.FullName
$pass = if ($inputText -match 'Test status:\s*(passed)') { 'True' } else { if ($exitCode -eq 0) { 'True' } else { 'False' } }
$replay = ($inputText | Select-String -AllMatches -Pattern 'https://app\.dashcam\.io/replay/[a-z0-9]+(\?share=[A-Za-z0-9]+)?').Matches | Select-Object -Last 1 -ExpandProperty Value
$summary = ''
if ($env:SUMMARY_FILE -and (Test-Path -LiteralPath $env:SUMMARY_FILE)) {
  $summary = Get-Content -Raw -LiteralPath $env:SUMMARY_FILE
}

$timestamp = (Get-Date).ToUniversalTime().ToString("yyyy-MM-dd HH:mm:ss 'UTC'")
$testName  = $TestFile

# --- Build Sheets payload ---
$payload = @{
  majorDimension = "ROWS"
  values        = @(@($timestamp, $testName, $pass, $summary, [int]$durationMs, ($replay ?? "")))
} | ConvertTo-Json -Depth 5

# --- Google OAuth (Service Account JWT) ---
$sa = $env:GCP_SA_KEY | ConvertFrom-Json
if (-not $sa) { throw "Missing or invalid GCP_SA_KEY." }
$saEmail = $sa.client_email
$rawKey  = $sa.private_key -replace '\\n',"`n"  # normalize

$header  = @{ alg = "RS256"; typ = "JWT" } | ConvertTo-Json -Compress
$iat     = [int][double]::Parse((Get-Date -Date (Get-Date).ToUniversalTime()).ToUniversalTime().Subtract([DateTime]'1970-01-01').TotalSeconds)
$exp     = $iat + 3600
$scope   = "https://www.googleapis.com/auth/spreadsheets"
$aud     = "https://oauth2.googleapis.com/token"
$claims  = @{ iss = $saEmail; scope = $scope; aud = $aud; iat = $iat; exp = $exp } | ConvertTo-Json -Compress

$hB64 = ConvertTo-Base64Url (Get-UTF8Bytes $header)
$pB64 = ConvertTo-Base64Url (Get-UTF8Bytes $claims)
$data = "$hB64.$pB64"

# Sign RS256 using .NET (PowerShell 7+) or fallback to OpenSSL if available
$signatureB64Url = $null
try {
  $rsa = [System.Security.Cryptography.RSA]::Create()
  if ($rsa -and ($rsa | Get-Member -Name ImportFromPem -ErrorAction SilentlyContinue)) {
    $rsa.ImportFromPem($rawKey.ToCharArray())
    $sig = $rsa.SignData((Get-UTF8Bytes $data), [System.Security.Cryptography.HashAlgorithmName]::SHA256, [System.Security.Cryptography.RSASignaturePadding]::Pkcs1)
    $signatureB64Url = ConvertTo-Base64Url $sig
  } else {
    throw "ImportFromPem not available"
  }
} catch {
  # Fallback to OpenSSL if installed
  $openssl = (Get-Command openssl -ErrorAction SilentlyContinue)?.Source
  if (-not $openssl) { throw "Cannot sign JWT: need PowerShell 7+ (RSA.ImportFromPem) or OpenSSL in PATH." }
  $tmpKey = New-TemporaryFile
  try {
    Set-Content -LiteralPath $tmpKey.FullName -Value $rawKey -NoNewline
    $sigBytes = & $openssl dgst -sha256 -sign $tmpKey.FullName -binary -passin pass:
    $signatureB64Url = (ConvertTo-Base64Url $sigBytes)
  } finally {
    Remove-Item -Force $tmpKey.FullName
  }
}

$assertion = "$data.$signatureB64Url"

$tokenResp = Invoke-RestMethod -Method POST -Uri $aud -ContentType 'application/x-www-form-urlencoded' -Body @{
  grant_type = 'urn:ietf:params:oauth:grant-type:jwt-bearer'
  assertion  = $assertion
}
$accessToken = $tokenResp.access_token
if (-not $accessToken) { throw "Failed to obtain access token." }

# --- Append to Google Sheets ---
$range   = if ($env:SHEETS_RANGE) { $env:SHEETS_RANGE } else { "Sheet1" }
$encRange = [System.Web.HttpUtility]::UrlEncode($range)
$appendUrl = "https://sheets.googleapis.com/v4/spreadsheets/$($env:SHEETS_SPREADSHEET_ID)/values/$encRange:append?valueInputOption=RAW&insertDataOption=INSERT_ROWS"

Invoke-RestMethod -Method POST -Uri $appendUrl -Headers @{ Authorization = "Bearer $accessToken" } -ContentType 'application/json' -Body $payload | Out-Null

# Bubble up the test's exit code
exit $exitCode
