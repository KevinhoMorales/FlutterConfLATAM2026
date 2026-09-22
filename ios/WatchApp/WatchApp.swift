import SwiftUI

/// `@main` del Apple Watch. Cero Flutter: este proceso es solo SwiftUI.
@main
struct WatchApp: App {
    // Al crear el singleton se activa WCSession en el Watch.
    @StateObject private var connectivity = WatchConnectivityManager.shared

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(connectivity)
        }
    }
}
