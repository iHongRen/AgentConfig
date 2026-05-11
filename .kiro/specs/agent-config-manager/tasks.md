# Implementation Plan: AgentConfig

## Overview

按照 MVVM + Repository 分层架构，从底层服务到 UI 逐步构建。每个阶段都能独立编译和测试，最终将所有组件串联为完整应用。

## Tasks

- [x] 1. 项目基础结构与核心数据模型
  - 在 Xcode 项目中创建目录结构：`Models/`、`Services/`、`ViewModels/`、`Views/`、`Resources/`
  - 创建 `Models/ConfigFile.swift`：定义 `ConfigFile`、`FileType`、`AgentCategory`、`EnvCategory` 结构体
  - 创建 `Models/AppSettings.swift`：定义 `AppSettings`、`AppearanceMode`、`AppLanguage` 枚举和结构体
  - 创建 `Models/AppError.swift`：定义 `AppError` 枚举及其 `LocalizedError` 实现
  - 创建 `Models/GitModels.swift`：定义 `GitCommit`、`DiffResult`、`DiffHunk`、`DiffLine`
  - 创建 `Services/AgentDefinitions.swift`：定义所有已知 Agent 的路径配置静态表
  - _Requirements: 1.1, 1.6, 2.1_

- [x] 2. AgentScanner 服务
  - [x] 2.1 实现 `AgentScannerProtocol` 和 `AgentScanner`
    - 实现 `scan()` 方法：遍历 `AgentDefinitions`，检查路径存在性，枚举文件（递归深度 ≤ 2）
    - 实现 `scanEnvFiles()` 方法：检测所有已知环境变量文件路径
    - 实现 `FileType.detect(from url: URL) -> FileType` 静态方法：优先扩展名，其次文件名
    - _Requirements: 1.1, 1.2, 1.3, 1.6, 2.1, 2.2_

  - [ ]* 2.2 为 AgentScanner 编写属性测试
    - **Property 1: 扫描结果与文件系统状态一致**
    - **Validates: Requirements 1.1, 1.2, 1.3**
    - 使用 SwiftCheck 生成随机路径存在/不存在组合，mock `FileManager`，验证扫描结果

  - [ ]* 2.3 为 FileType 检测编写属性测试
    - **Property 3: 文件类型判断基于扩展名**
    - **Validates: Requirements 1.6**
    - 生成随机文件名（带/不带已知扩展名），验证类型判断结果

  - [ ]* 2.4 为文件枚举深度编写属性测试
    - **Property 2: 文件枚举深度不超过 2 层**
    - **Validates: Requirements 1.2**
    - 生成随机目录树结构，验证枚举结果中所有文件深度 ≤ 2

- [x] 3. FileService 服务
  - [x] 3.1 实现 `FileServiceProtocol` 和 `FileService`
    - 实现 `read(url:)`、`write(content:to:)`、`create(at:)`、`modificationDate(of:)` 方法
    - 所有方法使用 `async throws`，错误包装为 `AppError`
    - _Requirements: 3.6, 4.1, 8.1_

  - [ ]* 3.2 为 FileService 编写单元测试
    - 使用临时目录测试读写、创建操作
    - 测试写入失败时抛出正确错误类型

- [x] 4. Checkpoint — 确保所有测试通过，如有疑问请告知用户

- [x] 5. GitService 服务
  - [x] 5.1 实现 `GitServiceProtocol` 和 `GitService`
    - 实现 `isGitRepo(at:)`、`initRepo(at:)` 方法
    - 实现 `log(for:)` 方法：解析 `git log --pretty=format:"%h|%s|%an|%ai"` 输出为 `[GitCommit]`
    - 实现 `diff(file:commitHash:)` 方法：解析 `git diff <hash> -- <file>` 输出为 `DiffResult`
    - 实现 `show(file:at:)` 方法：执行 `git show <hash>:<file>` 返回文件内容
    - 实现 `stageAndCommit(file:message:)` 方法：执行 `git add` + `git commit`
    - _Requirements: 7.1, 7.2, 7.4, 7.5, 7.6_

  - [ ]* 5.2 为 git log 解析编写属性测试
    - **Property 11: diff 可重建目标版本**
    - **Validates: Requirements 7.3**
    - 生成随机文本对 (A, B)，计算 diff，验证 added + context 行拼接等于 B

  - [ ]* 5.3 为 GitService 编写集成测试
    - 使用临时目录创建真实 Git 仓库
    - 测试完整流程：init → write → commit → log → show → restore

