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
            id: "claude",
            displayName: "Claude Code",
            configFiles: [
                AgentConfigEntry(title: "settings.json", candidatePaths: [
                    "~/.claude/settings.json",
                    "~/.claude.json"
                ])
            ]
        ),
        AgentDefinition(
            id: "qwen",
            displayName: "Qwen Code",
            configFiles: [
                AgentConfigEntry("~/.qwen/oauth_creds.json"),
                AgentConfigEntry("~/.qwen/settings.json"),
            ]
        ),
        AgentDefinition(
            id: "codex",
            displayName: "Codex",
            configFiles: [
                AgentConfigEntry("~/.codex/auth.json"),
                AgentConfigEntry("~/.codex/config.toml")
            ]
        ),
        AgentDefinition(
            id: "opencode",
            displayName: "OpenCode CLI",
            configFiles: [
                AgentConfigEntry(title: "config.json", candidatePaths: [
                    "~/.opencode/config.json",
                    "~/.config/opencode/config.json"
                ]),
                AgentConfigEntry("~/.opencode/config.toml"),
                AgentConfigEntry("~/.opencode/agents.json")
            ]
        ),
        AgentDefinition(
            id: "github-copilot",
            displayName: "GitHub Copilot",
            configFiles: [
                AgentConfigEntry("~/.config/github-copilot/settings.json"),
                AgentConfigEntry("~/.config/github-copilot/mcp.json")
            ]
        ),
        AgentDefinition(
            id: "cursor",
            displayName: "Cursor",
            configFiles: [
                AgentConfigEntry("~/Library/Application Support/Cursor/User/settings.json"),
                AgentConfigEntry("~/Library/Application Support/Cursor/User/keybindings.json"),
                AgentConfigEntry("~/Library/Application Support/Cursor/User/mcp.json"),
                AgentConfigEntry("~/Library/Application Support/Cursor/User/snippets.json")
            ]
        ),
        AgentDefinition(
            id: "windsurf",
            displayName: "Windsurf",
            configFiles: [
                AgentConfigEntry("~/Library/Application Support/Windsurf/User/settings.json"),
                AgentConfigEntry("~/Library/Application Support/Windsurf/User/keybindings.json")
            ]
        ),

        AgentDefinition(
            id: "aider",
            displayName: "Aider",
            configFiles: [
                AgentConfigEntry("~/.aider.conf.yml"),
                AgentConfigEntry("~/.aider.model.settings.yml")
            ]
        ),
        AgentDefinition(
            id: "gemini",
            displayName: "Gemini CLI",
            configFiles: [
                AgentConfigEntry(title: "settings.json", candidatePaths: [
                    "~/.gemini/settings.json",
                    "~/.config/gemini/settings.json"
                ]),
                AgentConfigEntry("~/.gemini/config.json")
            ]
        ),
        AgentDefinition(
            id: "cline",
            displayName: "Cline",
            configFiles: [
                AgentConfigEntry("~/Library/Application Support/Code/User/globalStorage/saoudrizwan.claude-dev/settings/cline_mcp_settings.json"),
                AgentConfigEntry("~/Library/Application Support/Code/User/globalStorage/saoudrizwan.claude-dev/settings/cline_custom_instructions.md")
            ]
        ),
        AgentDefinition(
            id: "kilocode",
            displayName: "Kilo Code",
            configFiles: [
                AgentConfigEntry("~/Library/Application Support/Code/User/globalStorage/kilocode.kilo-code/settings/mcp_settings.json"),
            ]
        ),
        AgentDefinition(
            id: "trae",
            displayName: "Trae",
            configFiles: [
                AgentConfigEntry("~/Library/Application Support/Trae/User/settings.json"),
            ]
        ),
        AgentDefinition(
            id: "cody",
            displayName: "Cody",
            configFiles: [
                AgentConfigEntry("~/.config/cody/config.json"),
                AgentConfigEntry("~/.config/cody/mcp.json")
            ]
        ),
        AgentDefinition(
            id: "augment",
            displayName: "Augment",
            configFiles: [
                AgentConfigEntry("~/Library/Application Support/Augment/User/settings.json"),
            ]
        )
    ]

    // MARK: - Convenience

    /// 根据 Agent ID 查找定义
    static func definition(for id: String) -> AgentDefinition? {
        all.first { $0.id == id }
    }
}
