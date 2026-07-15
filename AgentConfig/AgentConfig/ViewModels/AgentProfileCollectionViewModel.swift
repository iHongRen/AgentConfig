//
//  AgentProfileCollectionViewModel.swift
//  AgentConfig
//

import Combine
import Foundation

/// 从磁盘读取到的 profile 目标文件当前内容（已按写入时方式规范化/提取）。
struct ProfileDiskContents {
    let configText: String?
    let authText: String?
    let zshrcText: String?
}

protocol AgentProfileRecord: Identifiable, Equatable where ID == UUID {
    var name: String { get set }
    var isActive: Bool { get set }
    var isDirty: Bool { get set }
}

struct AgentProfileCollectionConfiguration<Profile: AgentProfileRecord> {
    let profileNameMaxLength: Int
    let loadProfiles: () async throws -> [Profile]
    let saveProfiles: ([Profile]) async throws -> Void
    let applyProfile: (Profile) async throws -> Void
    let fallbackProfiles: (Error) -> [Profile]
    let isProfileDirty: (Profile) -> Bool
    let markProfileApplied: (inout Profile, Profile) -> Void
    let makeNewProfile: (Profile, Int) -> Profile
    let duplicateProfile: (Profile) -> Profile
    let lastVisitedProfileID: (LastVisitedPage) -> UUID?
    let minimumProfileCountMessage: String
    let profileNotFoundMessage: String
    let persistDebounceNanoseconds: UInt64
    /// 读取当前磁盘上 profile 目标文件的内容，用于探测外部改动
    let readDiskContents: () async throws -> ProfileDiskContents
    /// 判定给定 profile（基于其 applied 快照）是否与磁盘内容失同步（外部改动）
    let isProfileOutOfSync: (Profile, ProfileDiskContents) -> Bool
    /// 需要监听外部改动的磁盘文件 URL
    let watchedFileURLs: () -> [URL]

    init(
        profileNameMaxLength: Int,
        loadProfiles: @escaping () async throws -> [Profile],
        saveProfiles: @escaping ([Profile]) async throws -> Void,
        applyProfile: @escaping (Profile) async throws -> Void,
        fallbackProfiles: @escaping (Error) -> [Profile],
        isProfileDirty: @escaping (Profile) -> Bool,
        markProfileApplied: @escaping (inout Profile, Profile) -> Void,
        makeNewProfile: @escaping (Profile, Int) -> Profile,
        duplicateProfile: @escaping (Profile) -> Profile,
        lastVisitedProfileID: @escaping (LastVisitedPage) -> UUID?,
        minimumProfileCountMessage: String,
        profileNotFoundMessage: String,
        persistDebounceNanoseconds: UInt64 = 350_000_000,
        readDiskContents: @escaping () async throws -> ProfileDiskContents,
        isProfileOutOfSync: @escaping (Profile, ProfileDiskContents) -> Bool,
        watchedFileURLs: @escaping () -> [URL]
    ) {
        self.profileNameMaxLength = profileNameMaxLength
        self.loadProfiles = loadProfiles
        self.saveProfiles = saveProfiles
        self.applyProfile = applyProfile
        self.fallbackProfiles = fallbackProfiles
        self.isProfileDirty = isProfileDirty
        self.markProfileApplied = markProfileApplied
        self.makeNewProfile = makeNewProfile
        self.duplicateProfile = duplicateProfile
        self.lastVisitedProfileID = lastVisitedProfileID
        self.minimumProfileCountMessage = minimumProfileCountMessage
        self.profileNotFoundMessage = profileNotFoundMessage
        self.persistDebounceNanoseconds = persistDebounceNanoseconds
        self.readDiskContents = readDiskContents
        self.isProfileOutOfSync = isProfileOutOfSync
        self.watchedFileURLs = watchedFileURLs
    }
}

class AgentProfileCollectionViewModel<Profile: AgentProfileRecord>: ObservableObject {

    @Published var profiles: [Profile] = []
    @Published var selectedProfileID: UUID?
    @Published var lastErrorMessage: String?
    @Published var lastAppliedProfileName: String?
    @Published private(set) var didFinishInitialLoad: Bool = false
    /// 当前生效（active）的 profile 是否与磁盘实际内容失同步（被外部改动）
    @Published var isDiskOutOfSync: Bool = false

    private let configuration: AgentProfileCollectionConfiguration<Profile>
    private let fileWatcher: FileWatcherProtocol
    private var persistTask: Task<Void, Never>?
    private var hasRestoredInitialSelection = false

    init(
        configuration: AgentProfileCollectionConfiguration<Profile>,
        fileWatcher: FileWatcherProtocol = FileWatcher()
    ) {
        self.configuration = configuration
        self.fileWatcher = fileWatcher
        Task { await loadProfiles() }
    }

    deinit {
        persistTask?.cancel()
        fileWatcher.stopWatching()
    }

    var selectedProfile: Profile? {
        guard let selectedProfileID else { return nil }
        return profiles.first { $0.id == selectedProfileID }
    }

    func loadProfiles() async {
        defer { didFinishInitialLoad = true }

        do {
            let loadedProfiles = try await configuration.loadProfiles()
            profiles = loadedProfiles.map { refreshedDirtyState(for: $0) }
            selectedProfileID = selectedProfileID ?? loadedProfiles.first(where: \.isActive)?.id ?? loadedProfiles.first?.id
        } catch {
            let fallbackProfiles = configuration.fallbackProfiles(error)
            profiles = fallbackProfiles.map { refreshedDirtyState(for: $0) }
            selectedProfileID = fallbackProfiles.first?.id
            lastErrorMessage = error.localizedDescription
        }

        startWatchingAndRefresh()
    }

