//
//  WKNavigationEvent.swift
//  klaviyo-swift-sdk
//
//  Created by Andrew Balmer on 9/30/24.
//

enum WKNavigationEvent: String {
    /// Invoked when a main frame navigation starts.
    case didStartProvisionalNavigation

    /// Invoked when a server redirect is received for the main frame.
    case didReceiveServerRedirectForProvisionalNavigation

    /// Invoked when an error occurs while starting to load data for the main frame.
    case didFailProvisionalNavigation

    /// Invoked when content starts arriving for the main frame.
    case didCommitNavigation

    /// Invoked when a main frame navigation completes.
    case didFinishNavigation

    /// Invoked when an error occurs during a committed main frame navigation.
    case didFailNavigation
}
