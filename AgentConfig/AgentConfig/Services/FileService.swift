//
//  FileService.swift
//  AgentConfig
//
//  Created by cxy on 2026/5/11.
//

import Foundation

// MARK: - FileServiceProtocol

/// 文件读写服务协议
protocol FileServiceProtocol {
    /// 读取文件内容（UTF-8 编码）
    /// - Parameter url: 文件路径
    /// - Returns: 文件内容字符串
    /// - Throws: `AppError.fileReadFailed` 读取失败时
    func read(url: URL) async throws -> String

    /// 将字符串写入文件（UTF-8 编码，原子写入）
    /// - Parameters:
    ///   - content: 要写入的内容
    ///   - url: 目标文件路径
    /// - Throws: `AppError.fileWriteFailed` 写入失败时
    func write(content: String, to url: URL) async throws

    /// 创建空文件（若父目录不存在则一并创建）
    /// - Parameter url: 要创建的文件路径
    /// - Throws: `AppError.fileWriteFailed` 创建失败时
    func create(at url: URL) async throws

    /// 获取文件的最后修改时间
    /// - Parameter url: 文件路径
    /// - Returns: 最后修改时间，文件不存在时返回 nil
    func modificationDate(of url: URL) -> Date?

    /// 删除文件
    /// - Parameter url: 文件路径
    /// - Throws: `AppError.fileWriteFailed` 删除失败时
    func delete(at url: URL) async throws
}

// MARK: - FileService

/// `FileServiceProtocol` 的默认实现，封装 `FileManager` 和 `String` 的文件 I/O 操作
final class FileService: FileServiceProtocol {

    private let fileManager: FileManager

    init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
    }

    // MARK: - FileServiceProtocol

    func read(url: URL) async throws -> String {
        do {
            return try String(contentsOf: url, encoding: .utf8)
        } catch {
            throw AppError.fileReadFailed(url, error)
        }
    }

    func write(content: String, to url: URL) async throws {
        do {
            try content.write(to: url, atomically: true, encoding: .utf8)
        } catch {
            throw AppError.fileWriteFailed(url, error)
        }
    }

    func create(at url: URL) async throws {
        // 若父目录不存在则一并创建
        let parentDirectory = url.deletingLastPathComponent()
        do {
            if !fileManager.fileExists(atPath: parentDirectory.path) {
                try fileManager.createDirectory(
                    at: parentDirectory,
                    withIntermediateDirectories: true,
                    attributes: nil
                )
            }
            // 创建空文件（若已存在则不覆盖）
            guard !fileManager.fileExists(atPath: url.path) else { return }
            let created = fileManager.createFile(atPath: url.path, contents: nil, attributes: nil)
            if !created {
                throw CocoaError(.fileWriteUnknown)
            }
        } catch let appError as AppError {
            throw appError
        } catch {
            throw AppError.fileWriteFailed(url, error)
        }
    }

    func modificationDate(of url: URL) -> Date? {
        try? fileManager.attributesOfItem(atPath: url.path)[.modificationDate] as? Date
    }

    func delete(at url: URL) async throws {
        do {
            try fileManager.removeItem(at: url)
        } catch {
            throw AppError.fileWriteFailed(url, error)
        }
    }
}
