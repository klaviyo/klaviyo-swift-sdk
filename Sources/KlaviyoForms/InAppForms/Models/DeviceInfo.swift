//
//  DeviceInfo.swift
//  klaviyo-swift-sdk
//
//  Created by Evan Masseau on 4/22/26.
//

import Foundation
import OSLog
import UIKit

/// Describes the device's current physical display characteristics, exposed to onsite JS
/// via the `data-klaviyo-device` attribute on the HTML `<head>` element.
///
/// The shape intentionally mirrors CSSOM conventions so onsite code can treat the payload
/// as a reliable, orientation-aware substitute for `window.screen.*` during the synchronous
/// HTML parse phase, before the web view attaches to the view hierarchy.
struct DeviceInfo: Codable, Equatable {
    /// Screen dimensions in CSS points, oriented to match the current interface orientation.
    struct Screen: Codable, Equatable {
        let width: Int
        let height: Int
    }

    /// Safe-area insets in CSS points for the currently displayed window.
    struct SafeAreaInsets: Codable, Equatable {
        // `top` name locked by wire contract (CSSOM / data-klaviyo-device spec).
        // swiftlint:disable:next identifier_name
        let top: Int
        let bottom: Int
        let left: Int
        let right: Int
    }

    let screen: Screen
    let safeAreaInsets: SafeAreaInsets
    let orientation: String
    // `dpr` name locked by wire contract (CSSOM / data-klaviyo-device spec).
    // swiftlint:disable:next identifier_name
    let dpr: Int

    // MARK: - CSSOM orientation mapping

    /// Map `UIInterfaceOrientation` to the CSSOM `ScreenOrientation.type` vocabulary.
    /// See https://drafts.csswg.org/screen-orientation/#enumdef-orientationtype
    static func cssOrientation(for orientation: UIInterfaceOrientation) -> String {
        switch orientation {
        case .portrait: return "portrait-primary"
        case .portraitUpsideDown: return "portrait-secondary"
        case .landscapeLeft: return "landscape-primary"
        case .landscapeRight: return "landscape-secondary"
        case .unknown: return "portrait-primary"
        @unknown default: return "portrait-primary"
        }
    }

    // MARK: - Construction

    /// Construct a `DeviceInfo` from raw inputs. `screenBounds` should already reflect the
    /// current window's drawable area (not the raw device screen) — live capture uses
    /// `window.bounds` as the source.
    static func make(
        screenBounds: CGSize,
        orientation: UIInterfaceOrientation,
        nativeScale: CGFloat,
        safeAreaInsets: UIEdgeInsets
    ) -> DeviceInfo {
        DeviceInfo(
            screen: Screen(
                width: Int(screenBounds.width.rounded()),
                height: Int(screenBounds.height.rounded())
            ),
            safeAreaInsets: SafeAreaInsets(
                top: Int(safeAreaInsets.top.rounded()),
                bottom: Int(safeAreaInsets.bottom.rounded()),
                left: Int(safeAreaInsets.left.rounded()),
                right: Int(safeAreaInsets.right.rounded())
            ),
            orientation: cssOrientation(for: orientation),
            dpr: max(1, Int(nativeScale.rounded()))
        )
    }

    // MARK: - Live capture

    /// Snapshot the current device state.
    ///
    /// Uses the customer app's key window bounds as the primary source so dimensions reflect
    /// the actual drawable area under iPad split view / stage manager / external-display
    /// scenarios. Falls back to `scene.screen` and `UIScreen.main` for pathological
    /// pre-scene cold-launch scenarios.
    @MainActor
    static func current() -> DeviceInfo {
        let scene = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first { $0.activationState == .foregroundActive }
            ?? UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first

        let window = scene?.windows.first(where: \.isKeyWindow)
            ?? scene?.windows.first

        let bounds = window?.bounds.size
            ?? scene?.screen.bounds.size
            ?? UIScreen.main.bounds.size

        let nativeScale = window?.screen.nativeScale
            ?? scene?.screen.nativeScale
            ?? UIScreen.main.nativeScale

        let orientation = scene?.interfaceOrientation ?? .portrait
        let insets = window?.safeAreaInsets ?? .zero

        return DeviceInfo.make(
            screenBounds: bounds,
            orientation: orientation,
            nativeScale: nativeScale,
            safeAreaInsets: insets
        )
    }

    // MARK: - Serialization

    /// Serializes the device info into its JSON representation as published on the
    /// `data-klaviyo-device` head attribute.
    func toJsonString() -> String {
        let encoder = JSONEncoder()
        // Stable key ordering helps downstream diffing and snapshot tests.
        encoder.outputFormatting = [.sortedKeys]
        do {
            let data = try encoder.encode(self)
            return String(data: data, encoding: .utf8) ?? "{}"
        } catch {
            if #available(iOS 14.0, *) {
                Logger.webViewLogger.error("DeviceInfo encode failed: \(error)")
            }
            return "{}"
        }
    }

    /// JS statement that sets the `data-klaviyo-device` attribute on the document head
    /// using this payload. Centralizes the attribute name and JS-escaping contract so
    /// injection-time and runtime-push call sites stay in lockstep.
    func asAttributeAssignmentScript() -> String {
        let json = toJsonString().klaviyoJsSingleQuoteEscaped
        return "document.head.setAttribute('data-klaviyo-device', '\(json)');"
    }
}

// MARK: - JS escaping

extension String {
    /// Escapes a JSON payload for embedding inside a single-quoted JS string literal.
    ///
    /// JSON already escapes double quotes, control characters, and non-ASCII characters,
    /// so only backslashes and single quotes need additional handling.
    var klaviyoJsSingleQuoteEscaped: String {
        replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "'", with: "\\'")
    }
}
