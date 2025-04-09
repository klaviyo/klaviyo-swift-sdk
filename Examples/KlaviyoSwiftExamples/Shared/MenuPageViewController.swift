//
//  MenuPageViewController.swift
//  KlaviyoSwift
//
//  Created by Katherine Keuper on 10/5/15.
//  Copyright © 2015 CocoaPods. All rights reserved.
//

import KlaviyoSwift
import UIKit

class MenuPageViewController: UIViewController {
    // MARK: public members

    var menuItems: [MenuItem]!
    var email: String?
    var zip: String?

    // MARK: private members

    @IBOutlet private var cartIcon: UIButton!
    @IBOutlet private var emailLabel: UILabel!
    @IBOutlet private var zipcode: UILabel!
    @IBOutlet private var tableView: UITableView!
    @IBOutlet private var logOutButton: UIButton!

    private let cart: Cart = .init()

    // MARK: view lifecycle methods

    override func viewDidLoad() {
        super.viewDidLoad()

        // example of registering for forms to display on navigating to a specific view
        KlaviyoSDK().registerForInAppForms()

        retrieveSavedData()
        setKLAppOpenEvent()
        if menuItems == nil || menuItems.isEmpty {
            menuItems = [MenuItem]()
            initializeMenuItems()
        }

        if let zip = zip {
            zipcode.text = zip
        } else {
            zipcode.text = "Missing Zipcode"
        }

        if let email = email {
            emailLabel.isHidden = false
            emailLabel.text = email

            KlaviyoSDK().set(email: email)
        }

        cartIcon.setImage(
            UIImage(
                named: cart.cartItems.isEmpty ? "emptyCart" : "FullCart"
            ),
            for: UIControl.State()
        )

        // Add observer for when the app enters background
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(saveCartItems),
            name: UIApplication.didEnterBackgroundNotification, object: nil
        )
    }

    override func viewWillAppear(_ animated: Bool) {
        if menuItems == nil {
            menuItems = [MenuItem]()
            initializeMenuItems()
        }

        if let zip = zip {
            zipcode.text = zip
        } else {
            zipcode.text = "Missing Zipcode"
        }
        if let email = email {
            emailLabel.isHidden = false
            emailLabel.text = email
        }
        tableView.reloadData()
    }

    override func prepare(for segue: UIStoryboardSegue, sender: Any?) {
        if segue.identifier == "logoutSegue" {
            // let vc = segue.destinationViewController as! ViewController
        } else {
            if let vc = segue.destination as? CheckOutViewController {
                vc.cart = cart
                // EXAMPLE: of triggering checkout event
                KlaviyoSDK().create(event: .init(name: .startedCheckoutMetric))
            }
        }
    }

    // MARK: IB Action

    @IBAction func addEmail(_ sender: AnyObject) {
        // present user with text box to add email & save
        let alertController = UIAlertController(
            title: "Add Email",
            message: "Please add your email",
            preferredStyle: .alert
        )

        let addEmailAction = UIAlertAction(
            title: "Submit",
            style: .default
        ) { _ in
            let emailTextField = alertController.textFields![0] as UITextField
            self.email = emailTextField.text
            if let email = self.email {
                // EXAMPLE: of when the users changes or an existing user changes their email we update the SDK with the new email.
                KlaviyoSDK().set(email: email)
                self.emailLabel.text = "Email: \(email)"
            }
        }

        let cancelAction = UIAlertAction(
            title: "Cancel",
            style: .cancel
        )

        alertController.addTextField { textfield in
            textfield.placeholder = "email"
            textfield.keyboardType = .emailAddress
        }

        alertController.addAction(addEmailAction)
        alertController.addAction(cancelAction)

        present(alertController, animated: true, completion: nil)
    }

    @IBAction func removeItem(_ sender: AnyObject) {
        if cart.cartItems.isEmpty {
            cartIcon.setImage(UIImage(named: "emptyCart"), for: UIControl.State())
            return
        }
        let itemToRemove = menuItems[sender.tag]
        cart.removeItem(itemToRemove)
        tableView.reloadData()
    }

    @IBAction func logOut(_ sender: AnyObject) {
        // Present an action sheet to ask if they are sure
        let alertController = UIAlertController(
            title: "Log Out?",
            message: "Are you sure you want to log out? You will lose any items in your cart.",
            preferredStyle: .actionSheet
        )
        let cancelAction = UIAlertAction(
            title: "Nevermind",
            style: .cancel
        )

        let logoutAction = UIAlertAction(
            title: "Log Out",
            style: .default,
            handler: { _ in
                let defaults = UserDefaults.standard
                defaults.removeObject(forKey: "email")
                defaults.removeObject(forKey: "zip")
                defaults.removeObject(forKey: "cartItems")
                self.performSegue(withIdentifier: "logoutSegue", sender: self)
            }
        )

        alertController.addAction(cancelAction)
        alertController.addAction(logoutAction)
        present(alertController, animated: true, completion: nil)
    }

    // Add a modal popup that lets users add their zip code: Can't add text to action sheet so this currently uses the alert controlelr
    @IBAction func addZipcode(_ sender: UIButton) {
        let alertController = UIAlertController(
            title: "Add Zipcode",
            message: "Please add your zipcode",
            preferredStyle: .alert
        )

        let addZipAction = UIAlertAction(
            title: "Update",
            style: .default,
            handler: { _ in
                let zipTextField = alertController.textFields![0] as UITextField
                self.zip = zipTextField.text
                self.zipcode.text = zipTextField.text
            }
        )

        let cancelAction = UIAlertAction(
            title: "Cancel",
            style: .cancel
        )

        alertController.addTextField { textfield in
            textfield.placeholder = "zip"
            textfield.keyboardType = .numberPad
        }

        alertController.addAction(addZipAction)
        alertController.addAction(cancelAction)

        present(alertController, animated: true, completion: nil)
    }

    @IBAction func viewCart(_ sender: UIButton) {
        let message = cart.cartItems.isEmpty ?
            "Your cart is empty! Please add some items before you check out." :
            "You have \(cart.cartItems.count) item(s) in your cart. Are you ready to check out?"

        let alertController = UIAlertController(
            title: "Your Cart",
            message: message,
            preferredStyle: .alert
        )

        let cancelAction = UIAlertAction(
            title: "Cancel",
            style: .cancel
        )
        alertController.addAction(cancelAction)

        let checkoutAction = UIAlertAction(
            title: "Check Out",
            style: .default,
            handler: { _ in
                if !self.cart.cartItems.isEmpty {
                    self.performSegue(withIdentifier: "checkOutSegue", sender: sender)
                } else {
                    alertController.message = "Please add items to your cart first"
                }
            }
        )
        alertController.addAction(checkoutAction)
        present(alertController, animated: true, completion: nil)
    }

    @IBAction func addToCart(_ sender: UIButton) {
        if !cart.cartItems.isEmpty {
            cartIcon.setImage(UIImage(named: "FullCart"), for: UIControl.State())
        }
        cart.cartItems.append(menuItems[sender.tag])

        if !cart.cartItems.isEmpty {
            // Create a dictionary of the items not purchased
            let propertiesDictionary = [
                "Items in Cart": cart.createCartItemsSet.map(\.name)
            ]

            // EXAMPLE : of Checkout Started.. but no placed order #
            KlaviyoSDK().create(event: .init(name: .startedCheckoutMetric, properties: propertiesDictionary))
        }

        tableView.reloadData()
    }

    @IBAction func unwindToMenuPageViewController(_ segue: UIStoryboardSegue) {
        print("Successfully unwound. Items in cart: \(cart.cartItems.count)")
    }

    // MARK: private methods

    private func retrieveSavedData() {
        let defaults = UserDefaults.standard
        zip = defaults.object(forKey: "zip") as? String
        email = defaults.object(forKey: "email") as? String
    }

    @objc
    private func saveCartItems(_ notification: Notification) {
        cart.saveCart()
    }

    private func setKLAppOpenEvent() {
        if let email = email {
            KlaviyoSDK().set(email: email)
        }
        // EXAMPLE: this is when the user opens the app consectective time
        KlaviyoSDK().create(event: .init(name: .customEvent("Opened klM App")))
    }

    private func initializeMenuItems() {
        if menuItems.isEmpty {
            menuItems.append(
                MenuItem(
                    name: "Fish & Chips",
                    id: 1, description: "Lightly battered & fried fresh cod and freshly cooked fries",
                    image: "battered_fish.jpg",
                    price: 10.99
                )
            )
            menuItems.append(
                MenuItem(
                    name: "Nicoise Salad",
                    id: 2, description: "Delicious salad of mixed greens, tuna nicoise and balasamic vinagrette",
                    image: "nicoise_salad.jpg",
                    price: 12.99
                )
            )
            menuItems.append(
                MenuItem(
                    name: "Red Pork",
                    id: 3, description: "Our take on the popular Chinese dish",
                    image: "red_pork.jpg",
                    price: 11.99
                )
            )
            menuItems.append(
                MenuItem(
                    name: "Beef Bolognese",
                    id: 4, description: "Traditional Italian Bolognese",
                    image: "bolognese_meal.jpg",
                    price: 10.99
                )
            )
        }
    }
}

