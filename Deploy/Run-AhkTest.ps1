# Run-AhkTest.ps1 — Run an AutoHotkey v2 test script and surface its real exit code.
#
# Why this exists:
#   AutoHotkey64.exe is a GUI-subsystem binary. When PowerShell invokes it with
#   the & call operator, $LASTEXITCODE is NOT updated (stays $null), and
#   $null -ne 0 is $true in PowerShell — so `& $ahk ...; if ($LASTEXITCODE -ne 0)`
#   reports failure even when the script passed.
#   Start-Process -Wait -PassThru can also hang when stdout/stderr are not
#   redirected (GUI binary waiting on an inherited-but-invalid console handle).
#   This script uses System.Diagnostics.Process with redirected output, which
#   is reliable in CI, and prints captured stdout so failures are diagnosable.

param(
    [Parameter(Mandatory = $true)][string]$AhkExe,
    [Parameter(Mandatory = $true)][string]$ScriptPath,
    [int]$TimeoutSeconds = 120
)

$ErrorActionPreference = "Stop"

if (-not (Test-Path -LiteralPath $AhkExe)) { throw "AHK runtime not found: $AhkExe" }
if (-not (Test-Path -LiteralPath $ScriptPath)) { throw "Script not found: $ScriptPath" }

$psi = New-Object System.Diagnostics.ProcessStartInfo
$psi.FileName = $AhkExe
$psi.Arguments = "/ErrorStdOut `"$ScriptPath`""
$psi.UseShellExecute = $false
$psi.RedirectStandardOutput = $true
$psi.RedirectStandardError = $true
$psi.CreateNoWindow = $true

$proc = [System.Diagnostics.Process]::Start($psi)

# Read streams asynchronously to avoid deadlock on full buffers.
$outTask = $proc.StandardOutput.ReadToEndAsync()
$errTask = $proc.StandardError.ReadToEndAsync()

if (-not $proc.WaitForExit($TimeoutSeconds * 1000)) {
    try { $proc.Kill() } catch { }
    throw "AHK test timed out after ${TimeoutSeconds}s: $ScriptPath"
}

$stdout = $outTask.Result
$stderr = $errTask.Result

if (-not [string]::IsNullOrWhiteSpace($stdout)) { Write-Host $stdout }
if (-not [string]::IsNullOrWhiteSpace($stderr)) { Write-Host $stderr }

if ($proc.ExitCode -ne 0) {
    throw "AHK test failed with exit code $($proc.ExitCode): $ScriptPath"
}

Write-Host "AHK test passed: $ScriptPath"
