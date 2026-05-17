//
//  AgentDefinitions.swift
//  AgentConfig
//
//  Created by cxy on 2026/5/11.
//

import Foundation

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
    /// Assets.xcassets 中的图标名称
    let iconName: String
    /// 该 Agent 应展示的可编辑配置文件列表
    let configFiles: [AgentConfigEntry]
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
            configFiles: [
                AgentConfigEntry("~/.aider.conf.yml"),
                AgentConfigEntry("~/.aider.model.settings.yml")
            ]
        ),
        AgentDefinition(
            id: "amazonq",
            displayName: "Amazon Q Developer",
            iconName: "AmazonQ",
            configFiles: [
                AgentConfigEntry("~/Library/Application Support/amazon-q/settings.json"),
                AgentConfigEntry("~/.aws/amazonq/mcp.json")
            ]
        ),
        AgentDefinition(
            id: "augment",
            displayName: "Augment Code",
            iconName: "Augment",
            configFiles: [
                AgentConfigEntry("~/.augment/config.json")
            ]
        ),
        AgentDefinition(
            id: "claude",
            displayName: "Claude Code",
            iconName: "ClaudeCode",
            configFiles: [
                AgentConfigEntry(title: "settings.json", candidatePaths: [
                    "~/.claude/settings.json",
                    "~/.claude.json"
                ])
            ]
        ),
        AgentDefinition(
            id: "cline",
            displayName: "Cline",
            iconName: "Cline",
            configFiles: [
                AgentConfigEntry("~/Library/Application Support/Code/User/globalStorage/saoudrizwan.claude-dev/settings/cline_mcp_settings.json")
            ]
        ),
        AgentDefinition(
            id: "codex",
            displayName: "Codex",
            iconName: "Codex",
            configFiles: [
                AgentConfigEntry("~/.codex/auth.json"),
                AgentConfigEntry("~/.codex/config.toml")
            ]
        ),
        AgentDefinition(
            id: "cody",
            displayName: "Cody",
            iconName: "Cody",
            configFiles: [
                AgentConfigEntry(title: "config.json", candidatePaths: [
                    "~/Library/Application Support/Cody/config.json",
                    "~/.config/cody/config.json"
                ]),
                AgentConfigEntry("~/.cody/mcp.json")
            ]
        ),
        AgentDefinition(
            id: "continue",
            displayName: "Continue",
            iconName: "Continue",
            configFiles: [
                AgentConfigEntry(title: "config.json", candidatePaths: [
                    "~/.continue/config.json",
                    "~/.continue/config.ts"
                ])
            ]
        ),
        AgentDefinition(
            id: "cursor",
            displayName: "Cursor",
            iconName: "Cursor",
            configFiles: [
                AgentConfigEntry("~/Library/Application Support/Cursor/User/settings.json"),
                AgentConfigEntry("~/Library/Application Support/Cursor/User/keybindings.json"),
                AgentConfigEntry("~/.cursor/mcp.json")
            ]
        ),
                AgentDefinition(
            id: "gemini",
            displayName: "Gemini CLI",
            iconName: "GeminiCLI",
            configFiles: [
                AgentConfigEntry("~/.gemini/settings.json")
            ]
        ),
        AgentDefinition(
            id: "github-copilot",
            displayName: "GitHub Copilot",
            iconName: "GitHubCopilot",
            configFiles: [
                AgentConfigEntry(title: "settings.json", candidatePaths: [
                    "~/Library/Application Support/GitHub Copilot/settings.json",
                    "~/.config/github-copilot/settings.json"
                ]),
                AgentConfigEntry("~/.github-copilot/mcp.json")
            ]
        ),
        AgentDefinition(
            id: "kilocode",
            displayName: "Kilo Code",
            iconName: "KiloCode",
            configFiles: [
                AgentConfigEntry("~/Library/Application Support/Code/User/globalStorage/kilocode.kilo-code/settings/mcp_settings.json")
            ]
        ),
        AgentDefinition(
            id: "kiro",
            displayName: "Kiro",
            iconName: "Kiro",
            configFiles: [
                AgentConfigEntry("~/Library/Application Support/Kiro/User/settings.json"),
                AgentConfigEntry("~/Library/Application Support/Kiro/User/keybindings.json")
            ]
        ),
        AgentDefinition(
            id: "opencode",
            displayName: "OpenCode CLI",
            iconName: "OpenCodeCLI",
            configFiles: [
                AgentConfigEntry(title: "opencode.jsonc", candidatePaths: [
                    "~/.config/opencode/opencode.jsonc",
                    "~/.config/opencode/opencode.json",
                    "~/.config/opencode/config.json"
                ])
            ]
        ),
        AgentDefinition(
            id: "qwen",
            displayName: "Qwen Code",
            iconName: "QwenCode",
            configFiles: [
                AgentConfigEntry("~/.qwen/settings.json")
            ]
        ),
        AgentDefinition(
            id: "trae",
            displayName: "Trae",
            iconName: "Trae",
            configFiles: [
                AgentConfigEntry("~/Library/Application Support/Trae/User/settings.json")
            ]
        ),
        AgentDefinition(
            id: "windsurf",
            displayName: "Windsurf",
            iconName: "Windsurf",
            configFiles: [
                AgentConfigEntry("~/Library/Application Support/Windsurf/User/settings.json"),
                AgentConfigEntry("~/Library/Application Support/Windsurf/User/keybindings.json")
            ]
        )
    ]

    // MARK: - Convenience

    /// 根据 Agent ID 查找定义
    static func definition(for id: String) -> AgentDefinition? {
        all.first { $0.id == id }
    }
}
