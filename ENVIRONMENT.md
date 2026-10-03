# 环境实测报告 — GitHub 协作前置条件

生成时间：本会话实测。所有结论均有命令与输出为证。
被测目录：`D:\radio`（空目录，尚未初始化 git）
执行身份：`ALAN_LIU\AlanL`，**Medium 完整性级别 + 未提权**（`whoami /groups` 显示
`BUILTIN\Administrators` 为 `Group used for deny only`）

---

## 0. 三条颠覆性结论（原 `~/.dsh/AGENTS.md` 记载有误）

### ① `npm` / `npx` **是能用的**，之前失败是配置问题

`AGENTS.md` 原文：「`npm` / `npx` 因 `EPERM`（沙箱拒绝写 npm-cache）不可用 → `npx -y <包>` 在本会话里必然失败」。

实测根因不是「沙箱禁止 npm」，而是 **npm 默认缓存目录恰好落在工作区之外**：

| 项 | 实测值 |
|---|---|
| `npm config get cache` | `C:\Users\AlanL\AppData\Local\npm-cache` ← 沙箱外 |
| `npm prefix -g` | `C:\Users\AlanL\AppData\Roaming\npm` ← 沙箱外 |
| 写 `AppData\Local\npm-cache` | `WRITE-FAIL ... Access to the path ... is denied` |
| 写 `AppData\Roaming\npm` | `WRITE-FAIL ... Access to the path ... is denied` |
| `$env:TEMP` | `C:\Users\AlanL\AppData\Local\Temp\dsh-qXQSCq` ← **可写** |

**把 cache 指到可写处，npm 立刻正常工作**：

```
npm install left-pad --dry-run --no-audit --no-fund --cache "$env:TEMP\npmcache"
→ add left-pad 1.3.0 | added 1 package in 2s

npm install -g --prefix "$WORKSPACE\npmglobal" left-pad --cache "$env:TEMP\npmcache" --no-audit --no-fund
→ added 1 package in 2s
→ D:\radio\_ghprobe\npmglobal\node_modules\left-pad\... （确实装进去了）
```

→ **修正**：本会话可以用 `npm install`（含全局装到工作区内 prefix）。
唯一不能做的是写用户级默认 prefix/cache，而那可以用参数绕开。

### ② Git 的 HTTPS **完全可用**，`http.sslBackend` 是开关

`AGENTS.md` 归咎于「受限令牌无法获取 Schannel 安全凭证」，这个机制描述**是对的**，
但漏掉了关键一点：**Git for Windows 自带 OpenSSL 后端，可以绕开 Schannel**。

`git version --build-options` 实测输出：

```
git version 2.55.0.windows.5
libcurl: 8.21.0
OpenSSL: OpenSSL 3.5.7 9 Jun 2026      ← 编译时真的链了 OpenSSL
shell-path: D:/git-sdk-64-build-installers/usr/bin/sh
```

问题出在**系统级 git 配置强制选了 Schannel**：

```
git config --system --get-regexp 'proxy|schannel|ssl'
→ http.sslbackend schannel
```

**对照实验（同一条命令，只差一个开关）**：

```
$ git ls-remote https://github.com/git/git.git HEAD
fatal: unable to access '...': schannel: AcquireCredentialsHandle failed:
SEC_E_NO_CREDENTIALS (0x8009030e)

$ git -c http.sslBackend=openssl ls-remote https://github.com/git/git.git HEAD
c46c1e37724f0478939de636ab8ea5a89086d532        HEAD      ← 成功

$ git -c http.sslBackend=openssl ls-remote https://github.com/octocat/Hello-World.git HEAD
7fd1a60b01f91b314f59955a4e4d4e80d8edf11d        HEAD      ← 成功

$ git -c http.sslBackend=openssl clone --depth 1 https://github.com/octocat/Hello-World.git ...
Cloning into 'D:\radio\_ghprobe\hello'...
→ README 文件真实落地，克隆成功
```

→ **结论：沙箱内 git 可以 clone / fetch / pull / push over HTTPS。**
代价只是要么每次带 `-c http.sslBackend=openssl`，要么写进 git 配置。

