/// Adapted from TCA v1.16.1 on 11/15/2024
/// https://github.com/pointfreeco/swift-composable-architecture/tree/1.16.1
/// Comments - removed import statement for CustomDump

import Foundation

extension String {
  @usableFromInline
  func indent(by indent: Int) -> String {
    let indentation = String(repeating: " ", count: indent)
    return indentation + self.replacingOccurrences(of: "\n", with: "\n\(indentation)")
  }
}
