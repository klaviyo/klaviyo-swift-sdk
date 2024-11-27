/// Copied verbatim from swift-case-paths v1.5.4 on 11/15/2024
/// https://github.com/pointfreeco/swift-case-paths/tree/1.5.4

func _isEqual(_ lhs: Any, _ rhs: Any) -> Bool? {
  (lhs as? any Equatable)?.isEqual(other: rhs)
}

extension Equatable {
  fileprivate func isEqual(other: Any) -> Bool {
    self == other as? Self
  }
}
