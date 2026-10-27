# 把本项目推到 GitHub（交互式）
$ErrorActionPreference = 'Continue'
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
chcp 65001 > $null

$proj = $PSScriptRoot
Set-Location $proj

function Find-Git {
    $candidates = @(
        'C:\Program Files\Git\cmd\git.exe',
        'C:\Program Files (x86)\Git\cmd\git.exe',
        "$env:LOCALAPPDATA\Programs\Git\cmd\git.exe"
    )
    foreach ($c in $candidates) { if (Test-Path $c) { return $c } }
    $cmd = Get-Command git -ErrorAction SilentlyContinue
    if ($cmd) { return $cmd.Source }
    return $null
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
    Write-Host "    下载：https://registry.npmmirror.com/-/binary/git-for-windows/"
    Read-Host "按回车退出"
    exit 1
}
Write-Host "使用 git: $git" -ForegroundColor DarkGray

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
& $git commit -m "学习监督：网页版 + 账号体系" 2>&1 | ForEach-Object { "      $_" }

Write-Host "[3/4] 设置远程..." -ForegroundColor Cyan
& $git branch -M main 2>&1 | Out-Null
& $git remote remove origin 2>&1 | Out-Null
& $git remote add origin "https://github.com/$user/$repo.git"

Write-Host "[4/4] 推送（可能会弹浏览器让你登录 GitHub）..." -ForegroundColor Cyan
& $git push -u origin main

Write-Host ""
if ($LASTEXITCODE -ne 0) {
    Write-Host "[!] 推送失败，常见原因：" -ForegroundColor Red
    Write-Host "    1. 仓库还没在网页上创建（https://github.com/new）"
    Write-Host "    2. 仓库名写错了"
    Write-Host "    3. 浏览器登录时取消了授权"
    Write-Host ""
    Write-Host "    可以把这里的报错发给我。"
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
