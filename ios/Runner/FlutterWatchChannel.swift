import Flutter
import Foundation

/// Puente Flutter ↔ Swift. No habla con el Apple Watch.
///
/// MethodChannel: Dart pide enviar un mensaje o leer el status.
/// EventChannel: Swift empuja al Dart mensajes del Watch y cambios de session.
final class FlutterWatchChannel: NSObject {
    // Deben coincidir con WatchService en Dart.
    static let methodChannelName = "com.example.flutter_watch/watch"
    static let messagesChannelName = "com.example.flutter_watch/messages"
    static let statusChannelName = "com.example.flutter_watch/status"

    private let messagesHandler = WatchEventStreamHandler()
    private let statusHandler = WatchEventStreamHandler()

    func register(with messenger: FlutterBinaryMessenger) {
        let methodChannel = FlutterMethodChannel(
            name: Self.methodChannelName,
            binaryMessenger: messenger
        )
        methodChannel.setMethodCallHandler { [weak self] call, result in
            self?.handle(call, result: result)
        }

        FlutterEventChannel(
            name: Self.messagesChannelName,
            binaryMessenger: messenger
        ).setStreamHandler(messagesHandler)

        FlutterEventChannel(
            name: Self.statusChannelName,
            binaryMessenger: messenger
        ).setStreamHandler(statusHandler)

        // Al suscribirse, Dart recibe el status actual en vez de esperar un cambio.
        statusHandler.onListenExtra = {
            WatchConnectivityManager.shared.currentStatus()
        }

        let manager = WatchConnectivityManager.shared
        manager.onMessageReceived = { [weak self] text in
            self?.messagesHandler.sink?(text)
        }
        manager.onStatusChanged = { [weak self] in
            self?.statusHandler.sink?(manager.currentStatus())
        }
    }

    private func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        switch call.method {
        case "sendMessageToWatch":
            sendMessage(call.arguments, result: result)
        case "getWatchStatus":
            result(WatchConnectivityManager.shared.currentStatus())
        case "isWatchReachable":
            result(WatchConnectivityManager.shared.isReachable())
        default:
            result(FlutterMethodNotImplemented)
        }
    }

    private func sendMessage(_ arguments: Any?, result: @escaping FlutterResult) {
        guard
            let payload = arguments as? [String: Any],
            let text = payload["text"] as? String
        else {
            result(
                FlutterError(
                    code: "invalidArguments",
                    message: "Expected a map with a String 'text' key.",
                    details: nil
                )
            )
            return
        }

        WatchConnectivityManager.shared.sendMessage(text) { sendResult in
            switch sendResult {
            case .success:
                result(nil)
            case .failure(let error):
                result(
                    FlutterError(
                        code: error.code,
                        message: error.message,
                        details: nil
                    )
                )
            }
        }
    }
}

/// Mantiene el EventSink entre hot restart (`onListen` / `onCancel`).
private final class WatchEventStreamHandler: NSObject, FlutterStreamHandler {
    var sink: FlutterEventSink?
    var onListenExtra: (() -> Any?)?

    func onListen(withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink) -> FlutterError? {
        sink = events
        if let extra = onListenExtra?() {
            events(extra)
        }
        return nil
    }

    func onCancel(withArguments arguments: Any?) -> FlutterError? {
        sink = nil
        return nil
    }
}
