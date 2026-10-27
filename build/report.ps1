$root = 'D:\dsh-workspace\projects\ai-agent-plan-v2'
Get-ChildItem $root -Recurse -File |
  Where-Object { $_.FullName -notmatch '\\build\\out\\' -and $_.Extension -ne '.keystore' } |
  ForEach-Object { '{0,-58} {1,9:N1} KB' -f $_.FullName.Replace($root + '\', ''), ($_.Length / 1KB) }

'--- APK SHA256 ---'
(Get-FileHash "$root\dist\AgentStudy-2.0.apk" -Algorithm SHA256).Hash

'--- 服务状态 ---'
try { (Invoke-WebRequest 'http://127.0.0.1:8790/api/ping' -UseBasicParsing -TimeoutSec 5).Content } catch { 'down' }

'--- 局域网地址 ---'
Get-NetIPAddress -AddressFamily IPv4 | Where-Object { $_.IPAddress -match '^(192\.168|10\.|172\.)' } | ForEach-Object { $_.IPAddress }