顺带确认了机制边界，解释了为什么 HTTPS 行而 SSH 不行：
`AGENTS.md` 说「进程不能开命名管道」，HTTPS 走 socket 所以没事，
SSH 和 SCManager 走命名管道 / RPC 所以被拦。

### ③ 系统代理 `127.0.0.1:7897` **当前没有在运行**

`AGENTS.md` 记载「实测 CONNECT 隧道与明文 HTTP 均可用」。实测现在：

```
Test-NetConnection 127.0.0.1 -Port 7897  → False
Test-NetConnection 127.0.0.1 -Port 7890  → False
Test-NetConnection 127.0.0.1 -Port 10809 → False
Test-NetConnection 127.0.0.1 -Port 1080  → False
netstat -ano | Select-String ':(789|7890|7897|1080|1087|10808|10809|8889|2080|9910)\s'  → 空
Get-Process | ? { $_.ProcessName -match 'clash|v2ray|xray|sing-box|verge|nekoray|surge|trojan|hiddify|mihomo' }  → 空
```

注册表里有残留但**已被禁用**：

```
HKCU:\...\Internet Settings
  ProxyEnable   = 0
  ProxyServer   = 127.0.0.1:7897
  AutoConfigURL = (空)
```

进程环境变量全部未设置：`HTTP_PROXY` `HTTPS_PROXY` `ALL_PROXY`（大小写皆无）。

→ **结论：当前网络是「裸连」，没有代理在起作用 —— 而 GitHub 裸连可用**（见下节）。
`AGENTS.md` 该条应改成「曾配置过 7897，但当前未运行；且 GitHub 直连可达」。

---

## 1. GitHub 网络可达性（直连，无代理）

用 Node 的 `fetch`（自带 OpenSSL，不受 Schannel 限制）：

```
OK   200 660ms https://api.github.com/zen        | Encourage flow.
OK   200 525ms https://github.com                | <!DOCTYPE html><html lang="en" data-color-mode=...
OK   301 682ms https://codeload.github.com
OK   301 525ms https://raw.githubusercontent.com
```

四项全部可达，延迟 0.5–0.7s。**说明 GitHub 没有被墙，不需要代理或 VPN。**

`api.github.com/zen` 返回 `200` 且带真实内容，证明 HTTPS 握手与 HTTP 层都正常。

---

## 2. 工具清单

### 已装且可用

