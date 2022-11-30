//
//  Cancellation.swift
//  Cancellation handling pulled from (https://github.com/pointfreeco/swift-composable-architecture).
//
//  Created by Noah Durell on 11/28/22.
//

import Combine
import Foundation

extension EffectPublisher {

    public func cancellable(id: AnyHashable, cancelInFlight: Bool = false) -> Self {
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
        case let .run(operation):
            return Self(
                operation: .run { send in
                    await withTaskCancellation(id: id, cancelInFlight: cancelInFlight) {
                        await operation(send)
                    }
                }
            )
        }
    }
    
    public func cancellable(id: Any.Type, cancelInFlight: Bool = false) -> Self {
        self.cancellable(id: ObjectIdentifier(id), cancelInFlight: cancelInFlight)
    }
    
    /// An effect that will cancel any currently in-flight effect with the given identifier.
    ///
    /// A convenience for calling ``EffectPublisher/cancel(id:)-6hzsl`` with a static type as the
    /// effect's unique identifier.
    ///
    /// - Parameter id: A unique type identifying the effect.
    /// - Returns: A new effect that will cancel any currently in-flight effect with the given
    ///   identifier.
    public static func cancel(id: Any.Type) -> Self {
        .cancel(id: ObjectIdentifier(id))
    }
    
    public static func cancel(id: AnyHashable) -> Self {
        .fireAndForget {
            _cancellablesLock.sync {
                _cancellationCancellables[.init(id: id)]?.forEach { $0.cancel() }
            }
        }
    }
    
    public static func fireAndForget(_ work: @escaping () throws -> Void) -> Self {
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
    
    
}

public func withTaskCancellation<T: Sendable>(
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

public func withTaskCancellation<T: Sendable>(
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
    public static func cancel<ID: Hashable & Sendable>(id: ID) {
        _cancellablesLock.sync { _cancellationCancellables[.init(id: id)]?.forEach { $0.cancel() } }
    }
    
    /// Cancel any currently in-flight operation with the given identifier.
    ///
    /// A convenience for calling `Task.cancel(id:)` with a static type as the operation's unique
    /// identifier.
    ///
    /// - Parameter id: A unique type identifying the operation.
    public static func cancel(id: Any.Type) {
        self.cancel(id: ObjectIdentifier(id))
    }
}

@_spi(Internals) public struct _CancelToken: Hashable {
    let id: AnyHashable
    let discriminator: ObjectIdentifier
    
    public init(id: AnyHashable) {
        self.id = id
        self.discriminator = ObjectIdentifier(type(of: id.base))
    }
}

@_spi(Internals) public var _cancellationCancellables: [_CancelToken: Set<AnyCancellable>] = [:]
@_spi(Internals) public let _cancellablesLock = NSRecursiveLock()

@rethrows
private protocol _ErrorMechanism {
    associatedtype Output
    func get() throws -> Output
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

extension NSRecursiveLock {
    @inlinable @discardableResult
    @_spi(Internals) public func sync<R>(work: () -> R) -> R {
        self.lock()
        defer { self.unlock() }
        return work()
    }
}

extension Task where Failure == Error {
    @_spi(Internals) public var cancellableValue: Success {
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
    public typealias Output = Action
    
    public func receive<S: Combine.Subscriber>(
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
    
    public init<P: Publisher>(_ publisher: P) where P.Output == Output, P.Failure == Failure {
        self.operation = .publisher(publisher.eraseToAnyPublisher())
    }
}

extension Publisher {
    public func eraseToEffect() -> EffectPublisher<Output, Failure> {
        EffectPublisher(self)
    }
}
