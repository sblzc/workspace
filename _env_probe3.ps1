$ErrorActionPreference = 'Continue'
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$ErrorView = 'NormalView'

function T($n, $b) {
  $out = ''
  try { $out = (& $b 2>&1 | Out-String) } catch { $out = 'EXC: ' + $_.Exception.Message }
  $out = ($out -split "`r?`n" | Where-Object { $_.Trim() -ne '' }) -join ' | '
  if ($out.Length -gt 800) { $out = $out.Substring(0, 800) + ' ...<trunc>' }
  '--- ' + $n
  '    ' + $out
}

$GH = 'D:\radio\_ghprobe'
New-Item -ItemType Directory -Path $GH -Force | Out-Null

'===== 1. THE DECISIVE TEST: git HTTPS via OpenSSL backend ====='
T 'default backend (schannel)' { git ls-remote https://github.com/git/git.git HEAD }
T 'ABOVE is the baseline -> now the fix' { 'see next' }
T 'http.sslBackend=openssl' { git -c http.sslBackend=openssl ls-remote https://github.com/git/git.git HEAD }
T 'sslBackend=openssl + verbose' { git -c http.sslBackend=openssl -c http.sslVerify=true ls-remote https://github.com/octocat/Hello-World.git HEAD }
T 'official github repo test' { git -c http.sslBackend=openssl ls-remote https://github.com/github/gitignore.git HEAD }

''
'===== 2. does GIT_CONFIG_GLOBAL work (no HOME override)? ====='
$env:HOME = ''
$env:GIT_CONFIG_GLOBAL = "$GH\gitconfig"
T 'git config --global writes there?' { git config --global user.name 'probe2'; git config --global --list --show-origin }
'  file exists: ' + (Test-Path "$GH\gitconfig")

''
'===== 3. git clone for real (openssl backend) ====='
$env:GIT_CONFIG_GLOBAL = ''
T 'clone octocat/Hello-World' {
  git -c http.sslBackend=openssl -c core.autocrlf=false clone --depth 1 https://github.com/octocat/Hello-World.git "$GH\hello"
}
Get-ChildItem "$GH\hello" -Force -ErrorAction SilentlyContinue | ForEach-Object { '  ' + $_.Name }

''
'===== 4. SSH transport (proper, HOME redirected to workspace) ====='
T 'ssh-keygen ed25519' { ssh-keygen -t ed25519 -N '' -f "$GH\id_ed25519" -q -C 'probe@local' }
Get-ChildItem $GH -Filter 'id_*' | ForEach-Object { '  ' + $_.Name + '  ' + $_.Length }
T 'ssh-keyscan github.com' { ssh-keyscan -t rsa,ed25519 github.com 2>$null }
$env:HOME = $GH
T 'ssh -T github (with our key)' { ssh -o BatchMode=yes -o StrictHostKeyChecking=no -o UserKnownHostsFile="$GH\known_hosts" -o ConnectTimeout=8 -T git@github.com }
T 'git ls-remote via SSH url' { git ls-remote git@github.com:octocat/Hello-World.git HEAD }
'  known_hosts: ' + (Test-Path "$GH\known_hosts")

''
'===== 5. private key pub extraction (for user to paste into GitHub) ====='
T 'ssh-keygen -y -f private' { ssh-keygen -y -f "$GH\id_ed25519" }

''
'===== 6. proxy: real process env vs registry ====='
'  --- actual process env (HTTP_PROXY / HTTPS_PROXY / http_proxy / ALL_PROXY / NO_PROXY) ---'
foreach ($n in 'HTTP_PROXY','HTTPS_PROXY','http_proxy','https_proxy','ALL_PROXY','all_proxy','NO_PROXY','no_proxy') {
  $v = [Environment]::GetEnvironmentVariable($n)
  if ($null -ne $v) { '  ' + $n + ' = ' + $v } else { '  ' + $n + ' = <not set>' }
}
'  --- machine/user env (registry) ---'
foreach ($n in 'HTTP_PROXY','HTTPS_PROXY','ALL_PROXY') {
  '  ' + $n + ' user=' + [Environment]::GetEnvironmentVariable($n,'User') + ' machine=' + [Environment]::GetEnvironmentVariable($n,'Machine')
}
'  --- listening ports 7000-11000 ---'
T 'netstat proxy-ish' { netstat -ano | Select-String -Pattern ':(789|7890|7891|7897|1080|1087|10808|10809|8889|2080|9910)\s' }

''
'===== 7. pnpm config ====='
foreach ($p in 'D:\.npmrc', (Join-Path $env:USERPROFILE '.npmrc'), (Join-Path $env:LOCALAPPDATA 'pnpm\config\rc'), (Join-Path $env:APPDATA 'pnpm\rc')) {
  if (Test-Path $p) { '--- ' + $p; Get-Content $p -ErrorAction SilentlyContinue | ForEach-Object { '    ' + $_ } } else { '  MISSING ' + $p }
}
T 'pnpm config list' { pnpm config list }
T 'pnpm config get store-dir' { pnpm config get store-dir }
T 'pnpm config get global-bin-dir' { pnpm config get global-bin-dir }

''
'===== 8. can we install to a workspace-local prefix? ====='
$env:npm_config_prefix = "$GH\npmglobal"
T 'npm i -g gh-like to local prefix' { npm install -g --prefix "$GH\npmglobal" left-pad --cache "$env:TEMP\npmcache" --no-audit --no-fund }
Get-ChildItem "$GH\npmglobal" -Recurse -ErrorAction SilentlyContinue | Select-Object -First 12 | ForEach-Object { '  ' + $_.FullName }

''
'===== 9. cleanup ====='
Remove-Item -LiteralPath $GH -Recurse -Force -ErrorAction SilentlyContinue
Get-ChildItem D:\radio -Force | ForEach-Object { '  LEFT: ' + $_.Name }
