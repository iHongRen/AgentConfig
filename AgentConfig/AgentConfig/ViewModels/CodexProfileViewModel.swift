//
//  CodexProfileViewModel.swift
//  AgentConfig
//

import Combine
import Foundation

struct APIValidationResult {
    let isValid: Bool
    let message: String
    let statusCode: Int?
    let baseURL: String
}

final class CodexProfileViewModel: ObservableObject {

    private static let profileNameMaxLength = 10

    @Published var profiles: [CodexProfile] = []
    @Published var selectedProfileID: UUID?
    @Published var lastErrorMessage: String?
    @Published var lastAppliedProfileName: String?
    @Published private(set) var didFinishInitialLoad: Bool = false

    private let service: CodexProfileServiceProtocol
    private var persistTask: Task<Void, Never>?
    private var hasRestoredInitialSelection = false

    init(service: CodexProfileServiceProtocol? = nil) {
        self.service = service ?? CodexProfileService()
        Task { await loadProfiles() }
    }

    var selectedProfile: CodexProfile? {
        guard let selectedProfileID else { return nil }
        return profiles.first { $0.id == selectedProfileID }
    }

    func loadProfiles() async {
        do {
            let loadedProfiles = try await service.loadProfiles()
            profiles = loadedProfiles.map { profile in
                var updatedProfile = profile
                updatedProfile.isDirty = isProfileDirty(updatedProfile)
                return updatedProfile
            }
            selectedProfileID = selectedProfileID ?? loadedProfiles.first(where: \.isActive)?.id ?? loadedProfiles.first?.id
        } catch {
            profiles = CodexProfile.defaultProfiles
            selectedProfileID = profiles.first?.id
            lastErrorMessage = error.localizedDescription
        }
        didFinishInitialLoad = true
    }

    func selectProfile(_ profile: CodexProfile) {
        guard selectedProfileID != profile.id else { return }
        selectedProfileID = profile.id
    }

    func restoreInitialSelectionIfNeeded(appViewModel: AppViewModel) -> Bool {
        guard didFinishInitialLoad, !hasRestoredInitialSelection else { return false }
        hasRestoredInitialSelection = true

        guard case .codexProfile(let id) = appViewModel.lastVisitedPage else { return false }
        guard profiles.contains(where: { $0.id == id }) else {
            appViewModel.persistLastVisitedPage(nil)
            return false
        }

        selectedProfileID = id
        return true
    }

    func clearSelection() {
        guard selectedProfileID != nil else { return }
        selectedProfileID = nil
    }

    func defaultSelectedProfileID() -> UUID? {
        profiles.first(where: \.isActive)?.id ?? profiles.first?.id
    }

    func updateSelected(name: String? = nil, configText: String? = nil, authText: String? = nil, zshrcText: String? = nil) {
        guard let index = selectedIndex else { return }
        var didChange = false

        if let name {
            let truncatedName = String(name.prefix(Self.profileNameMaxLength))
            if profiles[index].name != truncatedName {
                profiles[index].name = truncatedName
                didChange = true
            }
        }
        if let configText, profiles[index].configText != configText {
            profiles[index].configText = configText
            didChange = true
        }
        if let authText, profiles[index].authText != authText {
            profiles[index].authText = authText
            didChange = true
        }
        if let zshrcText, profiles[index].zshrcText != zshrcText {
            profiles[index].zshrcText = zshrcText
            didChange = true
        }

        guard didChange else { return }
        profiles[index].isDirty = isProfileDirty(profiles[index])
        schedulePersistProfiles()
    }

    func updateSelectedEditorHeight(
        configEditorHeight: Double? = nil,
        authEditorHeight: Double? = nil,
        zshrcEditorHeight: Double? = nil
    ) {
        guard let index = selectedIndex else { return }
        var didChange = false

        if let configEditorHeight {
            if profiles[index].configEditorHeight != configEditorHeight {
                profiles[index].configEditorHeight = configEditorHeight
                didChange = true
            }
        }
        if let authEditorHeight {
            if profiles[index].authEditorHeight != authEditorHeight {
                profiles[index].authEditorHeight = authEditorHeight
                didChange = true
            }
        }
        if let zshrcEditorHeight {
            if profiles[index].zshrcEditorHeight != zshrcEditorHeight {
                profiles[index].zshrcEditorHeight = zshrcEditorHeight
                didChange = true
            }
        }

        guard didChange else { return }
        schedulePersistProfiles()
    }

