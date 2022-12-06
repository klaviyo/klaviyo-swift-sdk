/**
 MIT License

 Copyright (c) 2020 Point-Free, Inc.

 Permission is hereby granted, free of charge, to any person obtaining a copy
 of this software and associated documentation files (the "Software"), to deal
 in the Software without restriction, including without limitation the rights
 to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
 copies of the Software, and to permit persons to whom the Software is
 furnished to do so, subject to the following conditions:

 The above copyright notice and this permission notice shall be included in all
 copies or substantial portions of the Software.

 THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
 IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
 FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
 AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
 LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
 OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
 SOFTWARE.
 */
//
//  Misc.swift
//  Misc items pulled from https://github.com/pointfreeco/swift-composable-architecture to get the store working.
//
//  Created by Noah Durell on 12/6/22.
//
import os

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

@_transparent
@usableFromInline
@inline(__always)
func runtimeWarn(
  _ message: @autoclosure () -> String,
  category: String? = "ComposableArchitecture",
  file: StaticString? = nil,
  line: UInt? = nil
) {
  #if DEBUG
    let message = message()
    let category = category ?? "Runtime Warning"
        os_log(
          .fault,
          dso: dso,
          log: OSLog(subsystem: "com.apple.runtime-issues", category: category),
          "%@",
          message
        )
  #endif
}

