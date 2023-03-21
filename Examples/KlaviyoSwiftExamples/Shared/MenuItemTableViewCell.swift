//
//  MenuItemTableViewCell.swift
//  klMunchery
//
//  Created by Katherine Keuper on 9/22/15.
//  Copyright © 2015 Katherine Keuper. All rights reserved.
//

import UIKit

class MenuItemTableViewCell: UITableViewCell {
    @IBOutlet weak var itemPrice: UILabel!
    @IBOutlet weak var itemDescription: UILabel!
    @IBOutlet weak var itemImage: UIImageView!
    @IBOutlet weak var itemName: UILabel!
    @IBOutlet weak var addToCartButton: UIButton!
    @IBOutlet weak var removeItemButton: UIButton!
    @IBOutlet weak var numberOfItemsLabel: UILabel!
    
    override func awakeFromNib() {
        super.awakeFromNib()
        // Initialization code
        itemImage.frame = CGRect(x:0, y:0, width: 100, height: 100)
        itemImage.image = UIImage(contentsOfFile: "monkey.png")
    }

    override func setSelected(_ selected: Bool, animated: Bool) {
        super.setSelected(selected, animated: animated)
    }
}
