$ErrorActionPreference = 'Continue'
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$ErrorView = 'NormalView'

$t = 'D:\radio\_crtest'
Remove-Item -LiteralPath $t -Recurse -Force -ErrorAction SilentlyContinue
New-Item -ItemType Directory -Path $t -Force | Out-Null

function Out($s) { Write-Output $s }

# --- write a REAL gitconfig with proper line endings ---
$cfg = "[credential]`r`n`thelper = manager`r`n[user]`r`n`tname = probe`r`n`temail = probe@example.com`r`n"
$cfgPath = Join-Path $t 'gitconfig'
[System.IO.File]::WriteAllText($cfgPath, $cfg, (New-Object System.Text.UTF8Encoding($false)))
Out '--- gitconfig written ---'
Get-Content $cfgPath | ForEach-Object { '    ' + $_ }
$env:GIT_CONFIG_GLOBAL = $cfgPath
$env:HOME = $t

Out '--- git config sanity ---'
git config --list --show-origin 2>&1 | Select-Object -First 8

Out ''
Out '--- git-remote-https + GCM with stdin closed, 20s timeout (job) ---'
$outFile = Join-Path $t 'out.txt'
$script = @"
`$env:GIT_CONFIG_GLOBAL = '$cfgPath'
`$env:GIT_TERMINAL_PROMPT = '0'
`$env:GCM_INTERACTIVE = 'never'
`$env:GCM_GUI_PROMPT = 'false'
git -c http.sslBackend=openssl ls-remote https://github.com/git/git.git HEAD 2>&1 | Out-File -LiteralPath '$outFile' -Encoding utf8
"@
$sb = [scriptblock]::Create($script)
$job = Start-Job -ScriptBlock $sb
$done = Wait-Job $job -Timeout 25
if ($done) {
  Out '  JOB COMPLETED (did not hang)'
  Get-Content $outFile -ErrorAction SilentlyContinue | Select-Object -First 6 | ForEach-Object { '    ' + $_ }
} else {
  Out '  *** TIMEOUT: git hung spawning GCM ***'
  Stop-Job $job
}
Remove-Job $job -Force -ErrorAction SilentlyContinue

Out ''
Out '--- does GCM ever try to open a window? check config ---'
git config --global --get-all credential.helper 2>&1
Out ('  GCM version: ' + (& 'C:\Program Files\Git\mingw64\bin\git-credential-manager.exe' --version 2>&1))

Out ''
Out '--- with credential.helper disabled entirely (anon HTTPS) ---'
Out "  (baseline above already proved anon works)"

Out ''
Out '--- cleanup ---'
Remove-Item -LiteralPath $t -Recurse -Force -ErrorAction SilentlyContinue
Remove-Item -LiteralPath 'D:\radio\.gitconfig' -Force -ErrorAction SilentlyContinue
Get-ChildItem D:\radio -Force | ForEach-Object { '  LEFT: ' + $_.Name }
