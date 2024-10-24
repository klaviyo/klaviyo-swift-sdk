import Combine

extension Effect {
  /// Creates an effect from a Combine publisher.
  ///
  /// - Parameter createPublisher: The closure to execute when the effect is performed.
  /// - Returns: An effect wrapping a Combine publisher.
  static func publisher(_ createPublisher: () -> some Publisher<Action, Never>) -> Self {
    Self(operation: .publisher(createPublisher().eraseToAnyPublisher()))
  }
}

struct _EffectPublisher<Action>: Publisher {
  typealias Output = Action
  typealias Failure = Never

  let effect: Effect<Action>

  init(_ effect: Effect<Action>) {
    self.effect = effect
  }

  func receive(subscriber: some Combine.Subscriber<Action, Failure>) {
    publisher.subscribe(subscriber)
  }

  private var publisher: AnyPublisher<Action, Failure> {
    switch effect.operation {
    case .none:
      return Empty().eraseToAnyPublisher()
    case let .publisher(publisher):
      return publisher
    case let .run(priority, operation):
      return .create { subscriber in
        let task = Task(priority: priority) { @MainActor in
          defer { subscriber.send(completion: .finished) }
          await operation(Send { subscriber.send($0) })
        }
        return AnyCancellable {
          task.cancel()
        }
      }
    }
  }
}
