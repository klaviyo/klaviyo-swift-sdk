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
import Foundation
import Combine
#if canImport(os)
  import os
#endif

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
      #if canImport(os)
        os_log(
          .fault,
          dso: dso,
          log: OSLog(subsystem: "com.apple.runtime-issues", category: category),
          "%@",
          message
        )
      #endif
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

extension NSRecursiveLock {
  @inlinable @discardableResult
  func sync<R>(work: () -> R) -> R {
    self.lock()
    defer { self.unlock() }
    return work()
  }
}

extension UnsafeMutablePointer where Pointee == os_unfair_lock_s {
  @inlinable @discardableResult
  func sync<R>(_ work: () -> R) -> R {
    os_unfair_lock_lock(self)
    defer { os_unfair_lock_unlock(self) }
    return work()
  }
}

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
