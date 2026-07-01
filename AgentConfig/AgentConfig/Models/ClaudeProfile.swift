//
//  ClaudeProfile.swift
//  AgentConfig
//

import Foundation

struct ClaudeProfile: Identifiable, Codable, Equatable, AgentProfileRecord {
    static let defaultClaudeJSONText = """
    {
      "hasCompletedOnboarding": true
    }
    """
    static let defaultZshrcText = ""

    let id: UUID
    var name: String
    var settingsText: String
    var claudeJSONText: String
    var zshrcText: String
    var appliedSettingsText: String
    var appliedClaudeJSONText: String
    var appliedZshrcText: String
    var isActive: Bool
    var isDirty: Bool
    var settingsEditorHeight: Double?
    var claudeJSONEditorHeight: Double?
    var zshrcEditorHeight: Double?

    private enum CodingKeys: String, CodingKey {
        case id
        case name
        case settingsText
        case claudeJSONText
        case zshrcText
        case appliedSettingsText
        case appliedClaudeJSONText
        case appliedZshrcText
        case isActive
        case isDirty
        case settingsEditorHeight
        case claudeJSONEditorHeight
        case zshrcEditorHeight
    }

    init(
        id: UUID = UUID(),
        name: String,
        settingsText: String,
        claudeJSONText: String,
        zshrcText: String = ClaudeProfile.defaultZshrcText,
        appliedSettingsText: String = "",
        appliedClaudeJSONText: String = "",
        appliedZshrcText: String = ClaudeProfile.defaultZshrcText,
        isActive: Bool = false,
        isDirty: Bool = false,
        settingsEditorHeight: Double? = nil,
        claudeJSONEditorHeight: Double? = nil,
        zshrcEditorHeight: Double? = nil
    ) {
        self.id = id
        self.name = name
        self.settingsText = settingsText
        self.claudeJSONText = claudeJSONText
        self.zshrcText = zshrcText
        self.appliedSettingsText = appliedSettingsText
        self.appliedClaudeJSONText = appliedClaudeJSONText
        self.appliedZshrcText = appliedZshrcText
        self.isActive = isActive
        self.isDirty = isDirty
        self.settingsEditorHeight = settingsEditorHeight
        self.claudeJSONEditorHeight = claudeJSONEditorHeight
        self.zshrcEditorHeight = zshrcEditorHeight
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        name = try container.decodeIfPresent(String.self, forKey: .name) ?? ""
        settingsText = try container.decodeIfPresent(String.self, forKey: .settingsText) ?? "{}"
        claudeJSONText = try container.decodeIfPresent(String.self, forKey: .claudeJSONText) ?? Self.defaultClaudeJSONText
        zshrcText = try container.decodeIfPresent(String.self, forKey: .zshrcText) ?? Self.defaultZshrcText
        appliedSettingsText = try container.decodeIfPresent(String.self, forKey: .appliedSettingsText) ?? settingsText
        appliedClaudeJSONText = try container.decodeIfPresent(String.self, forKey: .appliedClaudeJSONText) ?? claudeJSONText
        appliedZshrcText = try container.decodeIfPresent(String.self, forKey: .appliedZshrcText) ?? zshrcText
        isActive = try container.decodeIfPresent(Bool.self, forKey: .isActive) ?? false
        isDirty = try container.decodeIfPresent(Bool.self, forKey: .isDirty) ?? false
        settingsEditorHeight = try container.decodeIfPresent(Double.self, forKey: .settingsEditorHeight)
        claudeJSONEditorHeight = try container.decodeIfPresent(Double.self, forKey: .claudeJSONEditorHeight)
        zshrcEditorHeight = try container.decodeIfPresent(Double.self, forKey: .zshrcEditorHeight)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)

        try container.encode(id, forKey: .id)
        try container.encode(name, forKey: .name)
        try container.encode(settingsText, forKey: .settingsText)
        try container.encode(claudeJSONText, forKey: .claudeJSONText)
        try container.encode(zshrcText, forKey: .zshrcText)
        try container.encode(appliedSettingsText, forKey: .appliedSettingsText)
        try container.encode(appliedClaudeJSONText, forKey: .appliedClaudeJSONText)
        try container.encode(appliedZshrcText, forKey: .appliedZshrcText)
        try container.encode(isActive, forKey: .isActive)
        try container.encode(isDirty, forKey: .isDirty)
        try container.encodeIfPresent(settingsEditorHeight, forKey: .settingsEditorHeight)
        try container.encodeIfPresent(claudeJSONEditorHeight, forKey: .claudeJSONEditorHeight)
        try container.encodeIfPresent(zshrcEditorHeight, forKey: .zshrcEditorHeight)
    }
}