- [x] 6. SourceRunner 服务
  - [x] 6.1 实现 `SourceRunnerProtocol` 和 `SourceRunner`
    - 通过 `Process` 执行 `zsh -c "source <path>"`，捕获 stdout/stderr
    - 返回 `SourceResult`，不抛出异常（失败通过 `success: false` 表示）
    - _Requirements: 4.1, 4.2, 4.3_

  - [ ]* 6.2 为 SourceRunner 编写单元测试
    - 测试 source 成功和失败场景（使用临时 shell 脚本）

- [x] 7. FileWatcher 服务
  - [x] 7.1 实现 `FileWatcherProtocol` 和 `FileWatcher`
    - 使用 `DispatchSource.makeFileSystemObjectSource` 监控文件 `write` 事件
    - 实现 500ms 防抖，避免频繁回调
    - _Requirements: 8.1, 8.2_

  - [ ]* 7.2 为 FileWatcher 编写集成测试
    - 写入临时文件后验证回调在 1 秒内触发

- [x] 8. Checkpoint — 确保所有测试通过，如有疑问请告知用户

- [x] 9. AppViewModel
  - [x] 9.1 实现 `AppViewModel`
    - 注入 `AgentScannerProtocol`、`FileServiceProtocol`、`AppSettings`
    - 实现 `refresh()` 方法：调用 scanner，更新 `@Published` 属性
    - 实现 `addCustomPath(_ url: URL)` 方法：持久化到 `AppSettings.customPaths`，触发重新扫描
    - 实现 `AppSettings` 的 `UserDefaults` 持久化（使用 `@AppStorage` 或自定义编解码）
    - _Requirements: 1.4, 1.5, 5.1, 5.2, 6.1, 6.2, 6.3_

  - [ ]* 9.2 为分类互斥性编写属性测试
    - **Property 4: 分类互斥性**
    - **Validates: Requirements 2.1, 2.2**
    - 生成随机文件集合，验证环境变量分类与 Agent 分类无交集

  - [ ]* 9.3 为文件数量一致性编写属性测试
    - **Property 5: 分类文件数量一致性**
    - **Validates: Requirements 2.4**
    - 生成随机分类，验证 `files.count` 与实际文件数量一致

- [x] 10. EditorViewModel
  - [x] 10.1 实现 `EditorViewModel` 核心功能
    - 注入 `FileServiceProtocol`、`SourceRunnerProtocol`、`GitServiceProtocol`
    - 实现 `load(file:)` 方法：读取文件内容，重置 `isModified`
    - 实现 `save()` 方法：写入文件；若为环境变量文件且 `autoSource` 开启，则调用 `SourceRunner`
    - 实现撤销/重做栈（`UndoManager` 或自定义，≥100步）
    - 追踪 `isModified` 状态：内容变更时设为 `true`，保存成功后设为 `false`
    - _Requirements: 3.6, 3.7, 4.1, 4.2, 4.3, 4.4, 4.5_

  - [x] 10.2 实现搜索功能
    - 实现 `search(query:caseSensitive:) -> [NSRange]` 方法
    - 实现 `nextMatch()` / `previousMatch()` 导航
    - _Requirements: 3.3_

  - [ ]* 10.3 为搜索结果完整性编写属性测试
    - **Property 6: 搜索结果完整性**
    - **Validates: Requirements 3.3**
    - 生成随机文本和搜索词，验证返回的所有 NSRange 确实匹配，且无遗漏

  - [x] 10.4 实现 JSON 格式化功能
    - 实现 `formatJSON()` 方法：使用 `JSONSerialization` 解析后以 2 空格缩进重新序列化
    - 格式化失败时抛出 `AppError.jsonFormatError(line:column:message:)`
    - _Requirements: 3.4, 3.5_

  - [ ]* 10.5 为 JSON 格式化幂等性编写属性测试
    - **Property 7: JSON 格式化幂等性**
    - **Validates: Requirements 3.4**
    - 生成随机有效 JSON 结构，验证 `format(format(json)) == format(json)`

  - [ ]* 10.6 为 source 执行顺序编写单元测试
    - **Property 8: source 仅在写入成功后执行**
    - **Validates: Requirements 4.1**
    - mock `FileService`（模拟写入失败），验证 `SourceRunner` 未被调用
    - mock `FileService`（模拟写入成功），验证 `SourceRunner` 被调用一次

  - [ ]* 10.7 为 source 分类约束编写单元测试
    - **Property 9: source 仅对环境变量文件执行**
    - **Validates: Requirements 4.4**
    - 保存 Agent 配置文件，验证 `SourceRunner` 未被调用

