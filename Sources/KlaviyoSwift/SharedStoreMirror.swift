//
//  SharedStoreMirror.swift
//  klaviyo-swift-sdk
//

import Combine
import KlaviyoCore

/// KlaviyoSwift's write-side push of canonical SDK state into the shared `KlaviyoCore` stores.
/// Mirrors initialized `KlaviyoState` (identity + apiKey) into `IdentityStore` / `SDKConfigStore`
/// so other modules observe them without importing `KlaviyoSwift`.
enum SharedStoreMirror {
    private static var cancellable: AnyCancellable?

    /// Attach the mirror (idempotent). Established once at `initialize(with:)` and left alive
    /// for the SDK's lifetime.
    static func setup() {
        guard cancellable == nil else { return }
        cancellable = klaviyoSwiftEnvironment.statePublisher()
            .filter { $0.initalizationState == .initialized }
            .map { (identity: $0.identity, apiKey: $0.apiKey) }
            .removeDuplicates(by: { $0.identity == $1.identity && $0.apiKey == $1.apiKey })
            // TCA dispatches state changes on the main thread, so the two writes are observed
            // together. Write config before identity: IdentityStore.update(_:) notifies observers
            // synchronously, so an identity observer must not see a stale apiKey.
            .sink { result in
                SDKConfigStore.shared.update(KlaviyoConfig(apiKey: result.apiKey))
                IdentityStore.shared.update(result.identity)
            }
    }

    /// Test-only isolation helper: detach the mirror and clear the stores so each test starts
    /// detached + empty. Production never tears the mirror down.
    static func reset() {
        cancellable?.cancel()
        cancellable = nil
        SDKConfigStore.shared.update(KlaviyoConfig())
        IdentityStore.shared.update(ProfileData())
    }
}
