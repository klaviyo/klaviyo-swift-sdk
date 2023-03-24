//
//  ViewController.swift
//  KlaviyoSwift
//
//  Created by Katherine Keuper on 10/5/15.
//  Copyright © 2015 CocoaPods. All rights reserved.
//

import KlaviyoSwift
import UIKit

class ViewController: UIViewController {
    var menuItems = [MenuItem]()
    var zipCode: String?
    var emailAddr: String?
    var firstName: String?
    var lastName: String?
    var cartItems: [MenuItem]?
    @IBOutlet var emailTextField: UITextField!
    @IBOutlet var zipcodeTextField: UITextField!
    @IBOutlet var rememberMeSwitch: UISwitch!

    override func viewDidLoad() {
        super.viewDidLoad()
    }

    override func didReceiveMemoryWarning() {
        super.didReceiveMemoryWarning()
    }

    @IBAction func login(_ sender: UIButton) {
        if checkForZipAndEmail {
            performSegue(withIdentifier: "loginSegue", sender: sender)
        } else {
            showErrorMessage()
        }
    }

    private var checkForZipAndEmail: Bool {
        if zipcodeTextField.text?.isEmpty == true && emailTextField.text?.isEmpty == true {
            return false
        }

        let userInfo = NSMutableDictionary()

        // Unwrap textfield value and save it
        if let zip = zipcodeTextField.text {
            userInfo[Klaviyo.sharedInstance.KLPersonZipDictKey] = zip
            zipCode = zip
            if rememberMeSwitch.isOn {
                UserDefaults.standard.set(zip, forKey: "zip")
            }
        }

        // Unwrap email textfield value and save it
        if let email = emailTextField.text {
            if !email.isEmpty && rememberMeSwitch.isOn {
                UserDefaults.standard.set(email, forKey: "email")
            }
            emailAddr = email
            userInfo[Klaviyo.sharedInstance.KLPersonEmailDictKey] = email
            Klaviyo.sharedInstance.setUpUserEmail(userEmail: email)
        }

        // swiftformat:disable:next isEmpty
        if userInfo.count > 0 {
            // EXAMPLE: of tracking event with user properties during app opened
            Klaviyo.sharedInstance.trackEvent(eventName: "Opened klM App", customerProperties: userInfo, properties: nil)
        }

        return true
    }

    private func showErrorMessage() {
        let alertController = UIAlertController(
            title: "Oh No!",
            message: "Please enter a zipcode or email",
            preferredStyle: .alert)
        let okAction = UIAlertAction(
            title: "OK",
            style: .default)

        alertController.addAction(okAction)
        present(alertController, animated: true, completion: nil)
    }

    override func prepare(for segue: UIStoryboardSegue, sender: Any?) {
        guard let vc = segue.destination as? MenuPageViewController
        else {
            return
        }
        vc.menuItems = menuItems
        vc.zip = zipCode
        vc.email = emailAddr
    }
}
