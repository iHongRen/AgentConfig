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
/// - 注入 `FileServiceProtocol` 依赖
/// - 通过 `@Published` 属性驱动 SwiftUI 视图更新
/// - 支持撤销/重做（≥100步）、搜索导航、JSON 格式化
@MainActor
final class EditorViewModel: ObservableObject {

    enum PendingNavigationTarget {
        case configFile(ConfigFile)
        case codexProfile(UUID)
        case claudeProfile(UUID)
    }

    // MARK: - Published Properties

    /// 编辑器当前内容
    @Published var content: String = "" {
        didSet {
            guard content != oldValue else { return }
            // 非加载状态下，依据与磁盘加载内容的差异判定修改状态。
            // 撤销/重做回到原始内容时 isModified 会自动归 false（走 NSTextView 原生 undo）。
            if !isLoadingContent {
                isModified = content != loadedContent
            }
        }
    }

    /// 内容是否已被修改但未保存
    @Published var isModified: Bool = false {
        didSet {
            guard isModified != oldValue else { return }
            if let url = currentFile?.url {
                onModifiedChange?(url, isModified)
            }
        }
    }

    /// 修改状态变化回调，用于同步到 AppViewModel 侧边栏的 ConfigFile 指示点
    var onModifiedChange: ((URL, Bool) -> Void)?

    /// 当前搜索关键词
    @Published var searchQuery: String = ""

    /// 搜索结果（所有匹配的 NSRange）
    @Published var searchResults: [NSRange] = []

    /// 当前高亮的搜索结果索引
    @Published var currentSearchIndex: Int = 0

    /// 搜索是否区分大小写
    @Published var isCaseSensitive: Bool = false

    /// 最近一次错误（用于 UI 展示）
    @Published var lastError: AppError?

    /// 是否存在外部文件冲突（外部修改 + 本地未保存修改同时存在）
    @Published var hasExternalConflict: Bool = false

    /// 是否存在待确认的未保存切换
    @Published var hasPendingUnsavedChangesConfirmation: Bool = false

    // MARK: - Internal State

    /// 当前打开的文件
    private(set) var currentFile: ConfigFile?

    /// 最后一次从磁盘加载（或静默刷新）得到的纯净内容快照，用于判定 isModified
    private var loadedContent: String = ""

    /// 最后一次加载文件的时间，用于 onForeground() 比较
    private(set) var lastLoadedDate: Date?

    // MARK: - Dependencies

    private let fileService: FileServiceProtocol
    private let fileWatcher: FileWatcherProtocol

    // MARK: - Undo/Redo

    /// 撤销/重做由 NSTextView 原生 undoManager 处理（CommentingTextView.allowsUndo = true）。
    /// 此处不再维护自定义栈，避免与系统 Cmd+Z 历史冲突。

    /// 标记是否正在加载内容（加载时不触发 isModified 判定）
    private var isLoadingContent: Bool = false

    /// 用户确认后要执行的切换目标
    private var pendingNavigationTarget: PendingNavigationTarget?

    // MARK: - Init

    /// 初始化 EditorViewModel
    /// - Parameters:
    ///   - fileService: 文件读写服务，默认使用 `FileService()`
    ///   - fileWatcher: 文件监控服务，默认使用 `FileWatcher()`
    init(
        fileService: FileServiceProtocol? = nil,
        fileWatcher: FileWatcherProtocol? = nil
    ) {
        self.fileService = fileService ?? FileService()
        self.fileWatcher = fileWatcher ?? FileWatcher()
    }

    // MARK: - Deinit

    deinit {
        MainActor.assumeIsolated {
            fileWatcher.stopWatching()
        }
    }

    // MARK: - File Operations

