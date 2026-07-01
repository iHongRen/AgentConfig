//
//  SidebarView.swift
//  AgentConfig
//
//  Created by cxy on 2026/5/11.
//

import SwiftUI
import AppKit
import UniformTypeIdentifiers

private let sidebarReorderAnimation = Animation.spring(response: 0.24, dampingFraction: 0.82, blendDuration: 0.12)
private let sidebarDragLiftAnimation = Animation.spring(response: 0.18, dampingFraction: 0.86, blendDuration: 0.08)

struct SidebarView: View {

    private enum CoordinateSpace {
        static let sidebar = "sidebar-content"
    }

    @EnvironmentObject var appViewModel: AppViewModel
    @ObservedObject var codexProfileViewModel: CodexProfileViewModel
    @ObservedObject var claudeProfileViewModel: ClaudeProfileViewModel

    @State private var isEnvExpanded = true
    @State private var expandedAgentIDs: Set<String> = []
    @State private var targetedDropCategoryKey: String?
    @State private var deleteTarget: DeleteTarget?
    @State private var itemFrames: [String: CGRect] = [:]
    @State private var activeAgentDragID: String?
    @State private var activeCodexProfileDragID: UUID?
    @State private var activeClaudeProfileDragID: UUID?

    enum DeleteTarget: Identifiable {
        case hideFile(URL)
        case deleteCodexProfile(CodexProfile)
        case deleteClaudeProfile(ClaudeProfile)

