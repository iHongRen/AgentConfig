//
//  AgentDefinitions.swift
//  AgentConfig
//
//  Created by cxy on 2026/5/11.
//

import SwiftUI

// MARK: - AgentConfigEntry

/// 描述一个 Agent 的可编辑配置文件条目。
struct AgentConfigEntry {
    let title: String
    let candidatePaths: [String]

    init(_ path: String) {
        self.title = URL(fileURLWithPath: path).lastPathComponent
        self.candidatePaths = [path]
    }

    init(title: String, candidatePaths: [String]) {
        self.title = title
        self.candidatePaths = candidatePaths
    }

    /// 展开所有候选路径为绝对 URL
    var resolvedURLs: [URL] {
        candidatePaths.map {
            let expanded = ($0 as NSString).expandingTildeInPath
            return URL(fileURLWithPath: expanded)
        }
    }
}

// MARK: - AgentDefinition

/// 描述一个已知 Code Agent 的元数据和路径配置
struct AgentDefinition {
    /// 唯一标识符，如 "claude"
    let id: String
    /// 用户可见的显示名称
    let displayName: String
    /// Asset Catalog 中的图标名称，如 "ClaudeCode"
    let iconName: String
    /// 侧边栏图标颜色
    let iconColor: Color
    /// 该 Agent 应展示的可编辑配置文件列表
    let configFiles: [AgentConfigEntry]
}

// MARK: - AgentConfigMatch

struct AgentConfigMatch {
    let definition: AgentDefinition
    let entry: AgentConfigEntry
}

// MARK: - AgentDefinitions

/// 所有已知 Code Agent 的静态路径配置表
///
/// 扫描时仅检查每个 Agent 的预定义配置文件列表。
enum AgentDefinitions {

    /// 所有已知 Agent 的定义列表（按字母顺序排列）
    static let all: [AgentDefinition] = [
        AgentDefinition(
            id: "aider",
            displayName: "Aider",
            iconName: "Aider",
            iconColor: Color(red: 0.06, green: 0.74, blue: 0.58),
            configFiles: [
                AgentConfigEntry("~/.aider.conf.yml"),
                AgentConfigEntry("~/.aider.model.settings.yml")
            ]
        ),
        AgentDefinition(
            id: "amazonq",
            displayName: "Amazon Q Developer",
            iconName: "AmazonQ",
            iconColor: Color(red: 0.96, green: 0.72, blue: 0.10),
            configFiles: [
                AgentConfigEntry("~/.aws/config"),
                AgentConfigEntry("~/.aws/credentials")
            ]
        ),
        AgentDefinition(
            id: "augment",
            displayName: "Augment",
            iconName: "Augment",
            iconColor: Color(red: 0.48, green: 0.33, blue: 0.93),
            configFiles: [
                AgentConfigEntry("~/.augment/settings.json")
            ]
        ),
        AgentDefinition(
            id: "claude",
            displayName: "Claude Code",
            iconName: "ClaudeCode",
            iconColor: Color(red: 0.95, green: 0.43, blue: 0.09),
            configFiles: [
                AgentConfigEntry("~/.claude/settings.json"),
                AgentConfigEntry("~/.claude.json")
            ]
        ),
        AgentDefinition(
            id: "cline",
            displayName: "Cline",
            iconName: "Cline",
            iconColor: Color(red: 0.30, green: 0.55, blue: 0.96),
            configFiles: [
                AgentConfigEntry("~/.cline/data/settings/providers.json"),
                AgentConfigEntry("~/.cline/data/settings/global-settings.json")
            ]
        ),
        AgentDefinition(
            id: "codex",
            displayName: "Codex",
            iconName: "Codex",
            iconColor: Color(nsColor: .labelColor),
            configFiles: [
                AgentConfigEntry("~/.codex/auth.json"),
                AgentConfigEntry("~/.codex/config.toml")
            ]
        ),
        AgentDefinition(
            id: "continue",
            displayName: "Continue",
            iconName: "Continue",
            iconColor: Color(nsColor: .secondaryLabelColor),
            configFiles: [
                AgentConfigEntry("~/.continue/config.yaml"),
                AgentConfigEntry("~/.continue/config.ts"),
                AgentConfigEntry("~/.continue/.env")
            ]
        ),
        AgentDefinition(
            id: "cursor",
            displayName: "Cursor",
            iconName: "Cursor",
            iconColor: Color(nsColor: .controlTextColor),
            configFiles: [
                AgentConfigEntry("~/Library/Application Support/Cursor/User/settings.json"),
                AgentConfigEntry("~/.cursor/cli-config.json")
            ]
        ),
        AgentDefinition(
            id: "gemini",
            displayName: "Gemini CLI",
            iconName: "GeminiCLI",
            iconColor: Color(red: 0.22, green: 0.40, blue: 0.92),
            configFiles: [
                AgentConfigEntry("~/.gemini/settings.json")
            ]
        ),
        AgentDefinition(
            id: "github-copilot",
            displayName: "GitHub Copilot",
            iconName: "GitHubCopilot",
            iconColor: Color(red: 0.18, green: 0.80, blue: 0.44),
            configFiles: [
                AgentConfigEntry("~/Library/Application Support/Code/User/settings.json")
            ]
        ),
        AgentDefinition(
            id: "kilocode",
            displayName: "Kilo Code",
            iconName: "KiloCode",
            iconColor: Color(red: 0.95, green: 0.55, blue: 0.15),
            configFiles: [
                AgentConfigEntry("~/.config/kilo/kilo.jsonc")
            ]
        ),
        AgentDefinition(
            id: "opencode",
            displayName: "OpenCode CLI",
            iconName: "OpenCodeCLI",
            iconColor: Color(red: 0.25, green: 0.55, blue: 0.85),
            configFiles: [
                AgentConfigEntry("~/.config/opencode/opencode.json")
            ]
        ),
        AgentDefinition(
            id: "qwen",
            displayName: "Qwen Code",
            iconName: "QwenCode",
            iconColor: Color(red: 0.50, green: 0.20, blue: 0.90),
            configFiles: [
                AgentConfigEntry("~/.qwen/settings.json")
            ]
        ),
        AgentDefinition(
            id: "trae",
            displayName: "Trae",
            iconName: "Trae",
            iconColor: Color(red: 0.20, green: 0.60, blue: 0.95),
            configFiles: [
                AgentConfigEntry("~/Library/Application Support/Trae/User/settings.json")
            ]
        ),
        AgentDefinition(
            id: "windsurf",
            displayName: "Windsurf",
            iconName: "Windsurf",
            iconColor: Color(red: 0.15, green: 0.65, blue: 0.70),
            configFiles: [
                AgentConfigEntry("~/Library/Application Support/Windsurf/User/settings.json")
            ]
        )
    ]

    // MARK: - Convenience

    /// 根据 Agent ID 查找定义
    static func definition(for id: String) -> AgentDefinition? {
        all.first { $0.id == id }
    }

    static func match(for url: URL) -> AgentConfigMatch? {
        let standardizedURL = url.standardizedFileURL
        for definition in all {
            for entry in definition.configFiles where entry.resolvedURLs.contains(where: { $0.standardizedFileURL == standardizedURL }) {
                return AgentConfigMatch(definition: definition, entry: entry)
            }
        }
        return nil
    }
}
