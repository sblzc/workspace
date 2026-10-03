# GitHub 连接器操作手册

连接器已**端到端验证可用**。本文记录它是怎么接上的、怎么验证、怎么维护。

---

## 1. 结论速览

| 项 | 状态 |
|---|---|
| 传输方式 | **Streamable HTTP**（托管端点，非本地进程） |
| 端点 | `https://api.githubcopilot.com/mcp` |
| 认证 | 细粒度 PAT 作 Bearer 令牌 —— **无需 OAuth App、无需 Docker、无需本地二进制** |
| 实测工具数 | **46 个** |
| 端到端验证 | `initialize` → 200；`notifications/initialized` → 202；`tools/list` → 200；`get_me` → `{"login":"sblzc"}` |
| 代码量 | **0 行** |

**为什么是零代码**：这个远程端点同时绕开了本沙箱的两个死结 ——
`stdio` 传输需要带管道的子进程（`spawn EPERM`，见 `ENVIRONMENT.md` 第 8 节），
凭据帮助器需要 spawn `sh.exe`（`couldn't create signal pipe`，同上）。
换成 HTTP + 显式 Bearer 头，两个问题都不存在。

---

## 2. 配置在哪

`C:\Users\AlanL\.dsh\profiles\web\cordis.patch.yml` 的 `mcp-github` 块：

```yaml
- insert:
    - id: mcp-github
      name: '@deepseek-ai/dsh-mcp-client'
      config:
        serverName: github
        transport: streamable-http
        url: https://api.githubcopilot.com/mcp
        headers:
          Authorization: !!js '...读文件并拼 Bearer...'
        toolCallTimeoutMs: 60000
        failOnStartupError: true
```

工具对模型暴露为 `mcp__github__<toolName>`（见该 profile 文件中
`dsh-mcp-client` 的命名规则：一个插件实例 == 一个 MCP server）。

**`patchReload: live`** —— 首次挂载就是热加载生效的，不需要重启。

> ⚠️ **但「热加载」不等于「令牌会换」。** `!!js` 表达式在 entry
> **首次加载时求值一次**，结果作为普通字符串交给
> `StreamableHTTPClientTransport`（`dsh-mcp-client/lib/index.js:48`：
> `new StreamableHTTPClientTransport(new URL(config.url), { requestInit: { headers: config.headers } })`）。
> 换掉 `.github-token` 的内容**不会**影响已经建立的连接器 ——
> 它手里还是旧令牌，每个调用都会报
> `unauthorized: AuthenticateToken authentication failed`。
> 详见第 5 节的轮换流程。

---

## 3. 令牌为什么不写在配置里

配置里写的是 `!!js` 表达式，在**加载时**从 `D:\radio\.github-token` 读：

```
!!js '(/^(github_pat_|ghp_)/.test(readFileSync("D:/radio/.github-token","utf8").trim())
      ? readFileSync(...).trim()
      : (() => { throw ... })()).replace(/^/, "Bearer ")'
```

这样 `cordis.patch.yml` 保持干净 —— **可以放心备份或分享，不会带走令牌**。

**为什么不用 `process.env.GITHUB_PAT`**（原本的首选方案）：`setx GITHUB_PAT <token>`
在本沙箱直接失败 —— `ERROR: Access to the registry path is denied.`
（非提权 + 工作区外写保护）。而且**已经在运行的 dsh 进程本来就看不到新设的用户环境变量**。
读文件是等效保证，且在这里真的能跑（`node:fs` 不 spawn 子进程，沙箱不干预）。

**为什么用 `throw` 而不是给默认值**：空的 `"Bearer "` 仍然是合法字符串，
能过 `z.dict(String)` 校验，然后表现为一个语焉不详的 401。
直接抛错能让问题在启动时就以明确信息暴露。

> ⚠️ **配置文件里写死了 `D:/radio/.github-token` 这个绝对路径。**
> 如果仓库换目录，必须同步改这里。

---

## 4. 怎么验证

```powershell
# 1) 配置语法 + !!js 求值 + schema 形状
node D:\radio\_mcp_probe.mjs     # 直连端点跑完整握手，列出全部工具

# 2) 在会话里直接调一个只读工具，例如 mcp__github__get_me
```

`_mcp_probe.mjs` 不依赖 DSH，直接对端点做 `initialize` → `initialized` →
`tools/list`，是最干净的「连接器到底通不通」判据。

### 2026-10-03 重启后的完整验证记录（全绿）

一次性把所有层都验了一遍：

| 检查项 | 方法 | 结果 |
|---|---|---|
| 连接器认证 | `mcp__github__get_me` | `{"login":"sblzc","id":175811836}` |
| 连接器读文件 | `get_file_contents` AGENTS.md | SHA `fa68bba8…` |
| 连接器读提交 | `list_commits` | `757c74e`、`58dcb0c`、`ef190a8` |
| 连接器读分支 | `list_branches` | `main` @ `757c74e`，`protected: false` |
| 连接器读仓库 | `search_repositories` | `sblzc/workspace` |
| 端点工具数 | 直连 `tools/list` | **46 个** |
| 令牌写权限 | `tools/check-token-write.mjs` | **PASS**（建分支→删分支，204） |
| git 直连 | `git ls-remote` ×3 | 3/3 `exit=0` |
| 本地 = 远端 | `git rev-parse` 对比 | `757c74e` == `757c74e`，clean |

