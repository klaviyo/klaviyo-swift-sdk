//
//  Cart.swift
//  klMunchery
//
//  Created by Katherine Keuper on 9/28/15.
//  Copyright © 2015 Katherine Keuper. All rights reserved.
//

import Foundation

class Cart {
    var cartItems : [MenuItem] = [] // Cart is always initialized to empty
    
    init() {
        initializeCart()
    }
    
    /*
    Returns the quantity of a given item in the cart
    */
    func numberOfItemsInBasket(_ menuItem: MenuItem)->Int {
        var numberOfItems = 0
        
        for item in cartItems {
            if item.name == menuItem.name {
                numberOfItems += 1
            }
        }
        
        return numberOfItems
    }
    
    // Check standard defaults to see what is in the cart
    func initializeCart() {
        if let items = UserDefaults.standard.object(forKey: "cartItems") as? [String] {
            for name in items {
                switch name {
                case "Fish & Chips": cartItems.append(MenuItem(name: name, description: "Lightly battered & fried fresh cod and freshly cooked fries", imageURL: "battered_fish.jpg", price: 10.99, id: 1))
                case "Nicoise Salad": cartItems.append(MenuItem(name: name, description: "Delicious salad of mixed greens, tuna nicoise and balasamic vinagrette", imageURL: "nicoise_salad.jpg", price: 12.99, id: 2))
                case "Red Pork": cartItems.append(MenuItem(name: name, description: "Our take on the popular Chinese dish", imageURL: "red_pork.jpg", price: 11.99, id:4))
                case "Beef Bolognese": cartItems.append(MenuItem(name: name, description: "Traditional Italian Bolognese", imageURL: "bolognese_meal.jpg", price: 10.99, id:5))
                default: return
                }
            }
        }
        
    }
    
    func valueOfCart()->Double {
        let numberOfItems = createUniqueArray()
        var total = 0.0
        
        for (key,value) in numberOfItems {
            let amount = key.price * Double(value)
            total = total + amount
        }
        return total
    }
    
    func cartItemNames()->[String] {
        var itemNames = [String]()
        for item in cartItems {
            itemNames.append(item.name)
        }
        return itemNames
    }
    
    func saveCart() {
        //Save the cart items to bring back later
        var cartStrings = [String]()
        for item in cartItems {
            cartStrings.append(item.name)
        }
        let defaults = UserDefaults.standard
        defaults.set(cartStrings, forKey: "cartItems")
    }
    
    func removeItem(_ itemToRemove : MenuItem) {
        var index = 0
        for item in cartItems {
            if item.name == itemToRemove.name {
                cartItems.remove(at: index)
                return
            }
            index += 1
        }
    }
    
    // Creates a new cart array with the total number of items
    func createNumberOfCounts()->NSDictionary {
        var numberOfItemsInCart = [String: Int]()
        
        //Create a dictionary to hold the counts
        for item in cartItems {
            numberOfItemsInCart[item.name] = (numberOfItemsInCart[item.name] ?? 0) + 1
        }
        return numberOfItemsInCart as NSDictionary
    }
    
    func createUniqueArray()->[MenuItem: Int] {
        var cartItemDictionary = [MenuItem : Int]()
        
        for item in cartItems {
            cartItemDictionary[item] = (cartItemDictionary[item] ?? 0) + 1
        }
        return cartItemDictionary
    }
    
    func createCartItemsSet()->[MenuItem] {
        return  Array(Set(cartItems))
    }
}