- [x] 11. GitViewModel
  - [x] 11.1 实现 `GitViewModel`
    - 实现 `loadHistory(for:)` 方法
    - 实现 `selectCommit(_:)` 方法：加载 diff
    - 实现 `restore(to:)` 方法：调用 `GitService.show`，更新编辑器内容，标记为未保存
    - 实现 `initRepo(for:)` 方法
    - _Requirements: 7.1, 7.2, 7.3, 7.4, 7.5, 7.6_

- [x] 12. FileWatcher 集成到 EditorViewModel
  - 在 `EditorViewModel` 中注入 `FileWatcherProtocol`
  - `load(file:)` 时开始监控，`deinit` 时停止监控
  - 检测到外部变更时：若 `isModified == false` 则静默刷新；若 `isModified == true` 则发布冲突事件
  - 实现 `onForeground()` 方法：检查所有已打开文件的修改时间
  - _Requirements: 8.1, 8.2, 8.3, 8.4, 8.5_

  - [ ]* 12.1 为文件同步内容一致性编写单元测试
    - **Property 12: 文件同步后内容与磁盘一致**
    - **Validates: Requirements 8.1, 8.4**
    - mock `FileWatcher` 触发变更事件，验证 `content` 与 mock `FileService` 返回内容一致

- [x] 13. Checkpoint — 确保所有测试通过，如有疑问请告知用户

- [x] 14. 主界面布局（三栏 NavigationSplitView）
  - [x] 14.1 实现 `SidebarView`
    - 使用 `NavigationSplitView` 三栏布局
    - 显示"环境变量"分类（置顶）和各 Agent 分类
    - 每个分类显示文件数量角标
    - 提供"刷新"按钮（触发 `AppViewModel.refresh()`）
    - 提供"添加自定义路径"按钮（打开文件选择器）
    - _Requirements: 1.4, 1.5, 2.2, 2.3, 2.4_

  - [x] 14.2 实现 `FileListView`
    - 列出选中分类下的所有文件
    - 对不存在的环境变量文件显示"创建"按钮
    - _Requirements: 2.3_

- [x] 15. 编辑器视图
  - [x] 15.1 实现 `EditorView` 基础编辑器
    - 使用 `TextEditor` 或自定义 `NSViewRepresentable`（包装 `NSTextView`）
    - 显示行号（行号列宽随行数自动调整）
    - 在标题栏/标签页显示未保存标记"●"
    - 绑定 `EditorViewModel`
    - _Requirements: 3.1, 3.7_

  - [x] 15.2 实现语法高亮
    - 使用 `NSTextStorage` + `NSLayoutManager` 实现语法高亮
    - 为 JSON/JSONC、YAML/TOML、Shell 实现各自的高亮规则
    - 浅色/深色模式使用不同配色方案
    - _Requirements: 3.2, 5.4_

  - [x] 15.3 实现搜索栏 UI
    - Cmd+F 显示搜索栏，Escape 关闭
    - 显示匹配数量，支持上一个/下一个导航（Cmd+G / Cmd+Shift+G）
    - 大小写敏感开关
    - 无匹配时显示"未找到"提示
    - _Requirements: 3.3_

  - [x] 15.4 实现编辑器工具栏
    - JSON 文件显示"格式化"按钮
    - Git 仓库文件显示"历史记录"按钮
    - 格式化错误时内联显示错误位置
    - _Requirements: 3.4, 3.5, 7.1_

