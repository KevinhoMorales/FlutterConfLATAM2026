import Foundation
import os
import WatchConnectivity

/// Dueño de `WCSession` en el iPhone.
///
/// Flutter nunca importa WatchConnectivity. Todo el habla con el Watch
/// pasa por esta clase y luego por `FlutterWatchChannel`.
final class WatchConnectivityManager: NSObject {
    static let shared = WatchConnectivityManager()

    /// El Watch mandó un texto. FlutterWatchChannel lo emite por EventChannel.
    var onMessageReceived: ((String) -> Void)?
    /// Cambió pairing / reachability / activación.
    var onStatusChanged: (() -> Void)?

    private let log = Logger(subsystem: "com.example.flutterWatchDemo", category: "WatchConnectivity")
    private var session: WCSession?

    private override init() {
        super.init()
    }

    func activate() {
        guard WCSession.isSupported() else {
            log.warning("WCSession is not supported on this device")
            notifyStatusChanged()
            return
        }

        let session = WCSession.default
        session.delegate = self
        session.activate() // asíncrono → activationDidCompleteWith
        self.session = session
        log.info("WCSession.activate() called")
    }

    /// Snapshot que Dart convierte en `WatchStatus`.
    func currentStatus() -> [String: Any] {
        guard WCSession.isSupported(), let session else {
            return unsupportedStatus()
        }

        // paired / installed / reachable solo son válidos si ya activó.
        let activated = session.activationState == .activated
        return [
            "supported": true,
            "activationState": activationStateName(session.activationState),
            "paired": activated ? session.isPaired : false,
            "watchAppInstalled": activated ? session.isWatchAppInstalled : false,
            "reachable": activated ? session.isReachable : false,
        ]
    }

    func isReachable() -> Bool {
        guard WCSession.isSupported(), let session else {
            return false
        }
        return session.activationState == .activated && session.isReachable
    }

    /// Envía texto al Watch.
    ///
    /// 1. `updateApplicationContext` — no pide reachable (útil en Simulator).
    /// 2. `sendMessage` — inmediato, solo si `isReachable`.
    func sendMessage(_ text: String, completion: @escaping (Result<Void, WatchSendError>) -> Void) {
        guard WCSession.isSupported(), let session else {
            completion(.failure(.unsupported))
            return
        }
        guard session.activationState == .activated else {
            completion(.failure(.notActivated))
            return
        }
        guard session.isPaired else {
            completion(.failure(.notPaired))
            return
        }

        // sentAt hace único el context; si no cambia, Apple no lo reenvía.
        let payload: [String: Any] = [
            "text": text,
            "sentAt": Date().timeIntervalSince1970,
        ]

        do {
            try session.updateApplicationContext(payload)
            log.info("updateApplicationContext sent")
        } catch {
            log.error("updateApplicationContext failed: \(error.localizedDescription, privacy: .public)")
        }

        guard session.isReachable else {
            log.info("Watch not reachable; delivered via application context")
            completion(.success(()))
            return
        }

        session.sendMessage(
            payload,
            replyHandler: { _ in
                DispatchQueue.main.async {
                    completion(.success(()))
                }
            },
            errorHandler: { error in
                self.log.error("sendMessage failed: \(error.localizedDescription, privacy: .public)")
                DispatchQueue.main.async {
                    // El context ya salió; el Watch igual puede mostrar el texto.
                    completion(.success(()))
                }
            }
        )
    }

    private func unsupportedStatus() -> [String: Any] {
        [
            "supported": false,
            "activationState": "notActivated",
            "paired": false,
            "watchAppInstalled": false,
            "reachable": false,
        ]
    }

    private func activationStateName(_ state: WCSessionActivationState) -> String {
        switch state {
        case .notActivated:
            return "notActivated"
        case .inactive:
            return "inactive"
        case .activated:
            return "activated"
        @unknown default:
            return "notActivated"
        }
    }

    private func notifyStatusChanged() {
        // El delegate de WCSession corre en background. Flutter y UI van a main.
        DispatchQueue.main.async { [weak self] in
            self?.onStatusChanged?()
        }
    }

    private func handleIncomingMessage(_ message: [String: Any]) {
        let text = message["text"] as? String ?? String(describing: message)
        log.info("Received from Watch: \(text, privacy: .public)")
        DispatchQueue.main.async { [weak self] in
            self?.onMessageReceived?(text)
        }
    }
}

enum WatchSendError: Error {
    case unsupported
    case notActivated
    case notPaired
    case watchAppNotInstalled
    case notReachable
    case sendFailed(String)

    var code: String {
        switch self {
        case .unsupported:
            return "unsupported"
        case .notActivated:
            return "notActivated"
        case .notPaired:
            return "notPaired"
        case .watchAppNotInstalled:
            return "watchAppNotInstalled"
        case .notReachable:
            return "notReachable"
        case .sendFailed:
            return "sendFailed"
        }
    }

    var message: String {
        switch self {
        case .unsupported:
            return "Watch connectivity is not supported on this device."
        case .notActivated:
            return "The Watch session is not activated."
        case .notPaired:
            return "No Apple Watch is paired with this iPhone."
        case .watchAppNotInstalled:
            return "The Watch app is not installed. Run the WatchApp scheme on the paired Watch simulator."
        case .notReachable:
            return "The Apple Watch is not reachable. Open the Watch app and keep both devices in range."
        case .sendFailed(let details):
            return details
        }
    }
}

extension WatchConnectivityManager: WCSessionDelegate {
    func session(
        _ session: WCSession,
        activationDidCompleteWith activationState: WCSessionActivationState,
        error: Error?
    ) {
        log.info(
            "activation=\(self.activationStateName(activationState), privacy: .public) paired=\(session.isPaired) installed=\(session.isWatchAppInstalled) reachable=\(session.isReachable) error=\(error?.localizedDescription ?? "none", privacy: .public)"
        )
        // Si Flutter envió un context antes de abrir el iPhone, lo mostramos ahora.
        if !session.receivedApplicationContext.isEmpty {
            handleIncomingMessage(session.receivedApplicationContext)
        }
        notifyStatusChanged()
    }

    /// iOS only: el usuario se puso otro Watch.
    func sessionDidBecomeInactive(_ session: WCSession) {
        notifyStatusChanged()
    }

    /// iOS only: hay que reactivar para hablar con el Watch nuevo.
    func sessionDidDeactivate(_ session: WCSession) {
        session.activate()
        notifyStatusChanged()
    }

    func sessionReachabilityDidChange(_ session: WCSession) {
        log.info("reachability=\(session.isReachable)")
        notifyStatusChanged()
    }

    func sessionWatchStateDidChange(_ session: WCSession) {
        log.info("watchState paired=\(session.isPaired) installed=\(session.isWatchAppInstalled)")
        notifyStatusChanged()
    }

    func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String: Any]) {
        handleIncomingMessage(applicationContext)
    }

    func session(_ session: WCSession, didReceiveMessage message: [String: Any]) {
        handleIncomingMessage(message)
    }

    func session(
        _ session: WCSession,
        didReceiveMessage message: [String: Any],
        replyHandler: @escaping ([String: Any]) -> Void
    ) {
        handleIncomingMessage(message)
        replyHandler(["status": "ok"])
    }
}
