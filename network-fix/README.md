# 网络配置说明（2026-11-15 更新）

## 当前状态

| 项目 | 值 |
|---|---|
| Cloudflare WARP | **开启**（Connected / healthy），服务启动类型 Automatic |
| DNS | `127.0.2.2` / `127.0.2.3`（WARP 内置 DoH 代理） |
| 隧道路由 | 15 条（Cloudflare CDN、GitHub、Google 等走隧道） |
| hosts | GitHub 段已由 `fix-github2.ps1` 写入（见下），受管标记包围 |
| 默认网关 | 192.168.0.1（WLAN） |

## 2026-11-15 这次「GitHub 又打不开」的根因

WARP 一直是 Connected/healthy，问题不在隧道，在 **DNS**：

| 查询方式 | github.com 返回 | 结论 |
|---|---|---|
| WARP DoH（127.0.2.2） | 4.236.95.112 | 假 IP，443 不通 |
| 223.5.5.5 | 20.247.166.64 | 假 IP |
| 119.29.29.29 / 8.8.8.8 | 20.6.7.17 | 假 IP |
| 1.1.1.1 | 20.172.24.160 | 假 IP |

四个解析器四个不同答案，全部连接超时 —— 典型的 DNS 污染。真实 GitHub 在
`140.82.112.0/20`：那一段 9 个 IP 逐个做了**内容校验**（首页 525KB、含 `github` 字样），全部真实可用。

所以修复方式仍然是 hosts 固定，但要做对两件事：

1. **不能只看 HTTP 状态码** —— 污染/劫持会返回 200，但内容是空的或假的。v1 的 `fix-github.ps1` 就吃了这个亏。
2. **要覆盖 GitHub 真正用到的全部域名**，只固定 `github.com` 会出现「首页能开、登录页白屏、头像裂图、clone 失败」。

v2 的校验规则：严格组（`github.com`、`api`、`raw`）要求 `200` + 最小字节数 + 内容特征串；
宽松组（`codeload`、`gist`、`githubassets`）只要 TLS 握手成功且返回 2xx/3xx/404 即可。

## 为什么是这个状态

WARP 的分流表（include 列表）由 Cloudflare Zero Trust 策略下发，**本地无法修改**：

```
warp-cli tunnel ip remove-range 104.16.0.0/12
→ Not yet implemented.
```

所以只有两种可选状态，没有中间路线：

| 状态 | GitHub / Google | Cloudflare 系网站 | 国内网站 |
|---|---|---|---|
| **WARP 开**（当前） | ✅ 可用（首页 2.8s / 登录 2.1s，经 LAX） | ❌ 2.2s 偏慢 | ✅ 0.06~0.35s |
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
| `一键修复GitHub.cmd` | **推荐**：提权运行 `fix-github2.ps1`，内容校验 + 全域名固定 + 写后验证 |
| `fix-github2.ps1` | 上者调用的脚本。`-ProbeOnly` 只探测不改 hosts，`-NoPause` 不等待回车 |

### hosts 会被写成这样

```
# >>> github-pins (managed) >>>
140.82.112.3	github.com
140.82.112.3	www.github.com
140.82.114.5	api.github.com
140.82.112.9	codeload.github.com
140.82.113.3	gist.github.com
185.199.110.133	raw.githubusercontent.com       (+ 13 个 *.githubusercontent.com)
185.199.110.154	github.githubassets.com
# <<< github-pins (managed) <<<
```

标记块每次重跑都整体替换，不会越积越多；删掉标记块之间的内容就完全回到系统默认。

**注意**：`nslookup github.com` 仍然会显示污染后的 IP，因为 nslookup 直接问 DNS 服务器、
不读 hosts。要看真实生效结果请用 `curl -v https://github.com`（看 `Trying` 那一行的 IP）。

## 备份

- `backup-20261113-150231\` — 第一轮修改前的原始 hosts / DNS / 路由表 / 服务配置
- `backup-20261113-16xxxx\` — 后续每次修改前的 hosts

## 想要两边都快

需要换用支持规则分流的代理客户端（Clash / sing-box 等）配香港或新加坡节点，
把 Cloudflare CDN 域名指向国内直连、只让 GitHub/Google 走代理。
WARP 做不到这件事。
