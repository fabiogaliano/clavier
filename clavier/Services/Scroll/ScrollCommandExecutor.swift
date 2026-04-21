//
//  ScrollCommandExecutor.swift
//  clavier
//
//  Translates `(direction, speed)` → CGEvent scroll wheel posting.
//
//  Previously this logic was inlined in `ScrollModeController.performScroll`.
//  Extracting it here keeps the executor concern out of the orchestrator and
//  makes the `ClickService` dependency explicit and injectable.
//

import Foundation
import AppKit

// MARK: - Executor

/// Executes scroll events at a target point by delegating to `ClickService`.
///
/// The controller passes this executor a direction + speed pair from a
/// `ScrollSideEffect.performScroll` and the executor resolves the scroll
/// target from the current session's selected area center point.
@MainActor
final class ScrollCommandExecutor {

    private let clickService: ClickService

    init(clickService: ClickService) {
        self.clickService = clickService
    }

    /// Post a CGEvent scroll wheel event for `direction` at `targetPoint`.
    ///
    /// - Parameters:
    ///   - direction:    The scroll direction.
    ///   - speed:        Speed multiplier (maps directly to `ClickService.scroll`).
    ///   - targetPoint:  Quartz-coordinate point at the center of the scroll area.
    func execute(direction: ScrollDirection, speed: Double, at targetPoint: CGPoint) {
        clickService.scroll(at: targetPoint, direction: direction, speed: speed)
    }
}
