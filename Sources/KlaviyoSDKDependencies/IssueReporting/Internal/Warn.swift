/// Copied verbatim from Swift Issue Reporting v1.3.0 on 11/15/2024
/// https://github.com/pointfreeco/swift-issue-reporting/tree/1.3.0

#if os(Linux)
  @preconcurrency import Foundation
#else
  import Foundation
#endif

#if canImport(WinSDK)
  import WinSDK
#endif

@usableFromInline
func printError(_ message: String) {
  fputs("\(message)\n", stderr)
}
