import KlaviyoSwift
import SwiftUI

struct CheckoutView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var appState: AppState

    var body: some View {
        NavigationView {
            GeometryReader { _ in
                VStack(spacing: 0) {
                    if appState.cartItems.isEmpty {
                        VStack(spacing: 24) {
                            Spacer()

                            Image(systemName: "cart")
                                .font(.system(size: 80))
                                .foregroundColor(.gray.opacity(0.6))

                            Text("Your cart is empty!")
                                .font(.title)
                                .fontWeight(.bold)
                                .foregroundColor(.primary)

                            Text("Please add some items before you check out.")
                                .font(.body)
                                .foregroundColor(.secondary)
                                .multilineTextAlignment(.center)
                                .padding(.horizontal, 40)

                            Button("Back to Menu") {
                                dismiss()
                            }

                            Spacer()
                        }
                    } else {
                        VStack(spacing: 0) {
                            // Header
                            HStack {
                                Text("Items in Your Cart")
                                    .font(.title2)
                                    .fontWeight(.bold)
                                    .foregroundColor(.primary)

                                Spacer()

                                Button("Close") {
                                    dismiss()
                                }
                                .font(.headline)
                                .foregroundColor(.blue)
                            }
                            .padding(.horizontal, 20)
                            .padding(.vertical, 16)
                            .background(Color(.systemBackground))

                            // Cart Items List
                            ScrollView {
                                LazyVStack(spacing: 12) {
                                    ForEach(Array(Set(appState.cartItems.map(\.id))), id: \.self) { itemId in
                                        if let item = appState.cartItems.first(where: { $0.id == itemId }) {
                                            CheckoutItemRow(item: item, appState: appState)
                                                .padding(.horizontal, 16)
                                        }
                                    }
                                }
                                .padding(.vertical, 16)
                            }

                            // Order Total
                            VStack(spacing: 16) {
                                Divider()

                                HStack {
                                    Text("Order Total:")
                                        .font(.title2)
                                        .fontWeight(.medium)

                                    Spacer()

                                    Text("$\(String(format: "%.2f", totalPrice))")
                                        .font(.title)
                                        .fontWeight(.bold)
                                        .foregroundColor(.red)
                                }
                                .padding(.horizontal, 20)

                                // Action Buttons
                                HStack(spacing: 16) {
                                    Button("Back to Menu") {
                                        dismiss()
                                    }
                                    .font(.headline)
                                    .foregroundColor(.blue)
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 16)
                                    .background(Color(.systemGray6))
                                    .cornerRadius(12)

                                    Button("Check Out") {
                                        checkout()
                                    }
                                    .font(.headline)
                                    .foregroundColor(.white)
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 16)
                                    .background(
                                        LinearGradient(
                                            gradient: Gradient(colors: [.green, .green.opacity(0.8)]),
                                            startPoint: .leading,
                                            endPoint: .trailing
                                        )
                                    )
                                    .cornerRadius(12)
                                }
                                .padding(.horizontal, 20)
                            }
                            .padding(.bottom, 20)
                            .background(Color(.systemBackground))
                        }
                    }
                }
            }
            .navigationBarHidden(true)
        }
        .navigationViewStyle(StackNavigationViewStyle())
    }

    private var totalPrice: Double {
        appState.cartItems.reduce(0) { $0 + $1.price }
    }

    private func checkout() {
        // Track checkout event
        let propertiesDictionary = [
            "Items in Cart": appState.cartItems.map(\.name),
            "Total Price": totalPrice
        ] as [String: Any]

        KlaviyoSDK().create(event: .init(name: .startedCheckoutMetric, properties: propertiesDictionary))

        // Clear cart and dismiss
        appState.cartItems = []
        dismiss()
    }
}

struct CheckoutItemRow: View {
    let item: MenuItem
    let appState: AppState

    private var quantity: Int {
        appState.getQuantity(for: item)
    }

    private var totalPrice: Double {
        item.price * Double(quantity)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header with name and total price
            HStack {
                Text(item.name)
                    .font(.headline)
                    .fontWeight(.semibold)
                    .foregroundColor(.primary)

                Spacer()

                Text("$\(String(format: "%.2f", totalPrice))")
                    .font(.headline)
                    .fontWeight(.bold)
                    .foregroundColor(.red)
            }

            // Quantity controls
            HStack {
                Text("Quantity: \(quantity)")
                    .font(.subheadline)
                    .foregroundColor(.secondary)

                Spacer()

                HStack(spacing: 12) {
                    Button(action: { appState.removeFromCart(item) }) {
                        Image(systemName: "minus.circle.fill")
                            .foregroundColor(.red)
                            .font(.title2)
                    }

                    Text("\(quantity)")
                        .font(.headline)
                        .fontWeight(.semibold)
                        .frame(minWidth: 30)

                    Button(action: { appState.addToCart(item) }) {
                        Image(systemName: "plus.circle.fill")
                            .foregroundColor(.green)
                            .font(.title2)
                    }
                }
            }
        }
        .padding(16)
        .background(Color(.systemBackground))
        .cornerRadius(16)
        .shadow(color: .black.opacity(0.05), radius: 8, x: 0, y: 2)
    }
}

#Preview {
    CheckoutView()
        .environmentObject(AppState())
}
