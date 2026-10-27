$ErrorActionPreference = 'Continue'
$proj  = 'D:\dsh-workspace\projects\ai-agent-plan-v2'
$and   = Join-Path $proj 'android'
$out   = Join-Path $proj 'build\out'
$dist  = Join-Path $proj 'dist'
$sdk   = 'D:\dsh-workspace\tools\android-sdk'
$bt    = Join-Path $sdk 'build-tools\34.0.0'
$aj    = Join-Path $sdk 'platforms\android-34\android.jar'
$jdk   = (Get-ChildItem 'D:\dsh-workspace\tools' -Directory -Filter 'jdk-17*' | Select-Object -First 1).FullName

$env:JAVA_HOME = $jdk
$env:PATH = "$($jdk)\bin;$bt;$env:PATH"

New-Item -ItemType Directory -Force -Path $out, $dist | Out-Null
Remove-Item "$out\*" -Recurse -Force -ErrorAction SilentlyContinue
New-Item -ItemType Directory -Force -Path "$out\gen", "$out\classes", "$out\dex" | Out-Null

Write-Output "== 1/8 web/index.html"
$json = [System.IO.File]::ReadAllText("$proj\build\days.json", [System.Text.Encoding]::UTF8)
$tpl  = [System.IO.File]::ReadAllText("$proj\build\index.template.html", [System.Text.Encoding]::UTF8)
$html = $tpl.Replace('/*__DAYS__*/', $json)
New-Item -ItemType Directory -Force -Path "$proj\web" | Out-Null
[System.IO.File]::WriteAllText("$proj\web\index.html", $html, (New-Object System.Text.UTF8Encoding($false)))
Write-Output ("   {0:N0} KB" -f ((Get-Item "$proj\web\index.html").Length / 1KB))

Write-Output "== 2/8 assets"
New-Item -ItemType Directory -Force -Path "$and\assets" | Out-Null
Copy-Item "$proj\web\index.html" "$and\assets\index.html" -Force
New-Item -ItemType Directory -Force -Path "$proj\server\web" | Out-Null
Copy-Item "$proj\web\index.html" "$proj\server\web\index.html" -Force

Write-Output "== 3/8 aapt2 compile"
& "$bt\aapt2.exe" compile --dir "$and\res" -o "$out\res.zip"
if ($LASTEXITCODE -ne 0) { throw "aapt2 compile failed" }

Write-Output "== 4/8 aapt2 link"
& "$bt\aapt2.exe" link -o "$out\app-unaligned.apk" -I $aj --manifest "$and\AndroidManifest.xml" -R "$out\res.zip" --java "$out\gen" --auto-add-overlay -A "$and\assets"
if ($LASTEXITCODE -ne 0) { throw "aapt2 link failed" }

Write-Output "== 5/8 javac"
$srcs = @()
$srcs += (Get-ChildItem "$and\java" -Recurse -Filter *.java | ForEach-Object { $_.FullName })
$srcs += (Get-ChildItem "$out\gen" -Recurse -Filter *.java | ForEach-Object { $_.FullName })
Write-Output ("   sources: {0}" -f $srcs.Count)
$jargs = @('-source','8','-target','8','-nowarn','-encoding','UTF-8','-classpath',$aj,'-d',"$out\classes") + $srcs
& "$jdk\bin\javac.exe" @jargs
if ($LASTEXITCODE -ne 0) { throw "javac failed" }

Write-Output "== 6/8 d8"
$classes = Get-ChildItem "$out\classes" -Recurse -Filter *.class | ForEach-Object { $_.FullName }
& "$bt\d8.bat" --lib $aj --min-api 26 --output "$out\dex" @classes
if ($LASTEXITCODE -ne 0) { throw "d8 failed" }

Write-Output "== 7/8 dex + zipalign"
Add-Type -AssemblyName System.IO.Compression.FileSystem
$zip = [System.IO.Compression.ZipFile]::Open("$out\app-unaligned.apk", 'Update')
$e = $zip.GetEntry('classes.dex')
if ($e) { $e.Delete() }
[void][System.IO.Compression.ZipFileExtensions]::CreateEntryFromFile($zip, "$out\dex\classes.dex", 'classes.dex', [System.IO.Compression.CompressionLevel]::Optimal)
$zip.Dispose()

& "$bt\zipalign.exe" -f 4 "$out\app-unaligned.apk" "$out\app-aligned.apk"
if ($LASTEXITCODE -ne 0) { throw "zipalign failed" }

Write-Output "== 8/8 sign"
$ks = "$proj\build\ygbuddy.keystore"
if (-not (Test-Path $ks)) {
    & "$jdk\bin\keytool.exe" -genkeypair -v -keystore $ks -alias ygbuddy -keyalg RSA -keysize 2048 -validity 10000 -storepass ygbuddy2026 -keypass ygbuddy2026 -dname "CN=YGBuddy Study, OU=Dev, O=YGBuddy, L=Beijing, ST=Beijing, C=CN" | Out-Null
}
$apk = "$dist\AgentStudy-2.0.apk"
& "$bt\apksigner.bat" sign --ks $ks --ks-key-alias ygbuddy --ks-pass pass:ygbuddy2026 --key-pass pass:ygbuddy2026 --out $apk "$out\app-aligned.apk"
if ($LASTEXITCODE -ne 0) { throw "apksigner sign failed" }

Write-Output "== verify"
& "$bt\apksigner.bat" verify --print-certs $apk | Select-Object -First 5
& "$bt\aapt2.exe" dump badging $apk | Select-Object -First 3

Write-Output ("`nDONE: {0}  ({1:N2} MB)" -f $apk, ((Get-Item $apk).Length / 1MB))