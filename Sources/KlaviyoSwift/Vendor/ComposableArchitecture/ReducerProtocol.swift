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
//  ReducerProtocol.swift
//  Pulled from https://github.com/pointfreeco/swift-composable-architecture
//
//  Created by Noah Durell on 12/6/22.
//

import Foundation

protocol ReducerProtocol {
  /// A type that holds the current state of the reducer.
  associatedtype State

  /// A type that holds all possible actions that cause the ``State`` of the reducer to change
  /// and/or kick off a side ``EffectTask`` that can communicate with the outside world.
  associatedtype Action

  /// Evolves the current state of an reducer to the next state.
  ///
  ///
  /// - Parameters:
  ///   - state: The current state of the reducer.
  ///   - action: An action that can cause the state of the reducer to change, and/or kick off
  ///     a side effect that can communicate with the outside world.
  /// - Returns: An effect that can communicate with the outside world and feed actions back into
  ///   the system.
  func reduce(into state: inout State, action: Action) -> EffectTask<Action>

}
