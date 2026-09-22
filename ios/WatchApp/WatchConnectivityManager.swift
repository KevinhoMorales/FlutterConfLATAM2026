import Combine
import Foundation
import os
import WatchConnectivity

/// Dueño de `WCSession` en el Watch.
///
/// Otro proceso, mismo protocolo. Flutter no corre aquí.
/// Es `ObservableObject` para que SwiftUI se redibuje solo.
final class WatchConnectivityManager: NSObject, ObservableObject {
    static let shared = WatchConnectivityManager()

    @Published var lastMessage: String = ""
    @Published var isReachable: Bool = false
    @Published var activationState: WCSessionActivationState = .notActivated
    @Published var sendError: String?
    @Published var companionInstalled: Bool = false

    var connectionLabel: String {
        if activationState != .activated {
            return "Session not activated"
        }
        if isReachable {
            return "Connected to iPhone"
        }
        if companionInstalled {
            return "iPhone installed, not reachable"
        }
        return "Waiting for iPhone…"
    }

    private let log = Logger(subsystem: "com.example.flutterWatchDemo.watchkitapp", category: "WatchConnectivity")

    private override init() {
        super.init()
        activate()
    }

    func activate() {
        guard WCSession.isSupported() else {
            return
        }
        let session = WCSession.default
        session.delegate = self
        session.activate()
    }

    /// Watch → WCSession → iPhone Swift → EventChannel → Flutter.
    func sendToiPhone(_ text: String = "Message received from Apple Watch") {
        sendError = nil

        let session = WCSession.default
        guard session.activationState == .activated else {
            sendError = "Session not activated"
            return
        }

        let payload: [String: Any] = [
            "text": text,
            "sentAt": Date().timeIntervalSince1970,
        ]

        do {
            try session.updateApplicationContext(payload)
            log.info("updateApplicationContext sent to iPhone")
        } catch {
            log.error("updateApplicationContext failed: \(error.localizedDescription, privacy: .public)")
        }

        guard session.isReachable else {
            log.info("iPhone not reachable; delivered via application context")
            return
        }

        session.sendMessage(
            payload,
            replyHandler: { _ in
                DispatchQueue.main.async {
                    self.sendError = nil
                }
            },
            errorHandler: { error in
                DispatchQueue.main.async {
                    self.sendError = error.localizedDescription
                }
            }
        )
    }

    private func applySessionState(_ session: WCSession) {
        activationState = session.activationState
        isReachable = session.isReachable
        // En watchOS no existe isPaired; el equivalente es isCompanionAppInstalled.
        companionInstalled = session.isCompanionAppInstalled
    }

    private func handleIncomingMessage(_ message: [String: Any]) {
        let text = message["text"] as? String ?? String(describing: message)
        log.info("Received from iPhone: \(text, privacy: .public)")
        DispatchQueue.main.async { [weak self] in
            self?.lastMessage = text
            self?.sendError = nil
        }
    }
}

extension WatchConnectivityManager: WCSessionDelegate {
    func session(
        _ session: WCSession,
        activationDidCompleteWith activationState: WCSessionActivationState,
        error: Error?
    ) {
        DispatchQueue.main.async { [weak self] in
            self?.applySessionState(session)
            if let error {
                self?.sendError = error.localizedDescription
            }
        }
        // Mensaje que Flutter mandó mientras el Watch estaba cerrado.
        if !session.receivedApplicationContext.isEmpty {
            handleIncomingMessage(session.receivedApplicationContext)
        }
    }

    func sessionReachabilityDidChange(_ session: WCSession) {
        DispatchQueue.main.async { [weak self] in
            self?.applySessionState(session)
        }
    }

    func sessionCompanionAppInstalledDidChange(_ session: WCSession) {
        DispatchQueue.main.async { [weak self] in
            self?.applySessionState(session)
        }
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
