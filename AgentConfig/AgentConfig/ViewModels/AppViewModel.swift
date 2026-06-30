//
//  AppViewModel.swift
//  AgentConfig
//
//  Created by cxy on 2026/5/11.
//

import Foundation
import SwiftUI
import Combine

// MARK: - CategorySelection

/// 侧边栏分类选择，区分环境变量分类和 Agent 分类
enum CategorySelection: Hashable {
    case env
    case agent(id: String)
}

// MARK: - AppViewModel

/// 应用主 ViewModel，负责协调 Agent 扫描、文件选择和设置管理
///
/// - 注入 `AgentScannerProtocol` 和 `FileServiceProtocol` 依赖
/// - 通过 `@Published` 属性驱动 SwiftUI 视图更新
/// - 应用启动时自动触发扫描
@MainActor
final class AppViewModel: ObservableObject {

    // MARK: - Published Properties

    /// 环境变量文件分类（.zshrc、.bashrc 等）
    @Published var envCategory: EnvCategory?

    /// 已检测到的 Agent 配置文件分类列表
    @Published var agentCategories: [AgentCategory] = []

    /// 用户添加的自定义路径分组列表
    @Published var customPathGroups: [CustomPathGroup] = []

    /// 当前选中的配置文件
    @Published var selectedFile: ConfigFile?

    /// 当前选中的分类（nil 表示未选中）
    @Published var selectedCategory: CategorySelection?

    /// 是否正在扫描中
    @Published var isScanning: Bool = false

    /// 首次启动扫描是否已完成
    @Published private(set) var didFinishInitialRefresh: Bool = false

    // MARK: - Dependencies

    private let scanner: AgentScannerProtocol
    private let fileService: FileServiceProtocol
    private(set) var settings: AppSettings
    private var hasRestoredInitialSelection = false

    var lastVisitedPage: LastVisitedPage? {
        settings.lastVisitedPage
    }

    // MARK: - Init

    /// 初始化 AppViewModel
    /// - Parameters:
    ///   - scanner: Agent 扫描服务，默认使用 `AgentScanner()`
    ///   - fileService: 文件读写服务，默认使用 `FileService()`
    ///   - settings: 应用设置，默认从 UserDefaults 加载
    init(
        scanner: AgentScannerProtocol? = nil,
        fileService: FileServiceProtocol? = nil,
        settings: AppSettings? = nil
    ) {
        self.scanner = scanner ?? AgentScanner()
        self.fileService = fileService ?? FileService()
        self.settings = settings ?? AppSettings.load()

        // 应用启动时自动触发扫描
        Task { await refresh() }
    }

    // MARK: - Public Methods

    /// 重新扫描所有 Agent 配置文件和环境变量文件
    ///
    /// 扫描期间 `isScanning` 为 `true`，扫描完成后更新 `agentCategories` 和 `envCategory`。
    func refresh() async {
        isScanning = true
        defer { isScanning = false }

        async let agentResult = scanner.scan()
        async let envResult = scanner.scanEnvFiles()

        let (agents, env) = await (agentResult, envResult)
        agentCategories = filterHiddenFiles(from: mergeAddedFiles(into: agents))
        envCategory = filterHiddenFiles(from: mergeAddedFiles(into: env))
        customPathGroups = filterHiddenFiles(from: scanCustomPaths())
        didFinishInitialRefresh = true
    }

    func selectFile(_ file: ConfigFile?) {
        selectedFile = file

        if let file {
            persistLastVisitedPage(.configFile(path: file.url.standardizedFileURL.path))
        } else if case .configFile = settings.lastVisitedPage {
            persistLastVisitedPage(nil)
        }
    }

    func restoreInitialSelectionIfNeeded() -> ConfigFile? {
        guard didFinishInitialRefresh, !hasRestoredInitialSelection else { return nil }
        hasRestoredInitialSelection = true

        guard case .configFile(let path) = settings.lastVisitedPage else { return nil }
        let standardizedPath = URL(fileURLWithPath: path).standardizedFileURL.path

        let allFiles = (envCategory?.files ?? [])
            + agentCategories.flatMap(\.files)
            + customPathGroups.flatMap(\.files)

        guard let matchedFile = allFiles.first(where: { $0.url.standardizedFileURL.path == standardizedPath }) else {
            persistLastVisitedPage(nil)
            return nil
        }

        selectFile(matchedFile)
        return matchedFile
    }

    func persistLastVisitedPage(_ page: LastVisitedPage?) {
        guard settings.lastVisitedPage != page else { return }
        settings.lastVisitedPage = page
        settings.save()
    }

    // MARK: - Category Files

