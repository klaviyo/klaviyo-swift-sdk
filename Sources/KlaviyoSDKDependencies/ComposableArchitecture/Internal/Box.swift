/// Copied verbatim from TCA v1.16.1 on 11/15/2024
/// https://github.com/pointfreeco/swift-composable-architecture/tree/1.16.1

final class Box<Wrapped> {
  var wrappedValue: Wrapped

  init(wrappedValue: Wrapped) {
    self.wrappedValue = wrappedValue
  }

  var boxedValue: Wrapped {
    _read { yield self.wrappedValue }
    _modify { yield &self.wrappedValue }
  }
}
