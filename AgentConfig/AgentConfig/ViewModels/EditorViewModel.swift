//
//  EditorViewModel.swift
//  AgentConfig
//
//  Created by cxy on 2026/5/11.
//

import Foundation
import Combine

// MARK: - EditorViewModel

/// 编辑器 ViewModel，负责文件内容的加载、编辑、保存、搜索和格式化
///
/// - 注入 `FileServiceProtocol`、`SourceRunnerProtocol`、`GitServiceProtocol` 依赖
/// - 通过 `@Published` 属性驱动 SwiftUI 视图更新
/// - 支持撤销/重做（≥100步）、搜索导航、JSON 格式化
@MainActor
final class EditorViewModel: ObservableObject {

    // MARK: - Published Properties

    /// 编辑器当前内容
    @Published var content: String = "" {
        didSet {
            guard content != oldValue else { return }
            // 追踪修改状态
            if !isLoadingContent {
                isModified = true
                registerUndo(oldContent: oldValue)
            }
        }
    }

    /// 内容是否已被修改但未保存
    @Published var isModified: Bool = false

    /// 当前搜索关键词
    @Published var searchQuery: String = ""

    /// 搜索结果（所有匹配的 NSRange）
    @Published var searchResults: [NSRange] = []

    /// 当前高亮的搜索结果索引
    @Published var currentSearchIndex: Int = 0

    /// 搜索是否区分大小写
    @Published var isCaseSensitive: Bool = false

    /// source 命令执行结果（用于 UI 展示）
    @Published var sourceResult: SourceResult?

    /// 最近一次错误（用于 UI 展示）
    @Published var lastError: AppError?

    /// 是否存在外部文件冲突（外部修改 + 本地未保存修改同时存在）
    @Published var hasExternalConflict: Bool = false

    // MARK: - Internal State

    /// 当前打开的文件
    private(set) var currentFile: ConfigFile?

    /// 是否自动 source 环境变量文件（由外部注入）
    var autoSource: Bool = true

    /// 最后一次加载文件的时间，用于 onForeground() 比较
    private(set) var lastLoadedDate: Date?

    // MARK: - Dependencies

    private let fileService: FileServiceProtocol
    private let sourceRunner: SourceRunnerProtocol
    private let gitService: GitServiceProtocol
    private let fileWatcher: FileWatcherProtocol

    // MARK: - Undo/Redo

    /// 撤销栈，存储历史内容快照
    private var undoStack: [String] = []

    /// 重做栈，存储被撤销的内容快照
    private var redoStack: [String] = []

    /// 撤销/重做历史最大步数
    private let maxUndoSteps = 100

    /// 标记是否正在加载内容（加载时不触发 isModified 和 undo 注册）
    private var isLoadingContent: Bool = false

    // MARK: - Init

    /// 初始化 EditorViewModel
    /// - Parameters:
    ///   - fileService: 文件读写服务，默认使用 `FileService()`
    ///   - sourceRunner: source 执行服务，默认使用 `SourceRunner()`
    ///   - gitService: Git 操作服务，默认使用 `GitService()`
    ///   - fileWatcher: 文件监控服务，默认使用 `FileWatcher()`
    init(
        fileService: FileServiceProtocol = FileService(),
        sourceRunner: SourceRunnerProtocol = SourceRunner(),
        gitService: GitServiceProtocol = GitService(),
        fileWatcher: FileWatcherProtocol = FileWatcher()
    ) {
        self.fileService = fileService
        self.sourceRunner = sourceRunner
        self.gitService = gitService
        self.fileWatcher = fileWatcher
    }

    // MARK: - Deinit

    deinit {
        fileWatcher.stopWatching()
    }

    // MARK: - File Operations

    /// 加载文件内容到编辑器
    ///
    /// 读取文件内容后重置修改状态和撤销/重做历史，并开始监控文件变更。
    /// - Parameter file: 要加载的配置文件
    /// - Throws: `AppError.fileReadFailed` 读取失败时
    func load(file: ConfigFile) async throws {
        do {
            let fileContent = try await fileService.read(url: file.url)
            isLoadingContent = true
            content = fileContent
            isLoadingContent = false
            currentFile = file
            isModified = false
            lastLoadedDate = fileService.modificationDate(of: file.url) ?? Date()
            hasExternalConflict = false
            // 重置撤销/重做历史
            undoStack = []
            redoStack = []
            // 清空搜索状态
            searchResults = []
            currentSearchIndex = 0
            searchQuery = ""
            lastError = nil

            // 开始监控文件变更
            fileWatcher.watch(urls: [file.url]) { [weak self] changedURL in
                Task { @MainActor [weak self] in
                    await self?.handleExternalChange(at: changedURL)
                }
            }
        } catch let appError as AppError {
            lastError = appError
            throw appError
        } catch {
            let appError = AppError.fileReadFailed(file.url, error)
            lastError = appError
            throw appError
        }
    }

