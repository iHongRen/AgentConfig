//
//  GitHistoryView.swift
//  AgentConfig
//
//  Created by cxy on 2026/5/11.
//

import SwiftUI

// MARK: - GitHistoryView

/// Git 提交历史视图，以 Sheet 形式呈现
///
/// 左侧列表显示提交记录（短哈希、提交信息、作者、相对时间），
/// 右侧显示选中提交的 diff（`DiffView`）。
/// 绑定 `GitViewModel`，支持恢复到指定提交版本。
struct GitHistoryView: View {

    // MARK: - Environment

    @ObservedObject var gitViewModel: GitViewModel

    // MARK: - State

    /// 是否显示恢复确认对话框
    @State private var showRestoreConfirm: Bool = false

    /// 恢复操作的错误提示
    @State private var restoreError: String?

    /// 控制 Sheet 关闭
    @Environment(\.dismiss) private var dismiss

    // MARK: - Body

    var body: some View {
        NavigationSplitView {
            commitListSidebar
        } detail: {
            diffDetailView
        }
        .navigationTitle(NSLocalizedString("git.history.title", value: "提交历史", comment: "Git history view title"))
        .frame(minWidth: 800, minHeight: 500)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button(NSLocalizedString("git.history.close", value: "关闭", comment: "Close git history sheet")) {
                    dismiss()
                }
            }
        }
        .confirmationDialog(
            NSLocalizedString("git.restore.confirm.title", value: "确认恢复", comment: "Restore confirmation dialog title"),
            isPresented: $showRestoreConfirm,
            titleVisibility: .visible
        ) {
            Button(
                NSLocalizedString("git.restore.confirm.action", value: "恢复", comment: "Confirm restore action"),
                role: .destructive
            ) {
                performRestore()
            }
            Button(
                NSLocalizedString("git.restore.confirm.cancel", value: "取消", comment: "Cancel restore action"),
                role: .cancel
            ) {}
        } message: {
            if let commit = gitViewModel.selectedCommit {
                Text(String(
                    format: NSLocalizedString(
                        "git.restore.confirm.message",
                        value: "将文件内容恢复到提交 %@（%@）的版本？当前未保存的修改将被替换，恢复后文件将标记为未保存。",
                        comment: "Restore confirmation message with commit hash and message"
                    ),
                    commit.id,
                    commit.message
                ))
            }
        }
        .alert(
            NSLocalizedString("git.restore.error.title", value: "恢复失败", comment: "Restore error alert title"),
            isPresented: Binding(
                get: { restoreError != nil },
                set: { if !$0 { restoreError = nil } }
            )
        ) {
            Button(NSLocalizedString("git.restore.error.ok", value: "确定", comment: "Dismiss restore error")) {
                restoreError = nil
            }
        } message: {
            if let error = restoreError {
                Text(error)
            }
        }
    }

    // MARK: - Sidebar: Commit List

    private var commitListSidebar: some View {
        Group {
            if gitViewModel.isLoading && gitViewModel.commits.isEmpty {
                loadingView
            } else if gitViewModel.commits.isEmpty {
                emptyCommitsView
            } else {
                List(gitViewModel.commits, selection: Binding(
                    get: { gitViewModel.selectedCommit?.id },
                    set: { newID in
                        if let id = newID,
                           let commit = gitViewModel.commits.first(where: { $0.id == id }) {
                            Task { await gitViewModel.selectCommit(commit) }
                        }
                    }
                )) { commit in
                    CommitRowView(commit: commit)
                        .tag(commit.id)
                }
                .listStyle(.sidebar)
            }
        }
        .navigationSplitViewColumnWidth(min: 260, ideal: 300, max: 360)
        .navigationTitle(NSLocalizedString("git.history.commits", value: "提交记录", comment: "Commits list title"))
    }

    // MARK: - Detail: Diff View

    @ViewBuilder
    private var diffDetailView: some View {
        if gitViewModel.isLoading && gitViewModel.selectedCommit != nil {
            ProgressView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let commit = gitViewModel.selectedCommit {
            VStack(spacing: 0) {
                // 工具栏：提交信息 + 恢复按钮
                commitDetailHeader(commit: commit)

                Divider()

                // Diff 内容
                if let diffResult = gitViewModel.diffResult {
                    DiffView(diffResult: diffResult)
                } else if let error = gitViewModel.lastError {
                    errorView(message: error.localizedDescription)
                } else {
                    emptyDiffView
                }
            }
        } else {
            placeholderView
        }
    }

    /// 选中提交的详情头部（提交信息 + 恢复按钮）
    private func commitDetailHeader(commit: GitCommit) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(commit.message)
                    .font(.headline)
                    .lineLimit(2)

                HStack(spacing: 8) {
                    Label(commit.author, systemImage: "person.circle")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Text("·")
                        .foregroundStyle(.secondary)
                        .font(.caption)

                    Text(commit.id)
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)

                    Text("·")
                        .foregroundStyle(.secondary)
                        .font(.caption)

                    Text(commit.date.relativeFormatted)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            Button {
                showRestoreConfirm = true
            } label: {
                Label(
                    NSLocalizedString("git.restore.button", value: "恢复到此版本", comment: "Restore to this commit button"),
                    systemImage: "arrow.counterclockwise"
                )
            }
            .buttonStyle(.bordered)
            .disabled(gitViewModel.isLoading)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(.bar)
    }

    // MARK: - Empty / Loading States

    private var loadingView: some View {
        VStack(spacing: 12) {
            ProgressView()
            Text(NSLocalizedString("git.history.loading", value: "加载提交历史…", comment: "Loading commits"))
                .foregroundStyle(.secondary)
                .font(.callout)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var emptyCommitsView: some View {
        VStack(spacing: 12) {
            Image(systemName: "clock.arrow.circlepath")
                .font(.system(size: 36))
                .foregroundStyle(.secondary)
            Text(NSLocalizedString("git.history.empty", value: "暂无提交记录", comment: "No commits found"))
                .foregroundStyle(.secondary)
                .font(.callout)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var placeholderView: some View {
        VStack(spacing: 12) {
            Image(systemName: "arrow.left")
                .font(.system(size: 28))
                .foregroundStyle(.secondary)
            Text(NSLocalizedString("git.history.selectCommit", value: "选择左侧提交记录查看差异", comment: "Select a commit to view diff"))
                .foregroundStyle(.secondary)
                .font(.callout)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var emptyDiffView: some View {
        VStack(spacing: 12) {
            Image(systemName: "equal.circle")
                .font(.system(size: 36))
                .foregroundStyle(.secondary)
            Text(NSLocalizedString("git.diff.empty", value: "此提交无文件差异", comment: "No diff for this commit"))
                .foregroundStyle(.secondary)
                .font(.callout)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func errorView(message: String) -> some View {
        VStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 36))
                .foregroundStyle(.orange)
            Text(message)
                .foregroundStyle(.secondary)
                .font(.callout)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Actions

    private func performRestore() {
        guard let commit = gitViewModel.selectedCommit else { return }
        Task {
            do {
                try await gitViewModel.restore(to: commit)
                dismiss()
            } catch {
                restoreError = error.localizedDescription
            }
        }
    }
}

// MARK: - CommitRowView

/// 提交记录列表行视图
///
/// 显示：短哈希（monospace）、提交信息、作者、相对时间
private struct CommitRowView: View {

    let commit: GitCommit

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            // 提交信息（主要内容）
            Text(commit.message)
                .font(.body)
                .lineLimit(2)
                .truncationMode(.tail)

            HStack(spacing: 6) {
                // 短哈希（monospace 字体）
                Text(commit.id)
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 4)
                    .padding(.vertical, 1)
                    .background(Color.secondary.opacity(0.12))
                    .clipShape(RoundedRectangle(cornerRadius: 3))

                Text("·")
                    .font(.caption)
                    .foregroundStyle(.tertiary)

                // 作者
                Text(commit.author)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)

                Spacer()

                // 相对时间
                Text(commit.date.relativeFormatted)
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.vertical, 4)
    }
}

// MARK: - DiffView

/// Diff 内联视图
///
/// 以内联方式显示 `DiffResult` 中的所有 hunk：
/// - 新增行（`.added`）：绿色背景，前缀 `+`
/// - 删除行（`.removed`）：红色背景，前缀 `-`
/// - 上下文行（`.context`）：默认背景，前缀空格
struct DiffView: View {

    let diffResult: DiffResult

    var body: some View {
        if diffResult.hunks.isEmpty {
            emptyView
        } else {
            ScrollView(.vertical) {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(diffResult.hunks.enumerated()), id: \.offset) { hunkIndex, hunk in
                        // Hunk 分隔线
                        if hunkIndex > 0 {
                            hunkSeparator
                        }

                        ForEach(Array(hunk.lines.enumerated()), id: \.offset) { _, line in
                            DiffLineView(line: line)
                        }
                    }
                }
                .padding(.vertical, 4)
            }
            .background(Color(nsColor: .textBackgroundColor))
        }
    }

    private var emptyView: some View {
        VStack(spacing: 12) {
            Image(systemName: "equal.circle")
                .font(.system(size: 36))
                .foregroundStyle(.secondary)
            Text(NSLocalizedString("git.diff.noChanges", value: "无变更", comment: "No changes in diff"))
                .foregroundStyle(.secondary)
                .font(.callout)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var hunkSeparator: some View {
        HStack {
            Rectangle()
                .fill(Color.secondary.opacity(0.2))
                .frame(height: 1)
        }
        .padding(.vertical, 4)
    }
}

// MARK: - DiffLineView

/// 单行 diff 视图
///
/// 根据行类型显示不同背景色和前缀符号：
/// - `.added`：绿色背景，`+` 前缀
/// - `.removed`：红色背景，`-` 前缀
/// - `.context`：默认背景，空格前缀
private struct DiffLineView: View {

    let line: DiffLine

    var body: some View {
        HStack(spacing: 0) {
            // 前缀符号列
            Text(linePrefix)
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(prefixColor)
                .frame(width: 20, alignment: .center)
                .padding(.vertical, 1)

            // 行内容
            Text(line.content)
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(contentColor)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.trailing, 8)
                .padding(.vertical, 1)
        }
        .background(backgroundColor)
    }

    // MARK: - Computed Properties

    private var linePrefix: String {
        switch line {
        case .added:   return "+"
        case .removed: return "-"
        case .context: return " "
        }
    }

    private var backgroundColor: Color {
        switch line {
        case .added:
            return Color.green.opacity(0.15)
        case .removed:
            return Color.red.opacity(0.15)
        case .context:
            return Color.clear
        }
    }

    private var prefixColor: Color {
        switch line {
        case .added:   return .green
        case .removed: return .red
        case .context: return .secondary
        }
    }

    private var contentColor: Color {
        switch line {
        case .added:   return Color(nsColor: .labelColor)
        case .removed: return Color(nsColor: .labelColor)
        case .context: return Color(nsColor: .secondaryLabelColor)
        }
    }
}

// MARK: - Date Extension: Relative Formatting

extension Date {
    /// 使用 `RelativeDateTimeFormatter` 格式化为相对时间字符串（如"2小时前"）
    var relativeFormatted: String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .full
        return formatter.localizedString(for: self, relativeTo: Date())
    }
}

// MARK: - Preview

#Preview("Git History View") {
    let viewModel = GitViewModel()

    // 注入模拟数据
    let now = Date()
    let commits: [GitCommit] = [
        GitCommit(
            id: "a1b2c3d",
            fullHash: "a1b2c3d4e5f6a1b2c3d4e5f6a1b2c3d4e5f6a1b2",
            message: "Auto-save: 2026-05-11T10:30:00Z",
            author: "cxy",
            date: now.addingTimeInterval(-7200)
        ),
        GitCommit(
            id: "e4f5a6b",
            fullHash: "e4f5a6b7c8d9e4f5a6b7c8d9e4f5a6b7c8d9e4f5",
            message: "Initial commit: add CLAUDE.md configuration",
            author: "cxy",
            date: now.addingTimeInterval(-86400)
        ),
        GitCommit(
            id: "c7d8e9f",
            fullHash: "c7d8e9f0a1b2c7d8e9f0a1b2c7d8e9f0a1b2c7d8",
            message: "Update API key settings and model configuration for production",
            author: "cxy",
            date: now.addingTimeInterval(-172800)
        )
    ]

    // 模拟 diff 数据
    let diffResult = DiffResult(hunks: [
        DiffHunk(lines: [
            .context("# Claude Configuration"),
            .context(""),
            .removed("model: claude-3-opus"),
            .added("model: claude-3-5-sonnet"),
            .context("temperature: 0.7"),
            .removed("max_tokens: 2048"),
            .added("max_tokens: 4096"),
            .context("")
        ]),
        DiffHunk(lines: [
            .context("[api]"),
            .removed("# key: sk-old-key"),
            .added("key: sk-new-key-placeholder"),
            .context("timeout: 30")
        ])
    ])

    return GitHistoryView(gitViewModel: viewModel)
        .onAppear {
            viewModel.commits = commits
            viewModel.selectedCommit = commits[0]
            viewModel.diffResult = diffResult
            viewModel.isGitRepo = true
        }
}

#Preview("DiffView") {
    let diffResult = DiffResult(hunks: [
        DiffHunk(lines: [
            .context("# Configuration"),
            .removed("old_value: foo"),
            .added("new_value: bar"),
            .context("unchanged: baz")
        ])
    ])
    return DiffView(diffResult: diffResult)
        .frame(width: 600, height: 300)
}
