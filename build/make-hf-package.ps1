# 生成 Hugging Face Space 部署包（只挑运行必需的文件）
$ErrorActionPreference = 'Stop'
$proj = 'D:\dsh-workspace\projects\ai-agent-plan-v2'
$hf   = Join-Path $proj 'hf-space'

if (Test-Path $hf) { Remove-Item $hf -Recurse -Force }
New-Item -ItemType Directory -Force -Path (Join-Path $hf 'server\web') | Out-Null

Copy-Item (Join-Path $proj 'server\server.py')      (Join-Path $hf 'server\server.py')      -Force
Copy-Item (Join-Path $proj 'server\web\index.html') (Join-Path $hf 'server\web\index.html') -Force
Copy-Item (Join-Path $proj 'requirements.txt')      (Join-Path $hf 'requirements.txt')      -Force

# Dockerfile
$dockerfile = @'
FROM python:3.12-slim

WORKDIR /app
COPY . /app

# Hugging Face Space 固定监听 7860
ENV PORT=7860
ENV HOST=0.0.0.0
EXPOSE 7860

CMD ["python", "server/server.py"]
'@
[System.IO.File]::WriteAllText((Join-Path $hf 'Dockerfile'), $dockerfile, (New-Object System.Text.UTF8Encoding($false)))

# HF 需要 README 顶部的 YAML frontmatter
$readme = @'
---
title: Agent Study
emoji: 📘
colorFrom: green
colorTo: blue
sdk: docker
app_port: 7860
pinned: false
---

# Agent 学习监督

195 天 AI Agent 学习计划的打卡与监督工具。

- 登录后可以打卡、答题、看进度
- 数据存在私有 GitHub Gist（需要在 Space 设置里配置 GIST_ID 和 GITHUB_TOKEN）
'@
[System.IO.File]::WriteAllText((Join-Path $hf 'README.md'), $readme, (New-Object System.Text.UTF8Encoding($false)))

Write-Output "部署包已生成：$hf"
Get-ChildItem $hf -Recurse -File | ForEach-Object {
    "{0,-32} {1,8:N1} KB" -f $_.FullName.Replace($hf + '\', ''), ($_.Length / 1KB)
}
