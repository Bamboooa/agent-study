# 安装「开机/登录自动启动」的计划任务
$ErrorActionPreference = 'Stop'
$proj = 'D:\dsh-workspace\projects\ai-agent-plan-v2'
$serverDir = Join-Path $proj 'server'
$taskName = 'AgentStudyWeb'

$pyw = "$env:LOCALAPPDATA\Programs\Python\Python312\pythonw.exe"
if (-not (Test-Path $pyw)) { $pyw = 'D:\dsh-workspace\tools\python312\pythonw.exe' }
if (-not (Test-Path $pyw)) { throw "找不到 pythonw.exe，先确认 Python 装好了" }

$sid = (New-Object System.Security.Principal.NTAccount($env:USERNAME)).Translate([System.Security.Principal.SecurityIdentifier]).Value
Write-Output "用户 SID: $sid"
Write-Output "解释器 : $pyw"
Write-Output "工作目录: $serverDir"

$xml = @"
<?xml version="1.0" encoding="UTF-16"?>
<Task version="1.2" xmlns="http://schemas.microsoft.com/windows/2004/02/mit/task">
  <RegistrationInfo>
    <Description>Agent 学习监督 · 本地网页服务（127.0.0.1:8790）</Description>
  </RegistrationInfo>
  <Triggers>
    <LogonTrigger>
      <Enabled>true</Enabled>
      <Delay>PT15S</Delay>
    </LogonTrigger>
    <TimeTrigger>
      <StartBoundary>2026-10-27T00:00:00</StartBoundary>
      <Repetition>
        <Interval>PT1M</Interval>
        <StopAtDurationEnd>false</StopAtDurationEnd>
      </Repetition>
      <Enabled>true</Enabled>
    </TimeTrigger>
  </Triggers>
  <Principals>
    <Principal id="Author">
      <UserId>$sid</UserId>
      <LogonType>InteractiveToken</LogonType>
      <RunLevel>LeastPrivilege</RunLevel>
    </Principal>
  </Principals>
  <Settings>
    <MultipleInstancesPolicy>IgnoreNew</MultipleInstancesPolicy>
    <DisallowStartIfOnBatteries>false</DisallowStartIfOnBatteries>
    <StopIfGoingOnBatteries>false</StopIfGoingOnBatteries>
    <AllowHardTerminate>true</AllowHardTerminate>
    <StartWhenAvailable>true</StartWhenAvailable>
    <RunOnlyIfNetworkAvailable>false</RunOnlyIfNetworkAvailable>
    <IdleSettings>
      <StopOnIdleEnd>false</StopOnIdleEnd>
      <RestartOnIdle>false</RestartOnIdle>
    </IdleSettings>
    <AllowStartOnDemand>true</AllowStartOnDemand>
    <Enabled>true</Enabled>
    <Hidden>false</Hidden>
    <RunOnlyIfIdle>false</RunOnlyIfIdle>
    <RestartOnFailure>
      <Interval>PT1M</Interval>
      <Count>99</Count>
    </RestartOnFailure>
    <ExecutionTimeLimit>PT0S</ExecutionTimeLimit>
    <Priority>7</Priority>
  </Settings>
  <Actions Context="Author">
    <Exec>
      <Command>$pyw</Command>
      <Arguments>server.py</Arguments>
      <WorkingDirectory>$serverDir</WorkingDirectory>
    </Exec>
  </Actions>
</Task>
"@

$xmlPath = Join-Path $proj 'build\AgentStudyWeb.task.xml'
[System.IO.File]::WriteAllText($xmlPath, $xml, [System.Text.Encoding]::Unicode)

schtasks /Create /TN $taskName /XML "$xmlPath" /F | Out-String | Write-Output
if ($LASTEXITCODE -ne 0) { throw "任务创建失败（可能需要以管理员身份运行）" }

schtasks /Run /TN $taskName | Out-String | Write-Output
Start-Sleep -Seconds 3

try {
    $r = Invoke-WebRequest 'http://127.0.0.1:8790/api/ping' -UseBasicParsing -TimeoutSec 5
    Write-Output "服务已就绪: $($r.Content)"
} catch {
    Write-Output "服务还没起来，看看 server\server.log"
}
