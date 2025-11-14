import KlaviyoSwift
import SwiftUI

struct MenuView: View {
    @EnvironmentObject var appState: AppState
    @State private var menuItems: [MenuItem] = []
    @State private var showingMap = false
    @State private var showingCheckout = false

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(spacing: 12) {
                    ForEach(menuItems, id: \.id) { item in
                        MenuItemRow(item: item, onAddToCart: { item in
                            appState.addToCart(item)
                        })
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
            }
            .navigationTitle("Select Your Items")
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Log Out", systemImage: "rectangle.portrait.and.arrow.right") {
                        logout()
                    }
                }

                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(action: { showingCheckout = true }) {
                        Image(appState.cartItems.isEmpty ? "emptyCart" : "FullCart")
                    }
                    .badge(appState.cartItems.count)
                    .id("cart-\(appState.cartItems.count)")
                }
            }
            .toolbar {
                ToolbarItemGroup(placement: .bottomBar) {
                    Button("Map", systemImage: "map") {
                        showingMap = true
                    }

                    Spacer()

                    VStack(alignment: .center) {
                        Text("Zipcode: \(appState.userZipcode)")
                            .font(.caption)
                            .foregroundColor(.secondary)

                        Text("Email: \(appState.userEmail)")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .padding(.horizontal)
                    .fixedSize(horizontal: true, vertical: false)

                    Spacer()

                    Button("Add Email", systemImage: "envelope") {
                        addEmail()
                    }
                }
            }
        }
        .onAppear {
            loadMenuItems()
            KlaviyoSDK().registerForInAppForms()
        }
        .sheet(isPresented: $showingMap) {
            MapView()
        }
        .sheet(isPresented: $showingCheckout) {
            CheckoutView(cartItems: $appState.cartItems)
        }
    }

    private func loadMenuItems() {
        menuItems = [
            MenuItem(name: "Fish & Chips", id: 1, description: "Lightly battered & fried fresh cod and freshly cooked fries", price: 10.99),
            MenuItem(name: "Nicoise Salad", id: 2, description: "Delicious salad of mixed greens, tuna nicoise and balasamic vinagrette", price: 12.99),
            MenuItem(name: "Red Pork", id: 3, description: "Our take on the popular Chinese dish", price: 11.99),
            MenuItem(name: "Beef Bolognese", id: 4, description: "Traditional Italian Bolognese", price: 10.99)
        ]
    }

    private func logout() {
        appState.logout()
    }

    private func addEmail() {
        // This would show an alert to add email
        // For now, just a placeholder
    }
}

struct MenuItemRow: View {
    let item: MenuItem
    let onAddToCart: (MenuItem) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header with name and price
            HStack {
                Text(item.name)
                    .font(.title2)
                    .fontWeight(.bold)
                    .foregroundColor(.primary)

                Spacer()

                Text("$\(String(format: "%.2f", item.price))")
                    .font(.title2)
                    .fontWeight(.bold)
                    .foregroundColor(.red)
            }

            // Description
            Text(item.description)
                .font(.body)
                .foregroundColor(.secondary)
                .lineLimit(2)
                .multilineTextAlignment(.leading)

            // Add to Cart Button
            HStack {
                Button(action: { onAddToCart(item) }) {
                    HStack(spacing: 8) {
                        Image(systemName: "plus.circle.fill")
                            .foregroundColor(.white)
                        Text("Add to Cart")
                            .font(.headline)
                            .fontWeight(.semibold)
                            .foregroundColor(.white)
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 10)
                    .background(
                        LinearGradient(
                            gradient: Gradient(colors: [.red, .red.opacity(0.8)]),
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .cornerRadius(25)
                }

                Spacer()
            }
        }
        .padding(16)
        .background(Color(.systemBackground))
        .cornerRadius(16)
        .shadow(color: .black.opacity(0.05), radius: 8, x: 0, y: 2)
    }
}

// MARK: - Previews

@available(iOS 17.0, *)
#Preview {
    @Previewable @State var appState: AppState = {
        let appState = AppState()
        appState.userZipcode = "02111"
        appState.userEmail = "john@tester.com"
        appState.cartItems = [
            MenuItem(name: "", id: 1, description: ""),
            MenuItem(name: "", id: 2, description: "")
        ]

        return appState
    }()

    MenuView()
        .environmentObject(appState)
}

@available(iOS 17.0, *)
#Preview("Empty Cart") {
    @Previewable @State var appState: AppState = {
        let appState = AppState()
        appState.userZipcode = "02111"
        appState.userEmail = "john@tester.com"
        appState.cartItems = []

        return appState
    }()

    MenuView()
        .environmentObject(appState)
}
