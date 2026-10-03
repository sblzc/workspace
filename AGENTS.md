# radio 协作工作区 — 项目约定

本文件每轮注入。**不重复 `~/.dsh/AGENTS.md` 的全局内容**，只写本项目特有的。

---

## 这是什么

`D:\radio` 是一个用于项目协作的 GitHub 工作区仓库，远端 `sblzc/workspace`（public，MIT）。

```powershell
git push origin main        # 已配置自动认证，直接可用
git fetch origin
```

## 一、git 认证：不要碰凭据帮助器

**任何 `credential.helper` 在本沙箱都必然失败** —— 它会 spawn `sh.exe`，
而沙箱禁止创建信号管道：`sh.exe: *** fatal error - couldn't create signal pipe, Win32 error 5`。
`http.extraHeader` 同样无效（报 `could not read Username`，极具误导性）。

**可用方式**：令牌写在 `.git/radio-credentials`，经 `include.path` 注入，
用 `url.<tokenized>.insteadOf` 让普通 `git push` / `git fetch` 自动带上令牌。
重新生成用 `tools/setup-git-auth.ps1`。

**两条硬规矩**：

1. **永远不要 `git push -u <带令牌的URL>`** —— `-u` 会把令牌写进 `.git/config` 的
   `branch.*.remote`。曾实际发生过。`origin` 必须保持不含令牌的裸 URL。
2. **`.ps1` 一律纯 ASCII**。Windows PowerShell 5.1 会把无 BOM UTF-8 的 `.ps1`
   按 GBK 读，含中文时解析器直接崩（`Unexpected token '浠ょ墝...'`）。
   本机**没有 `pwsh`**，调用用 `powershell -NoProfile -ExecutionPolicy Bypass -File <path>`。

## 二、网络：`github.com` 不可靠，`api.github.com` 可靠

| 主机 | 实测成功率 |
|---|---|
| `github.com`（git push/clone 走这里） | **约 38%**（失败时卡满 ~10.7s） |
| `api.github.com` | 100% |
| `codeload.github.com` | 100% |

→ git 网络操作**失败就重试**，不要当成认证或权限问题。
→ 判断权限的正确方式**不是**查 `permissions` 字段 —— 那个字段对只读令牌也报
`push: true`（它描述的是账号在仓库里的角色，不是令牌的 scope）。
**唯一可靠的判据是真的做一次写操作**：`node tools/check-token-write.mjs`。

**每次 git 网络操作都会打一行 `sh.exe: couldn't create signal pipe` —— 这是噪声，
退出码仍是 0、结果正确。以退出码和远端 SHA 为准。**

本机有可用代理 `127.0.0.1:7897`（直连失败时的兜底）：
`git -c http.proxy=http://127.0.0.1:7897 push origin main`

## 三、GitHub 连接器

已挂载官方托管 MCP（`mcp__github__*`，46 个工具），零代码。
配置与排查见 `docs/github-connector.md`。

- 令牌：`C:\Users\AlanL\.dsh\.github-token` —— **在 `~/.dsh/` 下，不在本仓库里**
- 配置：`~/.dsh/profiles/web/cordis.patch.yml` 的 `mcp-github` 块
- **连接器挂在 `web` profile 上，服务所有工作区**（不绑定 `D:\radio`）。
  **不要把令牌放回仓库里** —— 那会把连接器绑死在这个目录上。
- 换令牌值之后**必须重启 dsh**；只改令牌文件路径可以靠热加载。
  （`patchReload: live`，但 `!!js` 只在 entry 首次加载时求值一次。）

## 四、沙箱事实（本项目踩过的）

- **写 `D:\radio` 以外的路径**（尤其 `~/.dsh/`）每次都要一次 `danger-full-access` 授权。
  **批量合并写入，减少弹窗次数。**
- `setx` 在本沙箱失败：`ERROR: Access to the registry path is denied.`
  → 需要持久化配置时，**用文件而不是环境变量**。
- 工作区外的东西可以**读**（`C:\Users\AlanL\.dsh\...` 能读），只有写受限。

## 五、目录约定

| 路径 | 内容 |
|---|---|
| `docs/` | 面向人的文档（PAT 指南、连接器手册） |
| `tools/` | 可重跑的运维脚本 |
| `ENVIRONMENT.md` | 环境实测报告，**所有结论都有命令输出为证** |
| `tools/check-token-write.mjs` | 真写一次判定令牌权限（`permissions` 字段不可信） |

**令牌文件不在本仓库里**，在 `C:\Users\AlanL\.dsh\.github-token`。
`.gitignore` 里保留 `.github-token` 规则只是兜底 —— 如果哪天这个文件又出现在
`D:\radio` 下，说明有人按旧文档操作了，**要纠正**。
