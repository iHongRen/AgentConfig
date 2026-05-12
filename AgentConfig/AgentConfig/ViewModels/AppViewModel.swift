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

    // MARK: - Dependencies

    private let scanner: AgentScannerProtocol
    private let fileService: FileServiceProtocol
    private(set) var settings: AppSettings

    // MARK: - Init

    /// 初始化 AppViewModel
    /// - Parameters:
    ///   - scanner: Agent 扫描服务，默认使用 `AgentScanner()`
    ///   - fileService: 文件读写服务，默认使用 `FileService()`
    ///   - settings: 应用设置，默认从 UserDefaults 加载
    init(
        scanner: AgentScannerProtocol = AgentScanner(),
        fileService: FileServiceProtocol = FileService(),
        settings: AppSettings = AppSettings.load()
    ) {
        self.scanner = scanner
        self.fileService = fileService
        self.settings = settings

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
        agentCategories = agents
        envCategory = env
        customPathGroups = scanCustomPaths()
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
        switch language {
        case .en:
            UserDefaults.standard.set(["en"], forKey: "AppleLanguages")
        case .zhHans:
            UserDefaults.standard.set(["zh-Hans"], forKey: "AppleLanguages")
        case .system:
            UserDefaults.standard.removeObject(forKey: "AppleLanguages")
        }
        UserDefaults.standard.synchronize()
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

            if isDirectory.boolValue {
                let files = enumerateFiles(in: standardizedURL, maxDepth: 2)
                return CustomPathGroup(url: standardizedURL, files: files.map { ConfigFile(url: $0) })
            }

            return CustomPathGroup(url: standardizedURL, files: [ConfigFile(url: standardizedURL)])
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
