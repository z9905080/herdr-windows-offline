<#
.SYNOPSIS
Installs Herdr (herdr-app + herdr-core) for the current user from this folder, fully offline.

.DESCRIPTION
Offline counterpart of the official installers
(https://releases.herdr.dev/app/install.ps1 and .../core/install.ps1):

  * herdr-app  -> %LOCALAPPDATA%\Programs\herdr-app   (Start menu "Herdr", on PATH)
  * herdr-core -> %LOCALAPPDATA%\Programs\herdr-core  (herdr-core.exe + conpty\, on PATH,
                  hc.exe hard link only if no `hc` exists yet)

Nothing is downloaded: every file is copied from windows-x86_64\ next to this
script after its SHA256 is checked against SHA256SUMS. No admin rights needed.

Running it again re-installs / upgrades: the app folder is swapped the way the
official installer does it (old folder renamed, removed when no longer in use);
an existing herdr-core older than the bundled one is updated the planned way
(`herdr-core update --from`), so running terminals keep running. A newer or
equal herdr-core is left alone. Settings under %APPDATA% / %LOCALAPPDATA% are
never touched.

.PARAMETER SkipCore
Do not install or update herdr-core.

.PARAMETER NoShortcut
Do not create the Start menu shortcut.

.PARAMETER NoPath
Do not add the install folders to the user PATH.

.EXAMPLE
powershell -NoProfile -File .\install.ps1 -WhatIf

.EXAMPLE
powershell -NoProfile -File .\install.ps1
#>
[CmdletBinding(SupportsShouldProcess = $true)]
param(
    [switch]$SkipCore,
    [switch]$NoShortcut,
    [switch]$NoPath
)

$ErrorActionPreference = "Stop"
$ProgressPreference = "SilentlyContinue"
. (Join-Path $PSScriptRoot "tools\herdr-offline-common.ps1")

$target = "windows-x86_64"
$payload = Join-Path $PSScriptRoot $target
$sums = Join-Path $PSScriptRoot "SHA256SUMS"

# --- Preconditions -----------------------------------------------------------
if ([Environment]::OSVersion.Platform -ne [PlatformID]::Win32NT) { Fail "this installer is for Windows" }
$arch = if ($env:PROCESSOR_ARCHITEW6432) { $env:PROCESSOR_ARCHITEW6432 } else { $env:PROCESSOR_ARCHITECTURE }
if ($arch -ne "AMD64") { Fail "this bundle is for x64 Windows only (found $arch)" }
$build = [Environment]::OSVersion.Version.Build
if ($build -lt 17134) { Fail "needs Windows 10 version 1803 (build 17134) or newer; this is build $build" }
if (-not $env:LOCALAPPDATA) { Fail "LOCALAPPDATA is not set" }
if (-not (Test-Path -LiteralPath $sums)) { Fail "SHA256SUMS not found next to install.ps1; copy the whole folder" }

$appVersion = (Get-Content -Raw (Join-Path $payload "app-latest.json") | ConvertFrom-Json).version
$coreVersion = (Get-Content -Raw (Join-Path $payload "core-latest.json") | ConvertFrom-Json).version
$bundleVersion = "$appVersion-core$coreVersion"

$programs = Join-Path $env:LOCALAPPDATA "Programs"
$appDir = Join-Path $programs "herdr-app"
$coreDir = Join-Path $programs "herdr-core"
if ($PSScriptRoot.TrimEnd('\').StartsWith($programs.TrimEnd('\'), [StringComparison]::OrdinalIgnoreCase)) {
    Fail "run install.ps1 from the bundle folder, not from inside $programs"
}

Write-Host "Herdr offline bundle $bundleVersion (app $appVersion, core $coreVersion) for $target"

# --- Verify payload (read-only, also under -WhatIf) ---------------------------
Write-Host "Checking files against SHA256SUMS..."
$problems = Test-Sha256Sums $PSScriptRoot $sums
if ($problems.Count) {
    $problems | ForEach-Object { Write-Host "  $_" }
    Fail "the bundle is incomplete or damaged; copy or clone it again"
}
if (-not (Test-Path -LiteralPath (Join-Path $payload "herdr-app\herdr-app.exe")) -or
    -not (Test-Path -LiteralPath (Join-Path $payload "herdr-core\herdr-core.exe")) -or
    -not (Test-Path -LiteralPath (Join-Path $payload "herdr-core\conpty\conpty.dll"))) {
    Fail "the bundle holds no complete app/core"
}
Write-Host "  all files OK"

$state = Read-InstallState
$whatIf = [bool]$WhatIfPreference

# Saved even if a step below fails, so uninstall.ps1 knows what to undo.
try {
    # --- herdr-app ---------------------------------------------------------------
    $staging = "$appDir.new"
    if ($PSCmdlet.ShouldProcess($appDir, "Install herdr-app $appVersion")) {
        New-Item -ItemType Directory -Force $programs | Out-Null
        Remove-Item -Recurse -Force -LiteralPath $staging -ErrorAction SilentlyContinue
        if (Test-Path -LiteralPath $staging) { Fail "cannot clear $staging; close anything using it and try again" }
        # Staged beside the target (same volume) so the swap is a rename.
        Copy-Tree (Join-Path $payload "herdr-app") $staging
        # A running app's folder can be renamed, not deleted: the old one goes
        # now if it can, else on the next install.
        Remove-Item -Recurse -Force -LiteralPath "$appDir.old" -ErrorAction SilentlyContinue
        if (Test-Path -LiteralPath "$appDir.old") { Fail "$appDir.old is still in use; quit Herdr and run install.ps1 again" }
        try {
            if (Test-Path -LiteralPath $appDir) { Rename-Item -LiteralPath $appDir "$appDir.old" }
            Rename-Item -LiteralPath $staging (Split-Path -Leaf $appDir)
        } catch { Fail "cannot replace ${appDir}: $($_.Exception.Message) - quit Herdr and try again" }
        Remove-Item -Recurse -Force -LiteralPath "$appDir.old" -ErrorAction SilentlyContinue
        $state.appInstalled = $true
        $state.appVersion = $appVersion
        Write-Host "herdr-app $appVersion installed into $appDir"
    }

    if (-not $NoShortcut) {
        $menu = Get-StartMenuShortcut
        if ($PSCmdlet.ShouldProcess($menu, "Create Start menu shortcut")) {
            $link = (New-Object -ComObject WScript.Shell).CreateShortcut($menu)
            $link.TargetPath = Join-Path $appDir "herdr-app.exe"
            $link.WorkingDirectory = $env:USERPROFILE
            $link.Description = "Terminals and coding agents that keep running"
            $link.Save()
            $state.shortcutCreated = $true
        }
    }

    # --- herdr-core --------------------------------------------------------------
    if (-not $SkipCore) {
        $coreExe = Join-Path $coreDir "herdr-core.exe"
        $bundledCore = Join-Path $payload "herdr-core"
        $wantCore = ConvertTo-HerdrVersion $coreVersion

        if (Test-Path -LiteralPath $coreExe) {
            $have = Get-ExeVersion $coreExe
            if ($have -and $have -ge $wantCore) {
                Write-Host "herdr-core $have is already installed (bundled: $wantCore); left as is"
            } elseif ($PSCmdlet.ShouldProcess($coreExe, "Update herdr-core $have -> $wantCore (herdr-core update --from)")) {
                # Swapped the planned way, so its terminals keep running.
                $tmp = Join-Path ([IO.Path]::GetTempPath()) "herdr-offline-$PID"
                New-Item -ItemType Directory -Force $tmp | Out-Null
                try {
                    $new = Join-Path $tmp "herdr-core.exe"
                    Copy-Item -LiteralPath (Join-Path $bundledCore "herdr-core.exe") -Destination $new
                    if (-not (Get-ExeVersion $new)) { Fail "the bundled herdr-core does not run on this machine" }
                    & $coreExe update --from $new | Out-Null
                    if ($LASTEXITCODE) { Fail "updating $coreExe failed (see above)" }
                } finally { Remove-Item -Recurse -Force -LiteralPath $tmp -ErrorAction SilentlyContinue }
                if (-not (Test-Path -LiteralPath (Join-Path $coreDir "conpty\conpty.dll"))) {
                    Copy-Tree (Join-Path $bundledCore "conpty") (Join-Path $coreDir "conpty")
                }
                Write-Host "herdr-core updated to $wantCore"
            }
        } elseif (Get-Command herdr-core -ErrorAction SilentlyContinue) {
            # One installed elsewhere is not ours to replace.
            Write-Host "herdr-core found at $((Get-Command herdr-core).Source); left as is"
        } elseif ($PSCmdlet.ShouldProcess($coreDir, "Install herdr-core $wantCore")) {
            New-Item -ItemType Directory -Force $coreDir | Out-Null
            Copy-Item -LiteralPath (Join-Path $bundledCore "herdr-core.exe") -Destination $coreExe
            Copy-Tree (Join-Path $bundledCore "conpty") (Join-Path $coreDir "conpty")
            $state.coreInstalledByBundle = $true
            if (-not (Get-ExeVersion $coreExe)) { Fail "herdr-core does not run on this machine" }
            Write-Host "herdr-core $wantCore installed into $coreDir"
        }

        if ((Test-Path -LiteralPath $coreExe) -and -not $whatIf) {
            Copy-Tree (Join-Path $bundledCore "THIRD-PARTY-NOTICES") (Join-Path $coreDir "THIRD-PARTY-NOTICES")
            Copy-Item -Force -LiteralPath (Join-Path $bundledCore "LICENSE") -Destination (Join-Path $coreDir "LICENSE")
            $hc = Join-Path $coreDir "hc.exe"
            if (-not (Get-Command hc -ErrorAction SilentlyContinue) -and -not (Test-Path -LiteralPath $hc)) {
                try {
                    New-Item -ItemType HardLink -Path $hc -Target $coreExe | Out-Null
                    $state.hcLinkCreated = $true
                } catch { Write-Warning "could not create $hc ($($_.Exception.Message)); use herdr-core instead of hc" }
            }
            $v = Get-ExeVersion $coreExe
            if ($v) { $state.coreVersion = "$v" }
        }
    }

    # --- PATH (per user, raw so %VARIABLES% stay as they are) ---------------------
    if (-not $NoPath) {
        $dirs = @($appDir)
        if (-not $SkipCore -and ((Test-Path -LiteralPath (Join-Path $coreDir "herdr-core.exe")) -or $whatIf)) { $dirs += $coreDir }
        foreach ($d in $dirs) {
            $raw = Get-UserPathRaw
            if (-not (Test-PathEntry $raw $d) -and $PSCmdlet.ShouldProcess("user PATH", "Add $d")) {
                Set-UserPathRaw (Add-PathEntry $raw $d)
                if (Test-SameDir $d $appDir) { $state.pathAddedApp = $true } else { $state.pathAddedCore = $true }
                Write-Host "Added $d to your PATH (new terminals see it)"
            }
            if (-not $whatIf -and ($env:Path -split ";") -notcontains $d) { $env:Path += ";$d" }
        }
    }

    if ($whatIf) {
        Write-Host "WhatIf: nothing was changed."
        return
    }
    $state.bundleVersion = $bundleVersion
} finally {
    if (-not $whatIf) { Write-InstallState $state }
}
Write-Host "Herdr is installed. Open it from the Start menu, or run: herdr-app"
