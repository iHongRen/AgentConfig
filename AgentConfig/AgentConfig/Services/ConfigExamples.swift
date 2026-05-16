//
//  ConfigExamples.swift
//  AgentConfig
//
//  Created by Claude on 2026/5/17.
//

import Foundation

enum ConfigExamples {

    static func groups(for file: ConfigFile) -> [ConfigExampleGroup] {
        guard let match = AgentDefinitions.match(for: file.url) else { return [] }
        let agentID = match.definition.id
        let path = file.url.standardizedFileURL.path
        let groups: [ConfigExampleGroup]

        switch agentID {
        case "aider":
            groups = aiderExamples(path: path)
        case "amazonq":
            groups = amazonQExamples(path: path)
        case "augment":
            groups = jsonSettingsExample(agentName: "Augment", modelKey: "model", providerKey: "provider")
        case "claude":
            groups = claudeExamples(path: path)
        case "cline":
            groups = clineExamples(path: path)
        case "codex":
            groups = codexExamples(path: path)
        case "continue":
            groups = continueExamples(path: path)
        case "cursor":
            groups = cursorExamples(path: path)
        case "gemini":
            groups = geminiExamples()
        case "github-copilot":
            groups = githubCopilotExamples()
        case "kilocode":
            groups = kiloCodeExamples()
        case "opencode":
            groups = openCodeExamples()
        case "qwen":
            groups = qwenExamples()
        case "trae":
            groups = jsonSettingsExample(agentName: "Trae", modelKey: "model", providerKey: "provider")
        case "windsurf":
            groups = jsonSettingsExample(agentName: "Windsurf", modelKey: "model", providerKey: "provider")
        default:
            groups = []
        }

        return groups.map { group in
            ConfigExampleGroup(
                id: group.id,
                title: group.title,
                summary: group.summary,
                documentationURL: group.documentationURL ?? documentationURL(for: agentID),
                examples: group.examples
            )
        }
    }

    private static func documentationURL(for agentID: String) -> URL? {
        let urls: [String: String] = [
            "aider": "https://aider.chat/docs/config.html",
            "amazonq": "https://docs.aws.amazon.com/cli/latest/userguide/cli-configure-files.html",
            "augment": "https://docs.augmentcode.com/cli/config",
            "claude": "https://docs.claude.com/en/docs/claude-code/settings",
            "cline": "https://docs.cline.bot/cline-cli/configuration",
            "codex": "https://developers.openai.com/codex/config/",
            "continue": "https://docs.continue.dev/customize/deep-dives/configuration",
            "cursor": "https://docs.cursor.com/en/cli/reference/configuration",
            "gemini": "https://github.com/google-gemini/gemini-cli/blob/main/docs/cli/settings.md",
            "github-copilot": "https://code.visualstudio.com/docs/copilot/reference/copilot-settings",
            "kilocode": "https://kilo.ai/docs/getting-started/settings",
            "opencode": "https://opencode.ai/docs/config/",
            "qwen": "https://qwenlm.github.io/qwen-code-docs/en/users/configuration/settings/",
            "trae": "https://docs.trae.ai/ide/model-management",
            "windsurf": "https://docs.windsurf.com/windsurf"
        ]
        return urls[agentID].flatMap(URL.init(string:))
    }

    private static func aiderExamples(path: String) -> [ConfigExampleGroup] {
        if path.hasSuffix(".aider.model.settings.yml") {
            return [group("aider-model", title: "模型参数示例", summary: "为自定义模型声明上下文窗口、编辑格式和弱模型等参数。", examples: [
                example("aider-model-settings", title: "自定义模型设置", language: "yaml", code: """
                - name: openai/my-custom-model
                  edit_format: diff
                  weak_model_name: openai/gpt-4o-mini
                  use_repo_map: true
                  max_context_window: 128000
                """)
            ])]
        }

        return [group("aider-config", title: "基础配置示例", summary: "配置默认模型和 API Key 环境变量名称。", examples: [
            example("aider-conf", title: "默认模型与 API Key", language: "yaml", code: """
            model: openai/gpt-4.1
            openai-api-key: YOUR_API_KEY
            auto-commits: false
            dark-mode: true
            """)
        ])]
    }

