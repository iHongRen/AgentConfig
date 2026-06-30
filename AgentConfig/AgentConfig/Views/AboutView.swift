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

    @Environment(\.openURL) private var openURL

    // MARK: - App Info

    private var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "—"
    }

    private let projectGitHubURL = URL(string: "https://github.com/iHongRen/AgentConfig")!
    private let authorGitHubURL = URL(string: "https://github.com/iHongRen")!

    // MARK: - Body

    var body: some View {
        VStack(spacing: 18) {
            appHeader
            actionButtons
        }
        .padding(24)
        .frame(width: 420, height: 390)
    }

    // MARK: - Sections

    private var appHeader: some View {
        VStack(spacing: 14) {
            if let icon = NSApp.applicationIconImage {
                Image(nsImage: icon)
                    .resizable()
                    .interpolation(.high)
                    .frame(width: 92, height: 92)
                    .clipShape(RoundedRectangle(cornerRadius: 21, style: .continuous))
                    .shadow(color: .black.opacity(0.12), radius: 12, y: 4)
            }

            Text(versionText)
                .font(.subheadline)
                .foregroundColor(.secondary)
        }
        .padding(.vertical, 24)
        .frame(maxWidth: .infinity)
        .background(
            LinearGradient(
                colors: [
                    Color(NSColor.controlBackgroundColor),
                    Color(NSColor.windowBackgroundColor)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(Color(NSColor.separatorColor), lineWidth: 0.5)
        }
    }

    private var actionButtons: some View {
        VStack(spacing: 12) {
            linkButton(
                title: "GitHub",
                subtitle: "github.com/iHongRen/AgentConfig",
                systemImage: "arrow.up.right.square",
                url: projectGitHubURL
            )

            linkButton(
                title: "@仙银",
                subtitle: "github.com/iHongRen",
                systemImage: "person.crop.circle",
                url: authorGitHubURL
            )
        }
    }

    // MARK: - Helpers

    private var versionText: String {
        String(
            format: NSLocalizedString(
                "about.version.build",
                value: "Version %@",
                comment: "About view version text"
            ),
            appVersion
        )
    }

    private func linkButton(
        title: String,
        subtitle: String,
        systemImage: String,
        url: URL
    ) -> some View {
        Button {
            openURL(url)
        } label: {
            HStack(spacing: 14) {
                Image(systemName: systemImage)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundColor(.primary)
                    .frame(width: 38, height: 38)
                    .background(Color.primary.opacity(0.06))
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.headline)
                        .foregroundColor(.primary)

                    Text(subtitle)
                        .font(.system(.caption, design: .monospaced))
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }

                Spacer(minLength: 0)

                Image(systemName: "arrow.up.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.secondary)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(NSColor.controlBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(Color(NSColor.separatorColor), lineWidth: 0.5)
            }
        }
        .buttonStyle(.plain)
    }
}
