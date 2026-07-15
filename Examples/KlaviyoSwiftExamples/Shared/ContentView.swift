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
        KlaviyoSDK().create(event: .init(name: .addedToCartMetric, properties: propertiesDictionary))
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

// MARK: - Mobile Inbox UI

/// Displays the messages captured by `MobileInbox` (see AppDelegate.swift).
/// Present this from anywhere — here it's shown as a sheet from the menu's
/// toolbar bell button (see `MenuView`).
struct InboxView: View {
    @ObservedObject private var inbox = MobileInbox.shared
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Group {
                if inbox.messages.isEmpty {
                    VStack(spacing: 8) {
                        Image(systemName: "tray")
                            .font(.largeTitle)
                            .foregroundColor(.secondary)
                        Text("No messages yet")
                            .font(.headline)
                        Text("Pushes sent with content-available appear here.")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .padding()
                } else {
                    List(inbox.messages) { message in
                        InboxRow(message: message)
                            .contentShape(Rectangle())
                            .onTapGesture { inbox.markAsRead(message) }
                    }
                }
            }
            .navigationTitle("Inbox")
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Done") { dismiss() }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    if !inbox.messages.isEmpty {
                        Button("Clear", role: .destructive) { inbox.clear() }
                    }
                }
            }
        }
    }
}

private struct InboxRow: View {
    let message: InboxMessage

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Circle()
                .fill(message.isRead ? Color.clear : Color.red)
                .frame(width: 8, height: 8)
                .padding(.top, 6)
            VStack(alignment: .leading, spacing: 4) {
                if !message.title.isEmpty {
                    Text(message.title).font(.headline)
                }
                if !message.body.isEmpty {
                    Text(message.body).font(.subheadline).foregroundColor(.secondary)
                }
                if !message.data.isEmpty {
                    Text(message.data.map { "\($0.key): \($0.value)" }.sorted().joined(separator: "\n"))
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                Text(message.receivedAt.formatted(date: .abbreviated, time: .shortened))
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
        }
        .padding(.vertical, 4)
    }
}
