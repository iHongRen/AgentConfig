//
//  AppError.swift
//  AgentConfig
//
//  Created by cxy on 2026/5/11.
//

import Foundation

// MARK: - AppError

/// 应用级别的错误枚举，提供用户可读的本地化描述
enum AppError: LocalizedError {
    /// 文件读取失败
    case fileReadFailed(URL, Error)

    /// 文件写入失败
    case fileWriteFailed(URL, Error)

    /// JSON 格式化错误，包含行列位置信息
    case jsonFormatError(line: Int, column: Int, message: String)

    /// source 命令执行失败
    case sourceFailed(stderr: String)

    // MARK: - LocalizedError

    var errorDescription: String? {
        switch self {
        case .fileReadFailed(let url, let error):
            return NSLocalizedString(
                "error.fileReadFailed",
                value: "Failed to read file \"\(url.lastPathComponent)\": \(error.localizedDescription)",
                comment: "Error when reading a file fails"
            )

        case .fileWriteFailed(let url, let error):
            return NSLocalizedString(
                "error.fileWriteFailed",
                value: "Failed to write file \"\(url.lastPathComponent)\": \(error.localizedDescription)",
                comment: "Error when writing a file fails"
            )

        case .jsonFormatError(let line, let column, let message):
            return NSLocalizedString(
                "error.jsonFormatError",
                value: "JSON format error at line \(line), column \(column): \(message)",
                comment: "Error when JSON formatting fails"
            )

        case .sourceFailed(let stderr):
            return NSLocalizedString(
                "error.sourceFailed",
                value: "source command failed: \(stderr)",
                comment: "Error when source command fails"
            )
        }
    }

    var failureReason: String? {
        switch self {
        case .fileReadFailed(_, let error):
            return error.localizedDescription
        case .fileWriteFailed(_, let error):
            return error.localizedDescription
        case .jsonFormatError(_, _, let message):
            return message
        case .sourceFailed(let stderr):
            return stderr
        }
    }

    var recoverySuggestion: String? {
        switch self {
        case .fileReadFailed:
            return NSLocalizedString(
                "error.fileReadFailed.recovery",
                value: "Check file permissions and try again.",
                comment: "Recovery suggestion for file read failure"
            )
        case .fileWriteFailed:
            return NSLocalizedString(
                "error.fileWriteFailed.recovery",
                value: "Check file permissions and available disk space.",
                comment: "Recovery suggestion for file write failure"
            )
        case .jsonFormatError:
            return NSLocalizedString(
                "error.jsonFormatError.recovery",
                value: "Fix the JSON syntax error and try formatting again.",
                comment: "Recovery suggestion for JSON format error"
            )
        case .sourceFailed:
            return NSLocalizedString(
                "error.sourceFailed.recovery",
                value: "Check the shell script for syntax errors.",
                comment: "Recovery suggestion for source command failure"
            )
        }
    }
}