// MARK: Table view datasource and delegates

extension MenuPageViewController: UITableViewDataSource, UITableViewDelegate {
    func numberOfSections(in tableView: UITableView) -> Int { 1 }

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        menuItems.count
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        guard let cell = tableView.dequeueReusableCell(withIdentifier: "MenuItem") as? MenuItemTableViewCell
        else {
            fatalError("unable to dequeue cell - MenuItemTableViewCell. check cell identifier")
        }

        cell.selectionStyle = .none

        let menuItem = menuItems[indexPath.row]
        cell.itemName.text = menuItem.name
        cell.itemDescription.text = menuItem.description

        let currentImage = UIImage(named: returnImagePath(menuItem.name))
        cell.itemImage.image = currentImage
        cell.addToCartButton.tag = (indexPath as NSIndexPath).row
        cell.removeItemButton.tag = (indexPath as NSIndexPath).row
        cell.numberOfItemsLabel.text = "Quantity: \(cart.numberOfItemsInBasket(menuItem))"
        cell.itemPrice.text = "($\(menuItem.price))"

        return cell
    }

    private func returnImagePath(_ imageName: String) -> String {
        switch imageName {
        case "Fish & Chips": return "battered_fish.jpg"
        case "Nicoise Salad": return "nicoise_salad.jpg"
        case "Red Pork": return "red_pork.jpg"
        default: return "bolognese_meal.jpg"
        }
    }
}
