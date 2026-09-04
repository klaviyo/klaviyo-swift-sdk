//
//  FormsSession.swift
//  klaviyo-swift-sdk
//

import Foundation
import KlaviyoCore
import OSLog
import UIKit

/// One In-App Forms session: a webview running `klaviyo.js`, plus everything scoped to it.
///
/// **Lifetime is the point.** Everything that belongs to a session — the webview, its view
/// model, the profile-event observer and the two tasks feeding it — is owned here rather than
/// held as flat properties on a long-lived manager. Ending a session is therefore releasing
/// this object; `deinit` performs the teardown. There is no hand-maintained list of things to
/// nil, and so no way for one of them to be forgotten.
///
/// That matters concretely: a stale profile-event observer surviving a session rebuild is what
/// caused push-open-triggered forms to silently stop firing after the session timeout elapsed.
@MainActor
final class FormsSession {
    /// What a session needs from its owner, so `FormsSession` doesn't reach back into the manager.
    struct Callbacks {
        /// Invoked when `klaviyo.js` asks for a form to be shown.
        let present: @MainActor (KlaviyoWebViewController, FormLayout?) -> Void
        /// Invoked when `klaviyo.js` asks for the current form to be hidden.
        let dismiss: @MainActor (KlaviyoWebViewController) -> Void
        /// Invoked when the session aborts itself (failed handshake, or an `abort` from JS).
        /// The owner is expected to release this session.
        let abort: @MainActor () -> Void
    }

    let apiKey: String

    private let callbacks: Callbacks
    private let viewModel: IAFWebViewModel
    private(set) var viewController: KlaviyoWebViewController

    private var formEventTask: Task<Void, Never>?
    private var handshakeTask: Task<Void, Never>?

    private var profileEventObserver: ProfileEventObserver?
    private var profileEventsTask: Task<Void, Never>?

    /// Creates the webview and immediately begins listening for form events and handshaking.
    /// Returns `nil` if the bundled `klaviyo.js` template can't be located.
    init?(apiKey: String, assetSource: String?, callbacks: Callbacks) {
        guard let fileUrl = Self.indexHtmlFileUrl else { return nil }

        self.apiKey = apiKey
        self.callbacks = callbacks

        let profileData = IdentityStore.shared.current
        viewModel = IAFWebViewModel(
            url: fileUrl,
            apiKey: apiKey,
            profileData: profileData,
            assetSource: assetSource
        )
        viewController = KlaviyoWebViewController(viewModel: viewModel)
        viewController.modalPresentationStyle = .overCurrentContext

        start()
    }

    deinit {
        // Releasing the session IS the teardown. Nothing here can be forgotten by a caller.
        formEventTask?.cancel()
        handshakeTask?.cancel()
        profileEventsTask?.cancel()
        // `profileEventObserver` stops itself in its own `deinit`, but stopping eagerly keeps
        // the Combine subscription from outliving this session by a deallocation cycle.
        let observer = profileEventObserver
        MainActor.assumeIsolated { observer?.stopObserving() }
    }

    // MARK: - Startup

    private func start() {
        if #available(iOS 14.0, *) {
            Logger.webViewLogger.info("👂 Starting to listen for form lifecycle events (BEFORE handshake)")
        }

        // Listen for form lifecycle events before handshaking, so no events are missed.
        formEventTask = Task { [weak self] in
            guard let self else { return }
            for await event in viewModel.formLifecycleStream {
                handleFormEvent(event)
            }
        }

