//
//  GitModels.swift
//  AgentConfig
//
//  Created by cxy on 2026/5/11.
//

import Foundation

// MARK: - GitCommit

/// 代表一条 Git 提交记录
struct GitCommit: Identifiable, Equatable {
    /// 7 位短哈希，用作唯一标识
    let id: String
    /// 完整的 40 位哈希
    let fullHash: String
    /// 提交信息
    let message: String
    /// 提交作者
    let author: String
    /// 提交时间
    let date: Date
}

// MARK: - DiffResult

/// 两个版本之间的差异结果
struct DiffResult: Equatable {
    let hunks: [DiffHunk]

    /// 空差异（两个版本完全相同）
    static let empty = DiffResult(hunks: [])
}

// MARK: - DiffHunk

/// diff 中的一个连续变更块
struct DiffHunk: Equatable {
    let lines: [DiffLine]
}

// MARK: - DiffLine

/// diff 中的单行，区分上下文行、新增行和删除行
enum DiffLine: Equatable {
    /// 上下文行（两个版本中均存在，未变更）
    case context(String)
    /// 新增行（仅在新版本中存在）
    case added(String)
    /// 删除行（仅在旧版本中存在）
    case removed(String)

    /// 行的文本内容
    var content: String {
        switch self {
        case .context(let text): return text
        case .added(let text):   return text
        case .removed(let text): return text
        }
    }
}
