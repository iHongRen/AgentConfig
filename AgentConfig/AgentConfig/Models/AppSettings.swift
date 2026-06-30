//
//  AppSettings.swift
//  AgentConfig
//
//  Created by cxy on 2026/5/11.
//

import Foundation

enum LastVisitedPage: Codable, Equatable {
    case configFile(path: String)
    case codexProfile(id: UUID)
    case claudeProfile(id: UUID)

    private enum CodingKeys: String, CodingKey {
        case kind
        case path
        case profileID
    }

    private enum Kind: String, Codable {
        case configFile
        case codexProfile
        case claudeProfile
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let kind = try container.decode(Kind.self, forKey: .kind)
        switch kind {
        case .configFile:
            let path = try container.decode(String.self, forKey: .path)
            self = .configFile(path: path)
        case .codexProfile:
            let id = try container.decode(UUID.self, forKey: .profileID)
            self = .codexProfile(id: id)
        case .claudeProfile:
            let id = try container.decode(UUID.self, forKey: .profileID)
            self = .claudeProfile(id: id)
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .configFile(let path):
            try container.encode(Kind.configFile, forKey: .kind)
            try container.encode(path, forKey: .path)
        case .codexProfile(let id):
            try container.encode(Kind.codexProfile, forKey: .kind)
            try container.encode(id, forKey: .profileID)
        case .claudeProfile(let id):
            try container.encode(Kind.claudeProfile, forKey: .kind)
            try container.encode(id, forKey: .profileID)
        }
    }
}

// MARK: - AppearanceMode

/// 应用外观模式
enum AppearanceMode: String, Codable, CaseIterable {
    case light
    case dark
    case system

    var displayName: String {
        switch self {
        case .light:
            return L10n.tr("appearance.light", value: "Light")
        case .dark:
            return L10n.tr("appearance.dark", value: "Dark")
        case .system:
            return L10n.tr("appearance.system", value: "System")
        }
    }
}

// MARK: - AppLanguage

/// 应用语言设置
enum AppLanguage: String, Codable, CaseIterable {
    case en
    case zhHans = "zh-Hans"

    static var allCases: [AppLanguage] {
        [.en, .zhHans]
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let rawValue = (try? container.decode(String.self)) ?? ""

        switch rawValue.lowercased() {
        case "zh-hans", "zh_cn", "zh-cn", "zh":
            self = .zhHans
        case "system":
            self = L10n.automaticLanguage
        case "en", "en-us", "en-gb", "":
            self = .en
        default:
            self = .en
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }

    var displayName: String {
        switch self {
        case .en:
            return "English"
        case .zhHans:
            return "简体中文"
        }
    }
}

// MARK: - AppSettings

/// 应用全局设置，持久化到 UserDefaults
struct AppSettings: Codable {
    /// 外观模式
    var appearanceMode: AppearanceMode = .system

    /// 界面语言
    var language: AppLanguage = L10n.automaticLanguage

    /// 用户手动添加的自定义配置文件路径
    var customPaths: [URL] = []

    /// 用户从列表中隐藏的文件路径（不从实际磁盘删除）
    var hiddenFilePaths: [URL] = []

    /// 用户手动添加到指定分类的文件路径
    var categoryFilePaths: [String: [URL]] = [:]

    /// 应用上次停留的配置页
    var lastVisitedPage: LastVisitedPage?

    enum CodingKeys: String, CodingKey {
        case appearanceMode
        case language
        case customPaths
        case hiddenFilePaths
        case categoryFilePaths
        case lastVisitedPage
    }

    init() {}

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        appearanceMode = try container.decodeIfPresent(AppearanceMode.self, forKey: .appearanceMode) ?? .system
        language = try container.decodeIfPresent(AppLanguage.self, forKey: .language) ?? L10n.automaticLanguage
        customPaths = try container.decodeIfPresent([URL].self, forKey: .customPaths) ?? []
        hiddenFilePaths = try container.decodeIfPresent([URL].self, forKey: .hiddenFilePaths) ?? []
        categoryFilePaths = try container.decodeIfPresent([String: [URL]].self, forKey: .categoryFilePaths) ?? [:]
        lastVisitedPage = try container.decodeIfPresent(LastVisitedPage.self, forKey: .lastVisitedPage)
    }

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
