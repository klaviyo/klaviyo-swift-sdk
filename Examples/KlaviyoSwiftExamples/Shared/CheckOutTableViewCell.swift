//
//  CheckOutTableViewCell.swift
//  klMunchery
//
//  Created by Katherine Keuper on 9/28/15.
//  Copyright © 2015 Katherine Keuper. All rights reserved.
//

import UIKit

class CheckOutTableViewCell: UITableViewCell {
    @IBOutlet var removeItemButton: UIButton!
    @IBOutlet var itemTotal: UILabel!
    @IBOutlet var itemQuantity: UILabel!
    @IBOutlet var itemName: UILabel!
    @IBOutlet var itemImage: UIImageView!

    override func awakeFromNib() {
        super.awakeFromNib()
    }

    override func setSelected(_ selected: Bool, animated: Bool) {
        super.setSelected(selected, animated: animated)
    }
}
