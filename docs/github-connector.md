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

**`patchReload: live`，改完即生效，不需要重启。** 本次挂载就是热加载生效的。

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

### 排查顺序

| 现象 | 查什么 |
|---|---|
| 会话里完全没有 `mcp__github__*` | `cordis.patch.yml` 是否被热加载；`failOnStartupError: true` 应让启动失败变响亮 |
| 有工具但调用报 401 | `.github-token` 内容是否含多余空白/换行；令牌是否被吊销或过期 |
| 配置解析失败 | `!!js` 后面**必须**跟合法 YAML 标量 —— 裸反引号会报 `bad indentation of a mapping entry` |
| `authorization value undefined` | 表达式返回了 `undefined`，检查 `readFileSync` 路径 |

---

## 5. 维护

**轮换令牌**（改完即生效，无需重启）：

```powershell
# 写新的令牌（一行，不要引号，不要 'Bearer ' 前缀）
Set-Content -Path D:\radio\.github-token -Value '<NEW_TOKEN>' -NoNewline -Encoding ascii
```

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
