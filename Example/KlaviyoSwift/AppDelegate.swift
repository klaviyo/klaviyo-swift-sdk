//
//  AppDelegate.swift
//  KlaviyoSwift
//
//  Created by Katy Keuper on 10/05/2015.
//  Copyright (c) 2015 Katy Keuper. All rights reserved.
//


import UIKit
import KlaviyoSwift

@UIApplicationMain
class AppDelegate: UIResponder, UIApplicationDelegate {
    
    var window: UIWindow?
    var menuItems : [MenuItem] = [MenuItem]()
    var firstName : String?
    var lastName : String?
    var email : String?
    var zip : String?
    var cartItems : [MenuItem]?
    
    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplicationLaunchOptionsKey: Any]?) -> Bool {
        retrieveSavedData()
        initializeMenuItems()
        
        self.window = UIWindow(frame: UIScreen.main.bounds)
        let mainStoryboard = UIStoryboard(name: "Main", bundle: nil)
        
        
        Klaviyo.setupWithPublicAPIKey(apiKey: "magpcN")
        
        if zip == nil && email == nil {
            // show login page
            let firstVC = mainStoryboard.instantiateViewController(withIdentifier: "loginVC") as! ViewController
            self.window?.rootViewController = firstVC
            self.window?.makeKeyAndVisible()
        } else {
            let menuVC = mainStoryboard.instantiateViewController(withIdentifier: "menuVC") as! MenuPageViewController
            menuVC.email = email
            menuVC.zip = zip
            if let unwrappedEmail = email {
                Klaviyo.sharedInstance.setUpUserEmail(userEmail: unwrappedEmail)
            }
            self.window?.rootViewController = menuVC
            self.window?.makeKeyAndVisible()
        }
        
        // Set up  Klaviyo
        Klaviyo.sharedInstance.trackEvent(eventName: "Opened kLM App")

        // Push Notification for Swift 2.0
        let settings = UIUserNotificationSettings(types: [.alert,.badge,.sound], categories: nil)
        application.registerUserNotificationSettings(settings)
        application.registerForRemoteNotifications()
        
        return true
    }
    
    // Check to see if user is logged in
    func retrieveSavedData() {
        let defaults = UserDefaults.standard
        zip = defaults.object(forKey: "zip") as? String
        firstName = defaults.object(forKey: "firstName") as? String
        lastName = defaults.object(forKey: "lastName") as? String
        email = defaults.object(forKey: "email") as? String
    }
    
    func initializeMenuItems() {
        if menuItems.count == 0 {
            // Initialize the dummy data
            menuItems.append(MenuItem(name: "Fish & Chips", description: "Lightly battered & fried fresh cod and freshly cooked fries", imageURL: "battered_fish.jpg", price: 10.99, id: 1))
            menuItems.append(MenuItem(name: "Nicoise Salad", description: "Delicious salad of mixed greens, tuna nicoise and balasamic vinagrette", imageURL: "nicoise_salad.jpg", price: 12.99, id: 2))
            menuItems.append(MenuItem(name: "Red Pork", description: "Our take on the popular Chinese dish", imageURL: "red_pork.jpg", price: 11.99, id: 3))
            menuItems.append(MenuItem(name: "Beef Bolognese", description: "Traditional Italian Bolognese", imageURL: "bolognese_meal.jpg", price: 10.99, id:4))
        }
    }
    
    
    func applicationWillResignActive(_ application: UIApplication) {
        
    }
    
    /*
    Push Notification implementation
    */
    func application(_ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        // Register APN Key
        Klaviyo.sharedInstance.addPushDeviceToken(deviceToken: deviceToken as Data)
    }
    
    func application(_ application: UIApplication, didReceiveRemoteNotification userInfo: [AnyHashable: Any]) {
        // Handle the notification∫
        // handlepush
        _ = userInfo as NSDictionary // userInfo as NSDictionary
    }
    
    func application(_ application: UIApplication, didFailToRegisterForRemoteNotificationsWithError error: Error) {
        if error._code == 3010 {
            print("push notifications are not supported in the iOS simulator")
        }else {
            print("application:didFailToRegisterForRemoteNotificationsWithError: \(error)")
        }
    }
    
    func applicationDidEnterBackground(_ application: UIApplication) {
        // Use this method to release shared resources, save user data, invalidate timers, and store enough application state information to restore your application to its current state in case it is terminated later.
        // If your application supports background execution, this method is called instead of applicationWillTerminate: when the user quits.
        
    }
    
    func applicationWillEnterForeground(_ application: UIApplication) {
        // Called as part of the transition from the background to the inactive state; here you can undo many of the changes made on entering the background.
        
        // Bring up user's cart status & login info
    }
    
    
    func applicationDidBecomeActive(_ application: UIApplication) {
        // Restart any tasks that were paused (or not yet started) while the application was inactive. If the application was previously in the background, optionally refresh the user interface.
    }
    
    func applicationWillTerminate(_ application: UIApplication) {
        // Called when the application is about to terminate. Save data if appropriate. See also applicationDidEnterBackground:.
        
        // Check status of cart items
        
    }
    
    
}
