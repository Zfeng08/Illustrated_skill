# 「上下文」页签去重

## 两个页签分别是谁

| 页签 | 来源插件 | 注册 | 内容 |
|---|---|---|---|
| 上下文（第 1 个） | dsh-context 0.84.0 | `conversation.view` id=`context`, order 20 | 完整仪表盘：上下文构成、统计、事件、趋势，另有 `/context` 命令 |
| 上下文（第 2 个） | billion-context 0.1.213 | `conversation.view` id=`bili-context`, order 30 | 小面板：当前压缩量/预算、上游状态，文案 "No context data yet…" |
| 编队 | dsh-context 0.84.0 | `conversation.view` id=`fleet`, order 30 | 多会话编队视图 |

## 现在的处理方式

关闭 **billion-context** 的重复页签，保留 dsh-context 的完整仪表盘。

改的是用户配置文件（不动 node_modules，不需要管理员权限）：

```
C:\Users\10625\.config\billion-context\billion-context.json
```

```json
{
  "providers": {},
  "dsh": {
    "contextTab": false
  }
}
```

对应代码里的开关：

```js
function dshContextTabEnabled(){
  const envRaw = process.env.BILI_DSH_CONTEXT_TAB;
  if (envRaw !== void 0) return !(envRaw.trim()==="0" || envRaw.trim().toLowerCase()==="false");
  return loadConfigFile().dsh?.contextTab !== false;
}
```

也可以不写配置文件，改用环境变量 `BILI_DSH_CONTEXT_TAB=0`（环境变量优先级更高）。

## 不受影响的功能

关掉的只是那个 Tab 的**渲染**。billion-context 的其他部分照常工作：

- 压缩闸门（compaction gate）
- 右上角上游状态浮层（`shell.overlay` id `bili-upstreams`）
- 设置里的「bili 上游状态」区块（`settings.section` id `bili`）
- `plugins.bundle.config` 配置入口

## 什么时候生效

`__BILI__` 全局变量在每次 `webserver/index-inject` 时重新计算，所以：

- **窗口内按 Ctrl+R 重载即可**，无需重启客户端、无需重新构建
- 如果 Ctrl+R 后没变，再关掉 DSH 重开一次

## 脚本

```
只留一个上下文.cmd    →  dsh.contextTab = false（当前状态）
恢复两个上下文.cmd    →  dsh.contextTab = true
```

两者都调用 `set-context-tab.ps1`：

- 先 `ConvertFrom-Json` 校验，配置坏了就拒绝改写
- 每次改动前在同目录留一份 `billion-context.json.bak-<时间戳>`
- 用 OrderedDictionary 保留 `providers` 的顺序，只增改 `dsh` 里的键
- 自写 JSON 格式化（PS 5.1 的 `ConvertTo-Json` 缩进很怪），UTF-8 无 BOM 写回

## 如果有天你想反过来

想留 billion-context 的 Tab、去掉 dsh-context 的，**不用改代码**：dsh-context 自带
`defaultPlacement: all | tab | sidebar | hide` 设置，把它设成 `hide`（或 `sidebar` 挪到右栏），
再把本文件的 `contextTab` 改回 `true` 即可。

## 备份

`billion-context.json.bak-20261113-224516` 是最初的原始配置（只有 `{"providers": {}}`）。
直接覆盖回 `billion-context.json` 就能完全复原。
