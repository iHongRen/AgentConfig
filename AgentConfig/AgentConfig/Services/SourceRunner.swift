//
//  SourceRunner.swift
//  AgentConfig
//
//  Created by cxy on 2026/5/11.
//

import Foundation

// MARK: - SourceResult

/// source 命令执行结果
struct SourceResult: Equatable {
    /// 是否执行成功（退出码为 0）
    let success: Bool
    /// 标准输出内容
    let output: String
    /// 标准错误输出内容
    let errorOutput: String
}

// MARK: - SourceRunnerProtocol

/// source 执行服务协议
protocol SourceRunnerProtocol {
    /// 对指定文件执行 `zsh -c "source <path>"`
    /// - Parameter file: 要 source 的文件 URL
    /// - Returns: 执行结果，不抛出异常，失败通过 `success: false` 表示
    func source(file: URL) async -> SourceResult
}

// MARK: - SourceRunner

/// 通过 `Process` 执行 `zsh -c "source <path>"` 的具体实现
final class SourceRunner: SourceRunnerProtocol {

    func source(file: URL) async -> SourceResult {
        await withCheckedContinuation { continuation in
            let process = Process()
            let stdoutPipe = Pipe()
            let stderrPipe = Pipe()

            process.executableURL = URL(fileURLWithPath: "/bin/zsh")
            process.arguments = ["-c", "source \(file.path.shellEscaped)"]
            process.standardOutput = stdoutPipe
            process.standardError = stderrPipe

            process.terminationHandler = { terminatedProcess in
                let stdoutData = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
                let stderrData = stderrPipe.fileHandleForReading.readDataToEndOfFile()

                let output = String(data: stdoutData, encoding: .utf8) ?? ""
                let errorOutput = String(data: stderrData, encoding: .utf8) ?? ""
                let success = terminatedProcess.terminationStatus == 0

                continuation.resume(returning: SourceResult(
                    success: success,
                    output: output,
                    errorOutput: errorOutput
                ))
            }

            do {
                try process.run()
            } catch {
                continuation.resume(returning: SourceResult(
                    success: false,
                    output: "",
                    errorOutput: error.localizedDescription
                ))
            }
        }
    }
}

// MARK: - String + Shell Escaping

private extension String {
    /// 对路径进行 shell 单引号转义，防止路径中的特殊字符引发问题
    var shellEscaped: String {
        // 将单引号替换为 '\'' 以安全地嵌入单引号包裹的字符串中
        "'\(self.replacingOccurrences(of: "'", with: "'\\''"))'"
    }
}