    func addFiles(_ urls: [URL], to categoryKey: SidebarCategoryKey) {
        let urlsToAdd = existingFileURLs(from: urls)
        guard !urlsToAdd.isEmpty else { return }

        let key = categoryKey.storageKey
        var existingURLs = settings.categoryFilePaths[key] ?? []
        for url in urlsToAdd where !existingURLs.contains(where: { $0.standardizedFileURL == url }) {
            existingURLs.append(url)
        }

        settings.categoryFilePaths[key] = existingURLs
        settings.hiddenFilePaths.removeAll { hiddenURL in
            urlsToAdd.contains { $0.standardizedFileURL == hiddenURL.standardizedFileURL }
        }
        settings.save()
        Task { await refresh() }
    }

    private func existingFileURLs(from urls: [URL]) -> [URL] {
        var result: [URL] = []
        for url in urls where url.isFileURL {
            let standardizedURL = url.standardizedFileURL
            var isDirectory: ObjCBool = false
            guard FileManager.default.fileExists(atPath: standardizedURL.path, isDirectory: &isDirectory), !isDirectory.boolValue else {
                continue
            }
            guard !result.contains(where: { $0.standardizedFileURL == standardizedURL }) else { continue }
            result.append(standardizedURL)
        }
        return result
    }

    private func addedFiles(for categoryKey: SidebarCategoryKey) -> [ConfigFile] {
        existingFileURLs(from: settings.categoryFilePaths[categoryKey.storageKey] ?? []).map { ConfigFile(url: $0) }
    }

    private func mergeAddedFiles(into categories: [AgentCategory]) -> [AgentCategory] {
        let categoryIDs = Set(categories.map(\.id))
        let mergedCategories = categories.map { category in
            AgentCategory(
                id: category.id,
                displayName: category.displayName,
                files: mergeFiles(category.files, with: addedFiles(for: .agent(id: category.id))),
                missingPaths: category.missingPaths
            )
        }

        let addedOnlyCategories = AgentDefinitions.all.compactMap { definition -> AgentCategory? in
            guard !categoryIDs.contains(definition.id) else { return nil }
            let files = addedFiles(for: .agent(id: definition.id))
            guard !files.isEmpty else { return nil }
            return AgentCategory(id: definition.id, displayName: definition.displayName, files: files, missingPaths: [])
        }

        return mergedCategories + addedOnlyCategories
    }

    private func mergeAddedFiles(into envCategory: EnvCategory?) -> EnvCategory? {
        guard let envCategory else { return nil }
        return EnvCategory(
            files: mergeFiles(envCategory.files, with: addedFiles(for: .env)),
            missingPaths: envCategory.missingPaths
        )
    }

    private func mergeFiles(_ baseFiles: [ConfigFile], with addedFiles: [ConfigFile]) -> [ConfigFile] {
        var result = baseFiles
        for file in addedFiles where !result.contains(where: { $0.url.standardizedFileURL == file.url.standardizedFileURL }) {
            result.append(file)
        }
        return result
    }

    // MARK: - Hidden Files Filtering

    /// 过滤掉被隐藏的文件
    private func filterHiddenFiles(from categories: [AgentCategory]) -> [AgentCategory] {
        categories.map { category in
            AgentCategory(
                id: category.id,
                displayName: category.displayName,
                files: category.files.filter { !isFileHidden($0.url) },
                missingPaths: category.missingPaths.filter { !isFileHidden($0) }
            )
        }
    }

    private func filterHiddenFiles(from envCategory: EnvCategory?) -> EnvCategory? {
        guard let env = envCategory else { return nil }
        return EnvCategory(
            files: env.files.filter { !isFileHidden($0.url) },
            missingPaths: env.missingPaths.filter { !isFileHidden($0) }
        )
    }

    private func filterHiddenFiles(from groups: [CustomPathGroup]) -> [CustomPathGroup] {
        groups.compactMap { group in
            let filteredFiles = group.files.filter { !isFileHidden($0.url) }
            // 如果过滤后没有文件了，返回 nil（不显示空分组）
            guard !filteredFiles.isEmpty else { return nil }
            return CustomPathGroup(url: group.url, files: filteredFiles)
        }
    }

    /// 添加用户自定义配置文件路径
    ///
    /// 将路径持久化到 `AppSettings.customPaths`，然后触发重新扫描。
    /// - Parameter url: 要添加的文件或目录 URL
    func addCustomPath(_ url: URL) {
        guard !settings.customPaths.contains(url) else { return }
        settings.customPaths.append(url)
        settings.save()
        Task { await refresh() }
    }

    /// 移除用户自定义路径（单个文件或目录）
    func removeCustomPath(_ url: URL) {
        settings.customPaths.removeAll { $0.standardizedFileURL == url.standardizedFileURL }
        settings.categoryFilePaths[SidebarCategoryKey.customPath(url).storageKey] = nil
        settings.save()
        Task { await refresh() }
    }

