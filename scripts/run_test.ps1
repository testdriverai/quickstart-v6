# --- Run TestDriverAI test and capture output ---
$replay = ($inputText | Select-String -AllMatches -Pattern 'https://app\.dashcam\.io/replay/[a-z0-9]+(\?share=[A-Za-z0-9]+)?').Matches | Select-Object -Last 1 -ExpandProperty Value
$summary = ''
if ($env:SUMMARY_FILE -and (Test-Path -LiteralPath $env:SUMMARY_FILE)) { $summary = Get-Content -Raw -LiteralPath $env:SUMMARY_FILE }


$timestamp = (Get-Date).ToUniversalTime().ToString("yyyy-MM-dd HH:mm:ss 'UTC'")
$testName = $TestFile


# --- Build Sheets payload ---
$payload = @{ majorDimension = "ROWS"; values = @(@($timestamp, $testName, $pass, $summary, [int]$durationMs, ($replay ?? ""))) } | ConvertTo-Json -Depth 5


# --- Google OAuth (Service Account JWT) ---
$sa = $env:GCP_SA_KEY | ConvertFrom-Json
if (-not $sa) { throw "Missing or invalid GCP_SA_KEY." }
$saEmail = $sa.client_email
$rawKey = $sa.private_key -replace '\\n',"`n" # normalize


$header = @{ alg = "RS256"; typ = "JWT" } | ConvertTo-Json -Compress
$iat = [int]([DateTimeOffset]::UtcNow.ToUnixTimeSeconds())
$exp = $iat + 3600
$scope = "https://www.googleapis.com/auth/spreadsheets"
$aud = "https://oauth2.googleapis.com/token"
$claims = @{ iss = $saEmail; scope = $scope; aud = $aud; iat = $iat; exp = $exp } | ConvertTo-Json -Compress


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
} else { throw "ImportFromPem not available" }
} catch {
$openssl = (Get-Command openssl -ErrorAction SilentlyContinue)?.Source
if (-not $openssl) { throw "Cannot sign JWT: need PowerShell 7+ (RSA.ImportFromPem) or OpenSSL in PATH." }
$tmpKey = New-TemporaryFile
try {
Set-Content -LiteralPath $tmpKey.FullName -Value $rawKey -NoNewline
$sigBytes = & $openssl dgst -sha256 -sign $tmpKey.FullName -binary -passin pass:
$signatureB64Url = ConvertTo-Base64Url $sigBytes
} finally { Remove-Item -Force $tmpKey.FullName }
}


$assertion = "$data.$signatureB64Url"


$tokenResp = Invoke-RestMethod -Method POST -Uri $aud -ContentType 'application/x-www-form-urlencoded' -Body @{ grant_type = 'urn:ietf:params:oauth:grant-type:jwt-bearer'; assertion = $assertion }
$accessToken = $tokenResp.access_token
if (-not $accessToken) { throw "Failed to obtain access token." }


# --- Append to Google Sheets ---
$range = if ($env:SHEETS_RANGE) { $env:SHEETS_RANGE } else { 'Sheet1' }
$encRange = [System.Web.HttpUtility]::UrlEncode($range)
$appendUrl = "https://sheets.googleapis.com/v4/spreadsheets/$($env:SHEETS_SPREADSHEET_ID)/values/$encRange:append?valueInputOption=RAW&insertDataOption=INSERT_ROWS"


Invoke-RestMethod -Method POST -Uri $appendUrl -Headers @{ Authorization = "Bearer $accessToken" } -ContentType 'application/json' -Body $payload | Out-Null


exit $exitCode