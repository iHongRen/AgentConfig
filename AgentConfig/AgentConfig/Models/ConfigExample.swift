//
//  ConfigExample.swift
//  AgentConfig
//
//  Created by Claude on 2026/5/17.
//

import Foundation

struct ConfigExample: Identifiable, Equatable {
    let id: String
    let title: String
    let description: String?
    let language: String
    let code: String
}

struct ConfigExampleGroup: Identifiable, Equatable {
    let id: String
    let title: String
    let summary: String?
    let documentationURL: URL?
    let examples: [ConfigExample]
}
