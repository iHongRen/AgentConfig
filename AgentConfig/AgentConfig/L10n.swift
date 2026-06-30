//
//  L10n.swift
//  AgentConfig
//

import Foundation

enum L10n {
    private static let tableName = "Localizable"

    static func tr(_ key: String, value: String) -> String {
        NSLocalizedString(key, tableName: tableName, bundle: bundle, value: value, comment: "")
    }

    static func format(_ key: String, value: String, _ arguments: CVarArg...) -> String {
        String(format: tr(key, value: value), locale: Locale.current, arguments: arguments)
    }

    static var automaticLanguage: AppLanguage {
        let preferredLanguage = Locale.preferredLanguages.first?.lowercased() ?? ""
        return preferredLanguage.hasPrefix("zh") ? .zhHans : .en
    }

    static var currentLanguage: AppLanguage {
        let settings = AppSettings.load()
        return settings.language
    }

    private static var bundle: Bundle {
        let languageCode = currentLanguage.rawValue
        guard
            let path = Bundle.main.path(forResource: languageCode, ofType: "lproj"),
            let localizedBundle = Bundle(path: path)
        else {
            return Bundle.main
        }
        return localizedBundle
    }
}