    func addProfile() {
        guard let source = selectedProfile ?? profiles.first else { return }
        let profile = CodexProfile(
            name: "新配置 \(profiles.count + 1)",
            configText: source.configText,
            authText: source.authText,
            zshrcText: source.zshrcText,
            isDirty: true
        )
        profiles.append(profile)
        selectedProfileID = profile.id
        Task { await persistProfiles() }
    }

    func deleteProfile(id: UUID) -> Bool {
        guard profiles.count > 1 else {
            lastErrorMessage = "至少需要保留一个 Codex Profile。"
            return false
        }
        guard let index = profiles.firstIndex(where: { $0.id == id }) else {
            lastErrorMessage = "未找到要删除的 Codex Profile。"
            return false
        }

        let deletedWasSelected = selectedProfileID == id
        profiles.remove(at: index)

        if deletedWasSelected {
            let nextIndex = min(index, profiles.count - 1)
            selectedProfileID = profiles.indices.contains(nextIndex) ? profiles[nextIndex].id : profiles.first?.id
        }

        lastErrorMessage = nil
        Task { await persistProfiles() }
        return true
    }

    func applySelected() async -> Bool {
        guard let selectedProfile, let selectedIndex else { return false }
        if let validationError = validate(profile: selectedProfile) {
            lastErrorMessage = validationError
            return false
        }

        do {
            try await service.apply(profile: selectedProfile)
            for index in profiles.indices {
                profiles[index].isActive = profiles[index].id == selectedProfile.id
            }
            profiles[selectedIndex].appliedConfigText = selectedProfile.configText
            profiles[selectedIndex].appliedAuthText = selectedProfile.authText
            profiles[selectedIndex].appliedZshrcText = selectedProfile.zshrcText
            profiles[selectedIndex].isDirty = false
            lastAppliedProfileName = profiles[selectedIndex].name
            lastErrorMessage = nil
            await persistProfiles()
            return true
        } catch {
            lastErrorMessage = error.localizedDescription
            return false
        }
    }

    func validateSelected() -> String? {
        guard let selectedProfile else { return "未选择 Profile" }
        return validate(profile: selectedProfile)
    }

    private var selectedIndex: Array<CodexProfile>.Index? {
        guard let selectedProfileID else { return nil }
        return profiles.firstIndex { $0.id == selectedProfileID }
    }

    private func isProfileDirty(_ profile: CodexProfile) -> Bool {
        normalizedProfileText(profile.configText) != normalizedProfileText(profile.appliedConfigText)
            || normalizedAuthJSON(profile.authText) != normalizedAuthJSON(profile.appliedAuthText)
            || normalizedProfileText(profile.zshrcText) != normalizedProfileText(profile.appliedZshrcText)
    }

