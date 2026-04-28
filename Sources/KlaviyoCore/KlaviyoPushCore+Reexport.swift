//
//  KlaviyoPushCore+Reexport.swift
//
// Re-exports KlaviyoPushCore symbols so consumers of KlaviyoCore (e.g. KlaviyoSwift)
// don't need to explicitly import KlaviyoPushCore.
//
// Note: @_exported is a non-public Swift compiler directive but is widely used
// in Apple's own frameworks and the broader Swift ecosystem for this purpose.

@_exported import KlaviyoPushCore
