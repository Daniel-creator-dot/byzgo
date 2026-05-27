import Flutter
import UIKit
import GoogleMaps

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
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
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
