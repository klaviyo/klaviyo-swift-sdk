//
//  Cart.swift
//  klMunchery
//
//  Created by Katherine Keuper on 9/28/15.
//  Copyright © 2015 Katherine Keuper. All rights reserved.
//

import Foundation

class Cart {
    var cartItems = [MenuItem]() // Cart is always initialized to empty

    init() {
        initializeCart()
    }

    /*
     Returns the quantity of a given item in the cart
     */
    func numberOfItemsInBasket(_ menuItem: MenuItem) -> Int {
        cartItems
            .filter { $0.name == menuItem.name }
            .reduce(into: 0) { res, _ in
                res += 1
            }
    }

    // Check standard defaults to see what is in the cart
    func initializeCart() {
        guard let items = UserDefaults.standard.object(forKey: "cartItems") as? [String]
        else {
            return
        }

        for name in items {
            switch name {
            case "Fish & Chips":
                cartItems.append(
                    MenuItem(
                        name: name,
                        id: 1, description: "Lightly battered & fried fresh cod and freshly cooked fries",
                        image: "battered_fish.jpg",
                        price: 10.99)
                )
            case "Nicoise Salad":
                cartItems.append(
                    MenuItem(
                        name: name,
                        id: 2, description: "Delicious salad of mixed greens, tuna nicoise and balasamic vinagrette",
                        image: "nicoise_salad.jpg",
                        price: 12.99)
                )
            case "Red Pork":
                cartItems.append(
                    MenuItem(
                        name: name,
                        id: 4, description: "Our take on the popular Chinese dish",
                        image: "red_pork.jpg",
                        price: 11.99)
                )
            case "Beef Bolognese":
                cartItems.append(
                    MenuItem(
                        name: name,
                        id: 5, description: "Traditional Italian Bolognese",
                        image: "bolognese_meal.jpg",
                        price: 10.99)
                )
            default:
                break
            }
        }
    }

    var valueOfCart: Double {
        createUniqueDictionary.reduce(into: 0.0) { res, item in
            res += item.key.price * Double(item.value)
        }
    }

    func saveCart() {
        // Save the cart items to bring back later
        let cartStrings = cartItems.map(\.name)
        UserDefaults.standard.set(cartStrings, forKey: "cartItems")
    }

    func removeItem(_ itemToRemove: MenuItem) {
        cartItems.removeAll(where: { $0 == itemToRemove })
    }

    var createUniqueDictionary: [MenuItem: Int] {
        var cartItemDictionary = [MenuItem: Int]()

        for item in cartItems {
            cartItemDictionary[item] = (cartItemDictionary[item] ?? 0) + 1
        }
        return cartItemDictionary
    }

    var createCartItemsSet: [MenuItem] {
        Array(Set(cartItems))
    }
}
