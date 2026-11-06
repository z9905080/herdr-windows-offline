# Static checks for the bundle's PowerShell scripts (runs on any pwsh, incl. Linux):
#  * parses with the PowerShell parser (no syntax errors)
#  * ASCII only (Windows PowerShell 5.1 reads BOM-less files in the ANSI code page)
#  * no syntax newer than 5.1 (??, ?., ternary, && / ||) via PSScriptAnalyzer when available
param([string]$Root = (Split-Path -Parent $PSScriptRoot))
$ErrorActionPreference = "Stop"
$failed = 0
$files = @(Get-ChildItem -LiteralPath $Root -Recurse -Filter *.ps1 | Where-Object { $_.FullName -notmatch '[\\/]\.git[\\/]' })
foreach ($f in $files) {
    $tokens = $null; $errors = $null
    [void][System.Management.Automation.Language.Parser]::ParseFile($f.FullName, [ref]$tokens, [ref]$errors)
    if ($errors.Count) { $failed++; $errors | ForEach-Object { Write-Host "PARSE  $($f.Name):$($_.Extent.StartLineNumber) $($_.Message)" } }
    $bytes = [IO.File]::ReadAllBytes($f.FullName)
    if ($bytes | Where-Object { $_ -gt 127 } | Select-Object -First 1) { $failed++; Write-Host "ASCII  $($f.Name) has non-ASCII bytes" }
    Write-Host "ok     $($f.FullName.Substring($Root.Length + 1))"
}
if (Get-Module -ListAvailable PSScriptAnalyzer) {
    Import-Module PSScriptAnalyzer
    $settings = @{ Rules = @{ PSUseCompatibleSyntax = @{ Enable = $true; TargetVersions = @("5.1") } } }
    foreach ($f in $files) {
        $r = @(Invoke-ScriptAnalyzer -Path $f.FullName -Settings $settings -IncludeRule PSUseCompatibleSyntax)
        $r | ForEach-Object { $failed++; Write-Host "PS5.1  $($f.Name):$($_.Line) $($_.Message)" }
        $e = @(Invoke-ScriptAnalyzer -Path $f.FullName -Severity Error)
        $e | ForEach-Object { $failed++; Write-Host "PSSA   $($f.Name):$($_.Line) $($_.RuleName) $($_.Message)" }
    }
    Write-Host "PSScriptAnalyzer: PS 5.1 syntax compatibility + error-severity rules checked"
} else {
    Write-Host "PSScriptAnalyzer not installed: 5.1 syntax compatibility NOT checked"
}
if ($failed) { Write-Host "FAILED ($failed)"; exit 1 }
Write-Host "parse checks passed ($($files.Count) files)"