    /// 开始监听 profile 目标文件的外部改动，并立即比对一次磁盘状态
    private func startWatchingAndRefresh() {
        let urls = configuration.watchedFileURLs()
        fileWatcher.watch(urls: urls) { [weak self] _ in
            Task { @MainActor in await self?.refreshDiskSyncState() }
        }
        Task { @MainActor in await self.refreshDiskSyncState() }
    }

    /// 读取磁盘内容并与 active profile 的 applied 快照比对，更新 `isDiskOutOfSync`
    func refreshDiskSyncState() async {
        guard let activeProfile = profiles.first(where: { $0.isActive }) else {
            isDiskOutOfSync = false
            return
        }

        do {
            let disk = try await configuration.readDiskContents()
            isDiskOutOfSync = configuration.isProfileOutOfSync(activeProfile, disk)
        } catch {
            isDiskOutOfSync = false
        }
    }

    func selectProfile(_ profile: Profile) {
        guard selectedProfileID != profile.id else { return }
        selectedProfileID = profile.id
    }

    func restoreInitialSelectionIfNeeded(appViewModel: AppViewModel) -> Bool {
        guard didFinishInitialLoad, !hasRestoredInitialSelection else { return false }
        hasRestoredInitialSelection = true

        guard let lastVisitedPage = appViewModel.lastVisitedPage,
              let profileID = configuration.lastVisitedProfileID(lastVisitedPage) else {
            return false
        }

        guard profiles.contains(where: { $0.id == profileID }) else {
            appViewModel.persistLastVisitedPage(nil)
            return false
        }

        selectedProfileID = profileID
        return true
    }

    func clearSelection() {
        guard selectedProfileID != nil else { return }
        selectedProfileID = nil
    }

    func defaultSelectedProfileID() -> UUID? {
        profiles.first(where: \.isActive)?.id ?? profiles.first?.id
    }

    func addProfile() {
        guard let source = selectedProfile ?? profiles.first else { return }
        let profile = configuration.makeNewProfile(source, profiles.count)
        profiles.append(profile)
        selectedProfileID = profile.id
        Task { await persistProfiles() }
    }

    func duplicateProfile(id: UUID) {
        guard let source = profiles.first(where: { $0.id == id }) else { return }
        let copy = configuration.duplicateProfile(source)
        profiles.append(copy)
        selectedProfileID = copy.id
        Task { await persistProfiles() }
    }

    func moveProfile(from sourceID: UUID, to destinationID: UUID?) {
        guard let sourceIndex = profiles.firstIndex(where: { $0.id == sourceID }) else { return }

        var reorderedProfiles = profiles
        let movedProfile = reorderedProfiles.remove(at: sourceIndex)

        if let destinationID, let destinationIndex = reorderedProfiles.firstIndex(where: { $0.id == destinationID }) {
            reorderedProfiles.insert(movedProfile, at: destinationIndex)
        } else {
            reorderedProfiles.append(movedProfile)
        }

        guard reorderedProfiles != profiles else { return }
        profiles = reorderedProfiles
        schedulePersistProfiles()
    }

    func deleteProfile(id: UUID) -> Bool {
        guard profiles.count > 1 else {
            lastErrorMessage = configuration.minimumProfileCountMessage
            return false
        }
        guard let index = profiles.firstIndex(where: { $0.id == id }) else {
            lastErrorMessage = configuration.profileNotFoundMessage
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

        do {
            try await configuration.applyProfile(selectedProfile)
            for index in profiles.indices {
                profiles[index].isActive = profiles[index].id == selectedProfile.id
            }
            configuration.markProfileApplied(&profiles[selectedIndex], selectedProfile)
            profiles[selectedIndex].isDirty = false
            lastAppliedProfileName = profiles[selectedIndex].name
            lastErrorMessage = nil
            await persistProfiles()
            await refreshDiskSyncState()
            return true
        } catch {
            lastErrorMessage = error.localizedDescription
            return false
        }
    }

    func updateSelectedProfile(
        recomputeDirtyState: Bool = true,
        _ mutate: (inout Profile) -> Bool
    ) {
        guard let index = selectedIndex else { return }

        var updatedProfile = profiles[index]
        guard mutate(&updatedProfile) else { return }

        if recomputeDirtyState {
            updatedProfile.isDirty = configuration.isProfileDirty(updatedProfile)
        }

        profiles[index] = updatedProfile
        schedulePersistProfiles()
    }

    func truncatedProfileName(_ name: String) -> String {
        String(name.prefix(configuration.profileNameMaxLength))
    }

    private var selectedIndex: Array<Profile>.Index? {
        guard let selectedProfileID else { return nil }
        return profiles.firstIndex { $0.id == selectedProfileID }
    }

    private func refreshedDirtyState(for profile: Profile) -> Profile {
        var updatedProfile = profile
        updatedProfile.isDirty = configuration.isProfileDirty(updatedProfile)
        return updatedProfile
    }

    private func persistProfiles() async {
        do {
            try await configuration.saveProfiles(profiles)
        } catch {
            lastErrorMessage = error.localizedDescription
        }
    }

    private func schedulePersistProfiles() {
        persistTask?.cancel()
        persistTask = Task { [weak self] in
            guard let self else { return }
            try? await Task.sleep(nanoseconds: configuration.persistDebounceNanoseconds)
            guard !Task.isCancelled else { return }
            await self.persistProfiles()
        }
    }
}
