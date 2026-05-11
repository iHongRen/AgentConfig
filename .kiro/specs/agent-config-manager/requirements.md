# AgentConfig 需求文档

## Introduction

AgentConfig 是一款 macOS 原生应用，用于集中管理本地安装的 AI Coding Agent 的配置文件及系统环境变量文件。用户可以在一个统一界面中浏览、编辑、版本管理所有相关配置，无需在终端和多个编辑器之间来回切换。

### 术语表

| 术语 | 定义 |
|------|------|
| Code Agent | 本地安装的 AI 编程助手工具，如 Claude Code、Qwen Code、Codex CLI 等 |
| 配置文件 | Code Agent 或系统使用的 JSON、TOML、YAML、Shell 等格式的配置文件 |
| 环境变量文件 | Shell 启动脚本，如 `.zshrc`、`.bashrc`、`.bash_profile` 等 |
| source | Shell 命令，用于在当前 Shell 会话中重新加载配置文件 |
| Git | 版本控制系统，用于追踪文件变更历史 |

---

## Requirements

### Requirement 1: 自动检测 Code Agent 配置文件

**User Story:** 作为用户，我希望应用能自动检测本地已安装的 AI Coding Agent 并找到其配置文件，这样我无需手动查找配置文件路径。

#### Acceptance Criteria

1. 应用启动时，SHALL 自动扫描以下已知 Code Agent 的配置文件路径：
   - **Claude Code**：`~/.claude/`, `~/.config/claude/`, `~/Library/Application Support/Claude/`
   - **Qwen Code**：`~/.qwen/`, `~/.config/qwen/`
   - **Codex CLI**：`~/.codex/`, `~/.config/codex/`
   - **OpenCode CLI**：`~/.opencode/`, `~/.config/opencode/`
   - **GitHub Copilot**：`~/.config/github-copilot/`
   - **Cursor**：`~/Library/Application Support/Cursor/User/`
   - **Continue**：`~/.continue/`
   - **Cody**：`~/.config/cody/`
   - **Aider**：`~/.aider/`, `~/.aider.conf.yml`
   - **Gemini CLI**：`~/.gemini/`, `~/.config/gemini/`
   - **Amazon Q / CodeWhisperer**：`~/.aws/amazonq/`
2. WHEN 某个 Code Agent 的配置目录存在时，THE 应用 SHALL 将其列入对应分类，并显示该目录下所有配置文件（递归深度不超过 2 层）。
3. IF 某个 Code Agent 未安装（配置目录不存在），THE 应用 SHALL 不显示该分类，避免空分类干扰用户。
4. 应用 SHALL 支持用户手动添加自定义配置文件路径，以覆盖未被自动检测到的 Code Agent。
5. WHEN 用户点击"刷新"按钮时，THE 应用 SHALL 重新扫描所有路径并在 3 秒内更新分类列表。
6. 文件类型判断 SHALL 优先依据文件扩展名（`.json`、`.yaml`、`.toml` 等），无扩展名时依据文件名（如 `.zshrc`）。

#### Correctness Properties

- **P1.1**：对于每个已知 Code Agent，若其配置目录存在，则该 Agent 的分类必须出现在列表中。
- **P1.2**：若配置目录不存在，则该 Agent 的分类不得出现在列表中。

---

### Requirement 2: 环境变量文件分类管理

**User Story:** 作为用户，我希望环境变量配置文件（如 `.zshrc`）单独归为一类，这样我可以快速找到并编辑它们。

#### Acceptance Criteria

1. 应用 SHALL 自动检测以下环境变量文件（若存在）：
   - `~/.zshrc`、`~/.zprofile`、`~/.zshenv`
   - `~/.bashrc`、`~/.bash_profile`、`~/.bash_login`
   - `~/.profile`
   - `~/.config/fish/config.fish`
2. 环境变量文件 SHALL 归入独立的"环境变量"分类，与 Code Agent 分类并列显示，且排列在分类列表顶部。
3. WHEN 某个环境变量文件不存在时，THE 应用 SHALL 提供"创建"选项，允许用户新建该文件。
4. 每个分类 SHALL 显示其包含的文件数量，数量必须与实际文件数量一致。

#### Correctness Properties

- **P2.1**：环境变量文件分类必须与 Code Agent 分类相互独立，不得混合。
- **P2.2**：文件数量显示必须与实际文件数量一致。

