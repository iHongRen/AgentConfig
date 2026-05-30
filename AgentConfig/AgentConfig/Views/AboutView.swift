//
//  AboutView.swift
//  AgentConfig
//
//  Created by cxy on 2026/5/11.
//

import SwiftUI
import AppKit

// MARK: - AboutView

struct AboutView: View {

    // MARK: - App Info

    private var appName: String {
        Bundle.main.infoDictionary?["CFBundleName"] as? String ?? "AgentConfig"
    }

    private var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "—"
    }

    private var buildNumber: String {
        Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "—"
    }

    private let authorName = "cxy"
    private let githubURL = URL(string: "https://github.com/cxy")!
    private let licenseURL = URL(string: "https://opensource.org/licenses/MIT")!

    // MARK: - State

    @State private var selectedTab: HelpTab = .agents

    // MARK: - Body

    var body: some View {
        VStack(spacing: 0) {
            appInfoSection
            Divider()
                .padding(.vertical, 8)
            helpSection
        }
        .padding(24)
        .frame(width: 560, height: 620)
    }

    // MARK: - App Info Section

    private var appInfoSection: some View {
        VStack(spacing: 12) {
            // App Icon
            if let icon = NSApp.applicationIconImage {
                Image(nsImage: icon)
                    .resizable()
                    .frame(width: 80, height: 80)
                    .cornerRadius(16)
            }

            // App Name
            Text(appName)
                .font(.title2)
                .fontWeight(.semibold)

            // Version & Build
            HStack(spacing: 4) {
                Text(String(format: NSLocalizedString("about.version", comment: ""), appVersion))
                    .foregroundColor(.secondary)
                Text("(\(String(format: NSLocalizedString("about.build", comment: ""), buildNumber)))")
                    .foregroundColor(.secondary)
            }
            .font(.subheadline)

            // Author & GitHub
            HStack(spacing: 6) {
                Text(String(format: NSLocalizedString("about.author", comment: ""), authorName))
                    .foregroundColor(.secondary)
                Text("·")
                    .foregroundColor(.secondary)
                Link(NSLocalizedString("about.github", comment: ""), destination: githubURL)
                    .font(.subheadline)
            }
            .font(.subheadline)

            // License
            HStack(spacing: 4) {
                Text(NSLocalizedString("about.license.prefix", comment: ""))
                    .foregroundColor(.secondary)
                Link(NSLocalizedString("about.license.mit", comment: ""), destination: licenseURL)
            }
            .font(.caption)
        }
        .padding(.bottom, 8)
    }

    // MARK: - Help Section

    private var helpSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(NSLocalizedString("about.help.title", comment: ""))
                .font(.headline)
                .padding(.bottom, 2)

            // Tab Picker
            Picker("", selection: $selectedTab) {
                ForEach(HelpTab.allCases) { tab in
                    Text(tab.localizedTitle).tag(tab)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()

            // Tab Content
            ScrollView {
                switch selectedTab {
                case .agents:
                    agentsTabContent
                case .faq:
                    faqTabContent
                case .shortcuts:
                    shortcutsTabContent
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    // MARK: - Agents Tab

    private var agentsTabContent: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(AgentDefinitions.all, id: \.id) { agent in
                AgentRowView(agent: agent)
                Divider()
            }
        }
        .padding(.top, 4)
    }

    // MARK: - FAQ Tab

    private var faqTabContent: some View {
        VStack(alignment: .leading, spacing: 16) {
            ForEach(faqItems, id: \.question) { item in
                FAQItemView(question: item.question, answer: item.answer)
            }
        }
        .padding(.top, 4)
    }

    private var faqItems: [(question: String, answer: String)] {
        [
            (
                question: NSLocalizedString("faq.q1", comment: ""),
                answer: NSLocalizedString("faq.a1", comment: "")
            ),
            (
                question: NSLocalizedString("faq.q2", comment: ""),
                answer: NSLocalizedString("faq.a2", comment: "")
            ),
            (
                question: NSLocalizedString("faq.q3", comment: ""),
                answer: NSLocalizedString("faq.a3", comment: "")
            ),
            (
                question: NSLocalizedString("faq.q4", comment: ""),
                answer: NSLocalizedString("faq.a4", comment: "")
            ),
            (
                question: NSLocalizedString("faq.q5", comment: ""),
                answer: NSLocalizedString("faq.a5", comment: "")
            ),
            (
                question: NSLocalizedString("faq.q6", comment: ""),
                answer: NSLocalizedString("faq.a6", comment: "")
            ),
        ]
    }

    // MARK: - Shortcuts Tab

    private var shortcutsTabContent: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(shortcutItems, id: \.key) { item in
                ShortcutRowView(key: item.key, description: item.description)
                Divider()
            }
        }
        .padding(.top, 4)
    }

    private var shortcutItems: [(key: String, description: String)] {
        [
            ("⌘S",       NSLocalizedString("shortcut.save", comment: "")),
            ("⌘F",       NSLocalizedString("shortcut.search", comment: "")),
            ("⌘G",       NSLocalizedString("shortcut.findNext", comment: "")),
            ("⌘⇧G",     NSLocalizedString("shortcut.findPrev", comment: "")),
            ("⌘Z",       NSLocalizedString("shortcut.undo", comment: "")),
            ("⌘⇧Z",     NSLocalizedString("shortcut.redo", comment: "")),
            ("⌘R",       NSLocalizedString("shortcut.refresh", comment: "")),
            ("⌘⇧F",     NSLocalizedString("shortcut.format", comment: "")),
        ]
    }
}