    private func normalizedProfileText(_ text: String) -> String {
        text
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func normalizedAuthJSON(_ text: String) -> String {
        let trimmedText = normalizedProfileText(text)
        guard let data = trimmedText.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data),
              JSONSerialization.isValidJSONObject(object),
              let stableData = try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys]),
              let stableText = String(data: stableData, encoding: .utf8) else {
            return trimmedText
        }

        return stableText
    }

    private func validate(profile: CodexProfile) -> String? {
        if profile.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return "配置名称不能为空。"
        }
        if profile.configText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return "config.toml 不能为空。"
        }

        do {
            let data = Data(profile.authText.utf8)
            let object = try JSONSerialization.jsonObject(with: data)
            guard object is [String: Any] else {
                return "auth.json 必须是 JSON object。"
            }
        } catch {
            return "auth.json 不是合法 JSON：\(error.localizedDescription)"
        }

        return nil
    }

    func validateWithAPI(profile: CodexProfile) async -> APIValidationResult {
        let zshrcBaseURL = parseZshrcBaseURL(from: profile.zshrcText)
        let tomlBaseURL = parseTOMLBaseURL(from: profile.configText)
        let baseURL = zshrcBaseURL ?? tomlBaseURL

        print("[验证] Zshrc base_url: \(zshrcBaseURL ?? "未解析")")
        print("[验证] TOML base_url: \(tomlBaseURL ?? "未解析")")
        print("[验证] 实际使用 base_url: \(baseURL ?? "无")")

        guard let baseURL else {
            print("[验证] 错误: 无法解析 base_url")
            return APIValidationResult(isValid: false,
                message: "无法解析 base_url（请检查 config.toml 或 zshrc）",
                statusCode: nil, baseURL: "")
        }

        let apiKey = parseAPIKey(from: profile.authText)
        print("[验证] API Key: \(apiKey != nil ? "已解析 (\(apiKey!.prefix(10))...)" : "未解析")")

        guard let apiKey else {
            print("[验证] 错误: 无法解析 API 密钥")
            return APIValidationResult(isValid: false,
                message: "无法解析 API 密钥",
                statusCode: nil, baseURL: baseURL)
        }

        let fullURL = "\(baseURL)/models"
        print("[验证] 请求 URL: \(fullURL)")

        guard let url = URL(string: fullURL) else {
            print("[验证] 错误: URL 格式无效 - \(fullURL)")
            return APIValidationResult(isValid: false,
                message: "URL 格式无效: \(fullURL)",
                statusCode: nil, baseURL: baseURL)
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.timeoutInterval = 10

        do {
            print("[验证] 发送请求...")
            let (data, response) = try await URLSession.shared.data(for: request)
            let httpResponse = response as? HTTPURLResponse
            let statusCode = httpResponse?.statusCode ?? 0

            print("[验证] 响应状态码: \(statusCode)")
            if let responseString = String(data: data, encoding: .utf8) {
                print("[验证] 响应内容: \(responseString)")
            }

            if statusCode == 200 {
                print("[验证] 结果: 成功")
                return APIValidationResult(isValid: true,
                    message: "验证成功",
                    statusCode: statusCode,
                    baseURL: baseURL)
            } else {
                let errorMessage = String(data: data, encoding: .utf8) ?? "未知错误"
                print("[验证] 结果: 失败 - \(errorMessage)")
                return APIValidationResult(isValid: false,
                    message: "验证失败: \(errorMessage)",
                    statusCode: statusCode,
                    baseURL: baseURL)
            }
        } catch {
            print("[验证] 连接错误: \(error.localizedDescription)")
            return APIValidationResult(isValid: false,
                message: "连接失败: \(error.localizedDescription)",
                statusCode: nil,
                baseURL: baseURL)
        }
    }

    private func parseZshrcBaseURL(from zshrc: String) -> String? {
        let pattern = #"export\s+OPENAI_BASE_URL="([^"]+)""#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: zshrc, range: NSRange(zshrc.startIndex..., in: zshrc)),
              let range = Range(match.range(at: 1), in: zshrc) else {
            return nil
        }
        return String(zshrc[range])
    }

    private func parseTOMLBaseURL(from toml: String) -> String? {
        let pattern = #"base_url\s*=\s*"([^"]+)""#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: toml, range: NSRange(toml.startIndex..., in: toml)),
              let range = Range(match.range(at: 1), in: toml) else {
            return nil
        }
        return String(toml[range])
    }

    private func parseAPIKey(from json: String) -> String? {
        guard let data = json.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let apiKey = object["OPENAI_API_KEY"] as? String else {
            return nil
        }
        return apiKey
    }

    private func persistProfiles() async {
        do {
            try await service.saveProfiles(profiles)
        } catch {
            lastErrorMessage = error.localizedDescription
        }
    }

    private func schedulePersistProfiles() {
        persistTask?.cancel()
        persistTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 350_000_000)
            guard !Task.isCancelled else { return }
            await self?.persistProfiles()
        }
    }

}
