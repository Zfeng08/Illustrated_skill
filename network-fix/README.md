# 网络配置说明（2026-11-13）

## 当前状态

| 项目 | 值 |
|---|---|
| Cloudflare WARP | **开启**（Connected / healthy），服务启动类型 Automatic |
| DNS | `127.0.2.2` / `127.0.2.3`（WARP 内置 DoH 代理） |
| 隧道路由 | 15 条（Cloudflare CDN、GitHub、Google 等走隧道） |
| hosts | 已无 GitHub 固定（注释已清理，走 WARP 隧道解析） |
| 默认网关 | 192.168.0.1（WLAN） |

## 为什么是这个状态

WARP 的分流表（include 列表）由 Cloudflare Zero Trust 策略下发，**本地无法修改**：

```
warp-cli tunnel ip remove-range 104.16.0.0/12
→ Not yet implemented.
```

所以只有两种可选状态，没有中间路线：

| 状态 | GitHub / Google | Cloudflare 系网站 | 国内网站 |
|---|---|---|---|
| **WARP 开**（当前） | ✅ 可用（1~1.8s） | ❌ 2.2s 偏慢 | ✅ 0.06~0.35s |
| WARP 关 | ❌ GitHub 直连不通、Google 不可用 | ✅ 1.4s | ✅ 0.04~0.3s |

实测过：直连 GitHub 时，IP 扫出来能通、但**几十秒内就会被切断**（连发 8 次全部超时），属于链路层的动态阻断，固定 hosts 无效。

## 脚本

| 脚本 | 作用 |
|---|---|
| `open-WARP.cmd` | 开启 WARP。需要 GitHub / Google / YouTube 时用 |
| `close-WARP.cmd` | 关闭 WARP + DNS 改回 223.5.5.5。追求国内/Cloudflare 站点速度时用 |
| `restore-all.cmd` | 恢复到最初原始配置（hosts / DNS / 服务启动类型） |
| `fix-github.cmd` | **仅在 WARP 关闭时有用**：自动扫描可用 GitHub IP 并写入 hosts |
| `apply-fix.ps1` | 一次性修复脚本（已执行过，保留备查） |
| `restore-github.ps1` | 恢复 WARP 并清理 GitHub hosts 固定（已执行过） |

## 备份

- `backup-20261113-150231\` — 第一轮修改前的原始 hosts / DNS / 路由表 / 服务配置
- `backup-20261113-16xxxx\` — 后续每次修改前的 hosts

## 想要两边都快

需要换用支持规则分流的代理客户端（Clash / sing-box 等）配香港或新加坡节点，
把 Cloudflare CDN 域名指向国内直连、只让 GitHub/Google 走代理。
WARP 做不到这件事。
