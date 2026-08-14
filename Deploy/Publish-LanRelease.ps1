[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$SourceDirectory,
    [Parameter(Mandatory)][string]$SharePath
)

$ErrorActionPreference = "Stop"
$files = @("SDGO-Toolbox.exe", "version.json")
if (-not (Test-Path -LiteralPath $SharePath -PathType Container)) { throw "局域网共享目录不可用: $SharePath" }
foreach ($file in $files) {
    if (-not (Test-Path -LiteralPath (Join-Path $SourceDirectory $file) -PathType Leaf)) {
        throw "发布源缺少文件 $file"
    }
}
$manifest = Get-Content -LiteralPath (Join-Path $SourceDirectory "version.json") -Raw | ConvertFrom-Json
if ([string]::IsNullOrWhiteSpace($manifest.sha256) -or $manifest.sha256 -notmatch '^[a-fA-F0-9]{64}$') {
    throw "version.json 必须包含 SHA-256 摘要。"
}
if ($manifest.file_name -ne "SDGO-Toolbox.exe") { throw "意外的发布文件名: $($manifest.file_name)" }
$sourceHash = (Get-FileHash -LiteralPath (Join-Path $SourceDirectory "SDGO-Toolbox.exe") -Algorithm SHA256).Hash
if ($sourceHash -ine $manifest.sha256) { throw "源 EXE 的 SHA-256 与 version.json 不匹配。" }

# EXE is published first and manifest last.  Clients only update after reading a
# newer manifest, so they never request an EXE that has not arrived yet.
Copy-Item -LiteralPath (Join-Path $SourceDirectory "SDGO-Toolbox.exe") -Destination (Join-Path $SharePath "SDGO-Toolbox.exe") -Force
$publishedHash = (Get-FileHash -LiteralPath (Join-Path $SharePath "SDGO-Toolbox.exe") -Algorithm SHA256).Hash
if ($publishedHash -ine $manifest.sha256) { throw "已发布 EXE 的 SHA-256 校验失败。" }
Copy-Item -LiteralPath (Join-Path $SourceDirectory "version.json") -Destination (Join-Path $SharePath "version.json") -Force
Write-Host "已发布文件到 $SharePath"
