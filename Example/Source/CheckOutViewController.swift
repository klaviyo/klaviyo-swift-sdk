//
//  CheckOutViewController.swift
//  KlaviyoSwift
//
//  Created by Katherine Keuper on 10/5/15.
//  Copyright © 2015 CocoaPods. All rights reserved.
//

import UIKit
import KlaviyoSwift

class CheckOutViewController: UIViewController, UITableViewDataSource, UITableViewDelegate {
    
    var cart : Cart!
    var numberOfItemsInCart : [MenuItem : Int]!
    var uniqueItemsArray : [MenuItem]!
    var cartTotal : Double = 0
    @IBOutlet weak var orderTotalLabel: UILabel!
    @IBOutlet weak var tableview: UITableView!
    
    override func viewDidLoad() {
        super.viewDidLoad()
        numberOfItemsInCart = cart.createUniqueArray()
        uniqueItemsArray = cart.createCartItemsSet()
        
        //Hide unused cells
        let tblfooter = UIView(frame: CGRect.zero)
        tableview.tableFooterView = tblfooter
        tableview.tableFooterView?.isHidden = true
        tableview.backgroundColor = UIColor.clear
        tableview.reloadData()
        
    }
    
    override func viewWillAppear(_ animated: Bool) {
        orderTotalLabel.text = "Order Total: \(cart.valueOfCart())"
    }
    override func didReceiveMemoryWarning() {
        super.didReceiveMemoryWarning()
    }
    
    /*
    Check out button action
    Triggers checkout completed event & empties the cart
    */
    @IBAction func checkOutButton(_ sender: UIButton) {
        if cart.cartItems.count == 0 {return}
        
        // Empty the cartItems to 0 and save
        if cart.cartItems.count > 0 {
            cart.cartItems.removeAll()
        }
        cart.saveCart()
        
        
        // Trigger "Checkout Completed" Event
        let propertiesDictionary : NSMutableDictionary = NSMutableDictionary()
        propertiesDictionary[Klaviyo.sharedInstance.KLEventTrackPurchasePlatform] = "iOS \(UIDevice.current.systemVersion)"
        propertiesDictionary["Total Price"] = cartTotal
        
        var itemsPurchasedArray : [String] = [String]()
        for item in uniqueItemsArray {
            itemsPurchasedArray.append(item.name)
        }
        
        propertiesDictionary["Items Purchased"] = itemsPurchasedArray
        Klaviyo.sharedInstance.trackEvent(eventName: "Checkout Completed", properties: propertiesDictionary)
        
        // Trigger thank you modal view
        let alertController = UIAlertController(title: "Thank You!", message: "Thank you for your purchase! Your order is currently being processed and will be on its way shortly.", preferredStyle: UIAlertController.Style.alert)
        let okAction = UIAlertAction(title: "OK", style: .default, handler: { void in
            //segue back to menu
            self.performSegue(withIdentifier: "checkoutMenuSegue", sender: self)
        })
        alertController.addAction(okAction)
        self.present(alertController, animated: true, completion: nil)
    }
    
    func numberOfItemsInBasket(_ menuItem: MenuItem)->Int {
        // Iterate through the cart and increment the counter each time an instance appears
        var numberOfItems = 0
        
        for item in cart.cartItems {
            if item.name == menuItem.name {
                numberOfItems += 1
            }
        }
        
        return numberOfItems
    }
    
    func numberOfSections(in tableView: UITableView) -> Int {
        return 1
    }
    
    @IBAction func removeItemButton(_ sender: AnyObject) {
        if cart.cartItems.count == 0 {return}
        let itemToRemove = uniqueItemsArray[sender.tag]
        if numberOfItemsInCart[itemToRemove] == 0 {return}
        cart.removeItem(itemToRemove)
        numberOfItemsInCart[itemToRemove] = numberOfItemsInCart[itemToRemove]! - 1
        orderTotalLabel.text = "Order Total: \(cart.valueOfCart())"
        tableview.reloadData()
    }
    
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return uniqueItemsArray.count
    }
    
    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        
        var cell : CheckOutTableViewCell? = tableView.dequeueReusableCell(withIdentifier: "cell") as? CheckOutTableViewCell
        
        if cell == nil {
            cell = UITableViewCell(style: UITableViewCell.CellStyle.default, reuseIdentifier: "cell") as? CheckOutTableViewCell
        }
        
        let menuItem = uniqueItemsArray[(indexPath as NSIndexPath).row]
        
        cell?.selectionStyle = UITableViewCell.SelectionStyle.none
        cell?.itemName.text = menuItem.name
        
        let currentImage = getCurrentImage(menuItem.name)
        cell?.itemImage.image = currentImage
        
        cell?.removeItemButton.tag = (indexPath as NSIndexPath).row
        let quantity = numberOfItemsInCart[menuItem]
        cell?.itemQuantity.text = "Quantitiy: \(quantity!)"
        let total = menuItem.price*Double(quantity!)
        cell?.itemTotal.text = "Subtotal: $\(total)"
        cartTotal = cartTotal + total
        return cell!
    }
    
    
    func getCurrentImage(_ itemName : String)->UIImage?{
        switch itemName {
        case "Fish & Chips": return UIImage(named: "Fish")
        case "Nicoise Salad": return UIImage(named: "salad")
        case "Red Pork": return UIImage(named: "pork")
        default: return UIImage(named: "Noodles")
        }
    }
    
}