        var id: String {
            switch self {
            case .hideFile(let url): return "hide-\(url.absoluteString)"
            case .deleteCodexProfile(let profile): return "profile-\(profile.id.uuidString)"
            case .deleteClaudeProfile(let profile): return "claude-profile-\(profile.id.uuidString)"
            }
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 6) {
                    if let envCategory = appViewModel.envCategory {
                        envSection(envCategory)
                        Divider()
                            .padding(.horizontal, 10)
                            .padding(.vertical, 4)
                    }

                    agentSections
                }
                .padding(.horizontal, 10)
                .padding(.top, 18)
                .padding(.bottom, 16)
                .coordinateSpace(name: CoordinateSpace.sidebar)
            }
        }
        .background(Color.agentSidebarBackground)
        .navigationSplitViewColumnWidth(min: 280, ideal: 280, max: 320)
        .alert(item: $deleteTarget) { target in
            switch target {
            case .hideFile(let url):
                return Alert(
                    title: Text(L10n.tr("sidebar.removeFromListTitle", value: "Remove from list?")),
                    message: Text(L10n.format("sidebar.removeFromListMessage", value: "This removes the file from the sidebar but does not delete the file.\n%@", url.path)),
                    primaryButton: .default(Text(L10n.tr("sidebar.remove", value: "Remove"))) {
                        appViewModel.hideFile(url)
                    },
                    secondaryButton: .cancel(Text(L10n.tr("profile.cancel", value: "Cancel")))
                )
            case .deleteCodexProfile(let profile):
                return Alert(
                    title: Text(L10n.tr("sidebar.deleteCodexProfileTitle", value: "Delete Codex Profile?")),
                    message: Text(L10n.format("sidebar.deleteCodexProfileMessage", value: "“%@” will be deleted. This will not modify any Codex config files already written to disk.", profile.name.isEmpty ? L10n.tr("profile.defaultName", value: "Untitled Profile") : profile.name)),
                    primaryButton: .destructive(Text(L10n.tr("profile.delete", value: "Delete"))) {
                        _ = codexProfileViewModel.deleteProfile(id: profile.id)
                    },
                    secondaryButton: .cancel(Text(L10n.tr("profile.cancel", value: "Cancel")))
                )
            case .deleteClaudeProfile(let profile):
                return Alert(
                    title: Text(L10n.tr("sidebar.deleteClaudeProfileTitle", value: "Delete Claude Profile?")),
                    message: Text(L10n.format("sidebar.deleteClaudeProfileMessage", value: "“%@” will be deleted. This will not modify any Claude config files already written to disk.", profile.name.isEmpty ? L10n.tr("profile.defaultName", value: "Untitled Profile") : profile.name)),
                    primaryButton: .destructive(Text(L10n.tr("profile.delete", value: "Delete"))) {
                        _ = claudeProfileViewModel.deleteProfile(id: profile.id)
                    },
                    secondaryButton: .cancel(Text(L10n.tr("profile.cancel", value: "Cancel")))
                )
            }
        }
        .onAppear {
            syncExpandedSectionsWithSelection()
        }
        .onChange(of: appViewModel.selectedFile?.url.standardizedFileURL.path) { _, _ in
            syncExpandedSectionsWithSelection()
        }
        .onChange(of: codexProfileViewModel.selectedProfileID) { _, _ in
            syncExpandedSectionsWithSelection()
        }
        .onChange(of: claudeProfileViewModel.selectedProfileID) { _, _ in
            syncExpandedSectionsWithSelection()
        }
        .onChange(of: appViewModel.agentCategories) { _, _ in
            syncExpandedSectionsWithSelection()
        }
    }

    private func envSection(_ category: EnvCategory) -> some View {
        SidebarDisclosureSection(
            title: L10n.tr("sidebar.environment", value: "Environment"),
            icon: .systemName("terminal.fill"),
            iconColor: Color(red: 0.22, green: 0.78, blue: 0.20),
            isExpanded: $isEnvExpanded
        ) {
            ForEach(category.files) { file in
                fileRow(file)
            }
        } contextMenu: {
            Button(L10n.tr("sidebar.addFile", value: "Add File")) {
                openFilePicker(for: .env, directoryURL: preferredDirectory(for: category))
            }

            Divider()

            Button(L10n.tr("sidebar.openInFinder", value: "Open in Finder")) {
                let home = FileManager.default.homeDirectoryForCurrentUser
                NSWorkspace.shared.activateFileViewerSelecting([home])
            }
        }
        .dropTargetStyle(isTargeted: targetedDropCategoryKey == SidebarCategoryKey.env.storageKey)
        .onDrop(of: [UTType.fileURL.identifier], isTargeted: dropTargetBinding(for: .env)) { providers in
            addDroppedFiles(from: providers, to: .env)
        }
    }

    private var agentSections: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(appViewModel.agentCategories) { category in
                SidebarDisclosureSection(
                    title: category.displayName,
                    icon: .assetName(category.iconName),
                    iconColor: category.iconColor,
                    isExpanded: bindingForAgent(category.id),
                    isDragging: activeAgentDragID == category.id,
                    dragGestureBuilder: {
                        AnyView(
                            SidebarDisclosureSectionHeader(
                                title: category.displayName,
                                icon: .assetName(category.iconName),
                                iconColor: category.iconColor,
                                isExpanded: bindingForAgent(category.id),
                                contextMenu: {
                                    Button(L10n.tr("sidebar.addFile", value: "Add File")) {
                                        openFilePicker(for: .agent(id: category.id), directoryURL: preferredDirectory(for: category))
                                    }

                                    Divider()

                                    Button(L10n.tr("sidebar.openInFinder", value: "Open in Finder")) {
                                        let representativeURL = finderTargetURL(for: category)
                                        if let url = representativeURL {
                                            NSWorkspace.shared.activateFileViewerSelecting([url])
                                        }
                                    }
                                    .disabled(category.files.isEmpty && category.missingPaths.isEmpty)
                                }
                            )
                            .simultaneousGesture(dragGestureForAgent(category.id))
                        )
                    }
                ) {
                    if category.id == "claude" {
                        claudeProfileSection
                        sidebarSubheading(L10n.tr("sidebar.filesSection", value: "Files"))
                    }

                    if category.id == "codex" {
                        codexProfileSection
                        sidebarSubheading(L10n.tr("sidebar.filesSection", value: "Files"))
                    }

                    ForEach(category.files) { file in
                        fileRow(file)
                    }

                    ForEach(category.missingPaths, id: \.absoluteString) { missingURL in
                        missingFileRow(missingURL)
                    }
                } contextMenu: { EmptyView() }
                .trackFrame(id: frameKeyForAgent(category.id), in: CoordinateSpace.sidebar) { frame in
                    itemFrames[frameKeyForAgent(category.id)] = frame
                }
                .dropTargetStyle(isTargeted: targetedDropCategoryKey == SidebarCategoryKey.agent(id: category.id).storageKey)
                .onDrop(of: [UTType.fileURL.identifier], isTargeted: dropTargetBinding(for: .agent(id: category.id))) { providers in
                    addDroppedFiles(from: providers, to: .agent(id: category.id))
                }
            }
        }
        .animation(sidebarReorderAnimation, value: appViewModel.agentCategories.map(\.id))
    }

    private var codexProfileSection: some View {
        VStack(alignment: .leading, spacing: 1) {
            HStack(alignment: .center) {
                sidebarSubheading(L10n.tr("sidebar.profilesSection", value: "Profiles"))

                CountBadge(count: codexProfileViewModel.profiles.count)

                Spacer()

                Button {
                    codexProfileViewModel.addProfile()
                    if appViewModel.selectedFile != nil {
                        appViewModel.selectFile(nil)
                    }
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 11, weight: .bold))
                        .frame(width: 20, height: 20)
                }
                .buttonStyle(.plain)
                .help(L10n.tr("sidebar.newCodexProfile", value: "New Codex Profile"))
                .padding(.trailing, 4)

            }
            
            ForEach(codexProfileViewModel.profiles) { profile in
                codexProfileRow(profile)
                    .trackFrame(id: frameKeyForCodexProfile(profile.id), in: CoordinateSpace.sidebar) { frame in
                        itemFrames[frameKeyForCodexProfile(profile.id)] = frame
                    }
                    .simultaneousGesture(dragGestureForCodexProfile(profile.id))
            }
        }
    }

    private var claudeProfileSection: some View {
        VStack(alignment: .leading, spacing: 1) {
            HStack {
                sidebarSubheading(L10n.tr("sidebar.profilesSection", value: "Profiles"))
                CountBadge(count: claudeProfileViewModel.profiles.count)

                Spacer()

                Button {
                    claudeProfileViewModel.addProfile()
                    codexProfileViewModel.clearSelection()
                    if appViewModel.selectedFile != nil {
                        appViewModel.selectFile(nil)
                    }
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 11, weight: .bold))
                        .frame(width: 20, height: 20)
                }
                .buttonStyle(.plain)
                .help(L10n.tr("sidebar.newClaudeProfile", value: "New Claude Profile"))
                .padding(.trailing, 4)
            }

            ForEach(claudeProfileViewModel.profiles) { profile in
                claudeProfileRow(profile)
                    .trackFrame(id: frameKeyForClaudeProfile(profile.id), in: CoordinateSpace.sidebar) { frame in
                        itemFrames[frameKeyForClaudeProfile(profile.id)] = frame
                    }
                    .simultaneousGesture(dragGestureForClaudeProfile(profile.id))
            }
        }
    }

    private func sidebarSubheading(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 11, weight: .bold))
            .foregroundStyle(.secondary)
            .textCase(.uppercase)
            .padding(.leading, 34)
         
    }

    private func codexProfileRow(_ profile: CodexProfile) -> some View {
        let isDragging = activeCodexProfileDragID == profile.id

        return Button {
            guard codexProfileViewModel.selectedProfileID != profile.id
                    || appViewModel.selectedFile != nil
                    || claudeProfileViewModel.selectedProfileID != nil else { return }
            if appViewModel.selectedFile != nil {
                appViewModel.selectFile(nil)
            }
            claudeProfileViewModel.clearSelection()
            codexProfileViewModel.selectProfile(profile)
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "rectangle.stack")
                    .font(.system(size: 14))
                    .foregroundStyle(Color(nsColor: .secondaryLabelColor))
                    .frame(width: 18)

                VStack(alignment: .leading, spacing: 2) {
                    Text(profile.name.isEmpty ? L10n.tr("profile.defaultName", value: "Untitled Profile") : profile.name)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(.primary)
                        .lineLimit(1)

                    Text(profileStatusText(profile))
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Spacer(minLength: 4)

                Circle()
                    .fill(profileStateColor(profile))
                    .frame(width: 8, height: 8)
            }
            .padding(.leading, 34)
            .padding(.trailing, 10)
            .padding(.vertical, 7)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(RoundedRectangle(cornerRadius: 7))
            .background(
                RoundedRectangle(cornerRadius: 7)
                    .fill(codexProfileViewModel.selectedProfileID == profile.id ? Color.accentColor.opacity(0.16) : Color.clear)
            )
        }
        .scaleEffect(isDragging ? 1.015 : 1)
        .opacity(isDragging ? 0.74 : 1)
        .shadow(color: .black.opacity(isDragging ? 0.12 : 0), radius: isDragging ? 10 : 0, y: isDragging ? 5 : 0)
        .zIndex(isDragging ? 1 : 0)
        .animation(sidebarDragLiftAnimation, value: isDragging)
        .animation(sidebarReorderAnimation, value: codexProfileViewModel.profiles.map(\.id))
        .buttonStyle(.plain)
        .contextMenu {
            Button(L10n.tr("sidebar.deleteProfile", value: "Delete Profile")) {
                deleteTarget = .deleteCodexProfile(profile)
            }
            .disabled(codexProfileViewModel.profiles.count <= 1)
        }
    }

    private func claudeProfileRow(_ profile: ClaudeProfile) -> some View {
        let isDragging = activeClaudeProfileDragID == profile.id

        return Button {
            guard claudeProfileViewModel.selectedProfileID != profile.id
                    || appViewModel.selectedFile != nil
                    || codexProfileViewModel.selectedProfileID != nil else { return }
            if appViewModel.selectedFile != nil {
                appViewModel.selectFile(nil)
            }
            codexProfileViewModel.clearSelection()
            claudeProfileViewModel.selectProfile(profile)
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "rectangle.stack")
                    .font(.system(size: 14))
                    .foregroundStyle(Color(nsColor: .secondaryLabelColor))
                    .frame(width: 18)

                VStack(alignment: .leading, spacing: 2) {
                    Text(profile.name.isEmpty ? L10n.tr("profile.defaultName", value: "Untitled Profile") : profile.name)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(.primary)
                        .lineLimit(1)

                    Text(claudeProfileStatusText(profile))
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Spacer(minLength: 4)

                Circle()
                    .fill(claudeProfileStateColor(profile))
                    .frame(width: 8, height: 8)
            }
            .padding(.leading, 34)
            .padding(.trailing, 10)
            .padding(.vertical, 7)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(RoundedRectangle(cornerRadius: 7))
            .background(
                RoundedRectangle(cornerRadius: 7)
                    .fill(claudeProfileViewModel.selectedProfileID == profile.id ? Color.accentColor.opacity(0.16) : Color.clear)
            )
        }
        .scaleEffect(isDragging ? 1.015 : 1)
        .opacity(isDragging ? 0.74 : 1)
        .shadow(color: .black.opacity(isDragging ? 0.12 : 0), radius: isDragging ? 10 : 0, y: isDragging ? 5 : 0)
        .zIndex(isDragging ? 1 : 0)
        .animation(sidebarDragLiftAnimation, value: isDragging)
        .animation(sidebarReorderAnimation, value: claudeProfileViewModel.profiles.map(\.id))
        .buttonStyle(.plain)
        .contextMenu {
            Button(L10n.tr("sidebar.deleteProfile", value: "Delete Profile")) {
                deleteTarget = .deleteClaudeProfile(profile)
            }
            .disabled(claudeProfileViewModel.profiles.count <= 1)
        }
    }

    private func fileRow(_ file: ConfigFile) -> some View {
        Button {
            guard appViewModel.selectedFile?.url != file.url
                    || codexProfileViewModel.selectedProfileID != nil
                    || claudeProfileViewModel.selectedProfileID != nil else { return }
            codexProfileViewModel.clearSelection()
            claudeProfileViewModel.clearSelection()
            appViewModel.selectFile(file)
        } label: {
            HStack(spacing: 10) {
                Image(systemName: fileTypeIcon(for: file.fileType))
                    .font(.system(size: 14))
                    .foregroundStyle(Color(nsColor: .secondaryLabelColor))
                    .frame(width: 18)

                Text(file.url.lastPathComponent)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .truncationMode(.middle)

                Spacer(minLength: 4)

                if file.isModified {
                    Circle()
                        .fill(Color.orange)
                        .frame(width: 7, height: 7)
                }
            }
            .padding(.leading, 34)
            .padding(.trailing, 10)
            .padding(.vertical, 7)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(RoundedRectangle(cornerRadius: 7))
            .background(
                RoundedRectangle(cornerRadius: 7)
                    .fill(appViewModel.selectedFile?.url == file.url ? Color.accentColor.opacity(0.16) : Color.clear)
            )
            .overlay(alignment: .trailing) {
                if appViewModel.selectedFile?.url == file.url {
                    Circle()
                        .fill(Color.accentColor)
                        .frame(width: 8, height: 8)
                        .padding(.trailing, 9)
                }
            }
        }
        .buttonStyle(.plain)
        .contextMenu {
            fileContextMenu(for: file)
        }
    }

    @ViewBuilder
    private func fileContextMenu(for file: ConfigFile) -> some View {
        Button(L10n.tr("sidebar.openInFinder", value: "Open in Finder")) {
            NSWorkspace.shared.activateFileViewerSelecting([file.url])
        }

        Button(L10n.tr("sidebar.openInVSCode", value: "Open in VSCode")) {
            let task = Process()
            task.launchPath = "/usr/local/bin/code"
            task.arguments = [file.url.path]
            task.launch()
        }

        Divider()

        Button(L10n.tr("sidebar.copyPath", value: "Copy Path")) {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(file.url.path, forType: .string)
        }

        Divider()

        Button(L10n.tr("sidebar.remove", value: "Remove")) {
            deleteTarget = .hideFile(file.url)
        }
    }

    private func profileStatusText(_ profile: CodexProfile) -> String {
        if profile.isDirty { return L10n.tr("sidebar.unapplied", value: "Unapplied") }
        if profile.isActive { return L10n.tr("sidebar.applied", value: "Applied") }
        return L10n.tr("sidebar.draft", value: "Draft")
    }

    private func profileStateColor(_ profile: CodexProfile) -> Color {
        if profile.isDirty { return .orange }
        if profile.isActive { return .green }
        return Color(nsColor: .tertiaryLabelColor)
    }

    private func claudeProfileStatusText(_ profile: ClaudeProfile) -> String {
        if profile.isDirty { return L10n.tr("sidebar.unapplied", value: "Unapplied") }
        if profile.isActive { return L10n.tr("sidebar.applied", value: "Applied") }
        return L10n.tr("sidebar.draft", value: "Draft")
    }

    private func claudeProfileStateColor(_ profile: ClaudeProfile) -> Color {
        if profile.isDirty { return .orange }
        if profile.isActive { return .green }
        return Color(nsColor: .tertiaryLabelColor)
    }

    private func missingFileRow(_ url: URL) -> some View {
        HStack(spacing: 10) {
            Image(systemName: fileTypeIcon(for: FileType.detect(from: url)))
                .font(.system(size: 14))
                .foregroundStyle(.tertiary)
                .frame(width: 18)

            Text(url.lastPathComponent)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)

            Spacer(minLength: 4)

            Button(L10n.tr("sidebar.create", value: "Create")) {
                createFile(at: url)
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
        .padding(.leading, 34)
        .padding(.trailing, 8)
        .padding(.vertical, 5)
        .contextMenu {
            Button(L10n.tr("sidebar.copyPath", value: "Copy Path")) {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(url.path, forType: .string)
            }
        }
    }

    private func bindingForAgent(_ id: String) -> Binding<Bool> {
        Binding(
            get: { expandedAgentIDs.contains(id) },
            set: { isExpanded in
                var transaction = Transaction()
                transaction.disablesAnimations = true
                withTransaction(transaction) {
                    if isExpanded {
                        expandedAgentIDs.insert(id)
                    } else {
                        expandedAgentIDs.remove(id)
                    }
                }
            }
        )
    }

    private func dropTargetBinding(for categoryKey: SidebarCategoryKey) -> Binding<Bool> {
        Binding(
            get: { targetedDropCategoryKey == categoryKey.storageKey },
            set: { isTargeted in
                targetedDropCategoryKey = isTargeted ? categoryKey.storageKey : nil
            }
        )
    }

    private func preferredDirectory(for category: EnvCategory) -> URL {
        category.files.first?.url.deletingLastPathComponent()
            ?? category.missingPaths.first?.deletingLastPathComponent()
            ?? FileManager.default.homeDirectoryForCurrentUser
    }

    private func preferredDirectory(for category: AgentCategory) -> URL? {
        category.files.first?.url.deletingLastPathComponent()
            ?? category.missingPaths.first?.deletingLastPathComponent()
    }

    private func finderTargetURL(for category: AgentCategory) -> URL? {
        guard let definition = AgentDefinitions.definition(for: category.id) else {
            return category.files.first?.url ?? category.missingPaths.first
        }

        let configuredURLs = definition.configFiles.flatMap(\.resolvedURLs).map(\.standardizedFileURL)

        for configuredURL in configuredURLs {
            if let matchedFile = category.files.first(where: { $0.url.standardizedFileURL == configuredURL }) {
                return matchedFile.url
            }
        }

        for configuredURL in configuredURLs {
            if let matchedMissingURL = category.missingPaths.first(where: { $0.standardizedFileURL == configuredURL }) {
                return matchedMissingURL
            }
        }

        return category.files.first?.url ?? category.missingPaths.first
    }

    private func fileTypeIcon(for fileType: FileType) -> String {
        fileType.systemIconName
    }

    private func frameKeyForAgent(_ id: String) -> String {
        "agent:\(id)"
    }

    private func frameKeyForCodexProfile(_ id: UUID) -> String {
        "codex-profile:\(id.uuidString)"
    }

    private func frameKeyForClaudeProfile(_ id: UUID) -> String {
        "claude-profile:\(id.uuidString)"
    }

    private func dragGestureForAgent(_ id: String) -> some Gesture {
        DragGesture(minimumDistance: 3, coordinateSpace: .named(CoordinateSpace.sidebar))
            .onChanged { value in
                if activeAgentDragID != id {
                    withAnimation(sidebarDragLiftAnimation) {
                        activeAgentDragID = id
                    }
                }
                moveDraggedAgent(id, toY: value.location.y)
            }
            .onEnded { value in
                moveDraggedAgent(id, toY: value.location.y)
                withAnimation(sidebarDragLiftAnimation) {
                    activeAgentDragID = nil
                }
            }
    }

    private func dragGestureForCodexProfile(_ id: UUID) -> some Gesture {
        DragGesture(minimumDistance: 3, coordinateSpace: .named(CoordinateSpace.sidebar))
            .onChanged { value in
                if activeCodexProfileDragID != id {
                    withAnimation(sidebarDragLiftAnimation) {
                        activeCodexProfileDragID = id
                    }
                }
                moveDraggedCodexProfile(id, toY: value.location.y)
            }
            .onEnded { value in
                moveDraggedCodexProfile(id, toY: value.location.y)
                withAnimation(sidebarDragLiftAnimation) {
                    activeCodexProfileDragID = nil
                }
            }
    }

    private func dragGestureForClaudeProfile(_ id: UUID) -> some Gesture {
        DragGesture(minimumDistance: 3, coordinateSpace: .named(CoordinateSpace.sidebar))
            .onChanged { value in
                if activeClaudeProfileDragID != id {
                    withAnimation(sidebarDragLiftAnimation) {
                        activeClaudeProfileDragID = id
                    }
                }
                moveDraggedClaudeProfile(id, toY: value.location.y)
            }
            .onEnded { value in
                moveDraggedClaudeProfile(id, toY: value.location.y)
                withAnimation(sidebarDragLiftAnimation) {
                    activeClaudeProfileDragID = nil
                }
            }
    }

    private func moveDraggedAgent(_ sourceID: String, toY y: CGFloat) {
        let orderedIDs = appViewModel.agentCategories.map(\.id)
        let destinationID = destinationAgentID(forY: y, sourceID: sourceID, orderedIDs: orderedIDs)
        withAnimation(sidebarReorderAnimation) {
            appViewModel.moveAgentCategory(from: sourceID, to: destinationID)
        }
    }

    private func moveDraggedCodexProfile(_ sourceID: UUID, toY y: CGFloat) {
        let orderedIDs = codexProfileViewModel.profiles.map(\.id)
        let destinationID = destinationCodexProfileID(forY: y, sourceID: sourceID, orderedIDs: orderedIDs)
        withAnimation(sidebarReorderAnimation) {
            codexProfileViewModel.moveProfile(from: sourceID, to: destinationID)
        }
    }

    private func moveDraggedClaudeProfile(_ sourceID: UUID, toY y: CGFloat) {
        let orderedIDs = claudeProfileViewModel.profiles.map(\.id)
        let destinationID = destinationClaudeProfileID(forY: y, sourceID: sourceID, orderedIDs: orderedIDs)
        withAnimation(sidebarReorderAnimation) {
            claudeProfileViewModel.moveProfile(from: sourceID, to: destinationID)
        }
    }

    private func destinationAgentID(forY y: CGFloat, sourceID: String, orderedIDs: [String]) -> String? {
        destinationID(
            forY: y,
            sourceID: sourceID,
            orderedIDs: orderedIDs,
            frameKey: frameKeyForAgent
        )
    }

    private func destinationCodexProfileID(forY y: CGFloat, sourceID: UUID, orderedIDs: [UUID]) -> UUID? {
        destinationID(
            forY: y,
            sourceID: sourceID,
            orderedIDs: orderedIDs,
            frameKey: frameKeyForCodexProfile
        )
    }

    private func destinationClaudeProfileID(forY y: CGFloat, sourceID: UUID, orderedIDs: [UUID]) -> UUID? {
        destinationID(
            forY: y,
            sourceID: sourceID,
            orderedIDs: orderedIDs,
            frameKey: frameKeyForClaudeProfile
        )
    }

    private func destinationID<ID: Equatable>(
        forY y: CGFloat,
        sourceID: ID,
        orderedIDs: [ID],
        frameKey: (ID) -> String
    ) -> ID? {
        let otherIDs = orderedIDs.filter { $0 != sourceID }
        guard !otherIDs.isEmpty else { return nil }

        for id in otherIDs {
            guard let frame = itemFrames[frameKey(id)] else { continue }
            if y < frame.midY {
                return id
            }
        }

        return nil
    }

    private func createFile(at url: URL) {
        Task {
            let fileService = FileService()
            do {
                try await fileService.create(at: url)
                await appViewModel.refresh()
            } catch {
                appViewModel.selectFile(nil)
            }
        }
    }

    private func addDroppedFiles(from providers: [NSItemProvider], to categoryKey: SidebarCategoryKey) -> Bool {
        let fileURLProviders = providers.filter { $0.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) }
        guard !fileURLProviders.isEmpty else { return false }

        expandCategory(categoryKey)
        for provider in fileURLProviders {
            provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
                guard let url = fileURL(from: item) else { return }
                Task { @MainActor in
                    appViewModel.addFiles([url], to: categoryKey)
                }
            }
        }
        return true
    }

    private func fileURL(from item: NSSecureCoding?) -> URL? {
        if let url = item as? URL { return url }
        if let data = item as? Data { return URL(dataRepresentation: data, relativeTo: nil) }
        if let string = item as? String { return URL(string: string) }
        return nil
    }

    private func expandCategory(_ categoryKey: SidebarCategoryKey) {
        switch categoryKey {
        case .env:
            isEnvExpanded = true
        case .agent(let id):
            expandedAgentIDs.insert(id)
        case .customPath:
            break
        }
    }

    private func openFilePicker(for categoryKey: SidebarCategoryKey, directoryURL: URL?) {
        let panel = NSOpenPanel()
        panel.title = L10n.tr("sidebar.addFilePanel.title", value: "Add File")
        panel.message = L10n.tr("sidebar.addFilePanel.message", value: "Choose files to add to this category")
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = true
        panel.canCreateDirectories = false
        panel.directoryURL = directoryURL

        panel.begin { response in
            if response == .OK {
                expandCategory(categoryKey)
                appViewModel.addFiles(panel.urls, to: categoryKey)
            }
        }
    }

    private func syncExpandedSectionsWithSelection() {
        if codexProfileViewModel.selectedProfileID != nil {
            expandCategory(.agent(id: "codex"))
            return
        }

        if claudeProfileViewModel.selectedProfileID != nil {
            expandCategory(.agent(id: "claude"))
            return
        }

        guard let selectedFile = appViewModel.selectedFile else { return }
        let standardizedURL = selectedFile.url.standardizedFileURL

        if appViewModel.envCategory?.files.contains(where: { $0.url.standardizedFileURL == standardizedURL }) == true {
            expandCategory(.env)
            return
        }

        if let category = appViewModel.agentCategories.first(where: { category in
            category.files.contains { $0.url.standardizedFileURL == standardizedURL }
        }) {
            expandCategory(.agent(id: category.id))
            return
        }

        if let match = AgentDefinitions.match(for: standardizedURL) {
            expandCategory(.agent(id: match.definition.id))
        }
    }
}

