import KlaviyoSwift
import SwiftUI

struct MenuView: View {
    @EnvironmentObject var appState: AppState
    @State private var menuItems: [MenuItem] = []
    @State private var showingMap = false
    @State private var showingCheckout = false

    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                // Header
                HStack {
                    Button(action: logout) {
                        Image("Log Out")
                            .resizable()
                            .frame(width: 30, height: 30)
                    }

                    Spacer()

                    Text("Select Your Items")
                        .font(.headline)
                        .fontWeight(.bold)
                        .foregroundColor(.white)

                    Spacer()

                    Button(action: { showingCheckout = true }) {
                        Image(appState.cartItems.isEmpty ? "emptyCart" : "FullCart")
                            .resizable()
                            .frame(width: 30, height: 30)
                    }
                }
                .padding()
                .background(Color.red)

                // Menu Items List
                List(menuItems, id: \.id) { item in
                    MenuItemRow(item: item, appState: appState)
                }
                .listStyle(PlainListStyle())

                // Footer
                HStack {
                    Button(action: { showingMap = true }) {
                        Image("Map")
                            .resizable()
                            .frame(width: 25, height: 25)
                    }

                    Text("Zipcode: \(appState.userZipcode)")
                        .font(.caption)
                        .foregroundColor(.secondary)

                    Spacer()

                    Text("Email: \(appState.userEmail)")
                        .font(.caption)
                        .foregroundColor(.secondary)

                    Button(action: addEmail) {
                        Image("Email")
                            .resizable()
                            .frame(width: 25, height: 25)
                    }
                }
                .padding()
                .background(Color(.systemGray6))
            }
            .navigationBarHidden(true)
        }
        .onAppear {
            loadMenuItems()
            KlaviyoSDK().registerForInAppForms()
        }
        .sheet(isPresented: $showingMap) {
            MapView()
        }
        .sheet(isPresented: $showingCheckout) {
            CheckoutView()
        }
    }

    private func loadMenuItems() {
        menuItems = [
            MenuItem(name: "Fish & Chips", id: 1, description: "Lightly battered & fried fresh cod and freshly cooked fries", image: "battered_fish.jpg", price: 10.99),
            MenuItem(name: "Nicoise Salad", id: 2, description: "Delicious salad of mixed greens, tuna nicoise and balasamic vinagrette", image: "nicoise_salad.jpg", price: 12.99),
            MenuItem(name: "Red Pork", id: 3, description: "Our take on the popular Chinese dish", image: "red_pork.jpg", price: 11.99),
            MenuItem(name: "Beef Bolognese", id: 4, description: "Traditional Italian Bolognese", image: "bolognese_meal.jpg", price: 10.99)
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
    let appState: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(item.image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: 150, height: 150)
                    .clipped()
                    .cornerRadius(8)

                VStack(alignment: .leading, spacing: 4) {
                    Text(item.name)
                        .font(.headline)
                        .fontWeight(.bold)

                    Text("$\(String(format: "%.2f", item.price))")
                        .font(.subheadline)
                        .foregroundColor(.secondary)

                    Text(item.description)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(3)

                    Spacer()

                    HStack {
                        Text("Quantity: \(appState.getQuantity(for: item))")
                            .font(.caption)

                        if appState.getQuantity(for: item) > 0 {
                            Button("X") {
                                appState.removeFromCart(item)
                            }
                            .font(.caption)
                            .foregroundColor(.red)
                        }
                    }

                    Button("Add to Cart") {
                        appState.addToCart(item)
                    }
                    .font(.headline)
                    .foregroundColor(.white)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 8)
                    .background(Color.red)
                    .cornerRadius(8)
                }

                Spacer()
            }
        }
        .navigationBarHidden(true)
        .navigationViewStyle(StackNavigationViewStyle())
        .background(Color(.systemBackground))
    }
}

#Preview {
    MenuView()
        .environmentObject(AppState())
}
