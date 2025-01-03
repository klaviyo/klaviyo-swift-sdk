/// Copied verbatim from Swift Issue Reporting v1.3.0 on 11/15/2024
/// https://github.com/pointfreeco/swift-issue-reporting/tree/1.3.0

@rethrows
@usableFromInline
protocol _ErrorMechanism {
  associatedtype Output
  func get() throws -> Output
}
extension _ErrorMechanism {
  func _rethrowError() rethrows -> Never {
    _ = try _rethrowGet()
    fatalError()
  }
  @usableFromInline
  func _rethrowGet() rethrows -> Output {
    return try get()
  }
}
extension Result: _ErrorMechanism {}
