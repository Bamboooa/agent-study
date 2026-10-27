# 卸载「开机/登录自动启动」的计划任务
$ErrorActionPreference = 'Continue'
$taskName = 'AgentStudyWeb'

schtasks /Delete /TN $taskName /F | Out-String | Write-Output

Get-Process pythonw -ErrorAction SilentlyContinue | ForEach-Object {
    $cmd = (Get-CimInstance Win32_Process -Filter "ProcessId = $($_.Id)").CommandLine
    if ($cmd -like '*server.py*') {
        Write-Output "停止进程 PID $($_.Id)"
        Stop-Process -Id $_.Id -Force
    }
}

Write-Output ""
Write-Output "已卸载。服务不再自动启动；需要时双击「启动服务.bat」手动运行。"
Write-Output "（数据不受影响，仍在 server\data.db）"
