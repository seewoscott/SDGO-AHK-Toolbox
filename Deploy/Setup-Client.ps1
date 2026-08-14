# Setup-Client.ps1 — 新设备一键接入局域网自动更新
#
# 作用: 在新设备上部署 SDGO-Toolbox.exe 及自动更新配置。
#   1. 从共享目录拉取最新 SDGO-Toolbox.exe
#   2. 生成 Data\Settings.ini (自动写入正确的 ShareFolder)
#   3. 校验 SHA-256
#
# 用法 (在新设备上, 从共享目录拷本脚本后运行):
#   powershell -NoProfile -ExecutionPolicy Bypass -File Setup-Client.ps1
# 可选参数:
#   -SharePath  共享目录 (默认 \\192.168.124.3\Windows share)
#   -InstallDir 安装目录 (默认 $env:USERPROFILE\Desktop\SDGO工具脚本)
#   -Password   共享访问密码 (如共享需要凭据, 自动执行 net use)

param(
    [string]$SharePath  = "\\192.168.124.3\Windows share",
    [string]$InstallDir = "$env:USERPROFILE\Desktop\SDGO工具脚本",
    [string]$Password   = ""
)

$ErrorActionPreference = "Stop"
$shareExe = Join-Path $SharePath "SDGO-Toolbox.exe"
$shareJson = Join-Path $SharePath "version.json"

Write-Host "=== SDGO 工具脚本 新设备接入 ===" -ForegroundColor Cyan

# 1. 共享目录可达性 (必要时带凭据连接)
if (-not (Test-Path -LiteralPath $SharePath -PathType Container)) {
    if ($Password -ne "") {
        Write-Host "共享目录需要凭据, 尝试连接..." -ForegroundColor Yellow
        $shareName = "\\" + (($SharePath -replace '^\\\\', '') -split '\\')[0]
        net use $shareName $Password /user:Administrator 2>&1 | Out-Null
    }
    if (-not (Test-Path -LiteralPath $SharePath -PathType Container)) {
        throw "无法访问共享目录: $SharePath (请确认网络与权限)"
    }
}

# 2. 读取版本信息
$json = Get-Content -LiteralPath $shareJson -Raw -Encoding UTF8 | ConvertFrom-Json
$version = $json.version
$sha256 = $json.sha256
Write-Host "共享版本: v$version" -ForegroundColor Green

# 3. 创建安装目录
New-Item -ItemType Directory -Path $InstallDir -Force | Out-Null
New-Item -ItemType Directory -Path (Join-Path $InstallDir "Data") -Force | Out-Null

# 4. 复制 EXE
Write-Host "复制 SDGO-Toolbox.exe ..." -ForegroundColor Cyan
Copy-Item -LiteralPath $shareExe -Destination (Join-Path $InstallDir "SDGO-Toolbox.exe") -Force

# 5. 校验 SHA-256
$actualHash = (Get-FileHash -LiteralPath (Join-Path $InstallDir "SDGO-Toolbox.exe") -Algorithm SHA256).Hash.ToLowerInvariant()
if ($actualHash -ne $sha256.ToLowerInvariant()) {
    throw "SHA-256 校验失败! 下载的 EXE 可能已损坏."
}
Write-Host "SHA-256 校验通过 ✓" -ForegroundColor Green

# 6. 生成 Settings.ini (基于完整模板, 替换 ShareFolder 为共享路径)
#    模板取自已发布 EXE 的仓库模板 (Deploy/Settings.ini.template),
#    或在此脚本同目录查找; 找不到则生成最小可用配置。
$settingsPath = Join-Path $InstallDir "Data\Settings.ini"
$template = Join-Path $PSScriptRoot "Settings.ini.template"
if (Test-Path -LiteralPath $template) {
    $ini = Get-Content -LiteralPath $template -Raw -Encoding UTF8
    # 替换 ShareFolder 行 (兼容有无空格两种格式)
    $ini = $ini -replace '(?m)^ShareFolder=.*$', "ShareFolder=$SharePath"
    # 写入时用 UTF-8 with BOM (AHK 需要 BOM 才能正确读中文)
    $utf8Bom = New-Object System.Text.UTF8Encoding($true)
    [System.IO.File]::WriteAllText($settingsPath, $ini, $utf8Bom)
    Write-Host "Settings.ini 已生成 (基于模板, ShareFolder=$SharePath)" -ForegroundColor Green
} else {
    Write-Host "警告: 未找到 Settings.ini.template, 生成最小配置" -ForegroundColor Yellow
    $ini = @"
; SDGO Tool Script — User Config
[General]
HotkeyModifier=^!
EmergencyStop=Esc
GameExe=gonline.exe

[Updater]
Enabled=1
ShareFolder=$SharePath
VersionFile=version.json
CheckIntervalMinutes=30

[Game]
ServerProfile=OC_ASIA
"@
    $utf8Bom = New-Object System.Text.UTF8Encoding($true)
    [System.IO.File]::WriteAllText($settingsPath, $ini, $utf8Bom)
    Write-Host "Settings.ini 已生成 (最小配置)" -ForegroundColor Green
}

# 7. 完成
Write-Host ""
Write-Host "=== 部署完成 ===" -ForegroundColor Cyan
Write-Host "安装目录: $InstallDir"
Write-Host "当前版本: v$version"
Write-Host ""
Write-Host "启动方式: 双击 $InstallDir\SDGO-Toolbox.exe"
Write-Host "自动更新: 启动时检查 + 每 30 分钟检查共享目录新版本"
Write-Host "(共享目录: $SharePath)" -ForegroundColor DarkGray
