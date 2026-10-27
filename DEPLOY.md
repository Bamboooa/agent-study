# 部署到公网（Render 免费版 + GitHub Gist 当数据库）

目标：不用开电脑，手机/平板/别人电脑都能打开 `https://xxxx.onrender.com`，登录同一个账号就能用。

**为什么不用 Render 自带的磁盘**：免费实例的磁盘是临时的，每次重启/重新部署都会清空，`data.db` 会丢。所以数据存到你自己的 GitHub Gist（免费、永久、只有你的 token 能读写）。

---

## 一、准备两样东西（5 分钟）

### 1. 建一个 Gist 当数据库

1. 打开 https://gist.github.com
2. 文件名填 `studydb.json`，内容填 `{}`
3. 点 **Create secret gist**
4. 看地址栏：`https://gist.github.com/你的用户名/<这一串就是 GIST_ID>`

### 2. 生成一个只够用的 Token

1. 打开 https://github.com/settings/tokens?type=beta （Fine-grained token）
2. Token name 随便填，Expiration 选 90 天或 No expiration
3. **Repository access** 选 `Public repositories` 或 `Only select repositories` 都行
4. **Account permissions → Gists** 选 **Read and write**
5. 生成后复制 `github_pat_...`（只显示一次）

> 这个 token 只能读写你的 Gist，不能碰你的代码仓库。

---

## 二、把代码推到 GitHub

先在 https://github.com/new 建一个空仓库，名字比如 `agent-study`，**不要**勾 README。

然后双击项目根目录的 **`部署到GitHub.bat`**，按提示填三样东西：

```
你的 GitHub 用户名:  ← 例如 chenyz
仓库名:              ← 直接回车就是 agent-study
邮箱:                ← 直接回车用 GitHub 的匿名邮箱
```

它会自动完成 `init → add → commit → push`，第一次推送会弹浏览器让你登录 GitHub，登一次就好。

> 如果你更习惯命令行，等价于：
> ```bat
> cd /d D:\dsh-workspace\projects\ai-agent-plan-v2
> git init
> git add .
> git commit -m "学习监督：网页版 + 账号体系"
> git branch -M main
> git remote add origin https://github.com/<你的用户名>/agent-study.git
> git push -u origin main
> ```

---

## 三、在 Render 上开服务

1. 打开 https://dashboard.render.com/ → 用 GitHub 登录
2. 点 **New +** → **Web Service**
3. 选你刚建的 `agent-study` 仓库 → Connect
4. 填这几项：

| 字段 | 填什么 |
|---|---|
| Name | `agent-study`（决定网址前缀） |
| Region | Singapore（离国内最近） |
| Branch | `main` |
| Runtime | Python 3 |
| Build Command | `pip install -r requirements.txt` |
| Start Command | `python server/server.py` |
| Instance Type | **Free** |

5. 展开 **Environment Variables**，加两条：

| Key | Value |
|---|---|
| `GIST_ID` | 第一步那串 ID |
| `GITHUB_TOKEN` | 第二步那个 `github_pat_...` |

6. 点 **Create Web Service**，等 2-3 分钟构建完成。

部署成功后会给你一个地址，形如 `https://agent-study-xxxx.onrender.com`。

---

## 四、验证

1. 打开那个网址 → 出现登录页
2. 用 `陈禹竹` / `230319` 登录（第一次会自动建号）
3. 勾一个打卡 → 等 3 秒 → 去 Gist 页面刷新，应该能看到 `studydb.json` 里有你的数据
4. 手机浏览器打开同一网址登录 → 看到同样的进度

**数据恢复验证**（我本地已经跑过这个测试）：删掉服务器上的 `data.db` 重启，账号和进度会从 Gist 自动恢复。

---

## 五、免费版的三个限制

| 限制 | 影响 | 应对 |
|---|---|---|
| **15 分钟没人访问会休眠** | 下次打开要等 30-60 秒唤醒 | 打开时先等一下；或每天第一次打开前先点一下 |
| 每月 750 小时额度 | 单实例够用（一个月 720 小时） | 别开第二个服务 |
| 内存 512MB | 够用（这个服务很轻） | — |

---

## 六、之后本机还要不要跑

两种用法，选一个：

**A. 只用云端**（推荐）
- 本机双击 `卸载开机自启.bat`，不再本机跑
- 以后就打开 `https://xxx.onrender.com`

**B. 本机 + 云端共用一份数据**
- 本机启动时也带上同样两个环境变量，两边读写同一个 Gist
- 做法：新建 `启动服务-云端.bat`，内容：
  ```bat
  set GIST_ID=你的GistID
  set GITHUB_TOKEN=github_pat_xxx
  cd /d %~dp0server
  python server.py
  ```
- 注意：两边同时写可能打架（按时间戳合并，晚的赢），不要两边同时改同一天

---

## 七、常见问题

**部署失败，日志里 `Address already in use`**
→ 本地也带着 `PORT` 环境变量了。本地不要设 `PORT`，代码默认 8790。

**登录后进度是空的**
→ 检查 `GIST_ID` / `GITHUB_TOKEN` 是否填对；看 Render 日志有没有 `[backup] 失败`。

**Gist 里的文件没更新**
→ 写入后有 2 秒攒批延迟，等几秒再刷新。

**忘了密码**
→ 云端没有重置入口。改 Gist 里的 JSON 不现实，直接用另一个账号注册即可（数据各自独立）。
