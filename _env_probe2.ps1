$ErrorActionPreference = 'Continue'
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$ErrorView = 'NormalView'

function T($n, $b) {
  $out = ''
  try { $out = (& $b 2>&1 | Out-String) } catch { $out = 'EXC: ' + $_.Exception.Message }
  $out = ($out -split "`r?`n" | Where-Object { $_.Trim() -ne '' }) -join ' | '
  if ($out.Length -gt 700) { $out = $out.Substring(0, 700) + ' ...<trunc>' }
  '--- ' + $n
  '    ' + $out
}

'===== A. gh / git install locations ====='
$cands = @(
  'C:\Program Files\GitHub CLI\gh.exe',
  'C:\Program Files (x86)\GitHub CLI\gh.exe',
  (Join-Path $env:LOCALAPPDATA 'Programs\GitHub CLI\gh.exe'),
  (Join-Path $env:LOCALAPPDATA 'GitHub CLI\gh.exe'),
  'C:\ProgramData\chocolatey\bin\gh.exe',
  (Join-Path $env:APPDATA 'npm\gh.cmd'),
  (Join-Path $env:APPDATA 'npm\gh.ps1')
)
foreach ($c in $cands) { '  {0,-6} {1}' -f (Test-Path $c), $c }

''
'===== B. real curl.exe (not the PS alias) ====='
foreach ($c in 'C:\Windows\System32\curl.exe','C:\Program Files\Git\mingw64\bin\curl.exe','C:\Program Files\Git\usr\bin\curl.exe') {
  if (Test-Path $c) { T ("curl -V  " + $c) { & $c -V } } else { '  MISSING ' + $c }
}

''
'===== C. OpenSSL-backed git? ====='
T 'git rev-parse --show-toplevel (non-repo)' { git rev-parse --show-toplevel }
T 'git --exec-path' { git --exec-path }
'  --- where is libcurl/openssl in Git dir ---'
Get-ChildItem 'C:\Program Files\Git\mingw64\bin' -ErrorAction SilentlyContinue |
  Where-Object { $_.Name -match 'curl|ssl|crypto|git-remote' } |
  ForEach-Object { '  ' + $_.Name + '  ' + $_.Length }
Get-ChildItem 'C:\Program Files\Git\mingw64\libexec\git-core' -ErrorAction SilentlyContinue |
  Where-Object { $_.Name -match 'remote-http|remote-curl' } |
  ForEach-Object { '  ' + $_.Name + '  ' + $_.Length }

''
'===== D. gh-like + git versions ====='
T 'git version --build-options' { git version --build-options }
T 'git config -l (all layers)' { git config -l }

''
'===== E. npm / pnpm / npx real behavior ====='
T 'pnpm -v' { pnpm -v }
T 'pnpm root -g' { pnpm root -g }
T 'pnpm store path' { pnpm store path }
$w = 'D:\radio\_npmpkg'
New-Item -ItemType Directory -Path $w -Force | Out-Null
Set-Content -LiteralPath (Join-Path $w 'package.json') -Value '{"name":"probe","version":"1.0.0","private":true}' -Encoding ascii
'Trying npm install (cache redirected to TEMP) in ' + $w
T 'npm install --dry-run' { npm install left-pad --dry-run --no-audit --no-fund --cache "$env:TEMP\npmcache" }
'Trying pnpm install in ' + $w
T 'pnpm install --lockfile-only' { pnpm install left-pad --lockfile-only }

''
'===== F. ssh with HOME redirected to workspace ====='
$fakeHome = 'D:\radio\_fakehome'
New-Item -ItemType Directory -Path $fakeHome -Force | Out-Null
T 'ssh-keygen into workspace' { ssh-keygen -t ed25519 -N '""' -f "$fakeHome\id_ed25519" -q }
'  files:'
Get-ChildItem $fakeHome -Force -ErrorAction SilentlyContinue | ForEach-Object { '  ' + $_.Name + '  ' + $_.Length }
T 'ssh -T with HOME override' {
  $env:HOME = $fakeHome
  ssh -o BatchMode=yes -o StrictHostKeyChecking=no -o UserKnownHostsFile="$fakeHome\known_hosts" -o ConnectTimeout=8 -T git@github.com
}

''
'===== G. git with HOME redirected (config writable?) ====='
$env:HOME = $fakeHome
T 'git config --global (writable?)' { git config --global user.name "probe"; git config --global --get user.name }
T 'git init in workspace' { git init D:\radio\_gitprobe }
T 'git commit smoke' {
  Set-Content -LiteralPath 'D:\radio\_gitprobe\a.txt' -Value 'hi' -Encoding ascii
  git -C D:\radio\_gitprobe add -A
  git -C D:\radio\_gitprobe -c user.name=p -c user.email=p@x commit -m probe
}

''
'===== H. node memory allocation (the 4MB trap) ====='
$f = 'D:\radio\_mem.mjs'
@'
for (const n of [1,4,16,64,256]) {
  try { const a = new Float32Array(n * 1024 * 1024 / 4); a[0]=1; console.log('ALLOC-OK   ' + n + 'MB'); }
  catch (e) { console.log('ALLOC-FAIL ' + n + 'MB | ' + e.name + ': ' + e.message); }
}
console.log('rss=' + Math.round(process.memoryUsage().rss/1048576) + 'MB');
'@ | Set-Content -LiteralPath $f -Encoding ascii
T 'node mem probe' { node $f }

''
'===== I. proxy detection ====='
T 'proxy port 7897' { (Test-NetConnection 127.0.0.1 -Port 7897 -InformationLevel Quiet) }
T 'proxy port 7890' { (Test-NetConnection 127.0.0.1 -Port 7890 -InformationLevel Quiet) }
T 'proxy port 10809' { (Test-NetConnection 127.0.0.1 -Port 10809 -InformationLevel Quiet) }
T 'proxy port 1080' { (Test-NetConnection 127.0.0.1 -Port 1080 -InformationLevel Quiet) }
T 'WinINET proxy' { Get-ItemProperty 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Internet Settings' | Select-Object ProxyEnable,ProxyServer,AutoConfigURL }
T 'proxy-ish processes' { Get-Process | Where-Object { $_.ProcessName -match 'clash|v2ray|xray|sing-box|verge|nekoray|winsw|surge|trojan|hiddify|mihomo' } | Select-Object ProcessName,Id }

''
'===== J. chocolatey real state ====='
T 'choco list (installed)' { choco list }
'Trying choco install gh --noop (no admin?)'
T 'choco install gh --noop' { choco install gh --noop --limit-output }

''
'===== K. workspace cleanup ====='
foreach ($d in '_npmpkg','_fakehome','_gitprobe','_mem.mjs','package.json','pnpm-lock.yaml') {
  $p = Join-Path 'D:\radio' $d
  if (Test-Path $p) { Remove-Item -LiteralPath $p -Recurse -Force -ErrorAction SilentlyContinue; '  removed ' + $d }
}
Get-ChildItem D:\radio -Force | ForEach-Object { '  LEFT: ' + $_.Name }