| 工具 | 版本 | 路径 |
|---|---|---|
| git | 2.55.0.windows.5（libcurl 8.21.0 + OpenSSL 3.5.7） | `C:\Program Files\Git\cmd\git.exe` |
| node | v24.21.0 | `C:\Program Files\nodejs\node.exe` |
| npm | 可用（需指定 cache） | `C:\Program Files\nodejs\npm.ps1` |
| pnpm | 12.6.0（受限，见下） | `C:\Users\AlanL\AppData\Roaming\npm\pnpm.ps1` |
| python | 3.14.7 | `C:\Python314\python.exe` |
| pip | 26.2.1 | `C:\Python314\Scripts\pip.exe` |
| OpenSSH | 9.5.5.1（`ssh` / `ssh-keygen`，沙箱内受限） | `C:\Windows\System32\OpenSSH\` |
| chocolatey | 2.7.4（**装包需提权**） | `C:\ProgramData\chocolatey\bin\choco.exe` |
| winget | 存在但命令无输出 | WindowsApps |
| VS Code | 已装（`code.cmd`） | `%LOCALAPPDATA%\Programs\...` |
| Windows Terminal | 已装（`wt.exe`） | `%LOCALAPPDATA%\Microsoft\...` |
| git-lfs | 已配置 filter（随 Git 装） | — |

### 未装

`gh`(GitHub CLI)、`yarn`、`bun`、`deno`、`uv`、`uvx`、`pipx`、`scoop`、
`bash`、`docker`、`go`、`rustc`、`cargo`、`java`、`7z`、`gpg`、`pwsh`

`gh` 已确认在常见安装位置全都不存在：

```
False  C:\Program Files\GitHub CLI\gh.exe
False  C:\Program Files (x86)\GitHub CLI\gh.exe
False  %LOCALAPPDATA%\Programs\GitHub CLI\gh.exe
False  C:\ProgramData\chocolatey\bin\gh.exe
False  %APPDATA%\npm\gh.cmd
```

---

## 3. 沙箱边界（精确版）

### 可写

```
WRITE-OK   D:\radio
WRITE-OK   C:\Users\AlanL\AppData\Local\Temp\dsh-qXQSCq   （TEMP 被重定向到会话临时目录）
```

### 不可写

```
WRITE-FAIL C:\Users\AlanL\AppData\Roaming\npm          | Access to the path ... is denied
WRITE-FAIL C:\Users\AlanL\AppData\Roaming\npm-cache    | UnauthorizedAccessException
WRITE-FAIL C:\Users\AlanL\AppData\Local\npm-cache      | Access to the path ... is denied
WRITE-FAIL C:\Users\AlanL\.dsh                         | Access to the path ... is denied
WRITE-FAIL C:\Users\AlanL\.gitconfig                   | UnauthorizedAccessException
WRITE-FAIL C:\Users\AlanL\.ssh                         | UnauthorizedAccessException
```

也就是说：**`%TEMP%` + 工作区 = 仅有的两个可写区域。**

### 绕过技巧（已验证）

**`HOME` / `GIT_CONFIG_GLOBAL` 重定向可以让 git 在沙箱内拥有自己的配置**：

```powershell
$env:GIT_CONFIG_GLOBAL = "D:\radio\.gitconfig"
git config --global user.name 'probe2'
git config --global --list --show-origin
→ file:"D:\\radio\\_ghprobe\\gitconfig"   user.name=probe2     ← 写入工作区成功
```

`git init` + `git commit` 在沙箱内也完全正常：

```
git init D:\radio\_gitprobe        → Initialized empty Git repository
git commit -m probe                → [master (root-commit) 839b0e0] probe / 1 file changed
```

---

## 4. SSH 通道：沙箱内不可用（重要限制）

`ssh` 本体能跑，`ssh -T git@github.com` 也能完成 TCP + 握手 + 密钥交换：

```
ssh -o BatchMode=yes -o StrictHostKeyChecking=no \
    -o UserKnownHostsFile="$GH\known_hosts" -o ConnectTimeout=8 -T git@github.com
→ Warning: Permanently added 'github.com' (ED25519) to the list of known hosts.
→ git@github.com: Permission denied (publickey).
```

注意 `Permission denied (publickey)` 是**预期结果**（没配密钥），
`Permanently added 'github.com'` 才是有价值的证据 —— **说明网络通、SSH 协议栈正常**。

但 git 自己调 SSH 时崩了：

```
git ls-remote git@github.com:octocat/Hello-World.git HEAD
→       0 [main] ssh (21852) C:\Program Files\Git\usr\bin\ssh.exe:
        *** fatal error - couldn't create signal pipe, Win32 error 5
→ fatal: Could not read from remote repository.
```

这正是 `AGENTS.md` 记载的「进程不能开命名管道」在 SSH 上的体现。此外：

- `.ssh` 无法创建（沙箱拒绝写 `C:\Users\AlanL\.ssh`）
- `ssh-keygen` 写私钥到工作区**可以**，但写 `.pub` 时报
  `Unable to save public key: Bad file descriptor`（公钥文件落地为 0 字节）

**结论：我在沙箱内只能用 HTTPS 通道。SSH 需要用 `gh` 或你在普通 shell 里配。**

---

## 5. pnpm 的精确状态

`pnpm 12.6.0` 存在，但连 `pnpm root -g` 都失败：

```
Error: failed to create the global bin directory
  C:\Users\AlanL\AppData\Local\pnpm\bin: 拒绝访问。 (os error 5)
```

`pnpm store path` 会跟着 cwd 走（`D:\radio\node_modules\.pnpm-store\v11`，这倒是在工作区内），
但 `pnpm install` 仍要写沙箱外路径：

```
Error: ERR_PNPM_STORE_DIR_OPEN_OPERATION_LOCK
  Failed to open the store operation lock at
  "C:\Users\AlanL\AppData\Local\pnpm-store-operation-locks\all-stores.lock": 拒绝访问。 (os error 5)
