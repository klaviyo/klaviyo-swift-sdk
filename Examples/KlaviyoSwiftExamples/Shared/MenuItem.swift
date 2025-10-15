//
//  MenuItem.swift
//  klMunchery
//
//  Created by Katherine Keuper on 9/22/15.
//  Copyright © 2015 Katherine Keuper. All rights reserved.
//

import Foundation
import UIKit

struct MenuItem: Hashable, Codable {
    var name: String
    var id: Int
    var description: String
    var price = 10.99
    var numberOfItems = 0
}
