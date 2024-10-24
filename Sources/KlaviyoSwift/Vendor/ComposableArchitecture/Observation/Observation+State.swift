import SwiftUI
import Perception
import CasePaths
import XCTestDynamicOverlay

#if canImport(Observation)
  import Observation
#endif

#if !os(visionOS)
  extension Store: Perceptible {}
#endif

extension Store where State: ObservableState {
  var observableState: State {
    self._$observationRegistrar.access(self, keyPath: \.currentState)
    return self.currentState
  }

  /// Direct access to state in the store when `State` conforms to ``ObservableState``.
  var state: State {
    self.observableState
  }

  subscript<Value>(dynamicMember keyPath: KeyPath<State, Value>) -> Value {
    self.state[keyPath: keyPath]
  }
}

extension Store: Equatable {
    public static nonisolated func == (lhs: Store, rhs: Store) -> Bool {
    lhs === rhs
  }
}

extension Store: Hashable {
    nonisolated public func hash(into hasher: inout Hasher) {
    hasher.combine(ObjectIdentifier(self))
  }
}

extension Store: Identifiable {}

extension Store where State: ObservableState {
  /// Scopes the store to optional child state and actions.
  ///
  /// If your feature holds onto a child feature as an optional:
  ///
  /// ```swift
  /// @Reducer
  /// struct Feature {
  ///   @ObservableState
  ///   struct State {
  ///     var child: Child.State?
  ///     // ...
  ///   }
  ///   enum Action {
  ///     case child(Child.Action)
  ///     // ...
  ///   }
  ///   // ...
  /// }
  /// ```
  ///
  /// …then you can use this `scope` operator in order to transform a store of your feature into
  /// a non-optional store of the child domain:
  ///
  /// ```swift
  /// if let childStore = store.scope(state: \.child, action: \.child) {
  ///   ChildView(store: childStore)
  /// }
  /// ```
  ///
  /// > Important: This operation should only be used from within a SwiftUI view or within
  /// > `withPerceptionTracking` in order for changes of the optional state to be properly
  /// > observed.
  ///
  /// - Parameters:
  ///   - state: A key path to optional child state.
  ///   - action: A case key path to child actions.
  /// - Returns: An optional store of non-optional child state and actions.
  func scope<ChildState, ChildAction>(
    state: KeyPath<State, ChildState?>,
    action: CaseKeyPath<Action, ChildAction>,
    fileID: StaticString = #fileID,
    filePath: StaticString = #filePath,
    line: UInt = #line,
    column: UInt = #column
  ) -> Store<ChildState, ChildAction>? {
    if !self.canCacheChildren {
      reportIssue(
        uncachedStoreWarning(self),
        fileID: fileID,
        filePath: filePath,
        line: line,
        column: column
      )
    }
    guard var childState = self.state[keyPath: state]
    else { return nil }
    return self.scope(
      id: self.id(state: state.appending(path: \.!), action: action),
      state: ToState {
        childState = $0[keyPath: state] ?? childState
        return childState
      },
      action: { action($0) },
      isInvalid: { $0[keyPath: state] == nil }
    )
  }
}

func uncachedStoreWarning<State, Action>(_ store: Store<State, Action>) -> String {
  """
  Scoping from uncached \(store) is not compatible with observation.

  This can happen for one of two reasons:

  • A parent view scopes on a store using transform functions, which has been \
  deprecated, instead of with key paths and case paths. Read the migration guide for 1.5 \
  to update these scopes: https://pointfreeco.github.io/swift-composable-architecture/\
  main/documentation/composablearchitecture/migratingto1.5

  • A parent feature is using deprecated navigation APIs, such as 'IfLetStore', \
  'SwitchStore', 'ForEachStore', or any navigation view modifiers taking stores instead of \
  bindings. Read the migration guide for 1.7 to update those APIs: \
  https://pointfreeco.github.io/swift-composable-architecture/main/documentation/\
  composablearchitecture/migratingto1.7
  """
}

// ND: Remove swiftui stuff