private struct SidebarDisclosureSection<Content: View, Menu: View>: View {
    let title: String
    let icon: SidebarIcon
    let iconColor: Color
    @Binding var isExpanded: Bool
    let isDragging: Bool
    let dragGestureBuilder: (() -> AnyView)?
    @ViewBuilder let content: () -> Content
    @ViewBuilder let contextMenu: (() -> Menu)?

    init(
        title: String,
        icon: SidebarIcon,
        iconColor: Color,
        isExpanded: Binding<Bool>,
        isDragging: Bool = false,
        dragGestureBuilder: (() -> AnyView)? = nil,
        @ViewBuilder content: @escaping () -> Content,
        @ViewBuilder contextMenu: @escaping () -> Menu = { EmptyView() }
    ) {
        self.title = title
        self.icon = icon
        self.iconColor = iconColor
        self._isExpanded = isExpanded
        self.isDragging = isDragging
        self.dragGestureBuilder = dragGestureBuilder
        self.content = content
        self.contextMenu = contextMenu
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            if let dragGestureBuilder {
                dragGestureBuilder()
                    .scaleEffect(isDragging ? 1.012 : 1)
                    .opacity(isDragging ? 0.78 : 1)
                    .shadow(color: .black.opacity(isDragging ? 0.10 : 0), radius: isDragging ? 9 : 0, y: isDragging ? 4 : 0)
                    .zIndex(isDragging ? 1 : 0)
                    .animation(sidebarDragLiftAnimation, value: isDragging)
            } else {
                SidebarDisclosureSectionHeader(
                    title: title,
                    icon: icon,
                    iconColor: iconColor,
                    isExpanded: $isExpanded,
                    contextMenu: {
                        contextMenu?()
                    }
                )
                    .scaleEffect(isDragging ? 1.012 : 1)
                    .opacity(isDragging ? 0.78 : 1)
                    .shadow(color: .black.opacity(isDragging ? 0.10 : 0), radius: isDragging ? 9 : 0, y: isDragging ? 4 : 0)
                    .zIndex(isDragging ? 1 : 0)
                    .animation(sidebarDragLiftAnimation, value: isDragging)
            }

            if isExpanded {
                VStack(alignment: .leading, spacing: 1) {
                    content()
                }
            }
        }
        .animation(sidebarReorderAnimation, value: isExpanded)
    }
}

