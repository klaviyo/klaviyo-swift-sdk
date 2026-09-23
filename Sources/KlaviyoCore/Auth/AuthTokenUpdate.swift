//
//  AuthTokenUpdate.swift
//  KlaviyoCore
//

package enum AuthTokenUpdate: Equatable, Sendable {
    case cleared
    case token(String)
}