```

没有 `.npmrc`（`D:\.npmrc`、`~\.npmrc`、`pnpm\config\rc`、`pnpm\rc` 全都不存在）。
`pnpm config list` 显示 registry 是标准 npmjs。

→ **建议本会话用 `npm` 而不是 `pnpm`。**

---

## 6. 关于 `AGENTS.md` 那条「Node 分配大数组会失败」的复核

原文称「约 4MB 的分配就可能触发 `RangeError: Array buffer allocation failed`」。
本次实测**无法复现**：

```
ALLOC-OK   1MB
ALLOC-OK   4MB
ALLOC-OK   16MB
ALLOC-OK   64MB
ALLOC-OK   256MB
rss=54MB
```

256MB 单次分配顺利通过。该现象很可能依赖当时的常驻内存压力，
不是稳定可复现的约束 —— 但「报错会伪装成卡住」的**教训仍然成立**，保留。

---

## 6b. 凭据与 pip（后补实测）

### Git Credential Manager 2.9.1 **存在且能启动**

```
C:\Program Files\Git\mingw64\bin\git-credential-manager.exe   → True
git-credential-manager.exe --version  → 2.9.1+6760f0ef069c994aa2bb1d703fb374986ee82a3e
```

**更正一次误判**：先前有一次 `git credential-manager get` 命令挂满 240s 超时，
我一度以为「GCM 在沙箱内挂死」。复核发现**那次超时是我自己的脚本错误**——
写 `.gitconfig` 时用了字面 `\n` 而非真实换行，产生
`fatal: bad config line 1 in file D:\radio\.gitconfig`，
加上管道组合导致 stdin 无法关闭。用正确的 CRLF 配置文件重测：

- `GCM --version` 正常返回
- 跑 `git ls-remote` 的 Job **在 25s 内正常结束，没有挂起**
- 该次失败原因是网络抖动（见下），不是 GCM

**结论：`credential.helper=manager` 可用，没被沙箱拦。**
（但仍建议推送走 PAT，避免 GCM 弹 GUI 窗口的可能。）

### 网络有抖动 —— 不是每次都通

同一天内两次 `ls-remote` 结果相反：

```
第一次  git -c http.sslBackend=openssl ls-remote https://github.com/git/git.git HEAD
        → c46c1e37724f0478939de636ab8ea5a89086d532   HEAD        ✅

第二次  （25s 超时保护下运行）
        → fatal: unable to access '...': Failed to connect to github.com:443
          after 21129 ms: Could not connect to server          ❌
```

**这是本次探测最重要的不确定性**：GitHub 对这台机器**不是稳定可达**，
存在约 20 秒级的连接失败。任何「一次就成功」的结论都不成立，
所有联网操作都必须带超时与重试。

### `pip` 在沙箱内**不可用**

```
pip install --target D:\radio\_piptest --no-input --quiet uv
→ ERROR: Could not install packages due to an OSError: [Errno 13] Permission denied:
  'C:\Users\AlanL\AppData\Local\Temp\dsh-qXQSCq\pip-unpack-0b6_twfe\uv-0.12.22-py3-none-win_amd64.whl.metadata'
→ [sandbox: file access denied under workspace-write mode]
```

**`$env:TEMP` 看起来在工作区内，其实不是。** 它指向
`C:\Users\AlanL\AppData\Local\Temp\dsh-qXQSCq`，是 DSH 给本会话的专用临时区，
**只允许某些操作写，pip 的解包流程写不了**。

→ 我**不能**用 pip 自行安装 `uv` / `pipx`。

### PyPI 上的 `gh` 不是 GitHub CLI

```
PyPI OK   gh             version=0.0.4    （空描述，占位包）
PyPI OK   gh-cli         version=0.0.0    （占位包）
PyPI OK   github-cli     version=1.0.0    | A command-line interface to the GitHub Issues API v2.
                       ↑ 不是 GitHub 官方的 gh，是另一个项目
