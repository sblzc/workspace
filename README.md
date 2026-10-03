# radio

GitHub 协作工作区。同时也是一个工作笔记库：环境事实、踩过的坑、协作约定都记在这里，
而不是留在某个人的脑子里。

## 这里有什么

| 文件 | 说明 |
|---|---|
| `ENVIRONMENT.md` | 本机环境的**实测**报告。工具链、沙箱边界、网络行为、GitHub 连接器可行性。 |
| `docs/github-pat.md` | 如何生成 GitHub 访问令牌，以及为什么需要哪些权限。 |
| `_env_probe*.ps1` | 产生 `ENVIRONMENT.md` 结论的探测脚本，保留以便复现。 |

## 三条已经踩明白的坑

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
1200ms 成功和 21 秒超时都出现过，同一天内。所有联网操作都要带超时和重试，
「一次成功」不构成结论。

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

