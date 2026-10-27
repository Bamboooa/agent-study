# 解析学习计划 md，生成 189 天任务数据 JSON（PowerShell 5.1 兼容）
$ErrorActionPreference = 'Stop'
$src = 'D:\dsh-workspace\projects\ai-agent-plan-v2\AI-Agent-学习计划-v2-8个月版.md'
$out = 'D:\dsh-workspace\projects\ai-agent-plan-v2\build\days.json'
New-Item -ItemType Directory -Force -Path (Split-Path $out) | Out-Null

$lines = [System.IO.File]::ReadAllLines($src, [System.Text.Encoding]::UTF8)
$PIPE = [string][char]1

function Get-Phase([string]$id) {
  if ($id.StartsWith('W0-')) { return 'W0' }
  $n = [int]($id -replace 'D', '')
  if ($n -le 42) { return 'M1' }
  elseif ($n -le 70) { return 'M2' }
  elseif ($n -le 105) { return 'M3' }
  elseif ($n -le 133) { return 'M4' }
  elseif ($n -le 154) { return 'M5' }
  else { return 'M6' }
}

$phaseNames = @{
  'W0' = '启动周'; 'M1' = '生成能力'; 'M2' = '骨架'; 'M3' = '项目①连续运行';
  'M4' = '上线+试投'; 'M5' = '判断力'; 'M6' = '求职冲刺'
}

$days = New-Object System.Collections.ArrayList
$week = ''
foreach ($raw in $lines) {
  $l = $raw.TrimEnd()
  if ($l -match '^###\s+(W\d+)') { $week = $matches[1]; continue }
  if ($l -notmatch '^\|\s*(\*{0,2})(W0-\d+|D\d+(?:[–-]D\d+)?)\1\s*\|') { continue }

  $safe = $l -replace '\\\|', $PIPE
  $cells = $safe.Split('|')
  $dayCell = $cells[1].Trim().Trim('*').Trim()

  $rest = @()
  for ($i = 2; $i -lt $cells.Count; $i++) {
    $c = $cells[$i].Trim()
    if ($c -ne '') { $rest += ($c -replace [regex]::Escape($PIPE), '|') }
  }

  $dateStr = ''; $task = ''; $flag = ''
  if ($rest.Count -ge 3 -and $rest[0] -match '^\d{2}/\d{2}') {
    $dateStr = $rest[0]
    $task = $rest[1]
    $flag = ($rest[2..($rest.Count - 1)] -join ' ')
  } elseif ($rest.Count -ge 2) {
    $task = $rest[0]
    $flag = ($rest[1..($rest.Count - 1)] -join ' ')
  } elseif ($rest.Count -eq 1) {
    $task = $rest[0]
  }

  if ($dayCell -match '^D(\d+)[–-]D(\d+)$') {
    $a = [int]$matches[1]; $b = [int]$matches[2]
    for ($n = $a; $n -le $b; $n++) {
      [void]$days.Add(@{ id = "D$n"; week = $week; task = $task; flag = $flag })
    }
  } else {
    [void]$days.Add(@{ id = $dayCell; week = $week; task = $task; flag = $flag })
  }
}

$base = [datetime]'2026-11-02'
$w0base = [datetime]'2026-10-27'
foreach ($d in $days) {
  $d.phase = Get-Phase $d.id
  $d.phaseName = $phaseNames[$d.phase]
  if ($d.id.StartsWith('W0-')) {
    $k = [int]($d.id.Split('-')[1]) - 1
    $dt = $w0base.AddDays($k)
  } else {
    $k = [int]($d.id -replace 'D', '')
    $dt = $base.AddDays($k - 1)
  }
  $d.date = $dt.ToString('yyyy-MM-dd')
  $d.dow = [int]$dt.DayOfWeek
  $d.task = $d.task -replace '\*\*', ''
  $d.flag = $d.flag -replace '\*\*', ''
}

# 插入 11/01 缓冲日，保证「日历日 <-> 数组下标」严格一一对应
$buf = @{
  id='缓冲日'; week='W0'; date='2026-11-01'; dow=0; phase='W0'; phaseName='启动周';
  task='缓冲日：拿模型 API Key（存环境变量，不写进代码）、跑通第一次纯对话、配 PyPI 镜像、写 W0 复盘三段';
  flag=''
}
$pos = -1
for ($i = 0; $i -lt $days.Count; $i++) { if ($days[$i].id -eq 'W0-5') { $pos = $i; break } }
if ($pos -ge 0) { $days.Insert($pos + 1, $buf) }

$json = $days | ConvertTo-Json -Depth 4
[System.IO.File]::WriteAllText($out, $json, (New-Object System.Text.UTF8Encoding($false)))

"条目数: $($days.Count)"
"首条: $($days[0].id) $($days[0].date) $($days[0].task)"
"末条: $($days[$days.Count-1].id) $($days[$days.Count-1].date) $($days[$days.Count-1].task)"
$ids = $days | ForEach-Object { $_.id }
$missing = @()
foreach ($n in 1..189) { if ($ids -notcontains "D$n") { $missing += "D$n" } }
"缺失: $($missing -join ',')"
"文件字节: $((Get-Item $out).Length)"