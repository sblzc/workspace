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
→ 判断权限的正确方式是查 `GET /api.github.com/repos/<owner>/<repo>` 的 `permissions` 字段，
**绝不要用 push 的报错推断权限**。

**每次 git 网络操作都会打一行 `sh.exe: couldn't create signal pipe` —— 这是噪声，
退出码仍是 0、结果正确。以退出码和远端 SHA 为准。**

## 三、GitHub 连接器

已挂载官方托管 MCP（`mcp__github__*`，46 个工具），零代码。
配置与排查见 `docs/github-connector.md`。

- 令牌：`D:\radio\.github-token`（已 gitignore）
- 配置：`~/.dsh/profiles/web/cordis.patch.yml` 的 `mcp-github` 块
- **配置文件里写死了 `D:/radio/.github-token` 绝对路径**，换目录要同步改

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
| `.github-token` | 令牌本体，**已 gitignore，永不提交** |
