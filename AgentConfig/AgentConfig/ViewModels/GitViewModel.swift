//
//  GitViewModel.swift
//  AgentConfig
//
//  Created by cxy on 2026/5/11.
//

import Foundation
import Combine

// MARK: - GitViewModel

/// Git 版本历史 ViewModel，负责加载提交历史、查看 diff 和恢复文件内容
///
/// - 注入 `GitServiceProtocol` 依赖
/// - 通过 `@Published` 属性驱动 SwiftUI 视图更新
/// - 通过 `onRestore` 回调将恢复的内容传递给 `EditorViewModel`
@MainActor
final class GitViewModel: ObservableObject {

    // MARK: - Published Properties

    /// 当前文件的提交历史列表（按时间倒序）
    @Published var commits: [GitCommit] = []

    /// 当前选中的提交
    @Published var selectedCommit: GitCommit?

    /// 当前选中提交的 diff 结果
    @Published var diffResult: DiffResult?

    /// 当前文件所在目录是否是 Git 仓库
    @Published var isGitRepo: Bool = false

    /// 是否正在执行异步操作
    @Published var isLoading: Bool = false

    /// 最近一次操作的错误（若有）
    @Published var lastError: AppError?

    // MARK: - Callbacks

    /// 恢复文件内容后的回调，参数为恢复的文件内容字符串
    ///
    /// 由外部（通常是 `EditorViewModel`）设置，用于将恢复的内容写入编辑器并标记为未保存。
    var onRestore: ((String) -> Void)?

    // MARK: - Private State

    /// 当前正在查看历史的文件
    private var currentFile: ConfigFile?

    // MARK: - Dependencies

    private let gitService: GitServiceProtocol

    // MARK: - Init

    /// 初始化 GitViewModel
    /// - Parameter gitService: Git 操作服务，默认使用 `GitService()`
    init(gitService: GitServiceProtocol? = nil) {
        self.gitService = gitService ?? GitService()
    }

    // MARK: - Public Methods

    /// 加载指定文件的 Git 提交历史
    ///
    /// 先检查文件所在目录是否是 Git 仓库，若是则加载提交历史；
    /// 若不是 Git 仓库，则清空提交列表并将 `isGitRepo` 设为 `false`。
    /// - Parameter file: 要查看历史的配置文件
    func loadHistory(for file: ConfigFile) async {
        currentFile = file
        isLoading = true
        lastError = nil
        defer { isLoading = false }

        let directory = file.url.deletingLastPathComponent()
        let isRepo = await gitService.isGitRepo(at: directory)
        isGitRepo = isRepo

        guard isRepo else {
            commits = []
            selectedCommit = nil
            diffResult = nil
            return
        }

        do {
            commits = try await gitService.log(for: file.url)
            // 重置选中状态
            selectedCommit = nil
            diffResult = nil
        } catch let error as AppError {
            lastError = error
            commits = []
        } catch {
            lastError = .gitCommandFailed(command: "git log", stderr: error.localizedDescription)
            commits = []
        }
    }

    /// 选中一个提交并加载该提交的 diff
    ///
    /// 加载当前文件在该提交中相对于其父提交的差异。
    /// - Parameter commit: 要查看的提交
    func selectCommit(_ commit: GitCommit) async {
        selectedCommit = commit
        diffResult = nil
        lastError = nil

        guard let file = currentFile else { return }

        isLoading = true
        defer { isLoading = false }

        do {
            diffResult = try await gitService.diff(file: file.url, commitHash: commit.fullHash)
        } catch let error as AppError {
            lastError = error
            diffResult = nil
        } catch {
            lastError = .gitCommandFailed(command: "git diff", stderr: error.localizedDescription)
            diffResult = nil
        }
    }

    /// 将文件内容恢复到指定提交时的状态
    ///
    /// 调用 `GitService.show(file:at:)` 获取该提交时的文件内容，
    /// 然后通过 `onRestore` 回调通知 `EditorViewModel` 更新内容并标记为未保存。
    /// - Parameter commit: 要恢复到的目标提交
    /// - Throws: `AppError.gitNotInstalled` 或 `AppError.gitCommandFailed`
    func restore(to commit: GitCommit) async throws {
        guard let file = currentFile else { return }

        isLoading = true
        lastError = nil
        defer { isLoading = false }

        do {
            let restoredContent = try await gitService.show(file: file.url, at: commit.fullHash)
            // 通过回调将恢复的内容传递给 EditorViewModel，并标记为未保存
            onRestore?(restoredContent)
        } catch let error as AppError {
            lastError = error
            throw error
        } catch {
            let appError = AppError.gitCommandFailed(
                command: "git show",
                stderr: error.localizedDescription
            )
            lastError = appError
            throw appError
        }
    }

    /// 在指定文件所在目录初始化 Git 仓库
    ///
    /// 初始化成功后自动重新加载该文件的提交历史。
    /// - Parameter file: 要初始化 Git 仓库的配置文件（使用其所在目录）
    /// - Throws: `AppError.gitNotInstalled` 或 `AppError.gitCommandFailed`
    func initRepo(for file: ConfigFile) async throws {
        isLoading = true
        lastError = nil
        defer { isLoading = false }

        let directory = file.url.deletingLastPathComponent()

        do {
            try await gitService.initRepo(at: directory)
            // 初始化成功后重新加载历史（此时仓库为空，commits 将为空列表）
            await loadHistory(for: file)
        } catch let error as AppError {
            lastError = error
            throw error
        } catch {
            let appError = AppError.gitCommandFailed(
                command: "git init",
                stderr: error.localizedDescription
            )
            lastError = appError
            throw appError
        }
    }
}