// MARK: - HelpTab

private enum HelpTab: String, CaseIterable, Identifiable {
    case agents
    case faq
    case shortcuts

    var id: String { rawValue }

    var localizedTitle: String {
        switch self {
        case .agents:    return NSLocalizedString("about.tab.agents", comment: "")
        case .faq:       return NSLocalizedString("about.tab.faq", comment: "")
        case .shortcuts: return NSLocalizedString("about.tab.shortcuts", comment: "")
        }
    }
}

// MARK: - AgentRowView

private struct AgentRowView: View {
    let agent: AgentDefinition

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(agent.displayName)
                .fontWeight(.medium)
            ForEach(agent.configFiles, id: \.title) { entry in
                HStack(spacing: 4) {
                    Image(systemName: "doc")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                    Text(entry.title)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .textSelection(.enabled)
                }
            }
        }
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - FAQItemView

private struct FAQItemView: View {
    let question: String
    let answer: String

    @State private var isExpanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    isExpanded.toggle()
                }
            } label: {
                HStack(alignment: .top) {
                    Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                        .font(.caption)
                        .foregroundColor(.accentColor)
                        .frame(width: 14)
                        .padding(.top, 2)
                    Text(question)
                        .fontWeight(.medium)
                        .multilineTextAlignment(.leading)
                        .foregroundColor(.primary)
                    Spacer()
                }
            }
            .buttonStyle(.plain)

            if isExpanded {
                Text(answer)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.leading)
                    .padding(.leading, 18)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

// MARK: - ShortcutRowView

private struct ShortcutRowView: View {
    let key: String
    let description: String

    var body: some View {
        HStack {
            Text(description)
                .foregroundColor(.primary)
            Spacer()
            Text(key)
                .font(.system(.body, design: .monospaced))
                .foregroundColor(.secondary)
                .padding(.horizontal, 8)
                .padding(.vertical, 2)
                .background(Color(NSColor.controlBackgroundColor))
                .cornerRadius(4)
                .overlay(
                    RoundedRectangle(cornerRadius: 4)
                        .stroke(Color(NSColor.separatorColor), lineWidth: 0.5)
                )
        }
        .padding(.vertical, 7)
    }
}

