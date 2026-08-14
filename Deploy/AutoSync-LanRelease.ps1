# AutoSync-LanRelease.ps1
# 定时检查 GitHub 最新 Release，有新版本时自动同步到局域网共享目录。
# 由 Windows 任务计划程序每 5 分钟调用一次（无新版本时静默跳过，不产生噪音）。
#
# 用法: powershell -NoProfile -ExecutionPolicy Bypass -File AutoSync-LanRelease.ps1
# 可选参数: -Repository, -SharePath, -LogFile

param(
    [string]$Repository = "seewoscott/SDGO-AHK-Toolbox",
    [string]$SharePath  = "\\192.168.124.2\Windows share",
    [string]$LogFile    = "$env:LOCALAPPDATA\SDGO-Toolbox\autosync.log"
)

$ErrorActionPreference = "Stop"

# ---- 日志 ----
$logDir = Split-Path -Parent $LogFile
if (-not (Test-Path -LiteralPath $logDir)) {
    New-Item -ItemType Directory -Path $logDir -Force | Out-Null
}
function Write-Log($msg) {
    $line = "[{0}] {1}" -f (Get-Date -Format "yyyy-MM-dd HH:mm:ss"), $msg
    Add-Content -LiteralPath $LogFile -Value $line -Encoding utf8
}

# ---- 1. 共享目录可达性 ----
if (-not (Test-Path -LiteralPath $SharePath -PathType Container)) {
    Write-Log "SKIP: 共享目录不可访问: $SharePath"
    exit 0
}

# ---- 2. 获取 GitHub 最新 Release ----
try {
    $headers = @{ Accept = "application/vnd.github+json" }
    $release = Invoke-RestMethod -Headers $headers -Uri "https://api.github.com/repos/$Repository/releases/latest"
} catch {
    Write-Log "SKIP: 获取最新 Release 失败: $($_.Exception.Message)"
    exit 0
}

$remoteVersion = $release.tag_name -replace '^v', ''
if (-not $remoteVersion) {
    Write-Log "SKIP: 没有可用 Release"
    exit 0
}

# ---- 3. 读取共享目录当前版本 ----
$currentVersion = "0.0.0"
$localManifest = Join-Path $SharePath "version.json"
if (Test-Path -LiteralPath $localManifest) {
    try {
        $m = Get-Content -LiteralPath $localManifest -Raw -Encoding utf8 | ConvertFrom-Json
        if ($m.version) { $currentVersion = $m.version -replace '^v', '' }
    } catch {
        Write-Log "WARN: 本地 version.json 解析失败，视为无版本"
    }
}

# ---- 4. 版本比较 ----
function Compare-Version($a, $b) {
    $pa = $a.Split('.') | ForEach-Object { [int]$_ }
    $pb = $b.Split('.') | ForEach-Object { [int]$_ }
    $n = [Math]::Max($pa.Count, $pb.Count)
    for ($i = 0; $i -lt $n; $i++) {
        $va = if ($i -lt $pa.Count) { $pa[$i] } else { 0 }
        $vb = if ($i -lt $pb.Count) { $pb[$i] } else { 0 }
        if ($va -gt $vb) { return 1 }
        if ($va -lt $vb) { return -1 }
    }
    return 0
}

$cmp = Compare-Version $remoteVersion $currentVersion
if ($cmp -le 0) {
    Write-Log "SKIP: 无新版本 (远程 $remoteVersion <= 本地 $currentVersion)"
    exit 0
}

# ---- 5. 执行同步 ----
Write-Log "检测到新版本 $remoteVersion (本地 $currentVersion)，开始同步..."
$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Definition
try {
    & (Join-Path $scriptDir "Sync-ReleaseToLanShare.ps1") -Repository $Repository -SharePath $SharePath -Tag $release.tag_name
    Write-Log "同步完成: v$remoteVersion -> $SharePath"
} catch {
    Write-Log "同步失败: $($_.Exception.Message)"
    exit 0
}
