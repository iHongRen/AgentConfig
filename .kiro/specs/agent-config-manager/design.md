# AgentConfig 设计文档

## Overview

AgentConfig 是一款 macOS 原生 SwiftUI 应用，为本地 AI Coding Agent 的配置文件提供统一管理界面。应用采用三栏布局（分类列表 / 文件列表 / 编辑器），支持自动检测已安装 Agent、代码编辑、Git 版本历史、实时文件同步、环境变量 source 等功能。

技术栈：
- **语言**：Swift 5.9+
- **UI 框架**：SwiftUI（macOS 13 Ventura+）
- **并发模型**：Swift Concurrency（async/await、Actor）
- **文件监控**：FSEvents（通过 `DispatchSource`）
- **Git 集成**：调用系统 `git` 命令行工具（`Process`）
- **测试框架**：Swift Testing（Xcode 16+）+ SwiftCheck（属性测试）

---

## Architecture

应用采用 **MVVM + Repository** 分层架构：

```
┌─────────────────────────────────────────────────────┐
│                    SwiftUI Views                     │
│  SidebarView │ FileListView │ EditorView │ Settings  │
└──────────────────────┬──────────────────────────────┘
                       │ @StateObject / @ObservedObject
┌──────────────────────▼──────────────────────────────┐
│                   ViewModels                         │
│  AppViewModel │ EditorViewModel │ GitViewModel       │
└──────────────────────┬──────────────────────────────┘
                       │ async/await
┌──────────────────────▼──────────────────────────────┐
│                   Services                           │
│  AgentScanner │ FileService │ GitService │ SourceRunner│
└──────────────────────┬──────────────────────────────┘
                       │
┌──────────────────────▼──────────────────────────────┐
│                  Foundation Layer                    │
│  FileManager │ Process │ FSEvents │ UserDefaults     │
└─────────────────────────────────────────────────────┘
```

### 数据流

```
用户操作 → View → ViewModel.action() → Service.method() → 文件系统/Git
                                    ↓
                              @Published 属性更新
                                    ↓
                              View 自动重渲染
```

---

## Components and Interfaces

### 1. AgentScanner（Agent 扫描服务）

负责检测已安装的 Code Agent 并枚举其配置文件。

```swift
protocol AgentScannerProtocol {
    func scan() async -> [AgentCategory]
    func scanEnvFiles() async -> EnvCategory
}

struct AgentCategory: Identifiable, Equatable {
    let id: String          // Agent 名称，如 "claude"
    let displayName: String
    let files: [ConfigFile]
}

struct EnvCategory: Equatable {
    let files: [ConfigFile]
    let missingPaths: [URL]  // 不存在但可创建的路径
}

struct ConfigFile: Identifiable, Equatable {
    let id: UUID
    let url: URL
    let fileType: FileType
    var isModified: Bool
}

enum FileType: Equatable {
    case json, jsonc, yaml, toml, shell, plainText
}
```

**已知 Agent 路径表**（静态配置，`AgentDefinitions.swift`）：

| Agent | 检测路径 |
|-------|---------|
| Claude Code | `~/.claude/`, `~/.config/claude/`, `~/Library/Application Support/Claude/` |
| Qwen Code | `~/.qwen/`, `~/.config/qwen/` |
| Codex CLI | `~/.codex/`, `~/.config/codex/` |
| OpenCode CLI | `~/.opencode/`, `~/.config/opencode/` |
| GitHub Copilot | `~/.config/github-copilot/` |
| Cursor | `~/Library/Application Support/Cursor/User/` |
| Continue | `~/.continue/` |
| Cody | `~/.config/cody/` |
| Aider | `~/.aider/`, `~/.aider.conf.yml` |
| Gemini CLI | `~/.gemini/`, `~/.config/gemini/` |
| Amazon Q | `~/.aws/amazonq/` |

**文件类型判断逻辑**：
1. 优先检查扩展名：`.json`/`.jsonc` → `.json`/`.jsonc`；`.yaml`/`.yml` → `.yaml`；`.toml` → `.toml`；`.sh`/`.zsh`/`.bash` → `.shell`
2. 无扩展名时检查文件名：`.zshrc`、`.bashrc`、`.profile` 等 → `.shell`
3. 其他 → `.plainText`

### 2. FileService（文件读写服务）

```swift
protocol FileServiceProtocol {
    func read(url: URL) async throws -> String
    func write(content: String, to url: URL) async throws
    func create(at url: URL) async throws
    func modificationDate(of url: URL) -> Date?
}
```

### 3. GitService（Git 操作服务）

封装对系统 `git` 命令的调用，所有操作通过 `Process` 异步执行。

