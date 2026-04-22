//
//  ShortcutRecorderView.swift
//  clavier
//
//  SwiftUI view for recording keyboard shortcuts
//

import SwiftUI
import AppKit
import Carbon

struct ShortcutRecorderView: View {
    @Binding var keyCode: Int
    @Binding var modifiers: Int

    @State private var showingRecordSheet = false
    @State private var displayText = ""

    var body: some View {
        Button(action: {
            showingRecordSheet = true
        }) {
            Text(displayText)
                .font(.system(size: 13, weight: .medium, design: .rounded))
                .frame(minWidth: 80)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .glassedEffect(in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                .contentShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        }
        .buttonStyle(.plain)
        .onAppear {
            updateDisplayText()
        }
        .sheet(isPresented: $showingRecordSheet) {
            ShortcutRecorderSheet(
                keyCode: $keyCode,
                modifiers: $modifiers,
                onConfirm: {
                    updateDisplayText()
                    showingRecordSheet = false
                },
                onCancel: {
                    showingRecordSheet = false
                }
            )
        }
    }

    private func updateDisplayText() {
        displayText = ShortcutRecorderView.formatShortcut(keyCode: keyCode, modifiers: modifiers)
    }

    static func formatShortcut(keyCode: Int, modifiers: Int) -> String {
        KeymapUtilities.formatShortcut(keyCode: keyCode, modifiers: modifiers)
    }

    static func keyCodeToString(_ keyCode: Int) -> String {
        KeymapUtilities.keyCodeToString(keyCode)
    }
}

struct ShortcutRecorderSheet: View {
    @Binding var keyCode: Int
    @Binding var modifiers: Int
    var onConfirm: () -> Void
    var onCancel: () -> Void

    @State private var currentPreview = ""
    @State private var recordedKeyCode: Int = -1
    @State private var recordedModifiers: Int = 0
    @State private var hasValidShortcut = false
    @State private var keyDownMonitor: Any?
    @State private var flagsChangedMonitor: Any?

    var body: some View {
        VStack(spacing: 24) {
            VStack(spacing: 4) {
                Text("Record Shortcut")
                    .font(.headline)
                Text("Press your key combination")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Text(currentPreview.isEmpty ? "…" : currentPreview)
                .font(.system(size: 42, weight: .semibold, design: .rounded))
                .foregroundStyle(currentPreview.isEmpty ? .secondary : .primary)
                .frame(maxWidth: .infinity)
                .frame(height: 72)
                .glassedEffect(in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .animation(.easeInOut(duration: 0.12), value: currentPreview)

            HStack(spacing: 10) {
                Button("Cancel") {
                    cleanup()
                    onCancel()
                }
                .keyboardShortcut(.cancelAction)
                .buttonStyle(.bordered)

                Spacer()

                Button("Confirm") {
                    keyCode = recordedKeyCode
                    modifiers = recordedModifiers
                    cleanup()
                    onConfirm()
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
                .disabled(!hasValidShortcut)
            }
        }
        .padding(24)
        .frame(width: 340)
        .onAppear {
            startMonitoring()
        }
        .onDisappear {
            cleanup()
        }
    }

    private func startMonitoring() {
        // Notify controllers to temporarily disable their hotkeys
        NotificationCenter.default.post(name: .disableGlobalHotkeys, object: nil)

        // Monitor modifier key changes for real-time preview
        flagsChangedMonitor = NSEvent.addLocalMonitorForEvents(matching: .flagsChanged) { event in
            updateModifierPreview(flags: event.modifierFlags)
            return event
        }

        // Monitor key presses
        keyDownMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            // Ignore modifier-only key codes
            let modifierKeyCodes: Set<UInt16> = [54, 55, 56, 57, 58, 59, 60, 61, 62, 63]
            guard !modifierKeyCodes.contains(event.keyCode) else {
                return event
            }

            // Record the shortcut
            self.recordedKeyCode = Int(event.keyCode)
            self.recordedModifiers = self.carbonModifiersFromFlags(event.modifierFlags)
            self.hasValidShortcut = true
            self.updatePreview()

            return nil // Consume the event
        }
    }

    private func updateModifierPreview(flags: NSEvent.ModifierFlags) {
        // Only update preview if we haven't recorded a full shortcut yet
        if !hasValidShortcut {
            var preview = ""
            if flags.contains(.control) {
                preview += "⌃"
            }
            if flags.contains(.option) {
                preview += "⌥"
            }
            if flags.contains(.shift) {
                preview += "⇧"
            }
            if flags.contains(.command) {
                preview += "⌘"
            }
            currentPreview = preview
        }
    }

    private func updatePreview() {
        currentPreview = ShortcutRecorderView.formatShortcut(keyCode: recordedKeyCode, modifiers: recordedModifiers)
    }

    private func carbonModifiersFromFlags(_ flags: NSEvent.ModifierFlags) -> Int {
        KeymapUtilities.carbonModifiers(from: flags)
    }

    private func cleanup() {
        if let monitor = keyDownMonitor {
            NSEvent.removeMonitor(monitor)
            keyDownMonitor = nil
        }
        if let monitor = flagsChangedMonitor {
            NSEvent.removeMonitor(monitor)
            flagsChangedMonitor = nil
        }
        // Re-enable global hotkeys
        NotificationCenter.default.post(name: .enableGlobalHotkeys, object: nil)
    }
}
