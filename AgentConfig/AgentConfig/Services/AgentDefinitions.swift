//
//  AgentDefinitions.swift
//  AgentConfig
//
//  Created by cxy on 2026/5/11.
//

import Foundation

// MARK: - AgentPathEntry

/// 描述一个 Agent 的路径条目
/// - `path`：相对于用户主目录的路径字符串（以 `~/` 开头）
/// - `isFile`：若为 `true`，表示该条目是单个文件而非目录
struct AgentPathEntry {
    let path: String
    let isFile: Bool

    init(_ path: String, isFile: Bool = false) {
        self.path = path
        self.isFile = isFile
    }

    /// 展开为绝对 URL
    var resolvedURL: URL {
        let expanded = (path as NSString).expandingTildeInPath
        return URL(fileURLWithPath: expanded)
    }
}

// MARK: - AgentDefinition

/// 描述一个已知 Code Agent 的元数据和路径配置
struct AgentDefinition {
    /// 唯一标识符，如 "claude"
    let id: String
    /// 用户可见的显示名称
    let displayName: String
    /// 该 Agent 的所有已知路径（目录或文件）
    let paths: [AgentPathEntry]
}

// MARK: - AgentDefinitions

/// 所有已知 Code Agent 的静态路径配置表
///
/// 扫描时按顺序检查每个 Agent 的路径列表，
/// 若任意路径存在则将该 Agent 纳入扫描结果。
enum AgentDefinitions {

    /// 所有已知 Agent 的定义列表（按字母顺序排列）
    static let all: [AgentDefinition] = [
        AgentDefinition(
            id: "claude",
            displayName: "Claude Code",
            paths: [
                AgentPathEntry("~/.claude"),
                AgentPathEntry("~/.config/claude"),
                AgentPathEntry("~/Library/Application Support/Claude")
            ]
        ),
        AgentDefinition(
            id: "qwen",
            displayName: "Qwen Code",
            paths: [
                AgentPathEntry("~/.qwen"),
                AgentPathEntry("~/.config/qwen")
            ]
        ),
        AgentDefinition(
            id: "codex",
            displayName: "Codex CLI",
            paths: [
                AgentPathEntry("~/.codex"),
                AgentPathEntry("~/.config/codex")
            ]
        ),
        AgentDefinition(
            id: "opencode",
            displayName: "OpenCode CLI",
            paths: [
                AgentPathEntry("~/.opencode"),
                AgentPathEntry("~/.config/opencode")
            ]
        ),
        AgentDefinition(
            id: "github-copilot",
            displayName: "GitHub Copilot",
            paths: [
                AgentPathEntry("~/.config/github-copilot")
            ]
        ),
        AgentDefinition(
            id: "cursor",
            displayName: "Cursor",
            paths: [
                AgentPathEntry("~/Library/Application Support/Cursor/User")
            ]
        ),
        AgentDefinition(
            id: "continue",
            displayName: "Continue",
            paths: [
                AgentPathEntry("~/.continue")
            ]
        ),
        AgentDefinition(
            id: "cody",
            displayName: "Cody",
            paths: [
                AgentPathEntry("~/.config/cody")
            ]
        ),
        AgentDefinition(
            id: "aider",
            displayName: "Aider",
            paths: [
                AgentPathEntry("~/.aider"),
                AgentPathEntry("~/.aider.conf.yml", isFile: true)
            ]
        ),
        AgentDefinition(
            id: "gemini",
            displayName: "Gemini CLI",
            paths: [
                AgentPathEntry("~/.gemini"),
                AgentPathEntry("~/.config/gemini")
            ]
        ),
        AgentDefinition(
            id: "amazonq",
            displayName: "Amazon Q",
            paths: [
                AgentPathEntry("~/.aws/amazonq")
            ]
        )
    ]

    // MARK: - Convenience

    /// 根据 Agent ID 查找定义
    static func definition(for id: String) -> AgentDefinition? {
        all.first { $0.id == id }
    }
}