#if canImport(os)
  import os

  // NB: Xcode runtime warnings offer a much better experience than traditional assertions and
  //     breakpoints, but Apple provides no means of creating custom runtime warnings ourselves.
  //     To work around this, we hook into SwiftUI's runtime issue delivery mechanism, instead.
  //
  // Feedback filed: https://gist.github.com/stephencelis/a8d06383ed6ccde3e5ef5d1b3ad52bbc
  @usableFromInline
  let dso = { () -> UnsafeMutableRawPointer in
    let count = _dyld_image_count()
    for i in 0..<count {
      if let name = _dyld_get_image_name(i) {
        let swiftString = String(cString: name)
        if swiftString.hasSuffix("/SwiftUI") {
          if let header = _dyld_get_image_header(i) {
            return UnsafeMutableRawPointer(mutating: UnsafeRawPointer(header))
          }
        }
      }
    }
    return UnsafeMutableRawPointer(mutating: #dsohandle)
  }()
#else
  import Foundation

  @usableFromInline
  let formatter: DateFormatter = {
    let formatter = DateFormatter()
    formatter.dateFormat = "yyyy-MM-dd HH:MM:SS.sssZ"
    return formatter
  }()
#endif

#if DEBUG
@usableFromInline
func debugCaseOutput(_ value: Any) -> String {
  func debugCaseOutputHelp(_ value: Any) -> String {
    let mirror = Mirror(reflecting: value)
    switch mirror.displayStyle {
    case .enum:
      guard let child = mirror.children.first else {
        let childOutput = "\(value)"
        return childOutput == "\(type(of: value))" ? "" : ".\(childOutput)"
      }
      let childOutput = debugCaseOutputHelp(child.value)
      return ".\(child.label ?? "")\(childOutput.isEmpty ? "" : "(\(childOutput))")"
    case .tuple:
      return mirror.children.map { label, value in
        let childOutput = debugCaseOutputHelp(value)
        return
          "\(label.map { isUnlabeledArgument($0) ? "_:" : "\($0):" } ?? "")\(childOutput.isEmpty ? "" : " \(childOutput)")"
      }
      .joined(separator: ", ")
    default:
      return ""
    }
  }

  return (value as? CustomDebugStringConvertible)?.debugDescription
    ?? "\(typeName(type(of: value)))\(debugCaseOutputHelp(value))"
}

private func isUnlabeledArgument(_ label: String) -> Bool {
  label.firstIndex(where: { $0 != "." && !$0.isNumber }) == nil
}

@usableFromInline
func typeName(_ type: Any.Type) -> String {
  var name = _typeName(type, qualified: true)
  if let index = name.firstIndex(of: ".") {
    name.removeSubrange(...index)
  }
  let sanitizedName =
    name
    .replacingOccurrences(
      of: #"\(unknown context at \$[[:xdigit:]]+\)\."#,
      with: "",
      options: .regularExpression
    )
  return sanitizedName
}

#endif


// MARK: Concurenncy helper

extension AsyncStream {
    /// An `AsyncStream` that never emits and never completes unless cancelled.
    static var never: Self {
      Self { _ in }
    }
}


// MARK: Cancellation

import Combine
import Foundation

extension EffectPublisher {
  /// Turns an effect into one that is capable of being canceled.
  ///
  /// To turn an effect into a cancellable one you must provide an identifier, which is used in
  /// ``EffectPublisher/cancel(id:)-6hzsl`` to identify which in-flight effect should be canceled.
  /// Any hashable value can be used for the identifier, such as a string, but you can add a bit of
  /// protection against typos by defining a new type for the identifier:
  ///
  /// ```swift
  /// struct LoadUserID {}
  ///
  /// case .reloadButtonTapped:
  ///   // Start a new effect to load the user
  ///   return self.apiClient.loadUser()
  ///     .map(Action.userResponse)
  ///     .cancellable(id: LoadUserID.self, cancelInFlight: true)
  ///
  /// case .cancelButtonTapped:
  ///   // Cancel any in-flight requests to load the user
  ///   return .cancel(id: LoadUserID.self)
  /// ```
  ///
  /// - Parameters:
  ///   - id: The effect's identifier.
  ///   - cancelInFlight: Determines if any in-flight effect with the same identifier should be
  ///     canceled before starting this new one.
  /// - Returns: A new effect that is capable of being canceled by an identifier.
 func cancellable(id: AnyHashable, cancelInFlight: Bool = false) -> Self {
    switch self.operation {
    case .none:
      return .none
    case let .publisher(publisher):
      return Self(
        operation: .publisher(
          Deferred {
            ()
              -> Publishers.HandleEvents<
                Publishers.PrefixUntilOutput<
                  AnyPublisher<Action, Failure>, PassthroughSubject<Void, Never>
                >
              > in
            _cancellablesLock.lock()
            defer { _cancellablesLock.unlock() }

            let id = _CancelToken(id: id)
            if cancelInFlight {
              _cancellationCancellables[id]?.forEach { $0.cancel() }
            }

            let cancellationSubject = PassthroughSubject<Void, Never>()

            var cancellationCancellable: AnyCancellable!
            cancellationCancellable = AnyCancellable {
              _cancellablesLock.sync {
                cancellationSubject.send(())
                cancellationSubject.send(completion: .finished)
                _cancellationCancellables[id]?.remove(cancellationCancellable)
                if _cancellationCancellables[id]?.isEmpty == .some(true) {
                  _cancellationCancellables[id] = nil
                }
              }
            }

            return publisher.prefix(untilOutputFrom: cancellationSubject)
              .handleEvents(
                receiveSubscription: { _ in
                  _ = _cancellablesLock.sync {
                    _cancellationCancellables[id, default: []].insert(
                      cancellationCancellable
                    )
                  }
                },
                receiveCompletion: { _ in cancellationCancellable.cancel() },
                receiveCancel: cancellationCancellable.cancel
              )
          }
          .eraseToAnyPublisher()
        )
      )
    case let .run(priority, operation):
      return Self(
        operation: .run(priority) { send in
          await withTaskCancellation(id: id, cancelInFlight: cancelInFlight) {
            await operation(send)
          }
        }
      )
    }
  }

  /// Turns an effect into one that is capable of being canceled.
  ///
  /// A convenience for calling ``EffectPublisher/cancellable(id:cancelInFlight:)-29q60`` with a
  /// static type as the effect's unique identifier.
  ///
  /// - Parameters:
  ///   - id: A unique type identifying the effect.
  ///   - cancelInFlight: Determines if any in-flight effect with the same identifier should be
  ///     canceled before starting this new one.
  /// - Returns: A new effect that is capable of being canceled by an identifier.
  func cancellable(id: Any.Type, cancelInFlight: Bool = false) -> Self {
    self.cancellable(id: ObjectIdentifier(id), cancelInFlight: cancelInFlight)
  }

  /// An effect that will cancel any currently in-flight effect with the given identifier.
  ///
  /// - Parameter id: An effect identifier.
  /// - Returns: A new effect that will cancel any currently in-flight effect with the given
  ///   identifier.
  static func cancel(id: AnyHashable) -> Self {
    .fireAndForget {
      _cancellablesLock.sync {
        _cancellationCancellables[.init(id: id)]?.forEach { $0.cancel() }
      }
    }
  }
    
    static func fireAndForget(_ work: @escaping () throws -> Void) -> Self {
        // NB: Ideally we'd return a `Deferred` wrapping an `Empty(completeImmediately: true)`, but
        //     due to a bug in iOS 13.2 that publisher will never complete. The bug was fixed in
        //     iOS 13.3, but to remain compatible with iOS 13.2 and higher we need to do a little
        //     trickery to make sure the deferred publisher completes.
        return Deferred { () -> Publishers.CompactMap<Result<Action?, Failure>.Publisher, Action> in
            try? work()
            return Just<Output?>(nil)
                .setFailureType(to: Failure.self)
                .compactMap { $0 }
        }
        .eraseToEffect()
    }

  /// An effect that will cancel any currently in-flight effect with the given identifier.
  ///
  /// A convenience for calling ``EffectPublisher/cancel(id:)-6hzsl`` with a static type as the
  /// effect's unique identifier.
  ///
  /// - Parameter id: A unique type identifying the effect.
  /// - Returns: A new effect that will cancel any currently in-flight effect with the given
  ///   identifier.
  static func cancel(id: Any.Type) -> Self {
    .cancel(id: ObjectIdentifier(id))
  }

  /// An effect that will cancel multiple currently in-flight effects with the given identifiers.
  ///
  /// - Parameter ids: An array of effect identifiers.
  /// - Returns: A new effect that will cancel any currently in-flight effects with the given
  ///   identifiers.
  static func cancel(ids: [AnyHashable]) -> Self {
    .merge(ids.map(EffectPublisher.cancel(id:)))
  }

  /// An effect that will cancel multiple currently in-flight effects with the given identifiers.
  ///
  /// A convenience for calling ``EffectPublisher/cancel(ids:)-1cqqx`` with a static type as the
  /// effect's unique identifier.
  ///
  /// - Parameter ids: An array of unique types identifying the effects.
  /// - Returns: A new effect that will cancel any currently in-flight effects with the given
  ///   identifiers.
  static func cancel(ids: [Any.Type]) -> Self {
    .merge(ids.map(EffectPublisher.cancel(id:)))
  }
}

/// Execute an operation with a cancellation identifier.
///
/// If the operation is in-flight when `Task.cancel(id:)` is called with the same identifier, or
/// operation will be cancelled.
///
/// ```
/// enum CancelID.self {}
///
/// await withTaskCancellation(id: CancelID.self) {
///   // ...
/// }
/// ```
///
/// ### Debouncing tasks
///
/// When paired with a clock, this function can be used to debounce a unit of async work by
/// specifying the `cancelInFlight`, which will automatically cancel any in-flight work with the
/// same identifier:
///
/// ```swift
/// @Dependency(\.continuousClock) var clock
/// enum CancelID {}
///
/// // ...
///
/// return .task {
///   await withTaskCancellation(id: CancelID.self, cancelInFlight: true) {
///     try await self.clock.sleep(for: .seconds(0.3))
///     return await .debouncedResponse(
///       TaskResult { try await environment.request() }
///     )
///   }
/// }
/// ```
///
/// - Parameters:
///   - id: A unique identifier for the operation.
///   - cancelInFlight: Determines if any in-flight operation with the same identifier should be
///     canceled before starting this new one.
///   - operation: An async operation.
/// - Throws: An error thrown by the operation.
/// - Returns: A value produced by operation.
func withTaskCancellation<T: Sendable>(
  id: AnyHashable,
  cancelInFlight: Bool = false,
  operation: @Sendable @escaping () async throws -> T
) async rethrows -> T {
  let id = _CancelToken(id: id)
  let (cancellable, task) = _cancellablesLock.sync { () -> (AnyCancellable, Task<T, Error>) in
    if cancelInFlight {
      _cancellationCancellables[id]?.forEach { $0.cancel() }
    }
    let task = Task { try await operation() }
    let cancellable = AnyCancellable { task.cancel() }
    _cancellationCancellables[id, default: []].insert(cancellable)
    return (cancellable, task)
  }
  defer {
    _cancellablesLock.sync {
      _cancellationCancellables[id]?.remove(cancellable)
      if _cancellationCancellables[id]?.isEmpty == .some(true) {
        _cancellationCancellables[id] = nil
      }
    }
  }
  do {
    return try await task.cancellableValue
  } catch {
    return try Result<T, Error>.failure(error)._rethrowGet()
  }
}

/// Execute an operation with a cancellation identifier.
///
/// A convenience for calling ``withTaskCancellation(id:cancelInFlight:operation:)-4dtr6`` with a
/// static type as the operation's unique identifier.
///
/// - Parameters:
///   - id: A unique type identifying the operation.
///   - cancelInFlight: Determines if any in-flight operation with the same identifier should be
///     canceled before starting this new one.
///   - operation: An async operation.
/// - Throws: An error thrown by the operation.
/// - Returns: A value produced by operation.
func withTaskCancellation<T: Sendable>(
  id: Any.Type,
  cancelInFlight: Bool = false,
  operation: @Sendable @escaping () async throws -> T
) async rethrows -> T {
  try await withTaskCancellation(
    id: ObjectIdentifier(id),
    cancelInFlight: cancelInFlight,
    operation: operation
  )
}

extension Task where Success == Never, Failure == Never {
  /// Cancel any currently in-flight operation with the given identifier.
  ///
  /// - Parameter id: An identifier.
  static func cancel<ID: Hashable & Sendable>(id: ID) {
    _cancellablesLock.sync { _cancellationCancellables[.init(id: id)]?.forEach { $0.cancel() } }
  }

  /// Cancel any currently in-flight operation with the given identifier.
  ///
  /// A convenience for calling `Task.cancel(id:)` with a static type as the operation's unique
  /// identifier.
  ///
  /// - Parameter id: A unique type identifying the operation.
  static func cancel(id: Any.Type) {
    self.cancel(id: ObjectIdentifier(id))
  }
}

struct _CancelToken: Hashable {
  let id: AnyHashable
  let discriminator: ObjectIdentifier

  init(id: AnyHashable) {
    self.id = id
    self.discriminator = ObjectIdentifier(type(of: id.base))
  }
}

var _cancellationCancellables: [_CancelToken: Set<AnyCancellable>] = [:]
let _cancellablesLock = NSRecursiveLock()

@rethrows
private protocol _ErrorMechanism {
    associatedtype Output
    func get() throws -> Output
}

extension NSRecursiveLock {
  @inlinable @discardableResult
  func sync<R>(work: () -> R) -> R {
    self.lock()
    defer { self.unlock() }
    return work()
  }
}

extension _ErrorMechanism {
    func _rethrowError() rethrows -> Never {
        _ = try _rethrowGet()
        fatalError()
    }

    func _rethrowGet() rethrows -> Output {
        return try get()
    }
}

extension Result: _ErrorMechanism {}

extension Task where Failure == Error {
    var cancellableValue: Success {
        get async throws {
            try await withTaskCancellationHandler {
                try await self.value
            } onCancel: {
                self.cancel()
            }
        }
    }
}

extension Task where Failure == Never {
    @usableFromInline
    var cancellableValue: Success {
        get async {
            await withTaskCancellationHandler {
                await self.value
            } onCancel: {
                self.cancel()
            }
        }
    }
}

extension EffectPublisher: Publisher {
    typealias Output = Action

    func receive<S: Combine.Subscriber>(
        subscriber: S
    ) where S.Input == Action, S.Failure == Failure {
        self.publisher.subscribe(subscriber)
    }

    var publisher: AnyPublisher<Action, Failure> {
        switch self.operation {
        case .none:
            return Empty().eraseToAnyPublisher()
        case let .publisher(publisher):
            return publisher
        case .run:
            return Empty().eraseToAnyPublisher()
        }
    }

    init<P: Publisher>(_ publisher: P) where P.Output == Output, P.Failure == Failure {
        self.operation = .publisher(publisher.eraseToAnyPublisher())
    }
}

extension Publisher {
    func eraseToEffect() -> EffectPublisher<Output, Failure> {
        EffectPublisher(self)
    }
}
