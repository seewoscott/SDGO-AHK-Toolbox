[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$Repository,
    [Parameter(Mandatory)][string]$SharePath,
    [string]$Tag = "latest"
)

$ErrorActionPreference = "Stop"
if (-not (Test-Path -LiteralPath $SharePath -PathType Container)) { throw "LAN share is unavailable: $SharePath" }
$headers = @{ Accept = "application/vnd.github+json" }
if ($Tag -eq "latest") { $release = Invoke-RestMethod -Headers $headers -Uri "https://api.github.com/repos/$Repository/releases/latest" }
else { $release = Invoke-RestMethod -Headers $headers -Uri "https://api.github.com/repos/$Repository/releases/tags/$Tag" }
$requiredFiles = @("SDGO-Toolbox.exe", "version.json")
$assets = @{}
foreach ($asset in $release.assets) { $assets[$asset.name] = $asset }
foreach ($file in $requiredFiles) { if (-not $assets.ContainsKey($file)) { throw "Release $($release.tag_name) does not contain $file" } }
$stagePath = Join-Path ([IO.Path]::GetTempPath()) ("SDGO-release-" + [guid]::NewGuid())
New-Item -ItemType Directory -Path $stagePath | Out-Null
try {
    foreach ($file in $requiredFiles) { Invoke-WebRequest -Headers $headers -Uri $assets[$file].browser_download_url -OutFile (Join-Path $stagePath $file) }
    & $PSScriptRoot\Publish-LanRelease.ps1 -SourceDirectory $stagePath -SharePath $SharePath
    Write-Host "Published $($release.tag_name) to $SharePath"
} finally { Remove-Item -LiteralPath $stagePath -Recurse -Force -ErrorAction SilentlyContinue }
