# radio

GitHub 协作工作区。同时也是一个工作笔记库：环境事实、踩过的坑、协作约定都记在这里，
而不是留在某个人的脑子里。

## 这里有什么

| 文件 | 说明 |
|---|---|
| `ENVIRONMENT.md` | 本机环境的**实测**报告。工具链、沙箱边界、网络行为、GitHub 连接器可行性。 |
| `docs/github-pat.md` | 如何生成 GitHub 访问令牌，以及为什么需要哪些权限。 |
| `docs/github-connector.md` | GitHub MCP 连接器操作手册：怎么接上的、怎么验证、怎么轮换令牌。 |
| `tools/check-token-write.mjs` | 检查 `.github-token` 是否**真的有写权限**（`permissions.push` 这个 API 字段会骗人）。 |
| `tools/setup-git-auth.ps1` | 配置本机 git 自动认证（令牌注入 URL，不经过凭据帮助器）。 |
| `_env_probe*.ps1` | 产生 `ENVIRONMENT.md` 结论的探测脚本，保留以便复现。 |

## 连接器

GitHub 官方托管的 MCP 服务器已经挂在本机的 DSH 上，46 个工具
（`push_files`、`create_pull_request`、`search_code` 等），**零代码**。
配置在 `C:\Users\AlanL\.dsh\profiles\web\cordis.patch.yml` 的 `mcp-github` 块，
令牌从 `.github-token` 读取。详见 [`docs/github-connector.md`](docs/github-connector.md)。

这两件东西**互相独立**：连接器让 AI 直接调 GitHub API，
git 走命令行。任何一个坏了都不影响另一个。

## 怎么协作

这是一个**普通的公开 git 仓库**。任何人只要有 GitHub 账号就能参与，
不需要装 DSH、不需要这个沙箱、不需要任何本机配置。

```bash
git clone https://github.com/sblzc/workspace.git
cd workspace
git config user.name  "你的名字"
git config user.email "你的邮箱"
```

**普通协作者（推荐）** —— 不碰 `main`，走 PR：

1. 在 GitHub 上 **Fork** 这个仓库（或由维护者把你加为 collaborator）。
2. 开分支：`git switch -c feat/你的主题`
3. 提交：`git commit -m "feat: 做了什么"`
4. 推送：`git push -u origin feat/你的主题`
5. 在 GitHub 上开 **Pull Request**，写清改了什么、为什么。
6. 等 review 通过后由维护者合并。

**维护者（有写权限）** 可以直接在 `main` 上工作，但即使是单人也建议开分支 ——
`main` 上永远是一个能用的状态。

**如果只改错别字/文档**：GitHub 网页上直接点铅笔图标就能改，
它会自动帮你开分支并提 PR，不用克隆。

**提 Issue**：发现环境事实不对、踩到新坑、想要新功能，开 Issue 比直接改更合适 ——
`ENVIRONMENT.md` 里的每条结论都应该能被别人复现。

### 这个仓库的写作约定

- **记录实测结论，不记录猜测。** `ENVIRONMENT.md` 里每条都注明怎么验证的。
- **坑要写清「看起来像什么」**，因为本机这几个坑全都表现为别的问题
  （比如权限不足其实是没有凭据）。
- **探测脚本保留在仓库里**，让结论可复现。
- **令牌、密码、私钥永不入库** —— 见 `.gitignore` 和 `docs/github-pat.md`。

## 已经踩明白的坑

写在这里，是因为它们都会以「看起来像别的问题」的样子出现。

**一、沙箱内不能 spawn 带管道的子进程。**
`spawn(node, [...], {stdio:'pipe'})` 直接 `EPERM`。
后果有两个，而且看起来毫不相干：MCP 的 `transport: stdio` 用不了；
git 一旦需要凭据就会报 `couldn't create signal pipe, Win32 error 5`，
因为它是靠 `sh.exe` 去调凭据帮助器的。SSH 报同样的错，是同一个根因。

**二、git 走 HTTPS 必须显式指定 OpenSSL 后端。**
系统配置强制了 `http.sslBackend = schannel`，会失败于
`schannel: AcquireCredentialsHandle failed: SEC_E_NO_CREDENTIALS`。
加 `-c http.sslBackend=openssl` 就正常。

**三、GitHub 对本机不是稳定可达。**
同一天内，`api.github.com` 可以 6/6 全绿（中位 100ms），而 `github.com`
可以 **0/6 全超时**（每轮卡满 20s）。失败形态还互相伪装 —— 见下面这张表。

| 报错 | 真正的原因 |
|---|---|
| `Recv failure: Connection was reset` | 链路抖动 |
| `Failed to connect ... after 21087 ms` | TCP 超时 |
| `OpenSSL SSL_read: unexpected eof ... errno 10004` | 隧道中途断开 |
| `could not read Username ... terminal prompts disabled` | **不是**缺凭据，是请求没发出去 |
| `403 Permission ... denied` | **不一定**是权限问题 |

**所以：本机的网络错误几乎都会伪装成别的问题。**
在得出「权限不足」「配置错了」这类结论前，先重试 3–5 次，
再用一个绕开该层的独立探针交叉验证。

**本机有一个可用代理 `127.0.0.1:7897`**（实测能 `CONNECT` 到 github.com，
TLSv1.3，1MB POST 也扛得住）。直连失败时可以：

```powershell
git -c http.proxy=http://127.0.0.1:7897 push origin main
```

**四、`permissions.push` 这个 API 字段会骗人。**
对一个**只读**令牌，`GET /repos/{owner}/{repo}` 仍然返回
`"push": true`，但每个写操作都是 403。
它描述的是**你账号在该仓库的角色**，不是**令牌被授予的 scope**。
唯一可靠的判据是真的做一次写 —— 用 `tools/check-token-write.mjs`。

## 本机约定

- 提交身份、凭据、令牌都走 **仓库内配置**，不写全局配置。
- 访问令牌放在 `.github-token`（已被 `.gitignore` 排除），不进对话记录，不进提交。
- 联网命令必须带超时与重试。

## 为什么不能用凭据帮助器

本机试过的替代方案都走不通，记在这里省得再试：凭据帮助器（Git Credential Manager）、
`credential.helper = store`、SSH 密钥 —— 三个失败原因**完全相同**，
都是沙箱拒绝创建信号管道（`couldn't create signal pipe, Win32 error 5`），
因为它们都要 spawn 子进程。只剩令牌这一条路。

## 许可

[MIT](LICENSE)

