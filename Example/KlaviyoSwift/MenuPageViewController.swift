//
//  MenuPageViewController.swift
//  KlaviyoSwift
//
//  Created by Katherine Keuper on 10/5/15.
//  Copyright © 2015 CocoaPods. All rights reserved.
//


import UIKit
import KlaviyoSwift

class MenuPageViewController: UIViewController, UITableViewDelegate, UITableViewDataSource {
    
    @IBOutlet weak var cartIcon: UIButton!
    @IBOutlet weak var emailLabel: UILabel!
    @IBOutlet weak var zipcode: UILabel!
    @IBOutlet weak var tableView: UITableView!
    @IBOutlet weak var logOutButton: UIButton!
    
    var menuItems : [MenuItem]!
    var email : String?
    var zip : String?
    let cart : Cart = Cart()
    
    //Log out functionality
    @IBAction func logOut(sender: AnyObject) {
        // Present an action sheet to ask if they are sure
        let alertController = UIAlertController(title: "Log Out?", message: "Are you sure you want to log out? You will lose any items in your cart.", preferredStyle: UIAlertControllerStyle.ActionSheet)
        let cancelAction = UIAlertAction(title: "Nevermind", style: .Cancel, handler: nil)
        
        let logoutAction = UIAlertAction(title: "Log Out", style: .Default, handler: { (action) in
            let defaults = NSUserDefaults.standardUserDefaults()
            defaults.removeObjectForKey("email")
            defaults.removeObjectForKey("zip")
            defaults.removeObjectForKey("cartItems")
            self.performSegueWithIdentifier("logoutSegue", sender: self)
        })
        
        alertController.addAction(cancelAction)
        alertController.addAction(logoutAction)
        self.presentViewController(alertController, animated: true, completion: nil)
    }
    
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        retrieveSavedData()
        if menuItems == nil || menuItems.count == 0 {
            menuItems = [MenuItem]()
            initializeMenuItems()
        }
        
        if zip == nil{
            zipcode.text = "Missing Zipcode"
        } else {
            zipcode.text = zip!
        }
        if email != nil {
            emailLabel.hidden = false
            emailLabel.text = email!
            
            Klaviyo.sharedInstance.setUpUserEmail(email!)
        }
        
        if cart.cartItems.count == 0 {
            cartIcon.setImage(UIImage(named: "emptyCart"), forState: UIControlState.Normal)
        } else{
            cartIcon.setImage(UIImage(named: "FullCart"), forState: UIControlState.Normal)
        }
        
