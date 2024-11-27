/// Copied verbatim from swift-concurrency-extras v1.2.0 on 11/15/2024
/// https://github.com/pointfreeco/swift-concurrency-extras/tree/1.2.0

extension Result where Failure == Swift.Error {
  /// Creates a new result by evaluating an async throwing closure, capturing the returned value as
  /// a success, or any thrown error as a failure.
  ///
  /// - Parameter body: A throwing closure to evaluate.
  @_transparent
  public init(catching body: () async throws -> Success) async {
    do {
      self = .success(try await body())
    } catch {
      self = .failure(error)
    }
  }
}
