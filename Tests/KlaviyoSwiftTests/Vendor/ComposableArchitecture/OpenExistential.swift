/// Copied verbatim from TCA v1.16.1 on 11/14/2024
/// https://github.com/pointfreeco/swift-composable-architecture/tree/1.16.1

// MARK: Equatable

func _isEqual(_ lhs: Any, _ rhs: Any) -> Bool? {
  (lhs as? any Equatable)?.isEqual(other: rhs)
}

extension Equatable {
  fileprivate func isEqual(other: Any) -> Bool {
    self == other as? Self
  }
}

// MARK: Identifiable

func _identifiableID(_ value: Any) -> AnyHashable? {
  func open(_ value: some Identifiable) -> AnyHashable {
    value.id
  }
  guard let value = value as? any Identifiable else { return nil }
  return open(value)
}
