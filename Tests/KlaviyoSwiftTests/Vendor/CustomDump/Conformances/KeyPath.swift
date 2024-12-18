/// Copied verbatim from swift-custom-dump v1.3.2 on 11/15/2024
/// https://github.com/pointfreeco/swift-custom-dump/tree/1.3.2

import Foundation
@testable import KlaviyoSDKDependencies

extension AnyKeyPath: CustomDumpStringConvertible {
  public var customDumpDescription: String {
    if #available(macOS 13.3, iOS 16.4, watchOS 9.4, tvOS 16.4, *) {
      return self.debugDescription
    }
    return """
      \(typeName(Self.self))<\
      \(typeName(Self.rootType, genericsAbbreviated: false)), \
      \(typeName(Self.valueType, genericsAbbreviated: false))>
      """
  }
}
