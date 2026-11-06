# Shared helpers for install.ps1 / uninstall.ps1 (dot-sourced; PowerShell 5.1+).
# Kept free of side effects so tests can dot-source it on any platform.

$script:BundleName = "herdr-windows-offline"

function Fail($why) { throw "herdr-offline: $why" }

# .NET, not Get-FileHash: that one fails when PowerShell 7 starts 5.1.
function Get-Sha256Hex([string]$Path) {
    $stream = [IO.File]::OpenRead($Path)
    try {
        $sha = [Security.Cryptography.SHA256]::Create()
        try { return -join ($sha.ComputeHash($stream) | ForEach-Object { $_.ToString("x2") }) } finally { $sha.Dispose() }
    } finally { $stream.Close() }
}

# Reads a sha256sum-style file ("<hex>  <relative/path>", "*" binary marker allowed).
function Read-Sha256Sums([string]$Path) {
    $entries = @()
    foreach ($line in [IO.File]::ReadAllLines($Path)) {
        $l = $line.Trim()
        if (-not $l -or $l.StartsWith("#")) { continue }
        if ($l -notmatch '^([0-9a-fA-F]{64}) [ *](.+)$') { Fail "malformed line in ${Path}: $line" }
        $entries += [pscustomobject]@{ Hash = $Matches[1].ToLowerInvariant(); RelPath = $Matches[2] }
    }
    return ,$entries
}

# Checks every file listed in SHA256SUMS under $Root. Returns the list of problems (empty = OK).
function Test-Sha256Sums([string]$Root, [string]$SumsFile) {
    $problems = @()
    $entries = Read-Sha256Sums $SumsFile
    if ($entries.Count -eq 0) { return ,@("no entries in $SumsFile") }
    foreach ($e in $entries) {
        $rel = $e.RelPath -replace '/', [IO.Path]::DirectorySeparatorChar
        $full = Join-Path $Root $rel
        if (-not (Test-Path -LiteralPath $full -PathType Leaf)) { $problems += "missing: $($e.RelPath)"; continue }
        $got = Get-Sha256Hex $full
        if ($got -ne $e.Hash) { $problems += "checksum mismatch: $($e.RelPath)" }
    }
    return ,$problems
}

# "hc 0.1.18" / "herdr-core 0.1.18" / "0.1.18-beta" -> [version] 0.1.18, or $null.
function ConvertTo-HerdrVersion([string]$Text) {
    if ($Text -match '(\d+)\.(\d+)\.(\d+)') { return [version]"$($Matches[1]).$($Matches[2]).$($Matches[3])" }
    return $null
}

