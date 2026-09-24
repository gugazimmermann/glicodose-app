import Flutter
import UIKit
import flutter_foreground_task
import home_widget

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    SwiftFlutterForegroundTaskPlugin.setPluginRegistrantCallback { registry in
      GeneratedPluginRegistrant.register(with: registry)
    }
    if #available(iOS 17, *) {
      HomeWidgetBackgroundWorker.setPluginRegistrantCallback { registry in
        GeneratedPluginRegistrant.register(with: registry)
      }
    }
    if #available(iOS 10.0, *) {
      UNUserNotificationCenter.current().delegate = self as? UNUserNotificationCenterDelegate
    }
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    let channel = FlutterMethodChannel(
      name: "app.glicodose/theme",
      binaryMessenger: engineBridge.applicationRegistrar.messenger()
    )
    channel.setMethodCallHandler { [weak self] call, result in
      guard call.method == "setThemeMode" else {
        result(FlutterMethodNotImplemented)
        return
      }
      let mode = call.arguments as? String ?? "system"
      self?.applyInterfaceStyle(mode)
      result(nil)
    }
  }

  private func applyInterfaceStyle(_ mode: String) {
    let style: UIUserInterfaceStyle
    switch mode {
    case "light":
      style = .light
    case "dark":
      style = .dark
    default:
      style = .unspecified
    }
    DispatchQueue.main.async {
      for scene in UIApplication.shared.connectedScenes {
        guard let windowScene = scene as? UIWindowScene else { continue }
        for window in windowScene.windows {
          window.overrideUserInterfaceStyle = style
        }
      }
    }
  }
}
