param(
    [switch]$SkipBuild,
    [switch]$SkipMsi
)

$ErrorActionPreference = "Stop"
$PSNativeCommandUseErrorActionPreference = $true

$root = Split-Path -Parent $PSScriptRoot
Set-Location $root
$versionLines = @(Get-Content (Join-Path $root "VERSION"))
if ($versionLines.Count -ne 2 -or $versionLines[1] -notmatch '^[1-9][0-9]*$') {
    throw "VERSION must contain a version and positive build number"
}
$marketingVersion = $versionLines[0]
$buildNumber = [int]$versionLines[1]
if ($marketingVersion -notmatch '^(?<major>[0-9]+)\.(?<minor>[0-9]+)\.(?<patch>[0-9]+)') {
    throw "VERSION contains an invalid marketing version: $marketingVersion"
}
$major = [int]$Matches.major
$minor = [int]$Matches.minor
if ($major -gt 255 -or $minor -gt 255 -or $buildNumber -gt 65535) {
    throw "VERSION cannot be represented as a Windows Installer product version"
}
$msiVersion = "$major.$minor.$buildNumber"
$packageVersion = "$marketingVersion-$buildNumber"
$bundle = Join-Path $root "build\windows\x64\runner\Release"
$output = Join-Path $root "build\archive"
$archive = Join-Path $output "ProcessLama-$packageVersion-windows-x86_64.zip"
$installer = Join-Path $output "ProcessLama-$packageVersion-windows-x86_64.msi"

if (-not $SkipBuild) {
    . (Join-Path $PSScriptRoot "initialize-msvc-environment.ps1")
    flutter config --enable-windows-desktop
    flutter pub get --enforce-lockfile
    flutter build windows --release
}
foreach ($required in @("processlama.exe", "flutter_windows.dll", "data")) {
    if (-not (Test-Path (Join-Path $bundle $required))) {
        throw "Windows release bundle is missing $required"
    }
}

# Remote helpers for every host target (docs/10_remote_hosts.md section 8.2). Release CI
# sets PROCESSLAMA_REQUIRE_REMOTE_HELPER=1 so a missing target fails the package.
$helperSource = if ($env:PROCESSLAMA_REMOTE_HELPER_DIR) { $env:PROCESSLAMA_REMOTE_HELPER_DIR } else { Join-Path $root "build\remote-helper" }
$helperDest = Join-Path $bundle "remote-helper"
Remove-Item -Recurse -Force -ErrorAction SilentlyContinue $helperDest
$compatibility = (Get-Content (Join-Path $root "rust-core\remote-helper\COMPATIBILITY") | Where-Object { $_ -match '^version ' }) -replace '^version ', ''
$expectedBuildId = $compatibility.Trim().PadLeft(40, '0')
$bundledHelpers = @()
foreach ($target in @("linux-x86_64", "linux-arm64", "macos-arm64", "macos-x86_64")) {
    $binary = Join-Path $helperSource "$target\processlama-remote-helper"
    $descriptorPath = Join-Path $helperSource "$target\processlama-remote-helper.json"
    if (-not (Test-Path $binary -PathType Leaf)) { continue }
    $descriptor = Get-Content -Raw $descriptorPath | ConvertFrom-Json
    $hash = (Get-FileHash -Algorithm SHA256 $binary).Hash.ToLowerInvariant()
    $size = (Get-Item $binary).Length
    if ($descriptor.target -ne $target -or $descriptor.buildId -ne $expectedBuildId -or $descriptor.sha256 -ne $hash -or $descriptor.size -ne $size) {
        throw "Remote helper $target does not match its descriptor or this build"
    }
    $targetDest = Join-Path $helperDest $target
    New-Item -ItemType Directory -Force $targetDest | Out-Null
    Copy-Item $binary, $descriptorPath $targetDest
    # Extracted archives keep their fixed member time; the bundle gets the build time.
    Get-ChildItem $targetDest -File | ForEach-Object { $_.LastWriteTime = Get-Date }
    $bundledHelpers += $target
}
if ($env:PROCESSLAMA_REQUIRE_REMOTE_HELPER -eq "1" -and $bundledHelpers.Count -ne 4) {
    throw "Missing remote helpers; bundled: $($bundledHelpers -join ', ')"
}
Write-Output "Bundled remote helpers: $($bundledHelpers -join ', ')"

New-Item -ItemType Directory -Force $output | Out-Null
Remove-Item -Force -ErrorAction SilentlyContinue $archive
python scripts/package_licenses.py $bundle
if ($LASTEXITCODE -ne 0) { throw "License staging failed" }
Compress-Archive -Path (Join-Path $bundle "*") -DestinationPath $archive -CompressionLevel Optimal -ErrorAction Stop
# Compress-Archive reports some entry failures without stopping: check the archive holds
# every file of the bundle before it ships.
Add-Type -AssemblyName System.IO.Compression.FileSystem
$expectedEntries = (Get-ChildItem -Recurse -File $bundle).Count
$zip = [System.IO.Compression.ZipFile]::OpenRead($archive)
try {
    $actualEntries = @($zip.Entries | Where-Object { -not $_.FullName.EndsWith('/') -and -not $_.FullName.EndsWith('\') }).Count
} finally {
    $zip.Dispose()
}
if ($actualEntries -ne $expectedEntries) {
    throw "The portable ZIP holds $actualEntries files, the bundle $expectedEntries"
}

if (-not $SkipMsi) {
    if (-not (Get-Command wix.exe -ErrorAction SilentlyContinue)) {
        throw "WiX 5 is required to build the MSI"
    }
    Remove-Item -Force -ErrorAction SilentlyContinue $installer
    wix build -arch x64 `
        -d "ProductVersion=$msiVersion" `
        -d "MarketingVersion=$marketingVersion" `
        -d "BuildNumber=$buildNumber" `
        -d "StageDir=$bundle" `
        -o $installer `
        (Join-Path $root "packaging\windows\processlama.wxs")
    wix msi validate $installer
}

Write-Output $archive
if (-not $SkipMsi) { Write-Output $installer }
