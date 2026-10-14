# Illustrated_skill

个人 Markdown 笔记仓库。

在这个文件夹里新建 / 编辑 `.md` 笔记后，**保存即自动同步到 GitHub**，无需手动敲 `git commit` / `git push`。

---

## 自动同步怎么工作

| 机制 | 触发时机 | 作用 |
| --- | --- | --- |
| 文件监听 | 文件保存后约 **8 秒**（等编辑动作停下） | 秒级实时推送 |
| 空闲兜底 | 监听进程空闲每 **10 分钟** | 防止漏推 |
| 定时任务兜底 | 每 **10 分钟** | 万一监听进程挂了也能补上 |
| 开机自启 | 登录 Windows 时 | 重启电脑后无需手动开启 |

每次同步执行的动作：`git add -A` → 有改动就 `git commit` → `git pull --rebase` → `git push`。

> 这里同步的是**整个文件夹**的改动，不只是 `.md` 文件。

---

## 日常使用

正常写笔记就行，其它什么都不用管。

### 查看同步日志

```powershell
Get-Content "$env:USERPROFILE\Desktop\Illustrated_skill\.autosync\logs\autosync.log" -Tail 30 -Wait
```

### 手动立即同步一次

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File "$env:USERPROFILE\Desktop\Illustrated_skill\.autosync\AutoSync.ps1" -Once
```

### 查看自动同步任务状态

```powershell
Get-ScheduledTask -TaskName 'Illustrated_skill-AutoSync-*' |
    Select-Object TaskName, State
```

### 关闭 / 开启自动同步

```powershell
# 关闭
Get-ScheduledTask -TaskName 'Illustrated_skill-AutoSync-*' | Disable-ScheduledTask
Get-Process powershell -ErrorAction SilentlyContinue |
    Where-Object { $_.CommandLine -like '*AutoSync.ps1*' } | Stop-Process -Force

# 开启
Get-ScheduledTask -TaskName 'Illustrated_skill-AutoSync-*' | Enable-ScheduledTask
Start-ScheduledTask -TaskName 'Illustrated_skill-AutoSync-Watch'
```

---

## 手动 Git 操作（可选）

自动同步在后台跑着，但你随时可以自己敲 Git 命令，两者不会冲突（脚本内部有互斥锁）。

```powershell
git status          # 看当前改动
git log --oneline   # 看提交历史
```

---

## 注意事项

- 本仓库是 **Public（公开）**，任何改动都会被推到公开网络，**不要放密码、密钥、个人隐私资料**。
- 仓库地址：<https://github.com/Zfeng08/Illustrated_skill>
- 自动同步脚本位于 [`.autosync/`](.autosync/)，日志在 `.autosync/logs/`（已被 `.gitignore` 排除，不会上传）。