        handshakeTask = Task { [weak self] in
            guard let self else { return }
            if #available(iOS 14.0, *) {
                Logger.webViewLogger.info("🤝 Starting handshake with KlaviyoJS")
            }
            do {
                try await viewModel.establishHandshake(timeout: NetworkSession.networkTimeout.seconds)
                if #available(iOS 14.0, *) {
                    Logger.webViewLogger.info("✅ Handshake completed successfully.")
                }
            } catch {
                if #available(iOS 14.0, *) {
                    Logger.webViewLogger.warning("❌ Unable to establish handshake with KlaviyoJS: \(error).")
                }
                callbacks.abort()
            }
        }
    }

    // MARK: - Events from klaviyo.js

    private func handleFormEvent(_ event: IAFLifecycleEvent) {
        if #available(iOS 14.0, *) {
            Logger.webViewLogger.info("Handling '\(event.rawValue, privacy: .public)' form lifecycle event")
        }
        switch event {
        case .handShook:
            // Handshake complete - webview is ready, start observing profile events
            if #available(iOS 14.0, *) {
                Logger.webViewLogger.info("✅ Handshake confirmed from webview, starting profile observation")
            }
            startProfileObservation()
        case let .present(withLayout: layout):
            callbacks.present(viewController, layout)
        case .dismiss:
            callbacks.dismiss(viewController)
        case .abort:
            callbacks.abort()
        }
    }

    /// Subscribes to the profile-event bus. Subscribing is also what replays the buffered
    /// events (the bus prepends its buffer on subscribe), so this must happen on every
    /// handshake — including a rebuilt session's.
    private func startProfileObservation() {
        guard profileEventObserver == nil else {
            if #available(iOS 14.0, *) {
                Logger.webViewLogger.log("Profile observer already exists; skipping.")
            }
            return
        }

        let observer = ProfileEventObserver()
        observer.startObserving()
        profileEventObserver = observer

        profileEventsTask = Task { [weak self] in
            for await event in observer.eventsStream {
                guard let self else { return }
                await dispatchProfileEvent(event)
            }
        }

        if #available(iOS 14.0, *) {
            Logger.webViewLogger.info(
                "👂 Started observing profile events. Buffered events will now be replayed."
            )
        }
    }

    // MARK: - Dispatch into klaviyo.js

    /// Forwards an app lifecycle transition ("foreground"/"background") into `klaviyo.js`.
    func dispatchLifecycleEvent(_ event: String) async {
        if #available(iOS 14.0, *) {
            Logger.webViewLogger.info(
                "Attempting to dispatch '\(event, privacy: .public)' lifecycle event via Klaviyo.JS"
            )
        }

        do {
            let result = try await viewController.evaluateJavaScript("dispatchLifecycleEvent('\(event)')")
            if #available(iOS 14.0, *) {
                let detail = result != nil ? "; message: \(result.debugDescription)" : ""
                Logger.webViewLogger.info("Successfully dispatched lifecycle event via Klaviyo.JS\(detail)")
            }
        } catch {
            if #available(iOS 14.0, *) {
                Logger.webViewLogger.warning(
                    "Error dispatching lifecycle event via Klaviyo.JS; message: \(error.localizedDescription)"
                )
            }
        }
    }

    private func dispatchProfileEvent(_ event: Event) async {
        do {
            // Safely convert metric to a JSON string or null
            let metricData = try KlaviyoEnvironment.encoder.encode(event.metric.name.value)
            let metric = String(data: metricData, encoding: .utf8) ?? "null"

            // Safely convert uniqueID to a JSON string or null
            let uniqueIdData = try KlaviyoEnvironment.encoder.encode(event.uniqueId)
            let uniqueId = String(data: uniqueIdData, encoding: .utf8) ?? "null"

            // Convert date to JSON, formatting with ISO8601 (which is always in UTC)
            let timestampData = try KlaviyoEnvironment.encoder.encode(event.time)
            let timestamp = String(data: timestampData, encoding: .utf8) ?? "null"

            // Get event's value as JSON or null
            let valueData = try KlaviyoEnvironment.encoder.encode(event.value)
            let value = String(data: valueData, encoding: .utf8) ?? "null"

            // Convert properties to JSON string to ensure proper object serialization,
            // default to empty dict if serialization fails
            var propertiesJSON = "{}"
            if let propertiesData = try? JSONSerialization.data(withJSONObject: event.properties) {
                propertiesJSON = String(data: propertiesData, encoding: .utf8) ?? propertiesJSON
            }

            // JSON encoding adds the necessary quotes to strings, and escapes unsafe chars,
            // so no need to add single quotes
            _ = try await viewController.evaluateJavaScript(
                "dispatchProfileEvent(\(metric), \(uniqueId), \(timestamp), \(value), \(propertiesJSON))"
            )
        } catch {
            if #available(iOS 14.0, *) {
                Logger.webViewLogger.warning(
                    "❌ Error dispatching event via Klaviyo.JS; message: \(error.localizedDescription)"
                )
            }
        }
    }

    // MARK: - Resources

    private static let indexHtmlFileUrl: URL? = {
        do {
            return try ResourceLoader.getResourceUrl(path: "InAppFormsTemplate", type: "html")
        } catch {
            if #available(iOS 14.0, *) {
                Logger.webViewLogger.warning("Error loading InAppFormsTemplate.html")
            }
            return nil
        }
    }()
}
