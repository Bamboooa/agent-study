$ErrorActionPreference = 'Continue'
$tools = 'D:\dsh-workspace\tools'
$sdk   = Join-Path $tools 'android-sdk'
New-Item -ItemType Directory -Force -Path $sdk | Out-Null
Add-Type -AssemblyName System.IO.Compression.FileSystem

$jdkDir = Get-ChildItem $tools -Directory -Filter 'jdk-17*' -ErrorAction SilentlyContinue | Select-Object -First 1
if (-not $jdkDir) {
  Write-Output "extracting jdk..."
  [IO.Compression.ZipFile]::ExtractToDirectory('D:\dsh-workspace\downloads\jdk17.zip', $tools)
  $jdkDir = Get-ChildItem $tools -Directory -Filter 'jdk-17*' | Select-Object -First 1
}
Write-Output "JDK: $($jdkDir.FullName)"

if (-not (Test-Path (Join-Path $sdk 'cmdline-tools\latest\bin\sdkmanager.bat'))) {
  Write-Output "extracting cmdline-tools..."
  [IO.Compression.ZipFile]::ExtractToDirectory('D:\dsh-workspace\downloads\cmdline-tools.zip', $sdk)
  if (Test-Path (Join-Path $sdk 'cmdline-tools\bin')) {
    Move-Item (Join-Path $sdk 'cmdline-tools') (Join-Path $sdk 'ct-tmp') -Force
    New-Item -ItemType Directory -Force -Path (Join-Path $sdk 'cmdline-tools') | Out-Null
    Move-Item (Join-Path $sdk 'ct-tmp') (Join-Path $sdk 'cmdline-tools\latest') -Force
  }
}

$env:JAVA_HOME = $jdkDir.FullName
$env:PATH = "$($jdkDir.FullName)\bin;$env:PATH"
$sdkman = Join-Path $sdk 'cmdline-tools\latest\bin\sdkmanager.bat'
Write-Output "sdkmanager: $sdkman  exists=$(Test-Path $sdkman)"

$yes = ("y`r`n" * 80)
Write-Output "=== accepting licenses ==="
$yes | & $sdkman --sdk_root=$sdk --licenses 2>&1 | Select-Object -Last 6

Write-Output "=== installing packages ==="
& $sdkman --sdk_root=$sdk "platform-tools" "platforms;android-34" "build-tools;34.0.0" 2>&1 | Select-Object -Last 20

Write-Output "=== result ==="
Get-ChildItem $sdk -Directory | ForEach-Object { "$($_.Name)" }
foreach ($p in @('build-tools\34.0.0\aapt2.exe','build-tools\34.0.0\d8.bat','build-tools\34.0.0\apksigner.bat','build-tools\34.0.0\zipalign.exe','platforms\android-34\android.jar')) {
  $f = Join-Path $sdk $p
  "$p -> $(Test-Path $f)"
}