        // Add observer for when the app enters background
        NSNotificationCenter.defaultCenter().addObserver(self, selector: Selector("saveCartItems:"), name:UIApplicationDidEnterBackgroundNotification, object: nil)
    }
    
    override func viewWillAppear(animated: Bool) {
        if menuItems == nil {
            menuItems = [MenuItem]()
            initializeMenuItems()
        }
        
        if zip == nil{
            zipcode.text = "Missing Zipcode"
        } else {
            zipcode.text = zip!
        }
        if email != nil {
            emailLabel.hidden = false
            emailLabel.text = email!
        }
        tableView.reloadData()
    }
    
    
    func setKLAppOpenEvent() {
        if let validEmail = email {
            Klaviyo.sharedInstance.setUpUserEmail(validEmail)
        }
        Klaviyo.sharedInstance.trackEvent("Opened klM App")
    }
    
    func saveCartItems(notification: NSNotification) {
        cart.saveCart()
        
        if cart.cartItems.count > 0 {
            //Create a dictionary of the items not purchased
            let propertiesDictionary : NSMutableDictionary = NSMutableDictionary()
            
            var itemsPurchasedArray : [String] = [String]()
            let uniqueItemsArray = cart.createCartItemsSet()
            
            for item in uniqueItemsArray {
                itemsPurchasedArray.append(item.name)
            }
            
            propertiesDictionary["Items in Cart"] = itemsPurchasedArray
            
            //Checkout Started.. but no placed order #
            Klaviyo.sharedInstance.trackEvent("Abandoned Cart", properties: propertiesDictionary)
        }
    }
    
    @IBAction func addEmail(sender: AnyObject) {
        //present user with text box to add email & save
        let alertController = UIAlertController(title: "Add Email", message: "Please add your email", preferredStyle: UIAlertControllerStyle.Alert)
        
        let addEmailAction = UIAlertAction(title: "Submit", style: .Default) { (_) in
            let emailTextField = alertController.textFields![0] as UITextField
            self.email = emailTextField.text
            if let validEmail = self.email {
                Klaviyo.sharedInstance.setUpUserEmail(validEmail)
                self.emailLabel.text = "Email: \(validEmail)"
            }
        }
        
        let cancelAction = UIAlertAction(title: "Cancel", style: .Cancel) { (_) in }
        
        alertController.addTextFieldWithConfigurationHandler { (textfield) in
            textfield.placeholder = "email"
            textfield.keyboardType = UIKeyboardType.Twitter
        }
        
        alertController.addAction(addEmailAction)
        alertController.addAction(cancelAction)
        
        self.presentViewController(alertController, animated: true, completion: nil)
    }
    
    @IBAction func removeItem(sender: AnyObject) {
        if cart.cartItems.count == 0 {
            cartIcon.setImage(UIImage(named: "emptyCart"), forState: UIControlState.Normal)
            return
        }
        let itemToRemove = menuItems[sender.tag]
        cart.removeItem(itemToRemove)
        tableView.reloadData()
    }
    
    func initializeMenuItems() {
        if menuItems.count == 0 {
            menuItems.append(MenuItem(name: "Fish & Chips", description: "Lightly battered & fried fresh cod and freshly cooked fries", imageURL: "battered_fish.jpg", price: 10.99, id: 1))
            menuItems.append(MenuItem(name: "Nicoise Salad", description: "Delicious salad of mixed greens, tuna nicoise and balasamic vinagrette", imageURL: "nicoise_salad.jpg", price: 12.99, id:2))
            menuItems.append(MenuItem(name: "Red Pork", description: "Our take on the popular Chinese dish", imageURL: "red_pork.jpg", price: 11.99, id:3))
            menuItems.append(MenuItem(name: "Beef Bolognese", description: "Traditional Italian Bolognese", imageURL: "bolognese_meal.jpg", price: 10.99, id:4))
        }
    }
    
    func retrieveSavedData() {
        let defaults = NSUserDefaults.standardUserDefaults()
        zip = defaults.objectForKey("zip") as? String
        email = defaults.objectForKey("email") as? String
    }
    
    // Add a modal popup that lets users add their zip code: Can't add text to action sheet so this currently uses the alert controlelr
    @IBAction func addZipcode(sender: UIButton) {
        let alertController = UIAlertController(title: "Add Zipcode", message: "Please add your zipcode", preferredStyle: UIAlertControllerStyle.Alert)
        
        let addZipAction = UIAlertAction(title: "Zip", style: .Default) { (_) in
            let zipTextField = alertController.textFields![0] as UITextField
            self.zip = zipTextField.text
        }
        
        let cancelAction = UIAlertAction(title: "Cancel", style: .Cancel) { (_) in }
        
        alertController.addTextFieldWithConfigurationHandler { (textfield) in
            textfield.placeholder = "zip"
            textfield.keyboardType = .NumberPad
        }
        
        alertController.addAction(addZipAction)
        alertController.addAction(cancelAction)
        
        self.presentViewController(alertController, animated: true, completion: nil)
    }
    
    override func didReceiveMemoryWarning() {
        super.didReceiveMemoryWarning()
    }
    
    func numberOfSectionsInTableView(tableView: UITableView) -> Int {
        return 1
    }
    
    func tableView(tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return menuItems.count
    }
    
    func tableView(tableView: UITableView, cellForRowAtIndexPath indexPath: NSIndexPath) -> UITableViewCell {
        
        var cell : MenuItemTableViewCell? = tableView.dequeueReusableCellWithIdentifier("MenuItem") as? MenuItemTableViewCell
        
        if cell == nil {
            cell = UITableViewCell(style: UITableViewCellStyle.Default, reuseIdentifier: "MenuItem") as? MenuItemTableViewCell
        }
        
        cell?.selectionStyle = UITableViewCellSelectionStyle.None
        
        let menuItem = menuItems[indexPath.row]
        cell?.itemName.text = menuItem.name
        cell?.itemDescription.text = menuItem.description
        
        let currentImage = UIImage(named: returnImagePath(menuItem.name))
        cell?.itemImage.image = currentImage
        cell?.addToCartButton.tag = indexPath.row
        cell?.removeItemButton.tag = indexPath.row
        cell?.numberOfItemsLabel.text = "Quantity: \(cart.numberOfItemsInBasket(menuItem))"
        cell?.itemPrice.text = "($\(menuItem.price))"
        return cell!
    }
    
    func returnImagePath(imageName : String)->String {
        switch imageName {
        case "Fish & Chips": return "battered_fish.jpg"
        case "Nicoise Salad": return "nicoise_salad.jpg"
        case "Red Pork": return "red_pork.jpg"
        default: return "bolognese_meal.jpg"
        }
    }
    
    @IBAction func viewCart(sender: UIButton) {
        var message = ""
        if cart.cartItems.count == 0 {
            message = "Your cart is empty! Please add some items before you check out."
        } else {
            message = "You have \(cart.cartItems.count) item(s) in your cart. Are you ready to check out?"
        }
        
        let alertController = UIAlertController(title: "Your Cart", message: message, preferredStyle: .Alert)
        
        let cancelAction = UIAlertAction(title: "Cancel", style: .Cancel, handler: nil)
        alertController.addAction(cancelAction)
        
        let checkoutAction = UIAlertAction(title: "Check Out", style: .Default) { (action) in
            if self.cart.cartItems.count > 0 {
                self.performSegueWithIdentifier("checkOutSegue", sender: sender)
            } else {
                alertController.message = "Please add items to your cart first"
            }
        }
        alertController.addAction(checkoutAction)
        self.presentViewController(alertController, animated: true, completion: nil)
        
    }
    
    @IBAction func addToCart(sender: UIButton) {
        if cart.cartItems.count > 0 {
            cartIcon.setImage(UIImage(named: "FullCart"), forState: UIControlState.Normal)
        }
        cart.cartItems.append(menuItems[sender.tag])
        tableView.reloadData()
    }
    
    override func prepareForSegue(segue: UIStoryboardSegue, sender: AnyObject?) {
        if segue.identifier == "logoutSegue" {
            //let vc = segue.destinationViewController as! ViewController
        } else {
            let vc = segue.destinationViewController as! CheckOutViewController
            vc.cart = cart
            //Trigger checkout event
            Klaviyo.sharedInstance.trackEvent("Checkout Started")
        }
    }
    
    @IBAction func unwindToMenuPageViewController(segue: UIStoryboardSegue) {
        print("Successfully unwound. Items in cart: \(cart.cartItems.count)")
    }
    
    
    
}
