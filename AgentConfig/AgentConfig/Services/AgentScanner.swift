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
/// - 遍历 `AgentDefinitions.all`，对每个 Agent 检查其路径列表
/// - 若任意路径存在则纳入结果，并枚举该路径下的配置文件（递归深度 ≤ 2）
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
            var collectedFiles: [ConfigFile] = []

            for entry in definition.paths {
                let url = entry.resolvedURL

                if entry.isFile {
                    // 单文件条目：直接检查文件是否存在
                    if fileManager.fileExists(atPath: url.path) {
                        let configFile = ConfigFile(url: url)
                        if !collectedFiles.contains(where: { $0.url == url }) {
                            collectedFiles.append(configFile)
                        }
                    }
                } else {
                    // 目录条目：枚举目录下的文件（深度 ≤ 2）
                    var isDirectory: ObjCBool = false
                    guard fileManager.fileExists(atPath: url.path, isDirectory: &isDirectory),
                          isDirectory.boolValue else {
                        continue
                    }

                    let files = enumerateFiles(in: url, maxDepth: 2)
                    for fileURL in files {
                        if !collectedFiles.contains(where: { $0.url == fileURL }) {
                            collectedFiles.append(ConfigFile(url: fileURL))
                        }
                    }
                }
            }

            // 只有当该 Agent 至少有一个路径存在时，才纳入结果
            if !collectedFiles.isEmpty {
                let category = AgentCategory(
                    id: definition.id,
                    displayName: definition.displayName,
                    files: collectedFiles
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

    // MARK: - Private Helpers

    /// 枚举目录下的所有文件，递归深度不超过 `maxDepth` 层
    ///
    /// - Parameters:
    ///   - directory: 根目录 URL
    ///   - maxDepth: 最大递归深度（相对于根目录，1 表示只枚举直接子文件）
    /// - Returns: 所有找到的文件 URL 列表（不含目录）
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

        let contents: [URL]
        do {
            contents = try fileManager.contentsOfDirectory(
                at: directory,
                includingPropertiesForKeys: [.isDirectoryKey, .isRegularFileKey],
                options: [.skipsHiddenFiles]
            )
        } catch {
            return
        }

        for itemURL in contents {
            var isDirectory: ObjCBool = false
            fileManager.fileExists(atPath: itemURL.path, isDirectory: &isDirectory)

            if isDirectory.boolValue {
                // 只有在未达到最大深度时才递归进入子目录
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
