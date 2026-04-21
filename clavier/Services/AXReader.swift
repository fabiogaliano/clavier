//
//  AXReader.swift
//  clavier
//
//  Typed boundary for reading AX attributes and decoding AXValue-wrapped geometry.
//
//  All AX attribute reads that require type-unsafe CFTypeRef casts are funneled
//  through this module so that (a) force-cast syntax never appears in caller code
//  and (b) decode failures are returned as structured values instead of crashing.
//

import AppKit

/// Errors that can arise when reading AX attributes.
enum AXReadError: Error {
    case attributeUnavailable
    case unexpectedType
}

/// Typed accessors for AX element attributes.
///
/// Every method returns a `Result` so callers can decide how to handle missing
/// or mistyped values without resorting to force casts.
enum AXReader {

    // MARK: - Scalar attributes

    /// Read a `String`-typed AX attribute.
    static func string(_ attribute: CFString, of element: AXUIElement) -> Result<String, AXReadError> {
        var ref: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute, &ref) == .success else {
            return .failure(.attributeUnavailable)
        }
        guard let value = ref as? String else {
            return .failure(.unexpectedType)
        }
        return .success(value)
    }

    /// Read a `Bool`-typed AX attribute.
    static func bool(_ attribute: CFString, of element: AXUIElement) -> Result<Bool, AXReadError> {
        var ref: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute, &ref) == .success else {
            return .failure(.attributeUnavailable)
        }
        guard let value = ref as? Bool else {
            return .failure(.unexpectedType)
        }
        return .success(value)
    }

    // MARK: - AXUIElement attributes

    /// Read an `AXUIElement`-typed AX attribute.
    ///
    /// `CFTypeRef` to `AXUIElement` casts cannot use the `as?` conditional form
    /// because `AXUIElement` is a non-class CF type; the runtime always succeeds
    /// (or crashes) with `as!`.  This method validates the `CFTypeID` first so
    /// the eventual cast is provably safe.
    static func element(_ attribute: CFString, of parent: AXUIElement) -> Result<AXUIElement, AXReadError> {
        var ref: CFTypeRef?
        guard AXUIElementCopyAttributeValue(parent, attribute, &ref) == .success, let ref else {
            return .failure(.attributeUnavailable)
        }
        guard CFGetTypeID(ref) == AXUIElementGetTypeID() else {
            return .failure(.unexpectedType)
        }
        // Safe: type-ID check above guarantees the underlying type.
        return .success(ref as! AXUIElement)
    }

    /// Read an array of `AXUIElement` children via a given attribute.
    static func elements(_ attribute: CFString, of parent: AXUIElement) -> Result<[AXUIElement], AXReadError> {
        var ref: CFTypeRef?
        guard AXUIElementCopyAttributeValue(parent, attribute, &ref) == .success else {
            return .failure(.attributeUnavailable)
        }
        guard let array = ref as? [AXUIElement] else {
            return .failure(.unexpectedType)
        }
        return .success(array)
    }

    // MARK: - AXValue geometry attributes

    /// Read a `CGPoint`-typed AX attribute (wrapped in `AXValue`).
    static func cgPoint(_ attribute: CFString, of element: AXUIElement) -> Result<CGPoint, AXReadError> {
        var ref: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute, &ref) == .success, let ref else {
            return .failure(.attributeUnavailable)
        }
        guard CFGetTypeID(ref) == AXValueGetTypeID() else {
            return .failure(.unexpectedType)
        }
        var point = CGPoint.zero
        // Safe: type-ID check above guarantees this is an AXValue.
        AXValueGetValue(ref as! AXValue, .cgPoint, &point)
        return .success(point)
    }

    /// Read a `CGSize`-typed AX attribute (wrapped in `AXValue`).
    static func cgSize(_ attribute: CFString, of element: AXUIElement) -> Result<CGSize, AXReadError> {
        var ref: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute, &ref) == .success, let ref else {
            return .failure(.attributeUnavailable)
        }
        guard CFGetTypeID(ref) == AXValueGetTypeID() else {
            return .failure(.unexpectedType)
        }
        var size = CGSize.zero
        // Safe: type-ID check above guarantees this is an AXValue.
        AXValueGetValue(ref as! AXValue, .cgSize, &size)
        return .success(size)
    }

    // MARK: - Compound geometry

    /// Read both `kAXPositionAttribute` and `kAXSizeAttribute` and return the
    /// element's frame in AX coordinates (top-left origin, y downward).
    ///
    /// Returns `.failure` if either attribute is missing or mis-typed; the
    /// specific error reflects whichever attribute failed first.
    static func axFrame(of element: AXUIElement) -> Result<CGRect, AXReadError> {
        let positionResult = cgPoint(kAXPositionAttribute as CFString, of: element)
        switch positionResult {
        case .failure(let e): return .failure(e)
        case .success(let position):
            let sizeResult = cgSize(kAXSizeAttribute as CFString, of: element)
            switch sizeResult {
            case .failure(let e): return .failure(e)
            case .success(let size):
                return .success(CGRect(origin: position, size: size))
            }
        }
    }

    // MARK: - Batch geometry (multi-attribute IPC optimisation)

    /// Read position and size in a single `AXUIElementCopyMultipleAttributeValues`
    /// call to reduce IPC round-trips.
    ///
    /// Equivalent to calling `axFrame(of:)` but costs one IPC call instead of two.
    static func axFrameBatched(of element: AXUIElement) -> Result<CGRect, AXReadError> {
        let attrs = [kAXPositionAttribute as CFString, kAXSizeAttribute as CFString] as CFArray
        var values: CFArray?
        guard AXUIElementCopyMultipleAttributeValues(element, attrs, [], &values) == .success,
              let array = values as? [Any], array.count == 2 else {
            return .failure(.attributeUnavailable)
        }

        guard let posRef = array[0] as CFTypeRef?,
              CFGetTypeID(posRef) == AXValueGetTypeID() else {
            return .failure(.unexpectedType)
        }
        var position = CGPoint.zero
        AXValueGetValue(posRef as! AXValue, .cgPoint, &position)

        guard let szRef = array[1] as CFTypeRef?,
              CFGetTypeID(szRef) == AXValueGetTypeID() else {
            return .failure(.unexpectedType)
        }
        var size = CGSize.zero
        AXValueGetValue(szRef as! AXValue, .cgSize, &size)

        return .success(CGRect(origin: position, size: size))
    }

    // MARK: - Batch-array element decoders

    /// Decode a `CGPoint` from an element of a `AXUIElementCopyMultipleAttributeValues`
    /// result array.
    ///
    /// Use this when the attribute values have already been fetched in a
    /// multi-attribute batch call to avoid an additional IPC round-trip.
    static func decodeCGPoint(from batchValue: Any?) -> CGPoint? {
        guard let ref = batchValue as CFTypeRef?,
              CFGetTypeID(ref) == AXValueGetTypeID() else {
            return nil
        }
        var point = CGPoint.zero
        // Safe: type-ID check above guarantees this is an AXValue wrapping a CGPoint.
        AXValueGetValue(ref as! AXValue, .cgPoint, &point)
        return point
    }

    /// Decode a `CGSize` from an element of a `AXUIElementCopyMultipleAttributeValues`
    /// result array.
    static func decodeCGSize(from batchValue: Any?) -> CGSize? {
        guard let ref = batchValue as CFTypeRef?,
              CFGetTypeID(ref) == AXValueGetTypeID() else {
            return nil
        }
        var size = CGSize.zero
        // Safe: type-ID check above guarantees this is an AXValue wrapping a CGSize.
        AXValueGetValue(ref as! AXValue, .cgSize, &size)
        return size
    }

    // MARK: - Convenience: AppKit frame

    /// Read the element's AX frame and convert it to AppKit screen coordinates
    /// using `ScreenGeometry.axToAppKit`.
    ///
    /// This is the operation duplicated across `AccessibilityService`,
    /// `ScrollableAreaService`, and `ChromiumDetector`; centralising it ensures
    /// the coordinate flip is applied consistently everywhere.
    static func appKitFrame(of element: AXUIElement) -> Result<CGRect, AXReadError> {
        axFrame(of: element).map { axRect in
            ScreenGeometry.axToAppKit(position: axRect.origin, size: axRect.size)
        }
    }
}
