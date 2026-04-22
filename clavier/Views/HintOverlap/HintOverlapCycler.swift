//
//  HintOverlapCycler.swift
//  clavier
//
//  Pure geometry for overlap-group detection and z-order rotation.
//
//  Given a list of label frames in window-local coordinates, produces:
//  - connected components of mutually-intersecting frames (overlap groups)
//  - a rotation function that maps a step count to the index within each
//    group that should sit on top of its siblings.
//
//  Kept pure (no AppKit state) so the cycling rule is testable without a
//  running overlay window.
//

import CoreGraphics

struct HintOverlapCycler {

    /// Index list form of an overlap group: members are indices into the
    /// source frame array, ordered by their original placement sequence.
    struct Group: Equatable {
        let memberIndices: [Int]
    }

    /// Compute connected components where two frames are connected if they
    /// intersect. Singletons (non-overlapping labels) are omitted — cycling
    /// only affects labels that have a disambiguation choice.
    static func groups(for frames: [CGRect]) -> [Group] {
        let n = frames.count
        guard n > 1 else { return [] }

        var parent = Array(0..<n)

        func find(_ i: Int) -> Int {
            var x = i
            while parent[x] != x {
                parent[x] = parent[parent[x]]
                x = parent[x]
            }
            return x
        }

        func union(_ a: Int, _ b: Int) {
            let ra = find(a)
            let rb = find(b)
            if ra != rb { parent[ra] = rb }
        }

        for i in 0..<n {
            let a = frames[i]
            if a.isEmpty || a.isNull { continue }
            for j in (i + 1)..<n {
                let b = frames[j]
                if b.isEmpty || b.isNull { continue }
                let inter = a.intersection(b)
                if !inter.isNull && !inter.isEmpty {
                    union(i, j)
                }
            }
        }

        var buckets: [Int: [Int]] = [:]
        for i in 0..<n {
            buckets[find(i), default: []].append(i)
        }

        return buckets.values
            .filter { $0.count > 1 }
            .map { Group(memberIndices: $0.sorted()) }
            .sorted { ($0.memberIndices.first ?? 0) < ($1.memberIndices.first ?? 0) }
    }

    /// For a group of size `size` and a rotation step `step`, return the
    /// member index (0..<size) that should be placed on top.
    ///
    /// `step == 0` returns `0` (original front). Non-negative steps rotate
    /// forward; negative steps wrap modulo size.
    static func topMember(size: Int, step: Int) -> Int {
        guard size > 0 else { return 0 }
        let r = step % size
        return r >= 0 ? r : r + size
    }
}