    private static func amazonQExamples(path: String) -> [ConfigExampleGroup] {
        if path.hasSuffix("credentials") {
            return [group("aws-credentials", title: "凭证文件示例", summary: "Amazon Q 可复用 AWS CLI profile 凭证。", examples: [
                example("aws-credentials", title: "命名 Profile", language: "ini", code: """
                [default]
                aws_access_key_id = YOUR_ACCESS_KEY_ID
                aws_secret_access_key = YOUR_SECRET_ACCESS_KEY

                [work]
                aws_access_key_id = YOUR_WORK_ACCESS_KEY_ID
                aws_secret_access_key = YOUR_WORK_SECRET_ACCESS_KEY
                """)
            ])]
        }

        return [group("aws-config", title: "AWS Profile 示例", summary: "配置 Amazon Q 使用的区域和 profile。", examples: [
            example("aws-config", title: "默认区域", language: "ini", code: """
            [default]
            region = us-east-1
            output = json

            [profile work]
            region = us-west-2
            output = json
            """)
        ])]
    }

    private static func claudeExamples(path: String) -> [ConfigExampleGroup] {
        if path.hasSuffix(".claude.json") {
            return [group("claude-global", title: "全局状态示例", summary: "用于 Claude Code 全局配置状态；实际字段会随版本变化。", examples: [
                example("claude-json", title: "全局偏好模板", language: "json", code: """
                {
                  "theme": "dark",
                  "preferredNotifChannel": "terminal_bell"
                }
                """)
            ])]
        }

        return [group("claude-settings", title: "设置示例", summary: "配置默认模型、环境变量和工具权限。", examples: [
            example("claude-settings", title: "模型与权限", language: "json", code: """
            {
              "model": "claude-sonnet-4-6",
              "env": {
                "ANTHROPIC_API_KEY": "YOUR_API_KEY"
              },
              "permissions": {
                "allow": [
                  "Bash(git status:*)",
                  "Read(*)"
                ]
              }
            }
            """)
        ])]
    }

    private static func clineExamples(path: String) -> [ConfigExampleGroup] {
        if path.hasSuffix("providers.json") {
            return [group("cline-providers", title: "Provider 示例", summary: "配置 API Provider 和默认模型。", examples: [
                example("cline-providers", title: "OpenAI Compatible Provider", language: "json", code: """
                {
                  "providers": [
                    {
                      "id": "openai-compatible",
                      "name": "OpenAI Compatible",
                      "baseUrl": "https://example.com/v1",
                      "apiKey": "YOUR_API_KEY",
                      "models": ["model-name"]
                    }
                  ],
                  "defaultProviderId": "openai-compatible",
                  "defaultModelId": "model-name"
                }
                """)
            ])]
        }

        return jsonSettingsExample(agentName: "Cline", modelKey: "defaultModelId", providerKey: "defaultProviderId")
    }

    private static func codexExamples(path: String) -> [ConfigExampleGroup] {
        if path.hasSuffix("auth.json") {
            return [group("codex-auth", title: "认证文件示例", summary: "用于保存 Codex CLI 的认证信息。", examples: [
                example("codex-auth", title: "API Key 模板", language: "json", code: """
                {
                  "OPENAI_API_KEY": "YOUR_API_KEY"
                }
                """)
            ])]
        }

        return [group("codex-config", title: "模型配置示例", summary: "设置默认模型和推理强度。", examples: [
            example("codex-config", title: "默认模型", language: "toml", code: """
            model = "gpt-5-codex"
            model_reasoning_effort = "medium"

            [model_providers.openai]
            name = "OpenAI"
            base_url = "https://api.openai.com/v1"
            env_key = "OPENAI_API_KEY"
            """)
        ])]
    }

    private static func continueExamples(path: String) -> [ConfigExampleGroup] {
        if path.hasSuffix(".env") {
            return [group("continue-env", title: "环境变量示例", summary: "把密钥放在 .env 文件中，再从配置引用。", examples: [
                example("continue-env", title: "API Key", language: "shell", code: """
                OPENAI_API_KEY=YOUR_API_KEY
                ANTHROPIC_API_KEY=YOUR_API_KEY
                """)
            ])]
        }

        if path.hasSuffix("config.ts") {
            return [group("continue-ts", title: "TypeScript 配置示例", summary: "用 TypeScript 定义模型列表。", examples: [
                example("continue-ts", title: "模型配置", language: "typescript", code: """
                export default {
                  models: [
                    {
                      title: "GPT-4.1",
                      provider: "openai",
                      model: "gpt-4.1",
                      apiKey: process.env.OPENAI_API_KEY
                    }
                  ]
                };
                """)
            ])]
        }

        return [group("continue-yaml", title: "YAML 配置示例", summary: "配置模型和自动补全模型。", examples: [
            example("continue-yaml", title: "模型列表", language: "yaml", code: """
            name: Local Assistant
            version: 1.0.0
            models:
              - name: GPT-4.1
                provider: openai
                model: gpt-4.1
                apiKey: YOUR_API_KEY
            autocomplete:
              provider: openai
              model: gpt-4.1-mini
            """)
        ])]
    }

