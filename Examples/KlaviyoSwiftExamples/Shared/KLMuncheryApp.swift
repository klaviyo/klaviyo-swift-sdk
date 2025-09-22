import KlaviyoSwift
import SwiftUI

@main
struct KLMuncheryApp: App {
    @StateObject private var appState = AppState()

    init() {
        // Initialize Klaviyo SDK
        KlaviyoSDK()
            .initialize(with: "ABC123")
            .registerForInAppForms()
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(appState)
        }
    }
}
