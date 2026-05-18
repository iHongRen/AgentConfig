//
//  ConfigExamplesPaneView.swift
//  AgentConfig
//
//  Created by Claude on 2026/5/17.
//

import SwiftUI
import AppKit

struct ConfigExamplesPaneView: View {
    let groups: [ConfigExampleGroup]
    let file: ConfigFile?
    let onCopy: (String) -> Void

    var body: some View {
        VStack(spacing: 0) {
            header

            Divider()

            if groups.isEmpty {
                emptyState
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 16) {
                        ForEach(groups) { group in
                            groupView(group)
                        }
                    }
                    .padding(.leading, 16)
                    .padding(.trailing, 20)
                    .padding(.vertical, 16)
                }
                .clipped()
            }
        }
        .background(Color.examplesPaneBackground)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 8) {
                Image(systemName: "book.pages")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Color.accentColor)

                Text("配置示例")
                    .font(.system(size: 14, weight: .semibold))
                    .lineLimit(1)

                Spacer(minLength: 6)

                if let documentationURL {
                    iconButton(systemName: "safari", foregroundColor: .accentColor) {
                        NSWorkspace.shared.open(documentationURL)
                    }
                    .help("打开官方配置文档")
                    .layoutPriority(2)
                }
            }

            if let file {
                Text(file.url.lastPathComponent)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private var documentationURL: URL? {
        groups.first(where: { $0.documentationURL != nil })?.documentationURL
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: "doc.text.magnifyingglass")
                .font(.system(size: 32))
                .foregroundStyle(.tertiary)

            Text("暂无配置示例")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.secondary)

            Text("仅默认配置文件会显示示例。")
                .font(.system(size: 12))
                .foregroundStyle(.tertiary)
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func groupView(_ group: ConfigExampleGroup) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(group.title)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.primary)

            if let summary = group.summary {
                Text(summary)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            ForEach(group.examples) { example in
                exampleCard(example)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func iconButton(systemName: String, foregroundColor: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(foregroundColor)
                .frame(width: 28, height: 28)
                .background(
                    RoundedRectangle(cornerRadius: 7)
                        .fill(Color(nsColor: .controlBackgroundColor))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 7)
                        .strokeBorder(Color(nsColor: .separatorColor).opacity(0.8))
                )
        }
        .buttonStyle(.plain)
    }

    private func exampleCard(_ example: ConfigExample) -> some View {
        ZStack(alignment: .topTrailing) {
            VStack(alignment: .leading, spacing: 8) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(example.title)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.trailing, 38)

                    Text(example.language)
                        .font(.system(size: 10, weight: .semibold, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Capsule().fill(Color(nsColor: .quaternaryLabelColor)))
                }

                if let description = example.description {
                    Text(description)
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Text(example.code)
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundStyle(.primary)
                    .textSelection(.enabled)
                    .lineLimit(nil)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(Color.examplesCodeBackground)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .strokeBorder(Color(nsColor: .separatorColor).opacity(0.65))
                    )
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(Color.examplesCardBackground)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .strokeBorder(Color(nsColor: .separatorColor).opacity(0.5))
            )

            iconButton(systemName: "doc.on.doc", foregroundColor: .primary) {
                onCopy(example.code)
            }
            .help("复制示例")
            .padding(8)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private extension Color {
    static var examplesPaneBackground: Color {
        Color(nsColor: .windowBackgroundColor)
    }

    static var examplesCardBackground: Color {
        Color(nsColor: .controlBackgroundColor)
    }

    static var examplesCodeBackground: Color {
        Color(nsColor: .textBackgroundColor)
    }
}
