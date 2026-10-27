# 验证「临时磁盘 + 远端快照」：重启后数据还在
$ErrorActionPreference = 'Stop'
$proj = 'D:\dsh-workspace\projects\ai-agent-plan-v2'
$server = Join-Path $proj 'server'
$snap = Join-Path $proj 'build\snaptest'
$py = 'D:\dsh-workspace\tools\python312\python.exe'
$port = 8791
$base = "http://127.0.0.1:$port"

Remove-Item $snap -Recurse -Force -ErrorAction SilentlyContinue
Remove-Item "$server\data.db*" -Force -ErrorAction SilentlyContinue

function Start-TestServer {
    $env:SNAP_DIR = $snap
    $env:PORT = "$port"
    $p = Start-Process -FilePath $py -ArgumentList 'server.py' -WorkingDirectory $server -PassThru -WindowStyle Hidden
    $env:SNAP_DIR = ''
    $env:PORT = ''
    for ($i = 0; $i -lt 20; $i++) {
        Start-Sleep -Milliseconds 400
        try { Invoke-WebRequest "$base/api/ping" -UseBasicParsing -TimeoutSec 2 | Out-Null; return $p } catch {}
    }
    throw "服务没起来"
}

function Stop-TestServer($p) {
    try { Stop-Process -Id $p.Id -Force -ErrorAction SilentlyContinue } catch {}
    Start-Sleep -Milliseconds 600
    Get-Process python -ErrorAction SilentlyContinue | Where-Object { $_.Path -eq $py } | Stop-Process -Force -ErrorAction SilentlyContinue
}

Write-Output "== 1. 首次启动（模拟云上全新实例）=="
$p1 = Start-TestServer
Write-Output "   ping: $((Invoke-WebRequest "$base/api/ping" -UseBasicParsing).Content)"

Write-Output "== 2. 注册账号 + 写入进度 =="
$reg = Invoke-WebRequest -Uri "$base/api/register" -Method POST -ContentType 'application/json' `
    -Body ([Text.Encoding]::UTF8.GetBytes('{"username":"测试员","password":"test123456"}')) -UseBasicParsing
$j = $reg.Content | ConvertFrom-Json
Write-Output "   注册: $($j.username) token=$($j.token.Substring(0,6))..."
$st = @{
    startDate = '2026-10-27'; goal = 120; setAt = 1793000000000
    logs = @{ '2026-10-27' = @{ done = @{ warm = 1; main = 1 }; minutes = 100; blocks = @('云上测试卡点'); at = 1793000005000 } }
    cp = @{ D28 = @{ v = 'pass'; at = 1793000006000 } }; fin = @{}; quiz = @{}
}
$body = [Text.Encoding]::UTF8.GetBytes((@{ state = $st; rev = 0 } | ConvertTo-Json -Depth 8 -Compress))
Invoke-WebRequest -Uri "$base/api/state" -Method POST -Headers @{ Authorization = "Bearer $($j.token)" } `
    -ContentType 'application/json' -Body $body -UseBasicParsing | Out-Null
Write-Output "   进度已写入"

Write-Output "== 3. 等快照落盘（debounce 2s）=="
Start-Sleep -Seconds 4
$snapFile = Join-Path $snap 'studydb.json'
if (Test-Path $snapFile) {
    $size = [math]::Round((Get-Item $snapFile).Length / 1KB, 1)
    Write-Output "   快照已生成: $size KB"
} else {
    Write-Output "   快照没生成！"
}

Write-Output "== 4. 杀掉服务并删掉 data.db（模拟容器重启/换机器）=="
Stop-TestServer $p1
Remove-Item "$server\data.db*" -Force -ErrorAction SilentlyContinue
Write-Output "   data.db 存在: $(Test-Path "$server\data.db")"

Write-Output "== 5. 重新启动，看数据是否从快照恢复 =="
$p2 = Start-TestServer
$login = (Invoke-WebRequest -Uri "$base/api/login" -Method POST -ContentType 'application/json' `
    -Body ([Text.Encoding]::UTF8.GetBytes('{"username":"测试员","password":"test123456"}')) -UseBasicParsing).Content | ConvertFrom-Json
$blk = $login.state.logs.'2026-10-27'.blocks
$min = $login.state.logs.'2026-10-27'.minutes
$cp  = $login.state.cp.D28.v
Write-Output "   登录: $($login.username)"
Write-Output "   卡点: $($blk -join ',')  分钟: $min  检查点D28: $cp"
Write-Output ""
if ($blk -eq '云上测试卡点' -and $min -eq 100 -and $cp -eq 'pass') {
    Write-Output "结论: 通过 —— 换机器/重启后数据完整恢复"
} else {
    Write-Output "结论: 失败 —— 数据没恢复"
}

Stop-TestServer $p2
Remove-Item "$server\data.db*" -Force -ErrorAction SilentlyContinue