**结论：重启 dsh 确实让连接器换上了新令牌。**
之前那个 `unauthorized: AuthenticateToken authentication failed` 消失了 ——
这实测确认了第 5 节「必须重启」的说法。

### 两个已知的工具限制（不是故障，别浪费时间去修）

**① `run_secret_scanning` 对本仓库永远不可用**

```
Error: Repository does not have GitHub Advanced Security enabled.
```

GitHub Advanced Security 是**付费功能**，公开仓库的免费额度也不包含它。
要找密钥请改用 `search_code` 配正则，或本地扫（本仓库用的是本地扫）。

**② `search_code` 加 `repo:` 限定符会因索引未覆盖而返回 0**

```
search_code("signal pipe")                        → 20,480,000 条（搜的是全 GitHub）
search_code("repo:sblzc/workspace \"signal pipe\"") → 0 条，incomplete_results: true
```

`incomplete_results: true` 表示**索引尚未覆盖该仓库** ——
**搜不到不等于文件里没有**。要确认仓库内容请用 `get_file_contents` 直接读。
（`get_file_contents`、`list_commits`、`list_branches` 都正常。）

### 排查顺序

| 现象 | 查什么 |
|---|---|
| 会话里完全没有 `mcp__github__*` | `cordis.patch.yml` 是否被热加载；`failOnStartupError: true` 应让启动失败变响亮 |
| **换了令牌后报 `unauthorized: AuthenticateToken authentication failed`** | **连接器仍持有旧令牌** —— 见第 5 节，重启 dsh 最可靠。（不要用 `permissions.push` 判断权限，那个字段会骗人；用 `tools/check-token-write.mjs`） |
| 有工具但调用报 401 | `.github-token` 内容是否含多余空白/换行；令牌是否被吊销或过期 |
| 配置解析失败 | `!!js` 后面**必须**跟合法 YAML 标量 —— 裸反引号会报 `bad indentation of a mapping entry` |
| `authorization value undefined` | 表达式返回了 `undefined`，检查 `readFileSync` 路径 |

---

## 5. 维护

**轮换令牌**（**只改 `.github-token` 是不够的**，见下）：

```powershell
# 1) 写新的令牌（一行，不要引号，不要 'Bearer ' 前缀）
Set-Content -Path D:\radio\.github-token -Value '<NEW_TOKEN>' -NoNewline -Encoding ascii

# 2) git 侧：重跑脚本，把新令牌写进 .git/radio-credentials
powershell -NoProfile -ExecutionPolicy Bypass -File D:\radio\tools\setup-git-auth.ps1

# 3) 连接器侧：让 !!js 重新求值 —— 见下方说明
```

**第 3 步为什么不能只 touch 文件**：`cordis-plugin-include/lib/index.js:177`
的 `read()` 第一行就是

```js
if (!forced && this.content === content) return;
```

**内容不变就直接返回**，所以改时间戳（`(Get-Item $f).LastWriteTime = ...`）
不会触发任何重载。必须**改变文件内容** —— 加一行注释即可。

⚠️ **实测：即使改了内容触发热加载，连接器仍可能继续用旧令牌。**
`interpolate` 本身不缓存（`cordis-plugin-loader/lib/index.js:295-300`），
但重载走的 `update` 路径不一定重跑 `internal/config` 求值
（`cordis-plugin-loader/lib/index.js:685-690`，其中一行 guard 是
`if (this.parent.fiber?.entry === this.entry) return config;`）。
**最可靠的做法是重启 dsh。** 确认方法：调用 `mcp__github__get_me`，
成功返回 `{"login":"sblzc"}` 就说明新令牌生效了。

**临时停用**：在 `mcp-github` 那一行加 `disabled: true`，或注释掉整个 `- insert:` 块。

**改了工作区路径**：同步改 `cordis.patch.yml` 里表达式的绝对路径。

---

## 6. 令牌安全

- `.github-token` **已被 `.gitignore` 忽略**，不会进版本库。
- `cordis.patch.yml` 里**没有明文令牌**（可自行 grep `github_pat_` 复核）。
- `.git/config` 里**没有明文令牌** —— 令牌经 `.git/radio-credentials` +
  `include.path` 注入（见 `ENVIRONMENT.md` 第 11 节）。
  历史教训：`git push -u <带令牌的URL>` 会把令牌写进 `.git/config`，**永远不要这么用**。
- **GitHub 会在一段时间未使用后自动吊销令牌**；若连接器突然 401 且令牌久未使用，先查这里。

---

## 7. 相关文件

| 文件 | 作用 |
|---|---|
| `D:\radio\.github-token` | 令牌本体（已 gitignore） |
| `_mcp_probe.mjs` | 直连端点的握手探测脚本（仓库根） |
| `_yamlcheck.mjs` | 校验 `cordis.patch.yml`：YAML 语法 / `!!js` 求值 / schema 形状（仓库根） |
| `D:\radio\tools\setup-git-auth.ps1` | 配置 git 自动认证（推送用，与连接器独立） |
| `docs/github-pat.md` | PAT 创建指南（类型、权限、预填链接） |
| `ENVIRONMENT.md` | 环境实测报告（第 8/11 节是本文的前置约束） |
