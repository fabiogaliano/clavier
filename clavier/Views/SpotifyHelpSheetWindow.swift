//
//  SpotifyHelpSheetWindow.swift
//  clavier
//
//  Standalone help window shown when clavier detects an empty AX tree
//  in Spotify. Hosts the SwiftUI content via `NSHostingView` so the
//  layout/typography stays consistent with the Preferences panel.
//
//  This window is intentionally NOT a `.screenSaver`-level overlay
//  like the hint or scroll windows. The user needs to read text,
//  copy commands, and click buttons — standard window chrome and
//  focus behaviour are correct here.
//

import AppKit
import SwiftUI

@MainActor
final class SpotifyHelpSheetWindow: NSWindow {

    init(
        onDismissThisSession: @escaping () -> Void,
        onDismissPermanently: @escaping () -> Void,
        onClose: @escaping () -> Void
    ) {
        let view = SpotifyHelpSheetView(
            onDismissThisSession: onDismissThisSession,
            onDismissPermanently: onDismissPermanently,
            onClose: onClose
        )
        let host = NSHostingView(rootView: view)

        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 560, height: 640),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )

        title = "Enable hints in Spotify"
        contentView = host
        isReleasedWhenClosed = false
        // Keep above other windows but not at screen-saver level — the
        // user is reading text and clicking buttons; we want the
        // standard front-most behaviour, not an overlay shield.
        level = .floating
    }
}

// MARK: - SwiftUI content

private struct SpotifyHelpSheetView: View {
    let onDismissThisSession: () -> Void
    let onDismissPermanently: () -> Void
    let onClose: () -> Void

    @State private var isRelaunching = false
    @State private var relaunchError: String?
    @State private var relaunchSucceeded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            header
            Divider()
            explanation
            quickFixSection
            Divider()
            autoRelaunchSection
            Spacer(minLength: 0)
            footer
        }
        .padding(24)
        .frame(width: 560, height: 520)
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "music.note.list")
                .font(.system(size: 28))
                .foregroundStyle(.tint)
            VStack(alignment: .leading, spacing: 4) {
                Text("Spotify needs a launch flag")
                    .font(.title2.weight(.semibold))
                Text("clavier can't see Spotify's UI yet — here's how to fix it.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var explanation: some View {
        Text("""
            Spotify is built on CEF (Chromium Embedded Framework), not Electron. \
            Other Chromium apps like Slack and Discord let clavier wake their accessibility tree at runtime, but CEF doesn't expose that hook. The fix is to relaunch Spotify with a Chromium flag that enables accessibility from startup.
            """)
            .font(.callout)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }

    private var quickFixSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Quick fix — works for any Spotify install", systemImage: "bolt.fill")
                .font(.headline)
                .foregroundStyle(.primary)

            Text("Quits Spotify and reopens it with the accessibility flag enabled. Active until you quit Spotify yourself.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            quickFixActionRow
        }
    }

    @ViewBuilder
    private var quickFixActionRow: some View {
        if relaunchSucceeded {
            Label("Spotify relaunched. Trigger hints again to see them.", systemImage: "checkmark.circle.fill")
                .foregroundStyle(.green)
                .font(.callout)
        } else if isRelaunching {
            HStack(spacing: 10) {
                ProgressView()
                    .controlSize(.small)
                Text("Quitting and relaunching Spotify…")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        } else {
            VStack(alignment: .leading, spacing: 6) {
                Button {
                    relaunchSpotify()
                } label: {
                    Label("Relaunch Spotify with hints enabled", systemImage: "arrow.clockwise")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)

                Text("Current playback will stop.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                if let error = relaunchError {
                    Label(error, systemImage: "exclamationmark.triangle.fill")
                        .font(.caption)
                        .foregroundStyle(.red)
                        .padding(.top, 4)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private var autoRelaunchSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Make it automatic (optional)", systemImage: "arrow.triangle.2.circlepath")
                .font(.headline)

            Text("Tired of clicking the button every time? Enable **Automatically relaunch Spotify with the flag on every launch** in clavier's Preferences → General → Spotify. clavier will silently re-launch Spotify with the flag whenever it detects an unflagged launch — at the cost of ~2 seconds added to Spotify's startup.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var footer: some View {
        HStack {
            Button("Don't show again", action: onDismissPermanently)
                .buttonStyle(.borderless)
                .foregroundStyle(.secondary)
            Spacer()
            Button("Not now", action: onDismissThisSession)
                .keyboardShortcut(.cancelAction)
            Button("Close", action: onClose)
                .keyboardShortcut(.defaultAction)
        }
    }

    private func relaunchSpotify() {
        relaunchError = nil
        isRelaunching = true
        Task { @MainActor in
            do {
                try await SpotifyAccessibilityHelper.shared.relaunchSpotifyWithFlag()
                isRelaunching = false
                relaunchSucceeded = true
            } catch let error as SpotifyAccessibilityHelper.RelaunchError {
                isRelaunching = false
                relaunchError = error.errorDescription
            } catch {
                isRelaunching = false
                relaunchError = error.localizedDescription
            }
        }
    }
}

