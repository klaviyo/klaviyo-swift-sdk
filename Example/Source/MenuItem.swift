//
//  MenuItem.swift
//  klMunchery
//
//  Created by Katherine Keuper on 9/22/15.
//  Copyright © 2015 Katherine Keuper. All rights reserved.
//

import Foundation
import UIKit

// Implement hashable protocol
func ==(lhs: MenuItem, rhs: MenuItem)->Bool {
    return lhs.hashValue == rhs.hashValue
}

class MenuItem: Hashable  {
    
    var name : String!
    var id : Int!
    var description : String!
    var image : String!
    var price = 10.99
    var numberOfItems = 0
    var hashValue : Int {
        get {
            return self.id
        }
    }
    
    init(name: String, description: String, imageURL: String, price: Double, id : Int) {
        self.name = name
        self.description = description
        self.image = imageURL
        self.price = price
        self.id = id
    }
    
}

