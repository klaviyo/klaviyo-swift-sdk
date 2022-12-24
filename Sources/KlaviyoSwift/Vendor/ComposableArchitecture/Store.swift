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
//  Store.swift
//  Pulled from https://github.com/pointfreeco/swift-composable-architecture/blob/main/Sources/ComposableArchitecture/ReducerProtocol.swift
//  with minimal modifications (scoping, dependencies and reducer protocol removed).
//
//  Created by Noah Durell on 12/6/22.
//
import Combine
import Foundation

/// A store represents the runtime that powers the application. It is the object that you will pass
/// around to views that need to interact with the application.
///
/// You will typically construct a single one of these at the root of your application:
///
/// ```swift
/// @main
/// struct MyApp: App {
///   var body: some Scene {
///     WindowGroup {
///       RootView(
///         store: Store(
///           initialState: AppReducer.State(),
///           reducer: AppReducer()
///         )
///       )
///     }
///   }
/// }
/// ```
///
/// …and then use the ``scope(state:action:)`` method to derive more focused stores that can be
/// passed to subviews.
///
/// ### Scoping
///
/// The most important operation defined on ``Store`` is the ``scope(state:action:)`` method, which
/// allows you to transform a store into one that deals with child state and actions. This is
/// necessary for passing stores to subviews that only care about a small portion of the entire
/// application's domain.
///
/// For example, if an application has a tab view at its root with tabs for activity, search, and
/// profile, then we can model the domain like this:
///
/// ```swift
/// struct State {
///   var activity: Activity.State
///   var profile: Profile.State
///   var search: Search.State
/// }
///
/// enum Action {
///   case activity(Activity.Action)
///   case profile(Profile.Action)
///   case search(Search.Action)
/// }
/// ```
///
/// We can construct a view for each of these domains by applying ``scope(state:action:)`` to a
/// store that holds onto the full app domain in order to transform it into a store for each
/// sub-domain:
///
/// ```swift
/// struct AppView: View {
///   let store: StoreOf<AppReducer>
///
///   var body: some View {
///     TabView {
///       ActivityView(store: self.store.scope(state: \.activity, action: App.Action.activity))
///         .tabItem { Text("Activity") }
///
///       SearchView(store: self.store.scope(state: \.search, action: App.Action.search))
///         .tabItem { Text("Search") }
///
///       ProfileView(store: self.store.scope(state: \.profile, action: App.Action.profile))
///         .tabItem { Text("Profile") }
///     }
///   }
/// }
/// ```
///
/// ### Thread safety
///
/// The `Store` class is not thread-safe, and so all interactions with an instance of ``Store``
/// (including all of its scopes and derived ``ViewStore``s) must be done on the same thread the
/// store was created on. Further, if the store is powering a SwiftUI or UIKit view, as is
/// customary, then all interactions must be done on the _main_ thread.
///
/// The reason stores are not thread-safe is due to the fact that when an action is sent to a store,
/// a reducer is run on the current state, and this process cannot be done from multiple threads.
/// It is possible to make this process thread-safe by introducing locks or queues, but this
/// introduces new complications:
///
///   * If done simply with `DispatchQueue.main.async` you will incur a thread hop even when you are
///     already on the main thread. This can lead to unexpected behavior in UIKit and SwiftUI, where
///     sometimes you are required to do work synchronously, such as in animation blocks.
///
///   * It is possible to create a scheduler that performs its work immediately when on the main
///     thread and otherwise uses `DispatchQueue.main.async` (_e.g._, see Combine Schedulers'
///     [UIScheduler][uischeduler]).
///
/// This introduces a lot more complexity, and should probably not be adopted without having a very
/// good reason.
///
/// This is why we require all actions be sent from the same thread. This requirement is in the same
/// spirit of how `URLSession` and other Apple APIs are designed. Those APIs tend to deliver their
/// outputs on whatever thread is most convenient for them, and then it is your responsibility to
/// dispatch back to the main queue if that's what you need. The Composable Architecture makes you
/// responsible for making sure to send actions on the main thread. If you are using an effect that
/// may deliver its output on a non-main thread, you must explicitly perform `.receive(on:)` in
/// order to force it back on the main thread.
///
/// This approach makes the fewest number of assumptions about how effects are created and
/// transformed, and prevents unnecessary thread hops and re-dispatching. It also provides some
/// testing benefits. If your effects are not responsible for their own scheduling, then in tests
/// all of the effects would run synchronously and immediately. You would not be able to test how
/// multiple in-flight effects interleave with each other and affect the state of your application.
/// However, by leaving scheduling out of the ``Store`` we get to test these aspects of our effects
/// if we so desire, or we can ignore if we prefer. We have that flexibility.
///
/// [uischeduler]: https://github.com/pointfreeco/combine-schedulers/blob/main/Sources/CombineSchedulers/UIScheduler.swift
///
/// #### Thread safety checks
///
/// The store performs some basic thread safety checks in order to help catch mistakes. Stores
/// constructed via the initializer ``init(initialState:reducer:)`` are assumed to run
/// only on the main thread, and so a check is executed immediately to make sure that is the case.
/// Further, all actions sent to the store and all scopes (see ``scope(state:action:)``) of the
/// store are also checked to make sure that work is performed on the main thread.
final class Store<State, Action> {
  private var bufferedActions: [Action] = []
  var effectCancellables: [UUID: AnyCancellable] = [:]
  private var isSending = false
  var parentCancellable: AnyCancellable?
#if swift(>=5.7)
  private let reducer: any ReducerProtocol<State, Action>
#else
  private let reducer: (inout State, Action) -> EffectTask<Action>
#endif
  var state: CurrentValueSubject<State, Never>
  #if DEBUG
    private let mainThreadChecksEnabled: Bool
  #endif

