//
//  SidebarView.swift
//  AgentConfig
//
//  Created by cxy on 2026/5/11.
//

import SwiftUI
import AppKit

// MARK: - SidebarView

/// 截图式左侧栏：分类、文件树和自定义路径入口集中在同一列。
struct SidebarView: View {

    @EnvironmentObject var appViewModel: AppViewModel

    @State private var isEnvExpanded = true
    @State private var expandedAgentIDs: Set<String> = []
    @State private var expandedCustomPathIDs: Set<String> = []

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 6) {
                    sidebarHeader

                    if let envCategory = appViewModel.envCategory {
                        envSection(envCategory)
                    }

                    agentSections
                    customPathSections
                    addCustomPathButton
                }
                .padding(.horizontal, 10)
                .padding(.top, 18)
                .padding(.bottom, 16)
            }

            selectionFooter
        }
        .frame(minWidth: 260, idealWidth: 292, maxWidth: 360)
        .background(Color.agentSidebarBackground)
        .toolbar {
            ToolbarItemGroup {
                Button {
                    Task { await appViewModel.refresh() }
                } label: {
                    if appViewModel.isScanning {
                        ProgressView()
                            .controlSize(.small)
                            .scaleEffect(0.72)
                            .frame(width: 16, height: 16)
                    } else {
                        Image(systemName: "arrow.clockwise")
                    }
                }
                .disabled(appViewModel.isScanning)
                .help("刷新")

                Button {
                    openFilePicker()
                } label: {
                    Image(systemName: "plus")
                }
                .help("添加自定义路径")
            }
        }
        .navigationSplitViewColumnWidth(min: 260, ideal: 292, max: 360)
        .onAppear {
            expandedAgentIDs.formUnion(appViewModel.agentCategories.map(\.id))
            expandedCustomPathIDs.formUnion(appViewModel.customPathGroups.map(\.id))
        }
        .onChange(of: appViewModel.agentCategories) { _, categories in
            expandedAgentIDs.formUnion(categories.map(\.id))
        }
        .onChange(of: appViewModel.customPathGroups) { _, groups in
            expandedCustomPathIDs.formUnion(groups.map(\.id))
        }
    }

    private var sidebarHeader: some View {
        Text("分类")
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 10)
            .padding(.bottom, 10)
    }

    private func envSection(_ category: EnvCategory) -> some View {
        SidebarDisclosureSection(
            title: "环境变量",
            count: category.files.count,
            icon: "terminal.fill",
            iconColor: Color(red: 0.22, green: 0.78, blue: 0.20),
            isExpanded: $isEnvExpanded
        ) {
            ForEach(category.files) { file in
                fileRow(file)
            }

            ForEach(category.missingPaths, id: \.absoluteString) { missingURL in
                missingFileRow(missingURL)
            }
        }
    }

    private var agentSections: some View {
        ForEach(appViewModel.agentCategories) { category in
            SidebarDisclosureSection(
                title: category.displayName,
                count: category.files.count,
                icon: agentIcon(for: category.id),
                iconColor: agentColor(for: category.id),
                isExpanded: bindingForAgent(category.id)
            ) {
                ForEach(category.files) { file in
                    fileRow(file)
                }
            }
        }
    }

    private var customPathSections: some View {
        Group {
            if !appViewModel.customPathGroups.isEmpty {
                ForEach(appViewModel.customPathGroups) { group in
                    SidebarDisclosureSection(
                        title: customPathTitle(for: group.url),
                        count: group.files.count,
                        icon: "folder.fill",
                        iconColor: Color(nsColor: .tertiaryLabelColor),
                        isExpanded: bindingForCustomPath(group.id)
                    ) {
                        ForEach(group.files) { file in
                            fileRow(file, showsPathHint: group.files.count <= 4)
                        }
                    }
                }
            }
        }
    }

    private var addCustomPathButton: some View {
        Button {
            openFilePicker()
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "plus")
                    .font(.system(size: 14, weight: .medium))
                    .frame(width: 18)

                Text("添加自定义路径")
                    .font(.system(size: 14, weight: .medium))

                Spacer()
            }
            .foregroundStyle(.secondary)
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.top, 6)
    }

    private var selectionFooter: some View {
        HStack(spacing: 8) {
            Text(appViewModel.selectedFile == nil ? "未选择文件" : "已选择 1 个文件")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)

            Spacer()
        }
        .padding(.horizontal, 20)
        .frame(height: 32)
        .background(Color.agentSidebarBackground)
        .overlay(Divider(), alignment: .top)
    }

    private func fileRow(_ file: ConfigFile, showsPathHint: Bool = false) -> some View {
        Button {
            appViewModel.selectedFile = file
        } label: {
            HStack(spacing: 10) {
                Image(systemName: fileTypeIcon(for: file.fileType))
                    .font(.system(size: 14))
                    .foregroundStyle(Color(nsColor: .secondaryLabelColor))
                    .frame(width: 18)

                VStack(alignment: .leading, spacing: 1) {
                    Text(file.url.lastPathComponent)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                        .truncationMode(.middle)

                    if showsPathHint {
                        Text(pathHint(for: file.url))
                            .font(.system(size: 11))
                            .foregroundStyle(.tertiary)
                            .lineLimit(1)
                            .truncationMode(.head)
                    }
                }

                Spacer(minLength: 4)

                if file.isModified {
                    Circle()
                        .fill(Color.orange)
                        .frame(width: 7, height: 7)
                }
            }
            .padding(.leading, 34)
            .padding(.trailing, 10)
            .padding(.vertical, showsPathHint ? 6 : 7)
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
    }

    private func bindingForAgent(_ id: String) -> Binding<Bool> {
        Binding(
            get: { expandedAgentIDs.contains(id) },
            set: { isExpanded in
                if isExpanded {
                    expandedAgentIDs.insert(id)
                } else {
                    expandedAgentIDs.remove(id)
                }
            }
        )
    }

    private func bindingForCustomPath(_ id: String) -> Binding<Bool> {
        Binding(
            get: { expandedCustomPathIDs.contains(id) },
            set: { isExpanded in
                if isExpanded {
                    expandedCustomPathIDs.insert(id)
                } else {
                    expandedCustomPathIDs.remove(id)
                }
            }
        )
    }

    private func customPathTitle(for url: URL) -> String {
        let path = url.path
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        if path.hasPrefix(home) {
            return "~" + String(path.dropFirst(home.count))
        }
        return path
    }

    private func pathHint(for url: URL) -> String {
        let parentPath = url.deletingLastPathComponent().path
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        if parentPath.hasPrefix(home) {
            return "~" + String(parentPath.dropFirst(home.count))
        }
        return parentPath
    }

    private func fileTypeIcon(for fileType: FileType) -> String {
        switch fileType {
        case .json, .jsonc:
            return "curlybraces"
        case .yaml:
            return "list.bullet.indent"
        case .toml:
            return "gearshape"
        case .shell:
            return "doc.text"
        case .plainText:
            return "doc"
        }
    }

    private func agentIcon(for id: String) -> String {
        switch id {
        case "claude":
            return "sparkle"
        case "qwen":
            return "wand.and.stars"
        case "codex":
            return "circle.hexagongrid"
        case "cursor":
            return "cube.fill"
        case "continue":
            return "circle.dashed"
        case "aider":
            return "pencil.and.outline"
        case "gemini":
            return "circle.grid.cross"
        case "amazonq":
            return "shippingbox.fill"
        default:
            return "terminal"
        }
    }

    private func agentColor(for id: String) -> Color {
        switch id {
        case "claude":
            return Color(red: 0.95, green: 0.43, blue: 0.09)
        case "qwen":
            return Color(red: 0.50, green: 0.20, blue: 0.90)
        case "codex":
            return Color(nsColor: .labelColor)
        case "cursor":
            return Color(nsColor: .controlTextColor)
        case "continue":
            return Color(nsColor: .secondaryLabelColor)
        case "aider":
            return Color(red: 0.06, green: 0.74, blue: 0.58)
        case "gemini":
            return Color(red: 0.22, green: 0.40, blue: 0.92)
        case "amazonq":
            return Color(red: 0.96, green: 0.72, blue: 0.10)
        default:
            return Color.accentColor
        }
    }

    private func createFile(at url: URL) {
        Task {
            let fileService = FileService()
            do {
                try await fileService.create(at: url)
                await appViewModel.refresh()
            } catch {
                appViewModel.selectedFile = nil
            }
        }
    }

    private func openFilePicker() {
        let panel = NSOpenPanel()
        panel.title = "选择配置文件或目录"
        panel.message = "选择要添加的配置文件或目录"
        panel.canChooseFiles = true
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = false

        panel.begin { response in
            if response == .OK, let url = panel.url {
                appViewModel.addCustomPath(url)
            }
        }
    }
}

// MARK: - SidebarDisclosureSection

private struct SidebarDisclosureSection<Content: View>: View {

    let title: String
    let count: Int
    let icon: String
    let iconColor: Color
    @Binding var isExpanded: Bool
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Button {
                isExpanded.toggle()
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .rotationEffect(.degrees(isExpanded ? 90 : 0))
                        .frame(width: 14)

                    ZStack {
                        RoundedRectangle(cornerRadius: 4)
                            .fill(iconColor.opacity(0.16))
                        Image(systemName: icon)
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(iconColor)
                    }
                    .frame(width: 22, height: 22)

                    Text(title)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                        .truncationMode(.middle)

                    CountBadge(count: count)

                    Spacer(minLength: 4)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 7)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if isExpanded {
                VStack(alignment: .leading, spacing: 1) {
                    content()
                }
            }
        }
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

private extension Color {
    static var agentSidebarBackground: Color {
        Color(nsColor: .windowBackgroundColor)
    }
}

// MARK: - Preview

#Preview {
    let viewModel = AppViewModel()
    NavigationSplitView {
        SidebarView()
            .environmentObject(viewModel)
    } detail: {
        Text("编辑器")
    }
}
