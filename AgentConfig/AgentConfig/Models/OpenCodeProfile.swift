//
//  OpenCodeProfile.swift
//  AgentConfig
//

import Foundation

struct OpenCodeProfile: Identifiable, Codable, Equatable, AgentProfileRecord {
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

    static var defaultProfiles: [OpenCodeProfile] {
        let config = """
        {
          "$schema": "https://opencode.ai/config.json",
          "provider": {
            "example": {
              "npm": "@ai-sdk/openai-compatible",
              "name": "Example Provider",
              "options": {
                "baseURL": "https://api.example.com/v1",
                "apiKey": "{env:OPENAI_API_KEY}"
              },
              "models": {
                "gpt-5.1": {
                  "name": "GPT-5.1"
                }
              }
            }
          },
          "model": "example/gpt-5.1",
          "small_model": "example/gpt-5.1"
        }
        """

        let auth = """
        {
        }
        """

        let zshrc = """
        export OPENAI_API_KEY="your-api-key"
        """

        return [
            OpenCodeProfile(
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