private struct SidebarDisclosureSectionHeader<Menu: View>: View {
    let title: String
    let icon: SidebarIcon
    let iconColor: Color
    @Binding var isExpanded: Bool
    @ViewBuilder let contextMenu: () -> Menu

    var body: some View {
        Button {
            var transaction = Transaction()
            transaction.disablesAnimations = true
            withTransaction(transaction) {
                isExpanded.toggle()
            }
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .rotationEffect(.degrees(isExpanded ? 90 : 0))
                    .animation(nil, value: isExpanded)
                    .frame(width: 14)

                ZStack {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(iconColor.opacity(0.16))
                    icon.view
                }
                .frame(width: 22, height: 22)

                Text(title)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .truncationMode(.middle)

                Spacer(minLength: 4)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 7)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .contextMenu {
            contextMenu()
        }
    }
}

private struct DropTargetStyle: ViewModifier {
    let isTargeted: Bool

    func body(content: Content) -> some View {
        content
            .padding(3)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(isTargeted ? Color.accentColor.opacity(0.10) : Color.clear)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .strokeBorder(isTargeted ? Color.accentColor.opacity(0.65) : Color.clear, style: StrokeStyle(lineWidth: 1.5, dash: [5, 3]))
            )
            .animation(.easeInOut(duration: 0.12), value: isTargeted)
    }
}

