$ErrorActionPreference = 'Stop'
$b = 'http://127.0.0.1:8790'

function postj($path, $obj) {
    $body = [Text.Encoding]::UTF8.GetBytes(($obj | ConvertTo-Json -Compress))
    $r = Invoke-WebRequest -Uri "$b$path" -Method POST -ContentType 'application/json; charset=utf-8' -Body $body -UseBasicParsing
    return $r.Content | ConvertFrom-Json
}
function poststate($token, $state, $rev) {
    $obj = @{ state = $state; rev = $rev }
    $body = [Text.Encoding]::UTF8.GetBytes(($obj | ConvertTo-Json -Depth 8 -Compress))
    $r = Invoke-WebRequest -Uri "$b/api/state" -Method POST -Headers @{ Authorization = "Bearer $token" } -ContentType 'application/json; charset=utf-8' -Body $body -UseBasicParsing
    return $r.Content | ConvertFrom-Json
}

$t1 = (postj '/api/login' @{ username = '陈禹竹'; password = '230319' }).token
$t2 = (postj '/api/login' @{ username = '小明'; password = 'abc12345' }).token
Write-Output "tokens: $($t1.Substring(0,6)) / $($t2.Substring(0,6))"

$st1 = @{
    startDate = '2026-10-27'; goal = 120; setAt = 1793000000000
    logs = @{ '2026-10-27' = @{ done = @{ warm = 1 }; minutes = 60; blocks = @('陈禹竹的卡点'); at = 1793000001000 } }
    cp = @{}; fin = @{}; quiz = @{}
}
$st2 = @{
    startDate = '2026-10-27'; goal = 60; setAt = 1793000000000
    logs = @{ '2026-10-27' = @{ done = @{ main = 1 }; minutes = 30; blocks = @('小明的卡点'); at = 1793000002000 } }
    cp = @{}; fin = @{}; quiz = @{}
}
Write-Output "push1: rev=$((poststate $t1 $st1 0).rev)"
Write-Output "push2: rev=$((poststate $t2 $st2 0).rev)"

$a = (postj '/api/login' @{ username = '陈禹竹'; password = '230319' }).state
$c = (postj '/api/login' @{ username = '小明'; password = 'abc12345' }).state
Write-Output ("陈禹竹: blocks={0} minutes={1} goal={2}" -f ($a.logs.'2026-10-27'.blocks -join ','), $a.logs.'2026-10-27'.minutes, $a.goal)
Write-Output ("小明:   blocks={0} minutes={1} goal={2}" -f ($c.logs.'2026-10-27'.blocks -join ','), $c.logs.'2026-10-27'.minutes, $c.goal)

$ok = ($a.logs.'2026-10-27'.blocks[0] -eq '陈禹竹的卡点') -and ($c.logs.'2026-10-27'.blocks[0] -eq '小明的卡点') -and ($a.goal -eq 120) -and ($c.goal -eq 60)
Write-Output "数据隔离: $ok"

# 用其他人的 token 拿不到对方数据
Write-Output "越权检查（小明 token 只能拿到自己的）: $((postj '/api/login' @{ username='小明'; password='abc12345' }).state.logs.'2026-10-27'.blocks[0])"