```swift
protocol GitServiceProtocol {
    func isGitRepo(at url: URL) async -> Bool
    func initRepo(at url: URL) async throws
    func log(for file: URL) async throws -> [GitCommit]
    func diff(file: URL, commitHash: String) async throws -> DiffResult
    func show(file: URL, at commitHash: String) async throws -> String
    func stageAndCommit(file: URL, message: String) async throws
}

struct GitCommit: Identifiable, Equatable {
    let id: String      // 7位短哈希
    let fullHash: String
    let message: String
    let author: String
    let date: Date
}

struct DiffResult: Equatable {
    let hunks: [DiffHunk]
}

struct DiffHunk: Equatable {
    let lines: [DiffLine]
}

enum DiffLine: Equatable {
    case context(String)
    case added(String)
    case removed(String)
}
```

### 4. SourceRunner（source 执行服务）

```swift
protocol SourceRunnerProtocol {
    func source(file: URL) async -> SourceResult
}

struct SourceResult: Equatable {
    let success: Bool
    let output: String
    let errorOutput: String
}
```

实现：通过 `Process` 执行 `zsh -c "source <path>"` 并捕获 stdout/stderr。

### 5. FileWatcher（文件监控）

```swift
protocol FileWatcherProtocol {
    func watch(urls: [URL], onChange: @escaping (URL) -> Void)
    func stopWatching()
}
```

实现：使用 `DispatchSource.makeFileSystemObjectSource` 监控每个已打开文件的 `write` 事件，防抖延迟 500ms。

### 6. ViewModels

#### AppViewModel
```swift
@MainActor
class AppViewModel: ObservableObject {
    @Published var envCategory: EnvCategory?
    @Published var agentCategories: [AgentCategory] = []
    @Published var selectedFile: ConfigFile?
    @Published var isScanning: Bool = false
    
    func refresh() async
    func addCustomPath(_ url: URL)
}
```

#### EditorViewModel
```swift
@MainActor
class EditorViewModel: ObservableObject {
    @Published var content: String = ""
    @Published var isModified: Bool = false
    @Published var searchQuery: String = ""
    @Published var searchResults: [NSRange] = []
    @Published var currentSearchIndex: Int = 0
    @Published var isCaseSensitive: Bool = false
    
    func load(file: ConfigFile) async throws
    func save() async throws
    func formatJSON() throws
    func search(query: String, caseSensitive: Bool) -> [NSRange]
    func undo()
    func redo()
}
```

#### GitViewModel
```swift
@MainActor
class GitViewModel: ObservableObject {
    @Published var commits: [GitCommit] = []
    @Published var selectedCommit: GitCommit?
    @Published var diffResult: DiffResult?
    @Published var isGitRepo: Bool = false
    
    func loadHistory(for file: ConfigFile) async
    func selectCommit(_ commit: GitCommit) async
    func restore(to commit: GitCommit) async throws
    func initRepo(for file: ConfigFile) async throws
}
```

---

## Data Models

### AppSettings（持久化到 UserDefaults）

```swift
struct AppSettings: Codable {
    var autoSource: Bool = true
    var appearanceMode: AppearanceMode = .system
    var language: AppLanguage = .system
    var customPaths: [URL] = []
}

enum AppearanceMode: String, Codable, CaseIterable {
    case light, dark, system
}

enum AppLanguage: String, Codable, CaseIterable {
    case en, zhHans, system
}
```

### 文件系统状态

应用不维护本地数据库，所有状态直接从文件系统读取。`AgentCategory` 和 `ConfigFile` 是值类型（struct），每次扫描重新构建。

---

## Correctness Properties

*属性（Property）是系统在所有有效执行中都应保持的特征或行为——本质上是关于系统应做什么的形式化陈述。属性是人类可读规范与机器可验证正确性保证之间的桥梁。*

### Property 1: 扫描结果与文件系统状态一致

*对于任意已知 Agent 路径集合*，若某 Agent 的配置目录存在，则该 Agent 的分类必须出现在扫描结果中；若不存在，则不得出现。

**Validates: Requirements 1.1, 1.2, 1.3**

### Property 2: 文件枚举深度不超过 2 层

*对于任意目录结构*，`AgentScanner` 枚举的所有文件，其相对于根目录的路径深度不超过 2 层。

**Validates: Requirements 1.2**

### Property 3: 文件类型判断基于扩展名

*对于任意带有已知扩展名的文件名*，`FileType.detect(from:)` 返回的类型必须与该扩展名对应的类型一致；对于无扩展名的已知 Shell 配置文件名，返回 `.shell`。

**Validates: Requirements 1.6**

### Property 4: 分类互斥性

*对于任意文件集合*，环境变量分类中的文件不得出现在任何 Agent 分类中，Agent 分类中的文件不得出现在环境变量分类中。

**Validates: Requirements 2.1, 2.2**

### Property 5: 分类文件数量一致性

*对于任意分类*，其 `files.count` 必须等于该分类下实际存在的文件数量。

**Validates: Requirements 2.4**

### Property 6: 搜索结果完整性