    private static func cursorExamples(path: String) -> [ConfigExampleGroup] {
        if path.hasSuffix("cli-config.json") {
            return [group("cursor-cli", title: "CLI 配置示例", summary: "配置 Cursor CLI 的默认行为。", examples: [
                example("cursor-cli", title: "CLI 模板", language: "json", code: """
                {
                  "editor": "cursor",
                  "model": "auto"
                }
                """)
            ])]
        }

        return [group("cursor-settings", title: "编辑器设置示例", summary: "配置 AI 相关设置，字段会随 Cursor 版本变化。", examples: [
            example("cursor-settings", title: "模型偏好", language: "json", code: """
            {
              "cursor.general.disableHttp2": false,
              "cursor.chat.defaultModel": "auto"
            }
            """)
        ])]
    }

    private static func geminiExamples() -> [ConfigExampleGroup] {
        [group("gemini-settings", title: "Gemini CLI 设置示例", summary: "设置默认模型和认证方式。", examples: [
            example("gemini-settings", title: "默认模型", language: "json", code: """
            {
              "model": "gemini-2.5-pro",
              "selectedAuthType": "api-key",
              "apiKey": "YOUR_API_KEY"
            }
            """)
        ])]
    }

    private static func githubCopilotExamples() -> [ConfigExampleGroup] {
        [group("copilot-settings", title: "VS Code Copilot 设置示例", summary: "GitHub Copilot 通常通过编辑器登录，这里展示可配置的模型偏好。", examples: [
            example("copilot-settings", title: "Copilot 设置", language: "json", code: """
            {
              "github.copilot.chat.localeOverride": "zh-CN",
              "github.copilot.nextEditSuggestions.enabled": true
            }
            """)
        ])]
    }

    private static func kiloCodeExamples() -> [ConfigExampleGroup] {
        [group("kilo-settings", title: "Kilo Code 设置示例", summary: "配置 Provider、模型和 API Key。", examples: [
            example("kilo-settings", title: "Provider 模板", language: "jsonc", code: """
            {
              "providers": {
                "openai-compatible": {
                  "baseUrl": "https://example.com/v1",
                  "apiKey": "YOUR_API_KEY",
                  "model": "model-name"
                }
              }
            }
            """)
        ])]
    }

    private static func openCodeExamples() -> [ConfigExampleGroup] {
        [group("opencode-config", title: "OpenCode 配置示例", summary: "配置模型 Provider 和默认模型。", examples: [
            example("opencode-config", title: "Provider 模板", language: "json", code: """
            {
              "$schema": "https://opencode.ai/config.json",
              "provider": {
                "openai": {
                  "npm": "@ai-sdk/openai",
                  "models": {
                    "gpt-4.1": {}
                  },
                  "options": {
                    "apiKey": "YOUR_API_KEY"
                  }
                }
              },
              "model": "openai/gpt-4.1"
            }
            """)
        ])]
    }

    private static func qwenExamples() -> [ConfigExampleGroup] {
        [group("qwen-settings", title: "Qwen Code 设置示例", summary: "配置模型、Base URL 和 API Key。", examples: [
            example("qwen-settings", title: "OpenAI Compatible", language: "json", code: """
            {
              "model": "qwen3-coder-plus",
              "baseUrl": "https://dashscope.aliyuncs.com/compatible-mode/v1",
              "apiKey": "YOUR_API_KEY"
            }
            """)
        ])]
    }

    private static func jsonSettingsExample(agentName: String, modelKey: String, providerKey: String) -> [ConfigExampleGroup] {
        [group("generic-json-\(agentName)", title: "\(agentName) 设置示例", summary: "配置默认 Provider、模型和 API Key。", examples: [
            example("generic-json-\(agentName)", title: "Provider 模板", language: "json", code: """
            {
              "\(providerKey)": "openai-compatible",
              "\(modelKey)": "model-name",
              "apiKey": "YOUR_API_KEY",
              "baseUrl": "https://example.com/v1"
            }
            """)
        ])]
    }

    private static func group(
        _ id: String,
        title: String,
        summary: String?,
        documentationURL: String? = nil,
        examples: [ConfigExample]
    ) -> ConfigExampleGroup {
        ConfigExampleGroup(
            id: id,
            title: title,
            summary: summary,
            documentationURL: documentationURL.flatMap(URL.init(string:)),
            examples: examples
        )
    }

    private static func example(
        _ id: String,
        title: String,
        description: String? = nil,
        language: String,
        code: String
    ) -> ConfigExample {
        ConfigExample(id: id, title: title, description: description, language: language, code: code)
    }
}