    /// 从列表中隐藏文件（不从磁盘删除，下次扫描不再显示）
    /// - Parameter url: 要隐藏的文件路径
    func hideFile(_ url: URL) {
        let standardizedURL = url.standardizedFileURL
        guard !settings.hiddenFilePaths.contains(where: { $0.standardizedFileURL == standardizedURL }) else { return }
        settings.hiddenFilePaths.append(standardizedURL)
        settings.save()
        // 如果当前选中的是被隐藏的文件，清除选择
        if selectedFile?.url.standardizedFileURL == standardizedURL {
            selectFile(nil)
        }
        Task { await refresh() }
    }

    /// 恢复显示被隐藏的文件
    /// - Parameter url: 要恢复显示的文件路径
    func unhideFile(_ url: URL) {
        settings.hiddenFilePaths.removeAll { $0.standardizedFileURL == url.standardizedFileURL }
        settings.save()
        Task { await refresh() }
    }

    /// 检查文件是否被隐藏
    /// - Parameter url: 文件路径
    /// - Returns: 是否被隐藏
    func isFileHidden(_ url: URL) -> Bool {
        settings.hiddenFilePaths.contains(where: { $0.standardizedFileURL == url.standardizedFileURL })
    }

    /// 更新应用设置（供设置页面调用）
    ///
    /// 保存新设置到 UserDefaults，并触发重新扫描以应用变更。
    /// 若语言设置发生变化，同时强制切换应用语言。
    /// - Parameter newSettings: 更新后的设置
    func updateSettings(_ newSettings: AppSettings) {
        let oldLanguage = settings.language
        settings = newSettings
        settings.save()

        // 若语言设置变化，强制切换（立即生效，无需重启）
        if newSettings.language != oldLanguage {
            applyLanguage(newSettings.language)
        }

        Task { await refresh() }
    }

    // MARK: - Language Switching

    /// 强制切换应用语言
    ///
    /// 通过更新 `UserDefaults["AppleLanguages"]` 并触发 UI 重建实现即时切换。
    /// - Parameter language: 目标语言
    func applyLanguage(_ language: AppLanguage) {
        // 发送通知触发 UI 重建（由 AgentConfigApp 监听）
        NotificationCenter.default.post(name: .languageDidChange, object: nil)
    }

    // MARK: - Custom Paths

    private func scanCustomPaths() -> [CustomPathGroup] {
        let fileManager = FileManager.default

        return settings.customPaths.compactMap { url in
            let standardizedURL = url.standardizedFileURL
            var isDirectory: ObjCBool = false

            guard fileManager.fileExists(atPath: standardizedURL.path, isDirectory: &isDirectory) else {
                return nil
            }

            let addedFiles = addedFiles(for: .customPath(standardizedURL))
            if isDirectory.boolValue {
                let files = enumerateFiles(in: standardizedURL, maxDepth: 2).map { ConfigFile(url: $0) }
                return CustomPathGroup(url: standardizedURL, files: mergeFiles(files, with: addedFiles))
            }

            return CustomPathGroup(url: standardizedURL, files: mergeFiles([ConfigFile(url: standardizedURL)], with: addedFiles))
        }
    }

    private func enumerateFiles(in directory: URL, maxDepth: Int) -> [URL] {
        var result: [URL] = []
        enumerateFilesRecursive(in: directory, currentDepth: 1, maxDepth: maxDepth, result: &result)
        return result
    }

    private func enumerateFilesRecursive(
        in directory: URL,
        currentDepth: Int,
        maxDepth: Int,
        result: inout [URL]
    ) {
        guard currentDepth <= maxDepth else { return }

        let contents = (try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.isDirectoryKey, .isRegularFileKey],
            options: [.skipsHiddenFiles]
        )) ?? []

        for itemURL in contents.sorted(by: { $0.lastPathComponent.localizedCaseInsensitiveCompare($1.lastPathComponent) == .orderedAscending }) {
            var isDirectory: ObjCBool = false
            FileManager.default.fileExists(atPath: itemURL.path, isDirectory: &isDirectory)

            if isDirectory.boolValue {
                if currentDepth < maxDepth {
                    enumerateFilesRecursive(
                        in: itemURL,
                        currentDepth: currentDepth + 1,
                        maxDepth: maxDepth,
                        result: &result
                    )
                }
            } else {
                result.append(itemURL)
            }
        }
    }
}

// MARK: - Notification Names

extension Notification.Name {
    /// 语言切换通知，由 `AppViewModel.applyLanguage(_:)` 发送
    static let languageDidChange = Notification.Name("AgentConfig.languageDidChange")
}
