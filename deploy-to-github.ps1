# 把本项目推到 GitHub（交互式，自动处理代理与凭据）
$ErrorActionPreference = 'Continue'
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
chcp 65001 > $null

$proj = $PSScriptRoot
Set-Location $proj

function Find-Git {
    foreach ($c in @('C:\Program Files\Git\cmd\git.exe', 'C:\Program Files (x86)\Git\cmd\git.exe')) {
        if (Test-Path $c) { return $c }
    }
    $cmd = Get-Command git -ErrorAction SilentlyContinue
    if ($cmd) { return $cmd.Source }
    return $null
}

function Find-GCM {
    # 优先用 8.3 短路径，避免 "Program Files" 里的空格把 helper 命令截断
    foreach ($c in @(
            'C:/PROGRA~1/Git/ucrt64/bin/GIT-CR~2.EXE',
            'C:/PROGRA~1/Git/mingw64/bin/git-credential-manager.exe',
            'C:/PROGRA~1/Git/ucrt64/bin/git-credential-manager.exe')) {
        if (Test-Path $c) { return $c }
    }
    $cmd = Get-Command git-credential-manager -ErrorAction SilentlyContinue
    if ($cmd) { return $cmd.Source }
    return $null
}

function Get-SystemProxy {
    try {
        $k = Get-ItemProperty 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Internet Settings' -ErrorAction Stop
        if ($k.ProxyEnable -eq 1 -and $k.ProxyServer) {
            $p = "$($k.ProxyServer)"
            if ($p -notmatch '^https?://') { $p = 'http://' + $p }
            return $p
        }
    } catch {}
    return $null
}

function Test-GitHubTcp {
    try {
        $c = New-Object System.Net.Sockets.TcpClient
        $r = $c.BeginConnect('github.com', 443, $null, $null)
        $ok = $r.AsyncWaitHandle.WaitOne(3500)
        $c.Close()
        return $ok
    } catch { return $false }
}

Write-Host "============================================" -ForegroundColor Cyan
Write-Host "  把「学习监督」推到你的 GitHub 仓库" -ForegroundColor Cyan
Write-Host "  先在 https://github.com/new 建一个空仓库" -ForegroundColor Cyan
Write-Host "  （不要勾 Add a README）" -ForegroundColor Cyan
Write-Host "============================================" -ForegroundColor Cyan
Write-Host ""

$git = Find-Git
if (-not $git) {
    Write-Host "[!] 没找到 git.exe，先装 Git for Windows" -ForegroundColor Red
    Read-Host "按回车退出"
    exit 1
}
Write-Host "git      : $git" -ForegroundColor DarkGray

# ---- 凭据助手 ----
$gcm = Find-GCM
$currentHelper = (& $git config --global --get credential.helper) 2>$null
if ($gcm -and -not $currentHelper) {
    & $git config --global credential.helper $gcm
    Write-Host "凭据助手 : 已配置（首次推送会弹浏览器登录一次）" -ForegroundColor DarkGray
} elseif ($currentHelper) {
    Write-Host "凭据助手 : 已存在" -ForegroundColor DarkGray
} else {
    Write-Host "凭据助手 : 未找到 Git Credential Manager，推送时可能要手输密码" -ForegroundColor Yellow
}

# ---- 网络 ----
$env:GIT_TERMINAL_PROMPT = '0'
if (Test-GitHubTcp) {
    Write-Host "网络     : github.com 直连可用" -ForegroundColor DarkGray
} else {
    $proxy = Get-SystemProxy
    if ($proxy) {
        & $git config --global http.proxy $proxy
        & $git config --global https.proxy $proxy
        Write-Host "网络     : 直连不通，已改用系统代理 $proxy" -ForegroundColor Yellow
    } else {
        Write-Host "网络     : 连不上 github.com，也没有检测到系统代理" -ForegroundColor Red
        Write-Host "           先开代理（如 Clash）再运行本脚本" -ForegroundColor Red
    }
}
Write-Host ""

$user = (Read-Host "你的 GitHub 用户名").Trim()
if ([string]::IsNullOrWhiteSpace($user)) {
    Write-Host "[!] 用户名不能为空" -ForegroundColor Red
    Read-Host "按回车退出"
    exit 1
}

$repo = (Read-Host "仓库名（直接回车用 agent-study）").Trim()
if ([string]::IsNullOrWhiteSpace($repo)) { $repo = 'agent-study' }

$mail = (Read-Host "邮箱（直接回车用 $user@users.noreply.github.com）").Trim()
if ([string]::IsNullOrWhiteSpace($mail)) { $mail = "$user@users.noreply.github.com" }

Write-Host ""
Write-Host "将推送到: https://github.com/$user/$repo.git" -ForegroundColor Yellow
$ok = Read-Host "确认？(y/n)"
if ($ok -notin @('y', 'Y', '')) { Write-Host "已取消"; Read-Host "按回车退出"; exit 0 }

& $git config --global user.name $user
& $git config --global user.email $mail
& $git config --global init.defaultBranch main
& $git config --global core.quotepath false

if (-not (Test-Path (Join-Path $proj '.git'))) { & $git init | Out-Null }

Write-Host "`n[1/4] 暂存文件..." -ForegroundColor Cyan
& $git add -A

Write-Host "[2/4] 提交..." -ForegroundColor Cyan
& $git commit -m "学习监督：网页版 + 账号体系" 2>$null | Out-Null

Write-Host "[3/4] 设置远程..." -ForegroundColor Cyan
& $git branch -M main 2>$null | Out-Null
& $git remote remove origin 2>$null | Out-Null
& $git remote add origin "https://github.com/$user/$repo.git"

Write-Host "[4/4] 推送（第一次会弹浏览器让你登录 GitHub）..." -ForegroundColor Cyan
$out = & $git push -u origin main 2>&1
$out | ForEach-Object { "      $_" }

Write-Host ""
if ($LASTEXITCODE -ne 0) {
    $s = ($out | Out-String)
    Write-Host "[!] 推送失败" -ForegroundColor Red
    if ($s -match 'Could not connect|Connection was reset|Recv failure|timed out') {
        Write-Host "    原因：连不上 GitHub（网络问题）" -ForegroundColor Red
        Write-Host "    处理：开代理后重跑本脚本；或手动配置"
        Write-Host "          git config --global http.proxy http://127.0.0.1:你的端口"
    } elseif ($s -match 'Authentication failed|could not read Username|403') {
        Write-Host "    原因：GitHub 认证没通过" -ForegroundColor Red
        Write-Host "    处理：弹出的浏览器窗口里完成登录后，再重跑一次"
    } elseif ($s -match 'not found|404') {
        Write-Host "    原因：仓库不存在或用户名写错" -ForegroundColor Red
        Write-Host "    处理：确认 https://github.com/$user/$repo 能打开"
    } elseif ($s -match 'rejected|non-fast-forward') {
        Write-Host "    原因：远端仓库已有提交（建仓库时勾了 README）" -ForegroundColor Red
        Write-Host "    处理：git pull --rebase origin main 之后再推"
    } else {
        Write-Host "    把上面的报错发给我，我按具体错误给解法"
    }
} else {
    Write-Host "[OK] 推送完成！" -ForegroundColor Green
    Write-Host ""
    Write-Host "下一步（DEPLOY.md 第三节）：" -ForegroundColor Yellow
    Write-Host "  1. https://dashboard.render.com → New + → Web Service"
    Write-Host "  2. 选仓库 $repo → Start Command 填: python server/server.py"
    Write-Host "  3. 环境变量加 GIST_ID 和 GITHUB_TOKEN"
}
Write-Host ""
Read-Host "按回车退出"
