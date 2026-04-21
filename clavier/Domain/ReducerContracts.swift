//
//  ReducerContracts.swift
//  clavier
//
//  Frozen reducer/coordinator naming and structural contract for P4-S2 and P4-S3.
//
//  P4-S2 extracts: HintInputReducer, HintRefreshCoordinator, HintOverlayRenderer
//  P4-S3 extracts: ScrollSelectionReducer, ScrollDiscoveryCoordinator, ScrollCommandExecutor
//
//  WHY a marker protocol rather than a shared generic protocol:
//  Both reducers share the (State, Command) -> (State, [SideEffect]) shape, but their
//  State and Command types are disjoint.  A generic `ModeReducer` protocol with
//  associated types provides no compile-time enforcement that downstream stories care
//  about — the two branches never interact through a shared reducer type — and adds
//  PAT complexity without benefit.
//
//  Instead this file defines:
//  1. A `ReducerSideEffect` marker protocol that both concrete side-effect enums must
//     conform to.  This keeps the naming convention machine-checkable.
//  2. A `ModeCoordinator` marker protocol for the refresh/discovery coordinator role.
//
//  Downstream stories add their conformances; this file is not otherwise modified.
//

import Foundation

/// Marker protocol for side-effect intents returned by mode reducers.
///
/// Concrete conformances are enums declared in the respective mode modules:
/// - `HintSideEffect` (P4-S2)
/// - `ScrollSideEffect` (P4-S3)
///
/// Controllers (or their coordinators) switch over the returned array and execute
/// each effect.  No shared execution logic is implied by conforming to this marker.
protocol ReducerSideEffect {}

/// Marker protocol for the refresh/discovery coordinator role in each mode.
///
/// A `ModeCoordinator` owns the asynchronous lifecycle of its mode's discovery or
/// refresh loop.  It is separate from the reducer to isolate pure state transitions
/// (reducer) from timing/async concerns (coordinator).
///
/// Concrete types:
/// - `HintRefreshCoordinator` (P4-S2)
/// - `ScrollDiscoveryCoordinator` (P4-S3)
protocol ModeCoordinator: AnyObject {}
