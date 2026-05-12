//
//  FileListView.swift
//  AgentConfig
//
//  Created by cxy on 2026/5/11.
//

import SwiftUI

// MARK: - FileListView

/// 三栏布局的中间栏，显示选中分类下的文件列表
///
/// - 列出选中分类下的所有已存在文件
/// - 对环境变量分类中不存在的文件（`EnvCategory.missingPaths`）显示"创建"按钮
/// - 若文件有未保存修改（`isModified`），显示"●"标记
/// - 点击文件时更新 `AppViewModel.selectedFile`
struct FileListView: View {

    // MARK: - Selection

    /// 当前选中的分类，可以是 AgentCategory 或 EnvCategory
    enum CategorySelection: Equatable {
        case agent(AgentCategory)
        case env(EnvCategory)
    }

    // MARK: - Properties

    @EnvironmentObject var appViewModel: AppViewModel

    let selection: CategorySelection

    // MARK: - Body

    var body: some View {
        List {
            switch selection {
            case .agent(let category):
                agentFileRows(for: category)

            case .env(let category):
                envFileRows(for: category)
            }
        }
        .listStyle(.sidebar)
        .navigationTitle(navigationTitle)
    }

    // MARK: - Private Views

    @ViewBuilder
    private func agentFileRows(for category: AgentCategory) -> some View {
        if category.files.isEmpty {
            emptyStateView
        } else {
            ForEach(category.files) { file in
                fileRow(for: file)
            }
        }
    }

    @ViewBuilder
    private func envFileRows(for category: EnvCategory) -> some View {
        // 已存在的文件
        ForEach(category.files) { file in
            fileRow(for: file)
        }

        // 不存在但可创建的文件
        ForEach(category.missingPaths, id: \.absoluteString) { missingURL in
            missingFileRow(for: missingURL)
        }

        if category.files.isEmpty && category.missingPaths.isEmpty {
            emptyStateView
        }
    }

    /// 已存在文件的行视图
    private func fileRow(for file: ConfigFile) -> some View {
        Button {
            appViewModel.selectedFile = file
        } label: {
            HStack(spacing: 8) {
                // 文件类型图标
                Image(systemName: fileTypeIcon(for: file.fileType))
                    .foregroundStyle(.secondary)
                    .frame(width: 16)

                // 文件名
                Text(file.url.lastPathComponent)
                    .lineLimit(1)
                    .truncationMode(.middle)

                Spacer()

                // 未保存修改标记
                if file.isModified {
                    Text("●")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .listRowBackground(
            appViewModel.selectedFile?.id == file.id
                ? Color.accentColor.opacity(0.15)
                : Color.clear
        )
    }

    /// 不存在文件的行视图（显示"创建"按钮）
    private func missingFileRow(for url: URL) -> some View {
        HStack(spacing: 8) {
            // 文件类型图标（灰色表示不存在）
            Image(systemName: fileTypeIcon(for: FileType.detect(from: url)))
                .foregroundStyle(.tertiary)
                .frame(width: 16)

            // 文件名（灰色表示不存在）
            Text(url.lastPathComponent)
                .lineLimit(1)
                .truncationMode(.middle)
                .foregroundStyle(.secondary)

            Spacer()

            // 创建按钮
            Button(NSLocalizedString("创建", comment: "Create missing env file")) {
                createFile(at: url)
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
    }

    /// 空状态视图
    private var emptyStateView: some View {
        HStack {
            Spacer()
            Text(NSLocalizedString("暂无文件", comment: "No files in category"))
                .foregroundStyle(.secondary)
                .font(.callout)
            Spacer()
        }
        .listRowBackground(Color.clear)
    }

    // MARK: - Private Helpers

    /// 根据分类获取导航标题
    private var navigationTitle: String {
        switch selection {
        case .agent(let category):
            return category.displayName
        case .env:
            return NSLocalizedString("环境变量", comment: "Environment variables category title")
        }
    }

    /// 根据文件类型返回对应的 SF Symbol 图标名称
    private func fileTypeIcon(for fileType: FileType) -> String {
        switch fileType {
        case .json, .jsonc, .json5, .jsonl:
            return "curlybraces"
        case .yaml:
            return "list.bullet.indent"
        case .toml:
            return "gearshape"
        case .shell:
            return "terminal"
        case .plainText:
            return "doc.text"
        }
    }

    /// 创建缺失的环境变量文件
    private func createFile(at url: URL) {
        Task {
            // 通过 AppViewModel 的 fileService 创建文件，然后刷新
            // 由于 fileService 是 private(set)，通过 addCustomPath 触发刷新
            // 这里直接使用 FileService 创建文件后刷新
            let fileService = FileService()
            do {
                try await fileService.create(at: url)
                await appViewModel.refresh()
            } catch {
                // 创建失败时静默处理（后续可扩展为错误提示）
            }
        }
    }
}

// MARK: - Preview

#Preview("Agent Category") {
    let appViewModel = AppViewModel()
    let category = AgentCategory(
        id: "claude",
        displayName: "Claude Code",
        files: [
            ConfigFile(url: URL(fileURLWithPath: "/Users/test/.claude/settings.json")),
            ConfigFile(url: URL(fileURLWithPath: "/Users/test/.claude/CLAUDE.md"), isModified: true)
        ],
        missingPaths: [
            URL(fileURLWithPath: "/Users/test/.claude.json")
        ]
    )
    return FileListView(selection: .agent(category))
        .environmentObject(appViewModel)
        .frame(width: 220, height: 400)
}

#Preview("Env Category") {
    let appViewModel = AppViewModel()
    let category = EnvCategory(
        files: [
            ConfigFile(url: URL(fileURLWithPath: "/Users/test/.zshrc"))
        ],
        missingPaths: [
            URL(fileURLWithPath: "/Users/test/.bashrc"),
            URL(fileURLWithPath: "/Users/test/.bash_profile")
        ]
    )
    return FileListView(selection: .env(category))
        .environmentObject(appViewModel)
        .frame(width: 220, height: 400)
}
