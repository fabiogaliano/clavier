//
//  ScrollDirection.swift
//  clavier
//
//  Neutral-namespace scroll direction type consumed by ClickService,
//  ScrollInputDecoder, and ScrollModeController.
//
//  Moved out of ClickService (F22) so scroll-mode input decoding and
//  click dispatch can both depend on the type without importing each other.
//

import Foundation

/// The four cardinal scroll directions used across input decoding and event dispatch.
enum ScrollDirection {
    case up, down, left, right
}