# Copies the files under $From into $To, merging with what is there (no
# Copy-Item -Recurse nesting surprises when $To already has the subfolder).
function Copy-Tree([string]$From, [string]$To) {
    $from = (Resolve-Path -LiteralPath $From).ProviderPath.TrimEnd('\', '/')
    if (-not (Test-Path -LiteralPath $To)) { New-Item -ItemType Directory -Force $To | Out-Null }
    foreach ($f in Get-ChildItem -LiteralPath $from -Recurse -Force -File) {
        $rel = $f.FullName.Substring($from.Length).TrimStart('\', '/')
        $dst = Join-Path $To $rel
        $dstDir = Split-Path -Parent $dst
        if (-not (Test-Path -LiteralPath $dstDir)) { New-Item -ItemType Directory -Force $dstDir | Out-Null }
        [IO.File]::Copy($f.FullName, $dst, $true)
    }
}

# Runs "<exe> --version" and returns the parsed [version], or $null if it does not run.
function Get-ExeVersion([string]$Exe) {
    try {
        $out = (& $Exe --version) -join " "
        if ($LASTEXITCODE) { return $null }
        return ConvertTo-HerdrVersion $out
    } catch { return $null }
}

function Test-SameDir([string]$A, [string]$B) {
    return ($A.Trim().TrimEnd('\', '/') -ieq $B.Trim().TrimEnd('\', '/'))
}

# Pure string helpers over a raw (unexpanded) PATH value: other entries are
# kept byte-for-byte, including %VARIABLES% and their order.
function Add-PathEntry([string]$Raw, [string]$Dir) {
    foreach ($p in ($Raw -split ';')) { if ($p -and (Test-SameDir $p $Dir)) { return $Raw } }
    if ($Raw) { return "$($Raw.TrimEnd(';'));$Dir" }
    return $Dir
}

function Remove-PathEntry([string]$Raw, [string]$Dir) {
    $kept = @($Raw -split ';' | Where-Object { -not ($_ -and (Test-SameDir $_ $Dir)) })
    return ($kept -join ';')
}

function Test-PathEntry([string]$Raw, [string]$Dir) {
    foreach ($p in ($Raw -split ';')) { if ($p -and (Test-SameDir $p $Dir)) { return $true } }
    return $false
}

# Registry access for the per-user PATH (HKCU\Environment), raw so %VARIABLES% stay unexpanded.
function Get-UserPathRaw {
    $key = [Microsoft.Win32.Registry]::CurrentUser.OpenSubKey("Environment", $false)
    try {
        if (-not $key) { return "" }
        return [string]$key.GetValue("Path", "", [Microsoft.Win32.RegistryValueOptions]::DoNotExpandEnvironmentNames)
    } finally { if ($key) { $key.Close() } }
}

function Set-UserPathRaw([string]$Value) {
    $key = [Microsoft.Win32.Registry]::CurrentUser.CreateSubKey("Environment")
    try {
        # Keep the existing value kind (normally REG_EXPAND_SZ).
        $kind = if ($key.GetValueNames() -contains "Path") { $key.GetValueKind("Path") } else { [Microsoft.Win32.RegistryValueKind]::ExpandString }
        if ($Value) { $key.SetValue("Path", $Value, $kind) } else { $key.DeleteValue("Path", $false) }
    } finally { $key.Close() }
    # Setting any user variable tells running programs the environment changed.
    [Environment]::SetEnvironmentVariable("HERDR_INSTALLING", "1", "User")
    [Environment]::SetEnvironmentVariable("HERDR_INSTALLING", $null, "User")
}

# Install record, so uninstall.ps1 only removes what this bundle created.
function Get-StateDir { return (Join-Path $env:LOCALAPPDATA $script:BundleName) }
function Get-StateFile { return (Join-Path (Get-StateDir) "install-state.json") }

function Read-InstallState {
    $f = Get-StateFile
    $s = [ordered]@{
        bundleVersion = $null; appVersion = $null; coreVersion = $null
        appInstalled = $false; coreInstalledByBundle = $false; hcLinkCreated = $false
        pathAddedApp = $false; pathAddedCore = $false; shortcutCreated = $false
    }
    if (Test-Path -LiteralPath $f) {
        try {
            $j = [IO.File]::ReadAllText($f) | ConvertFrom-Json
            foreach ($k in @($s.Keys)) { if ($null -ne $j.$k) { $s[$k] = $j.$k } }
        } catch { Write-Warning "ignoring unreadable $f" }
    }
    return $s
}

function Write-InstallState($State) {
    $d = Get-StateDir
    if (-not (Test-Path -LiteralPath $d)) { New-Item -ItemType Directory -Force $d | Out-Null }
    [IO.File]::WriteAllText((Get-StateFile), ($State | ConvertTo-Json))
}

function Get-StartMenuShortcut { return (Join-Path ([Environment]::GetFolderPath("Programs")) "Herdr.lnk") }

function Get-ShortcutTarget([string]$Lnk) {
    if (-not (Test-Path -LiteralPath $Lnk)) { return $null }
    try { return (New-Object -ComObject WScript.Shell).CreateShortcut($Lnk).TargetPath } catch { return $null }
}