    /// 保存当前编辑器内容到文件
    ///
    /// 写入成功后：
    /// - 将 `isModified` 设为 `false`
    /// - 若文件为环境变量类型（`.shell`）且 `autoSource` 开启，则执行 source
    /// - Throws: `AppError.fileWriteFailed` 写入失败时
    func save() async throws {
        guard let file = currentFile else { return }

        do {
            // 先写入文件
            try await fileService.write(content: content, to: file.url)
            // 写入成功后标记为未修改
            isModified = false

            // 仅对环境变量文件且 autoSource 开启时执行 source
            if file.fileType == .shell && autoSource {
                let result = await sourceRunner.source(file: file.url)
                sourceResult = result
                if !result.success {
                    lastError = AppError.sourceFailed(stderr: result.errorOutput)
                }
            }
        } catch let appError as AppError {
            lastError = appError
            throw appError
        } catch {
            let appError = AppError.fileWriteFailed(file.url, error)
            lastError = appError
            throw appError
        }
    }

    // MARK: - External File Change Handling

    /// 处理外部文件变更事件
    ///
    /// - 若本地无未保存修改（`isModified == false`）：静默刷新文件内容
    /// - 若本地有未保存修改（`isModified == true`）：发布冲突事件，等待用户决策
    /// - Parameter url: 发生变更的文件 URL
    private func handleExternalChange(at url: URL) async {
        guard let file = currentFile, file.url == url else { return }

        if isModified {
            // 有本地未保存修改，发布冲突事件，不自动覆盖
            hasExternalConflict = true
        } else {
            // 无本地修改，静默刷新
            await silentRefresh(file: file)
        }
    }

    /// 静默刷新文件内容（不打断用户，不修改 isModified 状态）
    private func silentRefresh(file: ConfigFile) async {
        guard let newContent = try? await fileService.read(url: file.url) else { return }
        isLoadingContent = true
        content = newContent
        isLoadingContent = false
        isModified = false
        lastLoadedDate = fileService.modificationDate(of: file.url) ?? Date()
    }

    /// 应用从后台切换到前台时调用，主动检查当前文件的修改时间
    ///
    /// 若文件修改时间比上次加载时间更新，则按冲突/静默刷新逻辑处理。
    func onForeground() async {
        guard let file = currentFile,
              let lastLoaded = lastLoadedDate,
              let diskModDate = fileService.modificationDate(of: file.url) else { return }

        // 磁盘修改时间比上次加载时间更新，说明有外部变更
        guard diskModDate > lastLoaded else { return }

        if isModified {
            hasExternalConflict = true
        } else {
            await silentRefresh(file: file)
        }
    }

    /// 解决外部文件冲突
    ///
    /// - Parameter keepLocal: `true` 保留本地修改，清除冲突标记；`false` 加载外部版本，清除冲突标记
    func resolveConflict(keepLocal: Bool) async {
        hasExternalConflict = false
        if keepLocal {
            // 保留本地修改，仅更新 lastLoadedDate 以避免重复触发
            lastLoadedDate = currentFile.flatMap { fileService.modificationDate(of: $0.url) } ?? Date()
        } else {
            // 加载外部版本
            if let file = currentFile {
                await silentRefresh(file: file)
                isModified = false
            }
        }
    }

    // MARK: - Undo / Redo

    /// 撤销上一步内容变更
    func undo() {
        guard let previousContent = undoStack.popLast() else { return }
        // 将当前内容压入重做栈
        redoStack.append(content)
        // 恢复内容（不触发 undo 注册）
        isLoadingContent = true
        content = previousContent
        isLoadingContent = false
        isModified = !undoStack.isEmpty || content != (currentFile.map { _ in "" } ?? "")
    }

    /// 重做上一步被撤销的内容变更
    func redo() {
        guard let nextContent = redoStack.popLast() else { return }
        // 将当前内容压入撤销栈
        undoStack.append(content)
        // 应用内容（不触发 undo 注册）
        isLoadingContent = true
        content = nextContent
        isLoadingContent = false
        isModified = true
    }

    // MARK: - Search