*对于任意文本内容和搜索词*，`EditorViewModel.search(query:caseSensitive:)` 返回的匹配范围集合必须覆盖文本中所有实际匹配位置，不得遗漏，也不得包含非匹配位置。

**Validates: Requirements 3.3**

### Property 7: JSON 格式化幂等性

*对于任意有效 JSON 字符串*，对其执行格式化操作后再次执行格式化，结果与第一次格式化结果完全相同。

**Validates: Requirements 3.4**

### Property 8: source 仅在写入成功后执行

*对于任意环境变量文件保存操作*，`SourceRunner.source(file:)` 必须且仅在 `FileService.write(content:to:)` 成功返回后才被调用；若写入抛出错误，`source` 不得被调用。

**Validates: Requirements 4.1**

### Property 9: source 仅对环境变量文件执行

*对于任意文件*，只有属于 `EnvCategory` 的文件在保存时才触发 `SourceRunner`；属于 `AgentCategory` 的文件保存时不得触发 `SourceRunner`。

**Validates: Requirements 4.4**

### Property 10: 本地化字符串完整性

*对于所有 UI 字符串键*，中文（`zh-Hans`）和英文（`en`）本地化文件中都必须存在对应的非空翻译。

**Validates: Requirements 6.4**

### Property 11: diff 可重建目标版本

*对于任意两个文本版本 A 和 B*，将 diff(A, B) 的所有 `added` 行和 `context` 行按顺序拼接，结果必须等于 B。

**Validates: Requirements 7.3**

### Property 12: 文件同步后内容与磁盘一致

*对于任意外部文件修改*，在应用检测到变更并自动刷新（无本地未保存修改的情况下）后，`EditorViewModel.content` 必须与磁盘文件的字节内容完全一致。

**Validates: Requirements 8.1, 8.4**

---

## Error Handling

| 场景 | 处理策略 |
|------|---------|
| 文件读取失败（权限不足） | 在文件列表显示错误图标，点击显示详情 |
| 文件写入失败 | Toast 提示错误，不清除编辑器内容 |
| JSON 格式化失败 | 内联显示错误行列，不修改内容 |
| Git 命令不存在 | 禁用 Git 相关功能，显示"需要安装 Git"提示 |
| Git 命令执行失败 | 显示 stderr 输出，操作可重试 |
| source 执行失败 | 显示错误详情，不回滚文件 |
| 外部文件变更冲突 | 弹出选择对话框，用户主动决策 |
| 扫描超时（>3秒） | 显示已扫描到的结果，后台继续 |

所有异步错误通过 `Result<T, Error>` 或 Swift 的 `throws` 传递，在 ViewModel 层转换为用户可读的 `AppError` 枚举。

```swift
enum AppError: LocalizedError {
    case fileReadFailed(URL, Error)
    case fileWriteFailed(URL, Error)
    case jsonFormatError(line: Int, column: Int, message: String)
    case gitNotInstalled
    case gitCommandFailed(command: String, stderr: String)
    case sourceFailed(stderr: String)
}
```

---

## Testing Strategy

### 单元测试（Swift Testing）

针对纯函数和服务层逻辑：
- `FileType.detect(from:)` 的类型判断逻辑
- `AgentScanner` 的路径过滤逻辑（使用 mock FileManager）
- `GitService` 的 git log/diff 输出解析
- `EditorViewModel.search(query:caseSensitive:)` 的搜索逻辑
- JSON 格式化函数
- `AppError.localizedDescription` 的本地化输出

### 属性测试（SwiftCheck）

使用 [SwiftCheck](https://github.com/typelift/SwiftCheck) 库，每个属性测试运行 100 次迭代：

| 属性 | 生成器 | 验证内容 |
|------|--------|---------|
| Property 1 | 随机 Agent 路径存在/不存在组合 | 扫描结果与文件系统状态一致 |
| Property 3 | 随机文件名（带/不带扩展名） | 类型判断正确 |
| Property 6 | 随机文本 + 随机搜索词 | 搜索结果无遗漏无误报 |
| Property 7 | 随机有效 JSON 结构 | 格式化幂等 |
| Property 10 | 所有本地化键 | 中英文均有非空翻译 |
| Property 11 | 随机文本对 (A, B) | diff 可重建 B |

Properties 2、4、5、8、9、12 使用 mock 依赖进行单元测试（行为验证），而非属性测试，因为它们涉及副作用或文件系统状态。

### 集成测试

- 完整的文件保存 → source 流程（使用临时目录）
- Git 初始化 → 提交 → 查看历史 → 恢复流程（使用临时 Git 仓库）
- FSEvents 文件监控触发（写入临时文件后验证回调）

### UI 测试

- 三栏布局基本导航
- 编辑器搜索功能（Cmd+F）
- 语言切换后 UI 文字更新
- 深色/浅色模式切换
