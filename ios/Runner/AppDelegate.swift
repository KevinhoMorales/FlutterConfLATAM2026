import Flutter
import UIKit

/// Punto de entrada del proceso iPhone.
///
/// Con iOS 26 la UI vive en UIScene (`FlutterSceneDelegate` en Info.plist).
/// Este AppDelegate solo hace setup de proceso y registra el engine.
@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
    private let watchChannel = FlutterWatchChannel()

    override func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
    ) -> Bool {
        // Activamos WCSession lo antes posible. No depende de la ventana Flutter.
        WatchConnectivityManager.shared.activate()
        return super.application(application, didFinishLaunchingWithOptions: launchOptions)
    }

    /// Flutter ya creó el engine implícito: aquí se registran plugins y channels.
    /// No uses `window?.rootViewController` — con UIScene no está listo aquí.
    func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
        GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
        watchChannel.register(with: engineBridge.applicationRegistrar.messenger())
    }
}
