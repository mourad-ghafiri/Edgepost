import Flutter
import UIKit
import UserNotifications
import workmanager_apple

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    // Background new-mail checks: plugins for the background engine, and the
    // launch handler BGTaskScheduler requires before didFinishLaunching returns
    // under the UIScene lifecycle.
    WorkmanagerPlugin.setPluginRegistrantCallback { registry in
      GeneratedPluginRegistrant.register(with: registry)
    }
    WorkmanagerPlugin.registerPeriodicTask(
      withIdentifier: "com.mouradghafiri.edgepost.mailsync",
      earliestBeginInSeconds: NSNumber(value: 15 * 60)
    )
    WorkmanagerPlugin.registerLaunchHandlers()
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)

    // App icon badge = unread mail. flutter_local_notifications can only set
    // a badge while showing a notification, so the count is set directly.
    guard let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "EdgepostBadge") else { return }
    let channel = FlutterMethodChannel(name: "edgepost/badge", binaryMessenger: registrar.messenger())
    channel.setMethodCallHandler { call, result in
      guard call.method == "set", let count = call.arguments as? Int else {
        result(FlutterMethodNotImplemented)
        return
      }
      if #available(iOS 16.0, *) {
        UNUserNotificationCenter.current().setBadgeCount(max(0, count)) { _ in result(nil) }
      } else {
        UIApplication.shared.applicationIconBadgeNumber = max(0, count)
        result(nil)
      }
    }
  }
}
