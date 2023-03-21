//
//  CheckOutTableViewCell.swift
//  klMunchery
//
//  Created by Katherine Keuper on 9/28/15.
//  Copyright © 2015 Katherine Keuper. All rights reserved.
//

import UIKit

class CheckOutTableViewCell: UITableViewCell {
    @IBOutlet weak var removeItemButton: UIButton!
    @IBOutlet weak var itemTotal: UILabel!
    @IBOutlet weak var itemQuantity: UILabel!
    @IBOutlet weak var itemName: UILabel!
    @IBOutlet weak var itemImage: UIImageView!
    
    override func awakeFromNib() {
        super.awakeFromNib()
    }

    override func setSelected(_ selected: Bool, animated: Bool) {
        super.setSelected(selected, animated: animated)
    }
}
