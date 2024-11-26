//
//  Dictionary+Ext.swift
//  klaviyo-swift-sdk
//
//  Created by Andrew Balmer on 11/26/24.
//

extension [String: Any] {
    /// Returns a type-casted value for the specified key, throwing an error if the key doesn't exist or the type-cast fails.
    /// - Parameter key: the key for which to extract the value.
    /// - Returns: the value for the specified key, type-cast to the inferred type.
    func value<T>(forKey key: String) throws -> T {
        guard let value = self[key] else {
            throw DictionaryError.keyNotFound(key)
        }
        guard let value = value as? T else {
            throw DictionaryError.unableToCastValue(expected: T.self)
        }
        return value
    }
}

enum DictionaryError: Error {
    /// The specified key doesn't exist in the dictionary.
    case keyNotFound(String)

    /// Unable to cast the value to the expected type.
    case unableToCastValue(expected: Any.Type)
}
