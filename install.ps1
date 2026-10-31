#Requires -Version 5.1
<#
    Far Far West - Cheat Mod installer
    ----------------------------------
    Installs the UE4SS mod loader (if missing), applies the Far Far West
    loader configuration and copies the FFW_Cheat mod.

    Usage:
        .\install.ps1
        .\install.ps1 -GamePath "F:\SteamLibrary\steamapps\common\FarFarWest"
        .\install.ps1 -Ue4ssSource "D:\Downloads\UE4SS"     # folder holding dwmapi.dll
        .\install.ps1 -Uninstall

    Nothing outside of the folders it creates is ever deleted.
#>
[CmdletBinding()]
param(
    [string]$GamePath,
    [string]$Ue4ssSource,
    [switch]$Uninstall,
    [switch]$SkipLoader
)

$ErrorActionPreference = 'Stop'
$scriptDir   = Split-Path -Parent $MyInvocation.MyCommand.Path
$modSource   = Join-Path $scriptDir 'Mods'
$configSource = Join-Path $scriptDir 'ue4ss-config'

function Ok([string]$t)   { Write-Host "  [ok]   $t" -ForegroundColor Green }
function Info([string]$t) { Write-Host "  ...    $t" -ForegroundColor Gray }
function Warn([string]$t) { Write-Host "  [warn] $t" -ForegroundColor Yellow }
function Fail([string]$t) { Write-Host "  [fail] $t" -ForegroundColor Red }

function Find-SteamLibraries {
    $libs = New-Object System.Collections.Generic.List[string]
    $steam = $null
    foreach ($key in @('HKCU:\Software\Valve\Steam', 'HKLM:\SOFTWARE\WOW6432Node\Valve\Steam')) {
        try {
            $item = Get-ItemProperty -Path $key -ErrorAction Stop
            if ($item.SteamPath)  { $steam = $item.SteamPath;  break }
            if ($item.InstallPath) { $steam = $item.InstallPath; break }
        } catch { }
    }
    if (-not $steam) {
        foreach ($c in @("${env:ProgramFiles(x86)}\Steam", "${env:ProgramFiles}\Steam")) {
            if ($c -and (Test-Path $c)) { $steam = $c; break }
        }
    }
    if ($steam) { $libs.Add($steam) }

    foreach ($vdf in @((Join-Path $steam 'steamapps\libraryfolders.vdf'),
                       (Join-Path $steam 'config\libraryfolders.vdf'))) {
        if ($steam -and (Test-Path $vdf)) {
            foreach ($line in Get-Content $vdf) {
                if ($line -match '"path"\s+"([^"]+)"') {
                    $p = $Matches[1] -replace '\\\\', '\'
                    if (Test-Path $p) { $libs.Add($p) }
                }
            }
        }
    }
    return $libs
}

function Find-Game {
    if ($GamePath) {
        if (Test-Path (Join-Path $GamePath 'FarFarWest\Binaries\Win64')) { return (Resolve-Path $GamePath).Path }
        Fail "-GamePath is not a Far Far West folder: $GamePath"
        return $null
    }
    foreach ($lib in (Find-SteamLibraries)) {
        $c = Join-Path $lib 'steamapps\common\FarFarWest'
        if (Test-Path (Join-Path $c 'FarFarWest\Binaries\Win64')) { return (Resolve-Path $c).Path }
    }
    return $null
}

function Get-Loader([string]$bin) {
    foreach ($n in @('UE4SS.dll', 'UE4SSL.dll')) {
        $p = Join-Path $bin "ue4ss\$n"
        if (Test-Path $p) { return $p }
    }
    return $null
}

function Install-Loader([string]$source, [string]$bin) {
    $proxy = Get-ChildItem $source -Filter 'dwmapi.dll' -File -ErrorAction SilentlyContinue | Select-Object -First 1
    if (-not $proxy) { $proxy = Get-ChildItem $source -Filter 'xinput*.dll' -File -ErrorAction SilentlyContinue | Select-Object -First 1 }
    if (-not $proxy) { throw "no UE4SS proxy dll (dwmapi.dll) in $source" }

    $srcUe4ss = Join-Path $source 'ue4ss'
    if (-not (Test-Path $srcUe4ss)) { $srcUe4ss = $source }

    $core = $null
    foreach ($n in @('UE4SS.dll', 'UE4SSL.dll')) {
        if (Test-Path (Join-Path $srcUe4ss $n)) { $core = Join-Path $srcUe4ss $n; break }
    }
    if (-not $core) { throw "no UE4SS.dll in $srcUe4ss" }

    $dstUe4ss = Join-Path $bin 'ue4ss'
    New-Item -ItemType Directory -Force $dstUe4ss | Out-Null
    New-Item -ItemType Directory -Force (Join-Path $dstUe4ss 'Mods') | Out-Null

    Copy-Item $proxy.FullName (Join-Path $bin 'dwmapi.dll') -Force
    Copy-Item $core (Join-Path $dstUe4ss (Split-Path $core -Leaf)) -Force

    # ship the stock mods / sdk backends that are part of a normal UE4SS install
    foreach ($item in (Get-ChildItem $srcUe4ss -Force)) {
        if ($item.Name -in @('Mods', 'UE4SS_Signatures', 'UE4SS-settings.ini')) { continue }
        Copy-Item $item.FullName (Join-Path $dstUe4ss $item.Name) -Recurse -Force
    }
    Ok ("loader installed: {0} + {1}" -f (Split-Path $proxy -Leaf), (Split-Path $core -Leaf))
}

