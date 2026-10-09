//
//  HintClickKind.swift
//  clavier
//
//  What happens to an element once the user has selected it.
//

import Foundation

enum HintClickKind: Equatable, Sendable {
    /// Left click (AX press where trustworthy).
    case primary
    /// Right click / context menu.
    case secondary
    case double
    /// Move the cursor onto the element without clicking.
    case hover
}
