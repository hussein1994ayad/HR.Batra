import Flutter
import UIKit
import UserNotifications

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {

  private let iosLocationChannel = "com.batra.hrpro/ios_location"

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {

    UNUserNotificationCenter.current().delegate = self
    UNUserNotificationCenter.current().requestAuthorization(
      options: [.alert, .badge, .sound, .provisional, .criticalAlert]
    ) { granted, _ in
      if granted {
        DispatchQueue.main.async { application.registerForRemoteNotifications() }
      }
    }
    application.registerForRemoteNotifications()

    if let controller = window?.rootViewController as? FlutterViewController {
      setupIOSLocationChannel(controller: controller)
    }

    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  private func setupIOSLocationChannel(controller: FlutterViewController) {
    let channel = FlutterMethodChannel(
      name: iosLocationChannel,
      binaryMessenger: controller.binaryMessenger
    )
    channel.setMethodCallHandler { call, result in
      switch call.method {
      case "configure":
        guard let args = call.arguments as? [String: Any],
              let url = args["supabaseUrl"] as? String,
              let anon = args["supabaseAnonKey"] as? String,
              let employeeId = args["employeeId"] as? String
        else {
          result(FlutterError(code: "BAD_ARGS", message: "configure needs args", details: nil))
          return
        }
        let token = (args["accessToken"] as? String) ?? anon
        LocationMonitorIOS.shared.configure(
          supabaseUrl: url,
          supabaseAnonKey: anon,
          employeeId: employeeId,
          accessToken: token
        )
        result(true)

      case "startMonitoring":
        guard let args = call.arguments as? [String: Any],
              let branches = args["branches"] as? [[String: Any]]
        else {
          result(FlutterError(code: "BAD_ARGS", message: "startMonitoring needs branches", details: nil))
          return
        }
        LocationMonitorIOS.shared.startMonitoring(branches: branches)
        result(true)

      case "setCheckedIn":
        guard let args = call.arguments as? [String: Any],
              let value = args["value"] as? Bool
        else {
          result(FlutterError(code: "BAD_ARGS", message: "setCheckedIn needs value", details: nil))
          return
        }
        LocationMonitorIOS.shared.setCheckedIn(value)
        result(true)

      case "stopMonitoring":
        LocationMonitorIOS.shared.stopMonitoring()
        result(true)

      default:
        result(FlutterMethodNotImplemented)
      }
    }
  }

  override func application(
    _ application: UIApplication,
    didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data
  ) {
    super.application(application, didRegisterForRemoteNotificationsWithDeviceToken: deviceToken)
  }

  override func application(
    _ application: UIApplication,
    didFailToRegisterForRemoteNotificationsWithError error: Error
  ) {
    NSLog("APNs registration failed: \(error.localizedDescription)")
    super.application(application, didFailToRegisterForRemoteNotificationsWithError: error)
  }

  override func userNotificationCenter(
    _ center: UNUserNotificationCenter,
    willPresent notification: UNNotification,
    withCompletionHandler completionHandler:
      @escaping (UNNotificationPresentationOptions) -> Void
  ) {
    if #available(iOS 14.0, *) {
      completionHandler([.banner, .list, .badge, .sound])
    } else {
      completionHandler([.alert, .badge, .sound])
    }
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
  }
}
