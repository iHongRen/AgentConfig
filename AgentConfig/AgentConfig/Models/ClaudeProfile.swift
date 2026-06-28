//
//  ClaudeProfile.swift
//  AgentConfig
//

import Foundation

struct ClaudeProfile: Identifiable, Codable, Equatable {
    let id: UUID
    var name: String
    var settingsText: String
    var claudeJSONText: String
    var appliedSettingsText: String
    var appliedClaudeJSONText: String
    var isActive: Bool
    var isDirty: Bool
    var settingsEditorHeight: Double?
    var claudeJSONEditorHeight: Double?

    init(
        id: UUID = UUID(),
        name: String,
        settingsText: String,
        claudeJSONText: String,
        appliedSettingsText: String = "",
        appliedClaudeJSONText: String = "",
        isActive: Bool = false,
        isDirty: Bool = false,
        settingsEditorHeight: Double? = nil,
        claudeJSONEditorHeight: Double? = nil
    ) {
        self.id = id
        self.name = name
        self.settingsText = settingsText
        self.claudeJSONText = claudeJSONText
        self.appliedSettingsText = appliedSettingsText
        self.appliedClaudeJSONText = appliedClaudeJSONText
        self.isActive = isActive
        self.isDirty = isDirty
        self.settingsEditorHeight = settingsEditorHeight
        self.claudeJSONEditorHeight = claudeJSONEditorHeight
    }
}
