//
//  Logging.swift
//  clavier
//
//  Shared `os.Logger` instances for structured logging.
//
//  Subsystem matches the app's bundle identifier so Console.app filters
//  such as `subsystem == "fabiogaliano.clavier"` capture the full log
//  stream.  Categories partition the stream by domain so feature-specific
//  traces can be isolated without touching unrelated code paths.
//
//  Level guidance:
//  - `.warning` — operational failure that degrades the feature but does
//    not crash the app (event tap creation failed, missing permissions).
//  - `.debug`   — perf/diagnostic traces kept available for live debugging
//    via `log stream --level debug`, but elided from the persistent store.
//

import Foundation
import os

extension Logger {
    private static let subsystem = "fabiogaliano.clavier"

    static let app = Logger(subsystem: subsystem, category: "app")
    static let hintMode = Logger(subsystem: subsystem, category: "hintMode")
    static let scrollMode = Logger(subsystem: subsystem, category: "scrollMode")
    static let accessibility = Logger(subsystem: subsystem, category: "accessibility")
    static let scrollDetect = Logger(subsystem: subsystem, category: "scrollDetect")
}
