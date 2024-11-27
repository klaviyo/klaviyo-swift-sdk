/// Adapted from Swift Issue Reporting v1.3.0 on 11/15/2024
/// https://github.com/pointfreeco/swift-issue-reporting/tree/1.3.0
/// Comments - Modified to avoid collision

@propertyWrapper
@usableFromInline
struct IssueReportingUncheckedSendable<Value>: @unchecked Sendable {
  @usableFromInline
  var wrappedValue: Value
  init(wrappedValue value: Value) {
    self.wrappedValue = value
  }
}