Write-Host ""
Write-Host "Far Far West - Cheat Mod" -ForegroundColor Cyan
Write-Host ""

$game = Find-Game
if (-not $game) {
    Fail 'Far Far West not found. Pass -GamePath "<Steam>\steamapps\common\FarFarWest".'
    exit 1
}
Ok "game: $game"

$bin     = Join-Path $game 'FarFarWest\Binaries\Win64'
$ue4ss   = Join-Path $bin 'ue4ss'
$modsDir = Join-Path $ue4ss 'Mods'

if ($Uninstall) {
    Info 'removing mod files'
    foreach ($name in @('FFW_Cheat', 'FFW_Probe')) {
        $p = Join-Path $modsDir $name
        if (Test-Path $p) { Remove-Item $p -Recurse -Force; Ok "$name removed" }
    }
    Write-Host ""
    Write-Host "UE4SS itself was left installed:" -ForegroundColor DarkGray
    Write-Host "  $bin\dwmapi.dll" -ForegroundColor DarkGray
    Write-Host "  $ue4ss" -ForegroundColor DarkGray
    exit 0
}

# ---------------------------------------------------------------- loader
if ($SkipLoader) {
    Info 'skipping loader install (-SkipLoader)'
} else {
    $loader = Get-Loader $bin
    if ($loader) {
        Ok "loader present: $loader"
    } elseif ($Ue4ssSource) {
        Info "installing UE4SS from $Ue4ssSource"
        if (-not (Test-Path $Ue4ssSource)) { Fail "source not found: $Ue4ssSource"; exit 1 }
        Install-Loader $Ue4ssSource $bin
    } else {
        Warn 'UE4SS is not installed for this game yet.'
        Write-Host ""
        Write-Host "  Two ways to get it:" -ForegroundColor Yellow
        Write-Host "    a) download a UE4SS build, unzip it into:"
        Write-Host "       $bin"
        Write-Host "       (you should end up with $bin\dwmapi.dll and $bin\ue4ss\UE4SS.dll)"
        Write-Host "    b) or re-run this script with -Ue4ssSource pointing at any"
        Write-Host "       extracted UE4SS folder (dwmapi.dll + ue4ss\UE4SS.dll)."
        Write-Host ""
        Write-Host "  Then run install.ps1 again." -ForegroundColor Yellow
        exit 2
    }
}

# ---------------------------------------------------------------- config
if (Test-Path $configSource) {
    Info 'applying the Far Far West loader configuration'
    Copy-Item (Join-Path $configSource 'UE4SS-settings.ini') (Join-Path $ue4ss 'UE4SS-settings.ini') -Force
    $sigSrc = Join-Path $configSource 'UE4SS_Signatures'
    if (Test-Path $sigSrc) {
        $sigDst = Join-Path $ue4ss 'UE4SS_Signatures'
        New-Item -ItemType Directory -Force $sigDst | Out-Null
        Copy-Item (Join-Path $sigSrc '*.lua') $sigDst -Force
    }
    Ok 'configuration applied (engine 5.8 signatures, debug console on)'
}

# ---------------------------------------------------------------- mods
Info 'installing the cheat mod'
New-Item -ItemType Directory -Force $modsDir | Out-Null
$installed = @()
foreach ($mod in (Get-ChildItem $modSource -Directory)) {
    $target = Join-Path $modsDir $mod.Name
    if (Test-Path $target) { Remove-Item $target -Recurse -Force }
    Copy-Item $mod.FullName $target -Recurse -Force
    if (Test-Path (Join-Path $target 'Scripts\main.lua')) {
        New-Item -ItemType File -Force -Path (Join-Path $target 'enabled.txt') | Out-Null
    }
    $installed += $mod.Name
    Ok "mod: $($mod.Name)"
}

$modsTxt = Join-Path $modsDir 'mods.txt'
$lines = @()
if (Test-Path $modsTxt) { $lines = Get-Content $modsTxt | Where-Object { $_.Trim() -ne '' } }
foreach ($name in $installed) {
    $pattern = '^\s*' + [regex]::Escape($name) + '\s*:'
    $lines = $lines | Where-Object { $_ -notmatch $pattern }
    $lines += "$name : 1"
}
$lines | Set-Content -Path $modsTxt -Encoding ASCII

Write-Host ""
Write-Host "Done. Start the game, the mod loads by itself." -ForegroundColor Green
Write-Host "  hotkeys   see README.md" -ForegroundColor Gray
Write-Host "  log       $ue4ss\UE4SS.log" -ForegroundColor DarkGray
Write-Host "  console   the UE4SS debug window opens with the game (CTRL+O toggles it)" -ForegroundColor DarkGray
Write-Host ""
