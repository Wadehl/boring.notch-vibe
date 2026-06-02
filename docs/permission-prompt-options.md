# Permission Prompt 选项渲染逻辑

Claude Code 在请求工具权限时，会根据工具类型和操作路径动态生成选项。boringNotch 在 `AgentStatusManager` 中复现了这套逻辑。

## 数据来源

Session JSON (`~/.claude/sessions/<pid>.json`) 的 `waitingFor` 字段为 `"permission prompt"` 时触发。  
具体工具信息从对应 JSONL 的最后一条未被响应的 `assistant` → `tool_use` 中读取。

JSONL 路径：`~/.claude/projects/<encoded-cwd>/<sessionId>.jsonl`

## 选项结构

所有工具均固定：
- **选项 1**：`Yes`（按键 `y`）
- **选项 N**：`No`（按键 `n`）

中间选项（option 2）根据工具和路径动态生成，可能不存在。

---

## 文件类工具（Write / Edit / NotebookEdit / Read）

对应 Claude Code 源码的 `rK4` 函数。

| 场景 | operationType | 选项 2 文案 | 按键 |
|------|--------------|-------------|------|
| 文件在 `~/.claude/` 内（配置文件）| write | `Yes, and allow Claude to edit its own settings for this session` | `a` |
| 文件在 cwd 内 | read | `Yes, during this session` | `a` |
| 文件在 cwd 内 | write | `Yes, allow all edits during this session` | `a` |
| 文件在 cwd 外 | read | `Yes, allow reading from <dirname>/ during this session` | `a` |
| 文件在 cwd 外 | write | `Yes, allow all edits in <dirname>/ during this session` | `a` |

`<dirname>` 取文件父目录的最后一段路径名（`path.basename(dir)`）。

### Read 工具

operationType = `"read"`，走上表 read 分支。

---

## Bash 工具

对应 Claude Code 源码的 `fK4` + `Py6` 函数组合。

Claude Code 实际用 LLM 提取命令前缀（prefix），boringNotch 用启发式替代：扫描命令 token 中首个以 `/` 开头、且不在 cwd 内的绝对路径。

| 场景 | 选项 2 文案 |
|------|------------|
| 命令含 cwd 外的绝对路径 | `Yes, allow reading from <dirname>/ from this project` |
| 无 cwd 外路径（普通命令）| 无选项 2，只显示 Yes / No |

`<dirname>` 取该路径父目录的最后一段名称。

---

## WebFetch 工具

WebFetch 有独立的 permission UI，与文件类工具完全不同。

| 选项 | 文案 | 按键 |
|------|------|------|
| 1 | `Yes` | `y` |
| 2 | `Yes, and don't ask again for <domain>` | `a` |
| 3 | `No, and tell Claude what to do differently` | `n` |

`<domain>` 取 URL 的 hostname（如 `example.com`）。

question 显示格式：`url: "<url>", prompt: "<prompt>"`（与 Claude Code 界面一致）。

---

## question 字段（卡片显示文案）

| 工具 | 显示格式 |
|------|---------|
| Bash | `<description>: <command>` 或直接 `<command>` |
| Write / Edit / NotebookEdit | `Write(/path/to/file)` |
| Read | `Read(/path/to/file)` |
| WebFetch | `url: "<url>", prompt: "<prompt>"` |
| 其他 | 工具名本身 |

---

## 实现位置

- 选项生成：`AgentStatusManager.swift` → `detectPermissionInteraction` / `permissionOptions` / `filePermissionOption2` / `bashPermissionOption2`
- 渲染：`AgentInteractionView.swift` → `questionContent` → `optionChips`（与 AskUserQuestion 共用同一套 chip 渲染）

## 参考

Claude Code 源码（从 binary 逆向）关键函数：
- `rK4`：文件工具选项构建
- `fK4`：Bash 工具选项构建  
- `Py6`：Bash suggestion → label 转换

---

## TODO：各场景验收测试

- [x] Write - cwd 内（`Yes, allow all edits during this session`）
- [x] Write - cwd 外（`Yes, allow all edits in <dirname>/ during this session`）
- [x] Write - ~/.claude/ 内（`Yes, and allow Claude to edit its own settings for this session`）
- [x] Read - cwd 外（`Yes, allow reading from <dirname>/ during this session`）
- [x] Bash - 普通命令（只有 Yes / No）
- [x] Bash - 含 cwd 外绝对路径（`Yes, allow reading from <dirname>/ from this project`）
- [x] WebFetch（`Yes, and don't ask again for <domain>`）
