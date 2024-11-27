/// Copied verbatim from swift-case-paths v1.3.2 on 11/15/2024
/// https://github.com/pointfreeco/swift-custom-dump/tree/1.3.2

extension CollectionDifference.Change {
  var offset: Int {
    switch self {
    case let .insert(offset, _, _), let .remove(offset, _, _):
      return offset
    }
  }
}
