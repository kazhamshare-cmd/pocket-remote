import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    GeneratedPluginRegistrant.register(with: self)

    // Register H.264 decoder plugin
    let controller = window?.rootViewController as! FlutterViewController
    H264DecoderPlugin.register(
      with: self.registrar(forPlugin: "H264DecoderPlugin")!
    )

    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }
}
