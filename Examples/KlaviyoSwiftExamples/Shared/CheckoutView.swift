import KlaviyoSwift
import SwiftUI

struct CheckoutView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var appState: AppState

    var body: some View {
        NavigationView {
            VStack {
                if appState.cartItems.isEmpty {
                    VStack(spacing: 20) {
                        Image(systemName: "cart")
                            .font(.system(size: 60))
                            .foregroundColor(.gray)

                        Text("Your cart is empty!")
                            .font(.title2)
                            .fontWeight(.bold)

                        Text("Please add some items before you check out.")
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)

                        Button("Back to Menu") {
                            dismiss()
                        }
                        .buttonStyle(.borderedProminent)
                    }
                    .padding()
                } else {
                    VStack(spacing: 0) {
                        // Header
                        Text("Items in Your Cart")
                            .font(.title2)
                            .fontWeight(.bold)
                            .padding()

                        // Cart Items List
                        List {
                            ForEach(Array(Set(appState.cartItems.map(\.id))), id: \.self) { itemId in
                                if let item = appState.cartItems.first(where: { $0.id == itemId }) {
                                    CheckoutItemRow(item: item, appState: appState)
                                }
                            }
                        }
                        .listStyle(PlainListStyle())

                        // Order Total
                        HStack {
                            Spacer()
                            Text("Order Total: $\(String(format: "%.2f", totalPrice))")
                                .font(.title2)
                                .fontWeight(.bold)
                        }
                        .padding()
                        .background(Color(.systemGray6))

                        // Action Buttons
                        HStack(spacing: 20) {
                            Button("Back") {
                                dismiss()
                            }
                            .buttonStyle(.bordered)
                            .frame(maxWidth: .infinity)

                            Button("Check Out") {
                                checkout()
                            }
                            .buttonStyle(.borderedProminent)
                            .frame(maxWidth: .infinity)
                        }
                        .padding()
                    }
                }
            }
            .navigationTitle("Checkout")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Close") {
                        dismiss()
                    }
                }
            }
        }
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
        HStack {
            Image(item.image)
                .resizable()
                .aspectRatio(contentMode: .fill)
                .frame(width: 65, height: 65)
                .clipped()
                .cornerRadius(8)

            VStack(alignment: .leading, spacing: 4) {
                Text(item.name)
                    .font(.headline)

                Text("Quantity: \(quantity)")
                    .font(.subheadline)
                    .foregroundColor(.secondary)

                HStack {
                    Text("Remove")
                        .font(.caption)
                        .foregroundColor(.red)

                    Button("X") {
                        appState.removeFromCart(item)
                    }
                    .font(.caption)
                    .foregroundColor(.red)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.red.opacity(0.1))
                    .cornerRadius(4)
                }
            }

            Spacer()

            Text("$\(String(format: "%.2f", totalPrice))")
                .font(.headline)
                .fontWeight(.bold)
        }
        .padding(.vertical, 4)
    }
}

#Preview {
    CheckoutView()
        .environmentObject(AppState())
}
