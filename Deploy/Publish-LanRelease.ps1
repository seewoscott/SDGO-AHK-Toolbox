[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$SourceDirectory,
    [Parameter(Mandatory)][string]$SharePath
)

$ErrorActionPreference = "Stop"
$files = @("SDGO-Toolbox.exe", "version.json")
if (-not (Test-Path -LiteralPath $SharePath -PathType Container)) { throw "LAN share is unavailable: $SharePath" }
foreach ($file in $files) {
    if (-not (Test-Path -LiteralPath (Join-Path $SourceDirectory $file) -PathType Leaf)) {
        throw "Release source is missing $file"
    }
}
$manifest = Get-Content -LiteralPath (Join-Path $SourceDirectory "version.json") -Raw | ConvertFrom-Json
if ([string]::IsNullOrWhiteSpace($manifest.sha256) -or $manifest.sha256 -notmatch '^[a-fA-F0-9]{64}$') {
    throw "version.json must contain a SHA-256 digest."
}
if ($manifest.file_name -ne "SDGO-Toolbox.exe") { throw "Unexpected release file name: $($manifest.file_name)" }
$sourceHash = (Get-FileHash -LiteralPath (Join-Path $SourceDirectory "SDGO-Toolbox.exe") -Algorithm SHA256).Hash
if ($sourceHash -ine $manifest.sha256) { throw "Source EXE SHA-256 does not match version.json." }

# EXE is published first and manifest last.  Clients only update after reading a
# newer manifest, so they never request an EXE that has not arrived yet.
Copy-Item -LiteralPath (Join-Path $SourceDirectory "SDGO-Toolbox.exe") -Destination (Join-Path $SharePath "SDGO-Toolbox.exe") -Force
$publishedHash = (Get-FileHash -LiteralPath (Join-Path $SharePath "SDGO-Toolbox.exe") -Algorithm SHA256).Hash
if ($publishedHash -ine $manifest.sha256) { throw "Published EXE SHA-256 verification failed." }
Copy-Item -LiteralPath (Join-Path $SourceDirectory "version.json") -Destination (Join-Path $SharePath "version.json") -Force
Write-Host "Published release files to $SharePath"
