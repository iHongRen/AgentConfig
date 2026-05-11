//
//  GitService.swift
//  AgentConfig
//
//  Created by cxy on 2026/5/11.
//

import Foundation

// MARK: - GitServiceProtocol

/// Git 操作服务协议，封装对系统 git 命令的调用
protocol GitServiceProtocol {
    /// 检查指定目录是否是 Git 仓库
    /// - Parameter url: 目录路径
    /// - Returns: 是 Git 仓库返回 true，否则返回 false
    func isGitRepo(at url: URL) async -> Bool

    /// 在指定目录初始化 Git 仓库
    /// - Parameter url: 目录路径
    /// - Throws: `AppError.gitNotInstalled` 或 `AppError.gitCommandFailed`
    func initRepo(at url: URL) async throws

    /// 获取指定文件的 Git 提交历史
    /// - Parameter file: 文件路径
    /// - Returns: 提交记录数组，按时间倒序排列
    /// - Throws: `AppError.gitNotInstalled` 或 `AppError.gitCommandFailed`
    func log(for file: URL) async throws -> [GitCommit]

    /// 获取指定文件在某次提交中的差异
    /// - Parameters:
    ///   - file: 文件路径
    ///   - commitHash: 提交哈希（短或完整）
    /// - Returns: 差异结果，包含所有变更块
    /// - Throws: `AppError.gitNotInstalled` 或 `AppError.gitCommandFailed`
    func diff(file: URL, commitHash: String) async throws -> DiffResult

    /// 获取文件在指定提交时的内容
    /// - Parameters:
    ///   - file: 文件路径
    ///   - commitHash: 提交哈希（短或完整）
    /// - Returns: 文件内容字符串
    /// - Throws: `AppError.gitNotInstalled` 或 `AppError.gitCommandFailed`
    func show(file: URL, at commitHash: String) async throws -> String

    /// 暂存并提交指定文件
    /// - Parameters:
    ///   - file: 文件路径
    ///   - message: 提交信息
    /// - Throws: `AppError.gitNotInstalled` 或 `AppError.gitCommandFailed`
    func stageAndCommit(file: URL, message: String) async throws
}

// MARK: - GitService

/// `GitServiceProtocol` 的默认实现，通过 `Process` 调用系统 git 命令
final class GitService: GitServiceProtocol {

    // MARK: - Private Helpers

    /// 查找系统 git 可执行文件路径
    private func gitExecutablePath() throws -> String {
        // 常见 git 安装路径
        let candidates = [
            "/usr/bin/git",
            "/usr/local/bin/git",
            "/opt/homebrew/bin/git"
        ]
        for path in candidates {
            if FileManager.default.isExecutableFile(atPath: path) {
                return path
            }
        }
        throw AppError.gitNotInstalled
    }

    /// 执行 git 命令并返回标准输出
    /// - Parameters:
    ///   - args: git 命令参数（不含 "git" 本身）
    ///   - workingDirectory: 工作目录
    /// - Returns: 标准输出字符串（已去除末尾换行）
    /// - Throws: `AppError.gitNotInstalled` 或 `AppError.gitCommandFailed`
    func runGitCommand(args: [String], workingDirectory: URL) throws -> String {
        let gitPath = try gitExecutablePath()

        let process = Process()
        process.executableURL = URL(fileURLWithPath: gitPath)
        process.arguments = args
        process.currentDirectoryURL = workingDirectory

        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        do {
            try process.run()
        } catch {
            throw AppError.gitCommandFailed(
                command: "git \(args.joined(separator: " "))",
                stderr: error.localizedDescription
            )
        }

        process.waitUntilExit()

        let stdoutData = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
        let stderrData = stderrPipe.fileHandleForReading.readDataToEndOfFile()
        let stdout = String(data: stdoutData, encoding: .utf8) ?? ""
        let stderr = String(data: stderrData, encoding: .utf8) ?? ""

        guard process.terminationStatus == 0 else {
            throw AppError.gitCommandFailed(
                command: "git \(args.joined(separator: " "))",
                stderr: stderr.trimmingCharacters(in: .whitespacesAndNewlines)
            )
        }

        return stdout.trimmingCharacters(in: .newlines)
    }

    // MARK: - GitServiceProtocol

    func isGitRepo(at url: URL) async -> Bool {
        guard let gitPath = try? gitExecutablePath() else { return false }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: gitPath)
        process.arguments = ["rev-parse", "--is-inside-work-tree"]
        process.currentDirectoryURL = url
        process.standardOutput = Pipe()
        process.standardError = Pipe()

        do {
            try process.run()
        } catch {
            return false
        }

