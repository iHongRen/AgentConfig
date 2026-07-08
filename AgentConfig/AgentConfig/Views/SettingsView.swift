//
//  SettingsView.swift
//  AgentConfig
//
//  Created by cxy on 2026/5/11.
//

import SwiftUI

/// 应用设置视图
///
/// 提供以下设置项：
/// - 外观模式：浅色 / 深色 / 跟随系统
/// - 界面语言：English / 简体中文
///
/// 每次设置变更后立即调用 `AppViewModel.updateSettings(_:)` 持久化。
struct SettingsView: View {

    @EnvironmentObject var appViewModel: AppViewModel

    @State private var appearanceMode: AppearanceMode = .system
    @State private var language: AppLanguage = L10n.automaticLanguage

    var body: some View {
        VStack(spacing: 16) {
            appearanceSection
            languageSection
            Spacer(minLength: 0)
        }
        .padding(20)
        .frame(minWidth: 440, idealWidth: 480, maxWidth: 560)
        .background(Color(nsColor: .windowBackgroundColor))
        .navigationTitle(L10n.tr("settings.title", value: "Settings"))
        .onAppear {
            appearanceMode = appViewModel.settings.appearanceMode
            language = appViewModel.settings.language
        }
    }

    // MARK: - 外观

    private var appearanceSection: some View {
        SettingsCard(
            title: L10n.tr("settings.appearance", value: "Appearance"),
            icon: "paintbrush"
        ) {
            VStack(spacing: 10) {
                ForEach(AppearanceMode.allCases, id: \.self) { mode in
                    OptionRow(
                        title: mode.displayName,
                        icon: mode.iconName,
                        isSelected: appearanceMode == mode
                    ) {
                        appearanceMode = mode
                        saveSettings(appearanceMode: mode)
                    }
                }
            }
            .padding(12)
        }
    }

    // MARK: - 语言

    private var languageSection: some View {
        SettingsCard(
            title: L10n.tr("settings.language", value: "Language"),
            icon: "globe"
        ) {
            VStack(spacing: 10) {
                ForEach(AppLanguage.allCases, id: \.self) { lang in
                    OptionRow(
                        title: lang.displayName,
                        icon: lang.iconName,
                        isSelected: language == lang
                    ) {
                        language = lang
                        saveSettings(language: lang)
                    }
                }
            }
            .padding(12)
        }
    }

    // MARK: - Private Helpers

    private func saveSettings(
        appearanceMode: AppearanceMode? = nil,
        language: AppLanguage? = nil
    ) {
        var updated = appViewModel.settings
        updated.appearanceMode = appearanceMode ?? self.appearanceMode
        updated.language = language ?? self.language
        appViewModel.updateSettings(updated)
    }
}

// MARK: - 卡片容器

private struct SettingsCard<Content: View>: View {
    let title: String
    let icon: String
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.secondary)
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)
            }
            .padding(.horizontal, 14)
            .padding(.top, 14)
            .padding(.bottom, 10)

            content()
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color(nsColor: .controlBackgroundColor))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .strokeBorder(Color(nsColor: .separatorColor).opacity(0.6))
                        .allowsHitTesting(false)
                )
                .padding(.horizontal, 14)
                .padding(.bottom, 14)
        }
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(nsColor: .textBackgroundColor).opacity(0.5))
        )
    }
}

// MARK: - 选项行

private struct OptionRow: View {
    let title: String
    let icon: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.system(size: 16, weight: .medium))
                    .frame(width: 22, height: 22)
                    .foregroundStyle(isSelected ? Color.accentColor : Color(nsColor: .secondaryLabelColor))

                Text(title)
                    .font(.system(size: 14))
                    .foregroundStyle(isSelected ? Color.accentColor : Color.primary)

                Spacer()

                if isSelected {
                    Image(systemName: "checkmark")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Color.accentColor)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            .contentShape(Rectangle())
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(isSelected ? Color.accentColor.opacity(0.12) : Color.clear)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(isSelected ? Color.accentColor.opacity(0.5) : Color(nsColor: .separatorColor).opacity(0.4))
                    .allowsHitTesting(false)
            )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - 选项图标

private extension AppearanceMode {
    var iconName: String {
        switch self {
        case .light: return "sun.max"
        case .dark: return "moon"
        case .system: return "circle.lefthalf.filled"
        }
    }
}

private extension AppLanguage {
    var iconName: String {
        switch self {
        case .en: return "character.book.closed"
        case .zhHans: return "character"
        }
    }
}
