# 让这台机器上的 git 自动带上 GitHub 令牌
#
# 为什么需要这个：
#   本机不能 spawn 带管道的子进程，所以凭据帮助器（GCM / credential.helper=store）
#   全部不可用 —— 它们都要 spawn 子进程，报 "couldn't create signal pipe, Win32 error 5"。
#   同时 http.extraHeader 送 Authorization 头在本机也不生效（Git for Windows 下
#   会被当成「没有凭据」而转去询问用户名）。
#
# 解决办法：
#   把令牌嵌进 URL。用 url.<带令牌的 URL>.insteadOf 做改写，
#   这样 `git push` / `git fetch` 照常敲，令牌自动补上。
#
# 令牌为什么不在 .git/config 里：
#   写在 .git/radio-credentials 里，再由 .git/config 的 include 引进来。
#   .git/config 保持干净，令牌单独一个文件，方便单独换、单独删。
#
# 换令牌时只需要跑这一个脚本。

$ErrorActionPreference = 'Stop'
$repoRoot   = 'D:\radio'
$tokenFile  = Join-Path $repoRoot '.github-token'
$credFile   = Join-Path $repoRoot '.git\radio-credentials'
$ownerRepo  = 'sblzc/workspace'

if (-not (Test-Path $tokenFile)) {
    throw "找不到 $tokenFile —— 先把令牌写进去（一行，无引号，无 Bearer 前缀）"
}
$tok = (Get-Content $tokenFile -Raw).Trim()
if ($tok -notmatch '^(github_pat_|ghp_)') {
    throw "令牌看起来不像 GitHub 令牌（应以 github_pat_ 或 ghp_ 开头）"
}

$withToken = "https://x-access-token:$tok@github.com/$ownerRepo.git"
$plain     = "https://github.com/$ownerRepo.git"

$content = @"
# 自动生成，请勿手工编辑。重新生成：pwsh -File D:\radio\tools\setup-git-auth.ps1
[url "$withToken"]
	insteadOf = $plain
"@
[System.IO.File]::WriteAllText($credFile, $content, (New-Object System.Text.UTF8Encoding($false)))

# 把这份凭据引进来（幂等：先删同名 include 再加）
Set-Location $repoRoot
$existing = git config --local --get-all 'include.path' 2>$null
if ($existing) {
    $existing | Where-Object { $_ -like '*radio-credentials*' } | ForEach-Object {
        git config --local --unset 'include.path' $_ 2>$null
    }
}
git config --local --add 'include.path' "$credFile"

Write-Output "  已写入   $credFile   ($($content.Length) 字节)"
Write-Output "  已引入   .git/config 的 include.path"
Write-Output ""
Write-Output "  验证:"
git config --local --get-regexp 'url\..*insteadof' | ForEach-Object {
    # 不打印令牌
    '    ' + ($_ -replace 'x-access-token:[^@]+@', 'x-access-token:***@')
}
Write-Output "    include.path = $(git config --local --get include.path)"