        process.waitUntilExit()
        return process.terminationStatus == 0
    }

    func initRepo(at url: URL) async throws {
        _ = try runGitCommand(args: ["init"], workingDirectory: url)
    }

    func log(for file: URL) async throws -> [GitCommit] {
        let workingDirectory = file.deletingLastPathComponent()
        let filePath = file.path

        // 格式：短哈希|完整哈希|提交信息|作者|ISO8601时间
        let format = "%h|%H|%s|%an|%ai"
        let output = try runGitCommand(
            args: ["log", "--pretty=format:\(format)", "--", filePath],
            workingDirectory: workingDirectory
        )

        guard !output.isEmpty else { return [] }

        let isoFormatter = ISO8601DateFormatter()
        isoFormatter.formatOptions = [.withInternetDateTime, .withColonSeparatorInTimeZone]

        var commits: [GitCommit] = []
        for line in output.components(separatedBy: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }

            let parts = trimmed.components(separatedBy: "|")
            // 期望至少 5 个字段：短哈希|完整哈希|提交信息|作者|时间
            guard parts.count >= 5 else { continue }

            let shortHash = parts[0]
            let fullHash = parts[1]
            // 提交信息可能包含 "|"，取第3个字段到倒数第3个字段之间的内容
            let author = parts[parts.count - 2]
            let dateString = parts[parts.count - 1]
            let message = parts[2..<(parts.count - 2)].joined(separator: "|")

            guard let date = isoFormatter.date(from: dateString) else { continue }

            let commit = GitCommit(
                id: shortHash,
                fullHash: fullHash,
                message: message,
                author: author,
                date: date
            )
            commits.append(commit)
        }

        return commits
    }

    func diff(file: URL, commitHash: String) async throws -> DiffResult {
        let workingDirectory = file.deletingLastPathComponent()
        let filePath = file.path

        // 对比该提交的父提交与该提交之间的差异
        let output = try runGitCommand(
            args: ["diff", "\(commitHash)^", commitHash, "--", filePath],
            workingDirectory: workingDirectory
        )

        return parseDiff(output: output)
    }

    func show(file: URL, at commitHash: String) async throws -> String {
        // 需要计算文件相对于 git 仓库根目录的路径
        let workingDirectory = file.deletingLastPathComponent()

        // 获取 git 仓库根目录
        let repoRoot = try runGitCommand(
            args: ["rev-parse", "--show-toplevel"],
            workingDirectory: workingDirectory
        )

        let repoRootURL = URL(fileURLWithPath: repoRoot)
        // 计算文件相对于仓库根目录的路径
        let relativePath: String
        if file.path.hasPrefix(repoRoot + "/") {
            relativePath = String(file.path.dropFirst(repoRoot.count + 1))
        } else {
            relativePath = file.path
        }

        let output = try runGitCommand(
            args: ["show", "\(commitHash):\(relativePath)"],
            workingDirectory: repoRootURL
        )

        return output
    }

    func stageAndCommit(file: URL, message: String) async throws {
        let workingDirectory = file.deletingLastPathComponent()
        let filePath = file.path

        // git add <file>
        _ = try runGitCommand(
            args: ["add", filePath],
            workingDirectory: workingDirectory
        )

        // git commit -m "<message>"
        _ = try runGitCommand(
            args: ["commit", "-m", message],
            workingDirectory: workingDirectory
        )
    }

    // MARK: - Diff Parsing

    /// 解析 git diff 输出为 DiffResult
    private func parseDiff(output: String) -> DiffResult {
        guard !output.isEmpty else { return .empty }

        var hunks: [DiffHunk] = []
        var currentLines: [DiffLine] = []
        var inHunk = false

        for line in output.components(separatedBy: "\n") {
            // hunk 头部行，如 @@ -1,4 +1,6 @@
            if line.hasPrefix("@@") {
                // 保存上一个 hunk（若有）
                if inHunk && !currentLines.isEmpty {
                    hunks.append(DiffHunk(lines: currentLines))
                    currentLines = []
                }
                inHunk = true
                continue
            }

            // 跳过 diff 头部元信息（diff --git, index, ---, +++ 等）
            if !inHunk {
                continue
            }

            // 解析 diff 行
            if line.hasPrefix("+") {
                // 去掉首个 "+" 字符
                currentLines.append(.added(String(line.dropFirst())))
            } else if line.hasPrefix("-") {
                // 去掉首个 "-" 字符
                currentLines.append(.removed(String(line.dropFirst())))
            } else if line.hasPrefix(" ") {
                // 上下文行，去掉首个空格
                currentLines.append(.context(String(line.dropFirst())))
            } else if line.hasPrefix("\\") {
                // "\ No newline at end of file" 等注释行，跳过
                continue
            }
            // 空行或其他行跳过
        }

        // 保存最后一个 hunk
        if inHunk && !currentLines.isEmpty {
            hunks.append(DiffHunk(lines: currentLines))
        }

        return DiffResult(hunks: hunks)
    }
}