    /// 加载文件内容到编辑器
    ///
    /// 读取文件内容后重置修改状态和撤销/重做历史，并开始监控文件变更。
    /// - Parameter file: 要加载的配置文件
    /// - Throws: `AppError.fileReadFailed` 读取失败时
    func load(file: ConfigFile) async throws {
        do {
            // 加载新文件前，先清除上一个文件的未保存指示点（currentFile 尚未被覆盖）
            if isModified, let previousURL = currentFile?.url {
                onModifiedChange?(previousURL, false)
            }
            let fileContent = try await fileService.read(url: file.url)
            isLoadingContent = true
            content = fileContent
            isLoadingContent = false
            currentFile = file
            loadedContent = fileContent
            isModified = false
            lastLoadedDate = fileService.modificationDate(of: file.url) ?? Date()
            hasExternalConflict = false
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
    /// - 更新 `lastLoadedDate`，避免将本次保存误判为外部修改
    /// - Throws: `AppError.fileWriteFailed` 写入失败时
    func save() async throws {
        guard let file = currentFile else { return }

        do {
            try validateSyntaxBeforeSaving()
            // 先写入文件
            try await fileService.write(content: content, to: file.url)
            lastLoadedDate = fileService.modificationDate(of: file.url) ?? Date()
            // 写后重读磁盘内容，校正 loadedContent 基准；若保存瞬间被外部进程覆盖，
            // 则以此为基准重新判定修改状态（避免同秒内的写+外部改被漏判）。
            if let fresh = try? await fileService.read(url: file.url) {
                loadedContent = fresh
                isModified = content != loadedContent
            } else {
                loadedContent = content
                isModified = false
            }
            hasExternalConflict = false
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
        loadedContent = newContent
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
    /// - Parameter keepLocal: `true` 将 App 中的修改写回文件；`false` 加载外部版本覆盖编辑区
    func resolveConflict(keepLocal: Bool) async {
        if keepLocal {
            do {
                try await save()
            } catch {
                // 保存失败时保留冲突状态，允许用户在修复问题后重新决策
                hasExternalConflict = true
            }
        } else {
            hasExternalConflict = false
            // 加载外部版本
            if let file = currentFile {
                await silentRefresh(file: file)
            }
        }
    }

    func requestNavigation(to target: PendingNavigationTarget) -> Bool {
        guard currentFile != nil, isModified else { return true }
        guard !hasExternalConflict else { return false }

        pendingNavigationTarget = target
        hasPendingUnsavedChangesConfirmation = true
        return false
    }

    func takePendingNavigationTarget() -> PendingNavigationTarget? {
        defer { pendingNavigationTarget = nil }
        return pendingNavigationTarget
    }

    func confirmPendingNavigationSavingChanges() async -> PendingNavigationTarget? {
        do {
            try await save()
            hasPendingUnsavedChangesConfirmation = false
            return takePendingNavigationTarget()
        } catch {
            hasPendingUnsavedChangesConfirmation = false
            return nil
        }
    }

    func confirmPendingNavigationDiscardingChanges() -> PendingNavigationTarget? {
        isModified = false
        hasPendingUnsavedChangesConfirmation = false
        return takePendingNavigationTarget()
    }

    func cancelPendingNavigation() {
        pendingNavigationTarget = nil
        hasPendingUnsavedChangesConfirmation = false
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

    private func validateSyntaxBeforeSaving() throws {
        guard let fileType = currentFile?.fileType else { return }

        switch fileType {
        case .json:
            try validateStrictJSON(content)
        case .jsonl:
            try validateJSONLines(content)
        case .toml, .json5:
            try validateBracketBalance(content, fileType: fileType.displayName)
        case .jsonc, .yaml, .shell, .plainText:
            return
        }
    }

    /// 轻量基础校验：括号 `() [] {}` 与引号 `"` `'` 是否配对。
    /// 适用于无原生解析器的 TOML/JSON5，避免误报故仅在字符串字面量外判定括号。
    private func validateBracketBalance(_ content: String, fileType: String) throws {
        var stack: [Character] = []
        var quote: Character? = nil
        let opening: [Character: Character] = ["(": ")", "[": "]", "{": "}"]
        let closing: Set<Character> = [")", "]", "}"]
        let chars = Array(content)

        for char in chars {
            if let currentQuote = quote {
                if char == currentQuote {
                    quote = nil
                }
                continue
            }

            if char == "\"" || char == "'" {
                quote = char
                continue
            }

            if let match = opening[char] {
                stack.append(match)
            } else if closing.contains(char) {
                guard let expected = stack.popLast(), expected == char else {
                    throw AppError.syntaxBalanceError(
                        fileType: fileType,
                        message: L10n.tr("error.syntaxBalanceError.unbalanced", value: "Unbalanced bracket or quote.")
                    )
                }
            }
        }

        if quote != nil {
            throw AppError.syntaxBalanceError(
                fileType: fileType,
                message: L10n.tr("error.syntaxBalanceError.unbalanced", value: "Unbalanced bracket or quote.")
            )
        }
        if !stack.isEmpty {
            throw AppError.syntaxBalanceError(
                fileType: fileType,
                message: L10n.tr("error.syntaxBalanceError.unbalanced", value: "Unbalanced bracket or quote.")
            )
        }
    }

    private func validateStrictJSON(_ content: String) throws {
        do {
            _ = try JSONSerialization.jsonObject(with: Data(content.utf8), options: [.fragmentsAllowed])
        } catch let jsonError as NSError {
            let (line, column, message) = extractJSONErrorInfo(from: jsonError, originalContent: content)
            throw AppError.jsonFormatError(line: line, column: column, message: message)
        }
    }

    private func validateJSONLines(_ content: String) throws {
        let lines = content.components(separatedBy: "\n")

        for (index, lineText) in lines.enumerated() {
            let trimmedLine = lineText.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmedLine.isEmpty else { continue }

            do {
                _ = try JSONSerialization.jsonObject(
                    with: Data(trimmedLine.utf8),
                    options: [.fragmentsAllowed]
                )
            } catch let jsonError as NSError {
                let (_, column, message) = extractJSONErrorInfo(from: jsonError, originalContent: trimmedLine)
                throw AppError.jsonFormatError(line: index + 1, column: column, message: message)
            }
        }
    }

    /// 从 NSError 中提取 JSON 错误的行列信息
    private func extractJSONErrorInfo(from error: NSError, originalContent: String) -> (line: Int, column: Int, message: String) {
        // JSONSerialization 错误通常在 userInfo 中包含字符偏移量
        let location = (error.userInfo["NSJSONSerializationErrorIndex"] as? Int).flatMap { charIndex in
            lineAndColumn(for: charIndex, in: originalContent)
        }
        let line = location?.line ?? 1
        let column = location?.column ?? 1
        let message = error.localizedDescription

        return (line, column, message)
    }

    /// 根据字符偏移量计算行列号（1-based）
    private func lineAndColumn(for charIndex: Int, in text: String) -> (line: Int, column: Int)? {
        let nsText = text as NSString
        guard charIndex >= 0 && charIndex <= nsText.length else { return nil }
        let prefix = nsText.substring(to: charIndex)
        let lines = prefix.components(separatedBy: "\n")
        let line = lines.count
        let column = (lines.last?.count ?? 0) + 1
        return (line, column)
    }
}
