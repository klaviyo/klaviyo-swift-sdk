/// Adapted from swift-case-paths v1.5.4 on 11/15/2024
/// https://github.com/pointfreeco/swift-case-paths/tree/1.5.4
/// Comments - renamed to avoid collision with other packages.

@propertyWrapper
struct CasePathsUncheckedSendable<Value>: @unchecked Sendable {
  var wrappedValue: Value
  init(wrappedValue value: Value) {
    self.wrappedValue = value
  }
  var projectedValue: Self { self }
}