---

### Requirement 3: 代码编辑器

**User Story:** 作为用户，我希望有一个功能完善的编辑器来查看和编辑配置文件，这样我可以高效地修改配置内容。

#### Acceptance Criteria

1. 编辑器 SHALL 显示行号，行号与对应代码行左对齐，行号列宽随文件行数自动调整。
2. 编辑器 SHALL 对以下文件类型提供语法高亮：JSON/JSONC、YAML/TOML、Shell 脚本（`.sh`、`.zsh`、`.bash`）、环境变量文件（无扩展名的 Shell 配置文件）；无法识别的文件类型显示纯文本（无高亮）。
3. 编辑器 SHALL 提供搜索功能（快捷键 Cmd+F），支持：关键词高亮匹配、上一个/下一个导航（Cmd+G / Cmd+Shift+G）、大小写敏感开关；IF 无匹配结果，SHALL 显示"未找到"提示。
4. IF 当前文件扩展名为 `.json` 或 `.jsonc`，THE 编辑器 SHALL 在工具栏显示"格式化"按钮，点击后将 JSON 内容格式化为 2 空格缩进。
5. IF JSON 内容格式化失败（语法错误），THE 编辑器 SHALL 显示包含错误行列位置的错误提示，不修改原内容。
6. 编辑器 SHALL 支持撤销（Cmd+Z）和重做（Cmd+Shift+Z），撤销历史步数不少于 100 步。
7. WHEN 内容被修改但未保存时，THE 编辑器 SHALL 在标题栏或标签页显示"●"标记；WHEN 文件保存成功后，THE 编辑器 SHALL 移除该标记。

#### Correctness Properties

- **P3.1**：格式化操作必须是幂等的——对已格式化的 JSON 再次格式化，结果不变。
- **P3.2**：搜索结果必须覆盖文件中所有匹配项，不得遗漏。

---

### Requirement 4: 保存并自动 source 环境变量文件

**User Story:** 作为用户，我希望保存环境变量文件后，修改能立即在当前终端会话中生效，这样我无需手动执行 source 命令。

#### Acceptance Criteria

1. WHEN 用户保存环境变量分类下的文件时，THE 应用 SHALL 先将内容写入磁盘，写入成功后再执行 `source <文件路径>` 命令。
2. 应用 SHALL 在保存后以非阻塞方式显示 source 执行结果（成功提示或失败详情），提示在 3 秒后自动消失。
3. IF source 执行失败，THE 应用 SHALL 显示包含错误输出的详情，但不回滚文件保存。
4. 应用 SHALL 仅对"环境变量"分类下的文件执行 source，不对 Code Agent 配置文件执行。
5. 用户 SHALL 能在应用设置中关闭"自动 source"功能，关闭后保存仅写入磁盘，不执行 source。

#### Correctness Properties

- **P4.1**：source 操作必须在文件写入成功后才执行，不得在写入失败时执行。
- **P4.2**：source 失败不得导致文件内容丢失。

---

### Requirement 5: 浅色与深色模式

**User Story:** 作为用户，我希望应用能跟随系统的浅色/深色模式，这样视觉体验与其他应用保持一致。

#### Acceptance Criteria

1. 应用 SHALL 默认跟随 macOS 系统的外观设置（浅色/深色）。
2. 用户 SHALL 能在应用设置中手动切换浅色、深色或跟随系统三种模式，切换后立即生效，无需重启。
3. WHEN 系统外观切换时且应用处于"跟随系统"模式时，THE 应用 SHALL 实时更新界面颜色。
4. 编辑器的语法高亮配色 SHALL 在浅色模式下使用亮色主题，在深色模式下使用暗色主题。

#### Correctness Properties

- **P5.1**：在深色模式下，所有文字与背景的对比度必须符合 WCAG AA 标准（对比度 ≥ 4.5:1）。

---

### Requirement 6: 国际化（中文 / 英文）

**User Story:** 作为用户，我希望应用支持中文和英文界面，这样不同语言偏好的用户都能舒适使用。

#### Acceptance Criteria

