$ErrorActionPreference = 'Continue'
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

function T($n, $b) {
  $out = ''
  try { $out = (& $b 2>&1 | Out-String) } catch { $out = "EXC: $($_.Exception.Message)" }
  $out = ($out -split "`r?`n" | Where-Object { $_.Trim() -ne '' }) -join ' | '
  "{0,-16}: {1}" -f $n, $out
}

'===== 1. TOOL PRESENCE / VERSION ====='
foreach ($c in 'git','gh','node','npm','npx','pnpm','yarn','bun','deno','python','py','pip','uv','uvx','pipx','scoop','choco','winget','ssh','ssh-keygen','curl','pwsh','code','wt','bash','wsl','docker','go','rustc','cargo','java','tar','7z','gpg') {
  T $c { Get-Command $c }
}

''
'===== 2. SANDBOX / ENV ====='
'USER         : ' + $env:USERNAME
'DSH_* vars   :'
Get-ChildItem env: | Where-Object { $_.Name -like 'DSH*' } | ForEach-Object { '  ' + $_.Name + ' = ' + $_.Value }
'NODE_OPTIONS = ' + $env:NODE_OPTIONS
'HTTP_PROXY   = ' + $env:HTTP_PROXY
'HTTPS_PROXY  = ' + $env:HTTPS_PROXY
'GIT_SSH      = ' + $env:GIT_SSH

''
'===== 3. IDENTITY / ELEVATION ====='
'name         : ' + [Security.Principal.WindowsIdentity]::GetCurrent().Name
try {
  $p = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
  'elevated     : ' + $p.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
} catch { 'elevated     : EXC ' + $_.Exception.Message }
T 'whoami /groups' { whoami /groups }

''
'===== 4. NODE / NPM ====='
T 'node -v' { node -v }
T 'npm prefix -g' { npm prefix -g }
T 'npm cache' { npm config get cache }
T 'npm registry' { npm config get registry }
T 'npm ping' { npm ping --loglevel=error }

''
'===== 5. GITHUB REACHABILITY (node fetch) ====='
$f = 'D:\radio\_fetch.mjs'
@'
const urls = [
  'https://api.github.com/zen',
  'https://github.com',
  'https://codeload.github.com',
  'https://raw.githubusercontent.com',
];
for (const u of urls) {
  const t0 = Date.now();
  try {
    const r = await fetch(u, { redirect: 'manual' });
    const body = (await r.text()).slice(0,60).replace(/\s+/g,' ');
    console.log('OK   ' + r.status + ' ' + (Date.now()-t0) + 'ms ' + u + ' | ' + body);
  } catch (e) {
    console.log('FAIL ' + u + ' | ' + e.name + ': ' + e.message + ' | cause: ' + (e.cause && (e.cause.code || e.cause.message)));
  }
}
'@ | Set-Content -LiteralPath $f -Encoding ascii
T 'node fetch' { node $f }
Remove-Item -LiteralPath $f -Force -ErrorAction SilentlyContinue

''
'===== 6. GIT CONFIG / CREDS / SSH ====='
T 'git --version' { git --version }
T 'git config --global -l' { git config -l --global }
T 'git proxy/ssl (system)' { git config --system --get-regexp 'proxy|schannel|ssl' }
T 'credential.helper' { git config --get-all credential.helper }
'--- .ssh contents ---'
$sshdir = Join-Path $env:USERPROFILE '.ssh'
if (Test-Path $sshdir) {
  Get-ChildItem $sshdir -Force | ForEach-Object { '  ' + $_.Name + '  ' + $_.Length }
} else { '  .ssh DOES NOT EXIST' }
'--- anonymous HTTPS clone test ---'
T 'git ls-remote' { git ls-remote https://github.com/git/git.git HEAD }
'--- ssh to github (BatchMode 5s) ---'
T 'ssh -T git@github.com' { ssh -o BatchMode=yes -o StrictHostKeyChecking=no -o ConnectTimeout=5 -T git@github.com }

''
'===== 7. LOCAL PROXY PORT ====='
T 'port 7897' { Test-NetConnection 127.0.0.1 -Port 7897 -InformationLevel Quiet }

''
'===== 8. PACKAGE MANAGERS (real execution) ====='
T 'winget --version' { winget --version }
T 'choco --version' { choco --version }
T 'scoop --version' { scoop --version }
T 'pip --version' { pip --version }

''
'===== 9. WRITE ABILITY ====='
$paths = @(
  'D:\radio',
  (Join-Path $env:APPDATA 'npm'),
  (Join-Path $env:APPDATA 'npm-cache'),
  (Join-Path $env:LOCALAPPDATA 'npm-cache'),
  (Join-Path $env:USERPROFILE '.dsh'),
  (Join-Path $env:USERPROFILE '.gitconfig'),
  (Join-Path $env:USERPROFILE '.ssh')
)
foreach ($d in $paths) {
  try {
    if (-not (Test-Path $d)) {
      New-Item -ItemType Directory -Path $d -Force -ErrorAction Stop | Out-Null
      Write-Output ('MKDIR-OK   ' + $d)
    }
    $t = Join-Path $d ('.wtest_' + [guid]::NewGuid().ToString('N').Substring(0,8))
    [System.IO.File]::WriteAllText($t, 'x')
    [System.IO.File]::Delete($t)
    Write-Output ('WRITE-OK   ' + $d)
  } catch {
    $msg = $_.Exception.GetType().Name + ': ' + $_.Exception.Message
    Write-Output ('WRITE-FAIL ' + $d + ' | ' + $msg)
  }
}

''
'===== 10. SYSTEM ====='
T 'PSVersion' { $PSVersionTable.PSVersion }
T 'D: volume' { Get-Volume -DriveLetter D }
T 'CIM OS' { Get-CimInstance Win32_OperatingSystem }
T 'TEMP' { $env:TEMP }
