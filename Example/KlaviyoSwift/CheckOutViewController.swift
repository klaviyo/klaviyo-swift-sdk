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
        let tblfooter = UIView(frame: CGRectZero)
        tableview.tableFooterView = tblfooter
        tableview.tableFooterView?.hidden = true
        tableview.backgroundColor = UIColor.clearColor()
        tableview.reloadData()
        
    }
    
    override func viewWillAppear(animated: Bool) {
        orderTotalLabel.text = "Order Total: \(cart.valueOfCart())"
    }
    override func didReceiveMemoryWarning() {
        super.didReceiveMemoryWarning()
    }
    
    /*
    Check out button action
    Triggers checkout completed event & empties the cart
    */
    @IBAction func checkOutButton(sender: UIButton) {
        if cart.cartItems.count == 0 {return}
        
        // Empty the cartItems to 0 and save
        if cart.cartItems.count > 0 {
            cart.cartItems.removeAll()
        }
        cart.saveCart()
        
        
        // Trigger "Checkout Completed" Event
        let propertiesDictionary : NSMutableDictionary = NSMutableDictionary()
        propertiesDictionary[Klaviyo.sharedInstance.KLEventTrackPurchasePlatform] = "iOS \(UIDevice.currentDevice().systemVersion)"
        propertiesDictionary["Total Price"] = cartTotal
        
        var itemsPurchasedArray : [String] = [String]()
        for item in uniqueItemsArray {
            itemsPurchasedArray.append(item.name)
        }
        
        propertiesDictionary["Items Purchased"] = itemsPurchasedArray
        Klaviyo.sharedInstance.trackEvent("Checkout Completed", properties: propertiesDictionary)
        
        // Trigger thank you modal view
        let alertController = UIAlertController(title: "Thank You!", message: "Thank you for your purchase! Your order is currently being processed and will be on its way shortly.", preferredStyle: UIAlertControllerStyle.Alert)
        let okAction = UIAlertAction(title: "OK", style: .Default, handler: { void in
            //segue back to menu
            self.performSegueWithIdentifier("checkoutMenuSegue", sender: self)
        })
        alertController.addAction(okAction)
        self.presentViewController(alertController, animated: true, completion: nil)
    }
    
    func numberOfItemsInBasket(menuItem: MenuItem)->Int {
        // Iterate through the cart and increment the counter each time an instance appears
        var numberOfItems = 0
        
        for item in cart.cartItems {
            if item.name == menuItem.name {
                numberOfItems++
            }
        }
        
        return numberOfItems
    }
    
    func numberOfSectionsInTableView(tableView: UITableView) -> Int {
        return 1
    }
    
    @IBAction func removeItemButton(sender: AnyObject) {
        if cart.cartItems.count == 0 {return}
        let itemToRemove = uniqueItemsArray[sender.tag]
        if numberOfItemsInCart[itemToRemove] == 0 {return}
        cart.removeItem(itemToRemove)
        numberOfItemsInCart[itemToRemove] = numberOfItemsInCart[itemToRemove]! - 1
        orderTotalLabel.text = "Order Total: \(cart.valueOfCart())"
        tableview.reloadData()
    }
    
    func tableView(tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return uniqueItemsArray.count
    }
    
    func tableView(tableView: UITableView, cellForRowAtIndexPath indexPath: NSIndexPath) -> UITableViewCell {
        
        var cell : CheckOutTableViewCell? = tableView.dequeueReusableCellWithIdentifier("cell") as? CheckOutTableViewCell
        
        if cell == nil {
            cell = UITableViewCell(style: UITableViewCellStyle.Default, reuseIdentifier: "cell") as? CheckOutTableViewCell
        }
        
        let menuItem = uniqueItemsArray[indexPath.row]
        
        cell?.selectionStyle = UITableViewCellSelectionStyle.None
        cell?.itemName.text = menuItem.name
        
        let currentImage = getCurrentImage(menuItem.name)
        cell?.itemImage.image = currentImage
        
        cell?.removeItemButton.tag = indexPath.row
        let quantity = numberOfItemsInCart[menuItem]
        cell?.itemQuantity.text = "Quantitiy: \(quantity!)"
        let total = menuItem.price*Double(quantity!)
        cell?.itemTotal.text = "Subtotal: $\(total)"
        cartTotal = cartTotal + total
        return cell!
    }
    
    
    func getCurrentImage(itemName : String)->UIImage?{
        switch itemName {
        case "Fish & Chips": return UIImage(named: "fish")
        case "Nicoise Salad": return UIImage(named: "salad")
        case "Red Pork": return UIImage(named: "pork")
        default: return UIImage(named: "noodles")
        }
    }
    
}
