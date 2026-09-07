import UIKit
import Flutter
import GoogleMaps

@UIApplicationMain
@objc class AppDelegate: FlutterAppDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    // iOS-specific Google Maps key (Maps SDK for iOS, restricted to this
    // bundle id). Android uses its own key in AndroidManifest.xml.
    GMSServices.provideAPIKey("AIzaSyCRL34adUBSuk-nj4qdonmuqyyV4OW1pHc")
    GeneratedPluginRegistrant.register(with: self)
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }
}
