/// Copied verbatim from swift-case-paths v1.3.2 on 11/15/2024
/// https://github.com/pointfreeco/swift-custom-dump/tree/1.3.2

func isIdentityEqual(_ lhs: Any, _ rhs: Any) -> Bool {
  guard let lhs = lhs as? any Identifiable else { return false }
  func open<LHS: Identifiable>(_ lhs: LHS) -> Bool {
    guard let rhs = rhs as? LHS else { return false }
    return lhs.id == rhs.id
  }
  return open(lhs)
}
