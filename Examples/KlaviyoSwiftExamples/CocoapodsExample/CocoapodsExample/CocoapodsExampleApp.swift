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
                    // copied preview link. Returns false, changing nothing, for every other link.
                    KlaviyoSDK().handleFormsPreviewLink(url)
                }
        }
    }
}
