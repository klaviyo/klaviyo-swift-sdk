import KlaviyoSwift
import SwiftUI

// MARK: - AppState

class AppState: ObservableObject {
    @Published var isLoggedIn: Bool {
        didSet {
            UserDefaults.standard.set(isLoggedIn, forKey: "isLoggedIn")
        }
    }

    @Published var userEmail: String {
        didSet {
            UserDefaults.standard.set(userEmail, forKey: "email")
            if !userEmail.isEmpty {
                KlaviyoSDK().set(email: userEmail)
            }
        }
    }

    @Published var userZipcode: String {
        didSet {
            UserDefaults.standard.set(userZipcode, forKey: "zip")
        }
    }

    @Published var cartItems: [MenuItem] {
        didSet {
            saveCartItems()
        }
    }

    init() {
        // Load saved data
        isLoggedIn = UserDefaults.standard.bool(forKey: "isLoggedIn")
        userEmail = UserDefaults.standard.string(forKey: "email") ?? ""
        userZipcode = UserDefaults.standard.string(forKey: "zip") ?? ""

        // Load cart items
        if let data = UserDefaults.standard.data(forKey: "cartItems"),
           let items = try? JSONDecoder().decode([MenuItem].self, from: data) {
            cartItems = items
        } else {
            cartItems = []
        }

        // Set up Klaviyo if user is logged in
        if isLoggedIn && !userEmail.isEmpty {
            KlaviyoSDK().set(email: userEmail)
        }
    }

    func login(email: String, zipcode: String) {
        userEmail = email
        userZipcode = zipcode
        isLoggedIn = true

        // Track login event
        KlaviyoSDK().create(event: .init(name: .customEvent("User Logged In")))
    }

    func logout() {
        isLoggedIn = false
        userEmail = ""
        userZipcode = ""
        cartItems = []

        // Clear UserDefaults
        UserDefaults.standard.removeObject(forKey: "isLoggedIn")
        UserDefaults.standard.removeObject(forKey: "email")
        UserDefaults.standard.removeObject(forKey: "zip")
        UserDefaults.standard.removeObject(forKey: "cartItems")
    }

    func addToCart(_ item: MenuItem) {
        cartItems.append(item)

        // Track add to cart event
        let propertiesDictionary = [
            "Items in Cart": cartItems.map(\.name)
        ]
        KlaviyoSDK().create(event: .init(name: .startedCheckoutMetric, properties: propertiesDictionary))
    }

    func removeFromCart(_ item: MenuItem) {
        if let index = cartItems.firstIndex(where: { $0.id == item.id }) {
            cartItems.remove(at: index)
        }
    }

    func getQuantity(for item: MenuItem) -> Int {
        cartItems.filter { $0.id == item.id }.count
    }

    private func saveCartItems() {
        if let data = try? JSONEncoder().encode(cartItems) {
            UserDefaults.standard.set(data, forKey: "cartItems")
        }
    }
}

struct ContentView: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        Group {
            if appState.isLoggedIn {
                MenuView()
            } else {
                LoginView()
            }
        }
        .ignoresSafeArea(.all, edges: .all)
        .onAppear {
            print("ContentView: Appeared, isLoggedIn: \(appState.isLoggedIn)")
            // Track app open event
            KlaviyoSDK().create(event: .init(name: .customEvent("Opened kLM App")))
        }
    }
}

#Preview {
    ContentView()
        .environmentObject(AppState())
}
