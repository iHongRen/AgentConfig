//
//  AppSettings.swift
//  AgentConfig
//
//  Created by cxy on 2026/5/11.
//

import Foundation

// MARK: - AppearanceMode

/// 应用外观模式
enum AppearanceMode: String, Codable, CaseIterable {
    case light
    case dark
    case system

    var displayName: String {
        switch self {
        case .light:
            return NSLocalizedString("appearance.light", value: "Light", comment: "Light appearance mode")
        case .dark:
            return NSLocalizedString("appearance.dark", value: "Dark", comment: "Dark appearance mode")
        case .system:
            return NSLocalizedString("appearance.system", value: "System", comment: "System appearance mode")
        }
    }
}

// MARK: - AppLanguage

/// 应用语言设置
enum AppLanguage: String, Codable, CaseIterable {
    case en
    case zhHans = "zh-Hans"
    case system

    var displayName: String {
        switch self {
        case .en:
            return "English"
        case .zhHans:
            return "简体中文"
        case .system:
            return NSLocalizedString("language.system", value: "System", comment: "System language setting")
        }
    }
}

// MARK: - AppSettings

/// 应用全局设置，持久化到 UserDefaults
struct AppSettings: Codable {
    /// 保存环境变量文件后是否自动执行 source
    var autoSource: Bool = true

    /// 外观模式
    var appearanceMode: AppearanceMode = .system

    /// 界面语言
    var language: AppLanguage = .system

    /// 用户手动添加的自定义配置文件路径
    var customPaths: [URL] = []

    /// 用户从列表中隐藏的文件路径（不从实际磁盘删除）
    var hiddenFilePaths: [URL] = []

    // MARK: - UserDefaults Key

    static let userDefaultsKey = "AppSettings"

    // MARK: - Persistence

    /// 从 UserDefaults 加载设置，若不存在则返回默认值
    static func load() -> AppSettings {
        guard
            let data = UserDefaults.standard.data(forKey: userDefaultsKey),
            let settings = try? JSONDecoder().decode(AppSettings.self, from: data)
        else {
            return AppSettings()
        }
        return settings
    }

    /// 将设置保存到 UserDefaults
    func save() {
        guard let data = try? JSONEncoder().encode(self) else { return }
        UserDefaults.standard.set(data, forKey: AppSettings.userDefaultsKey)
    }
}
