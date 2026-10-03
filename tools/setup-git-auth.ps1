# Make git on this machine authenticate to GitHub automatically.
#
# WHY THIS EXISTS
#   This sandbox cannot spawn a subprocess with pipes, so every credential
#   helper (GCM, credential.helper=store) is unusable -- they all shell out
#   and die with "couldn't create signal pipe, Win32 error 5".
#   http.extraHeader also fails to carry the token here (Git for Windows
#   treats it as "no credentials" and asks for a username instead).
#
# THE FIX
#   Put the token in the URL, and use url.<tokenized>.insteadOf so that a
#   plain `git push` / `git fetch` gets the token injected automatically.
#
# WHY THE TOKEN IS NOT IN .git/config
#   It lives in .git/radio-credentials, pulled in via include.path.
#   .git/config stays clean; the secret is one file you can rotate or delete.
#
# Re-run this script after changing the token.
# NOTE: this file is deliberately ASCII-only. Windows PowerShell 5.1 reads
#       BOM-less UTF-8 .ps1 files as ANSI/GBK and mangles non-ASCII text.

$ErrorActionPreference = 'Stop'
$repoRoot  = 'D:\radio'
$tokenFile = Join-Path $repoRoot '.github-token'
$credFile  = Join-Path $repoRoot '.git\radio-credentials'
$ownerRepo = 'sblzc/workspace'

if (-not (Test-Path $tokenFile)) {
    throw "Missing $tokenFile -- write the token there first (one line, no quotes, no 'Bearer ' prefix)."
}
$tok = (Get-Content $tokenFile -Raw).Trim()
if ($tok -notmatch '^(github_pat_|ghp_)') {
    throw "That does not look like a GitHub token (expected a github_pat_ or ghp_ prefix)."
}

$withToken = "https://x-access-token:$tok@github.com/$ownerRepo.git"
$plain     = "https://github.com/$ownerRepo.git"

# 1. Write the credential file (tokenized insteadOf rule).
$content = "# Generated file. Do not edit by hand.`n" +
           "# Regenerate: powershell -NoProfile -ExecutionPolicy Bypass -File D:\radio\tools\setup-git-auth.ps1`n" +
           "[url `"$withToken`"]`n" +
           "`tinsteadOf = $plain`n"
[System.IO.File]::WriteAllText($credFile, $content, (New-Object System.Text.UTF8Encoding($false)))

Set-Location $repoRoot

# 2. Include it from .git/config (idempotent).
$existing = git config --local --get-all 'include.path' 2>$null
if ($existing) {
    $existing | Where-Object { $_ -like '*radio-credentials*' } | ForEach-Object {
        git config --local --unset 'include.path' $_ 2>$null
    }
}
git config --local --add 'include.path' $credFile

# 3. Pin the TLS backend. The system-level http.sslBackend=schannel does not
#    work here ("schannel: AcquireCredentialsHandle failed"). Use openssl.
#    The key is http.sslBackend -- NOT core.sslbackend.
git config --local 'http.sslBackend' 'openssl'

# 4. Repair branch tracking. An earlier `git push -u <url-with-token> main`
#    recorded the tokenized URL as the branch's tracking remote, which leaked
#    the token into .git/config. Point it back at the plain remote name.
git config --local 'branch.main.remote' 'origin'
git config --local 'branch.main.merge'  'refs/heads/main'

Write-Output "  wrote     $credFile"
Write-Output "  included  .git/config include.path"
Write-Output "  set       http.sslBackend = openssl"
Write-Output "  repaired  branch.main.remote = origin"
Write-Output ""
Write-Output "  verification (token redacted):"
git config --local --get-regexp 'url\..*insteadof' | ForEach-Object {
    '    ' + ($_ -replace 'x-access-token:[^@]+@', 'x-access-token:***@')
}
Write-Output "    include.path    = $(git config --local --get include.path)"
Write-Output "    http.sslBackend = $(git config --local --get http.sslBackend)"
