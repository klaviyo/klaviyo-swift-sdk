//
//  User.swift
//  klMunchery
//
//  Created by Katherine Keuper on 9/24/15.
//  Copyright © 2015 Katherine Keuper. All rights reserved.
//

import Foundation

class User : NSObject {
    var firstName : String?
    var lastName : String?
    var zipcode : String!
    var email : String?
    var cart : [MenuItem]?
    var isLoggedIn : Bool?
    
}