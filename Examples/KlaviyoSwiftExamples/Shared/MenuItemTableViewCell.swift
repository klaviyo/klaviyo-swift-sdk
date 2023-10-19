//
//  MenuItemTableViewCell.swift
//  klMunchery
//
//  Created by Katherine Keuper on 9/22/15.
//  Copyright © 2015 Katherine Keuper. All rights reserved.
//

import UIKit

class MenuItemTableViewCell: UITableViewCell {
    @IBOutlet var itemPrice: UILabel!
    @IBOutlet var itemDescription: UILabel!
    @IBOutlet var itemImage: UIImageView!
    @IBOutlet var itemName: UILabel!
    @IBOutlet var addToCartButton: UIButton!
    @IBOutlet var removeItemButton: UIButton!
    @IBOutlet var numberOfItemsLabel: UILabel!

    override func awakeFromNib() {
        super.awakeFromNib()
        // Initialization code
        itemImage.frame = CGRect(x: 0, y: 0, width: 100, height: 100)
        itemImage.image = UIImage(contentsOfFile: "monkey.png")
    }
}
