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
    var configEditorHeight: Double?
    var authEditorHeight: Double?
    var zshrcEditorHeight: Double?

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
        isDirty: Bool = false,
        configEditorHeight: Double? = nil,
        authEditorHeight: Double? = nil,
        zshrcEditorHeight: Double? = nil
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
        self.configEditorHeight = configEditorHeight
        self.authEditorHeight = authEditorHeight
        self.zshrcEditorHeight = zshrcEditorHeight
    }

    static var defaultProfiles: [CodexProfile] {
        let config = """
        model_provider = "OpenAI"
        model = "gpt-5.4"
        review_model = "gpt-5.4"

        [model_providers.OpenAI]
        name = "OpenAI"
        base_url = "https://xxx.com"
        wire_api = "responses"
        requires_openai_auth = true
        """

        let auth = """
        {
          "OPENAI_API_KEY" : "sk-main-0c7e-86f12-preview-token"
        }
        """

        let zshrc = """
        """

        return [
            CodexProfile(
                name: L10n.tr("profile.newName", value: "New Profile"),
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
