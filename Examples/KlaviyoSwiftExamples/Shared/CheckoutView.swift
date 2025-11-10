import KlaviyoSwift
import SwiftUI

// MARK: - Cart Item with Quantity

struct CartItem: Identifiable, Hashable {
    let id = UUID()
    let menuItem: MenuItem
    var quantity: Int

    var totalPrice: Double {
        menuItem.price * Double(quantity)
    }
}

struct CheckoutView: View {
    @Environment(\.dismiss) private var dismiss
    @Binding var cartItems: [MenuItem]
    @State private var localCartItems: [CartItem] = []

    var body: some View {
        NavigationView {
            VStack {
                if localCartItems.isEmpty {
                    EmptyCartView {
                        dismiss()
                    }
                } else {
                    VStack {
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
                                ForEach(localCartItems) { cartItem in
                                    CheckoutItemRow(
                                        cartItem: cartItem,
                                        onQuantityChange: { newQuantity in
                                            updateQuantity(for: cartItem, to: newQuantity)
                                        }
                                    )
                                }
                            }
                            .padding(.horizontal, 16)
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
                            HStack {
                                Button {
                                    dismiss()
                                } label: {
                                    Text("Back to Menu")
                                        .frame(maxWidth: .infinity)
                                }
                                .buttonStyle(.bordered)
                                .controlSize(.large)
                                .frame(maxWidth: .infinity)

                                Button(action: checkout) {
                                    Text("Check Out")
                                        .frame(maxWidth: .infinity)
                                }
                                .buttonStyle(.borderedProminent)
                                .tint(.green)
                                .controlSize(.large)
                            }
                            .padding(.horizontal, 20)
                        }
                        .padding(.bottom, 20)
                    }
                }
            }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Close", systemImage: "xmark") {
                        dismiss()
                    }
                }
            }
            .navigationTitle("Items in your Cart")
            .navigationBarTitleDisplayMode(.inline)
        }
        .navigationViewStyle(StackNavigationViewStyle())
        .onAppear {
            loadCartItems()
        }
    }

    private var totalPrice: Double {
        localCartItems.reduce(0) { $0 + $1.totalPrice }
    }

    private func loadCartItems() {
        // Convert cart items to CartItem array
        let groupedItems = Dictionary(grouping: cartItems, by: \.id)
        localCartItems = groupedItems.compactMap { _, items in
            guard let firstItem = items.first else { return nil }
            return CartItem(menuItem: firstItem, quantity: items.count)
        }
    }

    private func updateQuantity(for cartItem: CartItem, to newQuantity: Int) {
        if let index = localCartItems.firstIndex(where: { $0.id == cartItem.id }) {
            if newQuantity <= 0 {
                localCartItems.remove(at: index)
            } else {
                localCartItems[index].quantity = newQuantity
            }
        }

        // Sync changes back to binding
        syncToBinding()
    }

    private func syncToBinding() {
        // Convert CartItem array back to MenuItem array for binding
        var newCartItems: [MenuItem] = []
        for cartItem in localCartItems {
            for _ in 0..<cartItem.quantity {
                newCartItems.append(cartItem.menuItem)
            }
        }
        cartItems = newCartItems
    }

    private func checkout() {
        // Track checkout event
        let propertiesDictionary = [
            "Items in Cart": localCartItems.map { "\($0.menuItem.name) x\($0.quantity)" },
            "Total Price": totalPrice
        ] as [String: Any]

        KlaviyoSDK().create(event: .init(name: .startedCheckoutMetric, properties: propertiesDictionary))

        // Clear cart and dismiss
        localCartItems = []
        syncToBinding()
        dismiss()
    }
}

struct CheckoutItemRow: View {
    let cartItem: CartItem
    let onQuantityChange: (Int) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header with name and total price
            HStack {
                Text(cartItem.menuItem.name)
                    .font(.headline)
                    .fontWeight(.semibold)
                    .foregroundColor(.primary)

                Spacer()

                Text("$\(String(format: "%.2f", cartItem.totalPrice))")
                    .font(.headline)
                    .fontWeight(.bold)
                    .foregroundColor(.red)
            }

            // Quantity controls
            HStack {
                Text("Quantity: \(cartItem.quantity)")
                    .font(.subheadline)
                    .foregroundColor(.secondary)

                Spacer()

                HStack(spacing: 12) {
                    Button(action: {
                        onQuantityChange(cartItem.quantity - 1)
                    }) {
                        Image(systemName: "minus.circle.fill")
                            .foregroundColor(.red)
                            .font(.title2)
                    }

                    Text("\(cartItem.quantity)")
                        .font(.headline)
                        .fontWeight(.semibold)
                        .frame(minWidth: 30)

                    Button(action: {
                        onQuantityChange(cartItem.quantity + 1)
                    }) {
                        Image(systemName: "plus.circle.fill")
                            .foregroundColor(.green)
                            .font(.title2)
                    }
                }
            }
        }
        .padding(16)
        .background(.ultraThinMaterial)
        .cornerRadius(16)
    }
}

struct EmptyCartView: View {
    var dismiss: (() -> Void)?

    var body: some View {
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
                dismiss?()
            }

            Spacer()
        }
    }
}

// MARK: - Previews

@available(iOS 17.0, *)
#Preview("Checkout View") {
    @Previewable @State var cartItems: [MenuItem] = [
        MenuItem(
            name: "Fish & Chips",
            id: 1,
            description: "",
            price: 10.99,
            numberOfItems: 1
        )
    ]

    CheckoutView(cartItems: $cartItems)
}

#Preview("Empty Cart View") {
    EmptyCartView()
}

#Preview("Checkout Item Row") {
    let menuItem = MenuItem(
        name: "Fish & Chips",
        id: 1,
        description: "Lightly battered fish fillet, served with crispy golden chips and tartar sauce.",
        price: 10.99,
        numberOfItems: 1
    )

    CheckoutItemRow(cartItem: CartItem(menuItem: menuItem, quantity: 3), onQuantityChange: { _ in })
        .padding()
}
