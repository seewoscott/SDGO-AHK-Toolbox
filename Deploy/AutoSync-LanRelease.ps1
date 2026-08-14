# AutoSync-LanRelease.ps1
# 定时检查 GitHub 最新 Release，有新版本时自动同步到局域网共享目录。
# 由 Windows 任务计划程序每 5 分钟调用一次（无新版本时静默跳过，不产生噪音）。
#
# 用法: powershell -NoProfile -ExecutionPolicy Bypass -File AutoSync-LanRelease.ps1
# 可选参数: -Repository, -SharePath, -LogFile

param(
    [string]$Repository = "seewoscott/SDGO-AHK-Toolbox",
    [string]$SharePath  = "\\192.168.124.3\Windows share",
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

# ---- 1. 共享目录可达性 (区分: 网络不可达 vs 存储 I/O 故障) ----
if (-not (Test-Path -LiteralPath $SharePath -PathType Container)) {
    Write-Log "跳过: 共享目录不可访问: $SharePath (检查网络连接与 NAS 共享权限)"
    exit 0
}

# 写测试: 确认共享目录可写 (I/O 故障时 Test-Path 可能误报可用)
$probeFile = Join-Path $SharePath (".sync-probe-" + [guid]::NewGuid().ToString("N") + ".tmp")
try {
    Set-Content -LiteralPath $probeFile -Value "probe" -Encoding utf8
    Remove-Item -LiteralPath $probeFile -Force -ErrorAction SilentlyContinue
} catch {
    Write-Log "跳过: 共享目录不可写: $SharePath (存储设备可能存在 I/O 故障, 请检查 NAS 硬盘)"
    exit 0
}

# ---- 2. 获取 GitHub 最新 Release ----
try {
    $headers = @{ Accept = "application/vnd.github+json" }
    $release = Invoke-RestMethod -Headers $headers -Uri "https://api.github.com/repos/$Repository/releases/latest"
} catch {
    Write-Log "跳过: 获取最新 Release 失败: $($_.Exception.Message)"
    exit 0
}

$remoteVersion = $release.tag_name -replace '^v', ''
if (-not $remoteVersion) {
    Write-Log "跳过: 没有可用 Release"
    exit 0
}

# ---- 3. 读取共享目录当前版本 ----
$currentVersion = "0.0.0"
$localManifest = Join-Path $SharePath "version.json"
try {
    if (Test-Path -LiteralPath $localManifest) {
        $m = Get-Content -LiteralPath $localManifest -Raw -Encoding utf8 | ConvertFrom-Json
        if ($m.version) { $currentVersion = $m.version -replace '^v', '' }
    }
} catch {
    Write-Log "警告: 读取本地 version.json 失败, 视为无版本: $($_.Exception.Message)"
}

# ---- 4. 版本比较 (含 SHA-256 一致性: 同版本号重新发布时也触发同步) ----
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

# 远程清单的 SHA-256 (Release 资产, 用 curl.exe 下载避免 Invoke-RestMethod 重定向问题)
$remoteSha = $null
foreach ($asset in $release.assets) {
    if ($asset.name -eq "version.json") {
        try {
            $tmpJson = Join-Path $env:TEMP ("sdgo-remote-" + [guid]::NewGuid().ToString("N") + ".json")
            curl.exe -sL -o $tmpJson $asset.browser_download_url | Out-Null
            if (Test-Path -LiteralPath $tmpJson) {
                $remoteManifest = Get-Content -LiteralPath $tmpJson -Raw -Encoding utf8 | ConvertFrom-Json
                $remoteSha = $remoteManifest.sha256
                Remove-Item -LiteralPath $tmpJson -Force -ErrorAction SilentlyContinue
            }
        } catch { }
        break
    }
}

# 本地清单的 SHA-256
$localSha = $null
if (Test-Path -LiteralPath $localManifest) {
    try {
        $lm = Get-Content -LiteralPath $localManifest -Raw -Encoding utf8 | ConvertFrom-Json
        $localSha = $lm.sha256
    } catch { }
}

$cmp = Compare-Version $remoteVersion $currentVersion
if ($cmp -lt 0) {
    Write-Log "跳过: 远程版本低于本地 (远程 $remoteVersion < 本地 $currentVersion)"
    exit 0
}
if ($cmp -eq 0 -and $remoteSha -and $localSha -and $remoteSha -ieq $localSha) {
    Write-Log "跳过: 无新版本 (远程 $remoteVersion = 本地 $currentVersion, SHA-256 一致)"
    exit 0
}
if ($cmp -eq 0) {
    Write-Log "检测到同版本号重新发布 (远程 $remoteVersion, SHA-256 与本地不同), 重新同步..."
}

# ---- 5. 执行同步 ----
Write-Log "检测到新版本 $remoteVersion (本地 $currentVersion)，开始同步..."
$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Definition
try {
    & (Join-Path $scriptDir "Sync-ReleaseToLanShare.ps1") -Repository $Repository -SharePath $SharePath -Tag $release.tag_name
    Write-Log "同步完成: v$remoteVersion -> $SharePath"
} catch {
    Write-Log "同步失败: $($_.Exception.Message) (详见上方错误; 常见原因: 共享目录只读或存储 I/O 故障)"
    exit 0
}
