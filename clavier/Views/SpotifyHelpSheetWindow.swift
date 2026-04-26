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
        onDismissPermanently: @escaping () -> Void,
        onClose: @escaping () -> Void
    ) {
        let view = SpotifyHelpSheetView(
            onDismissPermanently: onDismissPermanently,
            onClose: onClose
        )
        let host = NSHostingView(rootView: view)

        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 560, height: 400),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )

        title = "clavier"
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
    let onDismissPermanently: () -> Void
    let onClose: () -> Void

    @AppStorage(AppSettings.Keys.spotifyAutoRelaunchEnabled)
    private var spotifyAutoRelaunch: Bool = AppSettings.Defaults.spotifyAutoRelaunchEnabled

    @State private var isRelaunching = false
    @State private var relaunchError: String?
    @State private var relaunchSucceeded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            header
            Divider()
            quickFixSection
            Divider()
            autoRelaunchSection
            Spacer(minLength: 0)
            footer
        }
        .padding(24)
        .frame(width: 560)
    }

    private var header: some View {
        Text("Spotify needs a relaunch to work with clavier.")
            .font(.title2.weight(.semibold))
    }

    private var quickFixSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            quickFixActionRow
        }
        .padding(12)
        .background(.fill.tertiary)
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    @ViewBuilder
    private var quickFixActionRow: some View {
        if relaunchSucceeded {
            Label("Spotify relaunched. Hints should now work.", systemImage: "checkmark.circle.fill")
                .foregroundStyle(.green)
                .font(.callout)
        } else if isRelaunching {
            HStack(spacing: 8) {
                ProgressView()
                    .controlSize(.small)
                Text("Quitting and relaunching Spotify…")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        } else {
            VStack(alignment: .leading, spacing: 8) {
                Button {
                    relaunchSpotify()
                } label: {
                    Label("Relaunch Spotify with hints enabled", systemImage: "arrow.clockwise")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)

                Text("Stops playback. Hints work until Spotify is closed.")
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
        VStack(alignment: .leading, spacing: 8) {
            Toggle("Relaunch automatically on every Spotify launch", isOn: $spotifyAutoRelaunch)
                .toggleStyle(.switch)
                .font(.headline)
            Text("Adds ~2 seconds to Spotify's startup.")
                .font(.callout)
                .foregroundStyle(.secondary)
            if spotifyAutoRelaunch {
                Text("Takes effect next time Spotify opens.")
                    .font(.callout)
                    .foregroundStyle(.tint)
            }
        }
    }

    private var footer: some View {
        HStack {
            Button("Don't show again", action: onDismissPermanently)
                .buttonStyle(.borderless)
                .foregroundStyle(.secondary)
            Spacer()
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

