//
//  HintActionPolicy.swift
//  clavier
//
//  Primary-action routing policy for hinted elements.
//
//  Native controls usually work well with AXPress and only need the CGEvent
//  click as a fallback. Web-content controls are less reliable: Electron /
//  Chromium often acknowledge AXPress without visibly activating the target.
//  Route those through a real mouse click instead.
//

import Foundation

enum HintPrimaryActionStrategy: Equatable {
    case axPressThenCGEventFallback
    case cgEventOnly
}

struct HintPrimaryActionContext: Equatable {
    let role: String
    /// Discovery-time structural flag copied onto `UIElement` by the walker.
    /// Using the stored value avoids a second live AX ancestor walk during
    /// click execution, which proved unreliable in Electron apps.
    let isWebContent: Bool
}

protocol HintPrimaryActionPolicy {
    func strategy(for context: HintPrimaryActionContext) -> HintPrimaryActionStrategy
}

struct HintActionPolicy: HintPrimaryActionPolicy {
    func strategy(for context: HintPrimaryActionContext) -> HintPrimaryActionStrategy {
        switch (context.isWebContent, context.role) {
        case (true, _), (false, "AXLink"):
            return .cgEventOnly
        case (false, _):
            return .axPressThenCGEventFallback
        }
    }
}
