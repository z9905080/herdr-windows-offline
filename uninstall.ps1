<#
.SYNOPSIS
Removes what install.ps1 put in place, and nothing else.

.DESCRIPTION
  * %LOCALAPPDATA%\Programs\herdr-app and the Start menu "Herdr" shortcut
    (the shortcut only if it points at that folder).
  * %LOCALAPPDATA%\Programs\herdr-core only if install.ps1 created it (a core
    that was already there, or that lives elsewhere, is left alone), unless
    -RemoveCore is given.
  * The PATH entries install.ps1 added; every other PATH entry stays as is.

Never touched: this bundle folder, your Herdr settings and data under
%APPDATA% / %LOCALAPPDATA%, other Herdr installs.

.PARAMETER KeepCore
Leave herdr-core in place even if install.ps1 installed it.

.PARAMETER RemoveCore
Also remove %LOCALAPPDATA%\Programs\herdr-core when it was not installed by
this bundle (for example by the official installer or the app's own updater).

.PARAMETER Force
Remove %LOCALAPPDATA%\Programs\herdr-app (and its PATH entry) even when there
is no record of install.ps1 having installed it.

.EXAMPLE
powershell -NoProfile -File .\uninstall.ps1 -WhatIf
#>
[CmdletBinding(SupportsShouldProcess = $true)]
param(
    [switch]$KeepCore,
    [switch]$RemoveCore,
    [switch]$Force
)

$ErrorActionPreference = "Stop"
$ProgressPreference = "SilentlyContinue"
. (Join-Path $PSScriptRoot "tools\herdr-offline-common.ps1")

if ([Environment]::OSVersion.Platform -ne [PlatformID]::Win32NT) { Fail "this uninstaller is for Windows" }
if ($KeepCore -and $RemoveCore) { Fail "-KeepCore and -RemoveCore contradict each other" }
if (-not $env:LOCALAPPDATA) { Fail "LOCALAPPDATA is not set" }

$programs = Join-Path $env:LOCALAPPDATA "Programs"
$appDir = Join-Path $programs "herdr-app"
$coreDir = Join-Path $programs "herdr-core"
$state = Read-InstallState
$hadState = Test-Path -LiteralPath (Get-StateFile)
$whatIf = [bool]$WhatIfPreference

function Get-ProcessesUnder([string]$Name, [string]$Dir) {
    @(Get-Process -Name $Name -ErrorAction SilentlyContinue | Where-Object {
        $_.Path -and $_.Path.StartsWith($Dir.TrimEnd('\') + '\', [StringComparison]::OrdinalIgnoreCase)
    })
}

$removeApp = $state.appInstalled -or $Force
$removeCore = -not $KeepCore -and ($state.coreInstalledByBundle -or $RemoveCore) -and (Test-Path -LiteralPath $coreDir)

if (-not $hadState -and -not $Force -and -not $RemoveCore) {
    Write-Host "No record of an install by this bundle ($(Get-StateFile))."
    Write-Host "Nothing removed. Use -Force to remove $appDir anyway (and -RemoveCore for herdr-core)."
    return
}

# Refuse rather than half-remove a folder that is in use.
if ($removeApp -and (Get-ProcessesUnder "herdr-app" $appDir).Count) {
    Fail "Herdr is running; quit it and run uninstall.ps1 again"
}
if ($removeCore -and ((Get-ProcessesUnder "herdr-core" $coreDir).Count -or (Get-ProcessesUnder "hc" $coreDir).Count)) {
    Fail "herdr-core is running (it keeps your terminals alive); close those terminals and stop it, or run with -KeepCore"
}

# --- herdr-app ---------------------------------------------------------------
if ($removeApp) {
    foreach ($d in $appDir, "$appDir.old", "$appDir.new") {
        if ((Test-Path -LiteralPath $d) -and $PSCmdlet.ShouldProcess($d, "Remove folder")) {
            Remove-Item -Recurse -Force -LiteralPath $d
            Write-Host "removed $d"
        }
    }
    $menu = Get-StartMenuShortcut
    $t = Get-ShortcutTarget $menu
    if ($t -and $t.StartsWith($appDir.TrimEnd('\') + '\', [StringComparison]::OrdinalIgnoreCase) -and
        $PSCmdlet.ShouldProcess($menu, "Remove Start menu shortcut")) {
        Remove-Item -Force -LiteralPath $menu
        Write-Host "removed $menu"
    }
} else {
    Write-Host "herdr-app was not installed by this bundle; left as is (use -Force to remove it)"
}

# --- herdr-core --------------------------------------------------------------
if ($removeCore) {
    if ($PSCmdlet.ShouldProcess($coreDir, "Remove folder")) {
        Remove-Item -Recurse -Force -LiteralPath $coreDir
        Write-Host "removed $coreDir"
    }
} elseif (Test-Path -LiteralPath $coreDir) {
    Write-Host "herdr-core left in place at $coreDir"
}

# --- PATH --------------------------------------------------------------------
$drop = @()
if ($removeApp -and ($state.pathAddedApp -or $Force)) { $drop += $appDir }
if ($removeCore -and ($state.pathAddedCore -or $RemoveCore)) { $drop += $coreDir }
foreach ($d in $drop) {
    $raw = Get-UserPathRaw
    if ((Test-PathEntry $raw $d) -and $PSCmdlet.ShouldProcess("user PATH", "Remove $d")) {
        Set-UserPathRaw (Remove-PathEntry $raw $d)
        Write-Host "removed $d from your PATH"
    }
}

if ($whatIf) {
    Write-Host "WhatIf: nothing was changed."
    return
}

# --- Install record ----------------------------------------------------------
$coreLeft = $state.coreInstalledByBundle -and -not $removeCore
if ($coreLeft) {
    # Still remember the core, so a later uninstall.ps1 can remove it.
    $state.appInstalled = $false; $state.shortcutCreated = $false; $state.pathAddedApp = $false; $state.appVersion = $null
    Write-InstallState $state
} else {
    Remove-Item -Recurse -Force -LiteralPath (Get-StateDir) -ErrorAction SilentlyContinue
}

Write-Host "Herdr uninstalled. Your settings under %APPDATA% / %LOCALAPPDATA% were not touched."
