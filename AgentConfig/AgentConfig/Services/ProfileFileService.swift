//
//  ProfileFileService.swift
//  AgentConfig
//

import Foundation

/// Profile 服务共享的文件读写与 `.zshrc` 托管块管理逻辑。
///
/// `CodexProfileService` 与 `ClaudeProfileService` 通过此类型复用：
/// - 规范化后的原子写入
/// - 父目录自动创建
/// - 带 `BEGIN`/`END` 标记的 `.zshrc` 托管块写入与提取
final class ProfileFileService {

    let fileManager: FileManager

    init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
    }

    // MARK: - 文件读写

    func write(_ content: String, to url: URL) throws {
        try ensureParentDirectory(for: url)
        try normalized(content).write(to: url, atomically: true, encoding: .utf8)
    }

    func readIfExists(at url: URL) -> String? {
        guard fileManager.fileExists(atPath: url.path) else { return nil }
        return try? String(contentsOf: url, encoding: .utf8)
    }

    var zshrcURL: URL {
        fileManager.homeDirectoryForCurrentUser.appendingPathComponent(".zshrc")
    }

    // MARK: - .zshrc 托管块

    /// 将托管块写入 `.zshrc`：已存在同名块则替换，否则追加到末尾。
    /// - Parameters:
    ///   - content: 托管块内部内容（不含 BEGIN/END 标记）
    ///   - blockID: 用于区分不同 Agent 的标记后缀（如 "Codex Profile" / "Claude Profile"）
    func applyManagedZshrcBlock(_ content: String, blockID: String) throws {
        try write(computedZshrcWithBlock(content, blockID: blockID), to: zshrcURL)
    }

    /// 计算写入托管块后的 `.zshrc` 完整内容（不落盘），供事务化写入使用。
    func computedZshrcWithBlock(_ content: String, blockID: String) -> String {
        let begin = "# AgentConfig \(blockID) BEGIN"
        let end = "# AgentConfig \(blockID) END"
        let managedBlock = [begin, normalized(content), end].joined(separator: "\n")
        let current = readIfExists(at: zshrcURL) ?? ""

        if let beginRange = current.range(of: begin),
           let endRange = current.range(of: end, range: beginRange.upperBound..<current.endIndex) {
            return String(current[..<beginRange.lowerBound])
                + managedBlock
                + String(current[endRange.upperBound...])
        } else if current.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return managedBlock + "\n"
        } else {
            return normalized(current) + "\n\n" + managedBlock + "\n"
        }
    }

    /// 事务化写入多个文件：任一失败则回滚已写入的文件到写入前快照。
    /// - Parameter writes: 目标 `(url, content)` 列表，按顺序写入。
    func performWrites(_ writes: [(URL, String)]) throws {
        var backups: [(URL, String?)] = []
        for (url, content) in writes {
            backups.append((url, readIfExists(at: url)))
            do {
                try write(content, to: url)
            } catch {
                rollback(backups)
                throw error
            }
        }
    }

    private func rollback(_ backups: [(URL, String?)]) {
        for (url, snapshot) in backups {
            if let snapshot {
                try? write(snapshot, to: url)
            } else {
                try? fileManager.removeItem(at: url)
            }
        }
    }

    /// 从 `.zshrc` 提取指定托管块的内部内容（不含 BEGIN/END 标记）。
    /// - Parameter blockID: 标记后缀
    /// - Returns: 内部内容；不存在时返回 `nil`
    func extractManagedZshrcBlock(blockID: String) -> String? {
        let begin = "# AgentConfig \(blockID) BEGIN"
        let end = "# AgentConfig \(blockID) END"
        guard let content = readIfExists(at: zshrcURL),
              let beginRange = content.range(of: begin),
              let endRange = content.range(of: end, range: beginRange.upperBound..<content.endIndex) else {
            return nil
        }

        let body = content[beginRange.upperBound..<endRange.lowerBound]
        return body
            .trimmingCharacters(in: CharacterSet(charactersIn: "\n"))
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
    }

    // MARK: - 私有

    private func ensureParentDirectory(for url: URL) throws {
        let parent = url.deletingLastPathComponent()
        if !fileManager.fileExists(atPath: parent.path) {
            try fileManager.createDirectory(at: parent, withIntermediateDirectories: true)
        }
    }

    private func normalized(_ content: String) -> String {
        content.hasSuffix("\n") ? String(content.dropLast()) : content
    }
}