private struct FramePreferenceKey: PreferenceKey {
    static var defaultValue: [String: CGRect] = [:]

    static func reduce(value: inout [String: CGRect], nextValue: () -> [String: CGRect]) {
        value.merge(nextValue(), uniquingKeysWith: { _, new in new })
    }
}

private struct CountBadge: View {
    let count: Int

    var body: some View {
        Text("\(count)")
            .font(.system(size: 9, weight: .semibold))
            .foregroundStyle(.secondary)
            .monospacedDigit()
            .padding(.horizontal, 4)
            .padding(.vertical, 1)
            .background(
                Capsule()
                    .fill(Color(nsColor: .quaternaryLabelColor))
            )
    }
}

private enum SidebarIcon {
    case systemName(String)
    case assetName(String)

    @ViewBuilder
    var view: some View {
        switch self {
        case .systemName(let name):
            Image(systemName: name)
                .font(.system(size: 14, weight: .semibold))
        case .assetName(let name):
            Image(name)
                .renderingMode(.original)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 16, height: 16)
        }
    }
}

private extension View {
    func dropTargetStyle(isTargeted: Bool) -> some View {
        modifier(DropTargetStyle(isTargeted: isTargeted))
    }

    func trackFrame(id: String, in coordinateSpace: String, onChange: @escaping (CGRect) -> Void) -> some View {
        background(
            GeometryReader { proxy in
                Color.clear
                    .preference(key: FramePreferenceKey.self, value: [id: proxy.frame(in: .named(coordinateSpace))])
            }
        )
        .onPreferenceChange(FramePreferenceKey.self) { values in
            if let frame = values[id] {
                onChange(frame)
            }
        }
    }
}

private extension Color {
    static var agentSidebarBackground: Color {
        Color(nsColor: .windowBackgroundColor)
    }
}