PyPI OK   uv             version=0.12.22  | An extremely fast Python package and project manager
PyPI OK   pipx           version=1.17.10
```

→ 装 `gh` **只能**从 GitHub release 下载 zip（Node fetch 已验证可达），
不存在 pip / npm 的可用捷径。

---

## 7. npm 上的 GitHub MCP server 现状（实测 registry）

| 包名 | 最新版 | 状态 |
|---|---|---|
| `@modelcontextprotocol/server-github` | 2025.4.8 | **已废弃**：`Package no longer supported.` 依赖 7 个包 |
| `@github/github-mcp-server` | — | **HTTP 404，npm 上不存在** |
| `github-mcp-server` | 1.8.7 | 存活，但依赖 `@modelcontextprotocol/inspector` + `express` 等 4 个包 |
| `@modelcontextprotocol/server-git` | — | **HTTP 404** |
| `mcp-server-git` | 0.0.1-security | **security holding package**（空壳） |
| `@modelcontextprotocol/sdk` | 1.32.0 | 官方 SDK，17 个依赖，`engines: node>=18` |

**GitHub 官方 MCP server 是 Go 二进制**（`github/github-mcp-server`，
`pkg.go.dev/github.com/github/github-mcp-server@v1.10.1`），
不在 npm 上，官方推荐的远程端点则绑定 Copilot 账号体系。

→ 本机没有 Go、没有 Docker、且 `gh` 未装。**只能自己写一个零依赖的 Node MCP server。**

---

# 连接器可行性实测（第二轮，2026-02-06 之后）

这一轮回答的是：**「GitHub 连接器」到底哪条路走得通。**

---

## 11. 推送通道实测（第三轮，决定性）

### 结论：`github.com` 被间歇阻断，`api.github.com` 完全正常

同一时刻交替探测 8 轮：

```
github.com            ok=3 fail=5    ← 成功时仅 264ms，失败时卡满 ~10.7 秒
codeload.github.com   ok=8 fail=0    ← 100% 可靠，平均 559ms
api.github.com        ok=8 fail=0    ← 平均约 500ms
```

失败率约 **62%**。失败形态统一是 10-11 秒后 `TypeError`（Node）/ `Failed to connect
to github.com:443 after 21087 ms`（git）。**重试是有效的**，因为成功态只要 264ms。

### 关键陷阱：`http.extraHeader` 传令牌不生效

```
git -c "http.extraHeader=Authorization: Bearer <PAT>" push ...
→ 前 2 次:  Failed to connect to github.com:443 after 21087 ms
→ 第 3 次起: fatal: could not read Username for 'https://github.com'
             : terminal prompts disabled
```

**这条错误看起来像权限问题，实际是认证头根本没送出去。** 不要被它误导 ——
判断权限要对 `GET /api.github.com/repos/...` 看 `permissions` 字段。

### 可用写法：令牌嵌进 URL

```powershell
$url = "https://x-access-token:$tok@github.com/OWNER/REPO.git"
git -c http.sslBackend=openssl -c credential.helper= push -u $url main
→ ls-remote  attempt 1: OK
→ push       attempt 1: PUSH OK
```

**一次成功**，不需要重试。注意 `credential.helper=` 要显式置空，否则会去 spawn
那个必然失败的帮助器（见第 8 节）。

### 权限诊断的正确方法

```json
GET /repos/sblzc/workspace  →  200
  "permissions": {"admin":true,"maintain":true,"push":true,"triage":true,"pull":true}
```

细粒度令牌只要把该仓库勾进 **Selected repositories**，`push` 权限就是现成的。
不需要 `administration`（那只用于**建**仓库）。

### 建仓库必须走网页或账号级权限

`POST /user/repos` 用细粒度令牌返回 `403 Resource not accessible by personal access
token`。而且有个**先有鸡还是先有蛋**的问题：令牌的 Selected repositories 列表
只列出**已存在**的仓库，所以必须先建仓库，才能把仓库授权给令牌。
→ 建仓库请走网页，或用带账号级 `administration` 权限的令牌。

---

## 8. 决定性坏消息：沙箱内无法 spawn 带管道的子进程

```
node -e "spawn(node, ['-e',...], {stdio:['pipe','pipe','pipe']})"
→ Error: spawn EPERM  (errno -4048, syscall 'spawn')