1. 应用 SHALL 支持简体中文（`zh-Hans`）和英文（`en`）两种语言。
2. 应用 SHALL 默认跟随 macOS 系统语言设置；IF 系统语言不在支持列表中，SHALL 回退到英文。
3. 用户 SHALL 能在应用设置中手动切换语言，切换后立即强制生效，无需重启，无论当前是否有未保存的编辑内容或复杂 UI 状态。
4. 所有 UI 文字、按钮标签、错误提示、帮助文本 SHALL 均提供中英文翻译，不得出现硬编码字符串。
5. 日期和时间格式 SHALL 根据所选语言/地区自动适配（中文使用 `yyyy年MM月dd日`，英文使用 `MMM d, yyyy`）。

#### Correctness Properties

- **P6.1**：切换语言后，界面中不得出现未翻译的硬编码字符串。

---

### Requirement 7: Git 版本历史与恢复

**User Story:** 作为用户，我希望能查看配置文件的 Git 提交历史、对比差异并恢复到指定版本，这样我可以安全地回滚误操作。

#### Acceptance Criteria

1. WHEN 配置文件所在目录是 Git 仓库时，THE 应用 SHALL 在编辑器工具栏显示"历史记录"按钮。
2. 历史记录视图 SHALL 列出该文件的所有 Git 提交，每条记录显示：提交哈希（短，7位）、提交信息、作者、相对时间（如"2小时前"）。
3. WHEN 用户选择某条历史记录时，THE 应用 SHALL 以并排或内联方式显示该提交与当前版本的 diff，新增行高亮为绿色，删除行高亮为红色。
4. 用户 SHALL 能将文件恢复到指定提交的版本，恢复前 SHALL 弹出确认对话框，确认后将文件内容替换为该提交版本并标记为"未保存"。
5. IF 配置文件所在目录不是 Git 仓库，THE 应用 SHALL 提供"初始化 Git 仓库"选项，点击后在该目录执行 `git init`。
6. WHEN 用户保存文件且该目录已是 Git 仓库时，THE 应用 SHALL 自动执行 `git add <文件>` 和 `git commit -m "Auto-save: <ISO8601时间戳>"`。

#### Correctness Properties

- **P7.1**：恢复操作必须将文件内容精确还原为指定提交时的状态，与 `git show <hash>:<file>` 输出一致。
- **P7.2**：diff 视图必须准确反映两个版本之间的所有差异，不得有遗漏或误报。

---

### Requirement 8: 实时文件同步

**User Story:** 作为用户，我希望在其他编辑器修改配置文件后，切换回本应用时能自动看到最新内容，这样我不会因为内容不同步而产生困惑。

#### Acceptance Criteria

1. 应用 SHALL 使用 macOS FSEvents 或 `DispatchSource` 监控所有已打开文件的变更。
2. WHEN 外部程序修改了当前打开的文件时，THE 应用 SHALL 在 1 秒内检测到变更。
3. IF 当前文件在应用内有未保存的修改，WHEN 检测到外部变更时，THE 应用 SHALL 弹出提示，让用户选择"保留本地修改"或"加载外部版本"，不得自动覆盖。
4. IF 当前文件在应用内没有未保存的修改，WHEN 检测到外部变更时，THE 应用 SHALL 自动静默刷新文件内容，不打断用户操作。
5. WHEN 应用从后台切换到前台时，THE 应用 SHALL 主动检查所有已打开文件的修改时间，若有变更则按标准 3 或 4 处理。

#### Correctness Properties

- **P8.1**：自动刷新后，编辑器显示的内容必须与磁盘文件内容完全一致（字节级别）。
- **P8.2**：在有未保存修改的情况下，自动刷新不得在未经用户确认的情况下覆盖本地修改。

---

### Requirement 9: 关于页面

**User Story:** 作为用户，我希望能查看应用的作者信息、版本号和帮助文档，这样我可以了解应用背景并获取使用指引。

#### Acceptance Criteria

1. 应用 SHALL 在 macOS 菜单栏"AgentConfig > 关于 AgentConfig"中提供关于页面入口。
2. 关于页面 SHALL 显示：应用名称和图标、版本号（与 `CFBundleShortVersionString` 一致）和构建号、作者姓名和 GitHub 链接、开源协议（MIT）信息。
3. 关于页面 SHALL 包含"帮助"区域，提供：支持的 Code Agent 列表及其配置文件路径说明、常见问题解答（FAQ，至少 5 条）、快捷键列表。
4. 帮助内容 SHALL 支持中英文国际化，随应用语言设置切换。

#### Correctness Properties

- **P9.1**：版本号显示必须与 `Info.plist` 中的 `CFBundleShortVersionString` 一致。
