//
//  CodexProfile.swift
//  AgentConfig
//

import Foundation

struct CodexProfile: Identifiable, Codable, Equatable {
    let id: UUID
    var name: String
    var configText: String
    var authText: String
    var zshrcText: String
    var appliedConfigText: String
    var appliedAuthText: String
    var appliedZshrcText: String
    var isActive: Bool
    var isDirty: Bool

    init(
        id: UUID = UUID(),
        name: String,
        configText: String,
        authText: String,
        zshrcText: String,
        appliedConfigText: String = "",
        appliedAuthText: String = "",
        appliedZshrcText: String = "",
        isActive: Bool = false,
        isDirty: Bool = false
    ) {
        self.id = id
        self.name = name
        self.configText = configText
        self.authText = authText
        self.zshrcText = zshrcText
        self.appliedConfigText = appliedConfigText
        self.appliedAuthText = appliedAuthText
        self.appliedZshrcText = appliedZshrcText
        self.isActive = isActive
        self.isDirty = isDirty
    }

    static var defaultProfiles: [CodexProfile] {
        let config = """
        model_provider = "OpenAI"
        model = "gpt-5.4"
        review_model = "gpt-5.4"

        [model_providers.OpenAI]
        name = "OpenAI"
        base_url = "https://x2app.top"
        wire_api = "responses"
        requires_openai_auth = true
        """

        let auth = """
        {
          "OPENAI_API_KEY" : "sk-main-0c7e-86f12-preview-token"
        }
        """

        let zshrc = """
        export OPENAI_BASE_URL="https://x2app.top"
        export CODEX_PROFILE="personal"
        """

        return [
            CodexProfile(
                name: "个人配置",
                configText: config,
                authText: auth,
                zshrcText: zshrc,
                appliedConfigText: config,
                appliedAuthText: auth,
                appliedZshrcText: zshrc,
                isActive: true
            )
        ]
    }
}
