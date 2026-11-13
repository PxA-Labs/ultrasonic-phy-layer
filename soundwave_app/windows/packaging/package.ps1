# Package a Flutter Windows release directory as a portable zip and an MSIX,
# signing the binaries and the MSIX when a certificate is provided.
#
# Usage: package.ps1 -ReleaseDir <build\windows\x64\runner\Release>
#                    -Version <1.0.0> -OutDir <dir>
# Optional env: WINDOWS_CERT_PATH (.pfx), WINDOWS_CERT_PASSWORD,
#               MSIX_PUBLISHER (must match the certificate Subject).
param(
  [Parameter(Mandatory = $true)][string]$ReleaseDir,
  [Parameter(Mandatory = $true)][string]$Version,
  [Parameter(Mandatory = $true)][string]$OutDir
)
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$ReleaseDir = (Resolve-Path $ReleaseDir).Path
New-Item -ItemType Directory -Force -Path $OutDir | Out-Null
$OutDir = (Resolve-Path $OutDir).Path
$Here = $PSScriptRoot

foreach ($f in @('soundwave.exe', 'soundwave.dll', 'flutter_windows.dll', 'data\app.so')) {
  if (-not (Test-Path (Join-Path $ReleaseDir $f))) { throw "Missing $f in $ReleaseDir" }
}

# Windows SDK tools (signtool, makeappx) from the newest installed SDK.
$kits = 'C:\Program Files (x86)\Windows Kits\10\bin'
$sdkBin = Get-ChildItem $kits -Directory | Where-Object { $_.Name -match '^10\.' } |
  Sort-Object { [version]$_.Name } -Descending |
  Where-Object { Test-Path (Join-Path $_.FullName 'x64\makeappx.exe') } |
  Select-Object -First 1
if (-not $sdkBin) { throw "Windows SDK with makeappx.exe not found under $kits" }
$makeappx = Join-Path $sdkBin.FullName 'x64\makeappx.exe'
$signtool = Join-Path $sdkBin.FullName 'x64\signtool.exe'
Write-Host "Using Windows SDK $($sdkBin.Name)"

$certPath = $env:WINDOWS_CERT_PATH
$sign = $certPath -and (Test-Path $certPath)
function Invoke-Sign([string[]]$files) {
  & $signtool sign /fd SHA256 /f $certPath /p $env:WINDOWS_CERT_PASSWORD `
    /tr http://timestamp.digicert.com /td SHA256 $files
  if ($LASTEXITCODE -ne 0) { throw "signtool failed for $files" }
}

if ($sign) {
  Write-Host 'Signing executables'
  Invoke-Sign @((Join-Path $ReleaseDir 'soundwave.exe'), (Join-Path $ReleaseDir 'soundwave.dll'))
} else {
  Write-Host '::notice::No Windows signing certificate; producing unsigned zip and MSIX.'
}

# ---- portable zip ----------------------------------------------------------
$zip = Join-Path $OutDir "soundwave-$Version-windows-x64.zip"
if (Test-Path $zip) { Remove-Item $zip }
Compress-Archive -Path (Join-Path $ReleaseDir '*') -DestinationPath $zip

# ---- MSIX ------------------------------------------------------------------
$msixVersion = (($Version -split '[-+]')[0]) + '.0'
$publisher = if ($env:MSIX_PUBLISHER) { $env:MSIX_PUBLISHER } else { 'CN=PxA Labs' }
$layout = Join-Path ([IO.Path]::GetTempPath()) "soundwave-msix-$([guid]::NewGuid())"
New-Item -ItemType Directory -Path $layout | Out-Null
Copy-Item -Recurse -Path (Join-Path $ReleaseDir '*') -Destination $layout
Copy-Item -Recurse -Path (Join-Path $Here 'Assets') -Destination $layout
$manifest = (Get-Content -Raw (Join-Path $Here 'AppxManifest.xml.in')).
  Replace('@VERSION@', $msixVersion).
  Replace('@PUBLISHER@', [Security.SecurityElement]::Escape($publisher))
Set-Content -Path (Join-Path $layout 'AppxManifest.xml') -Value $manifest -Encoding utf8

$msix = Join-Path $OutDir "soundwave-$Version-windows-x64.msix"
& $makeappx pack /o /d $layout /p $msix
if ($LASTEXITCODE -ne 0) { throw 'makeappx pack failed' }
if ($sign) { Invoke-Sign @($msix) }
Remove-Item -Recurse -Force $layout

# ---- verify ----------------------------------------------------------------
Add-Type -AssemblyName System.IO.Compression.FileSystem
foreach ($pkg in @($zip, $msix)) {
  $entries = [IO.Compression.ZipFile]::OpenRead($pkg).Entries.FullName
  if (-not ($entries -contains 'soundwave.dll')) { throw "soundwave.dll missing from $pkg" }
  if (-not ($entries -contains 'soundwave.exe')) { throw "soundwave.exe missing from $pkg" }
  Write-Host "$pkg OK ($($entries.Count) entries)"
}
Get-ChildItem $OutDir | Format-Table Name, Length
