//
//  Effect.swift
//  
//
//  Created by Noah Durell on 11/28/22.
//

import Combine
import Foundation
import SwiftUI

public struct EffectPublisher<Action, Failure: Error> {
  @usableFromInline
  enum Operation {
    case none
    case publisher(AnyPublisher<Action, Failure>)
    case run(@Sendable (Send<Action>) async -> Void)
  }

  @usableFromInline
  let operation: Operation

  @usableFromInline
  init(operation: Operation) {
    self.operation = operation
  }
}

// MARK: - Creating Effects

extension EffectPublisher {
  /// An effect that does nothing and completes immediately. Useful for situations where you must
  /// return an effect, but you don't need to do anything.
  @inlinable
  public static var none: Self {
    Self(operation: .none)
  }
}

public typealias EffectTask<Action> = EffectPublisher<Action, Never>

extension EffectPublisher where Failure == Never {
 
  public static func task(
    operation: @escaping @Sendable () async throws -> Action,
    catch handler: (@Sendable (Error) async -> Action)? = nil,
    file: StaticString = #file,
    fileID: StaticString = #fileID,
    line: UInt = #line
  ) -> Self {
    return Self(
      operation: .run { send in
          do {
            try await send(operation())
          } catch is CancellationError {
            return
          } catch {
            guard let handler = handler else {
              #if DEBUG
//                var errorDump = ""
//                customDump(error, to: &errorDump, indent: 4)
//                runtimeWarn(
//                  """
//                  An "EffectTask.task" returned from "\(fileID):\(line)" threw an unhandled error. …
//
//                  \(errorDump)
//
//                  All non-cancellation errors must be explicitly handled via the "catch" parameter \
//                  on "EffectTask.task", or via a "do" block.
//                  """,
//                  file: file,
//                  line: line
//                )
              #endif
              return
            }
            await send(handler(error))
          }
        }
    )
  }


  public static func run(
    operation: @escaping @Sendable (Send<Action>) async throws -> Void,
    catch handler: (@Sendable (Error, Send<Action>) async -> Void)? = nil,
    file: StaticString = #file,
    fileID: StaticString = #fileID,
    line: UInt = #line
  ) -> Self {
    return Self(
      operation: .run { send in
          do {
            try await operation(send)
          } catch is CancellationError {
            return
          } catch {
            guard let handler = handler else {
              #if DEBUG
//                var errorDump = ""
//                customDump(error, to: &errorDump, indent: 4)
//                runtimeWarn(
//                  """
//                  An "EffectTask.run" returned from "\(fileID):\(line)" threw an unhandled error. …
//
//                  \(errorDump)
//
//                  All non-cancellation errors must be explicitly handled via the "catch" parameter \
//                  on "EffectTask.run", or via a "do" block.
//                  """,
//                  file: file,
//                  line: line
//                )
              #endif
              return
            }
            await handler(error, send)
          }
        }
    )
  }
    
    public static func fireAndForget(
      priority: TaskPriority? = nil,
      _ work: @escaping @Sendable () async throws -> Void
    ) -> Self {
      Self.run { _ in try? await work() }
    }
}

@MainActor
public struct Send<Action> {
  public let send: @MainActor (Action) -> Void

  public init(send: @escaping @MainActor (Action) -> Void) {
    self.send = send
  }

  /// Sends an action back into the system from an effect.
  ///
  /// - Parameter action: An action.
  public func callAsFunction(_ action: Action) {
    guard !Task.isCancelled else { return }
    self.send(action)
  }

  /// Sends an action back into the system from an effect with animation.
  ///
  /// - Parameters:
  ///   - action: An action.
  ///   - animation: An animation.
  public func callAsFunction(_ action: Action, animation: Animation?) {
    guard !Task.isCancelled else { return }
    withAnimation(animation) {
      self(action)
    }
  }
}

// MARK: - Composing Effects

extension EffectPublisher {

  /// Transforms all elements from the upstream effect with a provided closure.
  ///
  /// - Parameter transform: A closure that transforms the upstream effect's action to a new action.
  /// - Returns: A publisher that uses the provided closure to map elements from the upstream effect
  ///   to new elements that it then publishes.
  @inlinable
  public func map<T>(_ transform: @escaping (Action) -> T) -> EffectPublisher<T, Failure> {
    switch self.operation {
    case .none:
      return .none
    case let .publisher(publisher):
      let transform = { action in
          transform(action)
      }
      return .init(operation: .publisher(publisher.map(transform).eraseToAnyPublisher()))
    case let .run(operation):
      return .init(
        operation: .run { send in
          await operation(
            Send { action in
              send(transform(action))
            }
          )
        }
      )
    }
  }
}
