/// Copied verbatim from swift-concurrency-extras v1.2.0 on 11/15/2024
/// https://github.com/pointfreeco/swift-concurrency-extras/tree/1.2.0

final class UncheckedBox<Value>: @unchecked Sendable {
  var wrappedValue: Value
  init(wrappedValue: Value) {
    self.wrappedValue = wrappedValue
  }
}
