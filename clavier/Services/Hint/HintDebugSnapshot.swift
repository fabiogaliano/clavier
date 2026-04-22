//
//  HintDebugSnapshot.swift
//  clavier
//
//  Serialises `HintDiscoveryRecorder` events to a human-readable JSON
//  file under `~/Library/Logs/clavier/`, copies the path to the
//  clipboard, and exposes the URL for the debug overlay banner.
//
//  The snapshot pairs with the visual debug overlay by `id`: the number
//  drawn on a rectangle in the overlay matches `nodes[id].id` in the
//  JSON.  That lets the user point at "node 47" verbally and the
//  developer (or Claude) look up the full record.
//

import Foundation
import AppKit
import os

enum HintDebugSnapshot {

    struct AppInfo: Encodable {
        let pid: Int32
        let bundleId: String?
        let localizedName: String?
    }

    struct FrameRecord: Encodable {
        let x: Double
        let y: Double
        let w: Double
        let h: Double

        init(_ rect: CGRect) {
            self.x = Double(rect.origin.x)
            self.y = Double(rect.origin.y)
            self.w = Double(rect.size.width)
            self.h = Double(rect.size.height)
        }
    }

    struct NodeRecord: Encodable {
        let id: Int
        let parentId: Int?
        let depth: Int
        let role: String
        let roleDescription: String?
        let title: String?
        let label: String?
        let value: String?
        let description: String?
        let enabled: Bool?
        let actions: [String]?
        let decision: ClickabilityPolicy.Decision
        let outcome: HintDiscoveryEvent.Outcome
        let ancestorId: Int?
        let childrenVisited: Bool
        let frameAppKit: FrameRecord
        let frameAX: FrameRecord
    }

    struct SummaryRecord: Encodable {
        let visited: Int
        let accepted: Int
        let deduped: Int
        let rejectedTooSmall: Int
        let rejectedNotClickable: Int
        let clipped: Int
        let prunedSubtrees: Int
    }

    struct Root: Encodable {
        let schema: String
        let timestamp: String
        let app: AppInfo
        let summary: SummaryRecord
        let nodes: [NodeRecord]
    }

    /// Write the recorder's events to disk and return the file URL.
    ///
    /// Snapshots land in `<repo>/debug-snapshots/` so the developer (and
    /// Claude) can open them by a stable relative path — `debug-snapshots/
    /// latest.json` is always the most recent run, and the timestamped
    /// sibling lets you keep multiple runs for comparison.  The directory
    /// is in `.gitignore`.
    ///
    /// The repo root is derived from `#filePath` at compile time, which
    /// resolves to the absolute path of this source file on whichever
    /// machine built the binary — no hardcoded home directory.
    ///
    /// Failures log via `Logger.app.warning` and return nil so callers
    /// can still show the overlay.
    @MainActor
    @discardableResult
    static func write(recorder: HintDiscoveryRecorder, app: NSRunningApplication?) -> URL? {
        let timestamp = ISO8601DateFormatter().string(from: Date())
        let filename = "snapshot-" + timestamp.replacingOccurrences(of: ":", with: "-") + ".json"

        let root = Root(
            schema: "clavier.hint-debug.v1",
            timestamp: timestamp,
            app: AppInfo(
                pid: app?.processIdentifier ?? 0,
                bundleId: app?.bundleIdentifier,
                localizedName: app?.localizedName
            ),
            summary: Self.makeSummary(recorder.summary()),
            nodes: recorder.events.map { e in
                NodeRecord(
                    id: e.id,
                    parentId: e.parentId,
                    depth: e.depth,
                    role: e.role,
                    roleDescription: e.roleDescription,
                    title: e.title,
                    label: e.label,
                    value: e.value,
                    description: e.description,
                    enabled: e.enabled,
                    actions: e.actions,
                    decision: e.decision,
                    outcome: e.outcome,
                    ancestorId: e.ancestorId,
                    childrenVisited: e.childrenVisited,
                    frameAppKit: FrameRecord(e.frameAppKit),
                    frameAX: FrameRecord(e.frameAX)
                )
            }
        )

        let snapshotsDir = snapshotsDirectoryURL()
        let fm = FileManager.default

        do {
            try fm.createDirectory(at: snapshotsDir, withIntermediateDirectories: true)
            let fileURL = snapshotsDir.appendingPathComponent(filename)
            let latestURL = snapshotsDir.appendingPathComponent("latest.json")

            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(root)
            try data.write(to: fileURL, options: .atomic)

            // Replace-in-place so `debug-snapshots/latest.json` is always
            // the most recent run — lets Claude open it by a stable path.
            if fm.fileExists(atPath: latestURL.path) {
                try fm.removeItem(at: latestURL)
            }
            try data.write(to: latestURL, options: .atomic)

            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(fileURL.path, forType: .string)

            return fileURL
        } catch {
            Logger.app.warning("Failed to write hint debug snapshot: \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }

    /// Derive `<repo>/debug-snapshots/` from the source file's compile-time
    /// path.  This source file lives at `clavier/Services/Hint/HintDebugSnapshot.swift`,
    /// so the repo root is four `deletingLastPathComponent` hops up.
    private static func snapshotsDirectoryURL() -> URL {
        let thisFile = URL(fileURLWithPath: #filePath)
        let repoRoot = thisFile
            .deletingLastPathComponent()  // drop HintDebugSnapshot.swift
            .deletingLastPathComponent()  // drop Hint
            .deletingLastPathComponent()  // drop Services
            .deletingLastPathComponent()  // drop clavier
        return repoRoot.appendingPathComponent("debug-snapshots", isDirectory: true)
    }

    private static func makeSummary(_ s: HintDiscoveryRecorder.Summary) -> SummaryRecord {
        SummaryRecord(
            visited: s.visited,
            accepted: s.accepted,
            deduped: s.deduped,
            rejectedTooSmall: s.rejectedTooSmall,
            rejectedNotClickable: s.rejectedNotClickable,
            clipped: s.clipped,
            prunedSubtrees: s.prunedSubtrees
        )
    }
}
