# 部署到 Hugging Face Spaces（免费、不要信用卡、地址固定）

目标：`https://你的用户名-agent-study.hf.space` —— 任何电脑、任何时间都能打开，**不用开着自家电脑**。

数据存在你自己的私有 Gist 里（Space 重启不丢），代码在 Space 里跑。

---

## 一、准备（5 分钟）

### 1. 注册 Hugging Face

打开 <https://huggingface.co/join>，可以直接用 GitHub 账号登录。

### 2. 建 Gist（当数据库）——如果已经有就跳过

1. <https://gist.github.com> → 文件名 `studydb.json`，内容 `{}`
2. **Create secret gist**
3. 地址栏末尾那 32 位就是 `GIST_ID`

### 3. 生成 token（只给 Gist 权限）

1. <https://github.com/settings/tokens?type=beta> → Generate new token
2. **Account permissions → Gists → Read and write**
3. 复制 `github_pat_...`（只显示一次，别多复制空格或换行）

---

## 二、建 Space

1. 打开 <https://huggingface.co/new-space>
2. 填：

| 字段 | 值 |
|---|---|
| Space name | `agent-study` |
| License | 随便选（如 mit） |
| SDK | **Docker** |
| Docker template | **Blank** |
| Space hardware | **CPU basic · 2 vCPU · 16GB · FREE** |
| Visibility | **Public**（免费版只能公开） |

3. 点 **Create Space**

---

## 三、上传文件

Space 建好后进入 **Files** 标签 → **Add file** → **Upload files**。

把本机这个目录里的**全部文件和文件夹**拖进去：

```
D:\dsh-workspace\projects\ai-agent-plan-v2\hf-space\
├─ Dockerfile
├─ README.md
├─ requirements.txt
└─ server\
   ├─ server.py
   └─ web\
      └─ index.html
```

**注意目录结构不能变**：`server` 文件夹要整体拖进去，里面还有 `web/index.html`。

拖完点 **Commit changes to main**。

---

## 四、配置两个 Secret

Space 页面 → **Settings** → **Variables and secrets** → **New secret**，加两条：

| Name | Value |
|---|---|
| `GIST_ID` | 那 32 位 |
| `GITHUB_TOKEN` | `github_pat_...` |

加完 Space 会自动重新构建。

---

## 五、等构建

切到 **Logs** 标签看进度，一般 2-5 分钟。看到类似：

```
Agent 学习监督 · 服务已启动
电脑端： http://127.0.0.1:7860
```

就成了。地址是：

```
https://<你的HF用户名>-agent-study.hf.space
```

打开 → 登录页 → 用 `陈禹竹` / `230319`（第一次会自动建号）。

---

## 六、以后怎么验证数据真的存住了

1. 打开网址，勾一个打卡
2. 等 5 秒
3. 去 Gist 页面刷新，`studydb.json` 里应该出现 `"users"`、`"state"`、你刚勾的那天

如果 Gist 一直是 `{}`，去 Space 的 Logs 看有没有：

```
[backup] 失败：...
```

有的话八成是 token 权限没给够（要 Gists: Read and write）。

---

## 七、免费版的限制

| 限制 | 影响 | 应对 |
|---|---|---|
| 空闲 48 小时后休眠 | 下次打开要等 30-60 秒唤醒 | 正常现象，等一下 |
| 磁盘是临时的 | 重启就清空 | 已经用 Gist 兜住，会自动恢复 |
| Space 必须公开 | 别人能看到你的代码和登录页 | 有密码保护；数据在私有 Gist |
| 2 vCPU / 16GB | 够用（这个服务很轻） | — |

---

## 八、本机和云端怎么共存

两条路，选一条：

**A. 只用云端（推荐，最省心）**
- 本机双击 `卸载开机自启.bat`
- 以后就开 `https://xxx.hf.space`

**B. 本机也用云端同一份数据**
- 改 `启动服务.bat`，在开头加两行：
  ```bat
  set GIST_ID=你的GistID
  set GITHUB_TOKEN=github_pat_xxx
  ```
- 这样本机读写同一个 Gist，和云端完全同步

> ⚠️ 不要"本机用 SQLite、云端用 Gist"两边同时记 —— 那是两份互不相干的数据。
