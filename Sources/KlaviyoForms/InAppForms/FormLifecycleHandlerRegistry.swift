//
//  FormLifecycleHandlerRegistry.swift
//  klaviyo-swift-sdk
//

import Foundation
import OSLog

/// Stores the host app's form-lifecycle callback and invokes it.
///
/// Deliberately independent of the forms session: the host registers a handler once, and it
/// must survive session rebuilds (API-key change, session timeout) without being re-registered.
/// Keeping it off `IAFPresentationManager` also gives `IAFWebViewModel` somewhere to deliver
/// events other than reaching back into the manager singleton.
@MainActor
final class FormLifecycleHandlerRegistry {
    static let shared = FormLifecycleHandlerRegistry()

    private var handler: (@MainActor (FormLifecycleEvent) -> Void)?

    init() {}

    func register(_ handler: @escaping (FormLifecycleEvent) -> Void) {
        if #available(iOS 14.0, *) {
            Logger.webViewLogger.log("Registering form lifecycle handler")
        }
        self.handler = handler
    }

    func unregister() {
        if #available(iOS 14.0, *) {
            if handler != nil {
                Logger.webViewLogger.log("Unregistering form lifecycle handler")
            }
        }
        handler = nil
    }

    func invoke(for event: FormLifecycleEvent) {
        guard let handler else { return }

        if #available(iOS 14.0, *) {
            Logger.webViewLogger.debug(
                "Invoking form lifecycle handler for event: \(event.eventName, privacy: .public)"
            )
        }

        handler(event)
    }
}
