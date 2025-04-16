/// Copied verbatim from TCA v1.16.1 on 11/15/2024
/// https://github.com/pointfreeco/swift-composable-architecture/tree/1.16.1


/// A reducer that does nothing.
///
/// While not very useful on its own, `EmptyReducer` can be used as a placeholder in APIs that hold
/// reducers.
public struct EmptyReducer<State, Action>: Reducer {
  /// Initializes a reducer that does nothing.
  @inlinable
  public init() {
    self.init(internal: ())
  }

  @usableFromInline
  init(internal: Void) {}

  @inlinable
  public func reduce(into _: inout State, action _: Action) -> Effect<Action> {
    .none
  }
}
