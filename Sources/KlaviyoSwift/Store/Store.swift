//
//  Store.swift
//  Simplified store implementation inspired by TCA (https://github.com/pointfreeco/swift-composable-architecture).
//
//  Created by Noah Durell on 11/28/22.
//

import Foundation
import Combine

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

extension AsyncStream {
    static var never: Self {
        Self { _ in }
    }
}

final class Store {
    init(state: KlaviyoState,
         reducer: @escaping (inout KlaviyoState, KlaviyoAction) -> EffectTask<KlaviyoAction>) {
        self.reducer = reducer
        self.state = CurrentValueSubject(state)
    }
    private var bufferedActions: [KlaviyoAction] = []
    var effectCancellables: [UUID: AnyCancellable] = [:]
    private var isSending = false
    var parentCancellable: AnyCancellable?
    private let reducer: (inout KlaviyoState, KlaviyoAction) -> EffectTask<KlaviyoAction>
    var state: CurrentValueSubject<KlaviyoState, Never>
    
    public func send(
      _ action: KlaviyoAction,
      originatingFrom originatingAction: KlaviyoAction? = nil
    ) -> Task<Void, Never>? {
      self.bufferedActions.append(action)
      guard !self.isSending else { return nil }

      self.isSending = true
      var currentState = self.state.value
      let tasks = Box<[Task<Void, Never>]>(wrappedValue: [])
      defer {
        withExtendedLifetime(self.bufferedActions) {
          self.bufferedActions.removeAll()
        }
        self.state.value = currentState
        self.isSending = false
        if !self.bufferedActions.isEmpty {
          if let task = self.send(
            self.bufferedActions.removeLast(), originatingFrom: originatingAction
          ) {
            tasks.wrappedValue.append(task)
          }
        }
      }

      var index = self.bufferedActions.startIndex
      while index < self.bufferedActions.endIndex {
        defer { index += 1 }
        let action = self.bufferedActions[index]
        let effect = self.reducer(&currentState, action)

        switch effect.operation {
        case .none:
          break
        case let .publisher(publisher):
          var didComplete = false
          let boxedTask = Box<Task<Void, Never>?>(wrappedValue: nil)
          let uuid = UUID()
          let effectCancellable =
            publisher
            .handleEvents(
              receiveCancel: { [weak self] in
                //self?.threadCheck(status: .effectCompletion(action))
                self?.effectCancellables[uuid] = nil
              }
            )
            .sink(
              receiveCompletion: { [weak self] _ in
                //self?.threadCheck(status: .effectCompletion(action))
                boxedTask.wrappedValue?.cancel()
                didComplete = true
                self?.effectCancellables[uuid] = nil
              },
              receiveValue: { [weak self] effectAction in
                guard let self = self else { return }
                if let task = self.send(effectAction, originatingFrom: action) {
                  tasks.wrappedValue.append(task)
                }
              }
            )

          if !didComplete {
            let task = Task<Void, Never> { @MainActor in
              for await _ in AsyncStream<Void>.never {}
              effectCancellable.cancel()
            }
            boxedTask.wrappedValue = task
            tasks.wrappedValue.append(task)
            self.effectCancellables[uuid] = effectCancellable
          }
        case let .run(operation):
          tasks.wrappedValue.append(
            Task(priority: .background) {
              await operation(
                Send {
                  if let task = self.send($0, originatingFrom: action) {
                    tasks.wrappedValue.append(task)
                  }
                }
              )
            }
          )
        }
      }

      guard !tasks.wrappedValue.isEmpty else { return nil }
      return Task(priority: .background) {
        await withTaskCancellationHandler {
          var index = tasks.wrappedValue.startIndex
          while index < tasks.wrappedValue.endIndex {
            defer { index += 1 }
            await tasks.wrappedValue[index].value
          }
        } onCancel: {
          var index = tasks.wrappedValue.startIndex
          while index < tasks.wrappedValue.endIndex {
            defer { index += 1 }
            tasks.wrappedValue[index].cancel()
          }
        }
      }
    }
}