node -e "spawn(node, ['-e','process.exit(7)'], {stdio:'ignore'})"
→ stdio:ignore close exit= 7        ← 不带管道就能跑
```

同样地，任何会让 git 去 spawn 凭据帮助器的操作都会炸：

```
"protocol=https`nhost=github.com`n" | git credential fill
→ 0 [main] sh (19968) C:\Program Files\Git\usr\bin\sh.exe:
  *** fatal error - couldn't create signal pipe, Win32 error 5
→ fatal: could not read Username for 'https://github.com': terminal prompts disabled
```

用文件重定向代替 PowerShell 管道**一样会炸**，所以触发点不是管道本身，
而是 **git 需要凭据 → spawn 帮助器 → 帮助器是 `sh.exe` → 信号管道被沙箱拒绝**。
这跟之前 SSH 报的 `couldn't create signal pipe, Win32 error 5` 是**同一个根因**。

### 直接后果（两条硬约束）

| 形态 | 结论 |
|---|---|
| MCP `transport: stdio` | **不可用** —— MCP 客户端要用管道跟子进程说话，正是被禁的那件事 |
| `credential.helper`（含 GCM、含 `store`） | **只会挂死/报错**，因为 git 通过 `sh.exe` 调它 |

### 对应的两条绕法（都已实测到「不再报管道错误」这一步）

- **绕开 stdio**：改用 `transport: streamable-http`。
  实测后台 Node HTTP 服务能被**独立进程**访问：
  `PROBE-SERVER listening on http://127.0.0.1:7391`，
  另一个 pwsh 进程 `Invoke-WebRequest POST /mcp-probe` → `OK 200 {"ok":true,...}`。
  → **本机 → DSH 这条回环链路是通的。**
- **绕开凭据帮助器**：把 PAT 直接写进 remote URL。
  实测 `git push https://fakeuser:faketoken@github.com/...` **没有出现 sh.exe 管道错误**，
  而是正常走到网络层（`Failed to connect to github.com:443 after 21185 ms`）。
  → 管道问题被绕开了，剩下的纯粹是网络抖动 + 凭据真假。

## 9. 好消息：官方 GitHub MCP 远程端点从本机可达，且吃普通 PAT

```
POST https://api.githubcopilot.com/mcp      （无 token）
→ 401  1237ms
→ www-authenticate: Bearer error="invalid_request",
   error_description="No access token was provided in this request",
   resource_metadata="https://api.githubcopilot.com/.well-known/oauth-protected-resource/mcp"
→ body: bad request: missing required Authorization header
```

