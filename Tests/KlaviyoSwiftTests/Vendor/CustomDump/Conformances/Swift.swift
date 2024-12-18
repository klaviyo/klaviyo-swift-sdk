/// Copied verbatim from swift-custom-dump v1.3.2 on 11/15/2024
/// https://github.com/pointfreeco/swift-custom-dump/tree/1.3.2

import Foundation
import KlaviyoSDKDependencies

extension Character: CustomDumpRepresentable {
  public var customDumpValue: Any {
    String(self)
  }
}

#if os(iOS) || os(macOS) || os(tvOS) || os(watchOS)
  @available(macOS 13, iOS 16, watchOS 9, tvOS 16, *)
  extension Duration: CustomDumpStringConvertible {
    public var customDumpDescription: String {
      self.formatted(
        .units(
          allowed: [.days, .hours, .minutes, .seconds, .milliseconds, .microseconds, .nanoseconds],
          width: .wide
        )
      )
    }
  }
#endif

extension ObjectIdentifier: CustomDumpStringConvertible {
  public var customDumpDescription: String {
    self.debugDescription
      .replacingOccurrences(of: "0x0*", with: "0x", options: .regularExpression)
  }
}

extension StaticString: CustomDumpRepresentable {
  public var customDumpValue: Any {
    "\(self)"
  }
}

extension UnicodeScalar: CustomDumpRepresentable {
  public var customDumpValue: Any {
    String(self)
  }
}

extension AnyHashable: CustomDumpRepresentable {
  public var customDumpValue: Any {
    base
  }
}
