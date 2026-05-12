//
//  AgentScanner.swift
//  AgentConfig
//
//  Created by cxy on 2026/5/11.
//

import Foundation

// MARK: - AgentScannerProtocol

/// Agent 扫描服务协议
protocol AgentScannerProtocol {
    /// 扫描所有已知 Code Agent，返回存在配置文件的分类列表
    func scan() async -> [AgentCategory]
    /// 扫描所有已知环境变量文件，返回存在的文件及缺失路径
    func scanEnvFiles() async -> EnvCategory
}

// MARK: - AgentScanner

/// 默认 Agent 扫描服务实现
///
/// - 遍历 `AgentDefinitions.all`，仅检查每个 Agent 预定义的可编辑配置文件
/// - `scanEnvFiles()` 检测所有已知环境变量文件路径
struct AgentScanner: AgentScannerProtocol {

    private let fileManager: FileManager

    init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
    }

    // MARK: - scan()

    func scan() async -> [AgentCategory] {
        var categories: [AgentCategory] = []

        for definition in AgentDefinitions.all {
            let allURLs = definition.configFiles
                .flatMap(\.resolvedURLs)
                .uniqued(by: \.path)

            let collectedFiles = allURLs
                .filter { fileManager.fileExists(atPath: $0.path) }
                .map { ConfigFile(url: $0) }
                .sorted {
                    $0.url.lastPathComponent.localizedCaseInsensitiveCompare($1.url.lastPathComponent) == .orderedAscending
                }

            let missingPaths = allURLs
                .filter { !fileManager.fileExists(atPath: $0.path) }
                .sorted {
                    $0.lastPathComponent.localizedCaseInsensitiveCompare($1.lastPathComponent) == .orderedAscending
                }

            if !collectedFiles.isEmpty {
                let category = AgentCategory(
                    id: definition.id,
                    displayName: definition.displayName,
                    files: collectedFiles,
                    missingPaths: missingPaths
                )
                categories.append(category)
            }
        }

        return categories
    }

    // MARK: - scanEnvFiles()

    func scanEnvFiles() async -> EnvCategory {
        let knownEnvPaths: [String] = [
            "~/.zshrc",
            "~/.zprofile",
            "~/.zshenv",
            "~/.bashrc",
            "~/.bash_profile",
            "~/.bash_login",
            "~/.profile",
            "~/.config/fish/config.fish"
        ]

        var existingFiles: [ConfigFile] = []
        var missingPaths: [URL] = []

        for pathString in knownEnvPaths {
            let expanded = (pathString as NSString).expandingTildeInPath
            let url = URL(fileURLWithPath: expanded)

            if fileManager.fileExists(atPath: url.path) {
                existingFiles.append(ConfigFile(url: url))
            } else {
                missingPaths.append(url)
            }
        }

        return EnvCategory(files: existingFiles, missingPaths: missingPaths)
    }
}

private extension Array {
    func uniqued<Key: Hashable>(by keyPath: KeyPath<Element, Key>) -> [Element] {
        var seen: Set<Key> = []
        return filter { seen.insert($0[keyPath: keyPath]).inserted }
    }
}