  /// Initializes a store from an initial state and a reducer.
  ///
  /// - Parameters:
  ///   - initialState: The state to start the application in.
  ///   - reducer: The reducer that powers the business logic of the application.
  convenience init<R: ReducerProtocol>(
    initialState: R.State,
    reducer: R
  ) where R.State == State, R.Action == Action {
    self.init(
      initialState: initialState,
      reducer: reducer,
      mainThreadChecksEnabled: true
    )
  }

  func send(
    _ action: Action,
    originatingFrom originatingAction: Action? = nil
  ) -> Task<Void, Never>? {
    self.threadCheck(status: .send(action, originatingAction: originatingAction))

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
    #if swift(>=5.7)
        let effect = self.reducer.reduce(into: &currentState, action: action)
      #else
        let effect = self.reducer(&currentState, action)
      #endif

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
              self?.threadCheck(status: .effectCompletion(action))
              self?.effectCancellables[uuid] = nil
            }
          )
          .sink(
            receiveCompletion: { [weak self] _ in
              self?.threadCheck(status: .effectCompletion(action))
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
      case let .run(priority, operation):
        tasks.wrappedValue.append(
          Task(priority: priority) {
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
    return Task {
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

  private enum ThreadCheckStatus {
    case effectCompletion(Action)
    case `init`
    case scope
    case send(Action, originatingAction: Action?)
  }

  @inline(__always)
  private func threadCheck(status: ThreadCheckStatus) {
    #if DEBUG
      guard self.mainThreadChecksEnabled && !Thread.isMainThread
      else { return }

      switch status {
      case let .effectCompletion(action):
        runtimeWarn(
          """
          An effect completed on a non-main thread. …

            Effect returned from:
              \(debugCaseOutput(action))

          Make sure to use ".receive(on:)" on any effects that execute on background threads to \
          receive their output on the main thread.

          The "Store" class is not thread-safe, and so all interactions with an instance of \
          "Store" (including all of its scopes and derived view stores) must be done on the main \
          thread.
          """
        )

      case .`init`:
        runtimeWarn(
          """
          A store initialized on a non-main thread. …

          The "Store" class is not thread-safe, and so all interactions with an instance of \
          "Store" (including all of its scopes and derived view stores) must be done on the main \
          thread.
          """
        )

      case .scope:
        runtimeWarn(
          """
          "Store.scope" was called on a non-main thread. …

          The "Store" class is not thread-safe, and so all interactions with an instance of \
          "Store" (including all of its scopes and derived view stores) must be done on the main \
          thread.
          """
        )

      case let .send(action, originatingAction: nil):
        runtimeWarn(
          """
          "ViewStore.send" was called on a non-main thread with: \(debugCaseOutput(action)) …

          The "Store" class is not thread-safe, and so all interactions with an instance of \
          "Store" (including all of its scopes and derived view stores) must be done on the main \
          thread.
          """
        )

      case let .send(action, originatingAction: .some(originatingAction)):
        runtimeWarn(
          """
          An effect published an action on a non-main thread. …

            Effect published:
              \(debugCaseOutput(action))

            Effect returned from:
              \(debugCaseOutput(originatingAction))

          Make sure to use ".receive(on:)" on any effects that execute on background threads to \
          receive their output on the main thread.

          The "Store" class is not thread-safe, and so all interactions with an instance of \
          "Store" (including all of its scopes and derived view stores) must be done on the main \
          thread.
          """
        )
      }
    #endif
  }

    init<R: ReducerProtocol>(
      initialState: R.State,
      reducer: R,
      mainThreadChecksEnabled: Bool
    ) where R.State == State, R.Action == Action {
      self.state = CurrentValueSubject(initialState)
      #if swift(>=5.7)
        self.reducer = reducer
      #else
        self.reducer = reducer.reduce
      #endif
      #if DEBUG
        self.mainThreadChecksEnabled = mainThreadChecksEnabled
      #endif
      self.threadCheck(status: .`init`)
    }
}

/// A convenience type alias for referring to a store of a given reducer's domain.
///
/// Instead of specifying two generics:
///
/// ```swift
/// let store: Store<Feature.State, Feature.Action>
/// ```
///
/// You can specify a single generic:
///
/// ```swift
/// let store: StoreOf<Feature>
/// ```
typealias StoreOf<R: ReducerProtocol> = Store<R.State, R.Action>
