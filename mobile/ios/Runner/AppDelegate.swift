import Flutter
import UIKit
import GoogleMaps
import UserNotifications
import flutter_callkit_incoming

@main
@objc class AppDelegate: FlutterAppDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    if let mapsKey = Self.resolveMapsApiKey(), !mapsKey.isEmpty {
      GMSServices.provideAPIKey(mapsKey)
    }
    GeneratedPluginRegistrant.register(with: self)
    if #available(iOS 10.0, *) {
      UNUserNotificationCenter.current().delegate = self
      let incomingRide = UNNotificationCategory(
        identifier: "incoming_ride_offer",
        actions: [],
        intentIdentifiers: [],
        hiddenPreviewsBodyPlaceholder: "Incoming delivery job",
        options: [.customDismissAction]
      )
      UNUserNotificationCenter.current().setNotificationCategories([incomingRide])
    }
    application.registerForRemoteNotifications()
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  override func application(
    _ application: UIApplication,
    didReceiveRemoteNotification userInfo: [AnyHashable: Any],
    fetchCompletionHandler completionHandler: @escaping (UIBackgroundFetchResult) -> Void
  ) {
    if Self.isIncomingRide(userInfo) {
      Self.showIncomingRideCallKit(userInfo: userInfo) {
        completionHandler(.newData)
      }
      return
    }
    super.application(
      application,
      didReceiveRemoteNotification: userInfo,
      fetchCompletionHandler: completionHandler
    )
  }

  @available(iOS 10.0, *)
  override func userNotificationCenter(
    _ center: UNUserNotificationCenter,
    willPresent notification: UNNotification,
    withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
  ) {
    let userInfo = notification.request.content.userInfo
    if Self.isIncomingRide(userInfo) {
      Self.showIncomingRideCallKit(userInfo: userInfo)
      completionHandler([])
      return
    }
    super.userNotificationCenter(center, willPresent: notification, withCompletionHandler: completionHandler)
  }

  private static func isIncomingRide(_ userInfo: [AnyHashable: Any]) -> Bool {
    (userInfo["type"] as? String) == "incoming-ride"
  }

  private static func showIncomingRideCallKit(
    userInfo: [AnyHashable: Any],
    completion: (() -> Void)? = nil
  ) {
    let orderId = (userInfo["orderId"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
    let id = (orderId?.isEmpty == false) ? orderId! : UUID().uuidString
    let pickup = (userInfo["pickup"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
    let drop = (userInfo["address"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
    let pickupLabel = (pickup?.isEmpty == false) ? pickup! : "Pickup"
    let dropLabel = (drop?.isEmpty == false) ? drop! : "Drop-off"

    var extra: [String: Any] = [:]
    for key in [
      "type", "orderId", "expiresAt", "status", "pickup", "address",
      "orderType", "title", "body", "audience",
    ] {
      if let value = userInfo[key] {
        extra[key] = value
      }
    }
    extra["type"] = "incoming-ride"
    extra["orderId"] = id

    let data = flutter_callkit_incoming.Data(
      id: id,
      nameCaller: "Incoming delivery job",
      handle: "\(pickupLabel) → \(dropLabel)",
      type: 0
    )
    data.appName = "BytzGo"
    data.duration = 30000
    data.extra = extra as NSDictionary

    SwiftFlutterCallkitIncomingPlugin.sharedInstance?.showCallkitIncoming(data, fromPushKit: false) {
      completion?()
    }
  }

  private static func resolveMapsApiKey() -> String? {
    for name in ["GOOGLE_MAPS_API_KEY", "VITE_GOOGLE_MAPS_API_KEY"] {
      if let raw = ProcessInfo.processInfo.environment[name]?.trimmingCharacters(in: .whitespacesAndNewlines),
         raw.count >= 20 {
        return raw
      }
    }
    if let path = Bundle.main.path(forResource: "MapsConfig", ofType: "plist"),
       let dict = NSDictionary(contentsOfFile: path) {
      if let key = dict["GOOGLE_MAPS_API_KEY"] as? String, !key.isEmpty { return key }
      if let key = dict["API_KEY"] as? String, !key.isEmpty { return key }
    }
    if let key = Bundle.main.object(forInfoDictionaryKey: "GMSApiKey") as? String,
       !key.isEmpty {
      return key
    }
    if let path = Bundle.main.path(forResource: "GoogleService-Info", ofType: "plist"),
       let dict = NSDictionary(contentsOfFile: path),
       let key = dict["API_KEY"] as? String, !key.isEmpty {
      return key
    }
    return nil
  }
}
