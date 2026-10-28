import KlaviyoForms
import KlaviyoSwift
import SwiftUI

@main
struct CocoapodsExampleApp: App {
    @StateObject private var appState = AppState()
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(appState)
                .onOpenURL { url in
                    // Start a draft in-app forms preview from the form editor's QR code or
                    // copied preview link with KlaviyoSDK().handleFormsPreviewLink(_:). It returns
                    // false, changing nothing, for every other link. AppState also shows the
                    // preview in its controls.
                    appState.handleFormsPreviewLink(url)
                }
        }
    }
}