    /// 在当前内容中搜索所有匹配项
    ///
    /// - Parameters:
    ///   - query: 搜索关键词
    ///   - caseSensitive: 是否区分大小写
    /// - Returns: 所有匹配位置的 `NSRange` 数组
    @discardableResult
    func search(query: String, caseSensitive: Bool) -> [NSRange] {
        guard !query.isEmpty else {
            searchResults = []
            currentSearchIndex = 0
            return []
        }

        let nsContent = content as NSString
        let contentLength = nsContent.length
        var options: NSString.CompareOptions = [.literal]
        if !caseSensitive {
            options.insert(.caseInsensitive)
        }

        var results: [NSRange] = []
        var searchRange = NSRange(location: 0, length: contentLength)

        while searchRange.location < contentLength {
            let found = nsContent.range(of: query, options: options, range: searchRange)
            guard found.location != NSNotFound else { break }
            results.append(found)
            // 移动搜索起点到当前匹配结束位置
            let nextLocation = found.location + found.length
            searchRange = NSRange(location: nextLocation, length: contentLength - nextLocation)
        }

        searchResults = results
        // 重置到第一个匹配项
        currentSearchIndex = results.isEmpty ? 0 : 0
        // 触发滚动到第一个匹配项
        if !results.isEmpty { scrollRevision += 1 }
        return results
    }

    /// 跳转到下一个搜索匹配项
    func nextMatch() {
        guard !searchResults.isEmpty else { return }
        currentSearchIndex = (currentSearchIndex + 1) % searchResults.count
        scrollRevision += 1
    }

    /// 跳转到上一个搜索匹配项
    func previousMatch() {
        guard !searchResults.isEmpty else { return }
        currentSearchIndex = (currentSearchIndex - 1 + searchResults.count) % searchResults.count
        scrollRevision += 1
    }

    /// 每次需要滚动到当前匹配项时递增，供 CodeEditorView 监听
    @Published var scrollRevision: Int = 0

    // MARK: - JSON Formatting

    /// 将当前内容格式化为 4 空格缩进的 JSON
    ///
    /// 格式化成功后更新 `content`；失败时抛出 `AppError.jsonFormatError`，不修改原内容。
    /// - Throws: `AppError.jsonFormatError(line:column:message:)` 格式化失败时
    func formatJSON() throws {
        let data = Data(content.utf8)

        do {
            let jsonObject = try JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed])
            let formattedData = try JSONSerialization.data(
                withJSONObject: jsonObject,
                options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
            )
            // JSONSerialization.prettyPrinted 在 macOS 上使用 4 空格缩进。
            if let formattedString = String(data: formattedData, encoding: .utf8) {
                isLoadingContent = true
                content = formattedString
                isLoadingContent = false
                isModified = true
            }
        } catch let jsonError as NSError {
            // 从错误信息中提取行列信息
            let (line, column, message) = extractJSONErrorInfo(from: jsonError, originalContent: content)
            let appError = AppError.jsonFormatError(line: line, column: column, message: message)
            lastError = appError
            throw appError
        }
    }

    // MARK: - Private Helpers

    /// 注册撤销操作，将旧内容压入撤销栈
    private func registerUndo(oldContent: String) {
        undoStack.append(oldContent)
        // 超出最大步数时移除最旧的记录
        if undoStack.count > maxUndoSteps {
            undoStack.removeFirst()
        }
        // 内容变更后清空重做栈
        redoStack = []
    }

    /// 从 NSError 中提取 JSON 错误的行列信息
    private func extractJSONErrorInfo(from error: NSError, originalContent: String) -> (line: Int, column: Int, message: String) {
        // JSONSerialization 错误通常在 userInfo 中包含行列信息
        let line = (error.userInfo["NSJSONSerializationErrorIndex"] as? Int).flatMap { charIndex in
            lineAndColumn(for: charIndex, in: originalContent)
        }?.line ?? 1

        let column = (error.userInfo["NSJSONSerializationErrorIndex"] as? Int).flatMap { charIndex in
            lineAndColumn(for: charIndex, in: originalContent)
        }?.column ?? 1

        let message = error.localizedDescription

        return (line, column, message)
    }

    /// 根据字符偏移量计算行列号（1-based）
    private func lineAndColumn(for charIndex: Int, in text: String) -> (line: Int, column: Int)? {
        guard charIndex >= 0 && charIndex <= text.count else { return nil }
        let prefix = text.prefix(charIndex)
        let lines = prefix.components(separatedBy: "\n")
        let line = lines.count
        let column = (lines.last?.count ?? 0) + 1
        return (line, column)
    }
}
