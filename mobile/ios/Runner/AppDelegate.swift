import Flutter
import UIKit
import GoogleMaps

@main
@objc class AppDelegate: FlutterAppDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    if let path = Bundle.main.path(forResource: "MapsConfig", ofType: "plist"),
       let dict = NSDictionary(contentsOfFile: path),
       let key = dict["API_KEY"] as? String, !key.isEmpty {
      GMSServices.provideAPIKey(key)
    } else if let key = Bundle.main.object(forInfoDictionaryKey: "GMSApiKey") as? String,
              !key.isEmpty {
      GMSServices.provideAPIKey(key)
    }
    GeneratedPluginRegistrant.register(with: self)
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }
}
