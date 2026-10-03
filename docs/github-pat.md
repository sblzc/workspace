# GitHub 访问令牌（PAT）怎么建

这份文档是给**人**看的操作说明。目标：拿到一个令牌，让这台机器能
读写指定仓库的代码、议题和拉取请求，同时把风险限制在最小范围。

---

## 为什么不能用别的方式

本机试过的替代方案都走不通，原因记在这里省得再试一遍：

| 方案 | 结果 |
|---|---|
| 凭据帮助器（Git Credential Manager） | git 靠 `sh.exe` 调它，而沙箱拒绝创建信号管道 → `couldn't create signal pipe, Win32 error 5` |
| `credential.helper = store` | 同上，一样要 spawn 子进程 |
| SSH 密钥 | 同上，同一个管道根因 |
| GitHub CLI (`gh`) | 本机没装；`winget` 安装需要提权 |

**所以只剩令牌这一条路。** 好消息是它反而最简单：本质上就是一个字符串。

---

## 生成令牌

### 先选类型

| | 细粒度（fine-grained）**推荐** | 经典（classic） |
|---|---|---|
| 权限范围 | 按仓库 + 按权限逐项勾选 | 一个 `repo` 通吃你所有仓库 |
| 适用 | 开自己或自己所在组织的仓库 | 给**别人**的公开仓库提交、或你是外部协作者 |
| 链接 | [生成细粒度令牌](https://github.com/settings/personal-access-tokens/new) | [生成经典令牌](https://github.com/settings/tokens/new) |

> 细粒度令牌**无法**用于：给「你不是成员」的公开仓库提交，
> 也无法用于你是外部协作者（outside collaborator）的仓库。
> 踩到这两种情况才退回经典令牌，别一开始就用经典。

### 推荐配置：细粒度

直接点这个链接，大部分字段会预填好：

**[→ 生成协作令牌（已预填权限）](https://github.com/settings/personal-access-tokens/new?name=radio-workspace&expires_in=90&contents=write&issues=write&pull_requests=write&workflows=write&discussions=write&metadata=read)**

对应下表。如果链接里有你想去掉的权限，去掉即可 —— 少给不会出错，多给才是风险。

| 字段 | 填什么 | 说明 |
|---|---|---|
| Token name | `radio-workspace` | 随便起，但别起成 `temp` —— 你以后要靠名字认出它 |
| Expiration | `90` 天 | 别选 `none`。到期换一个的成本，远低于泄漏后的成本 |
| Description | 可选 | 例如「D:\radio 工作区协作」 |
| Resource owner | **你自己**（或你所在的组织） | 决定这个令牌能碰到谁名下的仓库 |
| Repository access | **Only select repositories** | **不要选 All repositories** —— 这是最重要的一栏 |
| Selected repositories | 只勾你真正要用的仓库 | 现在还没有仓库就先留空，建好后再回来加 |
| Permissions → Repository | 见下表 | |

**权限勾选清单**（Repository permissions 分组下）：

| 权限 | 级别 | 为什么需要 |
|---|---|---|
| Contents | **Read and write** | 读写代码、分支、提交。**必须**，没有它连 pull 都不行 |
| Issues | **Read and write** | 建/改议题、评论 |
| Pull requests | **Read and write** | 建/审拉取请求、写评审意见 |
| Workflows | **Read and write** | 仓库里有 `.github/workflows/` 时才需要；没有可以不给 |
| Discussions | **Read and write** | 只有用 Discussions 才需要 |
| Metadata | Read-only | **强制包含**，会自动带上，不用管 |

最后点 **Generate token**，然后**立刻复制** —— 这个字符串只显示一次，
关掉页面就再也看不到了。它长得像 `github_pat_11ABC...`。

### 备选配置：经典

只有当你要给「自己不是成员」的公开仓库提交时才用：

**[→ 生成经典令牌](https://github.com/settings/tokens/new?scopes=repo&description=radio-workspace)**

- Note: `radio-workspace`
- Expiration: 90 天
- Scopes: 勾 **`repo`**（这就是全部所需）

经典 `repo` 令牌**能访问你能访问的每一个仓库**，包括所有私有仓库。
这是它不如细粒度的原因，也是 GitHub 现在默认推荐细粒度的原因。

---

## 放哪里

存到工作区里的一个文件：

```
D:\radio\.github-token
```

内容就一行，就是令牌本身，前后不要加引号、不要加 `Bearer `：

```
github_pat_xxxxxxxxxxxxxxxxxxxx
```

`.gitignore` 里已经有 `.github-token` 这一条，所以它**不会被提交**。

### 为什么不放进聊天窗口

令牌一旦粘进对话，就会永久留在会话记录里，之后可能被导出、
被压缩进摘要、或出现在任何回顾这次会话的地方。
放进文件则不进对话，两条好处都拿到了。

### 关于 DSH 的凭据文件

`C:\Users\AlanL\.dsh\.credentials.yaml` 里目前只有 `DEEPSEEK_API_KEY` 和
`QWEN_TOKEN_PLAN_API_KEY`，**没有** GitHub 凭据。而且 DSH 不会把这个文件
加载进进程环境，所以别指望它能自动生效 —— 令牌要显式传给用它的程序。

---

## 验证它真的能用

放好文件之后，让助手跑一次验证。手工验证的话是这一条：

```powershell
$tok = (Get-Content D:\radio\.github-token -Raw).Trim()
Invoke-RestMethod -Uri 'https://api.github.com/user' -Headers @{
  Authorization = "Bearer $tok"
  Accept        = 'application/vnd.github+json'
}
```

返回你的账号信息（`login`、`id`、`plan` 等）就是通了。
返回 `401 Bad credentials` 说明令牌复制不完整或已被吊销。

**但「身份能认出来」不等于「能写」。** 这两件事必须分开验证：

```powershell
node D:\radio\tools\check-token-write.mjs
```

它会真的尝试建一个临时分支再删掉。`PASS` 才算能推代码；
`FAIL ... READ-ONLY` 说明 Contents 还是 Read，去令牌设置里改成 **Read and write**。

> ⚠️ **不要用 API 的 `permissions.push` 字段判断权限 —— 它会骗人。**
> 实测过：一个**只读**令牌查 `GET /repos/{owner}/{repo}` 返回
> ```json
> "permissions": {"admin":true,"maintain":true,"push":true,"triage":true,"pull":true}
> ```
> 但同一个令牌做任何写操作都是 `403 Resource not accessible by personal access token`，
> `git push` 报 `Permission to sblzc/workspace.git denied to sblzc`。
> 那个字段反映的是**你账号在这个仓库里的角色**，不是**这个令牌被授予的权限**。
> 唯一可靠的判据是**真的做一次写操作** —— 这就是 `check-token-write.mjs` 存在的理由。

---

## 万一泄漏了

**立刻**去 [令牌列表](https://github.com/settings/tokens) 删掉它，然后重新生成一个。
不需要改密码 —— 令牌和密码是两套东西。这也是为什么建议设过期时间：
它保证最坏情况下，泄漏也是有时限的。

---

## 这台机器上的已知网络问题

GitHub 从本机**不是稳定可达**：实测见过 1200ms 成功，也在同一天见过
21 秒连接超时。所以：

- 不要因为一次失败就断定令牌有问题，先重试。
- 所有联网操作都要带超时，不能无限等。
- 判断「能不能用」要看多次结果，不看单次。
