# Unit tests for tools/herdr-offline-common.ps1 (no Pester needed; runs on Linux pwsh too).
# Only the pure helpers are covered: registry, shortcuts and real installs need Windows.
$ErrorActionPreference = "Stop"
$root = Split-Path -Parent $PSScriptRoot
. (Join-Path $root "tools/herdr-offline-common.ps1")

$script:fails = 0; $script:passes = 0
function Check([string]$Name, $Got, $Want) {
    if ("$Got" -ceq "$Want") { $script:passes++ } else { $script:fails++; Write-Host "FAIL $Name`n  got:  $Got`n  want: $Want" }
}

$tmp = Join-Path ([IO.Path]::GetTempPath()) "herdr-offline-tests-$PID"
New-Item -ItemType Directory -Force $tmp | Out-Null
try {
    # --- PATH string handling ---------------------------------------------
    $d = 'C:\Users\u\AppData\Local\Programs\herdr-app'
    $raw = '%USERPROFILE%\bin;C:\Tools;%LOCALAPPDATA%\Microsoft\WindowsApps'
    Check "add appends, keeps %VARS%" (Add-PathEntry $raw $d) "$raw;$d"
    Check "add to empty" (Add-PathEntry "" $d) $d
    Check "add strips trailing ;" (Add-PathEntry "$raw;" $d) "$raw;$d"
    Check "add is idempotent" (Add-PathEntry "$raw;$d" $d) "$raw;$d"
    Check "add matches case/trailing \ insensitively" (Add-PathEntry "$raw;$($d.ToUpper())\" $d) "$raw;$($d.ToUpper())\"
    Check "remove drops only ours" (Remove-PathEntry "$raw;$d" $d) $raw
    Check "remove from middle" (Remove-PathEntry "C:\A;$d\;C:\B" $d) "C:\A;C:\B"
    Check "remove keeps unrelated prefix match" (Remove-PathEntry "$d-old;C:\B" $d) "$d-old;C:\B"
    Check "remove when absent is no-op" (Remove-PathEntry $raw $d) $raw
    Check "test entry true" (Test-PathEntry "$raw;$d" $d) $true
    Check "test entry false" (Test-PathEntry $raw $d) $false
    Check "roundtrip add/remove" (Remove-PathEntry (Add-PathEntry $raw $d) $d) $raw

    # --- versions -----------------------------------------------------------
    Check "version from hc output" (ConvertTo-HerdrVersion "hc 0.1.18") "0.1.18"
    Check "version none" ($null -eq (ConvertTo-HerdrVersion "garbage")) $true
    Check "version compare" ((ConvertTo-HerdrVersion "hc 0.1.9") -lt (ConvertTo-HerdrVersion "0.1.18")) $true

    # --- SHA256SUMS verification -------------------------------------------
    $b = Join-Path $tmp "bundle"
    New-Item -ItemType Directory -Force (Join-Path $b "w/sub") | Out-Null
    [IO.File]::WriteAllText((Join-Path $b "w/a.txt"), "hello`n")
    [IO.File]::WriteAllText((Join-Path $b "w/sub/b.bin"), "bytes")
    $ha = Get-Sha256Hex (Join-Path $b "w/a.txt")
    Check "sha256 known value" $ha "5891b5b522d5df086d0ff0b110fbd9d21bb4fc7163af34d08286a2e846f6be03"
    $hb = Get-Sha256Hex (Join-Path $b "w/sub/b.bin")
    [IO.File]::WriteAllLines((Join-Path $b "SUMS"), @("$ha  w/a.txt", "$hb *w/sub/b.bin"))
    Check "sums ok" (Test-Sha256Sums $b (Join-Path $b "SUMS")).Count 0
    [IO.File]::WriteAllText((Join-Path $b "w/a.txt"), "tampered")
    Check "sums detects tamper" ((Test-Sha256Sums $b (Join-Path $b "SUMS")) -join "|") "checksum mismatch: w/a.txt"
    Remove-Item (Join-Path $b "w/sub/b.bin")
    Check "sums detects missing" ((Test-Sha256Sums $b (Join-Path $b "SUMS")) -join "|") "checksum mismatch: w/a.txt|missing: w/sub/b.bin"
    [IO.File]::WriteAllLines((Join-Path $b "BAD"), @("nothex  w/a.txt"))
    $threw = $false; try { Read-Sha256Sums (Join-Path $b "BAD") | Out-Null } catch { $threw = $true }
    Check "sums rejects malformed" $threw $true

    # Real bundle manifest, if run from the repo.
    if (Test-Path (Join-Path $root "SHA256SUMS")) {
        Check "repo SHA256SUMS verifies" ((Test-Sha256Sums $root (Join-Path $root "SHA256SUMS")) -join "|") ""
    }

    # --- Copy-Tree merges instead of nesting --------------------------------
    $src = Join-Path $tmp "src"; $dst = Join-Path $tmp "dst"
    New-Item -ItemType Directory -Force (Join-Path $src "conpty/x64") | Out-Null
    [IO.File]::WriteAllText((Join-Path $src "conpty/conpty.dll"), "dll")
    [IO.File]::WriteAllText((Join-Path $src "conpty/x64/OpenConsole.exe"), "exe")
    Copy-Tree (Join-Path $src "conpty") (Join-Path $dst "conpty")
    Copy-Tree (Join-Path $src "conpty") (Join-Path $dst "conpty")
    $files = @(Get-ChildItem -Recurse -File $dst | ForEach-Object { $_.FullName.Substring($dst.Length + 1) -replace '\\', '/' } | Sort-Object)
    Check "copy-tree twice, no nesting" ($files -join ",") "conpty/conpty.dll,conpty/x64/OpenConsole.exe"

    # --- install record roundtrip ------------------------------------------
    $saved = $env:LOCALAPPDATA
    $env:LOCALAPPDATA = Join-Path $tmp "lad"
    try {
        $s = Read-InstallState
        Check "fresh state appInstalled" $s.appInstalled $false
        $s.appInstalled = $true; $s.coreInstalledByBundle = $true; $s.bundleVersion = "0.1.13-core0.1.18"
        Write-InstallState $s
        $s2 = Read-InstallState
        Check "state roundtrip appInstalled" $s2.appInstalled $true
        Check "state roundtrip core" $s2.coreInstalledByBundle $true
        Check "state roundtrip version" $s2.bundleVersion "0.1.13-core0.1.18"
        Check "state untouched key" $s2.hcLinkCreated $false
    } finally { $env:LOCALAPPDATA = $saved }
} finally {
    Remove-Item -Recurse -Force $tmp -ErrorAction SilentlyContinue
}

Write-Host "$script:passes passed, $script:fails failed"
if ($script:fails) { exit 1 }
