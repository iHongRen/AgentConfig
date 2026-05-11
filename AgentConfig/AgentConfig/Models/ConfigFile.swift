//
//  ConfigFile.swift
//  AgentConfig
//
//  Created by cxy on 2026/5/11.
//

import Foundation

// MARK: - FileType

/// 配置文件的类型，基于扩展名或文件名判断
enum FileType: Equatable {
    case json
    case jsonc
    case yaml
    case toml
    case shell
    case plainText

    /// 根据 URL 判断文件类型
    /// 优先检查扩展名，无扩展名时检查文件名
    static func detect(from url: URL) -> FileType {
        let ext = url.pathExtension.lowercased()
        switch ext {
        case "json":
            return .json
        case "jsonc":
            return .jsonc
        case "yaml", "yml":
            return .yaml
        case "toml":
            return .toml
        case "sh", "zsh", "bash":
            return .shell
        default:
            break
        }

        // 无扩展名时检查文件名
        let filename = url.lastPathComponent.lowercased()
        let shellConfigNames: Set<String> = [
            ".zshrc", ".zprofile", ".zshenv", ".zlogin", ".zlogout",
            ".bashrc", ".bash_profile", ".bash_login", ".bash_logout",
            ".profile", ".kshrc", ".tcshrc", ".cshrc",
            ".fishrc"
        ]
        if shellConfigNames.contains(filename) {
            return .shell
        }

        return .plainText
    }
}

// MARK: - ConfigFile

/// 代表一个配置文件
struct ConfigFile: Identifiable, Equatable {
    let id: UUID
    let url: URL
    let fileType: FileType
    var isModified: Bool

    init(url: URL, fileType: FileType? = nil, isModified: Bool = false) {
        self.id = UUID()
        self.url = url
        self.fileType = fileType ?? FileType.detect(from: url)
        self.isModified = isModified
    }
}

// MARK: - AgentCategory

/// 代表一个 Code Agent 的配置文件分类
struct AgentCategory: Identifiable, Equatable {
    /// Agent 名称，如 "claude"，用作唯一标识
    let id: String
    let displayName: String
    let files: [ConfigFile]
}

// MARK: - EnvCategory

/// 环境变量文件分类（.zshrc、.bashrc 等）
struct EnvCategory: Equatable {
    /// 已存在的环境变量文件
    let files: [ConfigFile]
    /// 不存在但可创建的路径
    let missingPaths: [URL]
}
