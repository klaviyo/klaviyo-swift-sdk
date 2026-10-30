//
// Vendored from Flight-School/AnyCodable 0.6.7 (https://github.com/Flight-School/AnyCodable,
// archived upstream). Copyright 2018 Read Evaluate Press, LLC. MIT License; see LICENSE in
// this directory. Changes: types renamed with a `Klaviyo` prefix and made `package`-scoped so
// they never clash with an app's own AnyCodable dependency.
//

import Foundation
/**
 A type-erased `Codable` value.

 The `KlaviyoAnyCodable` type forwards encoding and decoding responsibilities
 to an underlying value, hiding its specific underlying type.

 You can encode or decode mixed-type values in dictionaries
 and other collections that require `Encodable` or `Decodable` conformance
 by declaring their contained type to be `KlaviyoAnyCodable`.

 - SeeAlso: `KlaviyoAnyEncodable`
 - SeeAlso: `KlaviyoAnyDecodable`
 */
package struct KlaviyoAnyCodable: Codable {
    package let value: Any

    package init<T>(_ value: T?) {
        self.value = value ?? ()
    }
}

extension KlaviyoAnyCodable: _KlaviyoAnyEncodable, _KlaviyoAnyDecodable {}

extension KlaviyoAnyCodable: Equatable {
    package static func ==(lhs: KlaviyoAnyCodable, rhs: KlaviyoAnyCodable) -> Bool {
        switch (lhs.value, rhs.value) {
        case is (Void, Void):
            return true
        case let (lhs as Bool, rhs as Bool):
            return lhs == rhs
        case let (lhs as Int, rhs as Int):
            return lhs == rhs
        case let (lhs as Int8, rhs as Int8):
            return lhs == rhs
        case let (lhs as Int16, rhs as Int16):
            return lhs == rhs
        case let (lhs as Int32, rhs as Int32):
            return lhs == rhs
        case let (lhs as Int64, rhs as Int64):
            return lhs == rhs
        case let (lhs as UInt, rhs as UInt):
            return lhs == rhs
        case let (lhs as UInt8, rhs as UInt8):
            return lhs == rhs
        case let (lhs as UInt16, rhs as UInt16):
            return lhs == rhs
        case let (lhs as UInt32, rhs as UInt32):
            return lhs == rhs
        case let (lhs as UInt64, rhs as UInt64):
            return lhs == rhs
        case let (lhs as Float, rhs as Float):
            return lhs == rhs
        case let (lhs as Double, rhs as Double):
            return lhs == rhs
        case let (lhs as String, rhs as String):
            return lhs == rhs
        case let (lhs as [String: KlaviyoAnyCodable], rhs as [String: KlaviyoAnyCodable]):
            return lhs == rhs
        case let (lhs as [KlaviyoAnyCodable], rhs as [KlaviyoAnyCodable]):
            return lhs == rhs
        case let (lhs as [String: Any], rhs as [String: Any]):
            return NSDictionary(dictionary: lhs) == NSDictionary(dictionary: rhs)
        case let (lhs as [Any], rhs as [Any]):
            return NSArray(array: lhs) == NSArray(array: rhs)
        case is (NSNull, NSNull):
            return true
        default:
            return false
        }
    }
}

extension KlaviyoAnyCodable: CustomStringConvertible {
    package var description: String {
        switch value {
        case is Void:
            return String(describing: nil as Any?)
        case let value as CustomStringConvertible:
            return value.description
        default:
            return String(describing: value)
        }
    }
}

extension KlaviyoAnyCodable: CustomDebugStringConvertible {
    package var debugDescription: String {
        switch value {
        case let value as CustomDebugStringConvertible:
            return "KlaviyoAnyCodable(\(value.debugDescription))"
        default:
            return "KlaviyoAnyCodable(\(description))"
        }
    }
}

extension KlaviyoAnyCodable: ExpressibleByNilLiteral {}
extension KlaviyoAnyCodable: ExpressibleByBooleanLiteral {}
extension KlaviyoAnyCodable: ExpressibleByIntegerLiteral {}
extension KlaviyoAnyCodable: ExpressibleByFloatLiteral {}
extension KlaviyoAnyCodable: ExpressibleByStringLiteral {}
extension KlaviyoAnyCodable: ExpressibleByStringInterpolation {}
extension KlaviyoAnyCodable: ExpressibleByArrayLiteral {}
extension KlaviyoAnyCodable: ExpressibleByDictionaryLiteral {}

extension KlaviyoAnyCodable: Hashable {
    package func hash(into hasher: inout Hasher) {
        switch value {
        case let value as Bool:
            hasher.combine(value)
        case let value as Int:
            hasher.combine(value)
        case let value as Int8:
            hasher.combine(value)
        case let value as Int16:
            hasher.combine(value)
        case let value as Int32:
            hasher.combine(value)
        case let value as Int64:
            hasher.combine(value)
        case let value as UInt:
            hasher.combine(value)
        case let value as UInt8:
            hasher.combine(value)
        case let value as UInt16:
            hasher.combine(value)
        case let value as UInt32:
            hasher.combine(value)
        case let value as UInt64:
            hasher.combine(value)
        case let value as Float:
            hasher.combine(value)
        case let value as Double:
            hasher.combine(value)
        case let value as String:
            hasher.combine(value)
        case let value as [String: KlaviyoAnyCodable]:
            hasher.combine(value)
        case let value as [KlaviyoAnyCodable]:
            hasher.combine(value)
        default:
            break
        }
    }
}
