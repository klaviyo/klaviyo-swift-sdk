//
//  CheckOutViewController.swift
//  KlaviyoSwift
//
//  Created by Katherine Keuper on 10/5/15.
//  Copyright © 2015 CocoaPods. All rights reserved.
//

import UIKit
import KlaviyoSwift

class CheckOutViewController: UIViewController {
    // MARK: public members
    var cart: Cart!
    
    // MARK: private members
    private var numberOfItemsInCart: [MenuItem : Int]!
    private var uniqueItemsArray: [MenuItem]!
    private var cartTotal: Double = 0
    @IBOutlet private weak var orderTotalLabel: UILabel!
    @IBOutlet private weak var tableview: UITableView!
    
    // MARK: view lifecycle
    override func viewDidLoad() {
        super.viewDidLoad()
        numberOfItemsInCart = cart.createUniqueDictionary
        uniqueItemsArray = cart.createCartItemsSet
        
        //Hide unused cells
        let tblfooter = UIView(frame: CGRect.zero)
        tableview.tableFooterView = tblfooter
        tableview.tableFooterView?.isHidden = true
        tableview.backgroundColor = UIColor.clear
        tableview.reloadData()
    }
    
    override func viewWillAppear(_ animated: Bool) {
        orderTotalLabel.text = "Order Total: \(cart.valueOfCart)"
    }

    override func didReceiveMemoryWarning() {
        super.didReceiveMemoryWarning()
    }
    
    // MARK: IBActions
    
    /*
    Check out button action
    Triggers checkout completed event & empties the cart
    */
    @IBAction func checkOutButton(_ sender: UIButton) {
        if cart.cartItems.isEmpty {
            return
        }
        
        // Empty the cartItems to 0 and save
        if !cart.cartItems.isEmpty {
            cart.cartItems.removeAll()
        }
        cart.saveCart()

        // Trigger "Checkout Completed" Event
        //TODO: check with Noah why SDK doesn't take in swift dictionary
        let propertiesDictionary = NSMutableDictionary()
        propertiesDictionary[Klaviyo.sharedInstance.KLEventTrackPurchasePlatform] = "iOS \(UIDevice.current.systemVersion)"
        propertiesDictionary["Total Price"] = cartTotal
        propertiesDictionary["Items Purchased"] = uniqueItemsArray.compactMap { $0.name }
        Klaviyo.sharedInstance.trackEvent(eventName: "Checkout Completed", properties: propertiesDictionary)
        
        // Trigger thank you modal view
        let alertController = UIAlertController(
            title: "Thank You!",
            message: "Thank you for your purchase! Your order is currently being processed and will be on its way shortly.",
            preferredStyle: .alert)
        let okAction = UIAlertAction(
            title: "OK",
            style: .default,
            handler: { void in
                //segue back to menu
                self.performSegue(withIdentifier: "checkoutMenuSegue", sender: self)
            }
        )
        alertController.addAction(okAction)
        self.present(alertController, animated: true, completion: nil)
    }
    
    @IBAction func removeItemButton(_ sender: AnyObject) {
        if cart.cartItems.isEmpty {
            return
        }
        
        let itemToRemove = uniqueItemsArray[sender.tag]
        if numberOfItemsInCart[itemToRemove] == 0 {
            return
        }
        cart.removeItem(itemToRemove)
        numberOfItemsInCart[itemToRemove] = numberOfItemsInCart[itemToRemove]! - 1
        orderTotalLabel.text = "Order Total: \(cart.valueOfCart)"
        tableview.reloadData()
    }
}

// MARK: table view data source and delegates

extension CheckOutViewController: UITableViewDataSource, UITableViewDelegate {
    func numberOfSections(in tableView: UITableView) -> Int {
        1
    }
    
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        uniqueItemsArray.count
    }
    
    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        guard let cell = tableView.dequeueReusableCell(withIdentifier: "cell") as? CheckOutTableViewCell
        else {
            fatalError("unable to dequeue cell - CheckOutTableViewCell. check cell identifier")
        }
        
        let menuItem = uniqueItemsArray[(indexPath as NSIndexPath).row]
        
        cell.selectionStyle = .none
        cell.itemName.text = menuItem.name
        
        let currentImage = UIImage(named: getCurrentImage(menuItem.name))
        cell.itemImage.image = currentImage
        cell.removeItemButton.tag = indexPath.row

        if let quantity = numberOfItemsInCart[menuItem] {
            cell.itemQuantity.text = "Quantitiy: \(quantity)"
            let total = menuItem.price * Double(quantity)
            cell.itemTotal.text = "Subtotal: $\(total)"
            cartTotal = cartTotal + total
        }

        return cell
    }
    
    private func getCurrentImage(_ itemName : String) -> String {
        switch itemName {
        case "Fish & Chips": return "Fish"
        case "Nicoise Salad": return "salad"
        case "Red Pork": return "pork"
        default: return "Noodles"
        }
    }
}
