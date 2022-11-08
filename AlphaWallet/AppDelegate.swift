// Copyright © 2022 Stormbird PTE. LTD.

import UIKit

import UniPass_Swift

@UIApplicationMain
class AppDelegate: UIResponder, UIApplicationDelegate {
    private var appCoordinator: AppCoordinator!
    lazy var uniPass = UniPassController(option: UniPassOption(nodeRPC: "https://node.wallet.unipass.id/bsc-testnet",
                                                               env: .testnet,
                                                               domain: "testnet.wallet.unipass.id",
                                                               proto: "https",
                                                               appSetting: AppSetting(appName: "UniPass Swift", appIcon: "", theme: UniPassTheme.dark, chainType: ChainType.bsc)))
    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        do {
            appCoordinator = try AppCoordinator.create()
            appCoordinator.start(launchOptions: launchOptions)
            DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                self.showUniPass()
            }
        } catch {
            //no-op
        }

        return true
    }
    @objc func showUniPass() {
        uniPass.connect(in: UIApplication.shared.keyWindow!.rootViewController!) { account, errMSg in

        }
    }

    func application(_ application: UIApplication, performActionFor shortcutItem: UIApplicationShortcutItem, completionHandler: @escaping (Bool) -> Void) {
        appCoordinator.applicationPerformActionFor(shortcutItem, completionHandler: completionHandler)
    }

    func applicationWillResignActive(_ application: UIApplication) {
        appCoordinator.applicationWillResignActive()
    }

    func applicationDidBecomeActive(_ application: UIApplication) {
        appCoordinator.applicationDidBecomeActive()
    }

    func applicationDidEnterBackground(_ application: UIApplication) {
        appCoordinator.applicationDidEnterBackground()
    }

    func applicationWillEnterForeground(_ application: UIApplication) {
        appCoordinator.applicationWillEnterForeground()
    }

    func application(_ application: UIApplication, shouldAllowExtensionPointIdentifier extensionPointIdentifier: UIApplication.ExtensionPointIdentifier) -> Bool {
        return appCoordinator.applicationShouldAllowExtensionPointIdentifier(extensionPointIdentifier)
    }

    // URI scheme links and AirDrop
    func application(_ app: UIApplication, open url: URL, options: [UIApplication.OpenURLOptionsKey: Any] = [:]) -> Bool {
        return appCoordinator.applicationOpenUrl(url, options: options)
    }

    func application(_ application: UIApplication, continue userActivity: NSUserActivity, restorationHandler: @escaping ([UIUserActivityRestoring]?) -> Void) -> Bool {
        return appCoordinator.applicationContinueUserActivity(userActivity, restorationHandler: restorationHandler)
    }

    func application(_ application: UIApplication, didFailToRegisterForRemoteNotificationsWithError error: Error) {
        //no op
    }
}
