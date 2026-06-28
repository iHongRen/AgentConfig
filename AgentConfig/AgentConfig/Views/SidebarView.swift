//
//  SidebarView.swift
//  AgentConfig
//
//  Created by cxy on 2026/5/11.
//

import SwiftUI
import AppKit
import UniformTypeIdentifiers

struct SidebarView: View {

    @EnvironmentObject var appViewModel: AppViewModel
    @ObservedObject var codexProfileViewModel: CodexProfileViewModel
    @ObservedObject var claudeProfileViewModel: ClaudeProfileViewModel

    @State private var isEnvExpanded = true
    @State private var expandedAgentIDs: Set<String> = []
    @State private var targetedDropCategoryKey: String?
    @State private var deleteTarget: DeleteTarget?

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
            }
        }
        .background(Color.agentSidebarBackground)
        .navigationSplitViewColumnWidth(min: 280, ideal: 280, max: 320)
        .alert(item: $deleteTarget) { target in
            switch target {
            case .hideFile(let url):
                return Alert(
                    title: Text("从列表移除？"),
                    message: Text("将从侧边栏移除此文件，但不会删除实际文件。\n\(url.path)"),
                    primaryButton: .default(Text("移除")) {
                        appViewModel.hideFile(url)
                    },
                    secondaryButton: .cancel(Text("取消"))
                )
            case .deleteCodexProfile(let profile):
                return Alert(
                    title: Text("删除 Codex Profile？"),
                    message: Text("将删除“\(profile.name.isEmpty ? "未命名配置" : profile.name)”。此操作不会修改已经写入磁盘的 Codex 配置文件。"),
                    primaryButton: .destructive(Text("删除")) {
                        _ = codexProfileViewModel.deleteProfile(id: profile.id)
                    },
                    secondaryButton: .cancel(Text("取消"))
                )
            case .deleteClaudeProfile(let profile):
                return Alert(
                    title: Text("删除 Claude Profile？"),
                    message: Text("将删除“\(profile.name.isEmpty ? "未命名配置" : profile.name)”。此操作不会修改已经写入磁盘的 Claude 配置文件。"),
                    primaryButton: .destructive(Text("删除")) {
                        _ = claudeProfileViewModel.deleteProfile(id: profile.id)
                    },
                    secondaryButton: .cancel(Text("取消"))
                )
            }
        }
    }

    private func envSection(_ category: EnvCategory) -> some View {
        SidebarDisclosureSection(
            title: "环境变量",
            icon: .systemName("terminal.fill"),
            iconColor: Color(red: 0.22, green: 0.78, blue: 0.20),
            isExpanded: $isEnvExpanded
        ) {
            ForEach(category.files) { file in
                fileRow(file)
            }
        } contextMenu: {
            Button("添加文件") {
                openFilePicker(for: .env, directoryURL: preferredDirectory(for: category))
            }

            Divider()

            Button("在 Finder 中打开") {
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
        ForEach(appViewModel.agentCategories) { category in
            SidebarDisclosureSection(
                title: category.displayName,
                icon: .assetName(category.iconName),
                iconColor: category.iconColor,
                isExpanded: bindingForAgent(category.id)
            ) {
                if category.id == "claude" {
                    claudeProfileSection
                    sidebarSubheading("Files")
                }

                if category.id == "codex" {
                    codexProfileSection
                    sidebarSubheading("Files")
                }

                ForEach(category.files) { file in
                    fileRow(file)
                }

                ForEach(category.missingPaths, id: \.absoluteString) { missingURL in
                    missingFileRow(missingURL)
                }
            } contextMenu: {
                Button("添加文件") {
                    openFilePicker(for: .agent(id: category.id), directoryURL: preferredDirectory(for: category))
                }

                Divider()

                Button("在 Finder 中打开") {
                    let representativeURL = category.files.first?.url ?? category.missingPaths.first
                    if let url = representativeURL {
                        NSWorkspace.shared.activateFileViewerSelecting([url])
                    }
                }
                .disabled(category.files.isEmpty && category.missingPaths.isEmpty)
            }
            .dropTargetStyle(isTargeted: targetedDropCategoryKey == SidebarCategoryKey.agent(id: category.id).storageKey)
            .onDrop(of: [UTType.fileURL.identifier], isTargeted: dropTargetBinding(for: .agent(id: category.id))) { providers in
                addDroppedFiles(from: providers, to: .agent(id: category.id))
            }
        }
    }

    private var codexProfileSection: some View {
        VStack(alignment: .leading, spacing: 1) {
            HStack {
                sidebarSubheading("Profiles")

                Spacer()

                CountBadge(count: codexProfileViewModel.profiles.count)
                
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
                .help("新增 Codex Profile")
                .padding(.trailing, 4)

            }

            ForEach(codexProfileViewModel.profiles) { profile in
                codexProfileRow(profile)
            }
        }
    }

    private var claudeProfileSection: some View {
        VStack(alignment: .leading, spacing: 1) {
            HStack {
                sidebarSubheading("Profiles")

                Spacer()

                CountBadge(count: claudeProfileViewModel.profiles.count)

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
                .help("新增 Claude Profile")
                .padding(.trailing, 4)
            }

            ForEach(claudeProfileViewModel.profiles) { profile in
                claudeProfileRow(profile)
            }
        }
    }

    private func sidebarSubheading(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 10, weight: .bold))
            .foregroundStyle(.secondary)
            .textCase(.uppercase)
            .padding(.leading, 34)
            .padding(.top, 8)
            .padding(.bottom, 3)
    }

    private func codexProfileRow(_ profile: CodexProfile) -> some View {
        Button {
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
                    Text(profile.name.isEmpty ? "未命名配置" : profile.name)
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
        .buttonStyle(.plain)
        .contextMenu {
            Button("删除 Profile") {
                deleteTarget = .deleteCodexProfile(profile)
            }
            .disabled(codexProfileViewModel.profiles.count <= 1)
        }
    }

    private func claudeProfileRow(_ profile: ClaudeProfile) -> some View {
        Button {
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
                    Text(profile.name.isEmpty ? "未命名配置" : profile.name)
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
        .buttonStyle(.plain)
        .contextMenu {
            Button("删除 Profile") {
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
        Button("在 Finder 中打开") {
            NSWorkspace.shared.activateFileViewerSelecting([file.url])
        }

        Button("在 VSCode 中打开") {
            let task = Process()
            task.launchPath = "/usr/local/bin/code"
            task.arguments = [file.url.path]
            task.launch()
        }

        Divider()

        Button("复制路径") {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(file.url.path, forType: .string)
        }

        Divider()

        Button("从列表移除") {
            deleteTarget = .hideFile(file.url)
        }
    }

    private func profileStatusText(_ profile: CodexProfile) -> String {
        if profile.isDirty { return "未应用" }
        if profile.isActive { return "已应用" }
        return "草稿"
    }

    private func profileStateColor(_ profile: CodexProfile) -> Color {
        if profile.isDirty { return .orange }
        if profile.isActive { return .green }
        return Color(nsColor: .tertiaryLabelColor)
    }

    private func claudeProfileStatusText(_ profile: ClaudeProfile) -> String {
        if profile.isDirty { return "未应用" }
        if profile.isActive { return "已应用" }
        return "草稿"
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

            Button("创建") {
                createFile(at: url)
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
        .padding(.leading, 34)
        .padding(.trailing, 8)
        .padding(.vertical, 5)
        .contextMenu {
            Button("复制路径") {
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

    private func fileTypeIcon(for fileType: FileType) -> String {
        fileType.systemIconName
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
        panel.title = "添加文件"
        panel.message = "选择要添加到此分类的文件"
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
}

private struct SidebarDisclosureSection<Content: View, Menu: View>: View {
    let title: String
    let icon: SidebarIcon
    let iconColor: Color
    @Binding var isExpanded: Bool
    @ViewBuilder let content: () -> Content
    @ViewBuilder let contextMenu: (() -> Menu)?

    init(
        title: String,
        icon: SidebarIcon,
        iconColor: Color,
        isExpanded: Binding<Bool>,
        @ViewBuilder content: @escaping () -> Content,
        @ViewBuilder contextMenu: @escaping () -> Menu = { EmptyView() }
    ) {
        self.title = title
        self.icon = icon
        self.iconColor = iconColor
        self._isExpanded = isExpanded
        self.content = content
        self.contextMenu = contextMenu
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
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
                contextMenu?()
            }

            if isExpanded {
                VStack(alignment: .leading, spacing: 1) {
                    content()
                }
            }
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

private struct CountBadge: View {
    let count: Int

    var body: some View {
        Text("\(count)")
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(.secondary)
            .monospacedDigit()
            .padding(.horizontal, 8)
            .padding(.vertical, 2)
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
}

private extension Color {
    static var agentSidebarBackground: Color {
        Color(nsColor: .windowBackgroundColor)
    }
}
