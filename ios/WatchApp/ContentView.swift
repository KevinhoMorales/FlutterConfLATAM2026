import SwiftUI

/// Única pantalla del Watch: estado, último mensaje y botón de respuesta.
struct ContentView: View {
    @EnvironmentObject private var connectivity: WatchConnectivityManager

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Text("Flutter ↔ Apple Watch")
                    .font(.headline)
                    .fixedSize(horizontal: false, vertical: true)

                Label(connectivity.connectionLabel, systemImage: "applewatch")
                    .font(.caption)
                    .foregroundStyle(connectivity.isReachable ? .green : .orange)

                VStack(alignment: .leading, spacing: 4) {
                    Text("Message:")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(
                        connectivity.lastMessage.isEmpty
                            ? "Waiting for Flutter…"
                            : "\"\(connectivity.lastMessage)\""
                    )
                    .font(.body)
                    .fixedSize(horizontal: false, vertical: true)
                }

                if let error = connectivity.sendError {
                    Text(error)
                        .font(.caption2)
                        .foregroundStyle(.red)
                }

                // No exigimos isReachable: updateApplicationContext igual puede salir.
                Button("Send to iPhone") {
                    connectivity.sendToiPhone()
                }
                .disabled(connectivity.activationState != .activated)
            }
            .padding(.horizontal, 8)
        }
    }
}

#Preview {
    ContentView()
        .environmentObject(WatchConnectivityManager.shared)
}