**401 + "missing Authorization header" 正是想要的结果**：端点活着、协议对、只差 token。
GitHub 官方文档给的接法（[install-claude.md](https://github.com/github/github-mcp-server/blob/main/docs/installation-guides/install-claude.md)、
[GitHub Docs](https://docs.github.com/en/copilot/how-tos/copilot-in-your-ide/customize-copilot/extend-copilot-with-tools-and-context/set-up-the-github-mcp-server)）：

```
url:     https://api.githubcopilot.com/mcp
headers: Authorization: Bearer <GITHUB_PAT>
```

对照 DSH 的 `StreamableHttpConfig`（含 `headers`）—— **两边严丝合缝**。
所以「零代码连接器」是可行的，前提只有一个：**一个带 `repo` scope 的 PAT**。

## 10. 本机 MCP 相关依赖盘点

| 项 | 状态 |
|---|---|
| `@modelcontextprotocol/sdk` | **1.30.0 已存在**于 `…\@deepseek-ai\dsh\node_modules\@modelcontextprotocol\sdk` |
| `@octokit` 全量客户端 | **没有**（只有 `types` 18.0.0、`webhooks` 14.2.0、`openapi-types`、`request-error`） |
| node v24.21.0 | `fetch` ✅ `AbortSignal.timeout` ✅ —— **不装 octokit 也能打 GitHub API** |
| 已有 GitHub token | **没有**。`GITHUB_TOKEN`/`GH_TOKEN`/`GITHUB_PAT`/`GITHUB_PERSONAL_ACCESS_TOKEN` 进程/用户/机器三级全空 |
| `.credentials.yaml`（`C:\Users\AlanL\.dsh\`） | 存在，但 ref 只有 `DEEPSEEK_API_KEY`、`QWEN_TOKEN_PLAN_API_KEY`，**无 GitHub 凭据** |
| `gh` 的 hosts.yml / `.git-credentials` | 都不存在 |

→ 结论：**连接器的一切都卡在「给我一个 PAT」这一步。**

## 7b. DSH 侧 MCP 接入的确切契约（读自已安装的 .d.ts）

文件：`C:\Users\AlanL\AppData\Roaming\npm\node_modules\@deepseek-ai\dsh\node_modules\@deepseek-ai\dsh-mcp-client\lib\types\index.d.ts`

MCP 工具对模型暴露为 `mcp__<serverName>__<toolName>`（见该文件 L2-4 与 L28-33）。
一个插件实例 == 一个 MCP server。

**stdio 形态（`StdioConfig`，L25-48）**，必填 `transport:'stdio'` + `serverName` + `command`，
可选 `args` `env` `cwd` `toolCallTimeoutMs` `failOnStartupError` `reconnect`：

```
command    Executable used to start the server.
args       Arguments passed directly, without shell interpolation.
env        Extra env vars merged on top of scrubbed ambient env.
```

**Streamable HTTP 形态（`StreamableHttpConfig`，L50-69）**，必填 `transport:'streamable-http'`
+ `serverName` + `url`，可选 **`headers`** + `toolCallTimeoutMs` + `failOnStartupError`：

```
url      MCP endpoint URL.
headers  Additional headers attached to MCP requests.
```

`headers` 是合法字段 —— 这打开了**远程 MCP + `Authorization: Bearer <PAT>`** 这条路，
不必落地任何二进制。`serverName` 约束为 `[A-Za-z0-9_-]{1,32}` 且需全局唯一。

装配位置：`C:\Users\AlanL\.dsh\profiles\web\cordis.patch.yml`，写法照抄现成的 context7 行：

```yaml
- insert:
    - id: mcp-<name>
      name: '@deepseek-ai/dsh-mcp-client'
      config:
        serverName: <name>
        transport: streamable-http
        url: <endpoint>
        headers:
          Authorization: 'Bearer <PAT>'
        toolCallTimeoutMs: 30000
        failOnStartupError: false
```

已确认的坑（来自该 profile 文件自身的注释，可信度高）：

- `failOnStartupError: false` 让端点不可达时「记一条错误 + 零工具」，
  而不是整个 profile 加载失败。**调试期反而要设 `true` 才能看到启动失败。**
- `config:` 是**整体替换**语义（`cordis-plugin-include/lib/index.js` L102
  `target[key] = value`），写部分字段会丢掉其余字段。
- `name:` 是**可选守卫**，不匹配则**静默跳过**该补丁 —— 名字写错会「什么都没发生」。
- `dsh-mcp-client` **不消费 credentials seam**，所以
  `!!js process.env.XXX` 有用（需在启动 shell 里导出），但 DSH 的
  `.credentials.yaml` **不会**被加载进进程环境。
- 该文件已有中文注释，说明**可以用 Node 写**（不能用 PowerShell，BOM 问题）。
  改前先备份。

---

## 8. 附：本次探测留下的文件

- `_env_probe.ps1` — 工具存在性、身份、npm/node、GitHub 可达性、git 配置、写权限
- `_env_probe2.ps1` — gh 安装位置、真 curl.exe、OpenSSL 位置、pnpm、SSH、代理、choco、内存
- `_env_probe3.ps1` — **决定性**：sslBackend 对照实验、GIT_CONFIG_GLOBAL、真实 clone、SSH、npm 本地 prefix
- `_npmcheck.mjs` — 查 npm registry 上的 GitHub MCP server 包

脚本均为纯 ASCII（**含中文的 .ps1 会被 PowerShell 5.1 按 ANSI 读入并解析失败**，
本次已踩过这个坑；`.ps1` 一律用英文注释）。
