//
//  QwenProfile.swift
//  AgentConfig
//

import Foundation

struct QwenProfile: Identifiable, Codable, Equatable, AgentProfileRecord {
    let id: UUID
    var name: String
    var settingsText: String
    var envText: String
    var zshrcText: String
    var appliedSettingsText: String
    var appliedEnvText: String
    var appliedZshrcText: String
    var isActive: Bool
    var isDirty: Bool
    var settingsEditorHeight: Double?
    var envEditorHeight: Double?
    var zshrcEditorHeight: Double?

    init(
        id: UUID = UUID(),
        name: String,
        settingsText: String,
        envText: String,
        zshrcText: String,
        appliedSettingsText: String = "",
        appliedEnvText: String = "",
        appliedZshrcText: String = "",
        isActive: Bool = false,
        isDirty: Bool = false,
        settingsEditorHeight: Double? = nil,
        envEditorHeight: Double? = nil,
        zshrcEditorHeight: Double? = nil
    ) {
        self.id = id
        self.name = name
        self.settingsText = settingsText
        self.envText = envText
        self.zshrcText = zshrcText
        self.appliedSettingsText = appliedSettingsText
        self.appliedEnvText = appliedEnvText
        self.appliedZshrcText = appliedZshrcText
        self.isActive = isActive
        self.isDirty = isDirty
        self.settingsEditorHeight = settingsEditorHeight
        self.envEditorHeight = envEditorHeight
        self.zshrcEditorHeight = zshrcEditorHeight
    }

    static var defaultProfiles: [QwenProfile] {
        let settings = """
        {
          "modelProviders": {
            "openai": [
              {
                "id": "qwen/qwen3-coder",
                "name": "qwen/qwen3-coder",
                "baseUrl": "https://https://github.com/iHongRen/v1"
              }
            ]
          },
          "security": {
            "auth": {
              "selectedType": "openai"
            }
          },
          "model": {
            "name": "qwen/qwen3-coder"
          }
        }
        """

        let env = """
        OPENAI_API_KEY=your-api-key
        """

        let zshrc = ""

        return [
            QwenProfile(
                name: L10n.tr("profile.newName", value: "New Profile"),
                settingsText: settings,
                envText: env,
                zshrcText: zshrc,
                appliedSettingsText: settings,
                appliedEnvText: env,
                appliedZshrcText: zshrc,
                isActive: true
            )
        ]
    }
}
