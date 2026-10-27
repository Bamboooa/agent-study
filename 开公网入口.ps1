# 启动 Cloudflare 快速隧道，拿到一个公网地址
$ErrorActionPreference = 'Continue'
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
chcp 65001 > $null

$cf = 'D:\dsh-workspace\tools\cloudflared.exe'
$log = Join-Path $env:TEMP 'cloudflared-tunnel.log'

Write-Host "============================================" -ForegroundColor Cyan
Write-Host "  开一个公网入口（手机/外网可访问）" -ForegroundColor Cyan
Write-Host "============================================" -ForegroundColor Cyan
Write-Host ""

if (-not (Test-Path $cf)) {
    Write-Host "[!] 找不到 cloudflared.exe：$cf" -ForegroundColor Red
    Read-Host "按回车退出"; exit 1
}

# 1) 确保本机服务在跑
try {
    Invoke-WebRequest 'http://127.0.0.1:8790/api/ping' -UseBasicParsing -TimeoutSec 3 | Out-Null
    Write-Host "[1/2] 本机服务：运行中 (127.0.0.1:8790)" -ForegroundColor Green
} catch {
    Write-Host "[1/2] 本机服务没起来，正在启动..." -ForegroundColor Yellow
    schtasks /Run /TN AgentStudyWeb 2>$null | Out-Null
    Start-Sleep -Seconds 4
    try {
        Invoke-WebRequest 'http://127.0.0.1:8790/api/ping' -UseBasicParsing -TimeoutSec 5 | Out-Null
        Write-Host "      已启动" -ForegroundColor Green
    } catch {
        Write-Host "      [!] 还是起不来，先双击「安装开机自启.bat」" -ForegroundColor Red
        Read-Host "按回车退出"; exit 1
    }
}

# 2) 起隧道
Write-Host "[2/2] 正在建立隧道..." -ForegroundColor Yellow
Remove-Item $log -Force -ErrorAction SilentlyContinue
$proc = Start-Process -FilePath $cf `
    -ArgumentList 'tunnel', '--url', 'http://127.0.0.1:8790', '--no-autoupdate' `
    -RedirectStandardError $log -WindowStyle Hidden -PassThru

$url = $null
for ($i = 0; $i -lt 40; $i++) {
    Start-Sleep -Milliseconds 800
    if (Test-Path $log) {
        $txt = Get-Content $log -Raw -Encoding UTF8 -ErrorAction SilentlyContinue
        $m = [regex]::Match($txt, 'https://[a-z0-9-]+\.trycloudflare\.com')
        if ($m.Success) { $url = $m.Value; break }
    }
}

Write-Host ""
if ($url) {
    Write-Host "  公网地址：" -NoNewline
    Write-Host $url -ForegroundColor Green
    Write-Host ""
    Write-Host "  手机、平板、别人电脑都能打开这个地址" -ForegroundColor Cyan
    Write-Host "  账号：陈禹竹    密码：230319" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "  注意：电脑关机 / 关掉隧道，这个地址就失效。" -ForegroundColor DarkGray
    Write-Host "  每次重开地址都会变，重新跑一次本脚本即可。" -ForegroundColor DarkGray
    Write-Host ""
    Write-Host "  隧道进程 PID: $($proc.Id)   （要关掉就结束这个进程）" -ForegroundColor DarkGray
    Set-Clipboard -Value $url -ErrorAction SilentlyContinue
    Write-Host "  地址已复制到剪贴板" -ForegroundColor DarkGray
} else {
    Write-Host "[!] 没拿到地址，看日志：$log" -ForegroundColor Red
    Get-Content $log -Tail 20 -ErrorAction SilentlyContinue
}

Write-Host ""
Read-Host "按回车关闭本窗口（隧道继续在后台跑）"
