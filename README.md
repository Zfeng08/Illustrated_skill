# Illustrated_skill

个人 Markdown 笔记仓库 · <https://github.com/Zfeng08/Illustrated_skill>

在这个文件夹里新建 / 编辑 `.md` 笔记后，**保存即自动同步到 GitHub**，无需手动敲 `git commit` / `git push`。

---

## 自动同步怎么工作

装了两个 Windows 计划任务（都已注册并正在运行）：

| 任务名 | 触发时机 | 作用 |
| --- | --- | --- |
| `Illustrated_skill-AutoSync-Watch` | 登录 Windows 时启动，常驻 | 文件保存后约 **8 秒**自动推送 |
| `Illustrated_skill-AutoSync-Fallback` | 每 **10 分钟** | 兜底同步；发现监听进程挂了就自动重启它 |

每次同步执行的动作：

```
git add -A  →  有改动就 git commit  →  git pull --rebase  →  git push
```

> 同步的是**整个文件夹**的改动，不只是 `.md` 文件。新增、修改、删除、重命名都会同步。

---

## 日常使用

正常写笔记就行，其它什么都不用管。

### 查看同步日志（实时滚动）

```powershell
Get-Content "$env:USERPROFILE\Desktop\Illustrated_skill\.autosync\logs\autosync.log" -Tail 30 -Wait -Encoding UTF8
```

### 手动立即同步一次

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File "$env:USERPROFILE\Desktop\Illustrated_skill\.autosync\AutoSync.ps1" -Once
```

### 查看自动同步任务状态

```powershell
Get-ScheduledTask -TaskName 'Illustrated_skill-AutoSync-*' | Select-Object TaskName, State
```

### 关闭自动同步

```powershell
# 1. 停掉两个计划任务
Get-ScheduledTask -TaskName 'Illustrated_skill-AutoSync-*' | Disable-ScheduledTask
Get-ScheduledTask -TaskName 'Illustrated_skill-AutoSync-Watch' | Stop-ScheduledTask

# 2. 结束还在运行的监听进程（Get-Process 在 PowerShell 5.1 上拿不到 CommandLine，所以用 CIM）
Get-CimInstance Win32_Process -Filter "Name='powershell.exe'" |
    Where-Object { $_.CommandLine -like '*-File*AutoSync.ps1*' } |
    ForEach-Object { Stop-Process -Id $_.ProcessId -Force }
```

### 重新开启

```powershell
Get-ScheduledTask -TaskName 'Illustrated_skill-AutoSync-*' | Enable-ScheduledTask
Start-ScheduledTask -TaskName 'Illustrated_skill-AutoSync-Watch'
```

### 换电脑 / 计划任务丢了，重新注册

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File "$env:USERPROFILE\Desktop\Illustrated_skill\.autosync\Register-AutoSync.ps1"
```

卸载这两个任务（`-Unregister`）：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File "$env:USERPROFILE\Desktop\Illustrated_skill\.autosync\Register-AutoSync.ps1" -Unregister
```

---

## 手动 Git 操作（可选）

后台的自动同步和你自己敲 Git 命令不会冲突（脚本内部有跨进程互斥锁）。

```powershell
git status          # 看当前改动
git log --oneline   # 看提交历史
```

---

## 文件说明

| 路径 | 说明 |
| --- | --- |
| `README.md` | 本文件 |
| `笔记/` | 你的笔记（可以随意新建子文件夹） |
| `.autosync/AutoSync.ps1` | 核心同步脚本，默认是「监听模式」，`-Once` 则只同步一次 |
| `.autosync/FallbackSync.ps1` | 兜底入口：同步一次 + 确认监听进程还活着 |
| `.autosync/Register-AutoSync.ps1` | 注册 / 卸载计划任务 |
| `.autosync/logs/autosync.log` | 同步日志（已 gitignore，不会上传） |

---

## 注意事项

- 本仓库是 **Public（公开）**，任何改动都会被推到公开网络，**不要放密码、密钥、个人隐私资料**。
- 单个文件不要超过 100 MB（GitHub 硬限制），否则推送会一直失败并每 10 分钟重试一次。
- 断网时改动会先攒在本地，联网后由下一次同步自动补推。
- 如果保存后超过 1 分钟还没同步，先看 `.autosync\logs\autosync.log` 的最后几行。
- 本仓库的 Git 凭据单独指向 `gh` CLI 的 **Zfeng08** 账号（配置在 `.git/config` 里），
  不影响这台电脑上其它仓库使用的凭据。