- [x] 16. Git 历史记录视图
  - [x] 16.1 实现 `GitHistoryView`
    - 列表显示提交记录（短哈希、提交信息、作者、相对时间）
    - 选中提交后显示 diff 视图
    - _Requirements: 7.2, 7.3_

  - [x] 16.2 实现 diff 视图
    - 并排或内联显示 diff，新增行绿色高亮，删除行红色高亮
    - _Requirements: 7.3_

  - [x] 16.3 实现恢复确认对话框
    - 点击"恢复"弹出确认对话框，确认后替换编辑器内容并标记未保存
    - _Requirements: 7.4_

- [x] 17. 设置页面
  - [x] 17.1 实现 `SettingsView`
    - 外观模式选择（浅色/深色/跟随系统）
    - 语言选择（中文/英文/跟随系统）
    - 自动 source 开关
    - _Requirements: 4.5, 5.2, 6.3_

- [x] 18. 关于页面
  - [x] 18.1 实现 `AboutView`
    - 显示应用名称、图标、版本号（从 `Bundle.main.infoDictionary` 读取）、构建号、作者、GitHub 链接、MIT 协议
    - 帮助区域：支持的 Agent 列表及路径说明、FAQ（≥5条）、快捷键列表
    - 在 macOS 菜单栏"AgentConfig > 关于 AgentConfig"注册入口
    - _Requirements: 9.1, 9.2, 9.3_

- [x] 19. 国际化
  - [x] 19.1 创建本地化字符串文件
    - 创建 `en.lproj/Localizable.strings` 和 `zh-Hans.lproj/Localizable.strings`
    - 将所有硬编码 UI 字符串替换为 `NSLocalizedString` / `String(localized:)`
    - 实现日期格式本地化（中文 `yyyy年MM月dd日`，英文 `MMM d, yyyy`）
    - _Requirements: 6.1, 6.2, 6.4, 6.5_

  - [x] 19.2 实现语言强制切换
    - 在 `AppViewModel` 中实现语言切换逻辑（更新 `UserDefaults["AppleLanguages"]`，触发 UI 重建）
    - _Requirements: 6.3_

  - [ ]* 19.3 为本地化字符串完整性编写属性测试
    - **Property 10: 本地化字符串完整性**
    - **Validates: Requirements 6.4**
    - 遍历所有本地化键，验证中英文文件中均存在非空翻译

- [x] 20. 深色/浅色模式集成
  - 在 `AgentConfigApp.swift` 中根据 `AppSettings.appearanceMode` 设置 `.preferredColorScheme`
  - 监听 `NSApp.effectiveAppearance` 变化，在"跟随系统"模式下实时更新
  - _Requirements: 5.1, 5.2, 5.3_

- [x] 21. 串联所有组件
  - [x] 21.1 在 `AgentConfigApp.swift` 中完成依赖注入
    - 创建所有 Service 实例，注入到 ViewModel，通过 `.environmentObject` 传递给 View 层
    - 注册 `NSApplicationDelegate` 处理前台切换事件（触发 `EditorViewModel.onForeground()`）
    - _Requirements: 8.5_

  - [x] 21.2 连接 `AppViewModel` 与 `SidebarView`、`FileListView`
  - [x] 21.3 连接 `EditorViewModel` 与 `EditorView`、`GitViewModel` 与 `GitHistoryView`

- [x] 22. Final Checkpoint — 确保所有测试通过，完整运行应用验证主要功能流程，如有疑问请告知用户

## Notes

- 标有 `*` 的子任务为可选测试任务，可跳过以加快 MVP 进度
- 每个任务均引用了具体需求条目，便于追溯
- 属性测试需要添加 SwiftCheck 依赖（Swift Package Manager）：`https://github.com/typelift/SwiftCheck`
- 编辑器行号和语法高亮建议使用 `NSViewRepresentable` 包装 `NSTextView`，以获得更精细的控制
- Git 操作全部通过 `Process` 调用系统 `git`，不引入第三方 Git 库
