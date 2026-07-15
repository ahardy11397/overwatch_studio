param(
    [ValidateSet("Debug", "Release")]
    [string]$Config = "Release"
)

$ErrorActionPreference = "Stop"
$repoRoot = Split-Path -Parent $PSScriptRoot

# Ensure wix is installed
if (-not (Get-Command wix -ErrorAction SilentlyContinue)) {
    Write-Host "Installing WiX Toolset..." -ForegroundColor Yellow
    dotnet tool install --global wix --version 5.0.0
}

# Build the installer
Write-Host "Building installer ($Config)..." -ForegroundColor Cyan
& wix build "$repoRoot\installer\overwatch-studio.wxs" `
    -o "$repoRoot\build\installer\OverwatchStudio-Setup.msi" `
    -d RepoRoot="$repoRoot" `
    -d BuildOutput="$repoRoot\build\bin\$Config" `
    -d QtDir="$repoRoot\libs\Qt\6.6.2\msvc2019_64" `
    -d VCRedist="C:\Program Files\Microsoft Visual Studio\2022\Community\VC\Redist\MSVC\14.38.33130\x64\Microsoft.VC143.CRT"

if ($LASTEXITCODE -ne 0) {
    Write-Host "WiX build failed!" -ForegroundColor Red
    exit 1
}

Write-Host "Installer created: build\installer\OverwatchStudio-Setup.msi" -ForegroundColor Green
