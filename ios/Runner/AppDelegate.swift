import Flutter
import GoogleMaps
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  private let secureChannelName = "spargo/secure_screen"
  private var secureModeEnabled = false
  private var appIsActive = true
  private var secureOverlayView: UIVisualEffectView?

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    if let apiKey = Bundle.main.object(forInfoDictionaryKey: "GMSApiKey") as? String,
       !apiKey.isEmpty,
       apiKey != "YOUR_GOOGLE_MAPS_API_KEY" {
      GMSServices.provideAPIKey(apiKey)
    }

    NotificationCenter.default.addObserver(
      self,
      selector: #selector(handleScreenshotTaken),
      name: UIApplication.userDidTakeScreenshotNotification,
      object: nil
    )
    NotificationCenter.default.addObserver(
      self,
      selector: #selector(handleCaptureChanged),
      name: UIScreen.capturedDidChangeNotification,
      object: nil
    )
    NotificationCenter.default.addObserver(
      self,
      selector: #selector(handleWillResignActive),
      name: UIApplication.willResignActiveNotification,
      object: nil
    )
    NotificationCenter.default.addObserver(
      self,
      selector: #selector(handleDidBecomeActive),
      name: UIApplication.didBecomeActiveNotification,
      object: nil
    )

    let launched = super.application(application, didFinishLaunchingWithOptions: launchOptions)

    if let controller = window?.rootViewController as? FlutterViewController {
      let channel = FlutterMethodChannel(
        name: secureChannelName,
        binaryMessenger: controller.binaryMessenger
      )
      channel.setMethodCallHandler { [weak self] call, result in
        guard let self else {
          result(nil)
          return
        }

        switch call.method {
        case "enable":
          self.secureModeEnabled = true
          self.refreshSecureOverlay()
          result(nil)
        case "disable":
          self.secureModeEnabled = false
          self.hideSecureOverlay()
          result(nil)
        default:
          result(FlutterMethodNotImplemented)
        }
      }
    }

    return launched
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
  }

  @objc private func handleScreenshotTaken() {
    guard secureModeEnabled else { return }
    showSecureOverlay()
    DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { [weak self] in
      self?.refreshSecureOverlay()
    }
  }

  @objc private func handleCaptureChanged() {
    refreshSecureOverlay()
  }

  @objc private func handleWillResignActive() {
    appIsActive = false
    refreshSecureOverlay()
  }

  @objc private func handleDidBecomeActive() {
    appIsActive = true
    refreshSecureOverlay()
  }

  private func refreshSecureOverlay() {
    guard secureModeEnabled else {
      hideSecureOverlay()
      return
    }

    if !appIsActive || UIScreen.main.isCaptured {
      showSecureOverlay()
    } else {
      hideSecureOverlay()
    }
  }

  private func showSecureOverlay() {
    guard secureOverlayView == nil, let targetView = window else { return }
    let overlay = UIVisualEffectView(effect: UIBlurEffect(style: .systemUltraThinMaterialDark))
    overlay.frame = targetView.bounds
    overlay.autoresizingMask = [.flexibleWidth, .flexibleHeight]
    targetView.addSubview(overlay)
    secureOverlayView = overlay
  }

  private func hideSecureOverlay() {
    secureOverlayView?.removeFromSuperview()
    secureOverlayView = nil
  }
}
