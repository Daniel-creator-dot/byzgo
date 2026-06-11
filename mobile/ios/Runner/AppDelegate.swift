import Flutter
import UIKit
import GoogleMaps
import UserNotifications

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

  @available(iOS 10.0, *)
  override func userNotificationCenter(
    _ center: UNUserNotificationCenter,
    willPresent notification: UNNotification,
    withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
  ) {
    let userInfo = notification.request.content.userInfo
    let type = (userInfo["type"] as? String) ?? ""
    if type == "incoming-ride" {
      if #available(iOS 14.0, *) {
        completionHandler([.banner, .list, .sound, .badge])
      } else {
        completionHandler([.alert, .sound, .badge])
      }
      return
    }
    super.userNotificationCenter(center, willPresent: notification, withCompletionHandler: completionHandler)
  }

  private static func resolveMapsApiKey() -> String? {
    // CI / Xcode scheme / `flutter run` can inject before native Maps init.
    for name in ["GOOGLE_MAPS_API_KEY", "VITE_GOOGLE_MAPS_API_KEY"] {
      if let raw = ProcessInfo.processInfo.environment[name]?.trimmingCharacters(in: .whitespacesAndNewlines),
         raw.count >= 20 {
        return raw
      }
    }
    if let path = Bundle.main.path(forResource: "MapsConfig", ofType: "plist"),
       let dict = NSDictionary(contentsOfFile: path),
       let key = dict["API_KEY"] as? String, !key.isEmpty {
      return key
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
