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

    // MARK: - LocalizedError

    var errorDescription: String? {
        switch self {
        case .fileReadFailed(let url, let error):
            return L10n.format(
                "error.fileReadFailed",
                value: "Failed to read file \"%@\": %@",
                url.lastPathComponent,
                error.localizedDescription
            )

        case .fileWriteFailed(let url, let error):
            return L10n.format(
                "error.fileWriteFailed",
                value: "Failed to write file \"%@\": %@",
                url.lastPathComponent,
                error.localizedDescription
            )

        case .jsonFormatError(let line, let column, let message):
            return L10n.format(
                "error.jsonFormatError",
                value: "JSON format error at line %d, column %d: %@",
                line,
                column,
                message
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
        }
    }

    var recoverySuggestion: String? {
        switch self {
        case .fileReadFailed:
            return L10n.tr("error.fileReadFailed.recovery", value: "Check file permissions and try again.")
        case .fileWriteFailed:
            return L10n.tr("error.fileWriteFailed.recovery", value: "Check file permissions and available disk space.")
        case .jsonFormatError:
            return L10n.tr("error.jsonFormatError.recovery", value: "Fix the JSON syntax error and try formatting again.")
        }
    }
}
