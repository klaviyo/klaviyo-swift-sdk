//
//  ViewController.swift
//  KlaviyoSwift
//
//  Created by Katherine Keuper on 10/5/15.
//  Copyright © 2015 CocoaPods. All rights reserved.
//


import UIKit
import KlaviyoSwift

class ViewController: UIViewController {
    
    var menuItems : [MenuItem] = [MenuItem]()
    @IBOutlet weak var zipcodeTextField: UITextField!
    var zipCode : String?
    @IBOutlet weak var emailTextField: UITextField!
    var emailAddr: String?
    var firstName :  String?
    var lastName : String?
    var cartItems : [MenuItem]?
    @IBOutlet weak var rememberMeSwitch: UISwitch!
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
    }
    
    override func didReceiveMemoryWarning() {
        super.didReceiveMemoryWarning()
    }
    
    @IBAction func login(sender: UIButton) {
        if checkForZipAndEmail() {
            performSegueWithIdentifier("loginSegue", sender: sender)
        } else {
            showErrorMessage()
        }
    }
    
    
    func checkForZipAndEmail()->Bool {
        
        if zipcodeTextField.text?.characters.count == 0 && emailTextField.text?.characters.count == 0 {
            return false
        }
        
        let userInfo: NSMutableDictionary = NSMutableDictionary()
        
        //Unwrap textfield value and save it
        if let zip = zipcodeTextField.text {
            userInfo[Klaviyo.sharedInstance.KLPersonZipDictKey] = zip
            zipCode = zip
            if rememberMeSwitch.on == true {
                NSUserDefaults.standardUserDefaults().setObject(zip, forKey: "zip")
            }
        }
        
        //Unwrap email textfield value and save it
        if let email = emailTextField.text {
            if email.characters.count > 0 && rememberMeSwitch.on == true {
                NSUserDefaults.standardUserDefaults().setObject(email, forKey: "email")
            }
            emailAddr = email
            userInfo[Klaviyo.sharedInstance.KLPersonEmailDictKey] = email
            Klaviyo.sharedInstance.setUpUserEmail(email)
            Klaviyo.sharedInstance.trackEvent("Opened klM App")
        }
        
        return true
    }
    
    func showErrorMessage() {
        let alertController = UIAlertController(title: "Oh No!", message: "Please enter a zipcode or email", preferredStyle: UIAlertControllerStyle.Alert)
        let okAction = UIAlertAction(title: "OK", style: .Default, handler:nil)
        
        alertController.addAction(okAction)
        self.presentViewController(alertController, animated: true, completion: nil)
    }
    
    override func prepareForSegue(segue: UIStoryboardSegue, sender: AnyObject?) {
        //track event open
        let vc = segue.destinationViewController as! MenuPageViewController
        vc.menuItems = menuItems
        vc.zip = zipCode
        vc.email = emailAddr
        
    }
}

